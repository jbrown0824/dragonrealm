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
Zones.Camps = {
	{ id = "RaiderCamp", center = Vector3.new(0, 0, 430), radius = 60, levels = { 1, 4 },
		spawns = { Raider = 9 } },
	{ id = "FishingVillage", center = Vector3.new(-310, 0, 580), radius = 70, levels = { 5, 10 },
		spawns = { Raider = 4, AxeThrower = 6 } },
	{ id = "LonghouseHold", center = Vector3.new(310, 0, 620), radius = 70, levels = { 10, 17 },
		spawns = { Shieldbearer = 5, Berserker = 4, AxeThrower = 3 } },
	{ id = "JarlsFortress", center = Vector3.new(0, 0, 920), radius = 85, levels = { 18, 28 },
		spawns = { Berserker = 5, Shieldbearer = 4, AxeThrower = 3, Chieftain = 2 } },
}

-- Town points of interest.
Zones.Shops = {
	{ id = "Armory", name = "Emberforge Armory", tab = "Buy", position = Vector3.new(-78, 0, -38), facing = Vector3.new(1, 0, 1) },
	{ id = "Exchange", name = "Hoard Exchange", tab = "Sell", position = Vector3.new(78, 0, -38), facing = Vector3.new(-1, 0, 1) },
	{ id = "Forge", name = "Anvil of Ages", tab = "Upgrade", position = Vector3.new(-48, 0, -108), facing = Vector3.new(1, 0, 0.8) },
}

Zones.QuestGivers = {
	Elder = { position = Vector3.new(-42, 0, 48), facing = Vector3.new(0.6, 0, -1) },
	Captain = { position = Vector3.new(42, 0, 48), facing = Vector3.new(-0.6, 0, -1) },
	Gardener = { position = Vector3.new(-120, 0, 12), facing = Vector3.new(1, 0, 0) },
	Scout = { position = Vector3.new(48, 0, -160), facing = Vector3.new(-1, 0, 0.3) },
}

Zones.WarHorn = Vector3.new(28, 0, 74)

-- Player bases: 4 down each side of town, fronts facing the road in the middle.
Zones.BaseSize = Vector3.new(80, 0, 96)
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
