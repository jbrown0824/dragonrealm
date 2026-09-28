-- Builds four-legged animals out of parts (deer, goats, boars, wolves, bears). Same idea as
-- VikingBuilder: a HumanoidRootPart, a body, and legs/head/tail on Motor6Ds (LegFL/FR/BL/BR,
-- Head, Tail) that the client Animator swings. Models face -Z.

local AnimalBuilder = {}

local IVORY = Color3.fromRGB(235, 225, 200)
local HORN = Color3.fromRGB(120, 95, 70)

-- look: see Config/Animals. Returns model, hipHeight.
function AnimalBuilder.build(look, scale: number, name: string)
	local s = scale
	local model = Instance.new("Model")
	model.Name = name

	local function V(x, y, z)
		return Vector3.new(x * s, y * s, z * s)
	end

	local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, sphere: boolean?)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if sphere ~= false then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		p.Parent = model
		return p
	end

	local function limb(a: Vector3, b: Vector3, thick: number, color: Color3, material: Enum.Material?)
		local up = Vector3.yAxis
		if math.abs((b - a).Unit:Dot(up)) > 0.98 then
			up = Vector3.zAxis
		end
		return part(Vector3.new(thick, thick, (b - a).Magnitude + thick * 0.3), CFrame.lookAt((a + b) / 2, b, up), color, material)
	end

	local function weld(a: BasePart, b: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = b
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

	local L, H, W = look.bodyL, look.bodyH, look.bodyW
	local legLen = look.legLen
	local bodyY = legLen + H * 0.35 -- body center height above the ground

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V(W, H * 0.8, L * 0.8)
	root.CFrame = CFrame.new(V(0, bodyY, 0))
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	local body = part(V(W, H, L), CFrame.new(V(0, bodyY, 0)), look.body)
	body.Name = "Torso"
	weld(root, body)
	-- belly and chest
	weld(body, part(V(W * 0.85, H * 0.5, L * 0.8), CFrame.new(V(0, bodyY - H * 0.28, 0)), look.belly))
	weld(body, part(V(W * 0.95, H * 0.95, L * 0.45), CFrame.new(V(0, bodyY + H * 0.05, -L * 0.3)), look.body))
	if look.hump then
		weld(body, part(V(W * 0.8, H * 0.6, L * 0.4), CFrame.new(V(0, bodyY + H * 0.42, -L * 0.22)), look.body))
	end
	if look.mane then
		for i = 0, 3 do
			weld(body, part(V(0.4, 0.7, 0.8), CFrame.new(V(0, bodyY + H * 0.5, -L * 0.35 + i * L * 0.18)), look.mane))
		end
	end

	-- Head on a neck, jointed at the front of the body.
	local neckBase = V(0, bodyY + H * 0.25, -L * 0.45)
	local rise = look.neckLen > 1.2 and 0.9 or 0.35
	local neckTop = neckBase + V(0, look.neckLen * math.sin(rise), -look.neckLen * math.cos(rise))
	local headCenter = neckTop + V(0, 0.1, -look.headL * 0.4)
	local head = part(V(W * 0.62, H * 0.55, look.headL), CFrame.new(headCenter), look.body)
	head.Name = "Head"
	local function onHead(p)
		weld(head, p)
	end
	if look.neckLen > 0.6 then
		onHead(limb(neckBase, neckTop, W * 0.5 * s, look.body))
	end
	local snoutZ = -look.headL * (look.snout and 0.75 or 0.55)
	onHead(part(V(W * 0.38, H * 0.32, look.headL * 0.6), CFrame.new(headCenter + V(0, -0.12, snoutZ * 0.8)), look.belly))
	onHead(part(V(0.32, 0.26, 0.2), CFrame.new(headCenter + V(0, -0.02, snoutZ * 0.8 - look.headL * 0.3)), look.nose))
	for _, side in ipairs({ -1, 1 }) do
		onHead(part(V(0.2, 0.2, 0.14), CFrame.new(headCenter + V(side * W * 0.24, 0.14, -look.headL * 0.3)), look.eyes or Color3.fromRGB(20, 20, 20), look.eyes and Enum.Material.Neon or nil))
		if look.ears then
			onHead(part(V(0.2, 0.55, 0.4), CFrame.new(headCenter + V(side * W * 0.3, H * 0.3, look.headL * 0.1)) * CFrame.Angles(0, 0, side * 0.6), look.body))
		elseif look.pointyEars then
			onHead(part(V(0.25, 0.75, 0.35), CFrame.new(headCenter + V(side * W * 0.2, H * 0.4, look.headL * 0.15)) * CFrame.Angles(0, 0, side * 0.2), look.body, nil, false))
		elseif look.roundEars then
			onHead(part(V(0.5, 0.5, 0.25), CFrame.new(headCenter + V(side * W * 0.25, H * 0.32, look.headL * 0.1)), look.body))
		end
		if look.antlers then
			local base = headCenter + V(side * 0.3, H * 0.3, look.headL * 0.15)
			local a1 = base + V(side * 0.6, 1.3, 0.2)
			onHead(limb(base, a1, 0.18 * s, HORN))
			onHead(limb(a1, a1 + V(side * 0.7, 0.9, -0.2), 0.14 * s, HORN))
			onHead(limb(a1, a1 + V(side * 0.1, 1.1, 0.4), 0.14 * s, HORN))
			onHead(limb(base + V(side * 0.3, 0.6, 0.1), base + V(side * 0.2, 0.9, -0.6), 0.12 * s, HORN))
		end
		if look.curledHorns then
			local base = headCenter + V(side * 0.25, H * 0.3, look.headL * 0.05)
			local a1 = base + V(side * 0.3, 0.5, 0.45)
			local a2 = a1 + V(side * 0.35, -0.4, 0.3)
			onHead(limb(base, a1, 0.28 * s, HORN))
			onHead(limb(a1, a2, 0.24 * s, HORN))
			onHead(limb(a2, a2 + V(side * 0.1, -0.35, -0.3), 0.18 * s, HORN))
		end
		if look.tusks then
			local base = headCenter + V(side * W * 0.18, -0.2, snoutZ * 0.8)
			onHead(limb(base, base + V(side * 0.25, 0.5, -0.25), 0.16 * s, IVORY))
		end
	end
	if look.beard then
		onHead(part(V(0.35, 0.6, 0.3), CFrame.new(headCenter + V(0, -H * 0.35, snoutZ * 0.6)), look.belly))
	end
	motor("Head", body, head, CFrame.new(neckBase))

	-- Legs hang from the hips; the Animator swings them at the joint.
	for _, leg in ipairs({ { "FL", -1, -1 }, { "FR", 1, -1 }, { "BL", -1, 1 }, { "BR", 1, 1 } }) do
		local key, side, fb = leg[1], leg[2], leg[3]
		local hip = V(side * W * 0.3, bodyY - H * 0.15, fb * L * 0.34)
		local foot = V(side * W * 0.32, 0.15, fb * L * 0.34)
		local p = limb(hip, foot, look.legThick * s, look.legs)
		p.Name = "Leg" .. key
		weld(p, part(V(look.legThick * 1.2, 0.3, look.legThick * 1.4), CFrame.new(foot + V(0, 0, -0.1)), look.nose))
		motor("Leg" .. key, body, p, CFrame.new(hip))
	end

	-- Tail
	local tailBase = V(0, bodyY + H * 0.2, L * 0.48)
	local tailPart
	if look.tail == "bushy" then
		tailPart = limb(tailBase, tailBase + V(0, -0.8, 1.8), 0.7 * s, look.body)
		weld(tailPart, part(V(0.55, 0.55, 0.8), CFrame.new(tailBase + V(0, -0.95, 2.1)), look.belly))
	elseif look.tail == "thin" then
		tailPart = limb(tailBase, tailBase + V(0, -0.9, 0.6), 0.2 * s, look.body)
	else
		tailPart = part(V(0.45, 0.5, 0.45), CFrame.new(tailBase + V(0, 0.05, 0.1)), look.belly)
	end
	tailPart.Name = "Tail"
	motor("Tail", body, tailPart, CFrame.new(tailBase))

	local hipHeight = bodyY * s - root.Size.Y / 2
	return model, hipHeight
end

return AnimalBuilder
