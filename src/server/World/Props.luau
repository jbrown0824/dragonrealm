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

-- A signboard with text on its front (-Z) face. `cf` = center of the board.
function Props.sign(parent: Instance, cf: CFrame, text: string, size: Vector2?, textColor: Color3?, boardColor: Color3?)
	local sz = size or Vector2.new(12, 4)
	local board = Props.part(parent, Vector3.new(sz.X, sz.Y, 0.5), cf, boardColor or Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
	board.Name = "Sign"
	-- posts from the ground (y = 0) up to the middle of the board
	for _, x in ipairs({ -sz.X / 2 + 0.6, sz.X / 2 - 0.6 }) do
		local p = cf * Vector3.new(x, 0, 0.3)
		Props.column(parent, Vector3.new(p.X, 0, p.Z), math.max(0.5, cf.Position.Y), 0.5, DARK_WOOD, Enum.Material.Wood)
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
