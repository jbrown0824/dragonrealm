-- Showpiece effects for the big spells, layered on top of the basic shapes in VFX:
--   * every ultimate gets a flourish (a pillar of light and a spinning rune circle)
--   * healing spells float green "+" signs up from the dragon
--   * lasting spells follow their dragon for the whole duration: the Blizzard storm, the Ice
--     Fortress shell, the Cyclone funnel (a firestorm round a whirling dungeon boss, with little
--     cyclones spiralling off it) and the Rampage flames
--   * Eclipse darkens the sky for everyone nearby and slides a black disc over the sun
--   * one-shot showpieces: Epidemic, Umbral Devour, Absolute Zero, Lightning Storm, Toxic Deluge,
--     Death Mark, and Venom Spit's glob and splat
-- All cosmetic and local to each client.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage:WaitForChild("Shared").Config.Abilities)
local Dungeons = require(ReplicatedStorage:WaitForChild("Shared").Config.Dungeons)

local SpellFX = {}
local App
local U -- VFX.util

local followers = {} -- list of { character, root, untilTime, started, step, stop, parts }
local HEAL_GREEN = Color3.fromRGB(110, 255, 120)

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function rootOf(character: Model?): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Height of the ground under a dragon (its feet), from its Humanoid.
local function feetY(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root.Position.Y - root.Size.Y / 2 - (humanoid and humanoid.HipHeight or 3)
end

---------------------------------------------------------------- followers

-- Run an effect that sticks to a dragon for `duration` seconds. step(f, dt, t, root) moves its
-- parts every frame; everything in f.parts is faded and cleaned up at the end.
local function follow(character: Model, duration: number, setup, step)
	local root = rootOf(character)
	if not root then
		return nil
	end
	local f = { character = character, root = root, untilTime = os.clock() + duration, started = os.clock(), step = step, parts = {} }
	setup(f, root)
	table.insert(followers, f)
	return f
end

local function stopFollower(f)
	for _, p in ipairs(f.parts) do
		if p:IsA("BasePart") and p.Parent then
			U.tween(p, 0.4, { Transparency = 1 })
			Debris:AddItem(p, 0.45)
		elseif p:IsA("ParticleEmitter") then
			p.Enabled = false
			Debris:AddItem(p, 2)
		elseif p.Parent then
			Debris:AddItem(p, 0.45)
		end
	end
	if f.stop then
		f.stop(f)
	end
end

local function updateFollowers(dt: number)
	local now = os.clock()
	for i = #followers, 1, -1 do
		local f = followers[i]
		if now >= f.untilTime or not f.root.Parent or not f.character.Parent then
			table.remove(followers, i)
			stopFollower(f)
		else
			local ok, err = pcall(f.step, f, dt, now - f.started, f.root)
			if not ok then
				App.VFX.errorCount += 1
				warn("[SpellFX]", err)
				table.remove(followers, i)
				stopFollower(f)
			end
		end
	end
end

---------------------------------------------------------------- shared pieces

-- Green "+" signs drifting up around a dragon (every heal).
function SpellFX.plusSigns(character: Model?, count: number?, color: Color3?)
	local root = rootOf(character)
	if not root then
		return
	end
	local scale = character:GetAttribute("DragonScale") or 1
	for i = 1, count or 8 do
		task.delay(i * 0.07, function()
			if not root.Parent then
				return
			end
			local a = math.random() * math.pi * 2
			local r = rand(1.5, 4) * scale
			local anchor = U.anchorAt(root.Position + Vector3.new(math.cos(a) * r, rand(-1, 2) * scale, math.sin(a) * r))
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(44, 44)
			gui.LightInfluence = 0
			gui.MaxDistance = 150
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.FredokaOne
			label.Text = "+"
			label.TextSize = math.random(30, 46)
			label.TextColor3 = color or HEAL_GREEN
			label.TextStrokeColor3 = Color3.fromRGB(20, 90, 30)
			label.TextStrokeTransparency = 0.2
			label.Parent = gui
			gui.Parent = anchor
			local time = rand(1.1, 1.6)
			U.tween(anchor, time, { Position = anchor.Position + Vector3.new(rand(-1, 1), rand(6, 9) * scale, rand(-1, 1)) })
			U.tween(label, time, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad)
			Debris:AddItem(anchor, time + 0.1)
		end)
	end
end

-- Every ultimate: a pillar of light and a rune circle spinning out from the caster.
function SpellFX.flourish(pos: Vector3, colorA: Color3, colorB: Color3)
	local pillar = U.part(Vector3.new(50, 5, 5), CFrame.new(pos + Vector3.new(0, 22, 0)) * CFrame.Angles(0, 0, math.rad(90)), colorA, Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
	U.tween(pillar, 0.9, { Size = Vector3.new(70, 0.4, 0.4), Transparency = 1 })
	Debris:AddItem(pillar, 1)
	local ground = pos - Vector3.new(0, 3, 0)
	U.ring(ground, 16, colorA, 0.8, 0.8)
	U.ring(ground, 10, colorB, 1, 0.5)
	local spin = math.random() * math.pi
	for k = 1, 8 do
		local a = spin + k / 8 * math.pi * 2
		local rune = U.part(Vector3.new(0.4, 1.4, 3), CFrame.new(ground + Vector3.new(math.cos(a) * 3, 0.5, math.sin(a) * 3)) * CFrame.Angles(0, -a, 0), colorA, Enum.Material.Neon, 0.1)
		local out = a + 0.9
		U.tween(rune, 0.9, { CFrame = CFrame.new(ground + Vector3.new(math.cos(out) * 15, 0.5, math.sin(out) * 15)) * CFrame.Angles(0, -out, 0), Transparency = 1 })
		Debris:AddItem(rune, 1)
	end
	U.flash(pos, colorA, 40, 0.8)
end

local function isUltimate(abilityId: string?): boolean
	local ability = abilityId and Abilities[abilityId]
	return type(ability) == "table" and ability.ultimate == true
end
SpellFX.isUltimate = isUltimate

---------------------------------------------------------------- Eclipse

local eclipse = nil -- { untilTime, cc, disc, corona, exposure }

local function endEclipse()
	local e = eclipse
	eclipse = nil
	if not e then
		return
	end
	U.tween(e.cc, 1.2, { Brightness = 0, Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
	U.tween(Lighting, 1.2, { ExposureCompensation = e.exposure })
	U.tween(e.disc, 1.2, { Transparency = 1 })
	U.tween(e.corona, 1.2, { Transparency = 1 })
	Debris:AddItem(e.cc, 1.3)
	Debris:AddItem(e.disc, 1.3)
	Debris:AddItem(e.corona, 1.3)
end

local function updateEclipse()
	local e = eclipse
	if not e then
		return
	end
	if os.clock() >= e.untilTime then
		endEclipse()
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local sun = Lighting:GetSunDirection()
	local center = camera.CFrame.Position + sun * 150
	e.disc.CFrame = CFrame.new(center)
	e.corona.CFrame = CFrame.new(camera.CFrame.Position + sun * 152)
end

-- Darken the sky for anyone near the caster and blot out the sun.
function SpellFX.eclipse(character: Model, duration: number)
	local root = rootOf(character)
	local camera = workspace.CurrentCamera
	if not root or not camera or (camera.CFrame.Position - root.Position).Magnitude > 260 then
		return
	end
	if eclipse then
		eclipse.untilTime = math.max(eclipse.untilTime, os.clock() + duration)
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "EclipseTint"
	cc.Parent = Lighting
	U.tween(cc, 1, { TintColor = Color3.fromRGB(185, 160, 255), Brightness = -0.08, Saturation = -0.4, Contrast = 0.2 })
	local exposure = Lighting.ExposureCompensation
	U.tween(Lighting, 1, { ExposureCompensation = exposure - 1.3 })
	local disc = U.part(Vector3.new(26, 26, 26), CFrame.new(), Color3.fromRGB(8, 5, 14), Enum.Material.SmoothPlastic, 1, Enum.PartType.Ball)
	local corona = U.part(Vector3.new(36, 36, 36), CFrame.new(), Color3.fromRGB(215, 190, 255), Enum.Material.Neon, 1, Enum.PartType.Ball)
	U.tween(disc, 1.5, { Transparency = 0 })
	U.tween(corona, 1.5, { Transparency = 0.45 })
	eclipse = { untilTime = os.clock() + duration, cc = cc, disc = disc, corona = corona, exposure = exposure }
	updateEclipse()
	-- a ring of shadow washing out from the caster
	U.ring(root.Position - Vector3.new(0, 3, 0), 40, Color3.fromRGB(60, 20, 90), 1.2, 1.5)
end

---------------------------------------------------------------- lasting spells

-- A raging snowstorm swirling around the dragon: falling snow over the whole area, gusts of wind
-- circling at different heights and frost spreading on the ground.
function SpellFX.blizzard(character: Model, duration: number, radius: number)
	follow(character, duration, function(f, root)
		local sky = U.part(Vector3.new(radius * 2, 1, radius * 2), root.CFrame, Color3.new(1, 1, 1), nil, 1)
		local snow = U.emitter(sky, {
			Texture = U.SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 230, 255)),
			LightEmission = 0.6,
			Rate = 220,
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(18, 26),
			SpreadAngle = Vector2.new(20, 20),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(14, 0, 6),
			Size = U.NS({ { 0, 0.7 }, { 1, 0.4 } }),
			Transparency = U.NS({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
		})
		local fog = U.emitter(sky, {
			Texture = U.SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
			LightEmission = 0.2,
			Rate = 18,
			Lifetime = NumberRange.new(1.5, 2.2),
			Speed = NumberRange.new(10, 16),
			EmissionDirection = Enum.NormalId.Bottom,
			Size = U.NS({ { 0, 8 }, { 1, 14 } }),
			Transparency = U.NS({ { 0, 0.6 }, { 1, 1 } }),
			RotSpeed = NumberRange.new(-60, 60),
		})
		local frost = U.part(Vector3.new(0.2, 2, 2), CFrame.new(), Color3.fromRGB(215, 240, 255), Enum.Material.Ice, 0.35, Enum.PartType.Cylinder)
		U.tween(frost, 1.2, { Size = Vector3.new(0.2, radius * 2, radius * 2) })
		f.sky, f.frost = sky, frost
		f.gusts = {}
		for k = 1, 6 do
			local gust = U.part(Vector3.new(0.6, 0.6, 5), CFrame.new(), Color3.fromRGB(235, 248, 255), Enum.Material.Neon, 0.3)
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0, 2.5)
			a0.Parent = gust
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, 0, -2.5)
			a1.Parent = gust
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.45
			trail.LightEmission = 0.8
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 215, 255))
			trail.Transparency = U.NS({ { 0, 0.2 }, { 1, 1 } })
			trail.Parent = gust
			table.insert(f.gusts, { part = gust, r = rand(0.35, 0.95) * radius, h = rand(0.5, 9), speed = rand(2.5, 4) * (k % 2 == 0 and 1 or -1), phase = math.random() * 6.28 })
			table.insert(f.parts, gust)
		end
		table.insert(f.parts, sky)
		table.insert(f.parts, frost)
		table.insert(f.parts, snow)
		table.insert(f.parts, fog)
	end, function(f, _, t, root)
		local pos = root.Position
		local ground = feetY(f.character, root)
		f.sky.CFrame = CFrame.new(pos.X, pos.Y + 16, pos.Z)
		f.frost.CFrame = CFrame.new(pos.X, ground + 0.15, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		for _, g in ipairs(f.gusts) do
			local a = g.phase + t * g.speed
			local at = Vector3.new(pos.X + math.cos(a) * g.r, ground + g.h + math.sin(t * 2 + g.phase) * 1.5, pos.Z + math.sin(a) * g.r)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a)) * math.sign(g.speed)
			g.part.CFrame = CFrame.lookAt(at, at + tangent)
		end
	end)
end

-- Encased in ice: a few overlapping slabs of clear ice make a faceted crystal around the
-- dragon's body, with sharp crystals jutting out of it. It shatters when the spell ends.
function SpellFX.iceFortress(character: Model, duration: number)
	local root = rootOf(character)
	if not root then
		return
	end
	local scale = character:GetAttribute("DragonScale") or 1
	-- Fit the ice around the body, neck, head and legs (not the wings or the end of the tail).
	local lo, hi = Vector3.one * -2 * scale, Vector3.one * 2 * scale
	for _, d in ipairs(character:GetChildren()) do
		local name = d.Name
		if d:IsA("BasePart") and (name == "Torso" or name == "Head" or name == "Jaw" or name:match("^Neck") or name:match("^Leg") or name:match("^Shin") or name == "Tail1" or name == "Tail2") then
			local at = root.CFrame:PointToObjectSpace(d.Position)
			local half = Vector3.one * math.max(d.Size.X, d.Size.Y, d.Size.Z) / 2
			lo = lo:Min(at - half)
			hi = hi:Max(at + half)
		end
	end
	local margin = Vector3.one * 1.2 * scale
	local body = hi - lo + margin * 2
	local center = CFrame.new((lo + hi) / 2)
	follow(character, duration, function(f)
		f.slabs = {}
		local slabs = {
			{ size = body, rot = CFrame.new() },
			{ size = body * Vector3.new(0.9, 0.92, 0.96), rot = CFrame.Angles(0, math.rad(10), math.rad(7)) },
			{ size = body * Vector3.new(0.94, 0.86, 0.92), rot = CFrame.Angles(math.rad(6), math.rad(-9), math.rad(-5)) },
		}
		for i, slab in ipairs(slabs) do
			local color = i == 1 and Color3.fromRGB(190, 230, 255) or Color3.fromRGB(165, 215, 255)
			local p = U.part(slab.size * 0.2, root.CFrame, color, i == 1 and Enum.Material.Glass or Enum.Material.Ice, i == 1 and 0.55 or 0.7)
			U.tween(p, 0.3 + i * 0.08, { Size = slab.size }, Enum.EasingStyle.Back)
			table.insert(f.slabs, { part = p, rot = slab.rot })
			table.insert(f.parts, p)
		end
		f.crystals = {}
		for k = 1, 9 do
			local a = k / 9 * math.pi * 2 + rand(-0.25, 0.25)
			local len = rand(3.5, 6) * scale
			local crystal = U.part(Vector3.new(0.9 * scale, len, 0.9 * scale), root.CFrame, Color3.fromRGB(215, 245, 255), Enum.Material.Ice, 0.1)
			local offset = Vector3.new(math.cos(a) * body.X * 0.42, rand(0, 0.45) * body.Y, math.sin(a) * body.Z * 0.42)
			-- lean out from the body, turned 45 degrees so it reads as a sharp crystal
			local tilt = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, rand(-1.1, -0.5)) * CFrame.Angles(0, math.rad(45), 0)
			table.insert(f.crystals, { part = crystal, offset = offset + tilt.UpVector * len * 0.3, tilt = tilt })
			table.insert(f.parts, crystal)
		end
		local mist = U.emitter(f.slabs[1].part, {
			Texture = U.SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(230, 245, 255)),
			LightEmission = 0.3,
			Rate = 10,
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(1, 3),
			Size = U.NS({ { 0, 3 }, { 1, 6 } }),
			Transparency = U.NS({ { 0, 0.7 }, { 1, 1 } }),
		})
		U.burst(root.Position, Color3.fromRGB(230, 250, 255), Color3.fromRGB(150, 210, 255), 30, 18, 1.2, U.SPARKLE)
		table.insert(f.parts, mist)
	end, function(f, _, t, r)
		local cf = CFrame.new(r.Position) * r.CFrame.Rotation * center
		for i, slab in ipairs(f.slabs) do
			slab.part.CFrame = cf * slab.rot
			if i == 1 then
				slab.part.Transparency = 0.55 + math.sin(t * 3) * 0.06
			end
		end
		for _, c in ipairs(f.crystals) do
			c.part.CFrame = cf * CFrame.new(c.offset) * c.tilt
		end
	end)
	-- shatter at the end
	task.delay(duration, function()
		local r = rootOf(character)
		if r then
			U.burst(r.Position, Color3.fromRGB(220, 245, 255), Color3.fromRGB(140, 200, 255), 40, 30, 1.6, U.SPARKLE)
			for _ = 1, 8 do
				local shard = U.part(Vector3.new(0.8, 2, 0.8), CFrame.new(r.Position) * CFrame.Angles(rand(0, 6), rand(0, 6), 0), Color3.fromRGB(205, 240, 255), Enum.Material.Ice, 0.1)
				U.tween(shard, 0.7, { Position = r.Position + Vector3.new(rand(-9, 9), rand(-2, 6), rand(-9, 9)), Transparency = 1 })
				Debris:AddItem(shard, 0.8)
			end
		end
	end)
end

-- A tornado funnel around the dragon (or a boss: `color` makes it a firestorm): rings of dust
-- spinning faster and wider as they rise, with bits of debris caught in the wind.
function SpellFX.cyclone(character: Model, duration: number, radius: number, color: Color3?)
	follow(character, duration, function(f, root)
		f.puffs = {}
		local layers = 8
		local low = color or Color3.fromRGB(235, 242, 248)
		local high = color and color:Lerp(Color3.fromRGB(60, 20, 10), 0.55) or Color3.fromRGB(175, 185, 200)
		local mat = color and Enum.Material.Neon or Enum.Material.SmoothPlastic
		if color then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = radius * 2
			light.Brightness = 2
			light.Parent = root
			table.insert(f.parts, light)
		end
		for layer = 1, layers do
			local h = (layer - 1) * 2.8 * (color and 1.4 or 1)
			local r = radius * (0.2 + 0.8 * (layer - 1) / (layers - 1))
			for k = 1, 6 do
				local puff = U.part(Vector3.new(2.4 + layer * 0.5, 2.4 + layer * 0.5, 2.4 + layer * 0.5), root.CFrame, low:Lerp(high, layer / layers), mat, color and 0.55 or 0.62, Enum.PartType.Ball)
				table.insert(f.puffs, { part = puff, h = h, r = r, phase = k / 6 * math.pi * 2 + layer * 0.5, speed = 5 + layer * 0.4 })
				table.insert(f.parts, puff)
			end
		end
		for k = 1, 6 do
			local rock = U.part(Vector3.new(0.9, 0.7, 0.8), root.CFrame, Color3.fromRGB(110, 100, 90), Enum.Material.Slate, 0)
			table.insert(f.puffs, { part = rock, h = rand(2, 14), r = rand(0.5, 1) * radius, phase = k, speed = 7, spin = true })
			table.insert(f.parts, rock)
		end
		local dust = U.emitter(f.puffs[1].part, {
			Texture = U.SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(210, 215, 220)),
			LightEmission = 0.1,
			Rate = 25,
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(4, 8),
			Size = U.NS({ { 0, 3 }, { 1, 7 } }),
			Transparency = U.NS({ { 0, 0.6 }, { 1, 1 } }),
		})
		table.insert(f.parts, dust)
	end, function(f, _, t, root)
		local pos = root.Position
		local ground = feetY(f.character, root)
		for _, p in ipairs(f.puffs) do
			local a = p.phase + t * p.speed
			local at = Vector3.new(pos.X + math.cos(a) * p.r, ground + p.h, pos.Z + math.sin(a) * p.r)
			p.part.CFrame = p.spin and (CFrame.new(at) * CFrame.Angles(t * 5, t * 7, 0)) or CFrame.new(at)
		end
	end)
end

-- A boss whirlwind's little cyclones spiralling out across the room (Dungeons.cyclonePos, from
-- the server's start time, so every client sees them where they hurt).
function SpellFX.cyclones(data)
	local count, maxR = data.count or 4, data.maxR or 60
	local color = data.color or Color3.fromRGB(255, 150, 60)
	local funnels = {}
	for i = 1, count do
		local puffs = {}
		for layer = 1, 4 do
			for k = 1, 4 do
				local size = 1.4 + layer * 0.7
				local puff = U.part(Vector3.new(size, size, size), CFrame.new(data.center), color:Lerp(Color3.fromRGB(80, 30, 10), layer / 6), Enum.Material.Neon, 0.5, Enum.PartType.Ball)
				table.insert(puffs, { part = puff, h = (layer - 1) * 2.4, r = (data.radius or 7) * (0.25 + 0.25 * layer), phase = k / 4 * math.pi * 2 + layer })
			end
		end
		funnels[i] = puffs
	end
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - data.start
		if t > data.duration then
			conn:Disconnect()
			for _, puffs in ipairs(funnels) do
				for _, p in ipairs(puffs) do
					U.tween(p.part, 0.4, { Transparency = 1 })
					Debris:AddItem(p.part, 0.45)
				end
			end
			return
		end
		for i, puffs in ipairs(funnels) do
			local c = Dungeons.cyclonePos(data.center, i, count, math.max(0, t), maxR)
			for _, p in ipairs(puffs) do
				local a = p.phase + t * 9
				p.part.CFrame = CFrame.new(c.X + math.cos(a) * p.r, c.Y + 1 + p.h, c.Z + math.sin(a) * p.r)
			end
		end
	end)
end

-- Rampage: red flames licking up the dragon, steam puffs and cracks around its feet.
function SpellFX.rampage(character: Model, duration: number)
	follow(character, duration, function(f, root)
		local flames = U.emitter(root, {
			Texture = U.FIRE,
			Color = ColorSequence.new(Color3.fromRGB(255, 90, 40), Color3.fromRGB(160, 10, 0)),
			LightEmission = 0.8,
			Rate = 60,
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(4, 8),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top,
			Size = U.NS({ { 0, 3 }, { 1, 0.5 } }),
			Transparency = U.NS({ { 0, 0.2 }, { 1, 1 } }),
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 70, 40)
		light.Range = 18
		light.Brightness = 2
		light.Parent = root
		table.insert(f.parts, flames)
		table.insert(f.parts, light)
		f.nextStomp = 0
	end, function(f, _, t, root)
		if t >= f.nextStomp then
			f.nextStomp = t + 1.2
			local ground = Vector3.new(root.Position.X, feetY(f.character, root) + 0.2, root.Position.Z)
			U.ring(ground, 9, Color3.fromRGB(255, 80, 40), 0.5, 0.5)
		end
	end)
	local root = rootOf(character)
	if root then
		local ground = Vector3.new(root.Position.X, feetY(character, root) + 0.1, root.Position.Z)
		for k = 1, 8 do
			local a = k / 8 * math.pi * 2
			local crack = U.part(Vector3.new(0.5, 0.2, rand(5, 9)), CFrame.new(ground + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(255, 80, 20), Enum.Material.Neon, 0.1)
			U.tween(crack, 2.5, { Transparency = 1 })
			Debris:AddItem(crack, 2.6)
		end
	end
end

---------------------------------------------------------------- one-shot showpieces

-- Epidemic: a toxic dome bursts out, spores fly to the edge, and a sickly cloud bubbles there.
function SpellFX.epidemic(pos: Vector3, radius: number)
	local green, dark = Color3.fromRGB(150, 255, 60), Color3.fromRGB(40, 110, 20)
	local dome = U.part(Vector3.new(4, 4, 4), CFrame.new(pos), green, Enum.Material.ForceField, 0.2, Enum.PartType.Ball)
	U.tween(dome, 0.6, { Size = Vector3.new(radius * 2, radius * 2, radius * 2) })
	task.delay(0.6, function()
		U.tween(dome, 0.8, { Transparency = 1 })
	end)
	Debris:AddItem(dome, 1.5)
	local ground = pos - Vector3.new(0, 3, 0)
	for k = 1, 14 do
		local a = k / 14 * math.pi * 2
		local spore = U.part(Vector3.new(1.4, 1.4, 1.4), CFrame.new(pos), k % 2 == 0 and green or Color3.fromRGB(200, 255, 90), Enum.Material.Neon, 0, Enum.PartType.Ball)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.5, 0)
		a0.Parent = spore
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.5, 0)
		a1.Parent = spore
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.35
		trail.Color = ColorSequence.new(green, dark)
		trail.Transparency = U.NS({ { 0, 0.2 }, { 1, 1 } })
		trail.LightEmission = 0.6
		trail.Parent = spore
		U.tween(spore, 0.55, { Position = ground + Vector3.new(math.cos(a) * radius, 1, math.sin(a) * radius) })
		Debris:AddItem(spore, 0.6)
	end
	task.delay(0.5, function()
		for k = 1, 8 do
			local a = k / 8 * math.pi * 2
			local anchor = U.anchorAt(ground + Vector3.new(math.cos(a) * radius * 0.85, 1.5, math.sin(a) * radius * 0.85))
			local cloud = U.emitter(anchor, {
				Texture = U.SMOKE,
				Color = ColorSequence.new(green, dark),
				LightEmission = 0.3,
				Rate = 12,
				Lifetime = NumberRange.new(1.4, 2),
				Speed = NumberRange.new(1, 3),
				Size = U.NS({ { 0, 4 }, { 1, 9 } }),
				Transparency = U.NS({ { 0, 0.45 }, { 1, 1 } }),
				Acceleration = Vector3.new(0, 1.5, 0),
			})
			task.delay(3, function()
				cloud.Enabled = false
			end)
			Debris:AddItem(anchor, 5.5)
		end
		for _ = 1, 16 do
			local bubble = U.part(Vector3.new(0.8, 0.8, 0.8), CFrame.new(ground + Vector3.new(rand(-1, 1) * radius * 0.8, 0.5, rand(-1, 1) * radius * 0.8)), green, Enum.Material.Neon, 0.2, Enum.PartType.Ball)
			local time = rand(1, 2)
			task.delay(rand(0, 1.5), function()
				U.tween(bubble, time, { Position = bubble.Position + Vector3.new(0, rand(4, 8), 0), Size = Vector3.new(1.6, 1.6, 1.6), Transparency = 1 })
			end)
			Debris:AddItem(bubble, 4)
		end
	end)
	U.flash(pos, green, radius * 3, 1)
end

-- Umbral Devour: shadows are torn from the ground all around and sucked into the dragon.
function SpellFX.umbralDevour(pos: Vector3, radius: number)
	local purple, dark = Color3.fromRGB(150, 60, 220), Color3.fromRGB(25, 10, 40)
	local ground = pos - Vector3.new(0, 3, 0)
	for k = 1, 20 do
		local a = k / 20 * math.pi * 2 + rand(-0.1, 0.1)
		local wisp = U.part(Vector3.new(1.2, 1.2, 3), CFrame.lookAt(ground + Vector3.new(math.cos(a) * radius, 1, math.sin(a) * radius), pos), k % 3 == 0 and purple or dark, Enum.Material.Neon, 0.1)
		local time = rand(0.4, 0.7)
		U.tween(wisp, time, { CFrame = CFrame.lookAt(pos, pos + (pos - wisp.Position).Unit), Size = Vector3.new(0.3, 0.3, 1), Transparency = 0.6 }, Enum.EasingStyle.Quad)
		Debris:AddItem(wisp, time)
	end
	local hole = U.part(Vector3.new(radius * 2, radius * 2, radius * 2), CFrame.new(pos), dark, Enum.Material.Neon, 0.6, Enum.PartType.Ball)
	U.tween(hole, 0.6, { Size = Vector3.new(2, 2, 2), Transparency = 0.05 })
	task.delay(0.6, function()
		U.tween(hole, 0.3, { Size = Vector3.new(radius, radius, radius), Transparency = 1 })
		U.burst(pos, purple, dark, 40, 30, 2.5, U.SPARKLE)
	end)
	Debris:AddItem(hole, 1)
end

-- Absolute Zero: an ice dome snaps outward, spikes of ice burst from the ground in a ring and the
-- ground stays frozen for a moment.
function SpellFX.absoluteZero(pos: Vector3, radius: number)
	local ice = Color3.fromRGB(200, 240, 255)
	local dome = U.part(Vector3.new(3, 3, 3), CFrame.new(pos), ice, Enum.Material.Glass, 0.35, Enum.PartType.Ball)
	U.tween(dome, 0.35, { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 0.8 })
	task.delay(0.35, function()
		U.tween(dome, 0.6, { Transparency = 1 })
	end)
	Debris:AddItem(dome, 1)
	local ground = pos - Vector3.new(0, 3, 0)
	local frost = U.part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(225, 245, 255), Enum.Material.Ice, 0.3, Enum.PartType.Cylinder)
	task.delay(3, function()
		U.tween(frost, 1, { Transparency = 1 })
	end)
	Debris:AddItem(frost, 4.1)
	for ringIndex, dist in ipairs({ radius * 0.45, radius * 0.85 }) do
		local count = ringIndex == 1 and 8 or 14
		for k = 1, count do
			local a = k / count * math.pi * 2 + ringIndex * 0.3
			local height = rand(5, 9) * (ringIndex == 1 and 0.8 or 1)
			local base = ground + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
			local lean = CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, rand(-0.5, -0.15)) * CFrame.Angles(0, math.rad(45), 0) -- leaning outward
			local spike = U.part(Vector3.new(1.6, 0.2, 1.6), CFrame.new(base) * lean, ice, Enum.Material.Ice, 0.05)
			task.delay(ringIndex * 0.12, function()
				U.tween(spike, 0.18, { Size = Vector3.new(1.6, height, 1.6), CFrame = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0) }, Enum.EasingStyle.Back)
			end)
			task.delay(2.6, function()
				U.tween(spike, 0.5, { Transparency = 1 })
			end)
			Debris:AddItem(spike, 3.2)
		end
	end
	U.burst(pos, ice, Color3.fromRGB(120, 190, 255), 50, 35, 2, U.SPARKLE)
end

-- Lightning Storm: a black cloud gathers, then bolts keep hammering the area.
function SpellFX.lightningStorm(pos: Vector3, radius: number, delay: number, colorA: Color3)
	local cloud = U.part(Vector3.new(3, radius * 1.6, radius * 1.6), CFrame.new(pos + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 55), Enum.Material.SmoothPlastic, 1, Enum.PartType.Cylinder)
	U.tween(cloud, delay, { Transparency = 0.25, Size = Vector3.new(5, radius * 2.6, radius * 2.6) })
	local rumble = U.emitter(cloud, {
		Texture = U.SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(70, 70, 90)),
		LightEmission = 0,
		Rate = 25,
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(2, 5),
		Size = U.NS({ { 0, 10 }, { 1, 16 } }),
		Transparency = U.NS({ { 0, 0.4 }, { 1, 1 } }),
	})
	task.delay(delay, function()
		for k = 1, 9 do
			task.delay(k * 0.12, function()
				local off = Vector3.new(rand(-1, 1) * radius * 0.8, 0, rand(-1, 1) * radius * 0.8)
				App.VFX.lightningBolt(pos + off + Vector3.new(0, 45, 0), pos + off, Color3.new(1, 1, 1):Lerp(colorA, 0.4))
				U.flash(pos + off, colorA, 25, 0.2)
			end)
		end
		task.delay(1.4, function()
			rumble.Enabled = false
			U.tween(cloud, 1, { Transparency = 1 })
		end)
	end)
	Debris:AddItem(cloud, delay + 2.6)
end

-- Toxic Deluge: green rain pours down on the area and leaves a bubbling puddle.
function SpellFX.toxicDeluge(pos: Vector3, radius: number, delay: number)
	local green = Color3.fromRGB(140, 255, 60)
	local sky = U.part(Vector3.new(radius * 2, 1, radius * 2), CFrame.new(pos + Vector3.new(0, 35, 0)), green, nil, 1)
	local rain = U.emitter(sky, {
		Texture = U.SPARKLE,
		Color = ColorSequence.new(green, Color3.fromRGB(60, 160, 30)),
		LightEmission = 0.7,
		Rate = 260,
		Lifetime = NumberRange.new(0.6, 0.8),
		Speed = NumberRange.new(55, 70),
		SpreadAngle = Vector2.new(4, 4),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = U.NS({ { 0, 0.5 }, { 1, 0.3 } }),
		Transparency = U.NS({ { 0, 0.1 }, { 1, 0.4 } }),
	})
	task.delay(delay + 1.2, function()
		rain.Enabled = false
	end)
	Debris:AddItem(sky, delay + 2.5)
	task.delay(delay, function()
		local puddle = U.part(Vector3.new(0.2, 2, 2), CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 200, 40), Enum.Material.Neon, 0.35, Enum.PartType.Cylinder)
		U.tween(puddle, 0.4, { Size = Vector3.new(0.2, radius * 1.9, radius * 1.9) })
		task.delay(2.5, function()
			U.tween(puddle, 1, { Transparency = 1 })
		end)
		Debris:AddItem(puddle, 3.6)
	end)
end

-- Death Mark: a skull hangs over the target while the mark lands.
function SpellFX.deathMark(pos: Vector3, delay: number)
	local anchor = U.anchorAt(pos + Vector3.new(0, 10, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 90)
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Text = "💀"
	label.TextTransparency = 1
	label.Parent = gui
	gui.Parent = anchor
	U.tween(label, delay * 0.5, { TextTransparency = 0 })
	U.tween(anchor, delay, { Position = pos + Vector3.new(0, 4, 0) }, Enum.EasingStyle.Quad)
	task.delay(delay, function()
		U.tween(label, 0.3, { TextTransparency = 1 })
	end)
	Debris:AddItem(anchor, delay + 0.4)
end

-- Venom Spit: a stretched glob of venom that drips as it flies (not a fireball).
function SpellFX.venomGlob(origin: Vector3, size: number): BasePart
	local glob = U.part(Vector3.new(size * 1.1, size * 0.9, size * 1.8), CFrame.new(origin), Color3.fromRGB(150, 245, 60), Enum.Material.Neon, 0.1)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = glob
	U.emitter(glob, {
		Texture = U.SPARKLE,
		Color = ColorSequence.new(Color3.fromRGB(160, 255, 60), Color3.fromRGB(70, 150, 20)),
		LightEmission = 0.4,
		Rate = 40,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(0, 1),
		Acceleration = Vector3.new(0, -60, 0),
		Size = U.NS({ { 0, size * 0.35 }, { 1, size * 0.15 } }),
		Transparency = U.NS({ { 0, 0 }, { 1, 0.6 } }),
	})
	return glob
end

function SpellFX.venomSplat(pos: Vector3, radius: number)
	local green = Color3.fromRGB(130, 240, 50)
	local anchor = U.anchorAt(pos)
	local splash = U.emitter(anchor, {
		Texture = U.SPARKLE,
		Color = ColorSequence.new(green, Color3.fromRGB(60, 140, 20)),
		LightEmission = 0.4,
		Speed = NumberRange.new(10, 20),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60, 0),
		Lifetime = NumberRange.new(0.5, 0.8),
		Size = U.NS({ { 0, 0.8 }, { 1, 0.3 } }),
	})
	splash:Emit(35)
	Debris:AddItem(anchor, 1.2)
	local blob = U.part(Vector3.new(2, 2, 2), CFrame.new(pos), green, Enum.Material.Glass, 0.2, Enum.PartType.Ball)
	U.tween(blob, 0.25, { Size = Vector3.new(radius * 1.6, 1, radius * 1.6), Transparency = 1 })
	Debris:AddItem(blob, 0.3)
	local puddle = U.part(Vector3.new(0.15, 1, 1), CFrame.new(pos - Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(100, 200, 40), Enum.Material.Neon, 0.3, Enum.PartType.Cylinder)
	U.tween(puddle, 0.3, { Size = Vector3.new(0.15, radius * 1.4, radius * 1.4) })
	task.delay(1.5, function()
		U.tween(puddle, 0.8, { Transparency = 1 })
	end)
	Debris:AddItem(puddle, 2.4)
end

---------------------------------------------------------------- hooks from VFX

-- A lasting buff was cast. Returns true when it has its own showpiece (so VFX skips the
-- generic sparkle aura).
function SpellFX.onBuff(data): boolean
	local character = data.character
	local colorA, colorB = U.palette(data.classId)
	local root = rootOf(character)
	if root and isUltimate(data.abilityId) then
		SpellFX.flourish(root.Position, colorA, colorB)
	end
	local ability = Abilities[data.abilityId or ""]
	if type(ability) == "table" and ability.healPct then
		SpellFX.plusSigns(character, 10)
	end
	local duration = data.duration or 6
	if data.abilityId == "Eclipse" then
		SpellFX.eclipse(character, duration)
	elseif data.abilityId == "Blizzard" then
		SpellFX.blizzard(character, duration, ability.aura and ability.aura.radius or 20)
		return true
	elseif data.abilityId == "IceFortress" then
		SpellFX.iceFortress(character, duration)
		return true
	elseif data.abilityId == "Cyclone" then
		SpellFX.cyclone(character, duration, ability.aura and ability.aura.radius or 12)
		return true
	elseif data.abilityId == "Rampage" then
		SpellFX.rampage(character, duration)
		return true
	end
	return App.LegendFX.buff(data)
end

function SpellFX.onNova(data)
	local colorA, colorB = U.palette(data.classId, data.color)
	if isUltimate(data.abilityId) then
		SpellFX.flourish(data.pos, colorA, colorB)
	end
	if data.abilityId == "Epidemic" then
		SpellFX.epidemic(data.pos, data.radius)
	elseif data.abilityId == "UmbralDevour" then
		SpellFX.umbralDevour(data.pos, data.radius)
	elseif data.abilityId == "AbsoluteZero" then
		SpellFX.absoluteZero(data.pos, data.radius)
	else
		App.LegendFX.nova(data)
	end
	-- life-stealing novas heal their caster
	local ability = Abilities[data.abilityId or ""]
	if type(ability) == "table" and ability.effects and ability.effects.lifestealBonus and data.character then
		task.delay(0.3, function()
			SpellFX.plusSigns(data.character, 6)
		end)
	end
end

function SpellFX.onStrike(data)
	local colorA, colorB = U.palette(data.classId, data.color)
	local delay = data.delay or 0
	if isUltimate(data.abilityId) and data.character then
		local root = rootOf(data.character)
		if root then
			SpellFX.flourish(root.Position, colorA, colorB)
		end
	end
	if data.abilityId == "LightningStorm" then
		SpellFX.lightningStorm(data.pos, data.radius, delay, colorA)
	elseif data.abilityId == "ToxicDeluge" then
		SpellFX.toxicDeluge(data.pos, data.radius, delay)
	elseif data.abilityId == "DeathMark" then
		SpellFX.deathMark(data.pos, delay)
	end
end

function SpellFX.init(app)
	App = app
	U = App.VFX.util
	RunService.RenderStepped:Connect(function(dt)
		updateFollowers(dt)
		updateEclipse()
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		-- a respawn mid-eclipse shouldn't leave the sky dark
		if eclipse then
			eclipse.untilTime = 0
		end
	end)
end

return SpellFX
