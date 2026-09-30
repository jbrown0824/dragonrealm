-- Map layout. The world is generated in code from these positions (server/World/WorldBuilder),
-- and the same numbers drive zone detection, PvP, enemy camps and safe areas.
-- Coordinates are studs; y = 0 is ground level.

local Dungeons = require(script.Parent.Dungeons)

local Zones = {}

Zones.SPAWN = Vector3.new(0, 7, 32)

-- Areas used for zone names on screen, PvP and safety. Checked in order: first match wins.
-- shape "box": min/max on X and Z. shape "circle": center + radius (X/Z).
Zones.Areas = {
	{ id = "BattleZone", name = "Battle Zone", subtitle = "PvP enabled — other dragons can attack you!", shape = "box",
		min = Vector3.new(-95, -50, -335), max = Vector3.new(95, 180, -195), pvp = true, safe = false, color = Color3.fromRGB(255, 80, 80) },
	{ id = "Town", name = "Dragon Town", subtitle = "Safe haven of the dragons", shape = "box",
		min = Vector3.new(-280, -50, -360), max = Vector3.new(280, 300, 248), safe = true, color = Color3.fromRGB(255, 210, 120) },
	{ id = "RaiderCamp", name = "Raider Camp", subtitle = "Level 1 - 4", shape = "circle",
		center = Vector3.new(0, 0, 430), radius = 95, color = Color3.fromRGB(220, 220, 220) },
	{ id = "FishingVillage", name = "Fishing Village", subtitle = "Level 5 - 10", shape = "circle",
		center = Vector3.new(-310, 0, 580), radius = 110, color = Color3.fromRGB(120, 230, 120) },
	{ id = "LonghouseHold", name = "Longhouse Hold", subtitle = "Level 10 - 17", shape = "circle",
		center = Vector3.new(310, 0, 620), radius = 110, color = Color3.fromRGB(110, 170, 255) },
	{ id = "JarlsFortress", name = "Jarl's Fortress", subtitle = "Level 18 - 28", shape = "circle",
		center = Vector3.new(0, 0, 920), radius = 130, color = Color3.fromRGB(200, 110, 255) },
	{ id = "ElkMeadows", name = "Elk Meadows", subtitle = "Hunting grounds • Level 1 - 5", shape = "box",
		min = Vector3.new(-560, -50, -420), max = Vector3.new(-280, 300, 248), color = Color3.fromRGB(170, 230, 120) },
	{ id = "Whisperwood", name = "Whisperwood", subtitle = "Hunting grounds • Level 3 - 8", shape = "box",
		min = Vector3.new(280, -50, -420), max = Vector3.new(560, 300, 248), color = Color3.fromRGB(120, 200, 140) },
	{ id = "BearclawHollow", name = "Bearclaw Hollow", subtitle = "Hunting grounds • Level 12 - 20", shape = "box",
		min = Vector3.new(-560, -50, 740), max = Vector3.new(-180, 300, 1120), color = Color3.fromRGB(200, 160, 110) },
	{ id = "FrostfangRidge", name = "Frostfang Ridge", subtitle = "Frost wolves and bears • Level 16 - 24", shape = "box",
		min = Vector3.new(250, -50, 760), max = Vector3.new(560, 300, 1120), color = Color3.fromRGB(190, 230, 255) },
	{ id = "VikingLands", name = "Viking Lands", subtitle = "Danger! Vikings roam here", shape = "box",
		min = Vector3.new(-560, -50, 248), max = Vector3.new(560, 300, 1120), color = Color3.fromRGB(255, 150, 90) },
	{ id = "BossArena", name = "Boss Arena", subtitle = "Defeat the boss before time runs out!", shape = "circle",
		center = Vector3.new(3000, 0, 0), radius = 150, color = Color3.fromRGB(255, 60, 60) },
}

-- Anything outside all of these boxes gets teleported home (keeps flyers on the map).
Zones.WorldBounds = { min = Vector3.new(-560, -60, -420), max = Vector3.new(560, 320, 1120) }

Zones.BossArena = {
	center = Vector3.new(3000, 0, 0),
	radius = 110,
	wallHeight = 90,
}

-- Viking camps. EnemyService spawns `spawns` around `center` within `radius`.
--   chest:  the treasure chest in the middle (hold = seconds to open; starting to open it
--           alerts every viking in the camp). Rewards scale with the camp's levels.
--   boss:   where the camp's mini-boss (Enemies.MiniBosses[id]) stands guard
--   alarm:  Hornblowers here sound a horn that sends the whole camp after you
Zones.Camps = {
	{ id = "RaiderCamp", name = "Raider Camp", center = Vector3.new(0, 0, 430), radius = 60, levels = { 1, 4 },
		spawns = { Raider = 9 },
		chest = { hold = 4 }, boss = Vector3.new(-32, 0, -4) },
	{ id = "FishingVillage", name = "Fishing Village", center = Vector3.new(-310, 0, 580), radius = 70, levels = { 5, 10 },
		spawns = { Raider = 4, AxeThrower = 6 },
		chest = { hold = 5 }, boss = Vector3.new(-40, 0, 0) },
	{ id = "LonghouseHold", name = "Longhouse Hold", center = Vector3.new(310, 0, 620), radius = 70, levels = { 10, 17 },
		spawns = { Shieldbearer = 5, Berserker = 4, AxeThrower = 3 },
		chest = { hold = 6 }, boss = Vector3.new(0, 0, 40) },
	{ id = "JarlsFortress", name = "Jarl's Fortress", center = Vector3.new(0, 0, 920), radius = 85, levels = { 18, 28 },
		spawns = { Berserker = 5, Shieldbearer = 4, AxeThrower = 3, Chieftain = 2, Hornblower = 2 },
		chest = { hold = 7 }, boss = Vector3.new(0, 0, 30), alarm = true },
}

function Zones.getCamp(id: string)
	for _, camp in ipairs(Zones.Camps) do
		if camp.id == id then
			return camp
		end
	end
	return nil
end

-- Wild animals roam these boxes (X/Z). WildlifeService keeps `spawns` of each kind alive.
Zones.HuntingGrounds = {
	{ id = "ElkMeadows", min = Vector3.new(-540, 0, -330), max = Vector3.new(-300, 0, 225), levels = { 1, 5 },
		spawns = { Deer = 7, Goat = 4, Boar = 4 } },
	{ id = "Whisperwood", min = Vector3.new(300, 0, -330), max = Vector3.new(540, 0, 225), levels = { 3, 8 },
		spawns = { Deer = 5, Boar = 5, Wolf = 4 } },
	{ id = "BearclawHollow", min = Vector3.new(-540, 0, 760), max = Vector3.new(-200, 0, 1090), levels = { 12, 20 },
		spawns = { Bear = 3, Boar = 4, Goat = 4, Wolf = 3 } },
	{ id = "FrostfangRidge", min = Vector3.new(270, 0, 780), max = Vector3.new(540, 0, 1090), levels = { 16, 24 },
		spawns = { SnowWolf = 6, Bear = 3 } },
}

-- Lakes are carved as overlapping round bowls ("lobes": x, z offset from center, rim radius,
-- depth of the middle) so their shores are curvy and gently sloped, and the middle is deep. Water sits at WATER_LEVEL. `frozen` lakes get an ice sheet
-- with one fishing hole.
Zones.WATER_LEVEL = -4
Zones.Lakes = {
	{ id = "ElkLake", center = Vector3.new(-430, 0, -40), lobes = {
		{ 0, 0, 34, 20 }, { -32, 18, 24, 16 }, { 28, -22, 24, 16 }, { 14, 32, 20, 14 }, { -18, -34, 20, 14 }, { 40, 12, 14, 10 } } },
	{ id = "WhisperPond", center = Vector3.new(440, 0, 60), lobes = {
		{ 0, 0, 26, 18 }, { -20, -12, 18, 14 }, { 18, 16, 18, 14 }, { 4, -26, 15, 12 } } },
	{ id = "FjordLake", center = Vector3.new(-462, 0, 590), lobes = {
		{ 0, 0, 38, 24 }, { -8, -55, 32, 20 }, { 4, 56, 34, 22 }, { -18, 100, 24, 14 }, { -6, -100, 26, 14 },
		{ 36, -18, 25, 14 }, { 32, 36, 22, 14 }, { -34, 10, 22, 14 } } },
	{ id = "FrozenTarn", center = Vector3.new(405, 0, 945), frozen = true, hole = Vector3.new(6, 0, 4), lobes = {
		{ 0, 0, 30, 18 }, { -24, 14, 20, 12 }, { 22, -12, 20, 12 }, { 8, 26, 16, 10 } } },
}


-- Roads and trails (a, b, width, terrain material). The world builder paves them and the map
-- draws them.
local function seg(ax, az, bx, bz, width, material)
	return { a = Vector3.new(ax, 0, az), b = Vector3.new(bx, 0, bz), width = width, material = material }
end
Zones.SIDE_ROAD_X = 164 -- the streets in front of the lairs, at x = +-this
Zones.Roads = { -- cobblestone streets in town
	seg(0, 40, 0, 244, 18, "Cobblestone"),
	seg(0, -40, 0, -196, 16, "Cobblestone"),
	seg(-Zones.SIDE_ROAD_X, 0, Zones.SIDE_ROAD_X, 0, 14, "Cobblestone"),
	seg(-Zones.SIDE_ROAD_X, -225, -Zones.SIDE_ROAD_X, 225, 12, "Cobblestone"),
	seg(Zones.SIDE_ROAD_X, -225, Zones.SIDE_ROAD_X, 225, 12, "Cobblestone"),
}
Zones.Paths = { -- trails out of town
	seg(0, 305, 0, 400, 14, "Mud"),
	seg(0, 440, -280, 570, 12, "Mud"),
	seg(0, 440, 280, 610, 12, "Mud"),
	seg(0, 440, 0, 840, 14, "Mud"),
	seg(-170, 0, -330, 0, 10, "Ground"),
	seg(-330, 0, -372, -12, 8, "Ground"),
	seg(170, 0, 330, 0, 10, "Ground"),
	seg(330, 0, 400, 40, 8, "Ground"),
}

-- The river between town and the viking lands winds through these points (x, z) with `width`.
Zones.River = {
	width = 44,
	points = {
		{ -720, 282 }, { -560, 292 }, { -440, 266 }, { -300, 288 }, { -170, 268 }, { -70, 280 }, { 0, 276 },
		{ 70, 272 }, { 170, 290 }, { 300, 266 }, { 430, 286 }, { 560, 270 }, { 720, 280 },
	},
}

-- Channels carved and drawn like the river. The fjord channel joins Fjord Lake (the Fishing
-- Village's harbor) to the river, so the longships have a way out to sea. `depth` is the bowl
-- depth in the middle; the first point sits in the river and the last one in the lake.
Zones.Streams = {
	{ id = "FjordChannel", width = 32, depth = 14, points = {
		{ -446, 268 }, { -448, 312 }, { -462, 360 }, { -456, 410 }, { -466, 458 }, { -468, 500 } } },
}

-- Fishing spots (on the water surface). kind picks the fish table in Config/Food.
Zones.FishingSpots = {
	{ id = "RiverWest", kind = "River", pos = Vector3.new(-120, 0, 274) },
	{ id = "RiverEast", kind = "River", pos = Vector3.new(90, 0, 276) },
	{ id = "RiverFar", kind = "River", pos = Vector3.new(230, 0, 279) },
	{ id = "ElkLakeNorth", kind = "Lake", pos = Vector3.new(-436, 0, -52) },
	{ id = "ElkLakeWest", kind = "Lake", pos = Vector3.new(-462, 0, -20) },
	{ id = "WhisperPond", kind = "Lake", pos = Vector3.new(436, 0, 62) },
	{ id = "FjordSouth", kind = "Lake", pos = Vector3.new(-440, 0, 628) },
	{ id = "FjordNorth", kind = "Lake", pos = Vector3.new(-442, 0, 582) },
	{ id = "FrozenTarn", kind = "Ice", pos = Vector3.new(411, 0, 949) },
}
for _, spot in ipairs(Zones.FishingSpots) do
	spot.pos = Vector3.new(spot.pos.X, Zones.WATER_LEVEL, spot.pos.Z)
end

-- Training grounds in town, behind the houses on the east side of the main road: practice
-- dummies with a DPS meter (a sandy yard in front of them, south, where you fight), and a fenced
-- sparring pen whose golem throws practice axes at any dragon inside the fence.
Zones.Training = {
	dummies = { Vector3.new(86, 0, 140), Vector3.new(112, 0, 136), Vector3.new(138, 0, 140) },
	pen = { min = Vector3.new(84, 0, 164), max = Vector3.new(146, 0, 226) },
	golem = Vector3.new(115, 0, 212),
}

-- Target practice range (RangeService) on the west side of town, behind the houses on the main
-- road. Each lane has a firing mat at x = matX (you face -x); your targets move around the field
-- between x = near and far, within laneHalf of the lane's middle (z). Hay bales at x = backstop
-- catch stray fireballs.
Zones.Range = {
	lanes = { 146, 178, 210 }, -- z of each lane's middle
	laneHalf = 12,
	matX = -92,
	near = -116,
	far = -140,
	backstop = -148,
}

-- Town points of interest.
Zones.Shops = {
	{ id = "Armory", name = "Emberforge Armory", tab = "Buy", position = Vector3.new(-78, 0, -38), facing = Vector3.new(1, 0, 1) },
	{ id = "Exchange", name = "Hoard Exchange", tab = "Sell", position = Vector3.new(78, 0, -38), facing = Vector3.new(-1, 0, 1) },
	{ id = "Forge", name = "Anvil of Ages", tab = "Upgrade", position = Vector3.new(-48, 0, -108), facing = Vector3.new(1, 0, 0.8) },
	{ id = "Alchemist", name = "Bubbling Cauldron", panel = "Potions", position = Vector3.new(48, 0, -108), facing = Vector3.new(-1, 0, 0.8) },
	{ id = "Hatchery", name = "Nestmother's Hatchery", panel = "Hatchery", position = Vector3.new(92, 0, 40), facing = Vector3.new(-1, 0, -0.35) },
}

function Zones.getShop(id: string)
	for _, shop in ipairs(Zones.Shops) do
		if shop.id == id then
			return shop
		end
	end
	return nil
end

Zones.QuestGivers = {
	Elder = { position = Vector3.new(-42, 0, 48), facing = Vector3.new(0.6, 0, -1) },
	Captain = { position = Vector3.new(42, 0, 48), facing = Vector3.new(-0.6, 0, -1) },
	Gardener = { position = Vector3.new(-120, 0, 12), facing = Vector3.new(1, 0, 0) },
	Scout = { position = Vector3.new(48, 0, -160), facing = Vector3.new(-1, 0, 0.3) },
	-- beside the dungeon cave mouths in the viking lands (Config/Dungeons entrances)
	Ylva = { position = Vector3.new(-116, 0, 704), facing = Vector3.new(-0.4, 0, -1) },
	Kael = { position = Vector3.new(174, 0, 719), facing = Vector3.new(-0.4, 0, -1) },
}

Zones.WarHorn = Vector3.new(28, 0, 74)

-- Dragon houses you can walk into (Props.dragonHouse). `facing` points out of the front door.
-- HouseSize: X = width (along the front), Y = wall height, Z = depth.
-- The main road's two rows face each other across a 72-stud street, with 26-stud gaps between
-- houses, so you can see (and fly) between them during a raid (they used to be packed 18 studs
-- apart). Their backs stay clear of the target practice camera behind the firing mats.
Zones.HouseSize = Vector3.new(32, 18, 24)
Zones.Houses = {
	{ pos = Vector3.new(-48, 0, 100), facing = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(-48, 0, 158), facing = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(-48, 0, 216), facing = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(48, 0, 100), facing = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(48, 0, 158), facing = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(48, 0, 216), facing = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(-72, 0, -152), facing = Vector3.new(1, 0, 0) },
	{ pos = Vector3.new(108, 0, -132), facing = Vector3.new(-1, 0, 0) },
	{ pos = Vector3.new(-112, 0, 98), facing = Vector3.new(0, 0, -1) },
	{ pos = Vector3.new(112, 0, 96), facing = Vector3.new(0, 0, -1) },
}
-- Just outside a house's door, and the middle of its floor (ground level).
function Zones.houseDoor(house): Vector3
	return house.pos + house.facing.Unit * (Zones.HouseSize.Z / 2 + 7)
end
function Zones.houseInside(house): Vector3
	return house.pos - house.facing.Unit * 1
end
-- A point in a house's own frame (the same one Props.dragonHouse builds in): -z points out of the
-- door, +z toward the back wall. Used for where villagers stand indoors.
function Zones.housePoint(house, x: number, z: number): Vector3
	local cf = CFrame.lookAt(house.pos, house.pos + house.facing)
	return (cf * CFrame.new(x, 0, z)).Position
end
-- Town wells (Props.well): dragons dip in to scoop up water for burning houses during a raid (the
-- river below town is the other place close by). One on the main road between the house rows,
-- one between the two houses at the south end of town.
Zones.Wells = { Vector3.new(-24, 0, 129), Vector3.new(26, 0, -170) }
Zones.HOUSE_FLOOR = 2.6 -- height of the floorboards
Zones.HouseEntry = Vector3.new(0, 0, -8) -- just inside the door
-- Where villagers potter about indoors: the rug, in the nest, the fireplace, the bookshelf, the table.
Zones.HouseSpots = { Vector3.new(1, 0, -1), Vector3.new(-7.5, 0, 5), Vector3.new(6, 0, 5), Vector3.new(10, 0, -4), Vector3.new(-2, 0, -6) }

-- Where village dragons (CivilianService) stroll: a small graph of open ground between the
-- plaza, the streets and every house door. Every edge is a straight walk that misses stalls,
-- lamps and statues. `houseLinks[i]` is the node house i's door connects to.
Zones.TownWalk = {
	nodes = {
		PN = Vector3.new(0, 0, 30), PNE = Vector3.new(21, 0, 21), PE = Vector3.new(30, 0, 0), PSE = Vector3.new(21, 0, -21),
		PS = Vector3.new(0, 0, -30), PSW = Vector3.new(-21, 0, -21), PW = Vector3.new(-30, 0, 0), PNW = Vector3.new(-21, 0, 21),
		N1 = Vector3.new(0, 0, 60), N2 = Vector3.new(0, 0, 100), N3 = Vector3.new(0, 0, 158), N4 = Vector3.new(0, 0, 216),
		S1 = Vector3.new(0, 0, -70), S2 = Vector3.new(0, 0, -132), S3 = Vector3.new(0, 0, -152),
		W1 = Vector3.new(-50, 0, 2), W2 = Vector3.new(-80, 0, 30),
		E1 = Vector3.new(50, 0, 2), E2 = Vector3.new(62, 0, 24), E3 = Vector3.new(70, 0, 74),
	},
	edges = {
		{ "PN", "PNE" }, { "PNE", "PE" }, { "PE", "PSE" }, { "PSE", "PS" }, { "PS", "PSW" }, { "PSW", "PW" }, { "PW", "PNW" }, { "PNW", "PN" },
		{ "PN", "N1" }, { "N1", "N2" }, { "N2", "N3" }, { "N3", "N4" },
		{ "PS", "S1" }, { "S1", "S2" }, { "S2", "S3" },
		{ "PW", "W1" }, { "W1", "W2" },
		{ "PE", "E1" }, { "E1", "E2" }, { "E2", "E3" },
	},
	houseLinks = { "N2", "N3", "N4", "N2", "N3", "N4", "S3", "S2", "W2", "E3" },
}

-- How night raiders (RaidService) get to dragons at home: from the TownWalk node `from`, along
-- `via` to the side road, down the road (x = roadX) to the lair, and in through the gap in its
-- front fence (Zones.lairGate). walk_check.py keeps these walks clear.
Zones.LairApproach = {
	west = { from = "W1", via = { Vector3.new(-110, 0, -8), Vector3.new(-161, 0, -8) }, roadX = -161 },
	east = { from = "E1", via = { Vector3.new(110, 0, -8), Vector3.new(161, 0, -8) }, roadX = 161 },
}

-- Player bases: 4 down each side of town, fronts facing the side road (their front fences sit
-- 2 studs past its edge).
-- BaseSize: X = depth (along facing), Z = width.
Zones.BaseSize = Vector3.new(88, 0, 92)
Zones.Bases = {}
local baseX = Zones.SIDE_ROAD_X + 8 + Zones.BaseSize.X / 2
for i, z in ipairs({ -165, -55, 55, 165 }) do
	table.insert(Zones.Bases, { index = i, center = Vector3.new(-baseX, 0, z), facing = Vector3.new(1, 0, 0) })
end
for i, z in ipairs({ -165, -55, 55, 165 }) do
	table.insert(Zones.Bases, { index = i + 4, center = Vector3.new(baseX, 0, z), facing = Vector3.new(-1, 0, 0) })
end

-- Named places: the world map's list (click one for a waypoint) and where the Wayfinder pass
-- teleports you. `pos` is what the map points at; `drop` is where a teleport sets you down (clear
-- of statues and stalls; viking camps drop you at their edge on the town side). "home" is your
-- lair, which only the game knows.
local SHOP_ICONS = { Armory = "⚔️", Exchange = "💰", Forge = "🔨", Alchemist = "🧪", Hatchery = "🥚" }
function Zones.places()
	local range = Vector3.new(Zones.Range.matX, 0, Zones.Range.lanes[2])
	local list = {
		{ id = "home", label = "🏠 Your lair" },
		{ id = "square", label = "🐉 Town square", pos = Vector3.new(0, 0, 0), drop = Vector3.new(0, 0, 30) },
		{ id = "training", label = "🎯 Training grounds", pos = Zones.Training.dummies[2], drop = Zones.Training.dummies[2] - Vector3.new(0, 0, 20) },
		{ id = "range", label = "🏹 Target practice", pos = range, drop = range + Vector3.new(8, 0, 0) },
		{ id = "warhorn", label = "📯 War Horn (bosses)", pos = Zones.WarHorn, drop = Zones.WarHorn + Vector3.new(0, 0, -12) },
	}
	for _, shop in ipairs(Zones.Shops) do
		table.insert(list, { id = "shop:" .. shop.id, label = (SHOP_ICONS[shop.id] or "🛒") .. " " .. shop.name, pos = shop.position, drop = shop.position + shop.facing.Unit * 14 })
	end
	local bz = Zones.getArea("BattleZone")
	table.insert(list, { id = "battle", label = "🏟️ Battle Zone (PvP)", pos = Vector3.new((bz.min.X + bz.max.X) / 2, 0, (bz.min.Z + bz.max.Z) / 2) })
	for _, ground in ipairs(Zones.HuntingGrounds) do
		local a = Zones.getArea(ground.id)
		-- teleports land just inside the edge nearest town (Elk Lake fills the middle of the meadows)
		local center = (ground.min + ground.max) / 2
		local edge = Vector3.new(math.clamp(0, ground.min.X, ground.max.X), 0, math.clamp(0, ground.min.Z, ground.max.Z))
		table.insert(list, { id = "hunt:" .. ground.id, label = string.format("🦌 %s (Lv %d-%d)", a.name, ground.levels[1], ground.levels[2]),
			pos = center, drop = edge + (center - edge).Unit * 20 })
	end
	for _, camp in ipairs(Zones.Camps) do
		table.insert(list, { id = "camp:" .. camp.id, label = string.format("⚔️ %s (Lv %d-%d)", camp.name, camp.levels[1], camp.levels[2]),
			pos = camp.center, drop = camp.center - Vector3.new(0, 0, camp.radius + 25) })
	end
	for _, id in ipairs(Dungeons.Order) do
		local d = Dungeons.List[id]
		table.insert(list, { id = "dungeon:" .. id, label = string.format("🏰 %s (Lv %d+)", d.name, d.minLevel),
			pos = d.entrance, drop = d.entrance + d.entranceFacing.Unit * 34 })
	end
	for _, place in ipairs(list) do
		place.drop = place.drop or place.pos
	end
	return list
end

function Zones.getPlace(id: string)
	for _, place in ipairs(Zones.places()) do
		if place.id == id then
			return place
		end
	end
	return nil
end

-- Just inside the gap in a lair's front fence.
function Zones.lairGate(base): Vector3
	return base.center + base.facing * (Zones.BaseSize.X / 2 - 8)
end

-- The lair a point is in, if any.
function Zones.baseAt(pos: Vector3)
	for _, base in ipairs(Zones.Bases) do
		local d = pos - base.center
		local along = math.abs(d.X * base.facing.X + d.Z * base.facing.Z)
		local across = math.abs(d.X * base.facing.Z - d.Z * base.facing.X)
		if along <= Zones.BaseSize.X / 2 and across <= Zones.BaseSize.Z / 2 then
			return base
		end
	end
	return nil
end

local function inArea(area, pos: Vector3): boolean
	if area.shape == "box" then
		return pos.X >= area.min.X and pos.X <= area.max.X
			and pos.Y >= area.min.Y and pos.Y <= area.max.Y
			and pos.Z >= area.min.Z and pos.Z <= area.max.Z
	else
		local dx, dz = pos.X - area.center.X, pos.Z - area.center.Z
		return dx * dx + dz * dz <= area.radius * area.radius
	end
end

function Zones.areaAt(pos: Vector3)
	for _, area in ipairs(Zones.Areas) do
		if inArea(area, pos) then
			return area
		end
	end
	return nil
end

function Zones.getArea(id: string)
	for _, area in ipairs(Zones.Areas) do
		if area.id == id then
			return area
		end
	end
	return nil
end

function Zones.isIn(id: string, pos: Vector3): boolean
	local area = Zones.getArea(id)
	return area ~= nil and inArea(area, pos)
end

function Zones.inWorld(pos: Vector3): boolean
	local b = Zones.WorldBounds
	return pos.X >= b.min.X and pos.X <= b.max.X
		and pos.Y >= b.min.Y and pos.Y <= b.max.Y
		and pos.Z >= b.min.Z and pos.Z <= b.max.Z
end

return Zones
