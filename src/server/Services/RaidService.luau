-- Night raids on Dragon Town (Config/Raids). At nightfall DayNightService fires `nightfall` and
-- there's a Raids.CHANCE of a raid (always one after Raids.PITY_NIGHTS quiet nights in a row).
--
-- A raid: the war horn sounds and longships row down the river (Raids.WARNING) with the first
-- wave standing on deck, then the vikings leap ashore below town one after another. The vikings
-- on deck are already real raiders (EnemyService, welded to the keel and cheering, with no AI yet),
-- so dragons can fly out and fight them on the way in: one beaten on deck tumbles overboard. The
-- size of the raid follows the strongest dragon online (Raids.Tiers), so new players get a gentler
-- one. Raiders are ordinary vikings flagged `raid` (so they can fight inside town) with an
-- `objective` (see "raider brains"): Torchbearers walk the villagers' street graph
-- (Zones.TownWalk, via CivilianService) to a house door and set it alight; the rest go after
-- villagers (knocking them out for a while) and dragons all over town, even at home in their
-- lairs. Villagers come out and puff fire at them (CivilianService), and the quest givers breathe
-- fire at any raider that comes near their posts (and won't talk quests until it's over). Their
-- fire can't finish a raider fresh off the boat, but that wears off the longer it's ashore, and
-- it all hits harder when only one or two dragons are online (Raids.villagerHelp).
--
-- A raid never starts while a world boss is on its way or being fought: it waits for the boss
-- (BossService likewise waits for a raid to finish before sounding its warning).
--
-- Fire: a burning house burns down after the tier's burnTime unless a dragon drops water on it.
-- Dragons scoop water by skimming low over the river or a lake, or dipping into a town well, and
-- carry Raids.WATER_LOADS splashes (player attribute "Water"); flying over a burning house drops
-- one. A house that burns down flares up, blackens, caves in and smolders (see "houses").
--
-- The raid keeps its own clock (Raids.FIGHT_TIME after the last wave lands), so dawn doesn't cut
-- it short. Beat every raider to win: everyone who hit a raider or put out a fire gets the
-- rewards. Lose (time's up, or Raids.MAX_BURNED houses gone) and the raiders still standing run
-- back to their longships with sacks of loot and row away, and ShopService closes every vendor
-- for a while. Burned houses are rebuilt Raids.REBUILD seconds after the raid either way.
--
-- Clients follow along through workspace attributes (UI/RaidUI): RaidPhase ("incoming" /
-- "fighting"), RaidLandsAt, RaidEndsAt, RaidLeft, RaidWave, RaidWaves, HousesBurned,
-- RaidMaxBurned. Each house model carries Fire ("burning" / "burned") and BurnsAt.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Raids = require(Shared.Config.Raids)
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Quests = require(Shared.Config.Quests)

local Props = require(script.Parent.Parent.World.Props)

local RaidService = {}
local S

local raid = nil -- the raid in progress (see RaidService.start)
local raidCounter = 0
local quietNights = 0
local pendingRaid = false -- rolled a raid while a boss was busy: it starts once the boss is done
local houses = {} -- [index] = { model, state = "ok" | "burning" | "burned", burnsAt, fx, fires, lights, original, rebuildAt, baseY }
local wells = {} -- { ground = Vector3, tag = BillboardGui }
local rowing = {} -- [ship] = the trip it's on (a newer trip replaces it)
local shipFolder: Folder
local enemyFolder: Instance?
local riverSamples = {}
local terrainParams = RaycastParams.new()

local endRaid: (won: boolean, reason: string?) -> () -- below; burning a house down can end the raid
local giversFight: (r: any) -> () -- below; the quest givers fight once the raiders land
local runBack: (r: any, e: any) -> () -- below; a lost raid's raiders run back to their ships

local STREET_GOALS = { "PN", "PNE", "PE", "PSE", "PS", "PSW", "PW", "PNW", "N1", "N2", "N3", "E1", "E2", "W1", "S1" }
local CHAR = Color3.fromRGB(38, 32, 30)
local SHIP_SIDE = 9 -- a landed longship sits this far from the middle of the river, toward town
local SHIP_KEEL = CFrame.new(0, -2.4, 0) -- where Props.longship puts the keel (the ship's PrimaryPart)
local WATER_COLOR = Color3.fromRGB(140, 200, 255)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function broadcast(title: string, text: string, color: Color3, duration: number?)
	Remotes.event("Announce"):FireAllClients({ title = title, text = text, color = color, duration = duration or 6, sound = "horn" })
end

local function notifyAll(text: string, color: Color3, icon: string)
	for _, player in ipairs(Players:GetPlayers()) do
		S.PlayerService.notify(player, text, color, icon)
	end
end

-- Dragons who could defend the town (in the game with a dragon chosen).
local function defenders(): { Player }
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = S.PlayerService.getProfile(player)
		if profile and profile.class then
			table.insert(list, player)
		end
	end
	return list
end

local function setAttributes()
	local r = raid
	workspace:SetAttribute("RaidPhase", r and r.phase or nil)
	workspace:SetAttribute("RaidLandsAt", r and r.landsAt or nil)
	workspace:SetAttribute("RaidEndsAt", r and r.endsAt or nil)
	workspace:SetAttribute("RaidLeft", r and r.left or nil)
	workspace:SetAttribute("RaidWave", r and r.wave or nil)
	workspace:SetAttribute("RaidWaves", r and #r.tier.waves or nil)
	workspace:SetAttribute("RaidNextWaveAt", r and r.nextWaveAt or nil)
	workspace:SetAttribute("HousesBurned", r and r.burned or nil)
	workspace:SetAttribute("RaidMaxBurned", Raids.MAX_BURNED)
end

---------------------------------------------------------------- houses

local function houseCF(index: number): CFrame
	local house = Zones.Houses[index]
	return CFrame.lookAt(house.pos, house.pos + house.facing)
end

local function roofTop(index: number): Vector3
	return Vector3.new(Zones.Houses[index].pos.X, houses[index].baseY + Zones.HouseSize.Y + 4, Zones.Houses[index].pos.Z)
end

local function clearFx(h)
	if h.fx then
		h.fx:Destroy()
	end
	h.fx = nil
	h.fires = nil
	h.lights = nil
	h.smokes = nil
	h.tag = nil
	h.tagBar = nil
end

-- The effects on a house: invisible anchors on the roof carrying flames (`kind` "burning", with
-- the countdown everyone can see and a bar that fills as dragons pour water on it), or smoke and a
-- few embers that smolder for a while ("burned").
local SMOKE_DARK = Color3.fromRGB(70, 60, 55)
local STEAM = Color3.fromRGB(235, 240, 245)
local FLAME_SIZE = 14
local FLAME_LIGHT = 3

local function addFx(index: number, kind: string)
	local h = houses[index]
	clearFx(h)
	local size = Zones.HouseSize
	local cf = houseCF(index) + Vector3.new(0, h.baseY, 0)
	local fx = Instance.new("Folder")
	fx.Name = "FireFX"
	local fires, lights, smokes = {}, {}, {}
	local spots = kind == "burned" and { Vector3.new(-size.X * 0.2, size.Y + 3, 0), Vector3.new(size.X * 0.25, size.Y + 2, 3) }
		or { Vector3.new(-size.X * 0.28, size.Y + 5, 0), Vector3.new(size.X * 0.28, size.Y + 5, 2), Vector3.new(0, size.Y - 3, -size.Z / 2) }
	for _, off in ipairs(spots) do
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(4, 1, 4)
		anchor.CFrame = cf * CFrame.new(off)
		anchor.Parent = fx
		local smoke = Instance.new("Smoke")
		smoke.RiseVelocity = 8
		if kind == "burning" then
			smoke.Color, smoke.Size, smoke.Opacity = SMOKE_DARK, 12, 0.35
			table.insert(fires, Props.fire(anchor, FLAME_SIZE, Color3.fromRGB(255, 120, 40)))
			table.insert(lights, Props.light(anchor, Color3.fromRGB(255, 140, 60), 40, FLAME_LIGHT))
		else
			smoke.Color, smoke.Size, smoke.Opacity = Color3.fromRGB(110, 105, 100), 7, 0.2
			table.insert(fires, Props.fire(anchor, 3, Color3.fromRGB(200, 60, 20)))
			table.insert(lights, Props.light(anchor, Color3.fromRGB(255, 90, 30), 14, 0.8))
		end
		smoke.Parent = anchor
		table.insert(smokes, smoke)
	end
	if kind == "burning" then
		-- a countdown everyone can see from across town, and under it how much water it's had
		local gui = Instance.new("BillboardGui")
		gui.Name = "FireTag"
		gui.Size = UDim2.fromOffset(170, 48)
		gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 14, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 400
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.new(1, 0, 0, 36)
		label.BackgroundColor3 = Color3.fromRGB(80, 20, 10)
		label.BackgroundTransparency = 0.25
		label.TextColor3 = Color3.fromRGB(255, 200, 120)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "🔥 On fire!"
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		local bar = Instance.new("Frame")
		bar.Name = "Water"
		bar.Position = UDim2.fromOffset(10, 40)
		bar.Size = UDim2.new(1, -20, 0, 7)
		bar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		bar.BackgroundTransparency = 0.3
		bar.BorderSizePixel = 0
		bar.Visible = false
		bar.Parent = gui
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		local base = Instance.new("Part")
		base.Name = "TagAnchor"
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.Transparency = 1
		base.Size = Vector3.new(1, 1, 1)
		base.CFrame = cf
		base.Parent = fx
		gui.Parent = base
		h.tag = label
		h.tagBar = bar
	end
	fx.Parent = h.model
	h.fx = fx
	h.fires = fires
	h.lights = lights
	h.smokes = smokes
	h.shown = nil
	if kind == "burned" then
		-- the embers go cold after a while (the smoke lingers)
		task.delay(Raids.SMOLDER, function()
			if h.fx ~= fx then
				return
			end
			for _, f in ipairs(fires) do
				f.Enabled = false
			end
			for _, l in ipairs(lights) do
				l.Enabled = false
			end
		end)
	end
end

-- How a burning house looks with `k` of the water it needs poured on it: the flames shrink and the
-- smoke turns to steam as the water goes on.
local function soak(h, k: number)
	for _, f in ipairs(h.fires or {}) do
		f.Size = math.max(2, FLAME_SIZE * (1 - 0.7 * k))
		f.Heat = 9 * (1 - 0.6 * k)
	end
	for _, l in ipairs(h.lights or {}) do
		l.Brightness = FLAME_LIGHT * (1 - 0.6 * k)
	end
	for _, smoke in ipairs(h.smokes or {}) do
		smoke.Color = SMOKE_DARK:Lerp(STEAM, k)
		smoke.Size = 12 + 4 * k
		smoke.RiseVelocity = 8 + 5 * k
	end
	if h.tagBar then
		h.tagBar.Visible = k > 0
		h.tagBar.Fill.Size = UDim2.fromScale(math.clamp(k, 0, 1), 1)
	end
end

-- A fire that's been put out doesn't just blink off: the flames die away over Raids.FLAMES_FADE
-- seconds while the steam billows, then the steam thins out and clears.
local function fadeOut(h)
	local fx = h.fx
	if not fx then
		return
	end
	if h.tag then
		h.tag.Parent.Parent:Destroy() -- (the countdown's anchor)
	end
	h.tag = nil
	h.tagBar = nil
	local fires, lights, smokes = h.fires or {}, h.lights or {}, h.smokes or {}
	for _, smoke in ipairs(smokes) do
		smoke.Color = STEAM
		smoke.Size = 18
		smoke.Opacity = 0.4
		smoke.RiseVelocity = 14
	end
	local sizes, brights = {}, {}
	for i, f in ipairs(fires) do
		sizes[i] = f.Size
	end
	for i, l in ipairs(lights) do
		brights[i] = l.Brightness
	end
	task.spawn(function()
		local steps = 10
		for i = 1, steps do
			task.wait(Raids.FLAMES_FADE / steps)
			if h.fx ~= fx then
				return -- lit again, or rebuilt
			end
			local k = 1 - i / steps
			for j, f in ipairs(fires) do
				f.Size = math.max(2, sizes[j] * k)
				f.Heat = 9 * k
				f.Enabled = k > 0.1
			end
			for j, l in ipairs(lights) do
				l.Brightness = brights[j] * k
				l.Enabled = k > 0.1
			end
		end
		task.wait(Raids.STEAM_TIME)
		if h.fx ~= fx then
			return
		end
		for _, smoke in ipairs(smokes) do
			smoke.Enabled = false -- (the last puffs drift off)
		end
		task.wait(4)
		if h.fx == fx then
			clearFx(h)
		end
	end)
end

-- Remember every part's look and place (and switch off the fireplace and lanterns) before a
-- house burns down, so the rebuild can put it all back.
local function remember(h)
	if h.original then
		return
	end
	h.original = {}
	for _, d in ipairs(h.model:GetDescendants()) do
		if not d:FindFirstAncestor("FireFX") then
			if d:IsA("BasePart") then
				h.original[d] = { color = d.Color, material = d.Material, cf = d.CFrame }
			elseif d:IsA("Light") or d:IsA("Fire") then
				h.original[d] = { enabled = d.Enabled }
				d.Enabled = false
			end
		end
	end
end

-- Soot creeping over the walls: `k` from 0 (as built) to 1 (charred black).
local function blacken(h, k: number)
	for d, look in pairs(h.original) do
		if look.color and d.Parent then
			d.Color = look.color:Lerp(CHAR, 0.8 * k)
			if look.material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic -- the glowing windows go dark
			end
		end
	end
end

-- The roof (everything above the wall tops but the brick chimney) caves in: the two halves drop
-- into the house, tipping this way and that, and the ridge beam with its carved dragon heads comes
-- down in one piece, one end on the floor and the other leaning on a wall (falling on their own,
-- the heads used to end up hanging in the air beside the house). It speeds up as it falls.
local function caveIn(index: number, token)
	local h = houses[index]
	local frame = houseCF(index) + Vector3.new(0, h.baseY, 0)
	local rng = Random.new(index * 31)
	local roof = {}
	local top = -math.huge
	for d, look in pairs(h.original) do
		if look.cf and d.Material ~= Enum.Material.Brick then
			local y = frame:PointToObjectSpace(look.cf.Position).Y
			if y > Zones.HouseSize.Y + 0.8 then
				table.insert(roof, { part = d, from = look.cf, y = y })
				top = math.max(top, y)
			end
		end
	end
	-- the ridge: the beam along the peak and the heads on its ends (the highest parts)
	local center, n = Vector3.zero, 0
	for _, f in ipairs(roof) do
		if f.y >= top - 1.5 then
			f.ridge = true
			center += f.from.Position
			n += 1
		end
	end
	center /= math.max(1, n)
	local target = (frame * CFrame.new(0, Zones.HouseSize.Y * 0.6, 0)).Position
	local axis = frame.LookVector -- the beam runs across the house, so it tips about the front-back axis
	local tilt = (rng:NextNumber() < 0.5 and -1 or 1) * 0.5
	for _, f in ipairs(roof) do
		if not f.ridge then
			local drop = Zones.HouseSize.Y * 0.5 + rng:NextNumber(0, 3)
			local tip = CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.1, 0.1), rng:NextNumber(-0.2, 0.2))
			f.to = (f.from - Vector3.new(0, drop, 0)) * tip
		end
	end
	for i = 1, 6 do
		if h.collapsing ~= token then
			return
		end
		local k = (i / 6) ^ 2
		local pose = CFrame.new(center:Lerp(target, k)) * CFrame.fromAxisAngle(axis, tilt * k) * CFrame.new(-center)
		for _, f in ipairs(roof) do
			if f.part.Parent then
				f.part.CFrame = f.ridge and pose * f.from or f.from:Lerp(f.to, k)
			end
		end
		task.wait(0.08)
	end
end

-- A house burning down, over a little while rather than all at once: the flames roar up while the
-- walls blacken, the roof caves in with a burst of sparks, then the fire dies down to smoldering
-- embers and smoke.
local function collapse(index: number)
	local h = houses[index]
	local token = {}
	h.collapsing = token
	if not h.fires or #h.fires == 0 then
		addFx(index, "burning")
	end
	if h.tag then
		h.tag.Text = "🏚️ Burning down!"
	end
	for _, f in ipairs(h.fires) do
		f.Size = 22
		f.Heat = 18
	end
	for _, l in ipairs(h.lights) do
		l.Brightness = 5
	end
	for _, smoke in ipairs(h.smokes or {}) do
		smoke.Color = SMOKE_DARK
	end
	if h.tagBar then
		h.tagBar.Visible = false
	end
	remember(h)
	for i = 1, 5 do
		blacken(h, i / 5)
		task.wait(Raids.COLLAPSE_TIME / 5)
		if h.collapsing ~= token then
			return
		end
	end
	if h.tag then
		h.tag.Parent.Parent:Destroy() -- (the countdown's anchor)
		h.tag = nil
		h.tagBar = nil
	end
	caveIn(index, token)
	if h.collapsing ~= token then
		return
	end
	S.CombatService.broadcastVFX({ kind = "collapse", pos = roofTop(index) - Vector3.new(0, 6, 0) })
	local steps = 8
	for i = 1, steps do
		task.wait(Raids.DIE_DOWN / steps)
		if h.collapsing ~= token then
			return
		end
		local k = 1 - i / steps
		for _, f in ipairs(h.fires) do
			f.Size = 4 + 18 * k
			f.Heat = 4 + 14 * k
		end
		for _, l in ipairs(h.lights) do
			l.Brightness = 0.8 + 4.2 * k
		end
	end
	h.collapsing = nil
	addFx(index, "burned")
end

local function unchar(h)
	h.collapsing = nil
	for d, look in pairs(h.original or {}) do
		if d.Parent then
			if look.color then
				d.Color = look.color
				d.Material = look.material
				d.CFrame = look.cf
			else
				d.Enabled = look.enabled
			end
		end
	end
	h.original = nil
end

local function anyBurning(): boolean
	for _, h in pairs(houses) do
		if h.state == "burning" then
			return true
		end
	end
	return false
end

-- A Torchbearer made it to the door.
function RaidService.ignite(index: number): boolean
	local h = houses[index]
	if not h or h.state ~= "ok" then
		return false
	end
	local burnTime = (raid and raid.tier or Raids.Tiers[#Raids.Tiers]).burnTime
	h.state = "burning"
	h.burnsAt = now() + burnTime
	h.model:SetAttribute("Fire", "burning")
	h.model:SetAttribute("BurnsAt", h.burnsAt)
	addFx(index, "burning")
	notifyAll(string.format("A house is on fire! Scoop up water from the river or a well and hover over it to pour (%ds).", burnTime), Color3.fromRGB(255, 150, 70), "🔥")
	return true
end

local function extinguish(index: number)
	local h = houses[index]
	h.state = "ok"
	h.burnsAt = nil
	h.douse = nil
	h.pourers = nil
	h.model:SetAttribute("Fire", nil)
	h.model:SetAttribute("BurnsAt", nil)
	fadeOut(h)
end

local function burnDown(index: number)
	local h = houses[index]
	if h.state == "burned" then
		return
	end
	h.state = "burned"
	h.burnsAt = nil
	h.douse = nil
	h.pourers = nil
	h.model:SetAttribute("Fire", "burned")
	h.model:SetAttribute("BurnsAt", nil)
	task.spawn(collapse, index)
	if raid then
		raid.burned += 1
		setAttributes()
		notifyAll(string.format("A house burned down! (%d of %d)", raid.burned, Raids.MAX_BURNED), Color3.fromRGB(255, 110, 80), "🏚️")
		if raid.burned >= Raids.MAX_BURNED then
			endRaid(false, "burned")
		end
	else
		h.rebuildAt = now() + Raids.REBUILD
	end
end

local function rebuild(index: number)
	local h = houses[index]
	unchar(h)
	clearFx(h)
	h.state = "ok"
	h.rebuildAt = nil
	h.model:SetAttribute("Fire", nil)
end

function RaidService.rebuildAll()
	for index, h in pairs(houses) do
		if h.state == "burned" then
			rebuild(index)
		elseif h.state == "burning" then
			extinguish(index)
		end
	end
end

function RaidService.houseState(index: number): string?
	return houses[index] and houses[index].state
end

---------------------------------------------------------------- water
-- Dragons carry up to Raids.WATER_LOADS loads of water (player attribute "Water", a number that
-- runs down as they pour; drops drip off them while they carry any). They scoop it up skimming
-- low over any water or at a town well. Hovering over a burning house pours it: a stream falls
-- from the dragon (player attribute "Pouring", emitter "WaterPour") and the house's progress
-- (h.douse, the blue bar under its countdown) goes up. Every dragon pouring adds to the same
-- house, so a few together put a fire out much faster; left alone, a half-soaked fire creeps back.

local TICK = 0.2 -- seconds between water ticks

local function waterOf(player: Player): number
	return player:GetAttribute("Water") or 0
end

local function setWater(player: Player, n: number)
	player:SetAttribute("Water", n > 0.001 and n or nil)
	local _, _, root = S.PlayerService.getCharacter(player)
	local drips = root and root:FindFirstChild("WaterDrips")
	if n > 0.001 and root and not drips then
		drips = Instance.new("ParticleEmitter")
		drips.Name = "WaterDrips"
		drips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		drips.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255), Color3.fromRGB(80, 150, 230))
		drips.LightEmission = 0.4
		drips.Rate = 22
		drips.Lifetime = NumberRange.new(0.5, 0.8)
		drips.Speed = NumberRange.new(2, 5)
		drips.SpreadAngle = Vector2.new(35, 35)
		drips.EmissionDirection = Enum.NormalId.Bottom
		drips.Acceleration = Vector3.new(0, -50, 0)
		drips.Size = NumberSequence.new(0.5, 0.2)
		drips.Parent = root
	elseif n <= 0.001 and drips then
		drips:Destroy()
	end
end

-- The stream of water falling from a dragon while it pours.
local function setPouring(player: Player, on: boolean)
	if (player:GetAttribute("Pouring") == true) == on then
		return
	end
	player:SetAttribute("Pouring", on or nil)
	local _, _, root = S.PlayerService.getCharacter(player)
	local stream = root and root:FindFirstChild("WaterPour")
	if on and root and not stream then
		stream = Instance.new("ParticleEmitter")
		stream.Name = "WaterPour"
		stream.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		stream.Color = ColorSequence.new(Color3.fromRGB(190, 230, 255), Color3.fromRGB(60, 130, 220))
		stream.LightEmission = 0.25
		stream.Rate = 110
		stream.Lifetime = NumberRange.new(0.7, 1.1)
		stream.Speed = NumberRange.new(14, 22)
		stream.SpreadAngle = Vector2.new(12, 12)
		stream.EmissionDirection = Enum.NormalId.Bottom
		stream.Acceleration = Vector3.new(0, -60, 0)
		stream.Size = NumberSequence.new(1.3, 0.7)
		stream.Transparency = NumberSequence.new(0.1, 0.5)
		stream.Parent = root
	end
	if stream then
		stream.Enabled = on
	end
end

local function clearWater()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Water") then
			setWater(player, 0)
		end
		setPouring(player, false)
	end
end

-- Where this dragon could scoop water from right now (a well it's at, or water just under its
-- belly), or nil.
local function scoopSpot(humanoid: Humanoid, root: BasePart): Vector3?
	local pos = root.Position
	for _, well in ipairs(wells) do
		if flat(pos, well.ground) <= Raids.WELL_REACH and pos.Y - well.ground.Y <= Raids.WELL_HEIGHT then
			return well.ground + Vector3.new(0, 2.5, 0)
		end
	end
	local reach = humanoid.HipHeight + root.Size.Y / 2 + Raids.SCOOP_REACH
	local ray = workspace:Raycast(pos + Vector3.new(0, 10, 0), Vector3.new(0, -(10 + reach), 0), terrainParams)
	if ray and ray.Material == Enum.Material.Water then
		return ray.Position
	end
	return nil
end

local function overHouse(root: BasePart, index: number): boolean
	return flat(root.Position, Zones.Houses[index].pos) <= Raids.POUR_REACH and root.Position.Y - houses[index].baseY <= Raids.POUR_HEIGHT
end

local function scoop(player: Player, at: Vector3)
	local had = waterOf(player)
	setWater(player, Raids.WATER_LOADS)
	S.CombatService.broadcastVFX({ kind = "splash", pos = at })
	if had <= 0 then
		S.PlayerService.notify(player, string.format("You scooped up water (enough for %d fire%s)! Hover over a burning house to pour it.", Raids.WATER_LOADS, Raids.WATER_LOADS == 1 and "" or "s"), WATER_COLOR, "💧")
	end
end

-- Enough water went on: the fire's out. Everyone who poured some gets the credit.
local function putOut(index: number)
	local h = houses[index]
	local pourers = h.pourers or {}
	extinguish(index)
	S.CombatService.broadcastVFX({ kind = "putOut", pos = roofTop(index) })
	for player in pairs(pourers) do
		if player.Parent then
			if raid then
				raid.contrib[player] = (raid.contrib[player] or 0) + 1
			end
			S.PlayerService.notify(player, "The fire's out! The house is saved.", Color3.fromRGB(140, 230, 140), "💧")
		end
	end
end

-- One dragon pours for a tick onto the house under it (the one nearest to going out, if it's over
-- more than one). Returns the house it poured on.
local function pourTick(player: Player, root: BasePart, t: number): number?
	local best, bestK = nil, -1
	for index, h in pairs(houses) do
		if h.state == "burning" and overHouse(root, index) and (h.douse or 0) > bestK then
			best, bestK = index, h.douse or 0
		end
	end
	if not best then
		return nil
	end
	local h = houses[best]
	local water = waterOf(player)
	local use = math.min(water, TICK / Raids.POUR_TIME)
	setWater(player, water - use)
	h.douse = (h.douse or 0) + use * Raids.POUR_TIME / Raids.DOUSE_TIME
	h.pourers = h.pourers or {}
	h.pourers[player] = true
	h.lastPour = t
	if water - use <= 0.001 and h.douse < 1 then
		S.PlayerService.notify(player, "Out of water! Scoop up more from the river or a well.", WATER_COLOR, "💧")
	end
	return best
end

-- Five times a second: dragons at the water scoop, dragons over a fire pour, and every burning
-- house shows how soaked it is (or creeps back if nobody's pouring). Only while there's a raid or
-- a fire (otherwise nobody carries water).
local function waterTick()
	local burning = anyBurning()
	if not raid and not burning then
		clearWater()
		return
	end
	local t = os.clock()
	local poured = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local _, humanoid, root = S.PlayerService.getCharacter(player)
		local index = nil
		if root then
			if burning and waterOf(player) > 0 then
				index = pourTick(player, root, t)
			end
			if index then
				poured[index] = true
			elseif waterOf(player) < Raids.WATER_LOADS then
				local at = scoopSpot(humanoid, root)
				if at then
					scoop(player, at)
				end
			end
		end
		setPouring(player, index ~= nil)
	end
	local now_ = now()
	for index, h in pairs(houses) do
		if h.state == "burning" then
			if (h.douse or 0) >= 1 then
				putOut(index)
			else
				if h.douse and not poured[index] and t - (h.lastPour or 0) > Raids.REGROW_DELAY then
					h.douse = h.douse - TICK / Raids.DOUSE_REGROW
					if h.douse <= 0 then
						h.douse = nil
						h.pourers = nil
					end
				end
				local k = h.douse or 0
				if math.abs(k - (h.shown or 0)) > 0.015 or (k == 0 and (h.shown or 0) ~= 0) then
					h.shown = k
					soak(h, k)
				end
				if poured[index] and t - (h.lastSizzle or 0) >= 0.6 then
					h.lastSizzle = t
					S.CombatService.broadcastVFX({ kind = "sizzle", pos = roofTop(index) })
				end
				if h.tag then
					local text = poured[index] and "💧 Putting it out!" or string.format("🔥 On fire! %ds", math.max(0, math.ceil((h.burnsAt or now_) - now_)))
					if h.tag.Text ~= text then
						h.tag.Text = text
					end
				end
			end
		end
	end
end

-- How much water a burning house has had (0 to 1).
function RaidService.douseProgress(index: number): number
	return houses[index] and houses[index].douse or 0
end

---------------------------------------------------------------- longships

local function riverZ(x: number): number
	for i = 1, #riverSamples - 1 do
		local a, b = riverSamples[i], riverSamples[i + 1]
		if x >= a.X and x <= b.X then
			local k = (x - a.X) / math.max(0.01, b.X - a.X)
			return a.Z + (b.Z - a.Z) * k
		end
	end
	return 276
end

-- A ship on the river at x, `side` studs toward the town bank from the middle of the river.
local function shipCF(x: number, heading: number, side: number): CFrame
	local pos = Vector3.new(x, Zones.WATER_LEVEL, riverZ(x) - side)
	local ahead = Vector3.new(x + heading * 3, Zones.WATER_LEVEL, riverZ(x + heading * 3) - side)
	return CFrame.lookAt(pos, ahead)
end

-- How far along a trip is at time share k: full speed nearly all the way, slowing down only for
-- the last Raids.SHIP_SLOWDOWN of it (the ships used to ease in so gently they seemed to crawl up
-- to the beach while the vikings on deck waited).
function RaidService.rowEase(k: number): number
	local d = Raids.SHIP_SLOWDOWN
	local v = 1 / (1 - d / 2)
	if k <= 1 - d then
		return v * k
	end
	local u = (k - (1 - d)) / d
	return v * (1 - d) + v * d * (u - u * u / 2)
end

local function shipX(ship: Model): number
	return (ship.PrimaryPart.CFrame * SHIP_KEEL:Inverse()).Position.X
end

-- Row a ship from where it is now to x `toX`, `toSide` studs toward the town bank, over
-- `seconds`, then call done. A newer trip for the same ship cancels this one. The keel is the
-- ship's PrimaryPart and sits SHIP_KEEL below the waterline frame the ship was built on.
local function rowTo(ship: Model, toX: number, toSide: number, seconds: number, done: (() -> ())?)
	local keel = ship.PrimaryPart
	if not keel then
		return
	end
	local trip = {}
	rowing[ship] = trip
	local here = (keel.CFrame * SHIP_KEEL:Inverse()).Position
	local fromX, fromSide = here.X, riverZ(here.X) - here.Z
	local heading = toX > fromX and 1 or -1
	task.spawn(function()
		local start = os.clock()
		while ship.Parent and rowing[ship] == trip do
			local k = math.min(1, (os.clock() - start) / seconds)
			local e = RaidService.rowEase(k)
			ship:PivotTo(shipCF(fromX + (toX - fromX) * e, heading, fromSide + (toSide - fromSide) * e) * SHIP_KEEL)
			if k >= 1 then
				break
			end
			task.wait() -- every frame
		end
		if rowing[ship] ~= trip or not ship.Parent then
			return
		end
		rowing[ship] = nil
		if done then
			done()
		end
	end)
end

local function rowAll(r, inbound: boolean, seconds: number)
	for i, ship in ipairs(r.ships) do
		local landing = Raids.Landings[i]
		if inbound then
			rowTo(ship, landing.shipX, SHIP_SIDE, seconds, function()
				r.docked[i] = true
			end)
		else
			r.docked[i] = false
			rowTo(ship, landing.fromX, 0, seconds)
		end
	end
end

-- Weld every part to the keel, so moving the ship moves (and replicates) one part, not ~110.
local function weldTo(model: Model, anchor: BasePart)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d ~= anchor then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "ShipWeld"
				weld.Part0 = anchor
				weld.Part1 = d
				weld.Parent = d
				d.Massless = true
				d.Anchored = false
			end
		end
	end
end

-- Who comes ashore in a wave, in order ("leader" = the Raid Captain).
local function waveList(r, index: number): { string }
	local wave = r.tier.waves[index]
	local list = {}
	for typeId, count in pairs(wave) do
		if typeId ~= "leader" then
			for _ = 1, math.max(1, math.floor(count * r.scale + 0.5)) do
				table.insert(list, typeId)
			end
		end
	end
	table.sort(list)
	for i = #list, 2, -1 do -- mix them up a little
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	if wave.leader then
		table.insert(list, "leader")
	end
	return list
end

-- Which ship each raider in a wave rides (by its place in the list).
local function shipFor(k: number): number
	return (k % #Raids.Landings) + 1
end

-- Deck spot i of `count` on a ship: two rows along the deck.
local function deckSpot(keel: BasePart, i: number, count: number): Vector3
	local slots = math.ceil(count / 2)
	local slot = math.ceil(i / 2)
	local along = slots > 1 and (-9 + 18 * (slot - 1) / (slots - 1)) or 0
	local frame = keel.CFrame * SHIP_KEEL:Inverse() -- the ship's own frame at the waterline
	return (frame * CFrame.new(i % 2 == 0 and 1.3 or -1.3, 0.6, along)).Position
end

local function dropShipWelds(e)
	for _, d in ipairs(e.root:GetChildren()) do
		if d:IsA("WeldConstraint") and d.Name == "ShipWeld" then
			d:Destroy()
		end
	end
end

-- Stand a raider on a ship's deck (facing town, cheering: model attribute "Aboard"), welded to
-- the keel by its root. It doesn't think while it's aboard, huddles behind its shield (takes
-- Raids.DECK_DAMAGE_TAKEN of the damage, 🛡️ on its nametag), and if it's beaten there it tumbles
-- overboard (keepBody: see onRaiderDeath) instead of toppling onto the deck.
local function putAboard(e, ship: Model, deck: Vector3)
	local keel = ship.PrimaryPart
	local lift = e.humanoid.HipHeight + e.root.Size.Y / 2
	e.root.Anchored = true
	e.model:PivotTo(CFrame.lookAt(deck + Vector3.new(0, lift, 0), deck + Vector3.new(0, lift, -1)))
	e.model.Parent = ship
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ShipWeld"
	weld.Part0 = keel
	weld.Part1 = e.root
	weld.Parent = e.root
	e.root.Anchored = false
	e.aboard = true
	e.customAI = true
	e.keepBody = true
	e.target = nil
	e.damageTakenMult = Raids.DECK_DAMAGE_TAKEN
	e.humanoid.BreakJointsOnDeath = false
	e.model:SetAttribute("Aboard", true)
	e.model:SetAttribute("Shielded", true)
end

-- A leap in an arc from `from` to `dest` (where the root ends up) over Raids.LEAP_TIME, then `done`
-- (unless it was beaten mid-air). The root is anchored for the flight.
local function arc(e, from: Vector3, dest: Vector3, done: () -> ())
	e.leaping = true
	e.root.Anchored = true
	e.model:SetAttribute("Leaping", true)
	local turn = flat(from, dest) > 0.5 and CFrame.lookAt(from, Vector3.new(dest.X, from.Y, dest.Z)).Rotation or e.root.CFrame.Rotation
	task.spawn(function()
		local start = os.clock()
		while not e.dead and e.model.Parent do
			local k = math.min(1, (os.clock() - start) / Raids.LEAP_TIME)
			e.model:PivotTo(CFrame.new(from:Lerp(dest, k) + Vector3.new(0, Raids.LEAP_HEIGHT * 4 * k * (1 - k), 0)) * turn)
			if k >= 1 then
				break
			end
			task.wait()
		end
		if e.dead or not e.model.Parent then
			return
		end
		e.leaping = nil
		e.model:SetAttribute("Leaping", nil)
		done()
	end)
end

-- Off the deck and onto the beach at `spot`: from there it's an ordinary raider (or, if the raid
-- was lost while it was in the air, one running back to the ships).
local function leapAshore(r, e, spot: Vector3)
	dropShipWelds(e)
	e.aboard = nil
	e.model.Parent = enemyFolder
	local lift = e.humanoid.HipHeight + e.root.Size.Y / 2 + 0.5
	arc(e, e.root.Position, spot + Vector3.new(0, lift, 0), function()
		S.CombatService.broadcastVFX({ kind = "thud", pos = spot })
		e.model:SetAttribute("Aboard", nil)
		e.model:SetAttribute("Shielded", nil)
		e.damageTakenMult = nil
		e.keepBody = false
		e.root.Anchored = false
		pcall(function()
			e.root:SetNetworkOwner(nil)
			-- (it rode in welded to the ship and flew anchored: back on its feet)
			e.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		e.spawnPos = spot
		e.lastPos = e.root.Position
		e.landedAt = now()
		if r.retreating then
			task.spawn(runBack, r, e)
		else
			e.customAI = false
		end
	end)
end

-- A raider beaten on deck (or in mid-leap) tumbles off the side: a splash if it lands in the
-- river, a puff on the beach.
local function overboard(e)
	local model, root = e.model, e.root
	if not model.Parent then
		return
	end
	dropShipWelds(e)
	model.Parent = enemyFolder
	root.Anchored = true
	model:SetAttribute("Aboard", nil)
	model:SetAttribute("Leaping", nil)
	local from = model:GetPivot()
	local out = Vector3.new(math.random(-3, 3), 0, 7) -- over the river side of the deck, away from town
	local ground, material = S.EnemyService.terrainGround(from.Position + out)
	local to = Vector3.new(from.X + out.X, ground.Y - 1, from.Z + out.Z)
	task.spawn(function()
		local start = os.clock()
		while model.Parent do
			local k = math.min(1, (os.clock() - start) / 0.9)
			local pos = from.Position:Lerp(to, k) + Vector3.new(0, 16 * k * (1 - k), 0)
			model:PivotTo(CFrame.new(pos) * from.Rotation * CFrame.Angles(-2.2 * k, 0, 0.8 * k))
			if k >= 1 then
				break
			end
			task.wait()
		end
		if material == Enum.Material.Water then
			S.CombatService.broadcastVFX({ kind = "splash", pos = Vector3.new(to.X, ground.Y, to.Z), big = true })
		else
			S.CombatService.broadcastVFX({ kind = "enemyDeath", pos = to })
		end
		task.wait(0.3)
		S.EnemyService.forget(e)
	end)
end

local function launchShips(r)
	for _, landing in ipairs(Raids.Landings) do
		local heading = landing.shipX > landing.fromX and 1 or -1
		local ship = Props.longship(shipFolder, shipCF(landing.fromX, heading, 0))
		local keel = nil
		for _, d in ipairs(ship:GetDescendants()) do
			if d:IsA("BasePart") and (not keel or d.Size.Z > keel.Size.Z) then
				keel = d
			end
		end
		ship.PrimaryPart = keel
		weldTo(ship, keel)
		table.insert(r.ships, ship)
	end
end

-- The ships row off upriver and are gone (with whoever's still on deck).
local function sailAway(r)
	for i, ship in ipairs(r.ships) do
		local landing = Raids.Landings[i]
		local function gone()
			for e in pairs(r.raiders) do
				if e.aboard and e.model:IsDescendantOf(ship) then
					S.EnemyService.despawn(e)
				end
			end
			ship:Destroy()
		end
		if landing and ship.Parent then
			rowTo(ship, landing.fromX, 0, 25, gone)
		else
			gone()
		end
	end
end

---------------------------------------------------------------- raider brains
-- Every raider has a goal it works on whenever there's no dragon to fight (EnemyService calls
-- `objective`):
--   house     (Torchbearers) walk to a house's door and set it alight
--   villager  walk up to a villager and hit them until they're knocked out
--   dragon    walk to a dragon, even one at home in its lair; once close, the fight AI takes over
--   roam      stroll to a street corner looking for trouble
-- Goals spread out: at most Raids.CROWD raiders on one dragon (EnemyService.raidersOn counts
-- `hunting`), two on one villager, one Torchbearer per house while there's a choice. Fighters
-- pick someone new every Raids.RETARGET seconds or so.

local function hunters(kind: string, who, except): number
	local n = 0
	for other in pairs(raid.raiders) do
		if other ~= except and not other.dead and other.goal and other.goal.kind == kind and other.goal.who == who then
			n += 1
		end
	end
	return n
end

-- The nearest standing house (not already another Torchbearer's, if there's a choice).
local function pickHouse(e): number?
	local best, bestScore = nil, math.huge
	for index, h in pairs(houses) do
		if h.state == "ok" then
			local score = hunters("house", index, e) * 500 + flat(e.root.Position, Zones.houseDoor(Zones.Houses[index])) + math.random() * 20
			if score < bestScore then
				best, bestScore = index, score
			end
		end
	end
	return best
end

local function pickVillager(e)
	local best, bestScore = nil, math.huge
	for _, v in ipairs(S.CivilianService.villagers()) do
		if v.model.Parent and not v.knockedOut then
			local n = hunters("villager", v, e)
			if n < 2 then
				local score = n * 200 + flat(e.root.Position, v.root.Position) + math.random() * 60
				if score < bestScore then
					best, bestScore = v, score
				end
			end
		end
	end
	return best
end

-- A dragon on its feet somewhere in town (home in its lair counts).
local function huntable(player: Player): BasePart?
	local character, humanoid, root = S.PlayerService.getCharacter(player)
	if not character or humanoid.Health <= 0 or character:GetAttribute("Flying") or character:GetAttribute("Stealthed") then
		return nil
	end
	if S.BossService.isInFight(player) or not Zones.isIn("Town", root.Position) then
		return nil
	end
	return root
end

local function pickDragon(e): Player?
	local best, bestScore = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = huntable(player)
		if root then
			local n = S.EnemyService.raidersOn(player, e)
			if n < Raids.CROWD then
				local score = n * 150 + flat(e.root.Position, root.Position) * 0.5 + math.random() * 80
				if score < bestScore then
					best, bestScore = player, score
				end
			end
		end
	end
	return best
end

local function pickGoal(e, t: number)
	e.goal = nil
	e.hunting = nil
	e.route = nil
	if e.role == "torch" then
		local index = pickHouse(e)
		if index then
			e.goal = { kind = "house", who = index }
		end
	end
	if not e.goal then
		local v = math.random() < Raids.VILLAGER_VICTIM_CHANCE and pickVillager(e) or nil
		local p = not v and pickDragon(e) or nil
		if not v and not p then
			v = pickVillager(e)
		end
		if v then
			e.goal = { kind = "villager", who = v }
		elseif p then
			e.goal = { kind = "dragon", who = p }
			e.hunting = p
		else
			e.goal = { kind = "roam", who = STREET_GOALS[math.random(1, #STREET_GOALS)] }
		end
	end
	e.goalUntil = t + Raids.RETARGET * (0.7 + math.random() * 0.6)
end

-- Where the goal is right now (nil once it's done: house burning, villager down, dragon gone).
local function goalPos(e): Vector3?
	local g = e.goal
	if g.kind == "house" then
		local h = houses[g.who]
		return h and h.state == "ok" and Zones.houseDoor(Zones.Houses[g.who]) or nil
	elseif g.kind == "villager" then
		local v = g.who
		return (v.model.Parent and not v.knockedOut) and v.root.Position or nil
	elseif g.kind == "dragon" then
		local root = huntable(g.who)
		return root and root.Position or nil
	end
	return S.CivilianService.nodePos(g.who)
end

-- Street nodes from here to near `pos`, plus the side road and the gate for a dragon at home.
local function planRoute(e, pos: Vector3, t: number)
	local start = S.CivilianService.nearestNode(e.root.Position, true)
	local base = Zones.baseAt(pos)
	local approach = base and Zones.LairApproach[base.center.X < 0 and "west" or "east"]
	local goalNode = approach and approach.from or S.CivilianService.nearestNode(pos)
	local route = { S.CivilianService.nodePos(start) }
	for _, name in ipairs(S.CivilianService.route(start, goalNode)) do
		table.insert(route, S.CivilianService.nodePos(name))
	end
	if approach then
		for _, p in ipairs(approach.via) do
			table.insert(route, p)
		end
		table.insert(route, Vector3.new(approach.roadX, 0, base.center.Z))
		table.insert(route, Zones.lairGate(base))
	end
	e.route = route
	e.legStart = t
end

local function face(e, pos: Vector3)
	local here = e.root.Position
	if flat(here, pos) > 0.5 then
		e.root.CFrame = CFrame.lookAt(here, Vector3.new(pos.X, here.Y, pos.Z))
	end
end

local function reach(e): number
	return (e.def.attackRange or 6) + 4 + e.scale
end

-- A raider's axe on a villager.
local function hitVillager(e, v, t: number)
	e.humanoid:MoveTo(e.root.Position)
	face(e, v.root.Position)
	if t < e.nextAttack then
		return
	end
	e.nextAttack = t + (e.def.attackCooldown or 1.5)
	e.model:SetAttribute("Swing", os.clock())
	task.delay(0.3, function()
		if not e.dead and v.model.Parent and flat(e.root.Position, v.root.Position) <= reach(e) + 2 then
			S.CivilianService.hurt(v)
		end
	end)
end

-- EnemyService calls this whenever a raider has no dragon to fight. Returns true if it moved.
local function objective(e, t: number): boolean
	if not raid or raid.phase ~= "fighting" or not raid.raiders[e] then
		return false
	end
	if e.lastObjective and t - e.lastObjective > 1.5 then
		-- it was busy fighting: find the way again from wherever it ended up
		e.route = nil
		e.torchUntil = nil
	end
	e.lastObjective = t
	local humanoid = e.humanoid
	if e.torchUntil then
		humanoid:MoveTo(e.root.Position)
		if t >= e.torchUntil then
			e.torchUntil = nil
			RaidService.ignite(e.goal.who)
			e.goal = nil
		end
		return true
	end
	if e.idleUntil and t < e.idleUntil then
		humanoid:MoveTo(e.root.Position)
		return true
	end
	if not e.goal or (e.goal.kind ~= "house" and t >= e.goalUntil) then
		pickGoal(e, t)
	end
	local dest = goalPos(e)
	if not dest then
		pickGoal(e, t)
		dest = goalPos(e)
		if not dest then
			return false
		end
	end
	local g = e.goal
	local here = e.root.Position
	local dist = flat(here, dest)
	if g.kind == "villager" and dist <= reach(e) then
		hitVillager(e, g.who, t)
		return true
	end
	if (g.kind == "villager" or g.kind == "dragon") and (dist <= 30 or g.direct) then
		-- close (or at the end of the streets): straight at them. Give up on someone we can't
		-- get any closer to.
		e.route = nil
		if dist < (g.best or math.huge) - 2 then
			g.best = dist
			g.progressAt = t
		end
		if t - (g.progressAt or t) > 6 then
			pickGoal(e, t)
			return true
		end
		if t - (e.lastPush or 0) > 0.5 then
			e.lastPush = t
			humanoid:MoveTo(dest)
		end
		return true
	end
	if not e.route then
		planRoute(e, dest, t)
	end
	local step = e.route[1]
	if not step then
		-- end of the road
		e.route = nil
		if g.kind == "house" then
			local h = houses[g.who]
			if h and h.state == "ok" then
				e.torchUntil = t + Raids.TORCH_TIME
				e.model:SetAttribute("Swing", os.clock())
				face(e, Zones.Houses[g.who].pos)
			else
				e.goal = nil
			end
		elseif g.kind == "roam" then
			e.idleUntil = t + 2 + math.random() * 3
			e.goal = nil
		else
			g.direct = true
		end
		return true
	end
	local stepDist = flat(here, step)
	if stepDist < 4 then
		table.remove(e.route, 1)
		e.legStart = t
		return true
	end
	-- Humanoid:MoveTo gives up after 8 seconds, so keep nudging it, and hop past anything that
	-- has held a raider up for too long (a lamp post, a crowd of vikings).
	if t - (e.lastPush or 0) > 2 then
		e.lastPush = t
		humanoid:MoveTo(step)
	end
	if t - e.legStart > stepDist / math.max(6, e.baseSpeed) + 8 then
		local lift = humanoid.HipHeight + e.root.Size.Y / 2 + 0.5
		e.model:PivotTo(CFrame.new(step + Vector3.new(0, lift, 0)) * e.root.CFrame.Rotation)
		e.legStart = t
	end
	return true
end

-- Has the raid been won? Every wave has boarded and nobody's left (on deck or ashore).
local function checkWon(r)
	if raid == r and r.boarded >= #r.tier.waves and r.left <= 0 then
		endRaid(true)
	end
end

local function onRaiderDeath(e)
	if e.aboard or e.leaping then
		overboard(e)
	end
	local r = raid
	if not r or not r.raiders[e] then
		return
	end
	for player, dealt in pairs(e.damageBy) do
		r.contrib[player] = (r.contrib[player] or 0) + dealt
	end
	r.left = math.max(0, r.left - 1)
	setAttributes()
	checkWon(r)
end

-- A raider (typeId, or "leader" for the Raid Captain) standing at `pos`.
local function spawnRaider(r, typeId: string, pos: Vector3)
	local opts = { raid = true, leash = 5000, objective = objective, onDeath = onRaiderDeath }
	local c = Raids.Captain
	if typeId == "leader" then
		typeId = c.base
		opts.level = math.min(Game.LEVEL_CAP, r.level + 2)
		opts.displayName = c.name
		opts.scale = c.scale
		opts.look = c.look
		opts.healthMult = r.tier.captainHealth + c.healthPerPlayer * (r.players - 1)
		opts.damageMult = c.damageMult
		opts.slam = c.slam
	end
	local e = S.EnemyService.spawn(typeId, opts.level or r.level, pos, opts)
	if e then
		e.role = typeId == "Torchbearer" and "torch" or "fighter"
		e.landedAt = now()
		r.raiders[e] = true
	else
		r.left = math.max(0, r.left - 1)
		setAttributes()
		checkWon(r)
	end
	return e
end

-- A wave boards the longships upriver: real raiders, standing on the decks in two rows. They
-- all count toward "raiders left" from now on (so shooting them off the ships counts). If there
-- are more than fit on deck, the rest wade ashore when the wave lands.
local function board(r, index: number)
	local list = waveList(r, index)
	r.waveList = list
	r.aboard = {}
	r.boarded = index
	r.left += #list
	r.total += #list
	for s, ship in ipairs(r.ships) do
		local keel = ship.PrimaryPart
		if keel and ship.Parent then
			local mine = {}
			for k, typeId in ipairs(list) do
				if shipFor(k) == s then
					table.insert(mine, { k = k, typeId = typeId })
				end
			end
			local count = math.min(Raids.PASSENGERS, #mine)
			for i = 1, count do
				local deck = deckSpot(keel, i, count)
				local e = spawnRaider(r, mine[i].typeId, deck)
				if e then
					putAboard(e, ship, deck)
					r.aboard[mine[i].k] = e
				end
			end
		end
	end
	setAttributes()
end

-- The wave on deck leaps ashore one viking after another (anyone who didn't fit on deck wades
-- in). Returns how long that takes.
local function unload(r, index: number): number
	local list = r.waveList or {}
	local aboard = r.aboard or {}
	r.waveList = nil
	r.aboard = nil
	r.wave = index
	r.nextWaveAt = nil
	setAttributes()
	if index > 1 then
		notifyAll(string.format("Wave %d of %d is coming ashore!", index, #r.tier.waves), Color3.fromRGB(255, 170, 90), "⛵")
	end
	for k, typeId in ipairs(list) do
		task.delay((k - 1) * Raids.HOP_GAP, function()
			if raid ~= r then
				return -- (the raid's over: whoever's still on deck stays there)
			end
			local shore = Raids.Landings[shipFor(k)].shore
			local spot = (S.EnemyService.terrainGround(shore))
			for _ = 1, 10 do
				local ok, ground = S.EnemyService.isGoodSpawn(shore + Vector3.new(math.random(-8, 8), 0, math.random(-5, 3)))
				if ok then
					spot = ground
					break
				end
			end
			local e = aboard[k]
			if e then
				if not e.dead and e.aboard then
					leapAshore(r, e, spot)
				end
			else
				spawnRaider(r, typeId, spot)
			end
		end)
	end
	return #list * Raids.HOP_GAP + Raids.LEAP_TIME
end

-- The waves: the ships run aground and the vikings on deck leap ashore; then the ships row back
-- upriver, take the next wave aboard, and return with it WAVE_GAP after the previous landing.
local function runWaves(r)
	for index = 1, #r.tier.waves do
		if index > 1 then
			local landAt = r.landedAt + Raids.WAVE_GAP * (index - 1)
			r.nextWaveAt = landAt
			setAttributes()
			rowAll(r, false, Raids.SHIP_OUT_TIME)
			task.wait(Raids.SHIP_OUT_TIME)
			if raid ~= r then
				return
			end
			board(r, index)
			task.wait(math.max(0, landAt - Raids.SHIP_ROW_TIME - now()))
			if raid ~= r then
				return
			end
			rowAll(r, true, Raids.SHIP_ROW_TIME)
			task.wait(Raids.SHIP_ROW_TIME)
			if raid ~= r then
				return
			end
		end
		task.wait(unload(r, index) + 0.5)
		if raid ~= r then
			return
		end
		checkWon(r) -- (the whole wave might have been beaten on the way in)
	end
end

-- Axe throwers on deck throw at dragons who come close to the ships.
local function deckFight(r)
	while raid == r do
		local t = now()
		for e in pairs(r.raiders) do
			local def = e.def
			if e.aboard and not e.dead and def.throwCooldown and t >= e.nextThrow then
				local best, bestRoot, bestDist = nil, nil, def.throwRange
				for _, player in ipairs(Players:GetPlayers()) do
					local character, _, root = S.PlayerService.getCharacter(player)
					if character and not character:GetAttribute("Stealthed") then
						local d = (root.Position - e.root.Position).Magnitude
						if d <= bestDist then
							best, bestRoot, bestDist = player, root, d
						end
					end
				end
				if best then
					e.nextThrow = t + def.throwCooldown * (0.8 + math.random() * 0.4)
					S.EnemyService.throwAt(e, best, bestRoot, e.damage * def.throwDamage, def.look.weapon == "hammer" and "hammer" or "axe")
				end
			end
		end
		task.wait(0.4)
	end
end

---------------------------------------------------------------- a lost raid: back to the ships

-- A sack of loot slung over a raider's back.
local function lootSack(e)
	local s = e.scale
	local sack = Instance.new("Part")
	sack.Name = "LootSack"
	sack.Size = Vector3.new(1.9, 2.1, 1.6) * s
	sack.Color = Color3.fromRGB(160, 120, 70)
	sack.Material = Enum.Material.Fabric
	sack.CanCollide = false
	sack.CanQuery = false
	sack.CanTouch = false
	sack.Massless = true
	sack.CFrame = e.root.CFrame * CFrame.new(0, 0.9 * s, 1.3 * s)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = sack
	local gold = Instance.new("Part")
	gold.Name = "Gold"
	gold.Size = Vector3.new(1, 0.5, 0.9) * s
	gold.Color = Color3.fromRGB(255, 205, 60)
	gold.Material = Enum.Material.Neon
	gold.CanCollide = false
	gold.CanQuery = false
	gold.CanTouch = false
	gold.Massless = true
	gold.CFrame = sack.CFrame * CFrame.new(0, 1.05 * s, 0)
	for _, p in ipairs({ sack, gold }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = e.root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = e.model
	end
end

-- Leap from the beach onto a docked ship's deck.
local function leapAboard(r, e, s: number)
	local ship = r.ships[s]
	local keel = ship and ship.Parent and ship.PrimaryPart
	if not keel then
		return
	end
	r.riders[s] = (r.riders[s] or 0) + 1
	local deck = deckSpot(keel, (r.riders[s] - 1) % Raids.PASSENGERS + 1, Raids.PASSENGERS)
	local lift = e.humanoid.HipHeight + e.root.Size.Y / 2
	arc(e, e.root.Position, deck + Vector3.new(0, lift, 0), function()
		if ship.Parent then
			putAboard(e, ship, deck)
		end
	end)
end

-- One raider runs back to the beach: along the streets to the shore by the nearer ship, then
-- aboard as soon as the ship is back at the beach.
runBack = function(r, e)
	e.retreating = true
	e.customAI = true
	e.target = nil
	e.hunting = nil
	e.goal = nil
	e.torchUntil = nil
	e.humanoid.WalkSpeed = e.baseSpeed * Raids.RETREAT_SPEED
	lootSack(e)
	local here = e.root.Position
	local s, best = 1, math.huge
	for i, landing in ipairs(Raids.Landings) do
		local d = flat(here, landing.shore)
		if d < best then
			s, best = i, d
		end
	end
	local shore = Raids.Landings[s].shore
	local route = {}
	if here.Z < S.CivilianService.nodePos(Raids.ENTRY_NODE).Z then
		local start = S.CivilianService.nearestNode(here, true)
		table.insert(route, S.CivilianService.nodePos(start))
		for _, name in ipairs(S.CivilianService.route(start, Raids.ENTRY_NODE)) do
			table.insert(route, S.CivilianService.nodePos(name))
		end
	end
	table.insert(route, shore)
	local legStart, lastPush = os.clock(), 0
	while route[1] and not e.dead and e.model.Parent and os.clock() < r.retreatUntil do
		local step = route[1]
		local d = flat(e.root.Position, step)
		if d < 4 then
			table.remove(route, 1)
			legStart, lastPush = os.clock(), 0
		else
			if os.clock() - lastPush > 2 then
				lastPush = os.clock()
				e.humanoid:MoveTo(step)
			end
			if os.clock() - legStart > d / math.max(6, e.humanoid.WalkSpeed) + 6 then
				-- held up by something (a lamp post, a lair fence): hop past it
				local lift = e.humanoid.HipHeight + e.root.Size.Y / 2 + 0.5
				e.model:PivotTo(CFrame.new(S.EnemyService.terrainGround(step) + Vector3.new(0, lift, 0)) * e.root.CFrame.Rotation)
				legStart = os.clock()
			end
		end
		task.wait(0.2)
	end
	if e.dead or not e.model.Parent or route[1] then
		return
	end
	e.humanoid:MoveTo(e.root.Position)
	while not r.docked[s] and os.clock() < r.retreatUntil and not e.dead and e.model.Parent do
		task.wait(0.3)
	end
	if r.docked[s] and not e.dead and e.model.Parent then
		leapAboard(r, e, s)
	end
end

-- The raiders still standing make off with the loot: the ships come back to the beach (if they
-- were away), everyone ashore runs for them and leaps aboard, and off they row. Anyone still
-- ashore after Raids.RETREAT_TIME vanishes in a puff.
local function retreat(r)
	r.retreating = true
	r.retreatUntil = os.clock() + Raids.RETREAT_TIME
	for i, ship in ipairs(r.ships) do
		local landing = Raids.Landings[i]
		if ship.Parent and ship.PrimaryPart and not r.docked[i] then
			local seconds = math.max(3, math.abs(landing.shipX - shipX(ship)) / Raids.SHIP_SPEED)
			rowTo(ship, landing.shipX, SHIP_SIDE, seconds, function()
				r.docked[i] = true
			end)
		end
	end
	for e in pairs(r.raiders) do
		if not e.dead and e.model.Parent and not e.aboard and not e.leaping then
			task.spawn(runBack, r, e)
		end
	end
	local function ashore(): boolean
		for e in pairs(r.raiders) do
			if not e.dead and e.model.Parent and not e.aboard then
				return true
			end
		end
		return false
	end
	while ashore() and os.clock() < r.retreatUntil do
		task.wait(0.5)
	end
	for e in pairs(r.raiders) do
		if not e.dead and e.model.Parent and not e.aboard then
			S.CombatService.broadcastVFX({ kind = "enemyDeath", pos = e.root.Position })
			S.EnemyService.despawn(e)
		end
	end
	task.wait(1.5)
	sailAway(r)
end

---------------------------------------------------------------- the raid

local function reward(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	local R = Raids.Rewards
	local need = profile.level >= Game.LEVEL_CAP and Game.paragonXp(profile.paragon or 0) or Game.xpToNext(profile.level)
	local gold = R.gold.base + R.gold.perLevel * profile.level
	local rewards = { xp = need * R.xpShare, gold = gold }
	local extras = {}
	if math.random() < R.gearChance then
		rewards.gear = { rarity = R.gearRarity }
		table.insert(extras, R.gearRarity .. " gear")
	end
	if math.random() < R.eggChance then
		local egg = S.LootService.rollEgg(0.3)
		rewards.eggs = { [egg] = 1 }
		table.insert(extras, "an egg")
	end
	profile.raidsRepelled = (profile.raidsRepelled or 0) + 1
	profile.treats = (profile.treats or 0) + R.treats
	S.LootService.grant(player, rewards)
	S.PlayerService.markDirty(player)
	S.PlayerService.notify(player, string.format("Raid reward: %s gold, XP and %d Pet Treats%s!", Util.formatNumber(gold), R.treats,
		#extras > 0 and (", plus " .. table.concat(extras, " and ")) or ""), Color3.fromRGB(255, 215, 90), "🎁")
end

endRaid = function(won: boolean, reason: string?)
	local r = raid
	if not r then
		return
	end
	raid = nil
	S.CivilianService.setRaid(false)
	clearWater()
	for index, h in pairs(houses) do
		if h.state == "burning" then
			if won then
				extinguish(index) -- the villagers put out what's left
			else
				burnDown(index)
			end
		end
		if h.state == "burned" then
			h.rebuildAt = now() + Raids.REBUILD
		end
	end
	setAttributes()
	if won then
		for e in pairs(r.raiders) do
			if not e.dead then
				S.EnemyService.despawn(e) -- (an admin ending it early)
			end
		end
		sailAway(r)
		broadcast("🎉 RAID REPELLED!", "Dragon Town is safe! Everyone who helped gets a reward.", Color3.fromRGB(140, 235, 120))
		for player, score in pairs(r.contrib) do
			if player.Parent and score > 0 then
				reward(player)
			end
		end
	else
		task.spawn(retreat, r)
		local why = ({ burned = "Too many houses burned!", time = "The raiders held out and ran off with the loot!" })[reason or ""] or "The raiders got away with the loot!"
		broadcast("🔥 THE MARKET WAS LOOTED", string.format("%s The shops are closed for %s.", why, Util.formatTime(Raids.SHOPS_CLOSED)), Color3.fromRGB(255, 110, 80))
		S.ShopService.close(Raids.SHOPS_CLOSED)
	end
end

local function land(r)
	if raid ~= r then
		return
	end
	r.phase = "fighting"
	r.landedAt = now()
	-- the raid's own clock: time to fight after the last wave lands (dawn doesn't end it)
	r.endsAt = r.landedAt + Raids.WAVE_GAP * (#r.tier.waves - 1) + Raids.FIGHT_TIME
	S.CivilianService.setRaid(true)
	setAttributes()
	task.spawn(runWaves, r)
	task.spawn(giversFight, r)
end

-- Start a raid now (nightfall roll, or an admin). Returns ok, message.
function RaidService.begin(): (boolean, string)
	if raid then
		return false, "A raid is already under way."
	end
	local list = defenders()
	if #list == 0 then
		return false, "Nobody is here to defend the town."
	end
	local levels, top = 0, 1
	for _, player in ipairs(list) do
		local level = S.PlayerService.getProfile(player).level
		levels += level
		top = math.max(top, level)
	end
	local tier = Raids.tierFor(top)
	raidCounter += 1
	local t = now()
	local r = {
		id = raidCounter,
		phase = "incoming",
		landsAt = t + Raids.WARNING,
		tier = tier,
		level = math.clamp(math.floor(levels / #list + 0.5) - tier.levelBelow, Raids.LEVEL_RANGE[1], Raids.LEVEL_RANGE[2]),
		players = #list,
		scale = math.min(Raids.MAX_SCALE, 1 + Raids.EXTRA_PER_PLAYER * (#list - 1)),
		wave = 0,
		boarded = 0,
		left = 0,
		total = 0,
		burned = 0,
		raiders = {},
		contrib = {},
		ships = {},
		docked = {},
		riders = {},
	}
	raid = r
	quietNights = 0
	pendingRaid = false
	launchShips(r)
	board(r, 1)
	rowAll(r, true, Raids.SHIP_ROW_TIME)
	setAttributes()
	task.spawn(deckFight, r)
	broadcast("⚔️ VIKING RAID!", "Longships on the river! Fly out and fight them, then defend Dragon Town!", Color3.fromRGB(255, 120, 60), 7)
	task.delay(Raids.WARNING, function()
		land(r)
	end)
	return true, string.format("Raid started (level %d, %d defender%s).", r.level, #list, #list == 1 and "" or "s")
end

-- Admin: end the raid now.
function RaidService.stop(won: boolean): (boolean, string)
	if not raid then
		return false, "There's no raid."
	end
	endRaid(won, "admin")
	return true, won and "Raid ended: repelled." or "Raid ended: lost."
end

function RaidService.isActive(): boolean
	return raid ~= nil
end

-- Raiders ashore and fighting (not the ones still on deck or in mid-leap).
function RaidService.raiders()
	local list = {}
	if raid then
		for e in pairs(raid.raiders) do
			if not e.dead and e.model.Parent and not e.aboard and not e.leaping then
				table.insert(list, e)
			end
		end
	end
	return list
end

-- Raiders standing on the ships' decks.
function RaidService.aboard()
	local list = {}
	if raid then
		for e in pairs(raid.raiders) do
			if not e.dead and e.model.Parent and e.aboard then
				table.insert(list, e)
			end
		end
	end
	return list
end

-- For the villagers: the closest raider still standing.
function RaidService.nearestRaider(pos: Vector3)
	local best, bestDist = nil, 260
	for _, e in ipairs(RaidService.raiders()) do
		local d = flat(pos, e.root.Position)
		if d < bestDist then
			best, bestDist = e, d
		end
	end
	return best
end

-- How low villager and quest giver fire can take this raider: Raids.VILLAGER_FLOOR of its health
-- when it lands, wearing away to nothing the longer it's been ashore.
function RaidService.villagerFloor(e): number
	local _, finishAfter = Raids.villagerHelp(#defenders())
	local age = now() - (e.landedAt or now())
	return Raids.VILLAGER_FLOOR * math.clamp(1 - age / finishAfter, 0, 1)
end

-- A puff of fire from a villager or a quest giver (`model`, breathing like a `classId` dragon)
-- at a raider: `share` of its max health, boosted when few dragons are online.
local function puff(model: Model, classId: string, e, share: number)
	if e.dead or not e.model.Parent then
		return
	end
	local head = model:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	local from = mouth and mouth.WorldPosition or model:GetPivot().Position
	local dir = e.root.Position - from
	if dir.Magnitude < 0.1 then
		return
	end
	S.CombatService.broadcastVFX({ kind = "breath", character = model, dir = dir.Unit, classId = classId, duration = 0.7 })
	local boost = Raids.villagerHelp(#defenders())
	local max = e.humanoid.MaxHealth
	local floor = RaidService.villagerFloor(e)
	local amount = math.min(max * share * boost, e.humanoid.Health - max * floor)
	if amount >= 1 or (floor <= 0 and amount > 0) then
		S.CombatService.damageEnemy(nil, e, amount, false)
	end
end

-- A villager's little puff of fire.
function RaidService.villagerPuff(v, e)
	puff(v.model, v.def.plan, e, Raids.VILLAGER_DAMAGE)
end

---------------------------------------------------------------- quest givers join in

-- The quest givers stay at their posts and breathe fire at the nearest raider in reach, turning
-- to face it (and back to face the plaza once the raid is over).
giversFight = function(r)
	local homes = {} -- [model] = where it faced before the raid
	local nextPuff = {}
	while raid == r do
		if r.phase == "fighting" then
			for _, model in ipairs(CollectionService:GetTagged("QuestGiver")) do
				local root = model.PrimaryPart
				local giver = Quests.Givers[model:GetAttribute("GiverId") or ""]
				if root and giver and os.clock() >= (nextPuff[model] or 0) then
					local e = RaidService.nearestRaider(root.Position)
					if e and flat(root.Position, e.root.Position) <= Raids.ELDER_RANGE then
						nextPuff[model] = os.clock() + Raids.ELDER_INTERVAL * (0.85 + math.random() * 0.3)
						local pivot = model:GetPivot()
						if not homes[model] then
							homes[model] = pivot
							S.CivilianService.speak(root, 15, Raids.ELDER_LINES[math.random(1, #Raids.ELDER_LINES)]) -- (over its name and marker)
						end
						model:PivotTo(CFrame.lookAt(pivot.Position, Vector3.new(e.root.Position.X, pivot.Position.Y, e.root.Position.Z)))
						puff(model, giver.look, e, Raids.ELDER_DAMAGE)
					end
				end
			end
		end
		task.wait(0.3)
	end
	for model, pivot in pairs(homes) do
		if model.Parent then
			model:PivotTo(pivot)
		end
	end
end

local function onNightfall()
	if raid or #defenders() == 0 then
		return -- empty servers don't count toward the guarantee
	end
	if quietNights >= Raids.PITY_NIGHTS or math.random() < Raids.CHANCE then
		if S.BossService.isBusy() then
			pendingRaid = true -- after the boss (see the loop below)
		else
			RaidService.begin()
		end
	else
		quietNights += 1
	end
end

function RaidService.isPending(): boolean
	return pendingRaid
end

function RaidService.quietNights(): number
	return quietNights
end

function RaidService.init(services)
	S = services
	shipFolder = Instance.new("Folder")
	shipFolder.Name = "RaidShips"
	shipFolder.Parent = workspace
	riverSamples = Util.spline(Zones.River.points, 4)
end

function RaidService.start()
	local map = workspace:WaitForChild("Map")
	local town = map:WaitForChild("Town")
	enemyFolder = workspace:WaitForChild("Enemies")
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	terrainParams.IgnoreWater = false
	for index in ipairs(Zones.Houses) do
		local model = town:FindFirstChild("House" .. index)
		if model then
			-- the floor: the bottom of the lowest part (the foundation sits on the ground)
			local baseY = math.huge
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					baseY = math.min(baseY, d.Position.Y - d.Size.Y / 2)
				end
			end
			houses[index] = { model = model, state = "ok", baseY = baseY < math.huge and baseY or 0 }
		end
	end
	for index, pos in ipairs(Zones.Wells) do
		local model = town:FindFirstChild("Well" .. index)
		local tag = model and model:FindFirstChild("WellTag", true)
		table.insert(wells, { ground = (S.EnemyService.terrainGround(pos)), tag = tag })
	end
	setAttributes()
	S.DayNightService.nightfall:Connect(onNightfall)
	S.DayNightService.daybreak:Connect(function()
		pendingRaid = false -- (a raid under way carries on into the morning: it keeps its own clock)
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(waterTick)
			if not ok then
				warn("[RaidService] water:", err)
				task.wait(2)
			end
		end
	end)
	while true do
		task.wait(0.5)
		local t = now()
		for index, h in pairs(houses) do
			if h.state == "burning" and h.burnsAt then
				if t >= h.burnsAt then
					burnDown(index)
				end
			elseif h.state == "burned" and h.rebuildAt and t >= h.rebuildAt then
				rebuild(index)
			end
		end
		local burning = anyBurning()
		for _, well in ipairs(wells) do
			if well.tag and well.tag.Enabled ~= burning then
				well.tag.Enabled = burning
			end
		end
		if raid and raid.endsAt and t >= raid.endsAt then
			endRaid(false, "time")
		end
		if pendingRaid and not raid and not S.BossService.isBusy() then
			pendingRaid = false
			if S.DayNightService.isNight() and S.DayNightService.untilChange() >= Raids.RAID_MIN_NIGHT then
				RaidService.begin()
			end
		end
	end
end

return RaidService
