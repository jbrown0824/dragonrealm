-- Builds a dragon model out of parts, in code, so no meshes or uploads are needed.
-- Used for player characters, the village dragons, the town statue and the 3D previews on
-- the class select screen.
--
-- Every Dragon Realm dragon shares a signature look: a glowing ember core showing between its
-- belly plates (and a glowing slit on the chest), rune markings on the flanks, scalloped
-- two-part wings, and a hinged jaw with teeth. Each dragon type then has its own body plan
-- (see PLANS) so the silhouettes are clearly different.
--
-- The model faces -Z and is built in a spread "gliding" pose. Clients animate it through the
-- Motor6Ds listed in DragonRig (neck, head, jaw, eyelids, two-part wings, knees, tail...).

local Classes = require(script.Parent.Config.Classes)

local DragonBuilder = {}

local IVORY = Color3.fromRGB(240, 232, 214)
local DARK = Color3.fromRGB(18, 14, 20)

-- Body plans. Sizes are in studs before scaling. rise = neck angle above horizontal (radians).
local PLANS = {
	-- Feline night hunter: low arched body, long legs, swept blade horns, bladed tail fan.
	Shadowstalker = {
		body = { w = 3.4, h = 3.0, l = 7.6, y = 0.25, pitch = 0 },
		neck = { segs = 2, len = 3.6, thick = 1.75, rise = 0.55 },
		head = { style = "feline", w = 2.3, h = 1.8, l = 2.8 },
		tail = { segs = 6, len = 12, thick = 1.9, droop = 0.08, tip = "fan" },
		wings = { span = 1.0, fingers = 3, tattered = true },
		legs = { count = 4, thick = 1.05, splay = 1.0 },
		back = "blades",
		marks = "chevrons",
	},
	-- Wyvern: two legs, wings as forelimbs, upright chest, tall fin crest, kite-fin tail.
	Stormwing = {
		body = { w = 3.0, h = 2.8, l = 6.8, y = 0.55, pitch = 0.2 },
		neck = { segs = 3, len = 4.8, thick = 1.45, rise = 0.5 },
		head = { style = "crested", w = 1.9, h = 1.6, l = 3.3 },
		tail = { segs = 6, len = 13, thick = 1.5, droop = 0.02, tip = "kite" },
		wings = { span = 1.32, fingers = 4 },
		legs = { count = 2, thick = 1.25, splay = 1.05 },
		back = "fins",
		marks = "bolts",
	},
	-- Armored hulk: huge rock shell with lava seams, thick short neck, tusks, club tail.
	Behemoth = {
		body = { w = 5.2, h = 4.0, l = 7.6, y = 0.35, pitch = 0 },
		neck = { segs = 2, len = 2.6, thick = 2.7, rise = 0.35 },
		head = { style = "brute", w = 2.8, h = 2.2, l = 3.4 },
		tail = { segs = 4, len = 8, thick = 2.8, droop = 0.14, tip = "club" },
		wings = { span = 0.72, fingers = 3, armored = true },
		legs = { count = 4, thick = 1.9, splay = 1.08 },
		back = "shell",
		marks = "lava",
	},
	-- Serpentine ice wyrm: long body, long neck, very long tail, crystal spines, glass wings.
	Frostwyrm = {
		body = { w = 3.0, h = 2.7, l = 9.2, y = 0.1, pitch = 0 },
		neck = { segs = 4, len = 6.4, thick = 1.6, rise = 0.45 },
		head = { style = "wyrm", w = 2.1, h = 1.7, l = 3.4 },
		tail = { segs = 8, len = 17, thick = 1.9, droop = 0.1, tip = "crystal" },
		wings = { span = 1.05, fingers = 4, glass = true },
		legs = { count = 4, thick = 0.95, splay = 1.1 },
		back = "crystals",
		marks = "frost",
	},
	-- Frilled lizard: wide low stance, neck frill that flares open, quills, curling stinger tail.
	Venomspine = {
		body = { w = 4.0, h = 2.8, l = 7.0, y = -0.05, pitch = 0 },
		neck = { segs = 2, len = 3.0, thick = 1.95, rise = 0.4 },
		head = { style = "flat", w = 2.6, h = 1.6, l = 2.8 },
		tail = { segs = 7, len = 12.5, thick = 1.9, droop = 0.05, tip = "stinger", curl = true },
		wings = { span = 0.95, fingers = 3 },
		legs = { count = 4, thick = 1.25, splay = 1.3 },
		back = "quills",
		marks = "spots",
		frill = true,
	},
	-- Sea dragon (legendary): a long smooth body, manta fin-wings of see-through water on glowing
	-- ribs, a ribbed sail down the back, gill frills, whiskers and a pearl on the brow, webbed
	-- feet and a whale's fluke for a tail.
	Tidecaller = {
		body = { w = 3.3, h = 2.7, l = 8.4, y = 0.15, pitch = 0 },
		neck = { segs = 3, len = 4.6, thick = 1.6, rise = 0.5 },
		head = { style = "sea", w = 2.3, h = 1.7, l = 3.2 },
		tail = { segs = 7, len = 14, thick = 1.9, droop = 0.06, tip = "fluke" },
		wings = { span = 1.12, fingers = 4, fins = true },
		legs = { count = 4, thick = 1.05, splay = 1.12, webbed = true },
		back = "sail",
		marks = "waves",
	},
	-- Sun dragon (legendary): gilded armor plates, layered flight feathers over a sunlit
	-- membrane, a crown of horns with a blazing sunburst halo behind it, gold greaves and a
	-- phoenix plume of a tail.
	Solaris = {
		body = { w = 3.4, h = 3.1, l = 7.8, y = 0.4, pitch = 0.1 },
		neck = { segs = 3, len = 4.8, thick = 1.7, rise = 0.6 },
		head = { style = "regal", w = 2.2, h = 1.8, l = 3.1 },
		tail = { segs = 6, len = 12.5, thick = 1.8, droop = 0.05, tip = "plume" },
		wings = { span = 1.28, fingers = 4, feathers = true },
		legs = { count = 4, thick = 1.05, splay = 1.0, greaves = true },
		back = "plates",
		marks = "sunrays",
		halo = true,
	},
}
DragonBuilder.PLANS = PLANS

-- Builds a dragon. options:
--   scale (number), anchored (bool), name (string), material (Enum.Material),
--   tint (Color3: paint everything one color, e.g. a stone statue), noParticles (bool),
--   colors / fire (tables overriding the class palette, used by nano dragon pets),
--   lite (bool: skip teeth, claws, belly plates and markings; for tiny pets)
-- Returns model, hipHeight
function DragonBuilder.build(classId: string, options)
	options = options or {}
	local class = Classes.get(classId) or Classes.get("Shadowstalker")
	local plan = PLANS[class.id] or PLANS.Shadowstalker
	local s = (options.scale or 1) * class.scale
	local tint = options.tint
	local baseMaterial = options.material or Enum.Material.SmoothPlastic
	local colors = options.colors or class.colors
	local fire = class.fire
	if options.fire then
		fire = table.clone(class.fire)
		for k, v in pairs(options.fire) do
			fire[k] = v
		end
	end
	local lite = options.lite == true
	local isFrost = class.id == "Frostwyrm"

	local model = Instance.new("Model")
	model.Name = options.name or class.name

	---------------------------------------------------------------- helpers
	local function V(x, y, z)
		return Vector3.new(x * s, y * s, z * s)
	end

	local function paint(c: Color3): Color3
		return tint or c
	end

	local function mat(m: Enum.Material?): Enum.Material
		if tint then
			return baseMaterial
		end
		return m or baseMaterial
	end

	local function makePart(className: string, size: Vector3, cf: CFrame, c: Color3, material: Enum.Material?)
		local p = Instance.new(className)
		p.Size = size
		p.CFrame = cf
		p.Color = paint(c)
		p.Material = mat(material)
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
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

	-- An ellipsoid stretched from a to b (bones, limbs, horns, spikes). `thickness` in studs.
	local function limb(a: Vector3, b: Vector3, thickness: number, c: Color3, material: Enum.Material?, flat: number?)
		local length = (b - a).Magnitude
		local cf = lookAt((a + b) / 2, b)
		return ellipsoid(Vector3.new(thickness, thickness * (flat or 1), length + thickness * 0.35), cf, c, material)
	end

	-- A flat triangle made of two wedges (the classic Roblox 3D-triangle trick).
	local function triangle(a: Vector3, b: Vector3, c: Vector3, col: Color3, material: Enum.Material?, transparency: number?, thick: number?)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local cross = ac:Cross(ab)
		if cross.Magnitude < 1e-5 then
			return
		end
		local right = cross.Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local t = (thick or 0.12) * s
		local w1 = makePart("WedgePart", Vector3.new(t, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back), col, material)
		local w2 = makePart("WedgePart", Vector3.new(t, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back), col, material)
		if transparency then
			w1.Transparency = transparency
			w2.Transparency = transparency
		end
	end

	local function motor(name: string, part0: BasePart, part1: BasePart, joint: CFrame)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = part0.CFrame:Inverse() * joint
		m.C1 = part1.CFrame:Inverse() * joint
		m.Parent = part0
		return m
	end

	local function jointPart(name: string, pos: Vector3)
		local p = makePart("Part", Vector3.new(0.3, 0.3, 0.3) * s, CFrame.new(pos), Color3.new(), nil)
		p.Name = name
		p.Transparency = 1
		p.CastShadow = false
		return p
	end

	-- Weld every part created inside `fn` to `anchor`.
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

	---------------------------------------------------------------- root & body frame
	local body = plan.body
	local bw, bh, bl = body.w, body.h, body.l
	local groundY = -4.2 * s

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(math.clamp(bw, 3, 4.6), 3, 6) * s
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = true
	root.Anchored = options.anchored == true
	root.Parent = model
	model.PrimaryPart = root
	local hipHeight = -groundY - root.Size.Y / 2

	local bodyCF = CFrame.new(V(0, body.y, 0)) * CFrame.Angles(body.pitch, 0, 0)
	local function B(x, y, z) -- point in the (possibly pitched) body frame
		return bodyCF * V(x, y, z)
	end
	local function BCF(x, y, z)
		return bodyCF * CFrame.new(V(x, y, z))
	end
	-- height of the body's top surface at body-z (approximate ellipsoid profile)
	local function topY(z)
		local u = math.clamp((z - 0.2) / (bl * 0.55), -1, 1)
		return bh * 0.5 * math.sqrt(1 - u * u)
	end

	local torso = ellipsoid(V(bw, bh, bl), BCF(0, 0, 0.2), colors.primary)
	torso.Name = "Torso"
	motor("BodyJoint", root, torso, BCF(0, 0, 0.2))

	group(torso, function()
		ellipsoid(V(bw * 0.96, bh * 1.06, bl * 0.5), BCF(0, bh * 0.08, -bl * 0.33), colors.primary)
		ellipsoid(V(bw * 0.9, bh * 0.94, bl * 0.46), BCF(0, 0, bl * 0.36), colors.primary)

		-- Ember core: glows between the belly plates and through a slit in the chest.
		local core = ellipsoid(V(bw * 0.62, bh * 0.46, bl * 0.64), BCF(0, -bh * 0.3, -bl * 0.06), fire.colorA, Enum.Material.Neon)
		core.Name = "Core"
		ellipsoid(V(0.42, bh * 0.36, 0.3), BCF(0, -bh * 0.12, -bl * 0.57), fire.colorA, Enum.Material.Neon).Name = "CoreSlit"
		if not tint then
			local light = Instance.new("PointLight")
			light.Name = "CoreLight"
			light.Color = fire.colorA
			light.Range = 9 * s
			light.Brightness = 1
			light.Parent = core
		end
		for i = 0, lite and -1 or 4 do
			local z = -bl * 0.38 + i * bl * 0.17
			local wide = bw * (0.8 - math.abs(i - 2) * 0.07)
			ellipsoid(V(wide, bh * 0.2, bl * 0.105), BCF(0, -bh * 0.46 + math.abs(i - 2) * 0.05, z), colors.belly)
		end

		-- Back decoration (class signature)
		local backStyle = plan.back
		local spineCount = 6
		for i = 0, spineCount - 1 do
			local z = -bl * 0.36 + i * (bl * 0.78 / (spineCount - 1))
			local y = topY(z)
			local base = B(0, y - 0.1, z)
			if backStyle == "blades" then
				local h = 0.9 + (i % 2) * 0.2
				triangle(base + V(0, 0, -0.55), base + V(0, 0, 0.6), base + V(0, h, 0.75), colors.accent, nil, nil, 0.14)
			elseif backStyle == "fins" then
				local h = 1.4 - i * 0.12
				triangle(base + V(0, 0, -0.5), base + V(0, 0, 0.7), base + V(0, h, 1.0), colors.secondary, nil, nil, 0.12)
			elseif backStyle == "crystals" then
				for _, side in ipairs({ -1, 1 }) do
					local tilt = V(0.35 * side, 1.3 - (i % 2) * 0.3, 0.4)
					limb(base + V(0.25 * side, -0.1, 0), base + V(0.25 * side, 0, 0) + tilt, 0.42 * s, i % 2 == 0 and colors.accent or colors.horn, Enum.Material.Ice)
				end
			elseif backStyle == "quills" then
				for _, side in ipairs({ -1, 0, 1 }) do
					local tip = base + V(0.55 * side, 1.25 - math.abs(side) * 0.25, 1.1)
					limb(base + V(0.35 * side, -0.15, 0), tip, 0.2 * s, i % 2 == 0 and colors.horn or colors.secondary)
					ellipsoid(V(0.22, 0.22, 0.22), CFrame.new(tip), colors.accent, Enum.Material.Neon)
				end
			elseif backStyle == "plates" then
				-- overlapping gilded plates, each with a little fin, sunfire glowing between them
				ellipsoid(V(bw * 0.62, 0.55, bl * 0.2), bodyCF * CFrame.new(V(0, y + 0.05, z)) * CFrame.Angles(-0.22, 0, 0), colors.wing, Enum.Material.Metal)
				triangle(base + V(0, 0.25, -0.3), base + V(0, 0.25, 0.55), base + V(0, 1.05 - (i % 2) * 0.3, 0.75), colors.horn, Enum.Material.Metal, nil, 0.12)
				if i < spineCount - 1 then
					ellipsoid(V(0.45, 0.3, 0.45), CFrame.new(base + V(0, 0.15, bl * 0.075)), fire.colorA, Enum.Material.Neon)
				end
			end
		end
		if backStyle == "sail" then
			-- one long fin down the back: glowing ribs with see-through webbing between them
			local n = 7
			local bases, tips = {}, {}
			for i = 1, n do
				local z = -bl * 0.38 + (i - 1) * (bl * 0.8 / (n - 1))
				bases[i] = B(0, topY(z) - 0.15, z)
				tips[i] = bases[i] + V(0, 0.7 + 1.7 * math.sin(math.pi * (i - 0.4) / (n + 0.2)), 0.55)
				limb(bases[i], tips[i], 0.16 * s, colors.accent, Enum.Material.Neon)
			end
			for i = 1, n - 1 do
				triangle(bases[i], tips[i], tips[i + 1], colors.wing, Enum.Material.Glass, 0.35, 0.08)
				triangle(bases[i], tips[i + 1], bases[i + 1], colors.wing, Enum.Material.Glass, 0.35, 0.08)
			end
		end
		if backStyle == "shell" then
			-- Two rows of great rock plates with glowing lava seams between them.
			for i = 0, 3 do
				local z = -bl * 0.3 + i * bl * 0.22
				local y = topY(z)
				for _, side in ipairs({ -1, 1 }) do
					local plate = ellipsoid(V(bw * 0.5, 1.1, bl * 0.26), bodyCF * CFrame.new(V(side * bw * 0.22, y - 0.1, z)) * CFrame.Angles(0, 0, -side * 0.4), colors.secondary, Enum.Material.Slate)
					plate.Name = "ShellPlate"
					local spikeBase = B(side * bw * 0.24, y + 0.2, z)
					limb(spikeBase, spikeBase + V(side * 0.5, 1.5 - (i % 2) * 0.4, 0.35), 0.55 * s, colors.horn)
				end
				-- lava seams glowing between the plates
				limb(B(0, y + 0.05, z - bl * 0.11), B(0, y + 0.05, z + bl * 0.11), 0.5 * s, colors.accent, Enum.Material.Neon)
				limb(B(-bw * 0.3, y - 0.2, z + bl * 0.11), B(bw * 0.3, y - 0.2, z + bl * 0.11), 0.32 * s, colors.accent, Enum.Material.Neon)
			end
			for _, side in ipairs({ -1, 1 }) do
				ellipsoid(V(1.6, 1.7, 3.0), BCF(side * bw * 0.45, bh * 0.28, -bl * 0.3), colors.secondary, Enum.Material.Slate)
			end
		end

		-- Rune markings on the flanks
		local marks = not lite and plan.marks or nil
		for _, side in ipairs({ -1, 1 }) do
			local x = side * bw * 0.5
			local runeMat = Enum.Material.Neon
			if marks == "chevrons" then
				for k = 0, 2 do
					local z = -bl * 0.15 + k * bl * 0.16
					limb(B(x, bh * 0.12, z), B(x, -bh * 0.02, z + bl * 0.06), 0.16 * s, colors.accent, runeMat)
					limb(B(x, -bh * 0.02, z + bl * 0.06), B(x, -bh * 0.16, z), 0.16 * s, colors.accent, runeMat)
				end
			elseif marks == "bolts" then
				local pts = { B(x * 0.96, bh * 0.2, -bl * 0.3), B(x, 0, -bl * 0.1), B(x, bh * 0.1, bl * 0.02), B(x * 0.97, -bh * 0.12, bl * 0.25) }
				for k = 1, #pts - 1 do
					limb(pts[k], pts[k + 1], 0.16 * s, colors.accent, runeMat)
				end
			elseif marks == "lava" then
				limb(B(x * 1.01, bh * 0.15, -bl * 0.25), B(x * 1.02, -bh * 0.1, bl * 0.18), 0.22 * s, colors.accent, runeMat)
				limb(B(x, -bh * 0.1, bl * 0.18), B(x * 0.97, bh * 0.05, bl * 0.35), 0.18 * s, colors.accent, runeMat)
			elseif marks == "frost" then
				local c = B(x, 0, 0)
				for k = 0, 2 do
					local a = k * math.pi / 3
					local d = V(0, math.cos(a) * 0.8, math.sin(a) * 0.8)
					limb(c - d, c + d, 0.13 * s, colors.accent, runeMat)
				end
			elseif marks == "spots" then
				for k = 0, 3 do
					ellipsoid(V(0.36, 0.5, 0.5), BCF(x * 1.01, bh * (0.15 - (k % 2) * 0.2), -bl * 0.25 + k * bl * 0.16), colors.accent, runeMat)
				end
			elseif marks == "waves" then
				-- two rolling waves along each flank
				for row = 0, 1 do
					local prevPt
					for k = 0, 6 do
						local z = -bl * 0.24 + k * bl * 0.08
						local pt = B(x * (1.0 - row * 0.03), bh * (0.14 - row * 0.22) + math.sin(k * 1.4 + row) * bh * 0.07, z)
						if prevPt then
							limb(prevPt, pt, 0.14 * s, colors.accent, runeMat)
						end
						prevPt = pt
					end
				end
			elseif marks == "sunrays" then
				-- a sun on each flank, its rays reaching out over the scales
				local c = B(x * 1.02, bh * 0.02, -bl * 0.04)
				ellipsoid(V(0.3, 0.8, 0.8), CFrame.new(c), colors.accent, runeMat)
				for k = 0, 7 do
					local a = k / 8 * math.pi * 2
					local d = Vector3.new(0, math.cos(a), math.sin(a)) * s
					limb(c + d * 0.6, c + d * (k % 2 == 0 and 1.35 or 1.0), 0.12 * s, colors.accent, runeMat)
				end
			end
		end
	end)

	---------------------------------------------------------------- neck
	local neckPlan = plan.neck
	local segLen = neckPlan.len / neckPlan.segs
	local p = B(0, bh * 0.28, -bl * 0.5)
	local prev = torso
	for k = 1, neckPlan.segs do
		local frac = (k - 1) / math.max(1, neckPlan.segs - 1)
		local ang = neckPlan.rise * (1.35 - 0.7 * frac) + body.pitch
		local dir = Vector3.new(0, math.sin(ang), -math.cos(ang))
		local q = p + dir * segLen * s
		local thick = neckPlan.thick * (1 - 0.22 * frac) * s
		local seg = limb(p - dir * 0.35 * s, q + dir * 0.25 * s, thick, colors.primary)
		seg.Name = "Neck" .. k
		motor("Neck" .. k, prev, seg, CFrame.new(p))
		group(seg, function()
			-- throat plate
			local mid = (p + q) / 2
			if lite then
				return
			end
			limb(mid - dir * segLen * 0.35 * s + V(0, -0.3, 0), mid + dir * segLen * 0.35 * s + V(0, -0.3, 0), thick * 0.62, colors.belly, nil, 0.8)
			local top = mid + Vector3.new(0, thick * 0.45, 0)
			if plan.back == "blades" or plan.back == "quills" then
				triangle(top - dir * 0.4 * s, top + dir * 0.4 * s, top + V(0, 0.6, 0.3), colors.accent, nil, nil, 0.12)
			elseif plan.back == "fins" then
				triangle(top - dir * 0.6 * s, top + dir * 0.5 * s, top + V(0, 1.0, 0.7), colors.secondary, nil, nil, 0.1)
			elseif plan.back == "crystals" then
				limb(top, top + V(0, 0.9, 0.35), 0.32 * s, colors.accent, Enum.Material.Ice)
			elseif plan.back == "shell" then
				ellipsoid(V(1.3, 0.6, segLen * 0.6), CFrame.lookAt(top, top + dir), colors.secondary, Enum.Material.Slate)
			elseif plan.back == "sail" then
				triangle(top - dir * 0.6 * s, top + dir * 0.5 * s, top + V(0, 0.8, 0.6), colors.wing, Enum.Material.Glass, 0.35, 0.08)
				limb(top + dir * 0.5 * s, top + V(0, 0.8, 0.6), 0.12 * s, colors.accent, Enum.Material.Neon)
			elseif plan.back == "plates" then
				ellipsoid(V(1.15, 0.45, segLen * 0.6), CFrame.lookAt(top, top + dir), colors.wing, Enum.Material.Metal)
			end
		end)
		if plan.frill and k == 1 then
			-- Folding neck frill: built open, the Frill motor folds it back until the dragon breathes.
			local frillBase = (p + q) / 2 + V(0, 0.1, 0)
			local frillRoot = jointPart("FrillRoot", frillBase)
			group(frillRoot, function()
				local spines = 7
				local tips = {}
				for i = 0, spines - 1 do
					local a = -1.25 + 2.5 * i / (spines - 1)
					local tip = frillBase + V(math.sin(a) * 3.0, math.cos(a) * 2.6 + 0.2, 0.35)
					tips[i + 1] = tip
					limb(frillBase, tip, 0.22 * s, colors.horn)
					ellipsoid(V(0.34, 0.34, 0.34), CFrame.new(tip), colors.accent, Enum.Material.Neon)
				end
				for i = 1, spines - 1 do
					triangle(frillBase, tips[i], tips[i + 1], i % 2 == 0 and colors.belly or colors.accent:Lerp(colors.belly, 0.5), nil, nil, 0.1)
				end
			end)
			motor("Frill", seg, frillRoot, CFrame.new(frillBase))
		end
		prev = seg
		p = q
	end
	local headJoint = p

	---------------------------------------------------------------- head
	local hp = plan.head
	local style = hp.style
	local H = headJoint + V(0, 0.2, -hp.l * 0.28)
	local head = ellipsoid(V(hp.w, hp.h, hp.l), CFrame.new(H), colors.primary)
	head.Name = "Head"
	motor("Head", prev, head, CFrame.new(headJoint))

	local eyeScale = style == "feline" and 1.2 or (style == "brute" and 0.85 or 1)
	local eyePos = {}
	group(head, function()
		local snoutLen = style == "feline" and 0.7 or (style == "crested" and 1.0 or (style == "regal" and 0.95 or 0.85))
		ellipsoid(V(hp.w * 0.72, hp.h * 0.56, hp.l * snoutLen), CFrame.new(H + V(0, -hp.h * 0.13, -hp.l * (0.3 + snoutLen * 0.35))), colors.primary)
		ellipsoid(V(hp.w * 0.42, hp.h * 0.22, hp.l * snoutLen * 0.72), CFrame.new(H + V(0, hp.h * 0.1, -hp.l * (0.3 + snoutLen * 0.35))), colors.secondary)
		local noseZ = -hp.l * (0.3 + snoutLen * 0.82)
		for _, side in ipairs({ -1, 1 }) do
			local e = H + V(side * hp.w * 0.4, hp.h * 0.12, -hp.l * 0.2)
			eyePos[side] = e
			local eye = ellipsoid(V(0.52, 0.48, 0.6) * eyeScale, CFrame.new(e), colors.eyes, Enum.Material.Neon)
			eye.Name = "Eye"
			ellipsoid(V(0.12, 0.4, 0.14) * eyeScale, CFrame.new(e + V(side * 0.24 * eyeScale, 0, -0.06)), DARK)
			ellipsoid(V(hp.w * 0.36, hp.h * 0.2, hp.l * 0.42), CFrame.new(H + V(side * hp.w * 0.3, hp.h * 0.33, -hp.l * 0.17)), colors.secondary)
			ellipsoid(V(0.24, 0.16, 0.22), CFrame.new(H + V(side * hp.w * 0.15, -hp.h * 0.02, noseZ)), DARK)
			-- upper teeth
			for i = 1, lite and 0 or 3 do
				local tz = noseZ + hp.l * 0.12 + i * hp.l * 0.12
				local tx = side * hp.w * (0.24 - i * 0.015)
				limb(H + V(tx, -hp.h * 0.33, tz), H + V(tx, -hp.h * 0.33 - 0.38, tz - 0.05), 0.16 * s, IVORY)
			end
		end

		-- Where breath and shots come out: inside the mouth, between the upper teeth and the open
		-- jaw (it drops about a sixth of the head's length here), not out at the nose tip, where
		-- fire used to look like it came out of the nostrils.
		local mouth = Instance.new("Attachment")
		mouth.Name = "Mouth"
		mouth.CFrame = head.CFrame:Inverse() * CFrame.new(H + V(0, -hp.h * 0.3 - hp.l * 0.15, noseZ + hp.l * 0.3))
		mouth.Parent = head

		-- Horns, crests and frills by style
		local hornMat = isFrost and Enum.Material.Ice or nil
		for _, side in ipairs({ -1, 1 }) do
			local function Hp(x, y, z)
				return H + V(x * side, y, z)
			end
			if style == "feline" then
				-- long swept blades plus small ear fins
				limb(Hp(hp.w * 0.28, hp.h * 0.42, hp.l * 0.05), Hp(hp.w * 0.46, hp.h * 0.7, hp.l * 0.62), 0.42 * s, colors.horn)
				limb(Hp(hp.w * 0.46, hp.h * 0.7, hp.l * 0.62), Hp(hp.w * 0.5, hp.h * 0.85, hp.l * 1.25), 0.24 * s, colors.horn)
				triangle(Hp(hp.w * 0.45, hp.h * 0.1, hp.l * 0.2), Hp(hp.w * 0.46, hp.h * 0.35, hp.l * 0.45), Hp(hp.w * 0.95, hp.h * 0.55, hp.l * 0.75), colors.wing, nil, nil, 0.1)
			elseif style == "crested" then
				limb(Hp(hp.w * 0.22, hp.h * 0.4, -hp.l * 0.05), Hp(hp.w * 0.3, hp.h * 0.8, hp.l * 0.35), 0.24 * s, colors.horn)
				triangle(Hp(hp.w * 0.46, -hp.h * 0.05, hp.l * 0.05), Hp(hp.w * 0.46, hp.h * 0.25, hp.l * 0.35), Hp(hp.w * 1.1, hp.h * 0.2, hp.l * 0.65), colors.secondary, nil, nil, 0.1)
			elseif style == "brute" then
				limb(Hp(hp.w * 0.33, hp.h * 0.4, hp.l * 0.05), Hp(hp.w * 0.66, hp.h * 0.62, hp.l * 0.3), 0.85 * s, colors.horn)
				limb(Hp(hp.w * 0.66, hp.h * 0.62, hp.l * 0.3), Hp(hp.w * 0.8, hp.h * 0.2, hp.l * 0.6), 0.7 * s, colors.horn)
				limb(Hp(hp.w * 0.8, hp.h * 0.2, hp.l * 0.6), Hp(hp.w * 0.72, -hp.h * 0.25, hp.l * 0.4), 0.5 * s, colors.horn)
				limb(Hp(hp.w * 0.2, hp.h * 0.42, -hp.l * 0.1), Hp(hp.w * 0.24, hp.h * 0.62, -hp.l * 0.05), 0.3 * s, colors.horn)
			elseif style == "wyrm" then
				limb(Hp(hp.w * 0.25, hp.h * 0.42, hp.l * 0.05), Hp(hp.w * 0.34, hp.h * 0.62, hp.l * 0.85), 0.36 * s, colors.horn, hornMat)
				limb(Hp(hp.w * 0.34, hp.h * 0.62, hp.l * 0.85), Hp(hp.w * 0.36, hp.h * 0.7, hp.l * 1.4), 0.2 * s, colors.accent, hornMat)
				triangle(Hp(hp.w * 0.46, -hp.h * 0.1, 0), Hp(hp.w * 0.46, -hp.h * 0.2, hp.l * 0.4), Hp(hp.w * 1.05, -hp.h * 0.35, hp.l * 0.55), colors.accent, isFrost and Enum.Material.Glass or nil, isFrost and 0.25 or nil, 0.1)
				triangle(Hp(hp.w * 0.46, hp.h * 0.05, hp.l * 0.1), Hp(hp.w * 0.46, -hp.h * 0.1, hp.l * 0.45), Hp(hp.w * 0.95, hp.h * 0.2, hp.l * 0.6), colors.accent, isFrost and Enum.Material.Glass or nil, isFrost and 0.25 or nil, 0.1)
			elseif style == "flat" then
				limb(Hp(hp.w * 0.3, hp.h * 0.42, hp.l * 0.12), Hp(hp.w * 0.38, hp.h * 0.62, hp.l * 0.38), 0.34 * s, colors.horn)
				for i = 0, 2 do
					limb(Hp(hp.w * 0.46, -hp.h * 0.1 + i * 0.25, hp.l * (0.05 + i * 0.1)), Hp(hp.w * 0.75, -hp.h * 0.1 + i * 0.3, hp.l * (0.2 + i * 0.12)), 0.16 * s, colors.accent)
				end
			elseif style == "sea" then
				-- smooth pearl horns, a see-through fin for an ear, feathery gill stalks and whiskers
				limb(Hp(hp.w * 0.24, hp.h * 0.42, hp.l * 0.05), Hp(hp.w * 0.3, hp.h * 0.58, hp.l * 0.75), 0.28 * s, colors.horn)
				triangle(Hp(hp.w * 0.46, hp.h * 0.05, 0), Hp(hp.w * 0.46, hp.h * 0.3, hp.l * 0.42), Hp(hp.w * 1.05, hp.h * 0.55, hp.l * 0.6), colors.wing, Enum.Material.Glass, 0.3, 0.1)
				for g = 0, 2 do
					local base = Hp(hp.w * 0.4, -hp.h * 0.18 + g * 0.1, hp.l * (0.22 + g * 0.1))
					local tip = Hp(hp.w * (0.85 + g * 0.1), (g - 1) * 0.5, hp.l * (0.5 + g * 0.12))
					limb(base, tip, 0.17 * s, colors.accent, Enum.Material.Neon)
					for f = 1, 3 do
						local m = base:Lerp(tip, f / 3.4)
						limb(m, m + (tip - base).Unit * 0.35 * s + V(0, 0.32, 0.12), 0.11 * s, colors.wing)
						limb(m, m + (tip - base).Unit * 0.35 * s + V(0, -0.32, 0.12), 0.11 * s, colors.wing)
					end
				end
				local w0 = Hp(hp.w * 0.3, -hp.h * 0.12, noseZ + hp.l * 0.22)
				local w1 = Hp(hp.w * 0.62, -hp.h * 0.42, noseZ + hp.l * 0.6)
				limb(w0, w1, 0.1 * s, colors.horn)
				limb(w1, w1 + V(side * 0.15, -0.75, 0.55), 0.08 * s, colors.horn)
			elseif style == "regal" then
				-- a crown: three swept horns a side (the middle one longest), gilded at the tips
				for i, h in ipairs({ { 0.16, 0.5, 1.3 }, { 0.3, 0.38, 1.0 }, { 0.42, 0.2, 0.7 } }) do
					local base = Hp(hp.w * h[1], hp.h * 0.42, hp.l * (i * 0.06))
					local mid = Hp(hp.w * (h[1] + 0.08), hp.h * (0.48 + h[2]), hp.l * (0.3 + h[3] * 0.3))
					local tip = Hp(hp.w * (h[1] + 0.12), hp.h * (0.56 + h[2] * 1.3), hp.l * (0.3 + h[3] * 0.75))
					limb(base, mid, (0.36 - i * 0.05) * s, colors.horn)
					limb(mid, tip, (0.24 - i * 0.03) * s, colors.wing, Enum.Material.Metal)
				end
				triangle(Hp(hp.w * 0.45, -hp.h * 0.05, hp.l * 0.05), Hp(hp.w * 0.45, -hp.h * 0.25, hp.l * 0.4), Hp(hp.w * 0.95, -hp.h * 0.15, hp.l * 0.5), colors.wing, Enum.Material.Metal, nil, 0.1)
			end
		end
		if style == "crested" then
			-- tall fin crest along the top of the head
			for i = 0, 2 do
				local base = H + V(0, hp.h * 0.42, -hp.l * 0.2 + i * hp.l * 0.22)
				triangle(base + V(0, 0, -0.35), base + V(0, 0, 0.45), base + V(0, 1.3 - i * 0.2, 0.9), colors.accent, nil, nil, 0.1)
			end
		elseif style == "brute" then
			limb(H + V(0, hp.h * 0.15, -hp.l * 0.85), H + V(0, hp.h * 0.55, -hp.l * 0.95), 0.5 * s, colors.horn)
		elseif style == "sea" then
			-- a glowing pearl set in the brow
			ellipsoid(V(0.75, 0.3, 0.75), CFrame.new(H + V(0, hp.h * 0.44, -hp.l * 0.22)), colors.eyes, Enum.Material.Metal)
			ellipsoid(V(0.55, 0.55, 0.55), CFrame.new(H + V(0, hp.h * 0.56, -hp.l * 0.22)), colors.belly:Lerp(colors.accent, 0.3), Enum.Material.Neon)
		elseif style == "regal" then
			-- a sun-gem on the brow
			ellipsoid(V(0.5, 0.62, 0.36), CFrame.new(H + V(0, hp.h * 0.38, -hp.l * 0.4)) * CFrame.Angles(0.5, 0, 0), fire.colorA, Enum.Material.Neon)
		end
		if plan.halo then
			-- a blazing sunburst behind the crown: a glowing disc ringed with gold and long and short rays
			local hc = H + V(0, hp.h * 0.62, hp.l * 0.72)
			local R = 1.9
			local face = CFrame.new(hc) * CFrame.Angles(0, math.rad(90), 0)
			local sunDisc = makePart("Part", Vector3.new(0.1 * s, R * 2 * s, R * 2 * s), face, colors.accent:Lerp(fire.colorA, 0.45), Enum.Material.Neon)
			sunDisc.Shape = Enum.PartType.Cylinder
			sunDisc.Transparency = tint and 0 or 0.25
			sunDisc.Name = "Halo"
			local core = makePart("Part", Vector3.new(0.14 * s, R * 1.1 * s, R * 1.1 * s), face * CFrame.new(0.04 * s, 0, 0), fire.colorA, Enum.Material.Neon)
			core.Shape = Enum.PartType.Cylinder
			for k = 1, 20 do
				local a0, a1 = (k - 1) / 20 * math.pi * 2, k / 20 * math.pi * 2
				limb(hc + V(math.cos(a0) * R, math.sin(a0) * R, 0), hc + V(math.cos(a1) * R, math.sin(a1) * R, 0), 0.36 * s, colors.secondary, Enum.Material.Metal)
			end
			for k = 1, 16 do
				local a = (k - 0.5) / 16 * math.pi * 2
				local len = k % 2 == 0 and 1.6 or 0.85
				local function at(ang: number, r: number)
					return hc + V(math.cos(ang) * r, math.sin(ang) * r, 0.05)
				end
				triangle(at(a - 0.11, R + 0.1), at(a + 0.11, R + 0.1), at(a, R + len), k % 2 == 0 and fire.colorA or colors.accent, Enum.Material.Neon, nil, 0.1)
			end
			if not tint then
				local glow = Instance.new("PointLight")
				glow.Name = "HaloLight"
				glow.Color = fire.colorA
				glow.Range = 12 * s
				glow.Brightness = 1.5
				glow.Parent = sunDisc
			end
		end
	end)

	-- Eyelids rest tucked under the brow; the client slides them down to blink.
	for _, side in ipairs({ -1, 1 }) do
		local e = eyePos[side]
		local lidPos = e + V(0, 0.3 * eyeScale, 0.02)
		local lid = ellipsoid(V(0.6, 0.3, 0.68) * eyeScale, CFrame.new(lidPos), colors.primary)
		lid.Name = side > 0 and "LidR" or "LidL"
		motor(side > 0 and "LidR" or "LidL", head, lid, CFrame.new(lidPos))
	end

	-- Hinged jaw
	local hinge = H + V(0, -hp.h * 0.3, hp.l * 0.12)
	local jawLen = hp.l * (style == "crested" and 1.2 or 1.02)
	local jaw = ellipsoid(V(hp.w * 0.62, hp.h * 0.3, jawLen), CFrame.new(hinge + V(0, -hp.h * 0.06, -jawLen * 0.5)), colors.belly)
	jaw.Name = "Jaw"
	motor("Jaw", head, jaw, CFrame.new(hinge))
	group(jaw, function()
		for _, side in ipairs({ -1, 1 }) do
			for i = 1, lite and 0 or 2 do
				local tz = -jawLen * (0.55 + i * 0.13)
				local tx = side * hp.w * 0.2
				limb(hinge + V(tx, 0.02, tz), hinge + V(tx, 0.34, tz - 0.05), 0.14 * s, IVORY)
			end
			if style == "brute" then
				limb(hinge + V(side * hp.w * 0.28, 0, -jawLen * 0.7), hinge + V(side * hp.w * 0.34, 0.95, -jawLen * 0.85), 0.34 * s, IVORY)
			end
		end
		if style == "wyrm" then
			for i = -1, 1 do
				limb(hinge + V(i * 0.3, -hp.h * 0.12, -jawLen * 0.55), hinge + V(i * 0.35, -hp.h * 0.12 - 0.9 + math.abs(i) * 0.25, -jawLen * 0.5), 0.2 * s, colors.accent, Enum.Material.Ice)
			end
		end
	end)

	---------------------------------------------------------------- wings (two-part: arm + hand)
	local wp = plan.wings
	local ws = wp.span
	local wingMat = (wp.glass or wp.fins) and Enum.Material.Glass or nil
	local wingTrans = wp.glass and 0.3 or (wp.fins and 0.35 or nil)
	-- (sea dragons' fins hang on glowing ribs)
	local ribColor = wp.fins and colors.accent or colors.secondary
	local ribMat = wp.fins and Enum.Material.Neon or nil
	for _, side in ipairs({ -1, 1 }) do
		local S = B(side * bw * 0.42, bh * 0.36, -bl * 0.2)
		local function W(x, y, z)
			return V(x * side * ws, y * ws, z * ws)
		end
		local E = S + W(3.6, 1.0, -0.5)
		local Wr = E + W(3.5, 0.45, 0.9)
		local tips
		if wp.fingers >= 4 then
			tips = { Wr + W(3.6, -0.3, 1.2), Wr + W(2.9, -0.7, 2.9), Wr + W(1.6, -1.0, 4.3), Wr + W(0.1, -1.2, 5.1) }
		else
			tips = { Wr + W(3.4, -0.4, 1.6), Wr + W(2.0, -0.9, 3.9), Wr + W(0.2, -1.1, 4.9) }
		end
		local trail = E + W(0.2, -1.0, 4.3)
		local bodyEdge = S + W(-0.25, -0.5, 4.3)
		local pull = wp.tattered and 0.38 or (wp.fins and 0.3 or 0.22)

		local armRoot = jointPart(side > 0 and "WingRootR" or "WingRootL", S)
		group(armRoot, function()
			limb(S, E, 0.6 * s, colors.secondary)
			triangle(S, E, bodyEdge, colors.wing, wingMat, wingTrans)
			local scallop = trail:Lerp(bodyEdge, 0.5):Lerp(S, pull * 0.6)
			triangle(E, trail, scallop, colors.wing, wingMat, wingTrans)
			triangle(E, scallop, bodyEdge, colors.wing, wingMat, wingTrans)
			if wp.armored then
				ellipsoid(V(2.4, 0.9, 1.5), lookAt((S + E) / 2 + V(0, 0.35, 0), E + V(0, 0.35, 0)), colors.secondary, Enum.Material.Slate)
			end
			if wp.feathers then
				-- secondary feathers hanging back from the arm, laid over the membrane
				for k = 1, 4 do
					local base = S:Lerp(E, 0.12 + k * 0.2)
					local out = base + W(0.25, -0.6, 3.9 - k * 0.15)
					limb(base, out, 0.95 * s, k % 2 == 0 and colors.primary or colors.wing, nil, 0.16)
					limb(base:Lerp(out, 0.8), out, 0.6 * s, fire.colorA, Enum.Material.Neon, 0.18)
				end
			end
		end)
		motor(side > 0 and "WingR" or "WingL", torso, armRoot, CFrame.new(S))

		local handRoot = jointPart(side > 0 and "WingHandR" or "WingHandL", E)
		group(handRoot, function()
			limb(E, Wr, 0.48 * s, colors.secondary)
			limb(Wr, Wr + W(0.2, 0.6, -0.9), 0.3 * s, colors.horn)
			for i, tip in ipairs(tips) do
				limb(Wr, tip, (0.32 - i * 0.03) * s, ribColor, ribMat)
			end
			if wp.feathers then
				-- long flight feathers fanned over the hand, tipped with sunfire
				local fan = {}
				for i = 1, #tips - 1 do
					table.insert(fan, tips[i])
					table.insert(fan, tips[i]:Lerp(tips[i + 1], 0.5))
				end
				table.insert(fan, tips[#tips])
				for i, tip in ipairs(fan) do
					local out = Wr + (tip - Wr) * 1.2
					limb(Wr:Lerp(tip, 0.2), out, 0.9 * s, i % 2 == 0 and colors.primary or colors.wing, nil, 0.16)
					limb(Wr:Lerp(out, 0.78), out, 0.62 * s, colors.accent, Enum.Material.Neon, 0.18)
				end
			end
			for i = 1, #tips - 1 do
				local mid = tips[i]:Lerp(tips[i + 1], 0.5):Lerp(Wr, pull)
				triangle(Wr, tips[i], mid, colors.wing, wingMat, wingTrans)
				triangle(Wr, mid, tips[i + 1], colors.wing, wingMat, wingTrans)
			end
			local last = tips[#tips]
			local mid = last:Lerp(trail, 0.5):Lerp(E, pull)
			triangle(E, Wr, last, colors.wing, wingMat, wingTrans)
			triangle(E, last, mid, colors.wing, wingMat, wingTrans)
			triangle(E, mid, trail, colors.wing, wingMat, wingTrans)
		end)
		motor(side > 0 and "WingR2" or "WingL2", armRoot, handRoot, CFrame.new(E))
	end

	---------------------------------------------------------------- legs (hip + knee)
	local lp = plan.legs
	local legDefs = {}
	if lp.count == 4 then
		table.insert(legDefs, { key = "FL", side = -1, front = true })
		table.insert(legDefs, { key = "FR", side = 1, front = true })
	end
	table.insert(legDefs, { key = "BL", side = -1, front = false })
	table.insert(legDefs, { key = "BR", side = 1, front = false })
	for _, leg in ipairs(legDefs) do
		local side = leg.side
		local hip
		if leg.front then
			hip = B(side * bw * 0.34 * lp.splay, -bh * 0.18, -bl * 0.31)
		elseif lp.count == 2 then
			hip = B(side * bw * 0.4 * lp.splay, -bh * 0.1, bl * 0.12)
		else
			hip = B(side * bw * 0.37 * lp.splay, -bh * 0.12, bl * 0.3)
		end
		local thick = lp.thick * s * (leg.front and 1 or 1.15)
		local drop = hip.Y - groundY
		local knee, ankle, toe
		if leg.front then
			knee = Vector3.new(hip.X + 0.15 * side * s * lp.splay, hip.Y - drop * 0.48, hip.Z + 0.45 * s)
			ankle = Vector3.new(hip.X + 0.25 * side * s * lp.splay, groundY + 0.55 * s, hip.Z - 0.2 * s)
			toe = ankle + V(0.05 * side, -0.25, -1.2)
		else
			knee = Vector3.new(hip.X + 0.22 * side * s * lp.splay, hip.Y - drop * 0.4, hip.Z - 0.95 * s)
			ankle = Vector3.new(hip.X + 0.28 * side * s * lp.splay, groundY + 1.25 * s, hip.Z + 0.55 * s)
			toe = Vector3.new(ankle.X, groundY + 0.3 * s, ankle.Z - 1.5 * s)
		end
		local upper = limb(hip, knee, thick, colors.primary)
		upper.Name = "Leg" .. leg.key
		group(upper, function()
			if not leg.front then
				ellipsoid(Vector3.new(thick * 1.25, thick * 1.5, thick * 1.7), CFrame.new(hip:Lerp(knee, 0.3)), colors.primary)
			end
		end)
		motor("Leg" .. leg.key, torso, upper, CFrame.new(hip))

		local lower = limb(knee, ankle, thick * 0.7, colors.primary)
		lower.Name = "Shin" .. leg.key
		group(lower, function()
			if not leg.front then
				limb(ankle, toe, thick * 0.55, colors.primary)
			end
			ellipsoid(Vector3.new(thick * 0.95, thick * 0.45, thick * 1.2), CFrame.new(toe:Lerp(ankle, 0.35) + V(0, -0.1, 0)), colors.secondary)
			for _, dx in ipairs(lite and {} or { -0.32, 0, 0.32 }) do
				local base = toe + V(dx * lp.thick, -0.05, 0)
				limb(base, base + V(dx * 0.4, -0.2, -0.55), 0.2 * s, colors.horn)
			end
			if lp.webbed then
				ellipsoid(Vector3.new(thick * 1.35, 0.12 * s, thick * 0.9), CFrame.new(toe + V(0, -0.12, -0.3)), colors.wing, Enum.Material.Glass)
			end
			if lp.greaves then
				ellipsoid(Vector3.new(thick * 0.92, thick * 0.92, (ankle - knee).Magnitude * 0.5), lookAt(knee:Lerp(ankle, 0.5), ankle), colors.wing, Enum.Material.Metal)
			end
		end)
		motor("Knee" .. leg.key, upper, lower, CFrame.new(knee))
	end

	---------------------------------------------------------------- tail
	local tp = plan.tail
	local tailSeg = tp.len / tp.segs
	local q0 = B(0, bh * 0.05, bl * 0.5)
	prev = torso
	local lastSeg
	local tailEnd
	for k = 1, tp.segs do
		local frac = (k - 1) / tp.segs
		local droop = tp.droop * (1 - frac * 0.6) + body.pitch * 0.5 * (1 - frac)
		local dir = Vector3.new(0, -math.sin(droop), math.cos(droop))
		local q1 = q0 + dir * tailSeg * s
		local thick = tp.thick * (1 - 0.7 * frac) * s
		local seg = limb(q0 - dir * 0.35 * s, q1 + dir * 0.3 * s, thick, colors.primary)
		seg.Name = "Tail" .. k
		motor("Tail" .. k, prev, seg, CFrame.new(q0))
		group(seg, function()
			local mid = (q0 + q1) / 2
			local top = mid + Vector3.new(0, thick * 0.42, 0)
			local h = math.max(0.3, (1 - frac) * 0.9)
			if plan.back == "blades" or plan.back == "fins" then
				triangle(top - dir * 0.45 * s, top + dir * 0.45 * s, top + V(0, h, 0.4), plan.back == "fins" and colors.secondary or colors.accent, nil, nil, 0.1)
			elseif plan.back == "crystals" then
				limb(top, top + V(0, h * 1.2, 0.3), 0.3 * s * (1 - frac * 0.5), colors.accent, Enum.Material.Ice)
			elseif plan.back == "quills" then
				limb(top, top + V(0, h, 0.7), 0.16 * s, colors.horn)
			elseif plan.back == "shell" then
				ellipsoid(Vector3.new(thick * 0.8, thick * 0.35, tailSeg * s * 0.7), CFrame.lookAt(top, top + dir), colors.secondary, Enum.Material.Slate)
			elseif plan.back == "sail" then
				triangle(top - dir * 0.5 * s, top + dir * 0.5 * s, top + V(0, h * 0.9, 0.5), colors.wing, Enum.Material.Glass, 0.35, 0.08)
			elseif plan.back == "plates" then
				ellipsoid(Vector3.new(thick * 0.85, thick * 0.32, tailSeg * s * 0.62), CFrame.lookAt(top, top + dir), colors.wing, Enum.Material.Metal)
			end
			if plan.marks == "waves" and not lite then
				-- glowing dots down the sides, like a deep-sea fish
				for _, side in ipairs({ -1, 1 }) do
					ellipsoid(Vector3.new(thick * 0.18, thick * 0.18, thick * 0.18), CFrame.new(mid + Vector3.new(side * thick * 0.46, -thick * 0.08, 0)), colors.accent, Enum.Material.Neon)
				end
			end
			if k % 2 == 1 and plan.marks ~= "lava" and not lite then
				ellipsoid(Vector3.new(thick * 0.72, thick * 0.2, tailSeg * s * 0.3), CFrame.lookAt(mid + Vector3.new(0, -thick * 0.42, 0), mid + Vector3.new(0, -thick * 0.42, 0) + dir), colors.belly)
			end
		end)
		prev = seg
		lastSeg = seg
		tailEnd = q1
		q0 = q1
	end

	group(lastSeg, function()
		local t = tailEnd
		local tip = tp.tip
		if tip == "fan" then
			for _, a in ipairs({ -0.55, 0, 0.55 }) do
				local d = V(math.sin(a) * 1.6, 0.5, math.cos(a) * 2.2)
				triangle(t, t + d + V(0, 0.35, 0), t + d * 0.55 + V(0, -0.4, 0), colors.accent, Enum.Material.Neon, nil, 0.12)
			end
		elseif tip == "kite" then
			triangle(t + V(0, 0, -0.4), t + V(0, 1.7, 1.5), t + V(0, 0, 2.3), colors.secondary)
			triangle(t + V(0, 0, -0.4), t + V(0, -1.3, 1.3), t + V(0, 0, 2.3), colors.accent)
			triangle(t + V(-1.4, 0, 1.7), t + V(1.4, 0, 1.7), t + V(0, 0, -0.4), colors.secondary)
		elseif tip == "club" then
			local c = t + V(0, 0, 0.8)
			ellipsoid(V(2.2, 2.0, 2.4), CFrame.new(c), colors.horn, Enum.Material.Slate)
			for _, d in ipairs({ Vector3.new(1, 0.3, 0), Vector3.new(-1, 0.3, 0), Vector3.new(0, 1, 0.2), Vector3.new(0.6, -0.5, 0.6), Vector3.new(-0.6, -0.5, 0.6), Vector3.new(0, 0.3, 1) }) do
				limb(c + d * s * 0.8, c + d * s * 1.9, 0.5 * s, colors.horn)
			end
			ellipsoid(V(2.3, 0.3, 1.4), CFrame.new(c + V(0, 0.2, 0)), colors.accent, Enum.Material.Neon)
		elseif tip == "crystal" then
			limb(t, t + V(0, 0.4, 2.6), 0.9 * s, colors.accent, Enum.Material.Ice)
			limb(t + V(0, 0, 0.3), t + V(0.9, 0.8, 1.5), 0.5 * s, colors.horn, Enum.Material.Ice)
			limb(t + V(0, 0, 0.3), t + V(-0.9, 0.8, 1.5), 0.5 * s, colors.horn, Enum.Material.Ice)
		elseif tip == "stinger" then
			ellipsoid(V(1.2, 1.1, 1.5), CFrame.new(t + V(0, 0, 0.4)), colors.secondary)
			limb(t + V(0, 0.2, 0.7), t + V(0, 1.1, 1.9), 0.55 * s, colors.horn)
			ellipsoid(V(0.5, 0.5, 0.5), CFrame.new(t + V(0, 1.25, 2.1)), colors.accent, Enum.Material.Neon)
		elseif tip == "fluke" then
			-- a whale's fluke: two crescent lobes of see-through fin with glowing leading edges
			ellipsoid(V(1.1, 0.8, 1.5), CFrame.new(t + V(0, 0, 0.3)), colors.primary)
			for _, side in ipairs({ -1, 1 }) do
				local outer = t + V(side * 3.7, 0.2, 2.5)
				local inner = t + V(side * 0.9, 0, 2.7)
				triangle(t + V(0, 0, -0.2), outer, inner, colors.wing, Enum.Material.Glass, 0.25, 0.14)
				triangle(t + V(0, 0, -0.2), t + V(side * 1.7, 0.1, 0.7), outer, colors.wing, Enum.Material.Glass, 0.25, 0.14)
				limb(t + V(side * 0.4, 0, 0), t + V(side * 1.7, 0.1, 0.7), 0.24 * s, colors.accent, Enum.Material.Neon)
				limb(t + V(side * 1.7, 0.1, 0.7), outer, 0.18 * s, colors.accent, Enum.Material.Neon)
			end
		elseif tip == "plume" then
			-- phoenix plumes: five long feathers fanning out, glowing toward eye-spot tips
			for i, a in ipairs({ -0.62, -0.31, 0, 0.31, 0.62 }) do
				local len = 6.6 - math.abs(a) * 2.2
				local tipPos = t + V(math.sin(a) * len * 0.75, 0.4 + (i % 2) * 0.35, math.cos(a) * len)
				limb(t, tipPos, 1.0 * s, i % 2 == 0 and colors.primary or colors.wing, nil, 0.22)
				limb(t:Lerp(tipPos, 0.5), tipPos, 0.75 * s, colors.accent, Enum.Material.Neon, 0.25)
				ellipsoid(V(0.75, 0.35, 0.95), CFrame.new(tipPos), fire.colorA, Enum.Material.Neon)
			end
		end
	end)

	---------------------------------------------------------------- lights & particles
	if not options.noParticles and not tint then
		local light = Instance.new("PointLight")
		light.Color = colors.eyes
		light.Range = 8 * s
		light.Brightness = 0.6
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
		emitter.Color = ColorSequence.new(fire.colorA, fire.colorB)
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Size = NumberSequence.new(0.3 * s, 0)
		if class.id == "Shadowstalker" then
			emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
			emitter.Size = NumberSequence.new(1.5 * s, 3.5 * s)
		elseif class.id == "Venomspine" then
			emitter.Acceleration = Vector3.new(0, -8, 0)
			emitter.Size = NumberSequence.new(0.35 * s)
		elseif class.id == "Frostwyrm" then
			emitter.Acceleration = Vector3.new(0, -2, 0)
			emitter.Rate = 6
		elseif class.id == "Behemoth" then
			emitter.Acceleration = Vector3.new(0, 4, 0)
			emitter.Size = NumberSequence.new(0.35 * s, 0)
		elseif class.id == "Tidecaller" then
			-- bubbles drifting up off its scales
			emitter.Acceleration = Vector3.new(0, 3, 0)
			emitter.Rate = 7
			emitter.Size = NumberSequence.new(0.25 * s, 0.45 * s)
		elseif class.id == "Solaris" then
			-- golden motes rising like heat
			emitter.LightEmission = 1
			emitter.Acceleration = Vector3.new(0, 2.5, 0)
			emitter.Rate = 12
			emitter.Size = NumberSequence.new(0.4 * s, 0)
		end
		emitter.Parent = torso
	end

	model:SetAttribute("DragonClass", class.id)
	model:SetAttribute("HipHeight", hipHeight)
	model:SetAttribute("DragonScale", s)
	model:SetAttribute("RigNeck", plan.neck.segs)
	model:SetAttribute("RigTail", plan.tail.segs)
	model:SetAttribute("RigLegs", plan.legs.count)
	model:SetAttribute("RigCurl", plan.tail.curl == true)
	model:SetAttribute("RigFrill", plan.frill == true)
	return model, hipHeight
end

return DragonBuilder
