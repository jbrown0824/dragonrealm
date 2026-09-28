-- The natural world outside town: the winding river, lakes with curvy sandy shores, the four
-- hunting grounds (Zones.HuntingGrounds) and the fishing spots.
--
-- Lakes and the river are carved as overlapping round basins (a big ball of air whose bottom is a
-- shallow dish), then the carved space below Zones.WATER_LEVEL is filled with water. That gives
-- sloped banks and curvy outlines instead of boxes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)

local Props = require(script.Parent.Props)
local WorldUtil = require(script.Parent.WorldUtil)

local Wilds = {}

local terrain = WorldUtil.terrain
local rng = Random.new(51177)
local WATER = Zones.WATER_LEVEL

---------------------------------------------------------------- basins

-- Carve a round dish: `rim` = radius where it meets the ground (y = 0), `depth` below that.
local function basin(x: number, z: number, rim: number, depth: number)
	local R = (rim * rim + depth * depth) / (2 * depth)
	terrain:FillBall(Vector3.new(x, R - depth, z), R, Enum.Material.Air)
end

-- A deep bowl: a sandy slope down to the water's edge, then steep banks into deep water (so
-- boats float and you can't see the bottom), deepest in the middle. A shallow spherical cap
-- would leave a wide ring of ankle-deep water, so the main bowl is nearly a half-sphere.
local function bowl(x: number, z: number, rim: number, depth: number)
	basin(x, z, rim, 5)
	basin(x, z, rim * 0.8, depth)
	basin(x, z, rim * 0.5, depth + 4)
end

-- Solid lake bed under a water area. The world's ground is only 16 studs thick, and a bowl
-- carved deeper than that would leave water hanging over the void.
local BED_BOTTOM = -44
local function lakeBed(minX: number, minZ: number, maxX: number, maxZ: number)
	local top = -3 -- keep the grass / beach surface layer
	terrain:FillBlock(
		CFrame.new((minX + maxX) / 2, (top + BED_BOTTOM) / 2, (minZ + maxZ) / 2),
		Vector3.new(maxX - minX, top - BED_BOTTOM, maxZ - minZ),
		Enum.Material.Mud
	)
end

-- Top layer of ground around a basin becomes sand (done before carving).
local function beach(x: number, z: number, rim: number, material: Enum.Material?)
	terrain:FillCylinder(CFrame.new(x, -1.5, z), 3, rim + 5, material or Enum.Material.Sand)
end

local function fillWater(minX: number, minZ: number, maxX: number, maxZ: number, bottom: number)
	local region = Region3.new(Vector3.new(minX, bottom, minZ), Vector3.new(maxX, WATER, maxZ)):ExpandToGrid(4)
	terrain:ReplaceMaterial(region, 4, Enum.Material.Air, Enum.Material.Water)
end

-- Every circle of a lake (the defined lobes plus a few wobbly satellites) in world space.
local function lakeCircles(lake)
	local circles = {}
	for _, lobe in ipairs(lake.lobes) do
		local x, z = lake.center.X + lobe[1], lake.center.Z + lobe[2]
		table.insert(circles, { x = x, z = z, rim = lobe[3], depth = lobe[4] })
		for k = 1, 3 do
			local a = rng:NextNumber(0, math.pi * 2) + k * 2.1
			local d = lobe[3] * rng:NextNumber(0.55, 0.8)
			table.insert(circles, { x = x + math.cos(a) * d, z = z + math.sin(a) * d, rim = lobe[3] * rng:NextNumber(0.35, 0.5), depth = lobe[4] * 0.6 })
		end
	end
	return circles
end

local lakeShapes = {} -- [lakeId] = circles (for keeping scenery out of the water)

local function inAnyLake(p: Vector3, margin: number): boolean
	for _, circles in pairs(lakeShapes) do
		for _, c in ipairs(circles) do
			local dx, dz = p.X - c.x, p.Z - c.z
			if dx * dx + dz * dz < (c.rim + margin) ^ 2 then
				return true
			end
		end
	end
	return false
end
Wilds.inAnyLake = inAnyLake

local function carveLake(lake)
	local circles = lakeCircles(lake)
	lakeShapes[lake.id] = circles
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, c in ipairs(circles) do
		minX, maxX = math.min(minX, c.x - c.rim), math.max(maxX, c.x + c.rim)
		minZ, maxZ = math.min(minZ, c.z - c.rim), math.max(maxZ, c.z + c.rim)
	end
	lakeBed(minX - 12, minZ - 12, maxX + 12, maxZ + 12)
	for _, c in ipairs(circles) do
		beach(c.x, c.z, c.rim, lake.frozen and Enum.Material.Snow or nil)
	end
	for _, c in ipairs(circles) do
		bowl(c.x, c.z, c.rim, c.depth)
	end
	fillWater(minX - 4, minZ - 4, maxX + 4, maxZ + 4, BED_BOTTOM + 4)
	if lake.frozen then
		-- Freeze the top layer, then melt a fishing hole.
		local region = Region3.new(Vector3.new(minX - 4, WATER - 4, minZ - 4), Vector3.new(maxX + 4, WATER, maxZ + 4)):ExpandToGrid(4)
		terrain:ReplaceMaterial(region, 4, Enum.Material.Water, Enum.Material.Ice)
		local hole = lake.center + (lake.hole or Vector3.zero)
		terrain:FillCylinder(CFrame.new(hole.X, WATER - 2, hole.Z), 4, 4, Enum.Material.Water)
	end
end

local riverPoints = {}

local function carveRiver()
	local river = Zones.River
	local samples = Util.spline(river.points, 6)
	local phase = rng:NextNumber(0, 10)
	lakeBed(-660, 220, 660, 340)
	for i, p in ipairs(samples) do
		local w = river.width * (0.88 + 0.12 * math.sin(i * 0.11 + phase) + 0.06 * math.sin(i * 0.37))
		riverPoints[i] = { p = p, w = w }
		beach(p.X, p.Z, w / 2)
	end
	for _, rp in ipairs(riverPoints) do
		bowl(rp.p.X, rp.p.Z, rp.w / 2, 16)
	end
	fillWater(-656, 220, 656, 340, -32) -- stays inside the ground block (x = +-660)
end

function Wilds.inRiver(p: Vector3, margin: number): boolean
	for _, rp in ipairs(riverPoints) do
		local dx, dz = p.X - rp.p.X, p.Z - rp.p.Z
		if dx * dx + dz * dz < (rp.w / 2 + margin) ^ 2 then
			return true
		end
	end
	return false
end

-- Terrain water first (other builders place things around it).
function Wilds.buildWater()
	carveRiver()
	for _, lake in ipairs(Zones.Lakes) do
		carveLake(lake)
	end
end

---------------------------------------------------------------- hunting grounds

local function randomIn(area, margin: number): Vector3
	return Vector3.new(rng:NextNumber(area.min.X + margin, area.max.X - margin), 0, rng:NextNumber(area.min.Z + margin, area.max.Z - margin))
end

local function clear(p: Vector3, avoid): boolean
	if inAnyLake(p, 8) or Wilds.inRiver(p, 8) then
		return false
	end
	for _, a in ipairs(avoid or {}) do
		if WorldUtil.flatDistToSegment(p, a[1], a[2]) < a[3] then
			return false
		end
	end
	return true
end

-- Scatter `count` things in an area, skipping water and the given path corridors.
local function scatter(area, count: number, margin: number, avoid, fn)
	local placed, tries = 0, 0
	while placed < count and tries < count * 8 do
		tries += 1
		local p = randomIn(area, margin)
		if clear(p, avoid) then
			placed += 1
			fn(p + Vector3.new(0, Props.groundY(p.X, p.Z), 0))
		end
	end
end

local function hills(area, count: number, material: Enum.Material)
	for _ = 1, count do
		local r = rng:NextNumber(18, 36)
		local p = randomIn(area, r * 0.6)
		if not inAnyLake(p, r) and not Wilds.inRiver(p, r) then
			terrain:FillBall(Vector3.new(p.X, -r * 0.85, p.Z), r, material)
		end
	end
end

local function areaSign(parent: Instance, pos: Vector3, facing: Vector3, text: string, color: Color3)
	Props.sign(parent, CFrame.lookAt(pos + Vector3.new(0, 5, 0), pos + Vector3.new(0, 5, 0) + facing), text, Vector2.new(13, 4.5), color)
end

local function lakeDecor(parent: Instance, lake)
	local circles = lakeShapes[lake.id]
	for i = 1, #lake.lobes * 3 do
		local c = circles[rng:NextInteger(1, #circles)]
		local a = rng:NextNumber(0, math.pi * 2)
		local shore = Vector3.new(c.x + math.cos(a) * (c.rim + 2), 0, c.z + math.sin(a) * (c.rim + 2))
		if not lake.frozen and not inAnyLake(shore, 0.5) then
			Props.reeds(parent, shore + Vector3.new(0, Props.groundY(shore.X, shore.Z), 0), 5)
		end
		if not lake.frozen and i % 2 == 0 then
			local pad = Vector3.new(c.x + math.cos(a) * c.rim * 0.6, WATER, c.z + math.sin(a) * c.rim * 0.6)
			Props.lilyPad(parent, pad)
		end
	end
end

local function buildElkMeadows(parent: Instance, area)
	local f = WorldUtil.folder("ElkMeadows", parent)
	local path = { { Vector3.new(-280, 0, 0), Vector3.new(-372, 0, -12), 10 } }
	hills(area, 10, Enum.Material.Grass)
	scatter(area, 34, 15, path, function(p)
		if rng:NextNumber() < 0.45 then
			Props.birch(f, p, rng:NextNumber(0.9, 1.3))
		else
			Props.tree(f, p, rng:NextNumber(0.9, 1.4), "oak")
		end
	end)
	scatter(area, 26, 10, path, function(p)
		Props.flowers(f, p, ({ Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 225, 90), Color3.fromRGB(170, 130, 255), Color3.fromRGB(255, 255, 255) })[rng:NextInteger(1, 4)])
	end)
	scatter(area, 12, 10, path, function(p)
		Props.rock(f, p + Vector3.new(0, 1, 0), rng:NextNumber(3, 8))
	end)
	scatter(area, 8, 10, path, function(p)
		Props.bush(f, p, rng:NextNumber(0.9, 1.5))
	end)
	scatter(area, 4, 20, path, function(p)
		Props.log(f, p, rng:NextNumber(8, 14), rng:NextNumber(0, math.pi))
	end)
	areaSign(f, Vector3.new(-292, 0, 16), Vector3.new(1, 0, 0), "🦌 Elk Meadows\nHunting • Lv 1-5", Color3.fromRGB(200, 250, 170))
end

local function buildWhisperwood(parent: Instance, area)
	local f = WorldUtil.folder("Whisperwood", parent)
	local path = { { Vector3.new(280, 0, 0), Vector3.new(400, 0, 40), 10 } }
	hills(area, 8, Enum.Material.LeafyGrass)
	scatter(area, 80, 12, path, function(p)
		Props.tree(f, p, rng:NextNumber(1.0, 1.7), rng:NextNumber() < 0.55 and "oak" or "pine")
	end)
	scatter(area, 18, 10, path, function(p)
		Props.mushroom(f, p, rng:NextNumber(0.7, 1.6))
	end)
	scatter(area, 8, 15, path, function(p)
		Props.log(f, p, rng:NextNumber(10, 16), rng:NextNumber(0, math.pi))
	end)
	scatter(area, 10, 10, path, function(p)
		Props.rock(f, p + Vector3.new(0, 1, 0), rng:NextNumber(3, 7), Color3.fromRGB(110, 120, 110))
	end)
	-- a few fireflies over the pond
	for _ = 1, 8 do
		local p = Zones.Lakes[2].center + Vector3.new(rng:NextNumber(-40, 40), rng:NextNumber(3, 8), rng:NextNumber(-40, 40))
		local fly = Props.part(f, Vector3.new(0.4, 0.4, 0.4), CFrame.new(p), Color3.fromRGB(230, 255, 140), Enum.Material.Neon)
		fly.Shape = Enum.PartType.Ball
		fly.CanCollide = false
		fly.CastShadow = false
	end
	areaSign(f, Vector3.new(292, 0, 16), Vector3.new(-1, 0, 0), "🌲 Whisperwood\nHunting • Lv 3-8", Color3.fromRGB(170, 240, 180))
end

local function buildBearclaw(parent: Instance, area)
	local f = WorldUtil.folder("BearclawHollow", parent)
	hills(area, 10, Enum.Material.Rock)
	scatter(area, 45, 12, nil, function(p)
		Props.tree(f, p, rng:NextNumber(1.1, 1.8), rng:NextNumber() < 0.3 and "snowpine" or "pine")
	end)
	scatter(area, 16, 10, nil, function(p)
		Props.rock(f, p + Vector3.new(0, 2, 0), rng:NextNumber(6, 14), Color3.fromRGB(115, 105, 95))
	end)
	-- the bear den: a rock arch with scattered bones
	local den = Vector3.new(-420, 0, 1000)
	den += Vector3.new(0, Props.groundY(den.X, den.Z), 0)
	for i = 0, 6 do
		local a = math.pi * i / 6
		Props.rock(f, den + Vector3.new(math.cos(a) * 11, math.sin(a) * 9, 0), 7, Color3.fromRGB(100, 92, 85))
	end
	for _ = 1, 6 do
		local b = den + Vector3.new(rng:NextNumber(-10, 10), 0.3, rng:NextNumber(-16, -4))
		Props.beam(f, b, b + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), 0.4, Color3.fromRGB(235, 225, 205))
	end
	areaSign(f, Vector3.new(-200, 0, 752), Vector3.new(1, 0, -1), "🐻 Bearclaw Hollow\nHunting • Lv 12-20", Color3.fromRGB(240, 210, 170))
end

local function buildFrostfang(parent: Instance, area)
	local f = WorldUtil.folder("FrostfangRidge", parent)
	hills(area, 10, Enum.Material.Snow)
	scatter(area, 45, 12, nil, function(p)
		Props.tree(f, p, rng:NextNumber(1.1, 1.7), "snowpine")
	end)
	scatter(area, 14, 10, nil, function(p)
		local r = Props.rock(f, p + Vector3.new(0, 1.5, 0), rng:NextNumber(4, 9), Color3.fromRGB(170, 210, 235))
		r.Material = Enum.Material.Ice
	end)
	-- ice-fishing hut on the frozen tarn's shore
	local tarn = Zones.Lakes[4]
	local hut = tarn.center + Vector3.new(-36, 0, -28)
	hut += Vector3.new(0, Props.groundY(hut.X, hut.Z), 0)
	Props.hut(f, WorldUtil.facingCF(hut, tarn.center - hut))
	areaSign(f, Vector3.new(262, 0, 772), Vector3.new(-1, 0, -1), "🐺 Frostfang Ridge\nHunting • Lv 16-24", Color3.fromRGB(200, 235, 255))
end

function Wilds.build(map: Folder)
	local wilds = WorldUtil.folder("Wilds", map)
	local builders = {
		ElkMeadows = buildElkMeadows,
		Whisperwood = buildWhisperwood,
		BearclawHollow = buildBearclaw,
		FrostfangRidge = buildFrostfang,
	}
	for _, area in ipairs(Zones.HuntingGrounds) do
		local fn = builders[area.id]
		if fn then
			fn(wilds, area)
		end
	end
	for _, lake in ipairs(Zones.Lakes) do
		lakeDecor(wilds, lake)
	end
	local spots = WorldUtil.folder("FishingSpots", wilds)
	for _, spot in ipairs(Zones.FishingSpots) do
		local model = Props.fishingSpot(spots, spot.pos, spot.id, spot.kind == "Ice")
		CollectionService:AddTag(model, "FishingSpot")
	end
end

return Wilds
