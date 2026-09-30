-- Waypoints: one destination at a time, shown as a floating pin with the distance, a glowing
-- guide line from your dragon, and a pin on the minimap and the full map.
--   * By default it follows your current quest (where to go, then back to the quest giver).
--   * Picking a place on the map (or a quest to track) overrides that.
--   * Places you pick clear themselves when you arrive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Dungeons = require(Shared.Config.Dungeons)
local Zones = require(Shared.Config.Zones)
local Signal = require(Shared.Signal)

local Waypoint = {}
local App

local player = Players.LocalPlayer
local current = nil -- { pos, label, source ("quest" | "place"), questId? }
local trackedQuest = nil -- quest id the player chose to follow (nil = the first active quest)
local suppressed = false -- the tutorial draws its own guide
local marker, markerLabel, anchor, beam, beamStart
local ARRIVE_DISTANCE = 30

Waypoint.changed = Signal.new()

---------------------------------------------------------------- where quests happen

local CAMP_FOR = { Raider = "RaiderCamp", AxeThrower = "FishingVillage", Shieldbearer = "LonghouseHold", Berserker = "LonghouseHold", Chieftain = "JarlsFortress", Hornblower = "JarlsFortress" }
local SHOP_FOR = { buy = "Armory", sell = "Exchange", upgrade = "Forge", potion = "Alchemist", hatch = "Hatchery" }

local function campForLevel(level: number)
	local best = Zones.Camps[1]
	for _, camp in ipairs(Zones.Camps) do
		if level >= camp.levels[1] then
			best = camp
		end
	end
	return best
end

local function huntingForLevel(level: number)
	local best = Zones.HuntingGrounds[1]
	for _, area in ipairs(Zones.HuntingGrounds) do
		if level >= area.levels[1] then
			best = area
		end
	end
	return best
end

function Waypoint.homePosition(): Vector3?
	local p = App.State.profile
	local bases = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Bases")
	local base = p and p.baseIndex and bases and bases:FindFirstChild("Base" .. p.baseIndex)
	local home = base and base:FindFirstChild("HomeSpawn")
	return home and home.Position
end

local function nearestFishingSpot(from: Vector3): Vector3
	local best, bestD = Zones.FishingSpots[1].pos, math.huge
	for _, spot in ipairs(Zones.FishingSpots) do
		local d = (spot.pos - from).Magnitude
		if d < bestD then
			best, bestD = spot.pos, d
		end
	end
	return best
end

-- Where a quest giver stands: a dungeon keeper also stands inside its dungeon, so while you're in
-- that dungeon it's the one by the entrance in there.
local function giverPosition(giverId: string): Vector3
	local giver = Quests.Givers[giverId]
	local run = App.State.dungeon and App.State.dungeon.run
	if giver.dungeon and run and run.dungeonId == giver.dungeon and run.origin then
		return run.origin + Dungeons.get(giver.dungeon).keeper.at
	end
	return Zones.QuestGivers[giverId].position
end

-- Where to go for a quest right now: returns position, label (or nil if it can be done anywhere).
function Waypoint.questTarget(questId: string)
	local p = App.State.profile
	local quest = Quests.byId[questId]
	local progress = p and p.quests.active[questId]
	if not quest or progress == nil then
		return nil
	end
	local giver = Quests.Givers[quest.giver]
	if progress >= quest.objective.count then
		return giverPosition(quest.giver), "Return to " .. giver.name
	end
	local o = quest.objective
	local level = p.level
	local character = player.Character
	local here = character and character:GetPivot().Position or Zones.SPAWN
	if o.type == "kill" then
		local camp = Zones.getCamp(CAMP_FOR[o.target] or "") or campForLevel(level)
		return camp.center, camp.name
	elseif o.type == "miniBoss" or o.type == "openChest" then
		local camp = campForLevel(level)
		return camp.center, camp.name
	elseif o.type == "hunt" then
		local area = huntingForLevel(level)
		local zone = Zones.getArea(area.id)
		return (area.min + area.max) / 2, zone and zone.name or area.id
	elseif o.type == "fish" then
		return nearestFishingSpot(here), "Fishing spot"
	elseif o.type == "plant" or o.type == "care" or o.type == "harvest" then
		return Waypoint.homePosition(), "Your lair"
	elseif SHOP_FOR[o.type] then
		local shop = Zones.getShop(SHOP_FOR[o.type])
		return shop.position, shop.name
	elseif o.type == "pvpKill" then
		local bz = Zones.getArea("BattleZone")
		return (bz.min + bz.max) / 2, bz.name
	elseif o.type == "visitZone" then
		local area = Zones.getArea(o.target)
		if area then
			if area.shape == "box" then
				return (area.min + area.max) / 2, area.name
			end
			return area.center, area.name
		end
	elseif o.type == "bossJoin" or o.type == "bossKill" then
		return Zones.WarHorn, "War Horn"
	elseif o.type == "dungeonClear" or o.type == "dungeonKill" then
		-- the cave's mouth (nothing to point at once you're inside)
		local dungeon = Dungeons.get(o.target)
		if dungeon and player:GetAttribute("InDungeon") ~= dungeon.id then
			return dungeon.entrance, dungeon.name
		end
	end
	return nil
end

-- Active quests in log order.
local function activeQuests()
	local p = App.State.profile
	local list = {}
	for questId in pairs(p and p.quests.active or {}) do
		if Quests.byId[questId] then
			table.insert(list, Quests.byId[questId])
		end
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

---------------------------------------------------------------- setting it

local function apply(new)
	local same = current and new and current.pos == new.pos and current.label == new.label
	current = new
	if not same then
		Waypoint.changed:Fire(current)
	end
end

function Waypoint.get()
	return current
end

-- Go somewhere specific (a map click or a place in the map's list).
function Waypoint.setPlace(pos: Vector3, label: string)
	trackedQuest = false -- stop following quests until the player picks one again
	apply({ pos = pos, label = label, source = "place" })
end

-- Follow a quest (nil = follow whatever quest comes first).
function Waypoint.trackQuest(questId: string?)
	trackedQuest = questId
	Waypoint.refreshQuest()
end

function Waypoint.clear()
	trackedQuest = false
	apply(nil)
end

-- Recompute the quest waypoint (called whenever the profile changes).
function Waypoint.refreshQuest()
	if not App.State.profile then
		return
	end
	if current and current.source == "place" then
		return
	end
	if trackedQuest == false then
		return
	end
	local ids = {}
	if trackedQuest and App.State.profile.quests.active[trackedQuest] ~= nil then
		table.insert(ids, trackedQuest)
	end
	for _, q in ipairs(activeQuests()) do
		table.insert(ids, q.id)
	end
	for _, id in ipairs(ids) do
		local pos, label = Waypoint.questTarget(id)
		if pos then
			apply({ pos = pos, label = label, source = "quest", questId = id })
			return
		end
	end
	apply(nil)
end

function Waypoint.trackedQuestId(): string?
	return current and current.source == "quest" and current.questId or nil
end

function Waypoint.setSuppressed(on: boolean)
	suppressed = on
end

---------------------------------------------------------------- drawing

function Waypoint.init(app)
	App = app
	anchor = Instance.new("Attachment")
	anchor.Name = "WaypointTarget"
	anchor.Parent = workspace.Terrain
	marker = Instance.new("BillboardGui")
	marker.Name = "WaypointMarker"
	marker.ResetOnSpawn = false -- lives in PlayerGui: keep it when the dragon respawns
	marker.Adornee = anchor
	marker.Size = UDim2.fromOffset(180, 64)
	marker.StudsOffset = Vector3.new(0, 14, 0)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	markerLabel = Instance.new("TextLabel")
	markerLabel.BackgroundTransparency = 1
	markerLabel.Size = UDim2.fromScale(1, 1)
	markerLabel.Font = Enum.Font.FredokaOne
	markerLabel.TextSize = 20
	markerLabel.TextColor3 = Color3.fromRGB(255, 120, 110)
	markerLabel.TextStrokeTransparency = 0.2
	markerLabel.Parent = marker
	marker.Parent = player:WaitForChild("PlayerGui")
	beam = Instance.new("Beam")
	beam.Name = "WaypointBeam"
	beam.Attachment1 = anchor
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 110, 100))
	beam.Transparency = NumberSequence.new(0.45)
	beam.LightEmission = 1
	beam.Enabled = false
	beam.Parent = workspace.Terrain

	App.State.changed:Connect(Waypoint.refreshQuest)

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not current or not root then
			marker.Enabled = false
			beam.Enabled = false
			return
		end
		local flat = Vector3.new(current.pos.X - root.Position.X, 0, current.pos.Z - root.Position.Z).Magnitude
		if current.source == "place" and flat < ARRIVE_DISTANCE then
			App.Notifications.toast("You've arrived at " .. current.label .. "!", Color3.fromRGB(140, 230, 120), "📍")
			trackedQuest = nil -- go back to following quests
			apply(nil)
			Waypoint.refreshQuest()
			return
		end
		anchor.WorldPosition = current.pos
		markerLabel.Text = string.format("📍 %s\n%d studs", current.label, math.floor(flat))
		marker.Enabled = flat > 12
		if not beamStart or beamStart.Parent ~= root then
			beamStart = Instance.new("Attachment")
			beamStart.Name = "WaypointBeamStart"
			beamStart.Parent = root
		end
		beam.Attachment0 = beamStart
		beam.Enabled = not suppressed and flat > 40
	end)
end

return Waypoint
