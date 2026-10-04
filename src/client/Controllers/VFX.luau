-- Visual effects: dragon breath, fireballs, explosions, novas, meteor/lightning strikes,
-- boss telegraphs, viking axes, level-ups... Everything here is purely cosmetic.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Remotes = require(Shared.Remotes)

local VFX = {}
local App

local folder: Folder
local breaths = {} -- [Model] = { part, emitters, light, untilTime, dir }
local projectiles = {} -- [id] = { parts, origin, dir, speed, range, start }

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function NS(points)
	local kps = {}
	for _, p in ipairs(points) do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end

local function palette(classId: string?, color: Color3?)
	if color then
		return color, color:Lerp(Color3.new(0, 0, 0), 0.45), nil
	end
	local class = classId and Classes.get(classId)
	if class then
		return class.fire.colorA, class.fire.colorB, class.fire
	end
	return Color3.fromRGB(255, 180, 60), Color3.fromRGB(200, 40, 0), nil
end

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function anchorAt(pos: Vector3)
	local p = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), Color3.new(), nil, 1)
	return p
end

local function emitter(parent: Instance, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 0.8)
	e.Speed = NumberRange.new(10, 20)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(1, 0)
	e.Transparency = NS({ { 0, 0 }, { 1, 1 } })
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function tween(inst: Instance, time: number, goal, style: Enum.EasingStyle?)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function flash(pos: Vector3, color: Color3, range: number, time: number?)
	local anchor = anchorAt(pos)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 5
	light.Parent = anchor
	tween(light, time or 0.4, { Brightness = 0 })
	Debris:AddItem(anchor, (time or 0.4) + 0.1)
end

local function burst(pos: Vector3, colorA: Color3, colorB: Color3, count: number, speed: number, size: number, texture: string?)
	local anchor = anchorAt(pos)
	local e = emitter(anchor, {
		Texture = texture or FIRE,
		Color = ColorSequence.new(colorA, colorB),
		Speed = NumberRange.new(speed * 0.5, speed),
		Size = NS({ { 0, size }, { 1, size * 0.2 } }),
		Lifetime = NumberRange.new(0.4, 0.8),
		Drag = 3,
		RotSpeed = NumberRange.new(-180, 180),
		Rotation = NumberRange.new(0, 360),
	})
	e:Emit(count)
	Debris:AddItem(anchor, 1.5)
end

local function ring(pos: Vector3, radius: number, color: Color3, time: number, thickness: number?)
	local r = part(Vector3.new(thickness or 0.6, 2, 2), CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
	tween(r, time, { Size = Vector3.new(thickness or 0.6, radius * 2, radius * 2), Transparency = 1 })
	Debris:AddItem(r, time + 0.1)
end

-- Shared with SpellFX (the fancier per-spell effects).
VFX.util = {
	NS = NS,
	part = part,
	anchorAt = anchorAt,
	emitter = emitter,
	tween = tween,
	flash = flash,
	burst = burst,
	ring = ring,
	palette = palette,
	FIRE = FIRE,
	SMOKE = SMOKE,
	SPARKLE = SPARKLE,
}
VFX.errorCount = 0 -- effects that failed (the client sim checks this stays 0)

---------------------------------------------------------------- explosion

function VFX.explosion(pos: Vector3, radius: number, colorA: Color3, colorB: Color3)
	local sphere = part(Vector3.new(2, 2, 2), CFrame.new(pos), colorA, Enum.Material.Neon, 0.15, Enum.PartType.Ball)
	tween(sphere, 0.35, { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 })
	Debris:AddItem(sphere, 0.4)
	burst(pos, colorA, colorB, 25, radius * 4, radius * 0.5)
	flash(pos, colorA, radius * 3, 0.5)
end

---------------------------------------------------------------- breath

local function makeBreath(character: Model, classId: string)
	local colorA, colorB, fire = palette(classId)
	local style = fire and fire.style or "magma"
	local size = fire and fire.size or 2.4
	local scale = character:GetAttribute("DragonScale") or 1
	local p = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(), nil, 1)
	local emitters = {}
	table.insert(emitters, emitter(p, {
		Texture = fire and fire.texture or FIRE,
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1):Lerp(colorA, 0.6)), ColorSequenceKeypoint.new(0.3, colorA), ColorSequenceKeypoint.new(1, colorB) }),
		LightEmission = fire and fire.lightEmission or 1,
		Size = NS({ { 0, 0.5 * size * scale }, { 0.4, 1.6 * size * scale }, { 1, 2.8 * size * scale } }),
		Transparency = NS({ { 0, 0.1 }, { 0.7, 0.35 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.34, 0.44),
		Speed = NumberRange.new(56, 66),
		SpreadAngle = Vector2.new(13, 13),
		Rate = 150,
		RotSpeed = NumberRange.new(-120, 120),
		Rotation = NumberRange.new(0, 360),
		EmissionDirection = Enum.NormalId.Front,
	}))
	if style == "shadow" then
		table.insert(emitters, emitter(p, {
			Texture = SMOKE,
			Color = ColorSequence.new(colorB, Color3.new(0.05, 0, 0.08)),
			LightEmission = 0,
			Size = NS({ { 0, 1.5 * scale }, { 1, 5 * scale } }),
			Transparency = NS({ { 0, 0.5 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.5, 0.7),
			Speed = NumberRange.new(35, 45),
			SpreadAngle = Vector2.new(18, 18),
			Rate = 40,
			EmissionDirection = Enum.NormalId.Front,
		}))
	elseif style == "storm" then
		table.insert(emitters, emitter(p, {
			Texture = FIRE,
			Color = ColorSequence.new(Color3.new(1, 1, 1), colorA),
			Size = NS({ { 0, 0.8 * scale }, { 1, 1.6 * scale } }),
			Lifetime = NumberRange.new(0.3, 0.4),
			Speed = NumberRange.new(70, 80),
			SpreadAngle = Vector2.new(6, 6),
			Rate = 60,
			EmissionDirection = Enum.NormalId.Front,
		}))
	elseif style == "magma" then
		table.insert(emitters, emitter(p, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), colorB),
			Size = NS({ { 0, 0.6 * scale }, { 1, 0.1 } }),
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(40, 60),
			SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(0, -40, 0),
			Rate = 60,
			EmissionDirection = Enum.NormalId.Front,
		}))
	elseif style == "frost" then
		table.insert(emitters, emitter(p, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), colorB),
			LightEmission = 0.3,
			Size = NS({ { 0, 1 * scale }, { 1, 4 * scale } }),
			Transparency = NS({ { 0, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.45, 0.6),
			Speed = NumberRange.new(40, 50),
			SpreadAngle = Vector2.new(15, 15),
			Rate = 50,
			EmissionDirection = Enum.NormalId.Front,
		}))
	elseif style == "venom" then
		table.insert(emitters, emitter(p, {
			Texture = SPARKLE,
			Color = ColorSequence.new(colorA),
			Size = NS({ { 0, 0.7 * scale }, { 1, 0.2 } }),
			Lifetime = NumberRange.new(0.5, 0.7),
			Speed = NumberRange.new(40, 55),
			SpreadAngle = Vector2.new(18, 18),
			Acceleration = Vector3.new(0, -35, 0),
			Rate = 50,
			EmissionDirection = Enum.NormalId.Front,
		}))
	end
	for _, e in ipairs(emitters) do
		e.Enabled = false
	end
	local light = Instance.new("PointLight")
	light.Color = colorA
	light.Range = 18 * scale
	light.Brightness = 0
	light.Parent = p
	return { part = p, emitters = emitters, light = light, untilTime = 0, dir = Vector3.new(0, 0, -1), classId = classId }
end

function VFX.breath(character: Model, dir: Vector3, classId: string, duration: number, reach: number?)
	if not character or not character.Parent then
		return
	end
	local b = breaths[character]
	if b and b.classId ~= classId then
		b.part:Destroy()
		b = nil
	end
	if not b then
		b = makeBreath(character, classId)
		breaths[character] = b
	end
	b.dir = dir
	b.untilTime = os.clock() + duration
	-- a longer breath (the Forgeheart Wyrmling's +breath range): the flames fly faster, farther
	reach = reach or 1
	if b.reach ~= reach then
		b.reach = reach
		b.speeds = b.speeds or {}
		for _, e in ipairs(b.emitters) do
			b.speeds[e] = b.speeds[e] or e.Speed
			local base = b.speeds[e]
			e.Speed = NumberRange.new(base.Min * reach, base.Max * reach)
		end
	end
	for _, e in ipairs(b.emitters) do
		e.Enabled = true
	end
end

function VFX.isBreathing(character: Model): boolean
	local b = breaths[character]
	return b ~= nil and os.clock() < b.untilTime
end

local function updateBreaths()
	local now = os.clock()
	for character, b in pairs(breaths) do
		if not character.Parent then
			b.part:Destroy()
			breaths[character] = nil
			continue
		end
		local head = character:FindFirstChild("Head")
		local mouth = head and head:FindFirstChild("Mouth")
		local pos = mouth and mouth.WorldPosition or character:GetPivot().Position
		b.part.CFrame = CFrame.lookAt(pos, pos + b.dir)
		local active = now < b.untilTime
		for _, e in ipairs(b.emitters) do
			if e.Enabled ~= active then
				e.Enabled = active
			end
		end
		b.light.Brightness = active and (2.5 + math.random() * 1.5) or 0
	end
end

---------------------------------------------------------------- projectiles

function VFX.projectiles(data)
	local colorA, colorB = palette(data.classId)
	local size = data.size or 1.6
	for _, entry in ipairs(data.list) do
		local parts = {}
		local main
		local plain = true -- a glowing ball with a fiery trail (fireballs, bolts...)
		if data.abilityId == "VenomSpit" then
			main = App.SpellFX.venomGlob(data.origin, size)
			main.CFrame = CFrame.lookAt(data.origin, data.origin + entry.dir)
			plain = false
		elseif data.abilityId == "GlacialLance" or data.abilityId == "FrostShards" then
			main = part(Vector3.new(0.7, 0.7, size * 3.5), CFrame.lookAt(data.origin, data.origin + entry.dir), Color3.fromRGB(200, 240, 255), Enum.Material.Ice, 0.1)
		elseif data.abilityId == "SparkBolt" then
			main = part(Vector3.new(0.5, 0.5, size * 5), CFrame.lookAt(data.origin, data.origin + entry.dir), Color3.fromRGB(230, 250, 255), Enum.Material.Neon, 0)
		else
			main = part(Vector3.new(size, size, size), CFrame.new(data.origin), colorA, Enum.Material.Neon, 0.05, Enum.PartType.Ball)
		end
		table.insert(parts, main)
		emitter(main, {
			Enabled = plain,
			Texture = data.abilityId == "AcidWave" and SMOKE or FIRE,
			Color = ColorSequence.new(colorA, colorB),
			Rate = 70,
			Lifetime = NumberRange.new(0.3, 0.45),
			Speed = NumberRange.new(1, 3),
			Size = NS({ { 0, size * 1.3 }, { 1, size * 0.3 } }),
			Transparency = NS({ { 0, 0.2 }, { 1, 1 } }),
			SpreadAngle = Vector2.new(30, 30),
		})
		local light = Instance.new("PointLight")
		light.Color = colorA
		light.Range = 12
		light.Brightness = 2
		light.Parent = main
		projectiles[entry.id] = { main = main, origin = data.origin, dir = entry.dir, speed = data.speed, range = data.range, start = os.clock() }
		Debris:AddItem(main, data.range / math.max(1, data.speed) + 1)
	end
end

local function updateProjectiles()
	local now = os.clock()
	for id, p in pairs(projectiles) do
		local traveled = (now - p.start) * p.speed
		if traveled > p.range + 4 or not p.main.Parent then
			if p.main.Parent then
				p.main:Destroy()
			end
			projectiles[id] = nil
		else
			local pos = p.origin + p.dir * traveled
			p.main.CFrame = CFrame.lookAt(pos, pos + p.dir)
		end
	end
end

function VFX.projectileHit(data)
	local p = projectiles[data.id]
	if p then
		p.main:Destroy()
		projectiles[data.id] = nil
	end
	if data.abilityId == "VenomSpit" then
		App.SpellFX.venomSplat(data.pos, data.radius or 6)
		App.Sfx.play("Explosion", 0.25)
		return
	end
	local colorA, colorB = palette(data.classId)
	VFX.explosion(data.pos, data.radius or 6, colorA, colorB)
	App.Sfx.play("Explosion", 0.4)
end

---------------------------------------------------------------- nova / strike / telegraph

function VFX.nova(data)
	local colorA, colorB = palette(data.classId, data.color)
	ring(data.pos - Vector3.new(0, 3, 0), data.radius, colorA, 0.45, 1)
	ring(data.pos - Vector3.new(0, 2, 0), data.radius * 0.7, colorB, 0.6, 0.6)
	burst(data.pos, colorA, colorB, 40, data.radius * 3, 3)
	flash(data.pos, colorA, data.radius * 2.5, 0.5)
	App.SpellFX.onNova(data)
end

function VFX.telegraph(pos: Vector3, radius: number, duration: number, color: Color3?)
	local c = color or Color3.fromRGB(255, 60, 40)
	local base = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local outer = part(Vector3.new(0.2, radius * 2, radius * 2), base, c, Enum.Material.Neon, 0.7, Enum.PartType.Cylinder)
	local inner = part(Vector3.new(0.25, 0.5, 0.5), base, c, Enum.Material.Neon, 0.45, Enum.PartType.Cylinder)
	tween(inner, duration, { Size = Vector3.new(0.25, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	Debris:AddItem(outer, duration)
	Debris:AddItem(inner, duration)
end

function VFX.lightningBolt(from: Vector3, to: Vector3, color: Color3)
	local points = { from }
	local segments = 6
	for i = 1, segments - 1 do
		local p = from:Lerp(to, i / segments) + Vector3.new(math.random(-40, 40) / 10, 0, math.random(-40, 40) / 10)
		table.insert(points, p)
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = part(Vector3.new(0.5, 0.5, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, Enum.Material.Neon, 0)
		tween(seg, 0.3, { Transparency = 1 })
		Debris:AddItem(seg, 0.35)
	end
end

function VFX.strike(data)
	local colorA, colorB = palette(data.classId, data.color)
	local pos, radius, delay = data.pos, data.radius, data.delay or 0
	local style = data.style or "meteor"
	if delay > 0 then
		VFX.telegraph(pos, radius, delay, colorA)
	end
	App.SpellFX.onStrike(data)
	if style == "meteor" and delay > 0 then
		local start = pos + Vector3.new(30, 90, 20)
		local rock = part(Vector3.new(6, 6, 6), CFrame.new(start), Color3.fromRGB(80, 40, 20), Enum.Material.Slate, 0, Enum.PartType.Ball)
		emitter(rock, { Texture = FIRE, Color = ColorSequence.new(colorA, colorB), Rate = 120, Size = NS({ { 0, 7 }, { 1, 2 } }), Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(2, 5) })
		tween(rock, delay, { Position = pos }, Enum.EasingStyle.Linear)
		Debris:AddItem(rock, delay)
	elseif style == "ice" and delay > 0 then
		for _ = 1, 7 do
			local off = Vector3.new(math.random(-100, 100) / 100 * radius * 0.8, 0, math.random(-100, 100) / 100 * radius * 0.8)
			local shard = part(Vector3.new(1.2, 5, 1.2), CFrame.new(pos + off + Vector3.new(0, 50, 0)), Color3.fromRGB(200, 240, 255), Enum.Material.Ice, 0.1)
			tween(shard, delay, { Position = pos + off + Vector3.new(0, 2, 0) }, Enum.EasingStyle.Quad)
			Debris:AddItem(shard, delay + 0.8)
		end
	end
	task.delay(delay, function()
		if style == "lightning" then
			for _ = 1, 4 do
				local off = Vector3.new(math.random(-10, 10) / 10 * radius * 0.6, 0, math.random(-10, 10) / 10 * radius * 0.6)
				VFX.lightningBolt(pos + off + Vector3.new(0, 90, 0), pos + off, Color3.new(1, 1, 1):Lerp(colorA, 0.5))
			end
		elseif style == "poison" then
			local anchor = anchorAt(pos + Vector3.new(0, 2, 0))
			local cloud = emitter(anchor, {
				Texture = SMOKE,
				Color = ColorSequence.new(colorA, colorB),
				LightEmission = 0.4,
				Rate = 30,
				Lifetime = NumberRange.new(1.5, 2.2),
				Speed = NumberRange.new(radius * 0.4, radius * 0.7),
				Size = NS({ { 0, 4 }, { 1, 10 } }),
				Transparency = NS({ { 0, 0.4 }, { 1, 1 } }),
				Drag = 2,
			})
			task.delay(2.5, function()
				cloud.Enabled = false
			end)
			Debris:AddItem(anchor, 5)
		elseif style == "bone" then
			-- grave spikes: bones bursting up out of the floor, then sinking back
			for i = 1, 7 do
				local a = i / 7 * math.pi * 2 + math.random() * 0.6
				local r = (i == 7) and 0 or radius * (0.35 + math.random() * 0.5)
				local height = radius * (0.7 + math.random() * 0.5)
				local base = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				local tilt = CFrame.Angles(math.random(-20, 20) / 100, 0, math.random(-20, 20) / 100)
				local spike = part(Vector3.new(1.3, height, 1.3), CFrame.new(base - Vector3.new(0, height / 2, 0)) * tilt, Color3.fromRGB(225, 215, 190), Enum.Material.Slate, 0)
				tween(spike, 0.12, { CFrame = CFrame.new(base + Vector3.new(0, height / 2 - 0.5, 0)) * tilt })
				task.delay(0.9, function()
					tween(spike, 0.5, { CFrame = CFrame.new(base - Vector3.new(0, height / 2, 0)) * tilt, Transparency = 1 })
				end)
				Debris:AddItem(spike, 1.5)
			end
		elseif style == "shadow" then
			local orb = part(Vector3.new(radius * 2, radius * 2, radius * 2), CFrame.new(pos), colorB, Enum.Material.Neon, 0.5, Enum.PartType.Ball)
			tween(orb, 0.2, { Size = Vector3.new(1, 1, 1), Transparency = 0.1 })
			Debris:AddItem(orb, 0.22)
		end
		VFX.explosion(pos + Vector3.new(0, 2, 0), radius, colorA, colorB)
		ring(pos, radius * 1.1, colorA, 0.5, 0.8)
		App.Sfx.play("Explosion", 0.5)
	end)
end

function VFX.slam(data)
	local color = data.color or Color3.fromRGB(255, 120, 60)
	ring(data.pos, data.radius, color, 0.5, 1.5)
	ring(data.pos, data.radius * 0.6, Color3.fromRGB(180, 150, 110), 0.7, 1)
	burst(data.pos + Vector3.new(0, 1, 0), Color3.fromRGB(170, 150, 120), Color3.fromRGB(90, 80, 70), 40, data.radius * 2, 5, SMOKE)
	-- shake the camera if close
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and (root.Position - data.pos).Magnitude < data.radius * 2.5 then
		task.spawn(function()
			for _ = 1, 8 do
				humanoid.CameraOffset = Vector3.new(math.random(-10, 10) / 20, math.random(-10, 10) / 20, 0)
				task.wait(0.03)
			end
			humanoid.CameraOffset = Vector3.zero
		end)
	end
	App.Sfx.play("Explosion", 0.6)
end

---------------------------------------------------------------- dash / buff / heal / level

function VFX.dash(data)
	local colorA = palette(data.classId)
	local from, to = data.from, data.to
	for i = 0, 5 do
		local p = from:Lerp(to, i / 5)
		local ghost = part(Vector3.new(4, 4, 4), CFrame.new(p), colorA, Enum.Material.Neon, 0.55, Enum.PartType.Ball)
		task.delay(i * 0.035, function()
			tween(ghost, 0.35, { Transparency = 1, Size = Vector3.new(1, 1, 1) })
		end)
		Debris:AddItem(ghost, 0.6)
	end
end

function VFX.buff(data)
	local character = data.character
	if not character or not character.Parent or data.abilityId == "Vanish" then
		return
	end
	local colorA, colorB = palette(data.classId)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = colorA
	highlight.OutlineColor = colorB
	highlight.FillTransparency = 0.8
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	local root = character:FindFirstChild("HumanoidRootPart")
	local aura
	local showpiece = App.SpellFX.onBuff(data)
	if root and not showpiece then
		aura = emitter(root, {
			Color = ColorSequence.new(colorA, colorB),
			Rate = 25,
			Speed = NumberRange.new(4, 10),
			Lifetime = NumberRange.new(0.6, 1),
			Size = NS({ { 0, 1.2 }, { 1, 0 } }),
			Texture = SPARKLE,
		})
	end
	burst(character:GetPivot().Position, colorA, colorB, 30, 20, 2, SPARKLE)
	task.delay(data.duration or 6, function()
		highlight:Destroy()
		if aura then
			aura:Destroy()
		end
	end)
end

function VFX.heal(data)
	local character = data.character
	if not character or not character.Parent then
		return
	end
	local pos = character:GetPivot().Position
	burst(pos, Color3.fromRGB(150, 255, 150), Color3.fromRGB(60, 200, 80), 40, 15, 1.5, SPARKLE)
	ring(pos - Vector3.new(0, 3, 0), 10, Color3.fromRGB(120, 255, 140), 0.6, 0.6)
	App.SpellFX.plusSigns(character, 12)
end

function VFX.levelUp(data)
	local character = data.character
	if not character or not character.Parent then
		return
	end
	local pos = character:GetPivot().Position
	local gold = Color3.fromRGB(255, 215, 80)
	local pillar = part(Vector3.new(60, 6, 6), CFrame.new(pos + Vector3.new(0, 26, 0)) * CFrame.Angles(0, 0, math.rad(90)), gold, Enum.Material.Neon, 0.3, Enum.PartType.Cylinder)
	tween(pillar, 1.2, { Transparency = 1, Size = Vector3.new(60, 0.5, 0.5) })
	Debris:AddItem(pillar, 1.3)
	ring(pos - Vector3.new(0, 3, 0), 16, gold, 0.8, 1)
	burst(pos, gold, Color3.fromRGB(255, 255, 220), 60, 30, 2, SPARKLE)
	flash(pos, gold, 40, 1)
end

---------------------------------------------------------------- vikings & farm

-- A dungeon boss's harpoon: a chain of links flying out to a dragon.
-- A harpooned dragon being dragged in: the chain stays taut between the boss's hand and the
-- dragon for the whole reel, then a thud where it lands.
local function reelChain(d)
	local victim = Players:GetPlayerByUserId(d.userId)
	local bossRoot = d.model and d.model.PrimaryPart
	if not victim or not bossRoot then
		return
	end
	local hand = d.from - bossRoot.Position
	local links = {}
	for i = 1, 14 do
		links[i] = part(Vector3.new(0.4, 0.7, 1.4), CFrame.new(d.from), Color3.fromRGB(70, 70, 80), Enum.Material.Metal)
	end
	local hook = part(Vector3.new(0.6, 1.8, 1.4), CFrame.new(d.from), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
	local start, time = os.clock(), math.max(0.1, d.time or 0.6)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local character = victim.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local done = os.clock() - start >= time or not root or not bossRoot.Parent
		if not done then
			local a = bossRoot.Position + hand
			local b = root.Position
			local look = (b - a).Magnitude > 0.1 and (b - a) or Vector3.new(0, 0, -1)
			hook.CFrame = CFrame.lookAt(b, b + look)
			for i, link in ipairs(links) do
				local p = a:Lerp(b, i / (#links + 1))
				link.CFrame = CFrame.lookAt(p, p + look) * CFrame.Angles(0, 0, i % 2 == 0 and 0 or math.rad(90))
			end
		else
			conn:Disconnect()
			hook:Destroy()
			for _, link in ipairs(links) do
				link:Destroy()
			end
			burst(d.to, Color3.fromRGB(190, 190, 200), Color3.fromRGB(90, 90, 100), 16, 14, 1.5, SMOKE)
		end
	end)
end

local function chainThrow(from: Vector3, to: Vector3, time: number)
	local hook = part(Vector3.new(0.6, 1.8, 1.4), CFrame.new(from), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
	local links = {}
	for i = 1, 10 do
		links[i] = part(Vector3.new(0.35, 0.6, 1.2), CFrame.new(from), Color3.fromRGB(70, 70, 80), Enum.Material.Metal)
	end
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / time, 0, 1)
		local tip = from:Lerp(to, t)
		local dir = to - from
		local look = dir.Magnitude > 0.1 and dir or Vector3.new(0, 0, -1)
		hook.CFrame = CFrame.lookAt(tip, tip + look)
		for i, link in ipairs(links) do
			local p = from:Lerp(tip, i / #links)
			link.CFrame = CFrame.lookAt(p, p + look) * CFrame.Angles(0, 0, i % 2 == 0 and 0 or math.rad(90))
		end
		if t >= 1 then
			conn:Disconnect()
			task.delay(0.05, function()
				hook:Destroy()
				for _, link in ipairs(links) do
					link:Destroy()
				end
			end)
		end
	end)
end

function VFX.throw(data)
	local from, to, time = data.from, data.to, math.max(0.05, data.time)
	if data.style == "chain" then
		chainThrow(from, to, time)
		return
	end
	if data.style == "rune" then
		-- a bolt of rune-fire (Runemaster Sigrun casting from behind her shield)
		local bolt = part(Vector3.new(1.6, 1.6, 1.6), CFrame.new(from), Color3.fromRGB(255, 150, 60), Enum.Material.Neon, 0.1, Enum.PartType.Ball)
		local core = part(Vector3.new(0.8, 0.8, 0.8), CFrame.new(from), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, 0, Enum.PartType.Ball)
		local start = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - start) / time, 0, 1)
			local pos = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)
			bolt.CFrame = CFrame.new(pos)
			core.CFrame = CFrame.new(pos)
			if t >= 1 then
				conn:Disconnect()
				bolt:Destroy()
				core:Destroy()
				burst(to, Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 110, 40), 18, 16, 1.4, SPARKLE)
			end
		end)
		return
	end
	local isHammer = data.style == "hammer"
	local head = part(isHammer and Vector3.new(1.4, 1, 1) or Vector3.new(0.25, 1.4, 1.2), CFrame.new(from), isHammer and Color3.fromRGB(80, 80, 90) or Color3.fromRGB(170, 175, 185), Enum.Material.Metal)
	local handle = part(Vector3.new(0.3, 0.3, 2.4), CFrame.new(from), Color3.fromRGB(120, 80, 45), Enum.Material.Wood)
	local start = os.clock()
	local arc = (to - from).Magnitude * 0.12
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / time, 0, 1)
		local pos = from:Lerp(to, t) + Vector3.new(0, 4 * arc * t * (1 - t), 0)
		local dir = to - from
		local base = CFrame.lookAt(pos, pos + (dir.Magnitude > 0.1 and dir or Vector3.new(0, 0, -1))) * CFrame.Angles(-(os.clock() - start) * 18, 0, 0)
		handle.CFrame = base
		head.CFrame = base * CFrame.new(0, 0, -1.1)
		if t >= 1 then
			conn:Disconnect()
			head:Destroy()
			handle:Destroy()
			burst(to, Color3.fromRGB(180, 170, 150), Color3.fromRGB(100, 90, 80), 8, 10, 1.5, SMOKE)
		end
	end)
end

function VFX.poof(pos: Vector3)
	burst(pos, Color3.fromRGB(220, 220, 220), Color3.fromRGB(120, 120, 120), 18, 12, 4, SMOKE)
end

function VFX.water(pos: Vector3)
	local anchor = anchorAt(pos + Vector3.new(0, 9, 0))
	local e = emitter(anchor, {
		Color = ColorSequence.new(Color3.fromRGB(120, 200, 255)),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, -60, 0),
		Lifetime = NumberRange.new(0.6, 0.8),
		Size = NS({ { 0, 0.5 }, { 1, 0.3 } }),
		EmissionDirection = Enum.NormalId.Bottom,
	})
	e:Emit(45)
	Debris:AddItem(anchor, 1.5)
end

function VFX.harvest(pos: Vector3, color: Color3?)
	burst(pos + Vector3.new(0, 2, 0), color or Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 255, 200), 35, 18, 1.2, SPARKLE)
end

---------------------------------------------------------------- survival, camps, pets

-- A Hornblower winding up: rings pulse out from him until the horn sounds.
function VFX.hornWindup(pos: Vector3, time: number)
	local pulses = math.max(1, math.floor(time / 0.5))
	for i = 0, pulses - 1 do
		task.delay(i * 0.5, function()
			ring(pos - Vector3.new(0, 2.5, 0), 10 + i * 3, Color3.fromRGB(255, 200, 90), 0.45, 0.4)
		end)
	end
end

function VFX.alarm(pos: Vector3)
	ring(pos - Vector3.new(0, 2.5, 0), 70, Color3.fromRGB(255, 120, 60), 1.2, 1.5)
	ring(pos - Vector3.new(0, 2, 0), 40, Color3.fromRGB(255, 200, 90), 0.9, 1)
	flash(pos, Color3.fromRGB(255, 150, 70), 60, 0.8)
	App.Sfx.play("Horn", 0.7)
end

function VFX.eat(character: Model)
	if not character or not character.Parent then
		return
	end
	local head = character:FindFirstChild("Head")
	local pos = head and head.Position or character:GetPivot().Position
	burst(pos, Color3.fromRGB(255, 200, 140), Color3.fromRGB(200, 120, 70), 14, 8, 0.8, SPARKLE)
end

function VFX.potion(character: Model, color: Color3?)
	if not character or not character.Parent then
		return
	end
	local pos = character:GetPivot().Position
	local c = color or Color3.fromRGB(150, 255, 120)
	burst(pos, c, c:Lerp(Color3.new(1, 1, 1), 0.5), 40, 18, 1.6, SPARKLE)
	ring(pos - Vector3.new(0, 3, 0), 12, c, 0.6, 0.6)
end

function VFX.chest(pos: Vector3)
	local gold = Color3.fromRGB(255, 215, 80)
	burst(pos + Vector3.new(0, 4, 0), gold, Color3.fromRGB(255, 255, 200), 60, 25, 1.5, SPARKLE)
	flash(pos, gold, 40, 1)
	App.Sfx.play("Loot")
end

function VFX.splash(pos: Vector3, big: boolean?)
	local anchor = anchorAt(pos + Vector3.new(0, 0.5, 0))
	local e = emitter(anchor, {
		Color = ColorSequence.new(Color3.fromRGB(200, 235, 255)),
		Speed = NumberRange.new(big and 10 or 5, big and 18 or 9),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -45, 0),
		Lifetime = NumberRange.new(0.5, 0.8),
		Size = NS({ { 0, big and 0.7 or 0.4 }, { 1, 0.2 } }),
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(big and 40 or 15)
	Debris:AddItem(anchor, 1.5)
	ring(pos, big and 7 or 4, Color3.fromRGB(220, 245, 255), 0.6, 0.3)
end

---------------------------------------------------------------- dispatch

local HANDLERS = {
	breath = function(d)
		VFX.breath(d.character, d.dir, d.classId, d.duration, d.reach)
	end,
	projectiles = VFX.projectiles,
	projectileHit = VFX.projectileHit,
	nova = VFX.nova,
	strike = VFX.strike,
	telegraph = function(d)
		VFX.telegraph(d.pos, d.radius, d.duration, d.color)
	end,
	slam = VFX.slam,
	dash = VFX.dash,
	buff = VFX.buff,
	heal = VFX.heal,
	levelUp = VFX.levelUp,
	throw = VFX.throw,
	enemyDeath = function(d)
		VFX.poof(d.pos)
	end,
	water = function(d)
		VFX.water(d.pos)
	end,
	harvest = function(d)
		VFX.harvest(d.pos, d.color)
	end,
	hornWindup = function(d)
		VFX.hornWindup(d.pos, d.time or 2.5)
	end,
	alarm = function(d)
		VFX.alarm(d.pos)
	end,
	eat = function(d)
		VFX.eat(d.character)
	end,
	potion = function(d)
		VFX.potion(d.character, d.color)
	end,
	chest = function(d)
		VFX.chest(d.pos)
	end,
	splash = function(d)
		VFX.splash(d.pos, d.big)
	end,
	-- a practice target knocked down (gold ones sparkle more)
	pop = function(d)
		local color = d.color or Color3.fromRGB(255, 220, 90)
		burst(d.pos, Color3.new(1, 1, 1), color, d.big and 30 or 16, 22, 1.4, SPARKLE)
		ring(d.pos - Vector3.new(0, 0.4, 0), d.big and 7 or 4.5, color, 0.35, 0.3)
	end,
	-- a viking landing on the beach after leaping off a longship
	thud = function(d)
		burst(d.pos + Vector3.new(0, 0.5, 0), Color3.fromRGB(225, 205, 160), Color3.fromRGB(150, 125, 90), 14, 12, 2.5, SMOKE)
	end,
	-- water hitting a burning roof while a dragon pours: a hiss of steam and spray
	sizzle = function(d)
		burst(d.pos + Vector3.new(math.random(-6, 6), 0, math.random(-5, 5)), Color3.fromRGB(245, 248, 255), Color3.fromRGB(170, 180, 190), 14, 12, 5, SMOKE)
		burst(d.pos, Color3.fromRGB(200, 235, 255), Color3.fromRGB(90, 160, 240), 10, 16, 0.9, SPARKLE)
	end,
	-- the fire's out: a big cloud of steam
	putOut = function(d)
		burst(d.pos, Color3.fromRGB(245, 248, 255), Color3.fromRGB(170, 180, 190), 60, 18, 9, SMOKE)
		burst(d.pos, Color3.fromRGB(200, 235, 255), Color3.fromRGB(90, 160, 240), 40, 24, 1.3, SPARKLE)
	end,
	-- a dungeon boss's harpoon hooked a dragon and dragged it down (the hooked dragon stops flying)
	harpooned = function(d)
		if d.userId == Players.LocalPlayer.UserId then
			App.Movement.reel(d.to, d.time or 0.6)
		end
		reelChain(d)
	end,
	-- chains breaking (the Rune Forge's elder dragon set free, or a rune shield shattering)
	shatter = function(d)
		burst(d.pos, Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 40), 70, 34, 1.6, SPARKLE)
		ring(d.pos, 22, Color3.fromRGB(255, 200, 120), 0.9, 1)
		flash(d.pos, Color3.fromRGB(255, 180, 90), 70, 0.8)
	end,
	-- a dungeon boss's whirlwind: a firestorm round it, and little cyclones spiralling away
	bossCyclone = function(d)
		if d.model and d.model.Parent then
			App.SpellFX.cyclone(d.model, d.duration or 4, d.radius or 15, d.color)
		end
	end,
	cyclones = function(d)
		App.SpellFX.cyclones(d)
	end,
	-- a dungeon boss getting back up for its second life
	rise = function(d)
		local color = d.color or Color3.fromRGB(120, 255, 190)
		burst(d.pos, color, Color3.new(1, 1, 1), 60, 26, 2, SPARKLE)
		ring(d.pos - Vector3.new(0, 3, 0), 26, color, 1, 1.2)
		flash(d.pos, color, 60, 1)
	end,
	-- a burning house's roof caving in: sparks and a gust of smoke and flame
	collapse = function(d)
		burst(d.pos, Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 80, 20), 60, 30, 1.5, SPARKLE)
		burst(d.pos, Color3.fromRGB(255, 150, 60), Color3.fromRGB(120, 40, 10), 30, 14, 8)
		burst(d.pos, Color3.fromRGB(90, 80, 75), Color3.fromRGB(40, 35, 35), 40, 12, 10, SMOKE)
		flash(d.pos, Color3.fromRGB(255, 140, 60), 60, 0.8)
	end,
}

function VFX.init(app)
	App = app
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = workspace

	Remotes.event("VFX").OnClientEvent:Connect(function(data)
		local handler = type(data) == "table" and HANDLERS[data.kind]
		if handler then
			local ok, err = pcall(handler, data)
			if not ok then
				VFX.errorCount += 1
				warn("[VFX]", data.kind, err)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		updateBreaths()
		updateProjectiles()
	end)
end

return VFX
