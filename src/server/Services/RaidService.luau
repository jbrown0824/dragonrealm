-- Night raids on Dragon Town (Config/Raids). At nightfall DayNightService fires `nightfall` and
-- there's a Raids.CHANCE of a raid (always one after Raids.PITY_NIGHTS quiet nights in a row).
--
-- A raid: the war horn sounds and longships row down the river (Raids.WARNING) with the first
-- wave standing on deck, then the vikings hop ashore below town one after another. The size of
-- the raid follows the strongest dragon online (Raids.Tiers), so new players get a gentler one.
-- Raiders are ordinary EnemyService vikings flagged `raid` (so they can fight inside town) with
-- an `objective` (see "raider brains"): Torchbearers walk the villagers' street graph
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
-- A burning house burns down after the tier's burnTime unless a dragon holds E at its door. Beat
-- every raider before dawn to win: everyone who hit a raider or put out a fire gets the
-- rewards. Lose (dawn, or Raids.MAX_BURNED houses gone) and ShopService closes every vendor
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

local Enemies = require(Shared.Config.Enemies)
local Quests = require(Shared.Config.Quests)

local Props = require(script.Parent.Parent.World.Props)
local VikingBuilder = require(script.Parent.Parent.World.VikingBuilder)

local RaidService = {}
local S

local raid = nil -- the raid in progress (see RaidService.start)
local raidCounter = 0
local quietNights = 0
local pendingRaid = false -- rolled a raid while a boss was busy: it starts once the boss is done
local houses = {} -- [index] = { model, state = "ok" | "burning" | "burned", burnsAt, fx, original, rebuildAt }
local shipFolder: Folder
local riverSamples = {}

local endRaid: (won: boolean, reason: string?) -> () -- below; burning a house down can end the raid
local giversFight: (r: any) -> () -- below; the quest givers fight once the raiders land

local STREET_GOALS = { "PN", "PNE", "PE", "PSE", "PS", "PSW", "PW", "PNW", "N1", "N2", "N3", "E1", "E2", "W1", "S1" }
local CHAR = Color3.fromRGB(38, 32, 30)
local SHIP_SIDE = 9 -- a landed longship sits this far from the middle of the river, toward town
local SHIP_KEEL = CFrame.new(0, -2.4, 0) -- where Props.longship puts the keel (the ship's PrimaryPart)

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

local function clearFx(h)
	if h.fx then
		h.fx:Destroy()
		h.fx = nil
	end
end

-- Invisible anchors on the roof and over the door for the flames (or the smoke of a burned house).
local function addFx(index: number, burning: boolean)
	local h = houses[index]
	clearFx(h)
	local size = Zones.HouseSize
	local cf = houseCF(index)
	local fx = Instance.new("Folder")
	fx.Name = "FireFX"
	local spots = burning and { Vector3.new(-size.X * 0.28, size.Y + 5, 0), Vector3.new(size.X * 0.28, size.Y + 5, 2), Vector3.new(0, size.Y - 3, -size.Z / 2) }
		or { Vector3.new(-size.X * 0.2, size.Y + 3, 0), Vector3.new(size.X * 0.25, size.Y + 2, 3) }
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
		smoke.Color = burning and Color3.fromRGB(70, 60, 55) or Color3.fromRGB(110, 105, 100)
		smoke.Size = burning and 12 or 7
		smoke.RiseVelocity = 8
		smoke.Opacity = burning and 0.35 or 0.2
		smoke.Parent = anchor
		if burning then
			Props.fire(anchor, 14, Color3.fromRGB(255, 120, 40))
			Props.light(anchor, Color3.fromRGB(255, 140, 60), 40, 3)
		end
	end
	if burning then
		-- the prompt to beat out the flames, on the doorstep
		local door = Instance.new("Part")
		door.Name = "Doorstep"
		door.Anchored = true
		door.CanCollide = false
		door.CanQuery = false
		door.CanTouch = false
		door.Transparency = 1
		door.Size = Vector3.new(2, 2, 2)
		door.CFrame = CFrame.new(Zones.houseDoor(Zones.Houses[index]) + Vector3.new(0, 4, 0))
		door.Parent = fx
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Put out the fire"
		prompt.ObjectText = "Burning house"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = Raids.DOUSE_HOLD
		prompt.MaxActivationDistance = 20
		prompt.RequiresLineOfSight = false
		prompt.Parent = door
		prompt.Triggered:Connect(function(player)
			RaidService.douse(index, player)
		end)
		-- a countdown everyone can see from across town
		local gui = Instance.new("BillboardGui")
		gui.Name = "FireTag"
		gui.Size = UDim2.fromOffset(170, 36)
		gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y + 14, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 400
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
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
		local base = Instance.new("Part")
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
	end
	fx.Parent = h.model
	h.fx = fx
end

-- Soot-black walls, dark windows, cold fireplace. Remembers every part's look for the rebuild.
local function char(h)
	h.original = {}
	for _, d in ipairs(h.model:GetDescendants()) do
		if d:IsA("BasePart") then
			h.original[d] = { color = d.Color, material = d.Material }
			d.Color = d.Color:Lerp(CHAR, 0.8)
			if d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
		elseif d:IsA("Light") or d:IsA("Fire") then
			h.original[d] = { enabled = d.Enabled }
			d.Enabled = false
		end
	end
end

local function unchar(h)
	for d, look in pairs(h.original or {}) do
		if d.Parent then
			if look.color then
				d.Color = look.color
				d.Material = look.material
			else
				d.Enabled = look.enabled
			end
		end
	end
	h.original = nil
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
	addFx(index, true)
	notifyAll(string.format("A house is on fire! Hold E at its door to put it out (%ds).", burnTime), Color3.fromRGB(255, 150, 70), "🔥")
	return true
end

local function extinguish(index: number)
	local h = houses[index]
	h.state = "ok"
	h.burnsAt = nil
	h.tag = nil
	h.model:SetAttribute("Fire", nil)
	h.model:SetAttribute("BurnsAt", nil)
	clearFx(h)
end

function RaidService.douse(index: number, player: Player): boolean
	local h = houses[index]
	if not h or h.state ~= "burning" then
		return false
	end
	local _, _, root = S.PlayerService.getCharacter(player)
	if not root or flat(root.Position, Zones.houseDoor(Zones.Houses[index])) > 30 then
		return false
	end
	extinguish(index)
	S.CombatService.broadcastVFX({ kind = "douse", pos = houseCF(index).Position + Vector3.new(0, Zones.HouseSize.Y + 4, 0) })
	if raid then
		raid.contrib[player] = (raid.contrib[player] or 0) + 1
	end
	S.PlayerService.notify(player, "You beat out the flames! The house is saved.", Color3.fromRGB(140, 230, 140), "🧯")
	return true
end

local function burnDown(index: number)
	local h = houses[index]
	if h.state == "burned" then
		return
	end
	h.state = "burned"
	h.burnsAt = nil
	h.tag = nil
	h.model:SetAttribute("Fire", "burned")
	h.model:SetAttribute("BurnsAt", nil)
	clearFx(h)
	char(h)
	addFx(index, false)
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

-- Row a ship from where it is now to x `toX`, `toSide` studs toward the town bank, over
-- `seconds` (easing in to run aground gently), then call done. The keel is the ship's
-- PrimaryPart and sits SHIP_KEEL below the waterline frame the ship was built on.
local function rowTo(ship: Model, toX: number, toSide: number, seconds: number, done: (() -> ())?)
	local keel = ship.PrimaryPart
	if not keel then
		return
	end
	local here = (keel.CFrame * SHIP_KEEL:Inverse()).Position
	local fromX, fromSide = here.X, riverZ(here.X) - here.Z
	local heading = toX > fromX and 1 or -1
	task.spawn(function()
		local start = os.clock()
		while ship.Parent do
			local k = math.min(1, (os.clock() - start) / seconds)
			local e = 1 - (1 - k) * (1 - k)
			ship:PivotTo(shipCF(fromX + (toX - fromX) * e, heading, fromSide + (toSide - fromSide) * e) * SHIP_KEEL)
			if k >= 1 then
				break
			end
			task.wait() -- every frame: only the keel moves (everything else is welded to it)
		end
		if done then
			done()
		end
	end)
end

local function rowAll(r, inbound: boolean, seconds: number)
	for i, ship in ipairs(r.ships) do
		local landing = Raids.Landings[i]
		if inbound then
			rowTo(ship, landing.shipX, SHIP_SIDE, seconds)
		else
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

-- The wave's vikings stand on the decks in two rows, cheering (the Animator waves their arms:
-- tag "VikingPassenger"). They're only for show (no Humanoid): each one leaps ashore and turns
-- into the real raider where it lands. r.waveList keeps the order so ships and landings agree.
local function board(r, index: number)
	local list = waveList(r, index)
	r.waveList = list
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
			local slots = math.ceil(count / 2)
			local frame = keel.CFrame * SHIP_KEEL:Inverse() -- the ship's own frame at the waterline
			for i = 1, count do
				local typeId = mine[i].typeId
				local def = typeId == "leader" and Enemies.Vikings[Raids.Captain.base] or Enemies.Vikings[typeId]
				local look = typeId == "leader" and Raids.Captain.look or def.look
				local scale = typeId == "leader" and Raids.Captain.scale or def.scale
				local model = VikingBuilder.build(look, scale, "Passenger")
				local slot = math.ceil(i / 2)
				local along = slots > 1 and (-9 + 18 * (slot - 1) / (slots - 1)) or 0
				local deck = (frame * CFrame.new(i % 2 == 0 and 1.3 or -1.3, 0.6, along)).Position
				local pos = deck + Vector3.new(0, 3.05 * scale, 0)
				model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
				model:SetAttribute("Order", mine[i].k)
				model:SetAttribute("Scale", scale)
				weldTo(model, keel)
				CollectionService:AddTag(model, "VikingPassenger")
				model.Parent = ship
			end
		end
	end
end

-- A spot on the beach for a raider to land on.
local function shoreSpot(landing): Vector3
	for _ = 1, 10 do
		local try = landing.shore + Vector3.new(math.random(-8, 8), 0, math.random(-5, 3))
		local ok, ground = S.EnemyService.isGoodSpawn(try)
		if ok then
			return ground
		end
	end
	return (S.EnemyService.terrainGround(landing.shore))
end

-- A passenger leaps off the deck in an arc and lands on the beach at `to`, then `done` runs.
local function leap(passenger: Model, to: Vector3, done: () -> ())
	local root = passenger.PrimaryPart
	root.Anchored = true
	for _, d in ipairs(passenger:GetDescendants()) do
		if d:IsA("WeldConstraint") and d.Name == "ShipWeld" then
			d:Destroy()
		end
	end
	passenger.Parent = shipFolder
	passenger:SetAttribute("Leaping", true)
	local from = passenger:GetPivot().Position
	local dest = to + Vector3.new(0, 3.05 * (passenger:GetAttribute("Scale") or 1), 0)
	local turn = CFrame.lookAt(from, Vector3.new(dest.X, from.Y, dest.Z)).Rotation
	task.spawn(function()
		local start = os.clock()
		while passenger.Parent do
			local k = math.min(1, (os.clock() - start) / Raids.LEAP_TIME)
			passenger:PivotTo(CFrame.new(from:Lerp(dest, k) + Vector3.new(0, Raids.LEAP_HEIGHT * 4 * k * (1 - k), 0)) * turn)
			if k >= 1 then
				break
			end
			task.wait()
		end
		S.CombatService.broadcastVFX({ kind = "thud", pos = to })
		passenger:Destroy()
		done()
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
	board(r, 1)
	rowAll(r, true, Raids.SHIP_ROW_TIME)
end

local function sailAway(ships)
	for i, ship in ipairs(ships) do
		local landing = Raids.Landings[i]
		if landing and ship.Parent then
			rowTo(ship, landing.fromX, 0, 25, function()
				ship:Destroy()
			end)
		else
			ship:Destroy()
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

local function onRaiderDeath(e)
	local r = raid
	if not r or not r.raiders[e] then
		return
	end
	for player, dealt in pairs(e.damageBy) do
		r.contrib[player] = (r.contrib[player] or 0) + dealt
	end
	r.left = math.max(0, r.left - 1)
	setAttributes()
	if r.wave >= #r.tier.waves and r.left == 0 then
		endRaid(true)
	end
end

local function spawnRaider(r, typeId: string, pos: Vector3, opts)
	opts = opts or {}
	opts.raid = true
	opts.leash = 5000
	opts.objective = objective
	opts.onDeath = onRaiderDeath
	local e = S.EnemyService.spawn(typeId, opts.level or r.level, pos, opts)
	if e then
		e.role = typeId == "Torchbearer" and "torch" or "fighter"
		e.landedAt = now()
		r.raiders[e] = true
	else
		r.left = math.max(0, r.left - 1)
	end
	return e
end

local function spawnCaptain(r, pos: Vector3)
	local c = Raids.Captain
	return spawnRaider(r, c.base, pos, {
		level = math.min(Game.LEVEL_CAP, r.level + 2),
		displayName = c.name,
		scale = c.scale,
		look = c.look,
		healthMult = r.tier.captainHealth + c.healthPerPlayer * (r.players - 1),
		damageMult = c.damageMult,
		slam = c.slam,
	})
end

-- The wave on deck leaps ashore one viking after another. Returns how long that takes.
local function unload(r, index: number): number
	local list = r.waveList or waveList(r, index)
	r.waveList = nil
	r.wave = index
	r.nextWaveAt = nil
	r.left += #list -- counted now, so the raid can't be won while some are still jumping
	r.total += #list
	setAttributes()
	if index > 1 then
		notifyAll(string.format("Wave %d of %d is coming ashore!", index, #r.tier.waves), Color3.fromRGB(255, 170, 90), "⛵")
	end
	local passengers = {}
	for _, ship in ipairs(r.ships) do
		for _, child in ipairs(ship:GetChildren()) do
			if child.Name == "Passenger" then
				passengers[child:GetAttribute("Order")] = child
			end
		end
	end
	for k, typeId in ipairs(list) do
		task.delay((k - 1) * Raids.HOP_GAP, function()
			if raid ~= r then
				return
			end
			local landing = Raids.Landings[shipFor(k)]
			local spot = shoreSpot(landing)
			local function arrive()
				if raid ~= r then
					return
				end
				if typeId == "leader" then
					spawnCaptain(r, spot)
				else
					spawnRaider(r, typeId, spot)
				end
			end
			local passenger = passengers[k]
			if passenger and passenger.Parent then
				leap(passenger, spot, arrive)
			else
				arrive() -- more raiders than room on deck: they wade in
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
	end
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
	-- whoever is still standing sails off with their loot
	for e in pairs(r.raiders) do
		if not e.dead then
			S.EnemyService.despawn(e)
		end
	end
	sailAway(r.ships)
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
		broadcast("🎉 RAID REPELLED!", "Dragon Town is safe! Everyone who helped gets a reward.", Color3.fromRGB(140, 235, 120))
		for player, score in pairs(r.contrib) do
			if player.Parent and score > 0 then
				reward(player)
			end
		end
	else
		local why = ({ burned = "The village burned!", dawn = "Dawn broke with raiders in town!" })[reason or ""] or "The raiders got away with the loot!"
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
		endsAt = t + (S.DayNightService.isNight() and S.DayNightService.untilChange() or Game.NIGHT_SECONDS),
		tier = tier,
		level = math.clamp(math.floor(levels / #list + 0.5) - tier.levelBelow, Raids.LEVEL_RANGE[1], Raids.LEVEL_RANGE[2]),
		players = #list,
		scale = math.min(Raids.MAX_SCALE, 1 + Raids.EXTRA_PER_PLAYER * (#list - 1)),
		wave = 0,
		left = 0,
		total = 0,
		burned = 0,
		raiders = {},
		contrib = {},
		ships = {},
	}
	raid = r
	quietNights = 0
	pendingRaid = false
	setAttributes()
	launchShips(r)
	broadcast("⚔️ VIKING RAID!", "Longships on the river! Fly home and defend Dragon Town!", Color3.fromRGB(255, 120, 60), 7)
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
	if won then
		for e in pairs(raid.raiders) do
			if not e.dead then
				S.EnemyService.despawn(e)
			end
		end
	end
	endRaid(won, "admin")
	return true, won and "Raid ended: repelled." or "Raid ended: lost."
end

function RaidService.isActive(): boolean
	return raid ~= nil
end

function RaidService.raiders()
	local list = {}
	if raid then
		for e in pairs(raid.raiders) do
			if not e.dead and e.model.Parent then
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
	local town = workspace:WaitForChild("Map"):WaitForChild("Town")
	for index in ipairs(Zones.Houses) do
		local model = town:FindFirstChild("House" .. index)
		if model then
			houses[index] = { model = model, state = "ok" }
		end
	end
	setAttributes()
	S.DayNightService.nightfall:Connect(onNightfall)
	S.DayNightService.daybreak:Connect(function()
		pendingRaid = false
		if raid then
			endRaid(false, "dawn")
		end
	end)
	while true do
		task.wait(0.5)
		local t = now()
		for index, h in pairs(houses) do
			if h.state == "burning" and h.burnsAt then
				if t >= h.burnsAt then
					burnDown(index)
				elseif h.tag then
					h.tag.Text = string.format("🔥 On fire! %ds", math.ceil(h.burnsAt - t))
				end
			elseif h.state == "burned" and h.rebuildAt and t >= h.rebuildAt then
				rebuild(index)
			end
		end
		if raid and t >= raid.endsAt then
			endRaid(false, "dawn")
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
