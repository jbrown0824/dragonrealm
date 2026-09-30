-- Builds the dungeons: the cave mouths in the viking lands (entrance), and the interiors, carved out
-- of terrain far off the map from the layouts in Config/Dungeons (interior).
--
-- An interior is carved in four passes so the spaces join up cleanly: a rock shell around every
-- space, then the air inside all of them, then their floors, then the features (pillars, pools,
-- ledges, ramps, lava, bridges, the spiral). Floors are terrain, so the usual ground raycasts
-- (EnemyService.terrainGround) find them; walls and ceilings are terrain too. Decorations are
-- parts in the returned folder (under workspace.Map, so attacks and service raycasts see them).
-- Then it's dressed: torches along the tunnels and walls, lamps high in the rooms, glowing lava,
-- the keeper and the provisions by the entrance, the hoard, and the boss rooms' doors. The doors
-- are solid, so they live in workspace.Barriers (outside Map: service raycasts never see them);
-- DungeonService opens and seals them with DungeonBuilder.setDoor.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DragonBuilder = require(Shared.DragonBuilder)
local Dungeons = require(Shared.Config.Dungeons)
local DungeonNav = require(Shared.DungeonNav)

local Props = require(script.Parent.Props)
local WorldUtil = require(script.Parent.WorldUtil)

local DungeonBuilder = {}

local SHELL = 10 -- rock around each space
local IVORY = Color3.fromRGB(232, 224, 205)
local STONE = Color3.fromRGB(110, 112, 116)
local DARK_STONE = Color3.fromRGB(70, 70, 76)
local IRON = Color3.fromRGB(60, 60, 68)

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.IgnoreWater = true

local function mat(name: string): Enum.Material
	return Enum.Material[name]
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The terrain floor under a point inside a dungeon (cast from just above it, under the ceiling).
function DungeonBuilder.floorAt(pos: Vector3, fromAbove: number?): Vector3
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	local ray = workspace:Raycast(pos + Vector3.new(0, fromAbove or 6, 0), Vector3.new(0, -60, 0), terrainParams)
	return ray and ray.Position or pos
end

---------------------------------------------------------------- terrain passes

-- A frame along a tunnel segment from floor point a to b (z along the slope, y "up" off the floor).
local function segmentFrame(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	return CFrame.lookAt(mid, mid + (b - a).Unit)
end

-- The spiral ramp's segments: { a, b } floor points along its middle line, and its width.
local function spiralSegments(f, origin: Vector3)
	local list = {}
	local steps = math.max(2, math.ceil(math.abs(f.to - f.from) / 15))
	local mid = (f.inner + f.outer) / 2
	for i = 0, steps - 1 do
		local function point(k: number): Vector3
			local deg = f.from + (f.to - f.from) * k
			local a = math.rad(deg)
			local y = f.topY + (f.bottomY - f.topY) * k
			return origin + f.center + Vector3.new(math.cos(a) * mid, 0, math.sin(a) * mid) + Vector3.new(0, y - f.center.Y, 0)
		end
		table.insert(list, { point(i / steps), point((i + 1) / steps) })
	end
	return list, f.outer - f.inner
end

local function shellPass(terrain, def, origin: Vector3, shell: Enum.Material)
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "box" then
			local c = origin + sp.at
			local bottom, top = c.Y - 12, c.Y + sp.height + SHELL
			terrain:FillBlock(CFrame.new(c.X, (bottom + top) / 2, c.Z), Vector3.new(sp.size.X + SHELL * 2, top - bottom, sp.size.Y + SHELL * 2), shell)
		elseif sp.kind == "round" then
			local c = origin + sp.at
			local bottom, top = c.Y - 12, c.Y + sp.height + (sp.dome and sp.radius * 0.7 or 0) + SHELL
			terrain:FillBlock(CFrame.new(c.X, (bottom + top) / 2, c.Z), Vector3.new(sp.radius * 2 + SHELL * 2, top - bottom, sp.radius * 2 + SHELL * 2), shell)
		elseif sp.kind == "path" then
			for i = 1, #sp.points - 1 do
				local a, b = origin + sp.points[i], origin + sp.points[i + 1]
				local frame = segmentFrame(a, b)
				terrain:FillBlock(frame * CFrame.new(0, sp.height / 2 - 1, 0), Vector3.new(sp.width + SHELL * 2, sp.height + 22, (b - a).Magnitude + SHELL * 2), shell)
			end
			for i = 2, #sp.points - 1 do
				local p = origin + sp.points[i]
				terrain:FillCylinder(CFrame.new(p + Vector3.new(0, sp.height / 2 - 1, 0)), sp.height + 22, sp.width / 2 + SHELL, shell)
			end
		end
	end
end

local function airPass(terrain, def, origin: Vector3)
	local air = Enum.Material.Air
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "box" then
			local c = origin + sp.at
			terrain:FillBlock(CFrame.new(c + Vector3.new(0, sp.height / 2, 0)), Vector3.new(sp.size.X, sp.height, sp.size.Y), air)
		elseif sp.kind == "round" then
			local c = origin + sp.at
			terrain:FillCylinder(CFrame.new(c + Vector3.new(0, sp.height / 2, 0)), sp.height, sp.radius, air)
			if sp.dome then
				terrain:FillBall(c + Vector3.new(0, sp.height - sp.radius * 0.3, 0), sp.radius, air)
			end
		elseif sp.kind == "path" then
			for i = 1, #sp.points - 1 do
				local a, b = origin + sp.points[i], origin + sp.points[i + 1]
				local frame = segmentFrame(a, b)
				terrain:FillBlock(frame * CFrame.new(0, sp.height / 2, 0), Vector3.new(sp.width, sp.height, (b - a).Magnitude + 4), air)
			end
			for i = 2, #sp.points - 1 do
				local p = origin + sp.points[i]
				terrain:FillCylinder(CFrame.new(p + Vector3.new(0, sp.height / 2, 0)), sp.height, sp.width / 2, air)
			end
		end
	end
end

local function floorPass(terrain, def, origin: Vector3, shell: Enum.Material, floorMat: Enum.Material)
	for _, sp in ipairs(def.spaces) do
		local m = sp.floor and mat(sp.floor) or floorMat
		if sp.kind == "box" then
			local c = origin + sp.at
			terrain:FillBlock(CFrame.new(c - Vector3.new(0, 2, 0)), Vector3.new(sp.size.X, 4, sp.size.Y), m)
		elseif sp.kind == "round" then
			local c = origin + sp.at
			if sp.dome then
				-- the dome's ball dipped under the floor: fill it back in
				terrain:FillCylinder(CFrame.new(c - Vector3.new(0, 8, 0)), 12, sp.radius, shell)
			end
			terrain:FillCylinder(CFrame.new(c - Vector3.new(0, 2, 0)), 4, sp.radius, m)
		elseif sp.kind == "path" then
			for i = 1, #sp.points - 1 do
				local a, b = origin + sp.points[i], origin + sp.points[i + 1]
				local frame = segmentFrame(a, b)
				terrain:FillBlock(frame * CFrame.new(0, -2, 0), Vector3.new(sp.width, 4, (b - a).Magnitude + 2), m)
			end
			for i = 2, #sp.points - 1 do
				local p = origin + sp.points[i]
				terrain:FillCylinder(CFrame.new(p - Vector3.new(0, 2, 0)), 4, sp.width / 2, m)
			end
		end
	end
end

-- Axis-aligned box from two corners (the y range may be empty: `y0`..`y1` override it).
local function fillBox(terrain, a: Vector3, b: Vector3, y0: number, y1: number, m: Enum.Material)
	local min = Vector3.new(math.min(a.X, b.X), y0, math.min(a.Z, b.Z))
	local max = Vector3.new(math.max(a.X, b.X), y1, math.max(a.Z, b.Z))
	terrain:FillBlock(CFrame.new((min + max) / 2), max - min, m)
end

-- A strip `width` wide from a to b (flat), from y0 up to y1.
local function fillStrip(terrain, a: Vector3, b: Vector3, width: number, y0: number, y1: number, m: Enum.Material)
	local mid = (a + b) / 2
	local dir = flat(b - a)
	local cf = CFrame.lookAt(Vector3.new(mid.X, (y0 + y1) / 2, mid.Z), Vector3.new(mid.X, (y0 + y1) / 2, mid.Z) + dir)
	terrain:FillBlock(cf, Vector3.new(width, y1 - y0, dir.Magnitude), m)
end

local function featurePass(terrain, def, origin: Vector3, shell: Enum.Material, floorMat: Enum.Material, lavaParts: { Vector3 })
	for _, f in ipairs(def.features or {}) do
		if f.kind == "pillars" then
			for _, p in ipairs(f.points) do
				local w = origin + p
				terrain:FillCylinder(CFrame.new(w + Vector3.new(0, f.height / 2, 0)), f.height, f.radius, shell)
			end
		elseif f.kind == "pool" then
			local a, b = origin + f.min, origin + f.max
			fillBox(terrain, a, b, a.Y - f.depth, a.Y, Enum.Material.Air)
			fillBox(terrain, a, b, a.Y - f.depth - 3, a.Y - f.depth, mat("Mud"))
			fillBox(terrain, a, b, a.Y - f.depth, a.Y - f.depth + f.water, Enum.Material.Water)
		elseif f.kind == "walkway" then
			local a, b = origin + f.from, origin + f.to
			fillStrip(terrain, a, b, f.width, a.Y - 4, a.Y, mat("Cobblestone"))
		elseif f.kind == "ledge" then
			local a, b = origin + f.min, origin + f.max
			fillBox(terrain, a, b, a.Y - 2, b.Y, shell)
			fillBox(terrain, a, b, b.Y - 2, b.Y, floorMat)
		elseif f.kind == "ramp" then
			local a, b = origin + f.from, origin + f.to
			local frame = segmentFrame(a, b)
			terrain:FillBlock(frame * CFrame.new(0, -3, 0), Vector3.new(f.width, 6, (b - a).Magnitude + 2), floorMat)
		elseif f.kind == "lava" then
			local a, b = origin + f.min, origin + f.max
			fillBox(terrain, a, b, a.Y - f.depth, a.Y + 1, Enum.Material.Air)
			fillBox(terrain, a, b, a.Y - f.depth - 3, a.Y - f.depth, mat("CrackedLava"))
			for x = math.min(a.X, b.X) + 8, math.max(a.X, b.X) - 8, 16 do
				table.insert(lavaParts, Vector3.new(x, a.Y - f.depth + 0.2, (a.Z + b.Z) / 2))
			end
		elseif f.kind == "bridge" then
			local a, b = origin + f.from, origin + f.to
			fillStrip(terrain, a, b, f.width, a.Y - 8, a.Y, shell)
			fillStrip(terrain, a, b, f.width - 2, a.Y - 2, a.Y, floorMat)
		elseif f.kind == "spiral" then
			local segments, width = spiralSegments(f, origin)
			local base = origin.Y + f.baseY
			for _, seg in ipairs(segments) do
				local a, b = seg[1], seg[2]
				local frame = segmentFrame(a, b)
				local thick = (a.Y + b.Y) / 2 - base + 4
				terrain:FillBlock(frame * CFrame.new(0, -thick / 2, 0), Vector3.new(width + 2, thick, (b - a).Magnitude + 3), shell)
				terrain:FillBlock(frame * CFrame.new(0, -1.5, 0), Vector3.new(width + 2, 3, (b - a).Magnitude + 3), floorMat)
			end
		end
	end
end

---------------------------------------------------------------- decor

local function brazier(parent: Instance, pos: Vector3, theme)
	Props.column(parent, pos, 3.2, 2.4, DARK_STONE, Enum.Material.Slate)
	local bowl = Props.part(parent, Vector3.new(0.8, 3.8, 3.8), CFrame.new(pos + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), IRON, Enum.Material.Metal)
	bowl.Shape = Enum.PartType.Cylinder
	local coals = Props.ellipsoid(parent, Vector3.new(3, 1, 3), CFrame.new(pos + Vector3.new(0, 4, 0)), theme.accent, Enum.Material.Neon)
	coals.CanCollide = false
	Props.fire(coals, 4, theme.accent)
	Props.light(coals, theme.light, 36, 2.2)
end

local function sarcophagus(parent: Instance, pos: Vector3, face: Vector3, theme)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
	Props.part(parent, Vector3.new(5, 2.6, 9), cf * CFrame.new(0, 1.3, 0), STONE, Enum.Material.Slate)
	Props.part(parent, Vector3.new(5.6, 0.6, 9.6), cf * CFrame.new(0, 2.9, 0), DARK_STONE, Enum.Material.Slate)
	Props.ellipsoid(parent, Vector3.new(2.6, 0.9, 6.4), cf * CFrame.new(0, 3.5, 0.4), STONE, Enum.Material.Slate)
	Props.ellipsoid(parent, Vector3.new(1.6, 1.1, 1.6), cf * CFrame.new(0, 3.7, -3.4), STONE, Enum.Material.Slate)
	local rune = Props.part(parent, Vector3.new(0.15, 0.4, 6), CFrame.new(pos + face.Unit * 2.55 + Vector3.new(0, 1.6, 0)), theme.accent, Enum.Material.Neon)
	rune.CanCollide = false
end

local function standingStones(parent: Instance, center: Vector3, radius: number, count: number, skip: Vector3?, theme, rng: Random)
	for i = 1, count do
		local a = (i - 0.5) / count * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		if not (skip and dir:Dot(skip.Unit) > 0.92) then
			local h = rng:NextNumber(11, 16)
			local base = DungeonBuilder.floorAt(center + dir * radius)
			local cf = CFrame.lookAt(base + Vector3.new(0, h / 2 - 0.5, 0), Vector3.new(center.X, base.Y + h / 2 - 0.5, center.Z)) * CFrame.Angles(0, 0, rng:NextNumber(-0.06, 0.06))
			Props.part(parent, Vector3.new(4.4, h, 2.2), cf, DARK_STONE, Enum.Material.Slate)
			local rune = Props.part(parent, Vector3.new(0.5, h * 0.55, 0.2), cf * CFrame.new(0, 0.5, -1.15), theme.accent, Enum.Material.Neon)
			rune.CanCollide = false
		end
	end
end

-- (The seat is low enough for a giant with stiff legs: Haldor sits here until he wakes. Its top is
-- THRONE_SEAT above the floor.)
DungeonBuilder.THRONE_SEAT = 4
local function throne(parent: Instance, pos: Vector3, face: Vector3, theme)
	local cf = CFrame.lookAt(pos, pos + face)
	Props.part(parent, Vector3.new(16, 2, 12), cf * CFrame.new(0, 1, 0), DARK_STONE, Enum.Material.Slate)
	Props.part(parent, Vector3.new(9, 2, 7), cf * CFrame.new(0, 3, 1), STONE, Enum.Material.Slate)
	Props.part(parent, Vector3.new(10, 14, 2), cf * CFrame.new(0, 9, 4.5), STONE, Enum.Material.Slate)
	for _, x in ipairs({ -4.6, 4.6 }) do
		Props.part(parent, Vector3.new(1.4, 3, 7), cf * CFrame.new(x, 6, 1), DARK_STONE, Enum.Material.Slate)
	end
	local skull = Props.ellipsoid(parent, Vector3.new(2.6, 2.4, 2.4), cf * CFrame.new(0, 16.8, 4.2), IVORY, Enum.Material.Slate)
	skull.CanCollide = false
	local glow = Props.part(parent, Vector3.new(6, 0.3, 0.2), cf * CFrame.new(0, 12, 3.4), theme.accent, Enum.Material.Neon)
	glow.CanCollide = false
	Props.light(glow, theme.light, 30, 1.6)
end

local function bones(parent: Instance, at: Vector3, spread: number, count: number, rng: Random)
	for i = 1, count do
		local p = at + Vector3.new(rng:NextNumber(-spread, spread), 0, rng:NextNumber(-spread, spread))
		local ground = DungeonBuilder.floorAt(p)
		if i % 3 == 0 then
			local skull = Props.ellipsoid(parent, Vector3.new(1.3, 1.1, 1.4), CFrame.new(ground + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), IVORY, Enum.Material.Slate)
			skull.CanCollide = false
		else
			local bone = Props.part(parent, Vector3.new(0.35, 0.35, rng:NextNumber(1.6, 3)), CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), IVORY, Enum.Material.Slate)
			bone.CanCollide = false
		end
	end
end

local function anvils(parent: Instance, at: Vector3, rng: Random)
	for i = 0, 2 do
		local p = DungeonBuilder.floorAt(at + Vector3.new(math.cos(i * 2.1) * 4, 0, math.sin(i * 2.1) * 4))
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		Props.part(parent, Vector3.new(2.4, 2.6, 2.4), cf * CFrame.new(0, 1.3, 0), DARK_STONE, Enum.Material.Slate)
		Props.part(parent, Vector3.new(1.4, 1.2, 1.6), cf * CFrame.new(0, 3.2, 0), IRON, Enum.Material.Metal)
		Props.part(parent, Vector3.new(4.6, 1.1, 1.8), cf * CFrame.new(0.4, 4.3, 0), IRON, Enum.Material.Metal)
	end
	Props.crate(parent, DungeonBuilder.floorAt(at + Vector3.new(0, 0, -6)), 3)
end

local function forge(parent: Instance, pos: Vector3, face: Vector3, theme)
	local cf = CFrame.lookAt(pos, pos + face)
	Props.part(parent, Vector3.new(12, 3, 8), cf * CFrame.new(0, 1.5, 0), DARK_STONE, Enum.Material.Slate)
	Props.part(parent, Vector3.new(12, 6, 2), cf * CFrame.new(0, 6, 3), DARK_STONE, Enum.Material.Slate)
	for _, x in ipairs({ -5, 5 }) do
		Props.part(parent, Vector3.new(2, 6, 8), cf * CFrame.new(x, 6, 0), DARK_STONE, Enum.Material.Slate)
	end
	Props.part(parent, Vector3.new(12, 2, 8), cf * CFrame.new(0, 10, 0), STONE, Enum.Material.Slate)
	Props.part(parent, Vector3.new(5, 18, 5), cf * CFrame.new(0, 20, 1.5), DARK_STONE, Enum.Material.Slate)
	local coals = Props.part(parent, Vector3.new(8, 1, 6), cf * CFrame.new(0, 3.5, 0), theme.accent, Enum.Material.Neon)
	coals.CanCollide = false
	Props.fire(coals, 6, theme.accent)
	Props.light(coals, theme.light, 40, 2.4)
end

local function chains(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local links = math.max(2, math.floor(length / 3))
	local sag = length * 0.08
	for i = 0, links do
		local k = i / links
		local p = a:Lerp(b, k) - Vector3.new(0, sag * 4 * k * (1 - k), 0)
		local link = Props.part(parent, Vector3.new(0.5, 1.2, 2.6), CFrame.lookAt(p, p + (b - a)) * CFrame.Angles(0, 0, i % 2 == 0 and 0 or math.rad(90)), IRON, Enum.Material.Metal)
		link.CanCollide = false
	end
end

local function runeCircle(parent: Instance, center: Vector3, radius: number, theme)
	local floor = DungeonBuilder.floorAt(center)
	for i = 1, 28 do
		local a = i / 28 * math.pi * 2
		local p = Vector3.new(center.X + math.cos(a) * radius, floor.Y + 0.1, center.Z + math.sin(a) * radius)
		local rune = Props.part(parent, Vector3.new(3.4, 0.2, 1), CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)) * CFrame.Angles(0, math.rad(90), 0), theme.accent, Enum.Material.Neon)
		rune.CanCollide = false
		rune.Transparency = 0.25
	end
end

local function shields(parent: Instance, pos: Vector3, face: Vector3)
	local cf = CFrame.lookAt(pos, pos + face)
	for i, x in ipairs({ -7, 0, 7 }) do
		local c = cf * CFrame.new(x, 12 + (i == 2 and 2 or 0), 0.4) * CFrame.Angles(0, math.rad(90), 0)
		local s = Props.part(parent, Vector3.new(0.4, 5, 5), c, ({ Color3.fromRGB(150, 40, 35), Color3.fromRGB(60, 70, 120), Color3.fromRGB(200, 170, 60) })[i], Enum.Material.Wood)
		s.Shape = Enum.PartType.Cylinder
		local boss = Props.part(parent, Vector3.new(0.6, 1.4, 1.4), c * CFrame.new(-0.4, 0, 0), IRON, Enum.Material.Metal)
		boss.Shape = Enum.PartType.Cylinder
	end
end

-- The way out: a stone arch (two pillars and a round top) with the glow filling it.
local function exitPortal(parent: Instance, pos: Vector3, theme): BasePart
	local cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
	local HALF, LEG, R = 8, 12, 8 -- half the opening's width, the pillars' height, the arch's radius
	for _, x in ipairs({ -HALF - 1.6, HALF + 1.6 }) do
		Props.part(parent, Vector3.new(3.2, LEG, 3.2), cf * CFrame.new(x, LEG / 2, 0), DARK_STONE, Enum.Material.Slate)
		Props.part(parent, Vector3.new(4, 1, 4), cf * CFrame.new(x, 0.5, 0), STONE, Enum.Material.Slate)
	end
	for i = 0, 12 do
		local a = math.pi * i / 12
		local p = cf * CFrame.new(math.cos(a) * (R + 1.6), LEG + math.sin(a) * (R + 1.6), 0)
		Props.part(parent, Vector3.new(3.2, 3.2, 3.2), CFrame.lookAt(p.Position, p.Position + cf.LookVector) * CFrame.Angles(0, 0, a), DARK_STONE, Enum.Material.Slate)
	end
	local keystone = Props.part(parent, Vector3.new(2.2, 3.4, 3.6), cf * CFrame.new(0, LEG + R + 1.6, 0), theme.accent, Enum.Material.Neon)
	keystone.CanCollide = false
	-- the glow: the square part, then slices of the round top (none overlapping, none sticking out)
	local glowParts = {}
	local swirl = Props.part(parent, Vector3.new(HALF * 2, LEG, 0.4), cf * CFrame.new(0, LEG / 2, 0.2), theme.accent, Enum.Material.Neon)
	swirl.Name = "ExitPortal"
	table.insert(glowParts, swirl)
	local slices = 6
	for i = 0, slices - 1 do
		local y0, y1 = R * i / slices, R * (i + 1) / slices
		local ym = (y0 + y1) / 2
		local w = 2 * math.sqrt(math.max(0, R * R - ym * ym))
		table.insert(glowParts, Props.part(parent, Vector3.new(math.max(1, w), y1 - y0, 0.4), cf * CFrame.new(0, LEG + ym, 0.2), theme.accent, Enum.Material.Neon))
	end
	for _, g in ipairs(glowParts) do
		g.Transparency = 0.45
		g.CanCollide = false
		g.CastShadow = false
	end
	Props.light(swirl, theme.light, 30, 2)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Leave dungeon"
	prompt.ObjectText = "Way out"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.Parent = swirl
	CollectionService:AddTag(prompt, "DungeonExit")
	return swirl
end

-- The hidden hoard: a treasure chest like the camp ones (tag "DungeonChest", `OneTime`). Every
-- dragon in the run can open it once; each client draws it open (lid up, treasure gone, no
-- prompt) for itself from its ChestReady_<id> attribute (WorldView), like the camp chests.
local function bonusChest(parent: Instance, pos: Vector3, chestId: string): Model
	local ground = DungeonBuilder.floorAt(pos)
	local model = Props.chest(parent, WorldUtil.facingCF(ground, Vector3.new(0, 0, -1)), chestId)
	model.Name = "Hoard"
	model:SetAttribute("OneTime", true)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	prompt.ActionText = "Open"
	prompt.ObjectText = "Hidden hoard"
	prompt.HoldDuration = 2
	CollectionService:AddTag(model, "DungeonChest")
	return model
end

-- A table of food by the entrance: eat once per run to fill up (tag "DungeonFood").
local function provisions(parent: Instance, pos: Vector3)
	local ground = DungeonBuilder.floorAt(pos)
	local cf = CFrame.lookAt(ground, ground + Vector3.new(0, 0, 1))
	local wood = Color3.fromRGB(110, 75, 45)
	local top = Props.part(parent, Vector3.new(9, 0.8, 4.4), cf * CFrame.new(0, 3.2, 0), wood, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -3.8, 3.8 }) do
		for _, z in ipairs({ -1.6, 1.6 }) do
			Props.part(parent, Vector3.new(0.6, 2.8, 0.6), cf * CFrame.new(x, 1.4, z), wood, Enum.Material.Wood)
		end
	end
	-- a roast, bread, apples and a mead jug
	Props.ellipsoid(parent, Vector3.new(2.6, 1.4, 1.8), cf * CFrame.new(-2.4, 4.2, 0), Color3.fromRGB(150, 80, 40), Enum.Material.SmoothPlastic)
	Props.part(parent, Vector3.new(0.4, 0.4, 2.6), cf * CFrame.new(-2.4, 4.4, 0) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(235, 225, 200))
	Props.ellipsoid(parent, Vector3.new(1.8, 1, 1.2), cf * CFrame.new(0.2, 4.1, -0.6), Color3.fromRGB(215, 170, 100), Enum.Material.SmoothPlastic)
	for i, x in ipairs({ 1.4, 2, 1.7 }) do
		Props.ellipsoid(parent, Vector3.new(0.8, 0.8, 0.8), cf * CFrame.new(x, 4, 0.7 + i * 0.25), Color3.fromRGB(200, 50, 40), Enum.Material.SmoothPlastic)
	end
	Props.column(parent, (cf * CFrame.new(3.3, 3.6, -0.8)).Position, 1.8, 1.2, Color3.fromRGB(150, 120, 80), Enum.Material.Wood)
	Props.torch(parent, (cf * CFrame.new(-6, 0, 0)).Position)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Eat"
	prompt.ObjectText = "Provisions"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = top
	CollectionService:AddTag(prompt, "DungeonFood")
	return top
end

-- The elder dragon chained at the back of the Rune Forge (anchored; its fire comes from the boss
-- fight's Lane move).
local function chainedDragon(parent: Instance, origin: Vector3, spec, theme)
	local model = DragonBuilder.build("Behemoth", {
		scale = 3.4,
		anchored = true,
		name = "Chained Elder Dragon",
		colors = {
			primary = Color3.fromRGB(120, 40, 30), secondary = Color3.fromRGB(60, 22, 18), belly = Color3.fromRGB(255, 180, 100),
			accent = Color3.fromRGB(255, 140, 50), eyes = Color3.fromRGB(255, 230, 120), wing = Color3.fromRGB(150, 50, 30), horn = Color3.fromRGB(230, 210, 180),
		},
	})
	local at = origin + spec.at
	model:PivotTo(CFrame.lookAt(at + Vector3.new(0, 6, 0), at + Vector3.new(0, 6, 0) + spec.face))
	model.Parent = parent
	local chainFolder = Instance.new("Folder")
	chainFolder.Name = "Chains"
	chainFolder.Parent = parent
	local body = at + Vector3.new(0, 8, 0)
	for _, anchor in ipairs({ Vector3.new(-60, 26, 6), Vector3.new(60, 26, 6), Vector3.new(-40, 34, 26), Vector3.new(40, 34, 26) }) do
		chains(chainFolder, body, at + anchor)
	end
	local glow = Props.part(parent, Vector3.new(1, 1, 1), CFrame.new(body), theme.accent, Enum.Material.Neon)
	glow.Transparency = 1
	glow.CanCollide = false
	Props.light(glow, theme.light, 50, 2)
	return model, chainFolder
end

---------------------------------------------------------------- light

-- An unseen lamp high in a room (a PointLight reaches 60 studs at most, so big rooms get several).
local function lamp(parent: Instance, pos: Vector3, color: Color3, range: number, brightness: number)
	local p = Props.part(parent, Vector3.new(1, 1, 1), CFrame.new(pos), color, Enum.Material.Neon)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	Props.light(p, color, range, brightness)
	return p
end

-- A torch on an iron bracket, on the wall by the floor point `pos` (`inward` points off the wall).
local function sconce(parent: Instance, pos: Vector3, inward: Vector3, theme)
	local at = pos + Vector3.new(0, 8, 0)
	local cf = CFrame.lookAt(at, at + inward)
	local arm = Props.part(parent, Vector3.new(0.5, 0.5, 2), cf * CFrame.new(0, 0, -0.8), IRON, Enum.Material.Metal)
	arm.CanCollide = false
	local cup = Props.part(parent, Vector3.new(1.3, 0.7, 1.3), cf * CFrame.new(0, 0.1, -1.9), IRON, Enum.Material.Metal)
	cup.CanCollide = false
	local flame = Props.ellipsoid(parent, Vector3.new(1, 1.6, 1), cf * CFrame.new(0, 1.1, -1.9), theme.accent, Enum.Material.Neon)
	flame.CanCollide = false
	flame.CastShadow = false
	Props.light(flame, theme.light, 30, 1.6)
end

local function nearAny(p: Vector3, spots: { Vector3 }, dist: number): boolean
	for _, q in ipairs(spots) do
		if flat(q - p).Magnitude < dist then
			return true
		end
	end
	return false
end

-- Torches every ~24 studs along each tunnel (alternating walls, off the bends and out of the rooms),
-- torches around the rooms' walls every ~34, and lamps high up in a grid across each room.
local function lightUp(parent: Instance, def, origin: Vector3, theme, keepClear: { Vector3 })
	local rooms = {}
	for _, sp in ipairs(def.spaces) do
		if sp.kind ~= "path" then
			table.insert(rooms, sp)
		end
	end
	local function inRoom(localPos: Vector3): boolean
		for _, room in ipairs(rooms) do
			if DungeonNav.spaceHas(room, localPos) then
				return true
			end
		end
		return false
	end
	local side = 1
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "path" then
			for i = 1, #sp.points - 1 do
				local a, b = sp.points[i], sp.points[i + 1]
				local len = flat(b - a).Magnitude
				local dir = flat(b - a).Unit
				local across = Vector3.new(-dir.Z, 0, dir.X)
				for d = 12, len - 10, 24 do
					local k = d / len
					if k > 0.12 and k < 0.88 then
						local mid = a:Lerp(b, k)
						local wall = mid + across * side * (sp.width / 2 - 1.2)
						if not inRoom(mid) and not nearAny(origin + wall, keepClear, 10) then
							sconce(parent, DungeonBuilder.floorAt(origin + wall), -across * side, theme)
						end
						side = -side
					end
				end
			end
		elseif sp.sconces ~= false then
			local c = sp.at
			local spots = {}
			if sp.kind == "box" then
				local hx, hz = sp.size.X / 2, sp.size.Y / 2
				for _, edge in ipairs({ { Vector3.new(-hx, 0, -hz), Vector3.new(hx, 0, -hz) }, { Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz) },
					{ Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz) }, { Vector3.new(-hx, 0, hz), Vector3.new(-hx, 0, -hz) } }) do
					local len = (edge[2] - edge[1]).Magnitude
					if len >= 30 then
						local n = math.max(1, math.floor(len / 34))
						for j = 1, n do
							local p = edge[1]:Lerp(edge[2], (j - 0.5) / n)
							table.insert(spots, p)
						end
					end
				end
			elseif sp.radius >= 20 then
				local n = math.max(4, math.floor(2 * math.pi * sp.radius / 34))
				for j = 1, n do
					local a = (j - 0.5) / n * math.pi * 2
					table.insert(spots, Vector3.new(math.cos(a) * sp.radius, 0, math.sin(a) * sp.radius))
				end
			end
			for _, rel in ipairs(spots) do
				local inward = -flat(rel)
				if sp.kind == "box" then
					-- straight off the wall it's on
					inward = math.abs(math.abs(rel.X) - sp.size.X / 2) < 0.5 and Vector3.new(-math.sign(rel.X), 0, 0) or Vector3.new(0, 0, -math.sign(rel.Z))
				end
				inward = inward.Unit
				local wall = origin + c + rel + inward * 1.2
				-- not in a tunnel's mouth, by a door, or the entrance's things
				local mouth = false
				for _, other in ipairs(def.spaces) do
					if other.kind == "path" then
						for _, q in ipairs({ other.points[1], other.points[#other.points] }) do
							if flat(q - (c + rel)).Magnitude < other.width / 2 + 6 then
								mouth = true
							end
						end
						if DungeonNav.spaceHas(other, c + rel + inward * 1.2) then
							mouth = true
						end
					end
				end
				if not mouth and not nearAny(wall, keepClear, 10) then
					sconce(parent, DungeonBuilder.floorAt(wall, 30), inward, theme)
				end
			end
		end
		-- lamps high up
		if sp.kind == "box" and sp.size.X >= 30 and sp.size.Y >= 30 then
			local nx, nz = math.max(1, math.floor(sp.size.X / 46 + 0.5)), math.max(1, math.floor(sp.size.Y / 46 + 0.5))
			for ix = 1, nx do
				for iz = 1, nz do
					local p = sp.at + Vector3.new((ix - 0.5) / nx * sp.size.X - sp.size.X / 2, math.min(sp.height - 5, 26), (iz - 0.5) / nz * sp.size.Y - sp.size.Y / 2)
					lamp(parent, origin + p, theme.light, 60, 0.9)
				end
			end
		elseif sp.kind == "round" then
			local y = math.min(sp.height - 5, 26)
			lamp(parent, origin + sp.at + Vector3.new(0, y, 0), theme.light, 60, 0.9)
			if sp.radius > 36 then
				for j = 1, 5 do
					local a = j / 5 * math.pi * 2
					lamp(parent, origin + sp.at + Vector3.new(math.cos(a) * sp.radius * 0.6, y, math.sin(a) * sp.radius * 0.6), theme.light, 60, 0.8)
				end
			end
		end
	end
end

local LAVA = Color3.fromRGB(255, 110, 30)

-- Lava glows: hot patches and orange light over every pit of it (hazards), so the rock around reads.
local function lavaGlow(parent: Instance, def, origin: Vector3, rng: Random)
	for _, h in ipairs(def.hazards or {}) do
		if h.center then
			local c = origin + h.center
			local floorY = origin.Y + h.top - 4
			for j = 1, 8 do
				local a = j / 8 * math.pi * 2
				lamp(parent, Vector3.new(c.X + math.cos(a) * h.radius * 0.7, floorY + 5, c.Z + math.sin(a) * h.radius * 0.7), LAVA, 60, 2.2)
			end
			for j = 1, 4 do
				local a = j / 4 * math.pi * 2 + 0.4
				lamp(parent, Vector3.new(c.X + math.cos(a) * h.radius * 0.3, floorY + 22, c.Z + math.sin(a) * h.radius * 0.3), LAVA, 60, 1.6)
			end
			for _ = 1, 6 do
				local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(4, h.radius * 0.4)
				local patch = Props.ellipsoid(parent, Vector3.new(rng:NextNumber(8, 16), 0.5, rng:NextNumber(8, 16)), CFrame.new(c.X + math.cos(a) * r, floorY + 0.3, c.Z + math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), LAVA, Enum.Material.Neon)
				patch.CanCollide = false
				patch.CastShadow = false
				patch.Transparency = 0.25
			end
		end
	end
end

-- Molten rock pouring slowly down from the ceiling: a glowing column over a darker crust, falling
-- blobs of fire, a splash where it lands, and light all the way up.
local function lavafall(parent: Instance, origin: Vector3, f)
	local base = origin + f.at
	local top = origin.Y + f.top
	local h = top - base.Y
	local center = Vector3.new(base.X, (base.Y + top) / 2, base.Z)
	local cf = CFrame.new(center)
	local crust = Props.part(parent, Vector3.new(f.width + 1.5, h, 3.4), cf, Color3.fromRGB(110, 35, 15), Enum.Material.CrackedLava)
	crust.CanCollide = false
	local flow = Props.part(parent, Vector3.new(f.width, h, 3.8), cf, LAVA, Enum.Material.Neon)
	flow.CanCollide = false
	flow.CastShadow = false
	flow.Transparency = 0.15
	local source = Props.part(parent, Vector3.new(f.width, 1, 4), CFrame.new(center.X, top - 1, center.Z), LAVA, Enum.Material.Neon)
	source.Transparency = 1
	source.CanCollide = false
	local drip = Instance.new("ParticleEmitter")
	drip.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20))
	drip.LightEmission = 1
	drip.Rate = 10
	drip.Lifetime = NumberRange.new(h / 9, h / 7)
	drip.Speed = NumberRange.new(6, 9)
	drip.EmissionDirection = Enum.NormalId.Bottom
	drip.SpreadAngle = Vector2.new(6, 6)
	drip.Size = NumberSequence.new(2.4, 1.2)
	drip.Parent = source
	local pool = Props.ellipsoid(parent, Vector3.new(f.width * 2.2, 0.6, f.width * 2.2), CFrame.new(base + Vector3.new(0, 0.3, 0)), LAVA, Enum.Material.Neon)
	pool.CanCollide = false
	pool.CastShadow = false
	Props.fire(pool, 8, LAVA)
	for k = 0, 2 do
		lamp(parent, base + Vector3.new(0, 4 + (h - 8) * k / 2, 0), LAVA, 60, 2.4)
	end
end

-- A healing draught left on the floor during a boss fight (DungeonService drops them and hands them
-- out): a glowing red flask. Returns its model.
function DungeonBuilder.draught(parent: Instance, floor: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Draught"
	local at = floor + Vector3.new(0, 1.6, 0)
	local red = Color3.fromRGB(235, 50, 70)
	local glass = Props.ellipsoid(model, Vector3.new(2, 2.2, 2), CFrame.new(at), red, Enum.Material.Glass)
	glass.Transparency = 0.25
	local glow = Props.ellipsoid(model, Vector3.new(1.3, 1.3, 1.3), CFrame.new(at), Color3.fromRGB(255, 90, 110), Enum.Material.Neon)
	Props.part(model, Vector3.new(0.7, 1, 0.7), CFrame.new(at + Vector3.new(0, 1.4, 0)), Color3.fromRGB(200, 220, 230), Enum.Material.Glass)
	Props.part(model, Vector3.new(0.8, 0.5, 0.8), CFrame.new(at + Vector3.new(0, 2.1, 0)), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
	for _, p in ipairs(model:GetChildren()) do
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	Props.light(glow, Color3.fromRGB(255, 90, 110), 14, 2)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 150, 170))
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.8, 1.2)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.Parent = glow
	model.Parent = parent
	return model
end

---------------------------------------------------------------- boss doors

-- Where each tunnel comes into a room: just inside the tunnel from the room's edge, the way in (a
-- flat unit vector), and the tunnel's width and height.
local function roomMouths(def, roomId: string)
	local room = nil
	for _, sp in ipairs(def.spaces) do
		if sp.id == roomId then
			room = sp
		end
	end
	local list = {}
	if not room then
		return list
	end
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "path" then
			local n = #sp.points
			for _, ends in ipairs({ { sp.points[1], sp.points[2] }, { sp.points[n], sp.points[n - 1] } }) do
				local inner, outer = ends[1], ends[2]
				if DungeonNav.spaceHas(room, inner) and not DungeonNav.spaceHas(room, outer) then
					local len = (outer - inner).Magnitude
					local edge = inner
					for d = 0, len, 0.5 do
						local p = inner:Lerp(outer, d / len)
						if not DungeonNav.spaceHas(room, p) then
							break
						end
						edge = p
					end
					local dir = flat(inner - outer).Unit
					table.insert(list, { room = roomId, at = edge - dir * 3, dir = dir, width = sp.width, height = math.min(sp.height, room.height) })
				end
			end
		end
	end
	return list
end

-- Two great leaves across the tunnel mouth, hinged at its walls, and a rune seal between them
-- (unseen until the boss's fight seals the room). Parts are anchored; setDoor swings them.
local function buildDoor(parent: Instance, def, mouth, origin: Vector3, theme, index: number)
	local base = DungeonBuilder.floorAt(origin + mouth.at)
	local dir = mouth.dir
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local w, h = mouth.width, mouth.height
	local forge = def.id == "Forge"
	local leafColor = forge and Color3.fromRGB(62, 56, 56) or Color3.fromRGB(78, 68, 56)
	local leafMat = forge and Enum.Material.DiamondPlate or Enum.Material.WoodPlanks
	local model = Instance.new("Model")
	model.Name = "Door" .. index
	model:SetAttribute("Room", mouth.room)
	local leaves = {}
	for _, s in ipairs({ -1, 1 }) do
		local hinge = base + across * (s * w / 2)
		local leaf = Instance.new("Model")
		leaf.Name = s < 0 and "LeafL" or "LeafR"
		local center = base + across * (s * w / 4) + Vector3.new(0, h / 2, 0)
		local cf = CFrame.lookAt(center, center + dir)
		local slab = Props.part(leaf, Vector3.new(w / 2 + 1, h + 1.5, 1.6), cf, leafColor, leafMat)
		slab.Name = "Slab"
		leaf.PrimaryPart = slab
		for _, y in ipairs({ -h * 0.32, 0, h * 0.32 }) do
			Props.part(leaf, Vector3.new(w / 2 + 1, 0.8, 1.9), cf * CFrame.new(0, y, 0), IRON, Enum.Material.Metal)
		end
		Props.part(leaf, Vector3.new(0.9, h * 0.8, 1.9), cf * CFrame.new(s * (w / 4 - 1.2), 0, 0), IRON, Enum.Material.Metal)
		local rune = Props.part(leaf, Vector3.new(0.5, h * 0.35, 2), cf * CFrame.new(-s * (w / 4 - 2.2), 0, 0), theme.accent, Enum.Material.Neon)
		rune.CanCollide = false
		leaf.Parent = model
		-- which way round swings the free edge into the room
		local free = -across * s
		local spin = CFrame.Angles(0, math.rad(90), 0):VectorToWorldSpace(free):Dot(dir) > 0 and 1 or -1
		leaves[s] = { model = leaf, hinge = hinge, closed = leaf:GetPivot(), spin = spin }
	end
	local sealCF = CFrame.lookAt(base + Vector3.new(0, h / 2, 0) + dir * 1.4, base + Vector3.new(0, h / 2, 0) + dir * 2)
	local seal = Props.part(model, Vector3.new(w + 2, h + 2, 0.6), sealCF, theme.accent, Enum.Material.ForceField)
	seal.Name = "Seal"
	seal.Transparency = 1
	seal.CanCollide = false
	seal.CastShadow = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open the doors"
	local bossId = (def.miniBoss.room == mouth.room and def.miniBoss.id) or def.boss.id
	prompt.ObjectText = Dungeons.Bosses[bossId].name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = Dungeons.DOOR_HOLD
	prompt.MaxActivationDistance = math.max(16, w / 2 + 6)
	prompt.RequiresLineOfSight = false
	prompt.Parent = seal
	CollectionService:AddTag(prompt, "DungeonDoor")
	model.Parent = parent
	return { room = mouth.room, model = model, leaves = leaves, seal = seal, prompt = prompt, pos = base, dir = dir, width = w, height = h, state = "closed" }
end

local function swingTo(door, angle: number)
	for _, leaf in pairs(door.leaves) do
		local hinge = leaf.hinge
		leaf.model:PivotTo(CFrame.new(hinge) * CFrame.Angles(0, angle * leaf.spin, 0) * CFrame.new(-hinge) * leaf.closed)
	end
end

local function setSolid(door, solid: boolean)
	for _, leaf in pairs(door.leaves) do
		for _, p in ipairs(leaf.model:GetDescendants()) do
			if p:IsA("BasePart") and p.Material ~= Enum.Material.Neon then
				p.CanCollide = solid
			end
		end
	end
end

-- A boss door's state: "closed" (shut, you can push it open), "open" (swung into the room),
-- "sealed" (shut, with the rune seal glowing across it: nobody in or out). `animate` swings it.
function DungeonBuilder.setDoor(door, state: string, animate: boolean?)
	local was = door.state
	door.state = state
	local open = state == "open"
	door.prompt.Enabled = state == "closed"
	door.seal.Transparency = state == "sealed" and 0.35 or 1
	door.seal.CanCollide = state == "sealed"
	setSolid(door, not open)
	local from = was == "open" and math.rad(88) or 0
	local to = open and math.rad(88) or 0
	door.swing = (door.swing or 0) + 1
	if not animate or from == to then
		swingTo(door, to)
		return
	end
	local token = door.swing
	task.spawn(function()
		for i = 1, 15 do
			if door.swing ~= token then
				return
			end
			local k = i / 15
			swingTo(door, from + (to - from) * (1 - (1 - k) ^ 2))
			task.wait(0.06)
		end
	end)
end

---------------------------------------------------------------- interior

-- Carve one copy of a dungeon at `origin` and dress it. Returns what DungeonService needs. `slot`
-- tells copies of the same dungeon apart (the hoard's per-player id).
function DungeonBuilder.interior(def, origin: Vector3, parent: Instance, slot: number?)
	local terrain = workspace.Terrain
	local theme = def.theme
	local shell, floorMat = mat(theme.shell), mat(theme.floor)
	local rng = Random.new(#def.id * 7919)
	shellPass(terrain, def, origin, shell)
	airPass(terrain, def, origin)
	floorPass(terrain, def, origin, shell, floorMat)
	local lavaSpots = {}
	featurePass(terrain, def, origin, shell, floorMat, lavaSpots)

	local model = Instance.new("Folder")
	model.Name = def.id
	model.Parent = parent

	-- rooms (for the bosses) and the bounds of the whole thing
	local rooms = {}
	local min, max = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local function grow(p: Vector3)
		min = Vector3.new(math.min(min.X, p.X), math.min(min.Y, p.Y), math.min(min.Z, p.Z))
		max = Vector3.new(math.max(max.X, p.X), math.max(max.Y, p.Y), math.max(max.Z, p.Z))
	end
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "box" or sp.kind == "round" then
			local c = origin + sp.at
			local hx = sp.kind == "box" and sp.size.X / 2 or sp.radius
			local hz = sp.kind == "box" and sp.size.Y / 2 or sp.radius
			local top = sp.height + (sp.dome and sp.radius * 0.7 or 0)
			rooms[sp.id] = { id = sp.id, center = c, radius = math.min(hx, hz), hx = hx, hz = hz, top = c.Y + top, kind = sp.kind }
			grow(c - Vector3.new(hx, 0, hz))
			grow(c + Vector3.new(hx, top, hz))
		else
			for _, p in ipairs(sp.points) do
				grow(origin + p - Vector3.new(sp.width / 2, 0, sp.width / 2))
				grow(origin + p + Vector3.new(sp.width / 2, sp.height, sp.width / 2))
			end
		end
	end

	for _, d in ipairs(def.decor or {}) do
		local kind = d.kind
		if kind == "brazier" then
			brazier(model, DungeonBuilder.floorAt(origin + d.at), theme)
		elseif kind == "sarcophagus" then
			sarcophagus(model, DungeonBuilder.floorAt(origin + d.at), d.face, theme)
		elseif kind == "stones" then
			standingStones(model, origin + d.center, d.radius, d.count, d.skip, theme, rng)
		elseif kind == "throne" then
			throne(model, DungeonBuilder.floorAt(origin + d.at), d.face, theme)
		elseif kind == "bones" then
			bones(model, origin + d.at, d.spread, d.count, rng)
		elseif kind == "anvils" then
			anvils(model, origin + d.at, rng)
		elseif kind == "forge" then
			forge(model, DungeonBuilder.floorAt(origin + d.at), d.face, theme)
		elseif kind == "rack" then
			local p = DungeonBuilder.floorAt(origin + d.at)
			Props.weaponRack(model, CFrame.lookAt(p, p + d.face))
		elseif kind == "chains" then
			chains(model, origin + d.from, origin + d.to)
		elseif kind == "runes" then
			runeCircle(model, origin + d.center, d.radius, theme)
		elseif kind == "shields" then
			shields(model, DungeonBuilder.floorAt(origin + d.at), d.face)
		end
	end
	for _, f in ipairs(def.features or {}) do
		if f.kind == "lavafall" then
			lavafall(model, origin, f)
		end
	end
	-- glowing lava in the channels, and in the pits
	for _, p in ipairs(lavaSpots) do
		local glow = Props.part(model, Vector3.new(15, 0.4, 20), CFrame.new(p), LAVA, Enum.Material.Neon)
		glow.CanCollide = false
		glow.Transparency = 0.2
		Props.fire(glow, 5, LAVA)
		Props.light(glow, LAVA, 45, 2.4)
	end
	lavaGlow(model, def, origin, rng)

	-- the boss rooms' doors (solid, so outside Map: see the header)
	local barriers = workspace:FindFirstChild("Barriers")
	if not barriers then
		barriers = Instance.new("Folder")
		barriers.Name = "Barriers"
		barriers.Parent = workspace
	end
	local doorFolder = Instance.new("Folder")
	doorFolder.Name = string.format("DungeonDoors_%s_%d", def.id, slot or 1)
	doorFolder.Parent = barriers
	local doors = {}
	for _, spec in ipairs({ def.miniBoss, def.boss }) do
		for _, mouth in ipairs(roomMouths(def, spec.room)) do
			table.insert(doors, buildDoor(doorFolder, def, mouth, origin, theme, #doors + 1))
		end
	end

	-- the way out, the keeper and the provisions, the hoard, the chained elder dragon
	local exit = DungeonBuilder.floorAt(origin + def.exit)
	exitPortal(model, exit, theme)
	local keepClear = { exit }
	for _, door in ipairs(doors) do
		-- the middle and both hinges (the leaves swing through there)
		local across = Vector3.new(-door.dir.Z, 0, door.dir.X)
		table.insert(keepClear, door.pos)
		table.insert(keepClear, door.pos + across * door.width / 2)
		table.insert(keepClear, door.pos - across * door.width / 2)
	end
	local keeper, food = nil, nil
	if def.keeper then
		keeper = DungeonBuilder.floorAt(origin + def.keeper.at)
		WorldUtil.questGiver(model, def.giver, keeper, def.keeper.face)
		food = provisions(model, origin + def.keeper.food)
		table.insert(keepClear, keeper)
		table.insert(keepClear, food.Position)
	end
	local chest = def.chest and bonusChest(model, origin + def.chest, string.format("Hoard_%s_%d", def.id, slot or 1))
	if chest then
		table.insert(keepClear, chest:GetPivot().Position)
	end
	local chained = nil
	if def.chained then
		chained = chainedDragon(model, origin, def.chained, theme)
	end
	lightUp(model, def, origin, theme, keepClear)

	local spawn = DungeonBuilder.floorAt(origin + def.spawn)
	return {
		model = model,
		origin = origin,
		spawn = CFrame.lookAt(spawn + Vector3.new(0, 6, 0), spawn + Vector3.new(0, 6, 10)),
		exit = exit,
		rooms = rooms,
		bounds = { min = min - Vector3.new(SHELL, 14, SHELL), max = max + Vector3.new(SHELL, 10, SHELL) },
		chest = chest,
		chained = chained,
		doors = doors,
		keeper = keeper,
		food = food,
	}
end

---------------------------------------------------------------- entrance (in the viking lands)

function DungeonBuilder.entrance(parent: Instance, def)
	local folder = Instance.new("Model")
	folder.Name = "Dungeon_" .. def.id
	local theme = def.theme
	local face = def.entranceFacing.Unit
	local side = Vector3.new(-face.Z, 0, face.X)
	local x, z = def.entrance.X, def.entrance.Z
	local ground = Props.groundY(x, z)
	local base = Vector3.new(x, ground, z)
	local rock = def.id == "Forge" and Color3.fromRGB(70, 60, 58) or Color3.fromRGB(105, 110, 108)

	-- a rocky knoll behind the mouth
	workspace.Terrain:FillBall(base - face * 18 + Vector3.new(0, -8, 0), 30, mat(theme.shell))
	-- the arch: two great rocks and a lintel, with the dark mouth between them
	for _, s in ipairs({ -1, 1 }) do
		Props.part(folder, Vector3.new(9, 22, 10), CFrame.lookAt(base + side * 11 * s + Vector3.new(0, 9, 0), base + side * 11 * s + Vector3.new(0, 9, 0) + face) * CFrame.Angles(0, 0, -0.08 * s), rock, Enum.Material.Slate)
	end
	Props.part(folder, Vector3.new(32, 7, 11), CFrame.lookAt(base + Vector3.new(0, 21, 0), base + Vector3.new(0, 21, 0) + face) * CFrame.Angles(0, 0, 0.04), rock, Enum.Material.Slate)
	local mouth = Props.part(folder, Vector3.new(14, 17, 1), CFrame.lookAt(base + Vector3.new(0, 8.5, 0) - face * 2, base + Vector3.new(0, 8.5, 0) + face), Color3.fromRGB(8, 8, 12), Enum.Material.SmoothPlastic)
	mouth.Name = "Mouth"
	mouth.CanCollide = false
	local swirl = Props.part(folder, Vector3.new(12, 15, 0.3), CFrame.lookAt(base + Vector3.new(0, 8.5, 0) - face * 1.2, base + Vector3.new(0, 8.5, 0) + face), theme.accent, Enum.Material.Neon)
	swirl.Transparency = 0.7
	swirl.CanCollide = false
	Props.light(swirl, theme.light, 28, 2)
	-- braziers on either side
	for _, s in ipairs({ -1, 1 }) do
		local p = base + side * 20 * s + face * 4
		brazier(folder, Vector3.new(p.X, Props.groundY(p.X, p.Z), p.Z), theme)
	end
	if def.id == "Barrow" then
		for _, s in ipairs({ -1, 1 }) do
			local p = base + side * 30 * s - face * 2
			local h = 13
			Props.part(folder, Vector3.new(4, h, 2.4), CFrame.lookAt(Vector3.new(p.X, Props.groundY(p.X, p.Z) + h / 2 - 1, p.Z), Vector3.new(p.X, Props.groundY(p.X, p.Z) + h / 2 - 1, p.Z) + face), DARK_STONE, Enum.Material.Slate)
		end
		local skull = Props.ellipsoid(folder, Vector3.new(3.4, 3, 3), CFrame.new(base + Vector3.new(0, 25.5, 0) + face * 3), IVORY, Enum.Material.Slate)
		skull.CanCollide = false
	else
		for _, s in ipairs({ -1, 1 }) do
			chains(folder, base + side * 14 * s + Vector3.new(0, 19, 0) + face * 5, base + side * 20 * s + Vector3.new(0, 3, 0) + face * 8)
		end
	end
	-- boulders tumbled around the mouth
	local rng = Random.new(#def.id * 131)
	for i = 1, 7 do
		local a = math.rad(-80 + i * 22)
		local p = base - face * 6 + (side * math.sin(a) - face * math.cos(a) * 0.4) * rng:NextNumber(20, 28)
		Props.rock(folder, Vector3.new(p.X, Props.groundY(p.X, p.Z) + 1, p.Z), rng:NextNumber(4, 8), rock)
	end
	-- (the sign on the side away from the keeper, Zones.QuestGivers)
	Props.sign(folder, CFrame.lookAt(base + face * 14 - side * 16 + Vector3.new(0, 5, 0), base + face * 40 - side * 16 + Vector3.new(0, 5, 0)),
		string.format("%s %s\nDungeon  •  Level %d+", def.icon, def.name, def.minLevel), Vector2.new(15, 5), theme.accent, Color3.fromRGB(45, 40, 38))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter"
	prompt.ObjectText = def.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 24
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Panel", "Dungeons")
	prompt:SetAttribute("DungeonId", def.id)
	prompt.Parent = mouth
	CollectionService:AddTag(prompt, "PanelPrompt")

	folder.Parent = parent
	return folder
end

return DungeonBuilder
