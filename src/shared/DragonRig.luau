-- Procedural dragon poses. Given a dragon's rig (read from attributes DragonBuilder sets) and
-- what it's doing, returns a Motor6D.Transform for every joint. The client Animator applies
-- these every frame; keeping the math here (not in the Animator) lets it be previewed offline.
--
-- Motor frames are world-aligned at build time with the dragon facing -Z, so:
--   Rx(+) raises anything pointing forward (neck/head) and swings legs forward
--   Rz(+) raises the right wing; Ry(-) sweeps the right wing back (left wing is mirrored)

local DragonRig = {}

local function A(x, y, z)
	return CFrame.Angles(x, y, z)
end

function DragonRig.info(model)
	return {
		neck = model:GetAttribute("RigNeck") or 1,
		tail = model:GetAttribute("RigTail") or 4,
		legs = model:GetAttribute("RigLegs") or 4,
		curl = model:GetAttribute("RigCurl") == true,
		frill = model:GetAttribute("RigFrill") == true,
		scale = model:GetAttribute("DragonScale") or 1,
	}
end

-- mode: "ground" | "jump" (rising, not flying) | "fall" (dropping, not flying) | "fly" |
-- "downed" (knocked out or dead: the server lays the body on its belly, see WorldUtil.layDragon)
function DragonRig.modeFor(flying: boolean, vy: number, downed: boolean?): string
	if downed then
		return "downed"
	elseif flying then
		return "fly"
	elseif vy > 3 then
		return "jump"
	elseif vy < -4 then
		return "fall"
	end
	return "ground"
end

-- Knocked out cold: sprawled flat with its legs splayed out to the sides, neck and head resting
-- on the ground turned to one side, wings drooping open, tail limp in a curve and eyes shut.
local function downedPose(info)
	local out = {}
	local s = info.scale
	out.BodyJoint = CFrame.new()
	for i = 1, info.neck do
		out["Neck" .. i] = A(-0.16, 0.22 / info.neck, 0)
	end
	out.Head = A(-0.12, 0.25, 0.25)
	out.Jaw = A(-0.15, 0, 0)
	out.LidL = CFrame.new(0, -0.3 * s, 0)
	out.LidR = CFrame.new(0, -0.3 * s, 0)
	if info.frill then
		out.Frill = A(1.25, 0, 0)
	end
	out.WingR = A(0, -0.3, 0) * A(0, 0, -0.1)
	out.WingL = A(0, 0.3, 0) * A(0, 0, 0.1)
	out.WingR2 = A(0, -0.25, 0) * A(0, 0, -0.3)
	out.WingL2 = A(0, 0.25, 0) * A(0, 0, 0.3)
	for i = 1, info.tail do
		out["Tail" .. i] = A(0.02, 0.16, 0)
	end
	local legKeys = info.legs == 2 and { "BL", "BR" } or { "FL", "FR", "BL", "BR" }
	for _, key in ipairs(legKeys) do
		local front = key:sub(1, 1) == "F"
		local side = key:sub(2, 2) == "R" and 1 or -1 -- right legs splay toward +X
		out["Leg" .. key] = A(0, 0, side * 1.25) * A(front and -0.5 or 0.5, 0, 0)
		out["Knee" .. key] = A(front and -0.3 or 0.3, 0, 0)
	end
	return out
end

-- state: { t = seconds (add a per-dragon offset), mode, vy, speed, breathing, blink }
function DragonRig.pose(info, st)
	if st.mode == "downed" then
		return downedPose(info)
	end
	local out = {}
	local t = st.t
	local s = info.scale
	local mode = st.mode
	local breathing = st.breathing == true
	local airborne = mode ~= "ground"

	-- Body: gentle breathing bob on the ground, pitch with climb/dive in the air.
	local pitch = mode == "fly" and math.clamp((st.vy or 0) / 70, -0.3, 0.3) or 0
	local bob = mode == "ground" and math.sin(t * 2.1) * 0.05 * s or 0
	out.BodyJoint = CFrame.new(0, bob, 0) * A(pitch, 0, 0)

	-- Neck, head, jaw: look around idly, lunge forward and open wide to breathe fire.
	local sway = math.sin(t * 0.55) * 0.09
	for i = 1, info.neck do
		local p
		if breathing then
			p = -0.1
		elseif mode == "fly" then
			p = -0.07
		else
			p = math.sin(t * 0.9 + i) * 0.03
		end
		out["Neck" .. i] = A(p, sway * 1.5 / info.neck, 0)
	end
	out.Head = A(breathing and 0.12 or math.sin(t * 0.7) * 0.04, sway * 0.4, 0)
	out.Jaw = A(breathing and -0.55 or -math.max(0, math.sin(t * 0.35) - 0.93) * 2, 0, 0)
	local lid = st.blink and -0.3 * s or 0
	out.LidL = CFrame.new(0, lid, 0)
	out.LidR = CFrame.new(0, lid, 0)
	if info.frill then
		out.Frill = A(breathing and 0 or 1.25, 0, 0)
	end

	-- Wings (right side values; left is mirrored)
	local flapZ, sweepY, elbowY, elbowZ
	if mode == "fly" then
		local glide = (st.vy or 0) < -10
		local f = glide and 0 or math.sin(t * 6.5)
		flapZ, sweepY = glide and 0.18 or 0.15 + 0.85 * f, 0.05
		elbowY, elbowZ = glide and 0 or -0.35 * math.max(0, f), 0
	elseif mode == "jump" then
		local f = math.sin(t * 11)
		flapZ, sweepY = 0.3 + 1.0 * f, 0.1
		elbowY, elbowZ = -0.35 * math.max(0, f), 0
	elseif mode == "fall" then
		flapZ, sweepY = 0.38 + math.sin(t * 5) * 0.08, 0
		elbowY, elbowZ = -0.1, 0
	else
		-- folded: elbows raised above the back, hand folded down along the flank
		flapZ, sweepY = 0.7 + math.sin(t * 2.1) * 0.03, -0.9
		elbowY, elbowZ = -0.55, -1.05
	end
	out.WingR = A(0, sweepY, 0) * A(0, 0, flapZ)
	out.WingL = A(0, -sweepY, 0) * A(0, 0, -flapZ)
	out.WingR2 = A(0, elbowY, 0) * A(0, 0, elbowZ)
	out.WingL2 = A(0, -elbowY, 0) * A(0, 0, -elbowZ)

	-- Tail: travelling S-wave; Venomspine's curls up over its back like a scorpion.
	for i = 1, info.tail do
		local yaw = math.sin(t * 1.7 - i * 0.55) * (mode == "fly" and 0.04 or 0.09)
		local p
		if info.curl then
			p = i <= 2 and -0.08 or -0.36
			if mode == "fly" then
				p *= 0.5
			end
		else
			p = mode == "fly" and -0.02 or 0.02
		end
		out["Tail" .. i] = A(p, yaw, 0)
	end

	-- Legs: trot on the ground, tuck in flight, dangle when jumping/falling.
	local legKeys = info.legs == 2 and { "BL", "BR" } or { "FL", "FR", "BL", "BR" }
	for _, key in ipairs(legKeys) do
		local front = key:sub(1, 1) == "F"
		local hip, knee = 0, 0
		if airborne then
			hip = front and -0.6 or -0.8
			knee = front and -0.9 or 1.0
			if mode ~= "fly" then
				hip *= 0.5
				knee *= 0.5
			end
		elseif (st.speed or 0) > 1 then
			local amt = math.clamp(st.speed / 16, 0, 1)
			local ph = t * (5 + st.speed * 0.22) + ((key == "FL" or key == "BR") and 0 or math.pi)
			hip = math.sin(ph) * 0.55 * amt
			knee = (front and -1 or 1) * math.max(0, math.cos(ph)) * 0.9 * amt
		end
		out["Leg" .. key] = A(hip, 0, 0)
		out["Knee" .. key] = A(knee, 0, 0)
	end
	return out
end

return DragonRig
