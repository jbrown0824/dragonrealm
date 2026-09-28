-- Small builders for scenery: trees, rocks, houses, longhouses, tents, fences, signs...
-- Every part is anchored. Rotation helpers: `cf` arguments are full CFrames, `pos` are Vector3s.

local Props = {}

local WOOD = Color3.fromRGB(120, 82, 50)
local DARK_WOOD = Color3.fromRGB(80, 55, 35)
local STONE = Color3.fromRGB(140, 140, 145)

Props.WOOD = WOOD
Props.DARK_WOOD = DARK_WOOD
Props.STONE = STONE

function Props.part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, className: string?)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function Props.ellipsoid(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Props.part(parent, size, cf, color, material)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Vertical cylinder standing on `base` (bottom center).
function Props.column(parent: Instance, base: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?)
	local p = Props.part(parent, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Cylinder between two points.
function Props.beam(parent: Instance, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?)
	local up = Vector3.yAxis
	if math.abs((b - a).Unit:Dot(up)) > 0.98 then
		up = Vector3.zAxis
	end
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
	local p = Props.part(parent, Vector3.new((b - a).Magnitude, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Props.light(parent: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
	return l
end

function Props.fire(parent: BasePart, size: number?, color: Color3?)
	local f = Instance.new("Fire")
	f.Size = size or 5
	f.Heat = 9
	if color then
		f.Color = color
		f.SecondaryColor = color:Lerp(Color3.new(1, 1, 0.6), 0.5)
	end
	f.Parent = parent
	return f
end

---------------------------------------------------------------- nature

function Props.tree(parent: Instance, pos: Vector3, scale: number?, style: string?)
	local s = scale or 1
	style = style or "oak"
	local model = Instance.new("Model")
	model.Name = "Tree"
	if style == "oak" then
		Props.column(model, pos - Vector3.new(0, 1, 0), 9 * s, 1.8 * s, Color3.fromRGB(105, 75, 50), Enum.Material.Wood)
		local green = Color3.fromRGB(70 + math.random(0, 25), 140 + math.random(0, 30), 60)
		Props.ellipsoid(model, Vector3.new(10, 8, 10) * s, CFrame.new(pos + Vector3.new(0, 10 * s, 0)), green, Enum.Material.Grass)
		Props.ellipsoid(model, Vector3.new(7, 6, 7) * s, CFrame.new(pos + Vector3.new(2.5 * s, 12.5 * s, 1 * s)), green:Lerp(Color3.new(1, 1, 0.6), 0.1), Enum.Material.Grass)
		Props.ellipsoid(model, Vector3.new(6, 5, 6) * s, CFrame.new(pos + Vector3.new(-2.5 * s, 11.5 * s, -1.5 * s)), green, Enum.Material.Grass)
	else
		local snowy = style == "snowpine"
		Props.column(model, pos - Vector3.new(0, 1, 0), 6 * s, 1.4 * s, Color3.fromRGB(90, 65, 45), Enum.Material.Wood)
		local green = Color3.fromRGB(40, 95 + math.random(0, 20), 60)
		for i, d in ipairs({ 10, 8, 6, 3.6 }) do
			local y = (3 + i * 2.6) * s
			Props.ellipsoid(model, Vector3.new(d, 3.4, d) * s, CFrame.new(pos + Vector3.new(0, y, 0)), green, Enum.Material.Grass)
			if snowy then
				Props.ellipsoid(model, Vector3.new(d * 0.8, 1.2, d * 0.8) * s, CFrame.new(pos + Vector3.new(0, y + 1.2 * s, 0)), Color3.fromRGB(240, 245, 255), Enum.Material.Snow)
			end
		end
	end
	model.Parent = parent
	return model
end

function Props.rock(parent: Instance, pos: Vector3, size: number, color: Color3?)
	local p = Props.part(parent, Vector3.new(size, size * 0.7, size * 0.9), CFrame.new(pos) * CFrame.Angles(math.random() * 0.6, math.random() * 6.28, math.random() * 0.6), color or Color3.fromRGB(125, 125, 130), Enum.Material.Slate)
	return p
end

function Props.bush(parent: Instance, pos: Vector3, size: number?)
	local s = size or 1
	Props.ellipsoid(parent, Vector3.new(5, 3.5, 5) * s, CFrame.new(pos + Vector3.new(0, 1.2 * s, 0)), Color3.fromRGB(70, 130, 55), Enum.Material.Grass)
end

function Props.flowers(parent: Instance, pos: Vector3, color: Color3)
	for _ = 1, 5 do
		local offset = Vector3.new(math.random(-20, 20) / 10, 0.4, math.random(-20, 20) / 10)
		Props.ellipsoid(parent, Vector3.new(0.7, 0.5, 0.7), CFrame.new(pos + offset), color)
	end
end

---------------------------------------------------------------- buildings

-- Gable roof on top of a box. `cf` is the box center at ground level, size = box size.
function Props.roof(parent: Instance, cf: CFrame, width: number, depth: number, wallTop: number, roofHeight: number, color: Color3, material: Enum.Material?)
	local overhang = 1.2
	local half = depth / 2 + overhang
	Props.part(parent, Vector3.new(width + overhang * 2, roofHeight, half), cf * CFrame.new(0, wallTop + roofHeight / 2, -half / 2), color, material or Enum.Material.WoodPlanks, "WedgePart")
	Props.part(parent, Vector3.new(width + overhang * 2, roofHeight, half), cf * CFrame.new(0, wallTop + roofHeight / 2, half / 2) * CFrame.Angles(0, math.pi, 0), color, material or Enum.Material.WoodPlanks, "WedgePart")
end

function Props.house(parent: Instance, cf: CFrame, width: number, depth: number, height: number, wallColor: Color3, roofColor: Color3)
	local model = Instance.new("Model")
	model.Name = "House"
	Props.part(model, Vector3.new(width, height, depth), cf * CFrame.new(0, height / 2, 0), wallColor, Enum.Material.Plaster)
	Props.part(model, Vector3.new(width + 0.4, 1, depth + 0.4), cf * CFrame.new(0, 0.5, 0), STONE, Enum.Material.Cobblestone)
	Props.roof(model, cf, width, depth, height, math.max(4, depth * 0.45), roofColor, Enum.Material.WoodPlanks)
	-- door + windows on the front (-Z)
	Props.part(model, Vector3.new(3.2, 5.5, 0.4), cf * CFrame.new(0, 2.75, -depth / 2 - 0.1), DARK_WOOD, Enum.Material.Wood)
	for _, x in ipairs({ -width / 3.2, width / 3.2 }) do
		local w = Props.part(model, Vector3.new(2.4, 2.4, 0.3), cf * CFrame.new(x, height * 0.6, -depth / 2 - 0.1), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
		w.CastShadow = false
	end
	-- corner beams
	for _, x in ipairs({ -width / 2, width / 2 }) do
		for _, z in ipairs({ -depth / 2, depth / 2 }) do
			Props.part(model, Vector3.new(0.8, height, 0.8), cf * CFrame.new(x, height / 2, z), DARK_WOOD, Enum.Material.Wood)
		end
	end
	model.Parent = parent
	return model
end

function Props.longhouse(parent: Instance, cf: CFrame, length: number, width: number?)
	local w = width or 18
	local h = 7
	local model = Instance.new("Model")
	model.Name = "Longhouse"
	Props.part(model, Vector3.new(length, h, w), cf * CFrame.new(0, h / 2, 0), Color3.fromRGB(95, 65, 40), Enum.Material.WoodPlanks)
	Props.roof(model, cf, length, w, h, w * 0.6, Color3.fromRGB(70, 50, 35), Enum.Material.WoodPlanks)
	Props.part(model, Vector3.new(4, 6, 0.5), cf * CFrame.new(0, 3, -w / 2 - 0.15), Color3.fromRGB(50, 35, 25), Enum.Material.Wood)
	-- crossed dragon-head beams on each gable
	for _, x in ipairs({ -length / 2 - 1, length / 2 + 1 }) do
		local top = cf * Vector3.new(x, h + w * 0.6 + 1.5, 0)
		Props.beam(model, cf * Vector3.new(x, h + w * 0.3, -3), top + (cf.LookVector * -1.5), 0.8, DARK_WOOD, Enum.Material.Wood)
		Props.beam(model, cf * Vector3.new(x, h + w * 0.3, 3), top + (cf.LookVector * 1.5), 0.8, DARK_WOOD, Enum.Material.Wood)
	end
	-- shields along the walls
	for i = -2, 2 do
		local shieldPos = cf * Vector3.new(i * length / 6, h * 0.55, -w / 2 - 0.4)
		local p = Props.part(model, Vector3.new(0.3, 3, 3), CFrame.lookAt(shieldPos, shieldPos + cf.LookVector) * CFrame.Angles(0, math.rad(90), 0), ({ Color3.fromRGB(170, 40, 40), Color3.fromRGB(40, 80, 160), Color3.fromRGB(220, 190, 60) })[(i % 3) + 1], Enum.Material.Wood)
		p.Shape = Enum.PartType.Cylinder
	end
	model.Parent = parent
	return model
end

function Props.tent(parent: Instance, cf: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Tent"
	Props.roof(model, cf, 8, 7, 0, 6, color, Enum.Material.Fabric)
	Props.column(model, cf.Position, 6.5, 0.4, DARK_WOOD, Enum.Material.Wood)
	model.Parent = parent
	return model
end

function Props.hut(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Hut"
	Props.part(model, Vector3.new(12, 6, 10), cf * CFrame.new(0, 3, 0), Color3.fromRGB(130, 100, 70), Enum.Material.WoodPlanks)
	Props.roof(model, cf, 12, 10, 6, 5, Color3.fromRGB(170, 150, 90), Enum.Material.Fabric)
	Props.part(model, Vector3.new(3, 4.5, 0.4), cf * CFrame.new(0, 2.25, -5.1), DARK_WOOD, Enum.Material.Wood)
	model.Parent = parent
	return model
end

function Props.campfire(parent: Instance, pos: Vector3)
	local model = Instance.new("Model")
	model.Name = "Campfire"
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		Props.rock(model, pos + Vector3.new(math.cos(a) * 2.6, 0.3, math.sin(a) * 2.6), 1.3, Color3.fromRGB(100, 100, 105))
	end
	for i = 1, 3 do
		local a = i / 3 * math.pi
		Props.beam(model, pos + Vector3.new(math.cos(a) * 1.8, 0.3, math.sin(a) * 1.8), pos + Vector3.new(-math.cos(a) * 1.8, 0.3, -math.sin(a) * 1.8), 0.6, DARK_WOOD, Enum.Material.Wood)
	end
	local core = Props.part(model, Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, 0.6, 0)), Color3.fromRGB(255, 140, 40), Enum.Material.Neon)
	core.Transparency = 0.3
	Props.fire(core, 6)
	Props.light(core, Color3.fromRGB(255, 160, 80), 22, 2)
	model.Parent = parent
	return model
end

function Props.torch(parent: Instance, pos: Vector3, color: Color3?)
	Props.column(parent, pos, 6, 0.5, DARK_WOOD, Enum.Material.Wood)
	local head = Props.part(parent, Vector3.new(0.9, 0.9, 0.9), CFrame.new(pos + Vector3.new(0, 6.4, 0)), color or Color3.fromRGB(255, 150, 50), Enum.Material.Neon)
	Props.fire(head, 2.5, color)
	Props.light(head, color or Color3.fromRGB(255, 170, 90), 16, 1.5)
end

function Props.lamp(parent: Instance, pos: Vector3)
	Props.column(parent, pos, 9, 0.6, Color3.fromRGB(50, 45, 55), Enum.Material.Metal)
	local glass = Props.part(parent, Vector3.new(1.6, 2, 1.6), CFrame.new(pos + Vector3.new(0, 9.8, 0)), Color3.fromRGB(255, 210, 130), Enum.Material.Neon)
	glass.CastShadow = false
	Props.part(parent, Vector3.new(2.2, 0.4, 2.2), CFrame.new(pos + Vector3.new(0, 11, 0)), Color3.fromRGB(50, 45, 55), Enum.Material.Metal)
	Props.light(glass, Color3.fromRGB(255, 210, 150), 24, 1.2)
end

function Props.fence(parent: Instance, a: Vector3, b: Vector3, color: Color3?)
	local c = color or WOOD
	local dist = (b - a).Magnitude
	local n = math.max(1, math.floor(dist / 6))
	for i = 0, n do
		Props.column(parent, a:Lerp(b, i / n), 4, 0.6, c, Enum.Material.Wood)
	end
	for _, y in ipairs({ 1.6, 3.2 }) do
		Props.beam(parent, a + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0), 0.35, c, Enum.Material.Wood)
	end
end

function Props.palisade(parent: Instance, a: Vector3, b: Vector3, height: number?)
	local h = height or 11
	local dist = (b - a).Magnitude
	local n = math.max(1, math.floor(dist / 1.9))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		local ph = h + (i % 3) * 0.8
		Props.column(parent, p, ph, 2, Color3.fromRGB(105, 75, 45), Enum.Material.Wood)
		Props.ellipsoid(parent, Vector3.new(1.4, 2.2, 1.4), CFrame.new(p + Vector3.new(0, ph + 0.6, 0)), Color3.fromRGB(95, 68, 42), Enum.Material.Wood)
	end
end

function Props.stoneWall(parent: Instance, a: Vector3, b: Vector3, height: number, thickness: number)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b) * CFrame.new(0, height / 2, 0)
	Props.part(parent, Vector3.new(thickness, height, len), cf, Color3.fromRGB(115, 115, 120), Enum.Material.Slate)
	-- crenellations
	local n = math.floor(len / 5)
	for i = 0, n - 1 do
		local p = CFrame.lookAt(mid, b) * CFrame.new(0, height + 1, -len / 2 + 2.5 + i * 5)
		Props.part(parent, Vector3.new(thickness + 0.4, 2, 2.5), p, Color3.fromRGB(105, 105, 110), Enum.Material.Slate)
	end
end

function Props.tower(parent: Instance, base: Vector3, height: number, diameter: number, roofColor: Color3?)
	Props.column(parent, base, height, diameter, Color3.fromRGB(120, 120, 125), Enum.Material.Slate)
	Props.column(parent, base + Vector3.new(0, height, 0), 2, diameter + 2, Color3.fromRGB(100, 100, 105), Enum.Material.Slate)
	local cf = CFrame.new(base + Vector3.new(0, height + 2, 0))
	Props.roof(parent, cf, diameter + 1, diameter + 1, 0, diameter * 0.8, roofColor or Color3.fromRGB(120, 40, 40), Enum.Material.WoodPlanks)
end

function Props.watchtower(parent: Instance, base: Vector3)
	local h = 18
	for _, o in ipairs({ Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) }) do
		Props.column(parent, base + o, h, 1, DARK_WOOD, Enum.Material.Wood)
	end
	Props.part(parent, Vector3.new(9, 1, 9), CFrame.new(base + Vector3.new(0, h, 0)), WOOD, Enum.Material.WoodPlanks)
	Props.roof(parent, CFrame.new(base + Vector3.new(0, h + 5, 0)), 9, 9, 0, 4, Color3.fromRGB(80, 55, 35), Enum.Material.WoodPlanks)
	Props.torch(parent, base + Vector3.new(4, h + 0.5, -4))
end

function Props.banner(parent: Instance, pos: Vector3, color: Color3, facing: Vector3?)
	Props.column(parent, pos, 14, 0.5, DARK_WOOD, Enum.Material.Wood)
	local dir = facing or Vector3.new(0, 0, -1)
	local cf = CFrame.lookAt(pos + Vector3.new(0, 10.5, 0), pos + Vector3.new(0, 10.5, 0) + dir) * CFrame.new(1.8, 0, 0)
	Props.part(parent, Vector3.new(3.4, 6, 0.15), cf, color, Enum.Material.Fabric)
end

function Props.crate(parent: Instance, pos: Vector3, size: number?)
	local s = size or 3
	Props.part(parent, Vector3.new(s, s, s), CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, math.random() * 6, 0), Color3.fromRGB(150, 110, 60), Enum.Material.WoodPlanks)
end

function Props.barrel(parent: Instance, pos: Vector3)
	Props.column(parent, pos, 3.6, 2.6, Color3.fromRGB(120, 80, 45), Enum.Material.Wood)
	Props.column(parent, pos + Vector3.new(0, 0.6, 0), 0.3, 2.75, Color3.fromRGB(70, 70, 75), Enum.Material.Metal)
	Props.column(parent, pos + Vector3.new(0, 2.7, 0), 0.3, 2.75, Color3.fromRGB(70, 70, 75), Enum.Material.Metal)
end

function Props.longship(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Longship"
	Props.ellipsoid(model, Vector3.new(7, 5, 34), cf, Color3.fromRGB(110, 75, 45), Enum.Material.WoodPlanks)
	Props.part(model, Vector3.new(6, 0.4, 28), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(140, 100, 60), Enum.Material.WoodPlanks)
	Props.beam(model, cf * Vector3.new(0, 1, -16), cf * Vector3.new(0, 6, -19), 1.2, DARK_WOOD, Enum.Material.Wood)
	Props.ellipsoid(model, Vector3.new(1.6, 1.6, 2.6), cf * CFrame.new(0, 6.5, -19.5), Color3.fromRGB(200, 60, 40), Enum.Material.Wood)
	Props.column(model, cf.Position + Vector3.new(0, 1, 0), 16, 0.7, DARK_WOOD, Enum.Material.Wood)
	for i = 0, 3 do
		local color = i % 2 == 0 and Color3.fromRGB(190, 40, 40) or Color3.fromRGB(240, 235, 220)
		Props.part(model, Vector3.new(11, 2, 0.2), cf * CFrame.new(0, 14 - i * 2, 0.3), color, Enum.Material.Fabric)
	end
	for i = -2, 2 do
		for _, side in ipairs({ -1, 1 }) do
			local p = cf * Vector3.new(3.3 * side, 1.4, i * 5)
			local shield = Props.part(model, Vector3.new(0.3, 2.2, 2.2), CFrame.new(p), ({ Color3.fromRGB(200, 170, 50), Color3.fromRGB(50, 90, 170) })[(i + 3) % 2 + 1], Enum.Material.Wood)
			shield.Shape = Enum.PartType.Cylinder
		end
	end
	model.Parent = parent
	return model
end

---------------------------------------------------------------- dragon-sized buildings

-- A dragon's house: stone foundation, timber-framed walls, a tall arched doorway a dragon can
-- walk through, round windows, a steep roof with a perch beam on top and a chimney.
-- `cf` = center at ground level, front faces -Z.
function Props.dragonHouse(parent: Instance, cf: CFrame, width: number, depth: number, height: number, wallColor: Color3, roofColor: Color3)
	local model = Instance.new("Model")
	model.Name = "DragonHouse"
	local stone = Color3.fromRGB(135, 130, 128)
	Props.part(model, Vector3.new(width + 1.4, 2.4, depth + 1.4), cf * CFrame.new(0, 1.2, 0), stone, Enum.Material.Cobblestone)
	Props.part(model, Vector3.new(width, height - 2.4, depth), cf * CFrame.new(0, 2.4 + (height - 2.4) / 2, 0), wallColor, Enum.Material.Plaster)
	-- timber frame (the front skips the middle post and splits the rail around the door)
	local wallH = height - 2.4
	local doorGap = math.min(11, width * 0.4) / 2 + 1.4
	for _, x in ipairs({ -width / 2, 0, width / 2 }) do
		for _, z in ipairs({ -depth / 2, depth / 2 }) do
			if not (x == 0 and z < 0) then
				Props.part(model, Vector3.new(1.2, wallH, 1.2), cf * CFrame.new(x, 2.4 + wallH / 2, z), DARK_WOOD, Enum.Material.Wood)
			end
		end
	end
	local railY = 2.4 + wallH * 0.36
	for _, z in ipairs({ -depth / 2, depth / 2 }) do
		Props.part(model, Vector3.new(width + 1.2, 1.2, 1.2), cf * CFrame.new(0, height, z), DARK_WOOD, Enum.Material.Wood)
		if z > 0 then
			Props.part(model, Vector3.new(width + 1.2, 1, 1), cf * CFrame.new(0, railY, z), DARK_WOOD, Enum.Material.Wood)
		else
			local len = width / 2 - doorGap + 0.6
			for _, side in ipairs({ -1, 1 }) do
				Props.part(model, Vector3.new(len, 1, 1), cf * CFrame.new(side * (doorGap + len / 2 - 0.3), railY, z), DARK_WOOD, Enum.Material.Wood)
			end
		end
	end
	for _, x in ipairs({ -width / 2, width / 2 }) do
		Props.part(model, Vector3.new(1.2, 1.2, depth + 1.2), cf * CFrame.new(x, height, 0), DARK_WOOD, Enum.Material.Wood)
	end
	local roofH = math.max(8, depth * 0.55)
	Props.roof(model, cf, width, depth, height, roofH, roofColor, Enum.Material.WoodPlanks)
	-- perch beam along the ridge, with carved dragon-head ends
	Props.part(model, Vector3.new(width + 5, 1.2, 1.2), cf * CFrame.new(0, height + roofH + 0.6, 0), DARK_WOOD, Enum.Material.Wood)
	for _, x in ipairs({ -width / 2 - 2.5, width / 2 + 2.5 }) do
		Props.ellipsoid(model, Vector3.new(2.2, 1.8, 1.6), cf * CFrame.new(x, height + roofH + 1.2, 0), roofColor:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Wood)
	end
	-- chimney
	Props.part(model, Vector3.new(3, roofH + 3, 3), cf * CFrame.new(width * 0.28, height + roofH / 2 + 1, depth * 0.18), stone, Enum.Material.Brick)
	-- dragon-sized arched doorway (about 11 wide, 13 tall): a plank door with a round top,
	-- framed by a stone arch
	local doorW, doorH = math.min(11, width * 0.4), math.min(13, height * 0.8)
	local rectH = doorH - doorW / 2
	local doorColor = Color3.fromRGB(70, 45, 30)
	local front = -depth / 2
	local frame = Props.part(model, Vector3.new(0.4, doorW + 1.8, doorW + 1.8), cf * CFrame.new(0, rectH + 0.2, front - 0.15) * CFrame.Angles(0, math.rad(90), 0), stone, Enum.Material.Cobblestone)
	frame.Shape = Enum.PartType.Cylinder
	for _, x in ipairs({ -1, 1 }) do
		Props.part(model, Vector3.new(0.9, rectH, 0.4), cf * CFrame.new(x * (doorW / 2 + 0.45), rectH / 2 + 0.2, front - 0.15), stone, Enum.Material.Cobblestone)
	end
	Props.part(model, Vector3.new(doorW, rectH, 0.4), cf * CFrame.new(0, rectH / 2 + 0.2, front - 0.35), doorColor, Enum.Material.WoodPlanks)
	local top = Props.part(model, Vector3.new(0.4, doorW, doorW), cf * CFrame.new(0, rectH + 0.2, front - 0.35) * CFrame.Angles(0, math.rad(90), 0), doorColor, Enum.Material.WoodPlanks)
	top.Shape = Enum.PartType.Cylinder
	Props.part(model, Vector3.new(0.5, 3, 0.3), cf * CFrame.new(0, rectH * 0.55, front - 0.6), Color3.fromRGB(200, 170, 80), Enum.Material.Metal)
	Props.part(model, Vector3.new(doorW + 2.4, 1.2, 3), cf * CFrame.new(0, 0.6, front - 1.6), stone, Enum.Material.Cobblestone)
	-- round glowing windows
	for _, x in ipairs({ -width / 3, width / 3 }) do
		local w = Props.part(model, Vector3.new(0.4, 4, 4), cf * CFrame.new(x, height * 0.62, -depth / 2 - 0.15) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 215, 140), Enum.Material.Neon)
		w.Shape = Enum.PartType.Cylinder
		w.CastShadow = false
		local rim = Props.part(model, Vector3.new(0.3, 4.8, 4.8), cf * CFrame.new(x, height * 0.62, -depth / 2 - 0.05) * CFrame.Angles(0, math.rad(90), 0), DARK_WOOD, Enum.Material.Wood)
		rim.Shape = Enum.PartType.Cylinder
	end
	model.Parent = parent
	return model
end

---------------------------------------------------------------- camp props

-- Treasure chest (tag "CampChest"). CampService opens the lid and handles the prompt.
function Props.chest(parent: Instance, cf: CFrame, campId: string)
	local model = Instance.new("Model")
	model.Name = "Chest"
	local wood = Color3.fromRGB(125, 80, 45)
	local gold = Color3.fromRGB(240, 190, 60)
	-- platform
	Props.part(model, Vector3.new(12, 1, 10), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(110, 80, 50), Enum.Material.WoodPlanks)
	local base = Props.part(model, Vector3.new(6, 3, 4), cf * CFrame.new(0, 2.5, 0), wood, Enum.Material.WoodPlanks)
	base.Name = "Base"
	model.PrimaryPart = base
	for _, x in ipairs({ -2.2, 2.2 }) do
		Props.part(model, Vector3.new(0.4, 3.1, 4.1), cf * CFrame.new(x, 2.5, 0), gold, Enum.Material.Metal)
	end
	local glow = Props.part(model, Vector3.new(5.2, 0.5, 3.2), cf * CFrame.new(0, 4.05, 0), Color3.fromRGB(255, 220, 90), Enum.Material.Neon)
	glow.Name = "Glow"
	glow.CastShadow = false
	Props.light(glow, Color3.fromRGB(255, 210, 100), 18, 2)
	local lid = Props.part(model, Vector3.new(6, 1.4, 4), cf * CFrame.new(0, 4.7, 0), wood, Enum.Material.WoodPlanks)
	lid.Name = "Lid"
	Props.part(model, Vector3.new(0.9, 1.1, 0.3), cf * CFrame.new(0, 3.9, -2.1), gold, Enum.Material.Metal)
	for _, x in ipairs({ -4.8, 4.8 }) do
		Props.torch(model, (cf * CFrame.new(x, 1, -3.8)).Position)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Chest"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	model:SetAttribute("CampId", campId)
	model.Parent = parent
	return model
end

function Props.weaponRack(parent: Instance, cf: CFrame)
	Props.part(parent, Vector3.new(6, 0.5, 0.5), cf * CFrame.new(0, 3.2, 0), DARK_WOOD, Enum.Material.Wood)
	for _, x in ipairs({ -2.8, 2.8 }) do
		Props.part(parent, Vector3.new(0.5, 4, 0.5), cf * CFrame.new(x, 2, 0), DARK_WOOD, Enum.Material.Wood)
	end
	for i = -2, 2 do
		local c = cf * CFrame.new(i * 1.1, 2.2, 0.3) * CFrame.Angles(math.rad(-12), 0, 0)
		Props.part(parent, Vector3.new(0.25, 3.6, 0.25), c, WOOD, Enum.Material.Wood)
		Props.part(parent, Vector3.new(0.15, 0.9, 0.8), c * CFrame.new(0, 1.5, -0.35), Color3.fromRGB(160, 165, 175), Enum.Material.Metal)
	end
end

function Props.firewood(parent: Instance, cf: CFrame)
	for row = 0, 2 do
		for i = 0, 3 - row do
			local c = cf * CFrame.new(-1.8 + i * 1.2 + row * 0.6, 0.55 + row * 1.0, 0) * CFrame.Angles(0, math.rad(90), 0)
			local log = Props.part(parent, Vector3.new(4, 1.1, 1.1), c * CFrame.Angles(0, 0, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
			log.Shape = Enum.PartType.Cylinder
		end
	end
end

-- Big tent with a banner pole: the chieftain's or champion's tent.
function Props.bigTent(parent: Instance, cf: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "BigTent"
	Props.roof(model, cf, 16, 14, 0, 11, color, Enum.Material.Fabric)
	Props.column(model, cf.Position, 12, 0.7, DARK_WOOD, Enum.Material.Wood)
	Props.column(model, (cf * CFrame.new(0, 11.5, 0)).Position, 6, 0.4, DARK_WOOD, Enum.Material.Wood)
	Props.part(model, Vector3.new(0.15, 2.4, 3.6), cf * CFrame.new(0, 16, 1.8), color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Fabric)
	-- skull totems at the entrance
	for _, x in ipairs({ -5, 5 }) do
		local base = (cf * CFrame.new(x, 0, -8)).Position
		Props.column(model, base, 5, 0.5, DARK_WOOD, Enum.Material.Wood)
		Props.ellipsoid(model, Vector3.new(1.3, 1.4, 1.4), CFrame.new(base + Vector3.new(0, 5.6, 0)), Color3.fromRGB(235, 225, 200))
	end
	model.Parent = parent
	return model
end

-- Tall wooden tower with a great horn on top (where Hornblowers raise the alarm).
function Props.hornTower(parent: Instance, base: Vector3)
	Props.watchtower(parent, base)
	local ivory = Color3.fromRGB(240, 230, 200)
	local top = base + Vector3.new(0, 19.5, 0)
	Props.beam(parent, top + Vector3.new(-2.5, 1, 0), top + Vector3.new(0, 0.6, 0), 0.6, ivory)
	Props.beam(parent, top + Vector3.new(0, 0.6, 0), top + Vector3.new(2.2, 1.4, 0), 1.1, ivory)
	Props.beam(parent, top + Vector3.new(2.2, 1.4, 0), top + Vector3.new(3.6, 3.0, 0), 1.8, ivory)
end

---------------------------------------------------------------- training grounds

-- Straw practice dummy on a post (tag "TrainingDummy"; TrainingService adds the Humanoid).
function Props.dummy(parent: Instance, pos: Vector3, facing: Vector3)
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	local cf = CFrame.lookAt(pos, pos + Vector3.new(facing.X, 0, facing.Z))
	local straw = Color3.fromRGB(215, 185, 110)
	local burlap = Color3.fromRGB(190, 160, 115)
	local root = Props.part(model, Vector3.new(3, 8, 2.4), cf * CFrame.new(0, 4.5, 0), Color3.new(), nil)
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = false
	model.PrimaryPart = root
	Props.column(model, cf.Position - Vector3.new(0, 0.5, 0), 5, 0.7, DARK_WOOD, Enum.Material.Wood)
	Props.part(model, Vector3.new(4, 0.6, 4), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(120, 110, 100), Enum.Material.Slate)
	Props.ellipsoid(model, Vector3.new(3.4, 4.6, 2.6), cf * CFrame.new(0, 6.4, 0), straw, Enum.Material.Fabric)
	local head = Props.ellipsoid(model, Vector3.new(2.2, 2.3, 2.2), cf * CFrame.new(0, 9.6, 0), burlap, Enum.Material.Fabric)
	head.Name = "Head"
	Props.part(model, Vector3.new(7, 0.6, 0.6), cf * CFrame.new(0, 7.3, 0), DARK_WOOD, Enum.Material.Wood)
	for _, x in ipairs({ -3.4, 3.4 }) do
		Props.ellipsoid(model, Vector3.new(1.3, 1.3, 1.3), cf * CFrame.new(x, 7.3, 0), straw, Enum.Material.Fabric)
	end
	-- target rings on the chest
	for i, c in ipairs({ Color3.fromRGB(230, 60, 50), Color3.fromRGB(245, 240, 230), Color3.fromRGB(230, 60, 50) }) do
		local r = 2.6 - (i - 1) * 0.8
		local ring = Props.part(model, Vector3.new(0.2, r, r), cf * CFrame.new(0, 6.6, -1.25 - i * 0.03) * CFrame.Angles(0, math.rad(90), 0), c, Enum.Material.SmoothPlastic)
		ring.Shape = Enum.PartType.Cylinder
	end
	for _, x in ipairs({ -0.4, 0.4 }) do
		Props.part(model, Vector3.new(0.3, 0.3, 0.1), cf * CFrame.new(x, 9.9, -1.08), Color3.fromRGB(40, 30, 20))
	end
	model:SetAttribute("Kind", "Dummy")
	model:SetAttribute("Height", 7)
	model.Parent = parent
	return model
end

-- Stone sparring golem that throws practice axes (tag "TrainingDummy", Kind = "Golem").
function Props.golem(parent: Instance, pos: Vector3, facing: Vector3)
	local model = Instance.new("Model")
	model.Name = "SparringGolem"
	local cf = CFrame.lookAt(pos, pos + Vector3.new(facing.X, 0, facing.Z))
	local rock = Color3.fromRGB(125, 120, 115)
	local moss = Color3.fromRGB(90, 130, 70)
	local root = Props.part(model, Vector3.new(6, 12, 5), cf * CFrame.new(0, 6.5, 0), Color3.new(), nil)
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = false
	model.PrimaryPart = root
	Props.part(model, Vector3.new(8, 1, 8), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(100, 95, 90), Enum.Material.Slate)
	for _, x in ipairs({ -1.6, 1.6 }) do
		Props.part(model, Vector3.new(2.2, 4, 2.4), cf * CFrame.new(x, 3, 0) * CFrame.Angles(0, 0, x * 0.03), rock, Enum.Material.Slate)
	end
	Props.part(model, Vector3.new(6.4, 5, 4.2), cf * CFrame.new(0, 7.3, 0) * CFrame.Angles(0.05, 0, 0), rock, Enum.Material.Slate)
	Props.part(model, Vector3.new(6.6, 1.2, 4.4), cf * CFrame.new(0, 9.5, 0), moss, Enum.Material.Grass)
	local head = Props.part(model, Vector3.new(3, 2.6, 2.8), cf * CFrame.new(0, 11.3, -0.3), rock, Enum.Material.Slate)
	head.Name = "Head"
	for _, x in ipairs({ -0.7, 0.7 }) do
		local eye = Props.part(model, Vector3.new(0.6, 0.4, 0.2), cf * CFrame.new(x, 11.5, -1.72), Color3.fromRGB(120, 230, 255), Enum.Material.Neon)
		eye.CastShadow = false
	end
	for _, x in ipairs({ -4.2, 4.2 }) do
		Props.part(model, Vector3.new(2, 5.5, 2), cf * CFrame.new(x, 7, -0.4) * CFrame.Angles(0.2, 0, x * 0.04), rock, Enum.Material.Slate)
		Props.part(model, Vector3.new(0.4, 3, 0.4), cf * CFrame.new(x, 4.2, -1.6), WOOD, Enum.Material.Wood)
		Props.part(model, Vector3.new(0.2, 1.2, 1.4), cf * CFrame.new(x, 5.3, -2.1), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
	end
	model:SetAttribute("Kind", "Golem")
	model:SetAttribute("Height", 10)
	model:SetAttribute("Scale", 2)
	model.Parent = parent
	return model
end

---------------------------------------------------------------- wilds

-- Fishing spot: a bobbing float with ripple rings on the water (tag "FishingSpot").
function Props.fishingSpot(parent: Instance, pos: Vector3, spotId: string, iced: boolean?)
	local model = Instance.new("Model")
	model.Name = "FishingSpot"
	local float = Props.part(model, Vector3.new(1.4, 1.4, 1.4), CFrame.new(pos + Vector3.new(0, 0.4, 0)), Color3.fromRGB(240, 70, 60), Enum.Material.SmoothPlastic)
	float.Shape = Enum.PartType.Ball
	float.Name = "Float"
	float.CanCollide = false
	model.PrimaryPart = float
	Props.part(model, Vector3.new(0.9, 0.5, 0.9), CFrame.new(pos + Vector3.new(0, 1.2, 0)), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic).CanCollide = false
	for i, r in ipairs({ 5, 9 }) do
		local ring = Props.part(model, Vector3.new(0.1, r, r), CFrame.new(pos + Vector3.new(0, 0.05 + i * 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(210, 240, 255), Enum.Material.Neon)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.6 + i * 0.1
		ring.CanCollide = false
		ring.CastShadow = false
	end
	if iced then
		-- a little ice-fishing stool and bucket on the ice
		Props.column(model, pos + Vector3.new(4, 0, 3), 1.6, 1.6, WOOD, Enum.Material.Wood)
		Props.column(model, pos + Vector3.new(-3.5, 0, 3.5), 1.4, 1.4, Color3.fromRGB(130, 130, 140), Enum.Material.Metal)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "🎣 Fish"
	prompt.ObjectText = "Fishing Spot"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 30
	prompt.RequiresLineOfSight = false
	prompt.Parent = float
	model:SetAttribute("SpotId", spotId)
	model.Parent = parent
	return model
end

function Props.reeds(parent: Instance, pos: Vector3, count: number?)
	for _ = 1, count or 6 do
		local off = Vector3.new(math.random(-20, 20) / 10, 0, math.random(-20, 20) / 10)
		local h = 3 + math.random() * 2.5
		local p = Props.part(parent, Vector3.new(0.25, h, 0.25), CFrame.new(pos + off + Vector3.new(0, h / 2 - 0.5, 0)) * CFrame.Angles(math.random() * 0.2 - 0.1, 0, math.random() * 0.2 - 0.1), Color3.fromRGB(110, 150, 70), Enum.Material.Grass)
		p.CanCollide = false
		local top = Props.ellipsoid(parent, Vector3.new(0.45, 1.1, 0.45), p.CFrame * CFrame.new(0, h / 2 - 0.3, 0), Color3.fromRGB(120, 80, 45), Enum.Material.Fabric)
		top.CanCollide = false
	end
end

function Props.lilyPad(parent: Instance, pos: Vector3)
	local pad = Props.part(parent, Vector3.new(0.12, 3, 3), CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, math.random() * 6, math.rad(90)), Color3.fromRGB(80, 150, 70), Enum.Material.Grass)
	pad.Shape = Enum.PartType.Cylinder
	pad.CanCollide = false
	if math.random() < 0.4 then
		Props.ellipsoid(parent, Vector3.new(0.9, 0.6, 0.9), CFrame.new(pos + Vector3.new(0.4, 0.35, 0.2)), Color3.fromRGB(255, 190, 220)).CanCollide = false
	end
end

function Props.mushroom(parent: Instance, pos: Vector3, scale: number?)
	local s = scale or 1
	Props.column(parent, pos, 1.4 * s, 0.6 * s, Color3.fromRGB(235, 225, 205))
	Props.ellipsoid(parent, Vector3.new(2 * s, 1 * s, 2 * s), CFrame.new(pos + Vector3.new(0, 1.5 * s, 0)), Color3.fromRGB(200, 50, 45))
end

function Props.log(parent: Instance, pos: Vector3, length: number, yaw: number)
	local p = Props.part(parent, Vector3.new(length, 2.2, 2.2), CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(105, 75, 50), Enum.Material.Wood)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Props.birch(parent: Instance, pos: Vector3, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Tree"
	Props.column(model, pos - Vector3.new(0, 1, 0), 12 * s, 1.1 * s, Color3.fromRGB(235, 232, 225), Enum.Material.SmoothPlastic)
	for i = 1, 3 do
		Props.part(model, Vector3.new(1.15 * s, 0.25, 0.3), CFrame.new(pos + Vector3.new(0, (2 + i * 2.7) * s, -0.45 * s)), Color3.fromRGB(40, 40, 40))
	end
	local green = Color3.fromRGB(150, 190, 80)
	Props.ellipsoid(model, Vector3.new(7, 9, 7) * s, CFrame.new(pos + Vector3.new(0, 13 * s, 0)), green, Enum.Material.Grass)
	Props.ellipsoid(model, Vector3.new(5, 6, 5) * s, CFrame.new(pos + Vector3.new(1.5 * s, 10 * s, 1 * s)), green:Lerp(Color3.new(1, 1, 0.6), 0.15), Enum.Material.Grass)
	model.Parent = parent
	return model
end

-- Height of the terrain surface at (x, z). Signs and small props use this so they sit on
-- hills and river banks instead of sinking into them.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = false
function Props.groundY(x: number, z: number): number
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local ray = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), groundParams)
	return ray and ray.Position.Y or 0
end

-- A signboard with text on its front (-Z) face. `cf` = center of the board. The board is lifted
-- if needed so its bottom edge clears the ground under it by at least `clearance` studs, and the
-- posts reach down into the ground wherever it is.
function Props.sign(parent: Instance, cf: CFrame, text: string, size: Vector2?, textColor: Color3?, boardColor: Color3?, clearance: number?)
	local sz = size or Vector2.new(12, 4)
	local postXs = { -sz.X / 2 + 0.6, sz.X / 2 - 0.6 }
	local grounds = {}
	local highest = -math.huge
	for i, x in ipairs(postXs) do
		local p = cf * Vector3.new(x, 0, 0.3)
		grounds[i] = Props.groundY(p.X, p.Z)
		highest = math.max(highest, grounds[i])
	end
	local mid = cf.Position
	highest = math.max(highest, Props.groundY(mid.X, mid.Z))
	local minBottom = highest + (clearance or 3.5)
	local bottom = mid.Y - sz.Y / 2
	if bottom < minBottom then
		cf += Vector3.new(0, minBottom - bottom, 0)
	end
	local board = Props.part(parent, Vector3.new(sz.X, sz.Y, 0.5), cf, boardColor or Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
	board.Name = "Sign"
	-- posts from just under the ground up to the middle of the board
	for i, x in ipairs(postXs) do
		local p = cf * Vector3.new(x, 0, 0.3)
		local base = grounds[i] - 1
		Props.column(parent, Vector3.new(p.X, base, p.Z), math.max(0.5, cf.Position.Y - base), 0.5, DARK_WOOD, Enum.Material.Wood)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = textColor or Color3.fromRGB(255, 235, 190)
	label.TextStrokeTransparency = 0.5
	label.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = board
	return board
end

return Props
