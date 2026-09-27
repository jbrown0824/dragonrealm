-- Builds a dragon model out of parts, in code, so no meshes or uploads are needed.
-- Used for player characters, the village dragons, the town statue and the 3D previews on
-- the class select screen.
--
-- The model faces -Z. Wings, tail segments and legs hang off Motor6Ds named
-- WingL/WingR, Tail1..Tail4, LegFL/LegFR/LegBL/LegBR so the client can animate them.

local Classes = require(script.Parent.Config.Classes)

local DragonBuilder = {}

local BUILDS = {
	sleek = { w = 1.0, h = 1.0, l = 1.0, wing = 1.0, neck = 1.0 },
	slender = { w = 0.85, h = 0.9, l = 1.05, wing = 1.25, neck = 1.12 },
	bulky = { w = 1.3, h = 1.15, l = 1.0, wing = 0.85, neck = 0.85 },
	spiny = { w = 1.0, h = 1.0, l = 1.0, wing = 1.0, neck = 1.0 },
}

local HORNS = {
	Shadowstalker = "sweep",
	Stormwing = "sweepLong",
	Behemoth = "ram",
	Frostwyrm = "crystal",
	Venomspine = "crown",
}

local TAILS = {
	Shadowstalker = "blade",
	Stormwing = "fin",
	Behemoth = "club",
	Frostwyrm = "crystal",
	Venomspine = "stinger",
}

-- Builds a dragon. options:
--   scale (number), anchored (bool), name (string), material (Enum.Material),
--   tint (Color3: paint everything one color, e.g. a stone statue), noParticles (bool)
-- Returns model, hipHeight
function DragonBuilder.build(classId: string, options)
	options = options or {}
	local class = Classes.get(classId) or Classes.get("Shadowstalker")
	local s = (options.scale or 1) * class.scale
	local b = BUILDS[class.build] or BUILDS.sleek
	local tint = options.tint
	local baseMaterial = options.material or Enum.Material.SmoothPlastic
	local colors = class.colors
	local isFrost = class.id == "Frostwyrm"

	local model = Instance.new("Model")
	model.Name = options.name or class.name

	local function V(x, y, z)
		return Vector3.new(x * s, y * s, z * s)
	end

	local function color(c: Color3): Color3
		return tint or c
	end

	local function styleMaterial(m: Enum.Material?): Enum.Material
		if tint then
			return baseMaterial
		end
		return m or baseMaterial
	end

	local function makePart(className: string, size: Vector3, cf: CFrame, c: Color3, material: Enum.Material?)
		local p = Instance.new(className)
		p.Size = size
		p.CFrame = cf
		p.Color = color(c)
		p.Material = styleMaterial(material)
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local function weld(a: BasePart, p: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = p
		w.Parent = p
	end

	local function ellipsoid(size: Vector3, cf: CFrame, c: Color3, material: Enum.Material?)
		local p = makePart("Part", size, cf, c, material)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end

	local function lookAt(from: Vector3, to: Vector3): CFrame
		local dir = to - from
		if dir.Magnitude < 1e-4 then
			return CFrame.new(from)
		end
		local up = Vector3.yAxis
		if math.abs(dir.Unit:Dot(up)) > 0.98 then
			up = Vector3.zAxis
		end
		return CFrame.lookAt(from, to, up)
	end

	-- An ellipsoid stretched from a to b: bones, limbs, horns.
	local function limb(a: Vector3, bb: Vector3, thickness: number, c: Color3, material: Enum.Material?)
		local length = (bb - a).Magnitude
		local cf = lookAt((a + bb) / 2, bb)
		return ellipsoid(Vector3.new(thickness, thickness, length + thickness * 0.4), cf, c, material)
	end

	-- A flat triangle made of two wedges (the classic Roblox 3D-triangle trick).
	local function triangle(a: Vector3, bb: Vector3, c: Vector3, col: Color3, material: Enum.Material?, transparency: number?)
		local ab, ac, bc = bb - a, c - a, c - bb
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, bb = bb, a
		end
		ab, ac, bc = bb - a, c - a, c - bb
		local cross = ac:Cross(ab)
		if cross.Magnitude < 1e-5 then
			return {}
		end
		local right = cross.Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local thickness = 0.12 * s
		local w1 = makePart("WedgePart", Vector3.new(thickness, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + bb) / 2, right, up, back), col, material)
		local w2 = makePart("WedgePart", Vector3.new(thickness, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back), col, material)
		if transparency then
			w1.Transparency = transparency
			w2.Transparency = transparency
		end
		return { w1, w2 }
	end

	local function motor(name: string, part0: BasePart, part1: BasePart, jointWorld: CFrame)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = part0.CFrame:Inverse() * jointWorld
		m.C1 = part1.CFrame:Inverse() * jointWorld
		m.Parent = part0
		return m
	end

	local function jointPart(name: string, pos: Vector3)
		local p = makePart("Part", Vector3.new(0.4, 0.4, 0.4) * s, CFrame.new(pos), Color3.new(), nil)
		p.Name = name
		p.Transparency = 1
		p.CastShadow = false
		return p
	end

	-- Collect parts created during `fn` so they can all be welded to one anchor.
	local function group(anchor: BasePart, fn)
		local before = {}
		for _, child in ipairs(model:GetChildren()) do
			before[child] = true
		end
		fn()
		for _, child in ipairs(model:GetChildren()) do
			if not before[child] and child:IsA("BasePart") and child ~= anchor then
				weld(anchor, child)
			end
		end
	end

	---------------------------------------------------------------- root + body
	local rootSize = Vector3.new(3.6 * b.w, 3, 6) * s
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = rootSize
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = true
	root.Anchored = options.anchored == true
	root.Parent = model
	model.PrimaryPart = root

	local groundY = -4.2 * s
	local hipHeight = -groundY - rootSize.Y / 2

	local torso = ellipsoid(V(4.2 * b.w, 3.6 * b.h, 7.5 * b.l), CFrame.new(V(0, 0, 0.3)), colors.primary)
	torso.Name = "Torso"
	weld(root, torso)

	group(torso, function()
		ellipsoid(V(3.4 * b.w, 2.6 * b.h, 6.4 * b.l), CFrame.new(V(0, -0.75 * b.h, 0.2)), colors.belly)
		ellipsoid(V(3.9 * b.w, 3.4 * b.h, 3.8), CFrame.new(V(0, 0.25, -2.9 * b.l)), colors.primary)
		ellipsoid(V(3.5 * b.w, 3.0 * b.h, 3.4), CFrame.new(V(0, 0.1, 3.1 * b.l)), colors.primary)

		-- Neck
		local neckBase = V(0, 0.9 * b.h, -3.9 * b.l)
		local headBase = neckBase + V(0, 2.5 * b.neck, -2.3 * b.neck)
		local neckMid = (neckBase + headBase) / 2 + V(0, -0.1, -0.35)
		limb(neckBase, neckMid, 2.3 * s * b.w, colors.primary)
		limb(neckMid, headBase, 1.95 * s * b.w, colors.primary)
		ellipsoid(V(1.5 * b.w, 1.2, 2.2), lookAt(neckMid + V(0, -0.6, -0.2), headBase + V(0, -0.7, -0.2)), colors.belly)

		-- Head
		local headPos = headBase + V(0, 0.45, -0.7)
		local head = ellipsoid(V(2.6 * b.w, 2.2, 3.2), CFrame.new(headPos), colors.primary)
		head.Name = "Head"
		ellipsoid(V(1.9 * b.w, 1.4, 2.9), CFrame.new(headPos + V(0, -0.35, -1.75)), colors.primary)
		ellipsoid(V(1.7 * b.w, 0.7, 2.6), CFrame.new(headPos + V(0, -1.0, -1.35)), colors.belly)
		for _, side in ipairs({ -1, 1 }) do
			local eye = ellipsoid(V(0.6, 0.6, 0.6), CFrame.new(headPos + V(0.95 * b.w * side, 0.4, -0.75)), colors.eyes, Enum.Material.Neon)
			eye.Name = "Eye"
			ellipsoid(V(0.85, 0.35, 1.3), CFrame.new(headPos + V(0.85 * b.w * side, 0.78, -0.6)), colors.secondary)
			ellipsoid(V(0.28, 0.28, 0.28), CFrame.new(headPos + V(0.38 * side, -0.05, -3.1)), Color3.fromRGB(20, 20, 20))
		end

		local mouth = Instance.new("Attachment")
		mouth.Name = "Mouth"
		mouth.CFrame = head.CFrame:Inverse() * CFrame.new(headPos + V(0, -0.55, -3.25))
		mouth.Parent = head

		-- Horns
		local hornStyle = HORNS[class.id] or "sweep"
		local hornMat = isFrost and Enum.Material.Ice or nil
		for _, side in ipairs({ -1, 1 }) do
			local function H(x, y, z)
				return headPos + V(x * side, y, z)
			end
			if hornStyle == "sweep" then
				limb(H(0.7, 0.8, 0.4), H(1.0, 1.5, 1.9), 0.55 * s, colors.horn, hornMat)
				limb(H(1.0, 1.5, 1.9), H(1.15, 1.8, 3.1), 0.32 * s, colors.horn, hornMat)
			elseif hornStyle == "sweepLong" then
				limb(H(0.6, 0.8, 0.4), H(0.9, 1.3, 2.2), 0.45 * s, colors.horn)
				limb(H(0.9, 1.3, 2.2), H(1.0, 1.5, 3.9), 0.25 * s, colors.horn)
				limb(H(1.25, 0.1, 0.5), H(1.9, 0.3, 1.5), 0.2 * s, colors.accent)
			elseif hornStyle == "ram" then
				limb(H(0.9, 0.8, 0.2), H(1.9, 1.3, 0.9), 0.95 * s, colors.horn)
				limb(H(1.9, 1.3, 0.9), H(2.4, 0.5, 1.8), 0.8 * s, colors.horn)
				limb(H(2.4, 0.5, 1.8), H(2.2, -0.6, 1.2), 0.62 * s, colors.horn)
				limb(H(2.2, -0.6, 1.2), H(1.7, -0.9, 0.3), 0.45 * s, colors.horn)
			elseif hornStyle == "crystal" then
				limb(H(0.7, 0.8, 0.3), H(1.05, 1.9, 1.8), 0.55 * s, colors.horn, Enum.Material.Ice)
				limb(H(1.05, 1.9, 1.8), H(1.15, 2.4, 2.9), 0.3 * s, colors.accent, Enum.Material.Ice)
				limb(H(1.1, 0.5, 0.9), H(1.9, 1.1, 1.9), 0.3 * s, colors.accent, Enum.Material.Ice)
			elseif hornStyle == "crown" then
				for i = 0, 2 do
					local z = 0.3 + i * 0.55
					limb(H(0.35 + i * 0.3, 0.85 - i * 0.1, z), H(0.6 + i * 0.5, 1.9 - i * 0.2, z + 1.1), 0.3 * s, colors.horn)
				end
			end
		end
		if hornStyle == "ram" then
			limb(headPos + V(0, 0.4, -2.2), headPos + V(0, 1.4, -2.6), 0.5 * s, colors.horn)
		end

		-- Neck spines
		for i, t in ipairs({ 0.25, 0.6, 0.9 }) do
			local p = neckBase:Lerp(headBase, t) + V(0, 0.95, 0.2)
			local h = 0.7 - i * 0.1
			triangle(p + V(0, 0, -0.35), p + V(0, 0, 0.45), p + V(0, h, 0.4), colors.accent)
		end

		-- Class flair
		if class.id == "Behemoth" then
			for _, side in ipairs({ -1, 1 }) do
				limb(V(2.02 * side, 0.6, -1.8), V(2.08 * side, -0.4, 1.4), 0.22 * s, colors.accent, Enum.Material.Neon)
				limb(V(1.9 * side, -0.2, -2.6), V(1.95 * side, -0.9, -0.6), 0.18 * s, colors.accent, Enum.Material.Neon)
				-- armored shoulder plates
				ellipsoid(V(1.4, 1.5, 3.2), CFrame.new(V(2.1 * side, 0.9, -1.8)), colors.secondary, Enum.Material.Slate)
			end
		elseif class.id == "Venomspine" then
			for i = 0, 4 do
				ellipsoid(V(0.55, 0.3, 0.55), CFrame.new(V((i % 2 == 0) and 1.1 or -1.1, 1.45, -2 + i * 1.2)), colors.accent, Enum.Material.Neon)
			end
		elseif class.id == "Stormwing" then
			for _, side in ipairs({ -1, 1 }) do
				limb(V(1.9 * side * b.w, 0.4, -2.6), V(1.95 * side * b.w, 0.1, 2.6), 0.16 * s, colors.accent, Enum.Material.Neon)
			end
		end
	end)

	local head = model:FindFirstChild("Head") :: BasePart

	---------------------------------------------------------------- back spines
	local spineMaterial = isFrost and Enum.Material.Ice or (class.id == "Behemoth" and Enum.Material.Slate or nil)
	local spineHeight = class.build == "spiny" and 1.7 or 1
	local torsoSpines = {
		{ z = -3.0, y = 1.6, h = 0.8 },
		{ z = -1.4, y = 1.8, h = 1.0 },
		{ z = 0.3, y = 1.85, h = 1.1 },
		{ z = 2.0, y = 1.65, h = 1.0 },
		{ z = 3.5, y = 1.25, h = 0.9 },
	}
	group(torso, function()
		for _, sp in ipairs(torsoSpines) do
			local base = V(0, sp.y * b.h, sp.z * b.l)
			local h = sp.h * spineHeight
			triangle(base + V(0, -0.1, -0.6 * sp.h), base + V(0, -0.1, 0.6 * sp.h), base + V(0, h, 0.45 * h), colors.accent, spineMaterial)
			if class.build == "spiny" then
				for _, side in ipairs({ -1, 1 }) do
					limb(base + V(0.9 * side, -0.4, 0), base + V(1.5 * side, 0.4, 0.6), 0.25 * s, colors.accent)
				end
			end
		end
	end)

	---------------------------------------------------------------- wings
	local wingScale = b.wing
	local wingMaterial = isFrost and Enum.Material.Glass or nil
	for _, side in ipairs({ -1, 1 }) do
		local shoulder = V(1.7 * side * b.w, 1.3 * b.h, -1.4 * b.l)
		local wingRoot = jointPart(side > 0 and "WingRootR" or "WingRootL", shoulder)
		local function W(x, y, z)
			return shoulder + V(x * side * wingScale, y * wingScale, z * wingScale)
		end
		group(wingRoot, function()
			local R0, E, Wr = W(0, 0, 0), W(4.2, 1.3, -0.3), W(7.8, 2.0, 0.8)
			local F1, F2, F3 = W(11.2, 1.0, 2.6), W(9.2, 0.0, 5.0), W(5.8, -0.4, 6.0)
			local Rb = W(0, -0.3, 4.6)
			local membrane = colors.wing
			local transparency = isFrost and 0.25 or nil
			triangle(R0, E, Rb, membrane, wingMaterial, transparency)
			triangle(E, F3, Rb, membrane, wingMaterial, transparency)
			triangle(E, Wr, F3, membrane, wingMaterial, transparency)
			triangle(Wr, F2, F3, membrane, wingMaterial, transparency)
			triangle(Wr, F1, F2, membrane, wingMaterial, transparency)
			limb(R0, E, 0.6 * s, colors.secondary)
			limb(E, Wr, 0.48 * s, colors.secondary)
			limb(Wr, F1, 0.32 * s, colors.secondary)
			limb(Wr, F2, 0.26 * s, colors.secondary)
			limb(Wr, F3, 0.22 * s, colors.secondary)
			limb(Wr, Wr + V(0.1 * side, 0.4, -0.9), 0.28 * s, colors.horn)
		end)
		motor(side > 0 and "WingR" or "WingL", torso, wingRoot, CFrame.new(shoulder))
	end

	---------------------------------------------------------------- tail
	local tailSegs = {
		{ center = V(0, 0.0, 5.3 * b.l), size = V(2.5 * b.w, 2.1 * b.h, 3.8), joint = V(0, 0.05, 3.7 * b.l) },
		{ center = V(0, -0.35, 8.0 * b.l), size = V(1.8 * b.w, 1.5 * b.h, 3.6), joint = V(0, -0.2, 6.7 * b.l) },
		{ center = V(0, -0.7, 10.6 * b.l), size = V(1.2 * b.w, 1.0 * b.h, 3.4), joint = V(0, -0.55, 9.3 * b.l) },
		{ center = V(0, -0.95, 12.9 * b.l), size = V(0.75 * b.w, 0.65 * b.h, 3.0), joint = V(0, -0.85, 11.8 * b.l) },
	}
	local tailSpines = {
		{ seg = 1, z = 5.4, y = 1.0, h = 0.8 },
		{ seg = 2, z = 7.9, y = 0.45, h = 0.65 },
		{ seg = 3, z = 10.5, y = -0.2, h = 0.5 },
		{ seg = 4, z = 12.7, y = -0.6, h = 0.38 },
	}
	local prev = torso
	local segParts = {}
	for i, seg in ipairs(tailSegs) do
		local part = ellipsoid(seg.size, CFrame.new(seg.center), colors.primary)
		part.Name = "Tail" .. i
		segParts[i] = part
		motor("Tail" .. i, prev, part, CFrame.new(seg.joint))
		prev = part
	end
	for _, sp in ipairs(tailSpines) do
		group(segParts[sp.seg], function()
			local base = V(0, sp.y, sp.z * b.l)
			local h = sp.h * spineHeight
			triangle(base + V(0, -0.1, -0.5 * sp.h), base + V(0, -0.1, 0.5 * sp.h), base + V(0, h, 0.45 * h), colors.accent, spineMaterial)
		end)
	end

	local tip = V(0, -1.05, 14.5 * b.l)
	local tailStyle = TAILS[class.id] or "blade"
	group(segParts[4], function()
		if tailStyle == "blade" then
			triangle(tip + V(0, 1.0, -0.4), tip + V(0, 0, 2.6), tip + V(0, -1.0, -0.4), colors.accent, Enum.Material.Neon)
		elseif tailStyle == "fin" then
			triangle(tip + V(0, 0, -0.6), tip + V(0, 1.7, 1.8), tip + V(0, 0, 2.3), colors.secondary)
			triangle(tip + V(-1.5, 0, 2.0), tip + V(1.5, 0, 2.0), tip + V(0, 0, -0.6), colors.secondary)
		elseif tailStyle == "club" then
			ellipsoid(V(2.0, 1.9, 2.2), CFrame.new(tip + V(0, 0, 0.5)), colors.horn, Enum.Material.Slate)
			for _, d in ipairs({ Vector3.new(1, 0.4, 0), Vector3.new(-1, 0.4, 0), Vector3.new(0, 1, 0.2), Vector3.new(0, -0.6, 0.8), Vector3.new(0, 0.2, 1) }) do
				limb(tip + V(0, 0, 0.5) + d * s * 0.7, tip + V(0, 0, 0.5) + d * s * 1.7, 0.45 * s, colors.horn)
			end
			ellipsoid(V(2.05, 0.3, 1.2), CFrame.new(tip + V(0, 0.2, 0.5)), colors.accent, Enum.Material.Neon)
		elseif tailStyle == "crystal" then
			limb(tip + V(0, 0, -0.3), tip + V(0, 0.6, 2.4), 0.9 * s, colors.accent, Enum.Material.Ice)
			limb(tip + V(0, 0, 0.3), tip + V(0.9, 0.9, 1.4), 0.5 * s, colors.horn, Enum.Material.Ice)
			limb(tip + V(0, 0, 0.3), tip + V(-0.9, 0.9, 1.4), 0.5 * s, colors.horn, Enum.Material.Ice)
		elseif tailStyle == "stinger" then
			limb(tip + V(0, 0, -0.2), tip + V(0, 0.9, 2.1), 0.6 * s, colors.horn)
			ellipsoid(V(0.45, 0.45, 0.45), CFrame.new(tip + V(0, 1.0, 2.3)), colors.accent, Enum.Material.Neon)
		end
	end)

	---------------------------------------------------------------- legs
	local legs = {
		{ name = "LegFL", hip = V(-1.55 * b.w, -1.0, -2.4 * b.l), front = true, side = -1 },
		{ name = "LegFR", hip = V(1.55 * b.w, -1.0, -2.4 * b.l), front = true, side = 1 },
		{ name = "LegBL", hip = V(-1.75 * b.w, -1.0, 2.2 * b.l), front = false, side = -1 },
		{ name = "LegBR", hip = V(1.75 * b.w, -1.0, 2.2 * b.l), front = false, side = 1 },
	}
	for _, leg in ipairs(legs) do
		local hip = leg.hip
		local foot = Vector3.new(hip.X + 0.3 * s * leg.side, groundY + 0.4 * s, hip.Z - 0.2 * s)
		local knee
		if leg.front then
			knee = hip:Lerp(foot, 0.5) + V(0.15 * leg.side, 0, 0.55)
		else
			knee = hip:Lerp(foot, 0.45) + V(0.2 * leg.side, 0.1, -0.75)
		end
		local thick = (leg.front and 1.25 or 1.5) * s * b.w
		local upper = limb(hip, knee, thick, colors.primary)
		upper.Name = leg.name
		group(upper, function()
			limb(knee, foot, thick * 0.72, colors.primary)
			ellipsoid(V(1.05 * b.w, 0.6, 1.6), CFrame.new(foot + V(0, -0.05, -0.35)), colors.secondary)
			for _, dx in ipairs({ -0.35, 0, 0.35 }) do
				limb(foot + V(dx * b.w, -0.15, -1.0), foot + V(dx * b.w * 1.2, -0.35, -1.55), 0.22 * s, colors.horn)
			end
		end)
		motor(leg.name, torso, upper, CFrame.new(hip))
	end

	---------------------------------------------------------------- lights & particles
	if not options.noParticles and not tint then
		local light = Instance.new("PointLight")
		light.Color = colors.eyes
		light.Range = 10 * s
		light.Brightness = 0.8
		light.Parent = head

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.LightEmission = 0.6
		emitter.Rate = 4
		emitter.Lifetime = NumberRange.new(1, 1.8)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(class.fire.colorA, class.fire.colorB)
		if class.id == "Shadowstalker" then
			emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
			emitter.Size = NumberSequence.new(1.5 * s, 3.5 * s)
		elseif class.id == "Venomspine" then
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Acceleration = Vector3.new(0, -8, 0)
			emitter.Size = NumberSequence.new(0.35 * s)
		elseif class.id == "Frostwyrm" then
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Acceleration = Vector3.new(0, -2, 0)
			emitter.Size = NumberSequence.new(0.3 * s)
			emitter.Rate = 6
		elseif class.id == "Behemoth" then
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Acceleration = Vector3.new(0, 4, 0)
			emitter.Size = NumberSequence.new(0.35 * s, 0)
		else
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Size = NumberSequence.new(0.3 * s, 0)
		end
		emitter.Parent = torso
	end

	model:SetAttribute("DragonClass", class.id)
	model:SetAttribute("HipHeight", hipHeight)
	model:SetAttribute("DragonScale", s)
	return model, hipHeight
end

return DragonBuilder
