-- Night raids on Dragon Town (Config/Raids). At nightfall DayNightService fires `nightfall` and
-- there's a Raids.CHANCE of a raid (always one after Raids.PITY_NIGHTS quiet nights in a row).
--
-- A raid: the war horn sounds and longships row down the river (Raids.WARNING), then waves of
-- vikings come ashore below town. They're ordinary EnemyService vikings flagged `raid` (so they
-- can fight inside town) with an `objective`: Torchbearers walk the villagers' street graph
-- (Zones.TownWalk, via CivilianService) to a house door and set it alight; everyone else roams
-- the streets looking for a fight. Villagers come out and puff fire at them (CivilianService).
--
-- A burning house burns down after Raids.BURN_TIME unless a dragon holds E at its door. Beat
-- every raider before dawn to win: everyone who hit a raider or put out a fire gets the
-- rewards. Lose (dawn, or Raids.MAX_BURNED houses gone) and ShopService closes every vendor
-- for a while. Burned houses are rebuilt Raids.REBUILD seconds after the raid either way.
--
-- Clients follow along through workspace attributes (UI/RaidUI): RaidPhase ("incoming" /
-- "fighting"), RaidLandsAt, RaidEndsAt, RaidLeft, RaidWave, RaidWaves, HousesBurned,
-- RaidMaxBurned. Each house model carries Fire ("burning" / "burned") and BurnsAt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Raids = require(Shared.Config.Raids)
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Props = require(script.Parent.Parent.World.Props)

local RaidService = {}
local S

local raid = nil -- the raid in progress (see RaidService.start)
local raidCounter = 0
local quietNights = 0
local houses = {} -- [index] = { model, state = "ok" | "burning" | "burned", burnsAt, fx, original, rebuildAt }
local shipFolder: Folder
local riverSamples = {}

local endRaid: (won: boolean, reason: string?) -> () -- below; burning a house down can end the raid

local STREET_GOALS = { "PN", "PNE", "PE", "PSE", "PS", "PSW", "PW", "PNW", "N1", "N2", "N3", "E1", "E2", "W1", "S1" }
local CHAR = Color3.fromRGB(38, 32, 30)

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
	workspace:SetAttribute("RaidWaves", r and #Raids.Waves or nil)
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
	h.state = "burning"
	h.burnsAt = now() + Raids.BURN_TIME
	h.model:SetAttribute("Fire", "burning")
	h.model:SetAttribute("BurnsAt", h.burnsAt)
	addFx(index, true)
	notifyAll(string.format("A house is on fire! Hold E at its door to put it out (%ds).", Raids.BURN_TIME), Color3.fromRGB(255, 150, 70), "🔥")
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

local function shipCF(x: number, heading: number): CFrame
	local pos = Vector3.new(x, Zones.WATER_LEVEL, riverZ(x))
	local ahead = Vector3.new(x + heading * 3, Zones.WATER_LEVEL, riverZ(x + heading * 3))
	return CFrame.lookAt(pos, ahead)
end

-- Row a ship from x `a` to x `b` along the river over `seconds`, then call done.
local function row(ship: Model, a: number, b: number, seconds: number, done: (() -> ())?)
	task.spawn(function()
		local heading = b > a and 1 or -1
		local start = os.clock()
		while ship.Parent do
			local k = math.min(1, (os.clock() - start) / seconds)
			local e = 1 - (1 - k) * (1 - k) -- slow down as they run aground
			ship:PivotTo(shipCF(a + (b - a) * e, heading))
			if k >= 1 then
				break
			end
			task.wait(0.1)
		end
		if done then
			done()
		end
	end)
end

local function launchShips(r)
	for _, landing in ipairs(Raids.Landings) do
		local heading = landing.shipX > landing.fromX and 1 or -1
		local ship = Props.longship(shipFolder, shipCF(landing.fromX, heading))
		-- weld the whole ship to its keel, so rowing moves (and replicates) one part, not ~110
		local keel = nil
		for _, d in ipairs(ship:GetDescendants()) do
			if d:IsA("BasePart") and (not keel or d.Size.Z > keel.Size.Z) then
				keel = d
			end
		end
		ship.PrimaryPart = keel
		for _, d in ipairs(ship:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				if d ~= keel then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = keel
					weld.Part1 = d
					weld.Parent = d
					d.Massless = true
					d.Anchored = false
				end
			end
		end
		table.insert(r.ships, ship)
		row(ship, landing.fromX, landing.shipX, Raids.SHIP_ROW_TIME)
	end
end

local function sailAway(ships)
	for i, ship in ipairs(ships) do
		local landing = Raids.Landings[i]
		if landing and ship.Parent then
			row(ship, landing.shipX, landing.fromX, 25, function()
				ship:Destroy()
			end)
		else
			ship:Destroy()
		end
	end
end

---------------------------------------------------------------- raider brains

-- The nearest standing house (not already someone else's target, if there's a choice).
local function pickHouse(e): number?
	local best, bestDist, bestTaken = nil, math.huge, true
	for index, h in pairs(houses) do
		if h.state == "ok" then
			local taken = false
			for other in pairs(raid.raiders) do
				if other ~= e and not other.dead and other.house == index then
					taken = true
				end
			end
			local d = flat(e.root.Position, Zones.houseDoor(Zones.Houses[index])) + math.random() * 20
			if (bestTaken and not taken) or (taken == bestTaken and d < bestDist) then
				best, bestDist, bestTaken = index, d, taken
			end
		end
	end
	return best
end

local function planRoute(e, t: number)
	local start = S.CivilianService.nearestNode(e.root.Position, true)
	local goal = nil
	e.house = nil
	if e.role == "torch" then
		e.house = pickHouse(e)
		if e.house then
			goal = "Door" .. e.house
		end
	end
	goal = goal or STREET_GOALS[math.random(1, #STREET_GOALS)]
	local route = { S.CivilianService.nodePos(start) }
	for _, name in ipairs(S.CivilianService.route(start, goal)) do
		table.insert(route, S.CivilianService.nodePos(name))
	end
	e.route = route
	e.legStart = t
end

local function arrive(e, t: number)
	local h = e.house and houses[e.house]
	if e.role == "torch" and h and h.state == "ok" then
		e.torchUntil = t + Raids.TORCH_TIME
		e.model:SetAttribute("Swing", os.clock())
		local door = Zones.Houses[e.house].pos
		local here = e.root.Position
		e.root.CFrame = CFrame.lookAt(here, Vector3.new(door.X, here.Y, door.Z))
	else
		e.idleUntil = t + 2 + math.random() * 3
		e.route = nil
	end
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
			if e.house then
				RaidService.ignite(e.house)
			end
			e.house = nil
			e.route = nil
		end
		return true
	end
	if e.idleUntil and t < e.idleUntil then
		humanoid:MoveTo(e.root.Position)
		return true
	end
	if not e.route or #e.route == 0 then
		planRoute(e, t)
	end
	local goal = e.route[1]
	if not goal then
		return false
	end
	local dist = flat(e.root.Position, goal)
	if dist < 4 then
		table.remove(e.route, 1)
		e.legStart = t
		if #e.route == 0 then
			arrive(e, t)
		end
		return true
	end
	-- Humanoid:MoveTo gives up after 8 seconds, so keep nudging it, and hop past anything that
	-- has held a raider up for too long (a lamp post, a crowd of vikings).
	if t - (e.lastPush or 0) > 2 then
		e.lastPush = t
		humanoid:MoveTo(goal)
	end
	if t - e.legStart > dist / math.max(6, e.baseSpeed) + 8 then
		local lift = humanoid.HipHeight + e.root.Size.Y / 2 + 0.5
		e.model:PivotTo(CFrame.new(goal + Vector3.new(0, lift, 0)) * e.root.CFrame.Rotation)
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
	if r.wave >= #Raids.Waves and r.left == 0 then
		endRaid(true)
	end
end

local function spawnRaider(r, typeId: string, landing, opts)
	local pos = landing.shore
	for _ = 1, 10 do
		local try = landing.shore + Vector3.new(math.random(-8, 8), 0, math.random(-5, 3))
		if S.EnemyService.isGoodSpawn(try) then
			pos = try
			break
		end
	end
	opts = opts or {}
	opts.raid = true
	opts.leash = 5000
	opts.objective = objective
	opts.onDeath = onRaiderDeath
	local e = S.EnemyService.spawn(typeId, opts.level or r.level, pos, opts)
	if e then
		e.role = typeId == "Torchbearer" and "torch" or "fighter"
		r.raiders[e] = true
		r.left += 1
		r.total += 1
	end
	return e
end

local function spawnWave(r, index: number)
	local wave = Raids.Waves[index]
	r.wave = index
	local k = 0
	local types = {}
	for typeId, count in pairs(wave) do
		if typeId ~= "leader" then
			table.insert(types, { typeId, count })
		end
	end
	table.sort(types, function(a, b)
		return a[1] < b[1]
	end)
	for _, entry in ipairs(types) do
		for _ = 1, math.max(1, math.floor(entry[2] * r.scale + 0.5)) do
			k += 1
			spawnRaider(r, entry[1], Raids.Landings[(k % #Raids.Landings) + 1])
		end
	end
	if wave.leader then
		local c = Raids.Captain
		spawnRaider(r, c.base, Raids.Landings[1], {
			level = math.min(Game.LEVEL_CAP, r.level + 2),
			displayName = c.name,
			scale = c.scale,
			look = c.look,
			healthMult = c.healthMult + c.healthPerPlayer * (r.players - 1),
			damageMult = c.damageMult,
			slam = c.slam,
		})
	end
	setAttributes()
	if index > 1 then
		notifyAll(string.format("Wave %d of %d is coming ashore!", index, #Raids.Waves), Color3.fromRGB(255, 170, 90), "⛵")
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
	S.CivilianService.setRaid(true)
	spawnWave(r, 1)
	for i = 2, #Raids.Waves do
		task.delay(Raids.WAVE_GAP * (i - 1), function()
			if raid == r then
				spawnWave(r, i)
			end
		end)
	end
	setAttributes()
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
	local levels = 0
	for _, player in ipairs(list) do
		levels += S.PlayerService.getProfile(player).level
	end
	raidCounter += 1
	local t = now()
	local r = {
		id = raidCounter,
		phase = "incoming",
		landsAt = t + Raids.WARNING,
		endsAt = t + (S.DayNightService.isNight() and S.DayNightService.untilChange() or Game.NIGHT_SECONDS),
		level = math.clamp(math.floor(levels / #list + 0.5) - Raids.LEVEL_BELOW, Raids.LEVEL_RANGE[1], Raids.LEVEL_RANGE[2]),
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

-- A villager's little puff of fire.
function RaidService.villagerPuff(v, e)
	if e.dead or not e.model.Parent then
		return
	end
	local head = v.model:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	local from = mouth and mouth.WorldPosition or v.root.Position
	local dir = e.root.Position - from
	if dir.Magnitude < 0.1 then
		return
	end
	S.CombatService.broadcastVFX({ kind = "breath", character = v.model, dir = dir.Unit, classId = v.def.plan, duration = 0.7 })
	local max = e.humanoid.MaxHealth
	local amount = math.min(max * Raids.VILLAGER_DAMAGE, e.humanoid.Health - max * Raids.VILLAGER_FLOOR)
	if amount >= 1 then
		S.CombatService.damageEnemy(nil, e, amount, false)
	end
end

local function onNightfall()
	if raid or #defenders() == 0 then
		return -- empty servers don't count toward the guarantee
	end
	if quietNights >= Raids.PITY_NIGHTS or math.random() < Raids.CHANCE then
		RaidService.begin()
	else
		quietNights += 1
	end
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
	end
end

return RaidService
