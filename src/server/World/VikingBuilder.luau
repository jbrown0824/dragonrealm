-- Builds blocky viking NPCs (and viking bosses) out of parts.
-- Arms and legs hang off Motor6Ds (ArmL/ArmR/LegL/LegR) so clients can animate them.

local VikingBuilder = {}

local SKIN = Color3.fromRGB(236, 188, 150)
local METAL = Color3.fromRGB(150, 155, 165)
local DARK_METAL = Color3.fromRGB(90, 95, 105)
local IVORY = Color3.fromRGB(240, 230, 205)
local LEATHER = Color3.fromRGB(95, 60, 35)
local WOOD = Color3.fromRGB(120, 80, 45)
local GOLD = Color3.fromRGB(255, 200, 60)

-- look: { shirt, pants, beard, hair?, weapon, shield, bigShield?, cape?, crown?, warpaint?, quiver?, glow?,
--         skin? (face and hands: pale for the draugr), eyes? (glowing eyes instead of dark ones) }
-- Returns model, hipHeight
function VikingBuilder.build(look, scale: number, name: string)
	local s = scale
	local skin = look.skin or SKIN
	local model = Instance.new("Model")
	model.Name = name

	local function V(x, y, z)
		return Vector3.new(x * s, y * s, z * s)
	end

	local function part(className: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
		local p = Instance.new(className)
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local function mesh(p: BasePart, meshType: Enum.MeshType)
		local m = Instance.new("SpecialMesh")
		m.MeshType = meshType
		m.Parent = p
		return p
	end

	local function ellipsoid(size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?)
		return mesh(part("Part", size, CFrame.new(pos), color, material), Enum.MeshType.Sphere)
	end

	local function limb(a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material?)
		local length = (b - a).Magnitude
		local up = Vector3.yAxis
		if math.abs((b - a).Unit:Dot(up)) > 0.98 then
			up = Vector3.zAxis
		end
		local p = part("Part", Vector3.new(thickness, thickness, length + thickness * 0.3), CFrame.lookAt((a + b) / 2, b, up), color, material)
		return mesh(p, Enum.MeshType.Sphere)
	end

	local function cylinder(a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?)
		local length = (b - a).Magnitude
		local up = Vector3.yAxis
		if math.abs((b - a).Unit:Dot(up)) > 0.98 then
			up = Vector3.zAxis
		end
		local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
		local p = part("Part", Vector3.new(length, diameter, diameter), cf, color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	local function weldAll(anchor: BasePart, parts)
		for _, p in ipairs(parts) do
			local w = Instance.new("WeldConstraint")
			w.Part0 = anchor
			w.Part1 = p
			w.Parent = p
		end
	end

	local function collect(fn)
		local before = {}
		for _, c in ipairs(model:GetChildren()) do
			before[c] = true
		end
		fn()
		local new = {}
		for _, c in ipairs(model:GetChildren()) do
			if not before[c] and c:IsA("BasePart") then
				table.insert(new, c)
			end
		end
		return new
	end

	local function motor(name: string, p0: BasePart, p1: BasePart, joint: CFrame)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = p0.CFrame:Inverse() * joint
		m.C1 = p1.CFrame:Inverse() * joint
		m.Parent = p0
	end

	---------------------------------------------------------------- root + torso
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V(2, 2, 1.2)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	local torso = part("Part", V(2, 2, 1), CFrame.new(), look.shirt)
	torso.Name = "Torso"
	weldAll(root, { torso })

	weldAll(torso, collect(function()
		part("Part", V(2.05, 0.32, 1.05), CFrame.new(V(0, -0.78, 0)), LEATHER)
		part("Part", V(0.4, 0.34, 0.1), CFrame.new(V(0, -0.78, -0.55)), GOLD, Enum.Material.Metal)
		-- fur collar
		ellipsoid(V(2.3, 0.6, 1.3), V(0, 0.95, 0), Color3.fromRGB(110, 90, 70))

		local head = mesh(part("Part", V(1.25, 1.25, 1.25), CFrame.new(V(0, 1.65, 0)), skin), Enum.MeshType.Head)
		head.Name = "Head"
		for _, x in ipairs({ -0.22, 0.22 }) do
			if look.eyes then
				part("Part", V(0.18, 0.14, 0.06), CFrame.new(V(x, 1.78, -0.61)), look.eyes, Enum.Material.Neon)
			else
				part("Part", V(0.14, 0.18, 0.05), CFrame.new(V(x, 1.78, -0.6)), Color3.fromRGB(25, 25, 25))
			end
		end
		part("Part", V(0.2, 0.25, 0.2), CFrame.new(V(0, 1.6, -0.66)), look.skin and skin:Lerp(Color3.new(0, 0, 0), 0.15) or Color3.fromRGB(220, 160, 130))

		if look.beard then
			ellipsoid(V(1.15, 1.05, 0.55), V(0, 1.2, -0.52), look.beard)
			ellipsoid(V(0.9, 0.22, 0.3), V(0, 1.5, -0.66), look.beard)
		end
		if look.hair then
			ellipsoid(V(1.4, 2.2, 0.7), V(0, 1.2, 0.5), look.hair)
			ellipsoid(V(1.45, 0.7, 1.4), V(0, 2.2, 0.05), look.hair)
		end
		if look.warpaint then
			part("Part", V(1.0, 0.12, 0.05), CFrame.new(V(0, 1.82, -0.63)), Color3.fromRGB(40, 90, 200))
		end

		-- Helmet with horns
		if not look.hair then
			ellipsoid(V(1.38, 1.0, 1.38), V(0, 2.08, 0), METAL, Enum.Material.Metal)
			ellipsoid(V(1.45, 0.26, 1.45), V(0, 1.95, 0), DARK_METAL, Enum.Material.Metal)
			part("Part", V(0.18, 0.6, 0.12), CFrame.new(V(0, 1.75, -0.66)), DARK_METAL, Enum.Material.Metal)
			for _, side in ipairs({ -1, 1 }) do
				limb(V(0.62 * side, 2.1, 0), V(1.05 * side, 2.55, -0.05), 0.34 * s, IVORY)
				limb(V(1.05 * side, 2.55, -0.05), V(1.15 * side, 3.05, -0.25), 0.22 * s, IVORY)
			end
		end
		if look.crown then
			for i = 0, 4 do
				local a = math.rad(i * 72)
				limb(V(math.sin(a) * 0.62, 2.35, math.cos(a) * 0.62), V(math.sin(a) * 0.7, 2.85, math.cos(a) * 0.7), 0.2 * s, GOLD, Enum.Material.Metal)
			end
		end
		if look.cape then
			part("Part", V(2.2, 3.1, 0.14), CFrame.new(V(0, -0.45, 0.62)) * CFrame.Angles(math.rad(-6), 0, 0), look.cape, Enum.Material.Fabric)
		end
		if look.quiver then
			cylinder(V(0.4, -0.6, 0.7), V(-0.3, 0.9, 0.7), 0.6 * s, LEATHER)
			for i = 0, 2 do
				cylinder(V(-0.2 + i * 0.15, 0.6, 0.7), V(-0.5 + i * 0.15, 1.5, 0.7), 0.12 * s, WOOD)
			end
		end
		if look.glow then
			local light = Instance.new("PointLight")
			light.Color = look.glow
			light.Range = 18
			light.Brightness = 2
			light.Parent = torso
		end
	end))

	---------------------------------------------------------------- arms
	local arms = {}
	for _, side in ipairs({ -1, 1 }) do
		local arm = part("Part", V(0.8, 1.9, 0.85), CFrame.new(V(1.42 * side, 0, 0)), look.shirt)
		arm.Name = side > 0 and "RightArm" or "LeftArm"
		arms[side] = arm
		weldAll(arm, collect(function()
			ellipsoid(V(0.75, 0.75, 0.75), V(1.42 * side, -1.05, 0), skin)
			part("Part", V(0.85, 0.35, 0.9), CFrame.new(V(1.42 * side, -0.6, 0)), LEATHER)
		end))
		motor(side > 0 and "ArmR" or "ArmL", torso, arm, CFrame.new(V(1.42 * side, 0.8, 0)))
	end

	-- Weapons in the right hand (and left for twin axes)
	local function axe(side: number, big: boolean)
		local hand = V(1.42 * side, -1.1, 0)
		local len = big and 4.4 or 2.6
		local top = hand + V(0, len * 0.55, -0.9)
		local bottom = hand + V(0, -len * 0.35, 0.5)
		cylinder(bottom, top, 0.26 * s, WOOD)
		local bladeCF = CFrame.lookAt(top, top + (top - bottom).Unit)
		local bladeSize = big and V(0.18, 1.8, 1.6) or V(0.14, 1.05, 0.9)
		part("Part", bladeSize, bladeCF * CFrame.new(0, -0.5 * s, 0.35 * s), METAL, Enum.Material.Metal)
		if big then
			part("Part", bladeSize, bladeCF * CFrame.new(0, 0.5 * s, 0.35 * s), METAL, Enum.Material.Metal)
		end
	end

	for _, side in ipairs({ -1, 1 }) do
		weldAll(arms[side], collect(function()
			local weapon = look.weapon
			if side > 0 then
				if weapon == "axe" or weapon == "twinAxe" then
					axe(1, false)
				elseif weapon == "greatAxe" then
					axe(1, true)
				elseif weapon == "hammer" then
					local hand = V(1.42, -1.1, 0)
					local top = hand + V(0, 1.6, -0.7)
					cylinder(hand + V(0, -0.8, 0.3), top, 0.28 * s, WOOD)
					part("Part", V(1.1, 0.75, 0.75), CFrame.lookAt(top, top + Vector3.new(0, 1, -0.4)), DARK_METAL, Enum.Material.Metal)
				elseif weapon == "horn" then
					-- a great curved war horn, raised to the lips when sounding the alarm
					local hand = V(1.42, -1.1, 0)
					local a, b, c = hand + V(-0.2, 0.2, -0.4), hand + V(0.1, 0.9, -1.1), hand + V(0.5, 1.8, -1.4)
					limb(a, b, 0.32 * s, IVORY)
					limb(b, c, 0.5 * s, IVORY)
					ellipsoid(V(0.9, 0.9, 0.3), c + V(0.1, 0.3, -0.1), GOLD, Enum.Material.Metal)
				elseif weapon == "torch" then
					-- a burning torch held high (raid Torchbearers set houses alight with it)
					local hand = V(1.42, -1.1, 0)
					local top = hand + V(0, 2.3, -0.6)
					cylinder(hand + V(0, -0.5, 0.2), top, 0.26 * s, WOOD)
					cylinder(top - V(0, 0.35, 0), top + V(0, 0.15, 0), 0.42 * s, LEATHER)
					local flame = ellipsoid(V(0.7, 1.1, 0.7), top + V(0, 0.55, 0), Color3.fromRGB(255, 150, 50), Enum.Material.Neon)
					local fire = Instance.new("Fire")
					fire.Size = 2.5 * s
					fire.Heat = 7
					fire.Color = Color3.fromRGB(255, 140, 40)
					fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
					fire.Parent = flame
					local light = Instance.new("PointLight")
					light.Color = Color3.fromRGB(255, 160, 70)
					light.Range = 16
					light.Brightness = 1.6
					light.Parent = flame
				elseif weapon == "staff" then
					local hand = V(1.42, -1.1, 0)
					local top = hand + V(0, 3.4, -0.4)
					cylinder(hand + V(0, -1.6, 0.2), top, 0.28 * s, WOOD)
					ellipsoid(V(0.9, 0.9, 0.9), top + V(0, 0.4, 0), look.glow or GOLD, Enum.Material.Neon)
				end
			else
				if weapon == "twinAxe" then
					axe(-1, false)
				elseif look.shield then
					local d = look.bigShield and 3.1 or 2.3
					local center = V(-1.95, -0.2, 0)
					cylinder(center + V(-0.12, 0, 0), center + V(0.12, 0, 0), d * s, look.shirt, Enum.Material.Wood)
					cylinder(center + V(-0.08, 0, 0), center + V(0.1, 0, 0), (d + 0.2) * s, DARK_METAL, Enum.Material.Metal)
					part("Part", V(0.3, d * 0.95, 0.35), CFrame.new(center + V(-0.13, 0, 0)), Color3.fromRGB(240, 235, 220), Enum.Material.Wood)
					ellipsoid(V(0.45, 0.6, 0.6), center + V(-0.2, 0, 0), METAL, Enum.Material.Metal)
				end
			end
		end))
	end

	---------------------------------------------------------------- legs
	for _, side in ipairs({ -1, 1 }) do
		local leg = part("Part", V(0.92, 2, 0.95), CFrame.new(V(0.5 * side, -2, 0)), look.pants)
		leg.Name = side > 0 and "RightLeg" or "LeftLeg"
		weldAll(leg, collect(function()
			part("Part", V(1.0, 0.65, 1.12), CFrame.new(V(0.5 * side, -2.72, -0.06)), Color3.fromRGB(70, 50, 35))
			ellipsoid(V(1.1, 0.45, 1.1), V(0.5 * side, -2.35, 0), Color3.fromRGB(130, 110, 90))
		end))
		motor(side > 0 and "LegR" or "LegL", torso, leg, CFrame.new(V(0.5 * side, -1, 0)))
	end

	local hipHeight = (3.05 - 1) * s
	return model, hipHeight
end

return VikingBuilder
