-- Map layout. The world is generated in code from these positions (server/World/WorldBuilder),
-- and the same numbers drive zone detection, PvP, enemy camps and safe areas.
-- Coordinates are studs; y = 0 is ground level.

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

-- Lakes are carved as overlapping round basins ("lobes": x, z offset from center, rim radius,
-- depth) so their shores are curvy. Water sits at WATER_LEVEL. `frozen` lakes get an ice sheet
-- with one fishing hole.
Zones.WATER_LEVEL = -4
Zones.Lakes = {
	{ id = "ElkLake", center = Vector3.new(-430, 0, -40), lobes = {
		{ 0, 0, 34, 11 }, { -32, 18, 24, 8 }, { 28, -22, 24, 8 }, { 14, 32, 20, 7 }, { -18, -34, 20, 7 }, { 40, 12, 14, 6 } } },
	{ id = "WhisperPond", center = Vector3.new(440, 0, 60), lobes = {
		{ 0, 0, 26, 9 }, { -20, -12, 18, 7 }, { 18, 16, 18, 7 }, { 4, -26, 15, 6 } } },
	{ id = "FjordLake", center = Vector3.new(-462, 0, 590), lobes = {
		{ 0, 0, 38, 12 }, { -8, -55, 32, 10 }, { 4, 56, 34, 10 }, { -18, 100, 24, 7 }, { -6, -100, 26, 7 },
		{ 36, -18, 25, 8 }, { 32, 36, 22, 8 }, { -34, 10, 22, 7 } } },
	{ id = "FrozenTarn", center = Vector3.new(405, 0, 945), frozen = true, hole = Vector3.new(6, 0, 4), lobes = {
		{ 0, 0, 30, 9 }, { -24, 14, 20, 6 }, { 22, -12, 20, 6 }, { 8, 26, 16, 6 } } },
}

-- Roads and trails (a, b, width, terrain material). The world builder paves them and the map
-- draws them.
local function seg(ax, az, bx, bz, width, material)
	return { a = Vector3.new(ax, 0, az), b = Vector3.new(bx, 0, bz), width = width, material = material }
end
Zones.Roads = { -- cobblestone streets in town
	seg(0, 40, 0, 244, 18, "Cobblestone"),
	seg(0, -40, 0, -196, 16, "Cobblestone"),
	seg(-140, 0, 140, 0, 14, "Cobblestone"),
	seg(-140, -225, -140, 225, 12, "Cobblestone"),
	seg(140, -225, 140, 225, 12, "Cobblestone"),
}
Zones.Paths = { -- trails out of town
	seg(0, 305, 0, 400, 14, "Mud"),
	seg(0, 440, -280, 570, 12, "Mud"),
	seg(0, 440, 280, 610, 12, "Mud"),
	seg(0, 440, 0, 840, 14, "Mud"),
	seg(-146, 0, -330, 0, 10, "Ground"),
	seg(-330, 0, -372, -12, 8, "Ground"),
	seg(146, 0, 330, 0, 10, "Ground"),
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

-- Training grounds in town: practice dummies with a DPS meter, and a fenced sparring pen whose
-- golem throws practice axes at any dragon inside the fence.
Zones.Training = {
	dummies = { Vector3.new(78, 0, 138), Vector3.new(98, 0, 134), Vector3.new(118, 0, 138) },
	pen = { min = Vector3.new(72, 0, 160), max = Vector3.new(128, 0, 222) },
	golem = Vector3.new(100, 0, 208),
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
}

Zones.WarHorn = Vector3.new(28, 0, 74)

-- Player bases: 4 down each side of town, fronts facing the road in the middle.
-- BaseSize: X = depth (along facing), Z = width.
Zones.BaseSize = Vector3.new(88, 0, 92)
Zones.Bases = {}
for i, z in ipairs({ -165, -55, 55, 165 }) do
	table.insert(Zones.Bases, { index = i, center = Vector3.new(-192, 0, z), facing = Vector3.new(1, 0, 0) })
end
for i, z in ipairs({ -165, -55, 55, 165 }) do
	table.insert(Zones.Bases, { index = i + 4, center = Vector3.new(192, 0, z), facing = Vector3.new(-1, 0, 0) })
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
