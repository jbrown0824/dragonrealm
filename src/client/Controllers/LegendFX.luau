-- The legendary dragons' own effects (the Robux dragons in Config/Classes), layered into VFX and
-- SpellFX by ability id and strike style:
--   * Solaris: the Solar Beam (held like a breath: it opens the jaw), the Sunspear, Solar Flare's
--     rays, Supernova, the Sunfall pillar, Zenith's falling sun, Phoenix Form's burning wings
--   * Tidecaller: Tide Shot's water orbs, the Tidal Surge wave, Riptide / Undertow / Maelstrom
--     whirlpools, the Geyser, the Kraken's tentacles, the Abyssal Shell
-- All cosmetic and local to each client.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local LegendFX = {}
local App
local U -- VFX.util

local beams = {} -- [Model] = { core, glow, tip, light, emitter, to, untilTime }
local shots = {} -- [Model] = os.clock() of its last Tide Shot (the jaw stays open while it spits)
local followers = {} -- { parts = { { part, offset } }, root, untilTime, step? }

local WATER = Color3.fromRGB(70, 175, 235)
local FOAM = Color3.fromRGB(225, 248, 255)
local DEEP = Color3.fromRGB(20, 70, 120)
local SUN = Color3.fromRGB(255, 246, 190)
local GOLD = Color3.fromRGB(255, 170, 40)

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function mouthOf(character: Model): Vector3
	local head = character:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	return mouth and mouth.WorldPosition or character:GetPivot().Position
end

-- A cylinder part lying from a to b (Roblox cylinders run along their X axis).
local function rodCF(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	if (b - a).Magnitude < 1e-3 then
		return CFrame.new(mid)
	end
	return CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
end

local function upright(pos: Vector3): CFrame -- a cylinder standing on end
	return CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
end

local function disc(pos: Vector3, radius: number, color: Color3, material: Enum.Material?, transparency: number?)
	return U.part(Vector3.new(0.3, radius * 2, radius * 2), upright(pos), color, material or Enum.Material.Neon, transparency or 0.4, Enum.PartType.Cylinder)
end

local function fadeOut(p: BasePart, time: number)
	U.tween(p, time, { Transparency = 1 })
	Debris:AddItem(p, time + 0.05)
end

-- Parts that ride along with a dragon for a while (anchored, moved every frame).
local function follow(character: Model, duration: number, build)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local f = { parts = {}, root = root, untilTime = os.clock() + duration, started = os.clock() }
	build(f, root)
	table.insert(followers, f)
end

local function updateFollowers()
	local now = os.clock()
	for i = #followers, 1, -1 do
		local f = followers[i]
		local done = now >= f.untilTime or not f.root.Parent
		for _, entry in ipairs(f.parts) do
			local p, offset = entry[1], entry[2]
			if done then
				if p:IsA("BasePart") then
					fadeOut(p, 0.4)
				else
					p.Enabled = false
					Debris:AddItem(p, 2)
				end
			elseif offset and p:IsA("BasePart") then
				local cf = CFrame.new(f.root.Position) * offset
				if entry[3] then
					cf = entry[3](cf, now - f.started)
				end
				p.CFrame = cf
			end
		end
		if done then
			table.remove(followers, i)
		end
	end
end

---------------------------------------------------------------- Solar Beam

local function makeBeam(classId: string)
	local colorA, colorB = U.palette(classId)
	local core = U.part(Vector3.new(1, 0.8, 0.8), CFrame.new(), Color3.new(1, 1, 1):Lerp(colorA, 0.4), Enum.Material.Neon, 0, Enum.PartType.Cylinder)
	local glow = U.part(Vector3.new(1, 2.6, 2.6), CFrame.new(), colorB, Enum.Material.Neon, 0.62, Enum.PartType.Cylinder)
	local tip = U.part(Vector3.new(2.4, 2.4, 2.4), CFrame.new(), colorA, Enum.Material.Neon, 0.25, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = colorA
	light.Range = 22
	light.Brightness = 3
	light.Parent = tip
	local sparks = U.emitter(tip, {
		Color = ColorSequence.new(colorA, colorB),
		Rate = 45,
		Speed = NumberRange.new(8, 18),
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = U.NS({ { 0, 1.1 }, { 1, 0 } }),
		Acceleration = Vector3.new(0, -20, 0),
	})
	local glint = U.part(Vector3.new(1.6, 1.6, 1.6), CFrame.new(), Color3.new(1, 1, 1), Enum.Material.Neon, 0.1, Enum.PartType.Ball)
	return { core = core, glow = glow, tip = tip, glint = glint, light = light, sparks = sparks, untilTime = 0, classId = classId }
end

-- Keep (or start) a dragon's beam pointed at `to` for `duration` seconds.
function LegendFX.beam(character: Model, to: Vector3, classId: string, duration: number)
	if not character or not character.Parent then
		return
	end
	local b = beams[character]
	if b and b.classId ~= classId then
		LegendFX.stopBeam(character)
		b = nil
	end
	if not b then
		b = makeBeam(classId)
		beams[character] = b
	end
	b.to = to
	b.untilTime = os.clock() + duration
end

function LegendFX.stopBeam(character: Model)
	local b = beams[character]
	if b then
		for _, p in ipairs({ b.core, b.glow, b.tip, b.glint }) do
			p:Destroy()
		end
		beams[character] = nil
	end
end

local function updateBeams()
	local now = os.clock()
	for character, b in pairs(beams) do
		if not character.Parent or now > b.untilTime + 0.6 then
			LegendFX.stopBeam(character)
			continue
		end
		local on = now < b.untilTime
		local from = mouthOf(character)
		local scale = character:GetAttribute("DragonScale") or 1
		local length = (b.to - from).Magnitude
		local flicker = 1 + math.sin(now * 40) * 0.12
		local w = on and 0.75 * scale * flicker or 0.05
		b.core.Size = Vector3.new(length, w, w)
		b.core.CFrame = rodCF(from, b.to)
		b.glow.Size = Vector3.new(length, w * 3.2, w * 3.2)
		b.glow.CFrame = b.core.CFrame
		b.core.Transparency = on and 0 or 1
		b.glow.Transparency = on and 0.62 or 1
		b.tip.CFrame = CFrame.new(b.to)
		b.tip.Size = Vector3.new(2.4, 2.4, 2.4) * (on and flicker or 0.1)
		b.tip.Transparency = on and 0.25 or 1
		b.glint.CFrame = CFrame.new(from)
		b.glint.Transparency = on and 0.1 or 1
		b.sparks.Enabled = on
		b.light.Brightness = on and 3 or 0
	end
end

-- Is this dragon's mouth busy (beaming, or spitting Tide Shots)? The Animator opens the jaw.
function LegendFX.mouthOpen(character: Model): boolean
	local b = beams[character]
	return (b ~= nil and os.clock() < b.untilTime) or os.clock() - (shots[character] or -10) < 0.35
end

---------------------------------------------------------------- projectiles

-- The main part (and riders: { part, offset }) of a legendary shot, or nil for anyone else's.
-- VFX.projectiles moves `main`; riders keep their offset from it.
function LegendFX.projectile(data, entry)
	local origin, dir = data.origin, entry.dir
	local look = CFrame.lookAt(origin, origin + dir)
	local size = data.size or 1
	if data.abilityId == "Breath" and data.classId == "Tidecaller" then
		-- Tide Shot: a wobbling orb of seawater shedding droplets
		if data.character then
			shots[data.character] = os.clock()
		end
		local orb = U.part(Vector3.new(size, size, size) * 1.3, look, Color3.fromRGB(150, 225, 255), Enum.Material.Glass, 0.25, Enum.PartType.Ball)
		local core = U.part(Vector3.new(size, size, size) * 0.6, look, FOAM, Enum.Material.Neon, 0.1, Enum.PartType.Ball)
		U.emitter(orb, {
			Color = ColorSequence.new(FOAM, WATER),
			LightEmission = 0.5,
			Rate = 45,
			Speed = NumberRange.new(0.5, 2),
			Lifetime = NumberRange.new(0.25, 0.45),
			Acceleration = Vector3.new(0, -30, 0),
			Size = U.NS({ { 0, size * 0.5 }, { 1, 0.05 } }),
		})
		return orb, { { core, CFrame.new() } }
	elseif data.abilityId == "TidalSurge" then
		-- a curling wall of water with a foaming crest
		local width = data.width or 20
		local body = U.part(Vector3.new(width, 5, 4), look, WATER, Enum.Material.Glass, 0.3)
		local crest = U.part(Vector3.new(width * 0.96, 3, 4.5), look, Color3.fromRGB(140, 215, 250), Enum.Material.Glass, 0.25, nil)
		local lip = U.part(Vector3.new(width * 0.94, 0.9, 1.2), look, FOAM, Enum.Material.Neon, 0.15)
		local back = U.part(Vector3.new(width * 0.9, 3.2, 3), look, DEEP, Enum.Material.Glass, 0.45)
		U.emitter(lip, {
			Color = ColorSequence.new(FOAM, Color3.fromRGB(170, 230, 255)),
			LightEmission = 0.4,
			Rate = 160,
			Speed = NumberRange.new(4, 10),
			SpreadAngle = Vector2.new(35, 35),
			EmissionDirection = Enum.NormalId.Top,
			Lifetime = NumberRange.new(0.4, 0.7),
			Acceleration = Vector3.new(0, -35, 0),
			Size = U.NS({ { 0, 1.2 }, { 1, 0.2 } }),
		})
		U.emitter(body, {
			Texture = U.SMOKE,
			Color = ColorSequence.new(FOAM),
			LightEmission = 0.2,
			Rate = 40,
			Speed = NumberRange.new(2, 5),
			Lifetime = NumberRange.new(0.6, 0.9),
			Size = U.NS({ { 0, 3 }, { 1, 6 } }),
			Transparency = U.NS({ { 0, 0.55 }, { 1, 1 } }),
		})
		-- (the crest leans forward over the front of the wave)
		return body, {
			{ crest, CFrame.new(0, 3.3, -1.2) * CFrame.Angles(math.rad(-25), 0, 0) },
			{ lip, CFrame.new(0, 4.6, -2.6) },
			{ back, CFrame.new(0, -0.6, 2.8) },
		}
	elseif data.abilityId == "Sunspear" then
		local spear = U.part(Vector3.new(0.55, 0.55, size * 6), look, SUN, Enum.Material.Neon, 0)
		local halo = U.part(Vector3.new(1.5, 1.5, size * 7.5), look, GOLD, Enum.Material.Neon, 0.6)
		local head = U.part(Vector3.new(1.2, 1.2, 1.2), look, Color3.new(1, 1, 1), Enum.Material.Neon, 0, Enum.PartType.Ball)
		U.emitter(spear, {
			Color = ColorSequence.new(SUN, GOLD),
			Rate = 60,
			Speed = NumberRange.new(1, 3),
			Lifetime = NumberRange.new(0.25, 0.4),
			Size = U.NS({ { 0, 1.2 }, { 1, 0 } }),
		})
		return spear, { { halo, CFrame.new() }, { head, CFrame.new(0, 0, -size * 3) } }
	end
	return nil
end

-- A legendary shot landing. Returns true when it was one (VFX skips its explosion).
function LegendFX.projectileHit(data): boolean
	if data.abilityId == "Breath" and data.classId == "Tidecaller" then
		App.VFX.splash(data.pos)
		return true
	elseif data.abilityId == "TidalSurge" then
		App.VFX.splash(data.pos, true)
		U.burst(data.pos, FOAM, WATER, 30, 25, 2.5)
		U.ring(data.pos - Vector3.new(0, 2.5, 0), 14, FOAM, 0.7, 0.6)
		return true
	elseif data.abilityId == "Sunspear" then
		U.burst(data.pos, SUN, GOLD, 25, 30, 1.6, U.SPARKLE)
		U.flash(data.pos, SUN, 25, 0.4)
		return true
	end
	return false
end

---------------------------------------------------------------- whirlpools, geysers, tentacles

-- Spiral arms of water turning on the ground: `inward` pulls them toward the middle as they go.
local function whirlpool(pos: Vector3, radius: number, duration: number, dark: boolean?)
	local arms = {}
	local base = disc(pos + Vector3.new(0, 0.2, 0), radius, dark and DEEP or WATER, Enum.Material.Glass, 0.45)
	local eye = disc(pos + Vector3.new(0, 0.3, 0), radius * 0.25, dark and Color3.fromRGB(8, 25, 45) or DEEP, Enum.Material.Neon, 0.2)
	for k = 1, 6 do
		for seg = 1, 5 do
			local p = U.part(Vector3.new(0.5, 0.35, radius * 0.32), CFrame.new(pos), seg % 2 == 0 and FOAM or Color3.fromRGB(150, 220, 250), Enum.Material.Neon, 0.25)
			table.insert(arms, { part = p, arm = k, seg = seg })
		end
	end
	local spray = U.emitter(eye, {
		Color = ColorSequence.new(FOAM, WATER),
		Rate = 30,
		Speed = NumberRange.new(4, 9),
		EmissionDirection = Enum.NormalId.Right, -- (up, on a standing cylinder)
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -30, 0),
		Lifetime = NumberRange.new(0.5, 0.8),
		Size = U.NS({ { 0, 0.9 }, { 1, 0.1 } }),
	})
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > duration then
			conn:Disconnect()
			spray.Enabled = false
			for _, a in ipairs(arms) do
				fadeOut(a.part, 0.4)
			end
			fadeOut(base, 0.5)
			fadeOut(eye, 0.5)
			return
		end
		local grow = math.min(1, t / 0.3)
		for _, a in ipairs(arms) do
			local f = a.seg / 5
			local r = radius * (0.2 + 0.8 * f) * grow
			local ang = a.arm / 6 * math.pi * 2 + f * 2.2 - t * 4
			local at = pos + Vector3.new(math.cos(ang) * r, 0.5, math.sin(ang) * r)
			-- each piece lies along the spiral
			a.part.CFrame = CFrame.lookAt(at, at + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
		end
	end)
end

local function geyser(pos: Vector3, radius: number)
	local column = U.part(Vector3.new(1, radius * 0.7, radius * 0.7), upright(pos), Color3.fromRGB(160, 225, 255), Enum.Material.Glass, 0.25, Enum.PartType.Cylinder)
	local height = 26
	U.tween(column, 0.18, { Size = Vector3.new(height, radius * 0.8, radius * 0.8), CFrame = upright(pos + Vector3.new(0, height / 2, 0)) })
	task.delay(0.7, function()
		U.tween(column, 0.4, { Size = Vector3.new(2, radius * 1.2, radius * 1.2), CFrame = upright(pos + Vector3.new(0, 1, 0)), Transparency = 1 })
	end)
	Debris:AddItem(column, 1.2)
	local anchor = U.anchorAt(pos + Vector3.new(0, height, 0))
	local spray = U.emitter(anchor, {
		Color = ColorSequence.new(FOAM, WATER),
		Speed = NumberRange.new(10, 22),
		Acceleration = Vector3.new(0, -50, 0),
		Lifetime = NumberRange.new(0.8, 1.2),
		Size = U.NS({ { 0, 1.4 }, { 1, 0.3 } }),
	})
	spray:Emit(60)
	Debris:AddItem(anchor, 2)
	App.VFX.splash(pos, true)
	U.ring(pos, radius, FOAM, 0.6, 0.6)
end

-- Tentacles bursting out of the ground round the spot, curling in and slamming down on it.
local function kraken(pos: Vector3, radius: number)
	local skin = Color3.fromRGB(90, 60, 130)
	local under = Color3.fromRGB(230, 170, 200)
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2 + rand(-0.2, 0.2)
		local base = pos + Vector3.new(math.cos(a) * radius * 0.8, 0, math.sin(a) * radius * 0.8)
		local segs = 7
		local height = rand(16, 22)
		for i = 1, segs do
			local f = i / segs
			local size = (2.8 - f * 2.1)
			local seg = U.part(Vector3.new(size, size, size), CFrame.new(base - Vector3.new(0, 4, 0)), skin, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
			local cup = U.part(Vector3.new(size * 0.45, size * 0.45, size * 0.45), CFrame.new(base - Vector3.new(0, 4, 0)), under, Enum.Material.SmoothPlastic, 0, Enum.PartType.Ball)
			-- rise: up and curling over toward the middle; then slam onto it
			local up = base + Vector3.new(0, f * height, 0) + (pos - base) * (f * f * 0.6)
			local slam = base:Lerp(pos, f * 0.9) + Vector3.new(0, math.sin(f * math.pi) * 4 + 1, 0)
			local inward = (pos - base).Unit
			U.tween(seg, 0.3, { CFrame = CFrame.new(up) }, Enum.EasingStyle.Back)
			U.tween(cup, 0.3, { CFrame = CFrame.new(up + inward * size * 0.4) }, Enum.EasingStyle.Back)
			task.delay(0.55, function()
				U.tween(seg, 0.15, { CFrame = CFrame.new(slam) })
				U.tween(cup, 0.15, { CFrame = CFrame.new(slam + Vector3.new(0, -size * 0.3, 0)) })
			end)
			task.delay(1.6, function()
				U.tween(seg, 0.5, { CFrame = CFrame.new(slam - Vector3.new(0, 6, 0)), Transparency = 1 })
				U.tween(cup, 0.5, { CFrame = CFrame.new(slam - Vector3.new(0, 6, 0)), Transparency = 1 })
			end)
			Debris:AddItem(seg, 2.2)
			Debris:AddItem(cup, 2.2)
		end
		task.delay(0.7, function()
			App.VFX.splash(base:Lerp(pos, 0.6), true)
		end)
	end
	local pool = disc(pos + Vector3.new(0, 0.2, 0), radius, DEEP, Enum.Material.Glass, 0.4)
	task.delay(1.8, function()
		fadeOut(pool, 0.5)
	end)
	task.delay(0.7, function()
		U.ring(pos, radius * 1.2, FOAM, 0.6, 1)
		U.flash(pos, Color3.fromRGB(150, 110, 255), 40, 0.5)
	end)
end

---------------------------------------------------------------- sunlight

-- A pillar of sunfire standing on the spot for `duration` seconds.
local function sunPillar(pos: Vector3, radius: number, duration: number)
	local height = 140
	local outer = U.part(Vector3.new(height, radius * 2, radius * 2), upright(pos + Vector3.new(0, height / 2, 0)), GOLD, Enum.Material.Neon, 1, Enum.PartType.Cylinder)
	local inner = U.part(Vector3.new(height, radius * 0.7, radius * 0.7), upright(pos + Vector3.new(0, height / 2, 0)), SUN, Enum.Material.Neon, 1, Enum.PartType.Cylinder)
	local floor = disc(pos + Vector3.new(0, 0.25, 0), radius, SUN, Enum.Material.Neon, 1)
	U.tween(outer, 0.3, { Transparency = 0.72 })
	U.tween(inner, 0.3, { Transparency = 0.3 })
	U.tween(floor, 0.3, { Transparency = 0.35 })
	local light = Instance.new("PointLight")
	light.Color = SUN
	light.Range = radius * 3
	light.Brightness = 4
	light.Parent = floor
	local motes = U.emitter(floor, {
		Color = ColorSequence.new(SUN, GOLD),
		Rate = 70,
		Speed = NumberRange.new(6, 16),
		EmissionDirection = Enum.NormalId.Right, -- up
		SpreadAngle = Vector2.new(25, 25),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = U.NS({ { 0, 1.2 }, { 1, 0 } }),
	})
	task.delay(duration, function()
		motes.Enabled = false
		fadeOut(outer, 0.5)
		fadeOut(inner, 0.5)
		fadeOut(floor, 0.6)
	end)
end

-- Zenith: a small sun drops out of the sky, then a column of light slams down.
local function zenith(pos: Vector3, radius: number, delay: number)
	local orb = U.part(Vector3.new(4, 4, 4), CFrame.new(pos + Vector3.new(0, 90, 0)), SUN, Enum.Material.Neon, 0.05, Enum.PartType.Ball)
	local corona = U.part(Vector3.new(8, 8, 8), CFrame.new(pos + Vector3.new(0, 90, 0)), GOLD, Enum.Material.Neon, 0.6, Enum.PartType.Ball)
	U.tween(orb, delay, { Size = Vector3.new(9, 9, 9), CFrame = CFrame.new(pos + Vector3.new(0, 12, 0)) }, Enum.EasingStyle.Quad)
	U.tween(corona, delay, { Size = Vector3.new(20, 20, 20), CFrame = CFrame.new(pos + Vector3.new(0, 12, 0)) }, Enum.EasingStyle.Quad)
	Debris:AddItem(orb, delay)
	Debris:AddItem(corona, delay)
	task.delay(delay, function()
		local column = U.part(Vector3.new(160, radius * 2.2, radius * 2.2), upright(pos + Vector3.new(0, 80, 0)), SUN, Enum.Material.Neon, 0.1, Enum.PartType.Cylinder)
		U.tween(column, 0.8, { Size = Vector3.new(160, 0.5, 0.5), Transparency = 1 })
		Debris:AddItem(column, 0.85)
		for k = 1, 12 do
			local a = k / 12 * math.pi * 2
			local ray = U.part(Vector3.new(0.8, 0.5, radius * 0.6), CFrame.lookAt(pos + Vector3.new(0, 1, 0), pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 10 + Vector3.new(0, 1, 0)), GOLD, Enum.Material.Neon, 0.1)
			U.tween(ray, 0.5, { CFrame = ray.CFrame * CFrame.new(0, 0, -radius * 1.1), Transparency = 1 })
			Debris:AddItem(ray, 0.55)
		end
		U.flash(pos, SUN, 80, 1)
	end)
end

-- Rays of light shooting out from a point (Solar Flare, Supernova).
local function sunRays(pos: Vector3, radius: number, count: number, time: number)
	for k = 1, count do
		local a = k / count * math.pi * 2
		local dir = Vector3.new(math.cos(a), rand(-0.15, 0.25), math.sin(a)).Unit
		local ray = U.part(Vector3.new(0.6, 0.6, radius * 0.5), CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -radius * 0.25), k % 2 == 0 and SUN or GOLD, Enum.Material.Neon, 0.05)
		U.tween(ray, time, { CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -radius), Transparency = 1 })
		Debris:AddItem(ray, time + 0.05)
	end
end

---------------------------------------------------------------- hooks from VFX / SpellFX

-- Returns true when it drew the whole strike (VFX skips its own blast).
function LegendFX.strike(data): boolean
	local pos, radius, delay = data.pos, data.radius or 10, data.delay or 0
	local lasting = (data.pulses or 1) * (data.interval or 0) -- (how long a lasting one keeps going)
	local style = data.style
	if style == "whirlpool" then
		task.delay(delay * 0.5, function()
			whirlpool(pos, radius, delay * 0.5 + 1.2, false)
		end)
		task.delay(delay, function()
			App.VFX.splash(pos, true)
		end)
		return true
	elseif style == "maelstrom" then
		whirlpool(pos, radius, delay + lasting + 0.3, true)
		for i = 0, (data.pulses or 1) - 1 do
			task.delay(delay + i * (data.interval or 0.5), function()
				U.ring(pos, radius, FOAM, 0.5, 0.6)
				App.VFX.splash(pos + Vector3.new(rand(-1, 1) * radius * 0.5, 0, rand(-1, 1) * radius * 0.5), true)
			end)
		end
		return true
	elseif style == "geyser" then
		task.delay(delay, function()
			geyser(pos, radius)
		end)
		return true
	elseif style == "kraken" then
		task.delay(math.max(0, delay - 0.3), function()
			kraken(pos, radius)
		end)
		return true
	elseif style == "sunfall" then
		task.delay(delay, function()
			sunPillar(pos, radius, math.max(lasting, 0.5))
		end)
		return true
	elseif style == "zenith" then
		zenith(pos, radius, delay)
		task.delay(delay, function()
			U.ring(pos, radius * 1.2, GOLD, 0.7, 1)
			App.VFX.explosion(pos + Vector3.new(0, 2, 0), radius, SUN, GOLD)
		end)
		return true
	end
	return false
end

function LegendFX.nova(data)
	local id = data.abilityId
	if id == "SolarFlare" then
		sunRays(data.pos, data.radius, 16, 0.35)
	elseif id == "Supernova" then
		local core = U.part(Vector3.new(3, 3, 3), CFrame.new(data.pos), Color3.new(1, 1, 1), Enum.Material.Neon, 0, Enum.PartType.Ball)
		U.tween(core, 0.45, { Size = Vector3.new(data.radius * 2, data.radius * 2, data.radius * 2), Transparency = 1 })
		Debris:AddItem(core, 0.5)
		sunRays(data.pos, data.radius * 1.3, 24, 0.6)
		task.delay(0.15, function()
			U.ring(data.pos - Vector3.new(0, 2.5, 0), data.radius * 1.2, SUN, 0.8, 1.5)
		end)
	elseif id == "Undertow" then
		local ground = data.pos - Vector3.new(0, 3, 0)
		whirlpool(ground, data.radius, 1.2, true)
	end
end

-- Lasting buffs with their own look. Returns true when it drew one (VFX skips its sparkles).
function LegendFX.buff(data): boolean
	local character = data.character
	local duration = data.duration or 6
	if data.abilityId == "AbyssalShell" then
		follow(character, duration, function(f, root)
			local scale = character:GetAttribute("DragonScale") or 1
			local d = 15 * scale
			local shell = U.part(Vector3.new(d, d * 0.8, d * 1.1), root.CFrame, Color3.fromRGB(60, 160, 220), Enum.Material.Glass, 0.6, Enum.PartType.Ball)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = shell
			table.insert(f.parts, { shell, CFrame.new(0, 0.5 * scale, 0), function(cf, t)
				return cf * CFrame.Angles(0, t * 0.6, 0)
			end })
			local bubbles = U.emitter(root, {
				Color = ColorSequence.new(FOAM, WATER),
				LightEmission = 0.4,
				Rate = 25,
				Speed = NumberRange.new(2, 5),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 6, 0),
				Lifetime = NumberRange.new(1, 1.6),
				Size = U.NS({ { 0, 0.5 }, { 1, 0.9 } }),
				Transparency = U.NS({ { 0, 0.3 }, { 1, 1 } }),
			})
			table.insert(f.parts, { bubbles })
		end)
		return true
	elseif data.abilityId == "PhoenixForm" then
		follow(character, duration, function(f, root)
			-- the wings catch fire (emitters on the wing joints flap along with them)
			for _, name in ipairs({ "WingHandL", "WingHandR", "WingRootL", "WingRootR" }) do
				local joint = character:FindFirstChild(name, true)
				if joint and joint:IsA("BasePart") then
					local flames = U.emitter(joint, {
						Texture = U.FIRE,
						Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 80, 10)),
						LightEmission = 1,
						Rate = 55,
						Speed = NumberRange.new(2, 6),
						Lifetime = NumberRange.new(0.4, 0.8),
						Size = U.NS({ { 0, 3 }, { 1, 0.4 } }),
						Transparency = U.NS({ { 0, 0.15 }, { 1, 1 } }),
						Acceleration = Vector3.new(0, 12, 0),
					})
					table.insert(f.parts, { flames })
				end
			end
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 150, 50)
			light.Range = 26
			light.Brightness = 2.5
			light.Parent = root
			table.insert(f.parts, { light })
			local ember = U.emitter(root, {
				Color = ColorSequence.new(SUN, GOLD),
				Rate = 30,
				Speed = NumberRange.new(3, 8),
				Lifetime = NumberRange.new(0.8, 1.2),
				Acceleration = Vector3.new(0, 10, 0),
				Size = U.NS({ { 0, 0.8 }, { 1, 0 } }),
			})
			table.insert(f.parts, { ember })
		end)
		return true
	end
	return false
end

function LegendFX.init(app)
	App = app
	U = App.VFX.util
	RunService.RenderStepped:Connect(function()
		updateBeams()
		updateFollowers()
	end)
end

return LegendFX
