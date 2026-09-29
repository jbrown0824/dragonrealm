-- Where a practice target is at a given moment (Config/Range patterns). Shared so the server
-- (hit checks) and every client (drawing the targets) agree without sending positions around:
-- the server stamps each target with its pattern and birth time, and both sides compute from
-- workspace:GetServerTimeNow().
--
-- t = { pattern, x, y, z (home spot), speed, amp (how far across the lane), phase, born, life? }

local RangeUtil = {}

local SPRINT_REST = 0.7 -- a sprinter catches its breath this long at each side of the lane

-- A sprinter's place across its lane (-1..1): it rests at one side, dashes across at `speed`
-- studs a second, rests, and dashes back. The rests give younger players a beat to line up.
local function sprint(age: number, speed: number, amp: number, phase: number): number
	local dash = 2 * amp / math.max(1, speed)
	local leg = dash + SPRINT_REST
	local u = (age + phase / (math.pi * 2) * 2 * leg) % (2 * leg)
	if u < SPRINT_REST then
		return -1
	elseif u < leg then
		return -1 + 2 * (u - SPRINT_REST) / dash
	elseif u < leg + SPRINT_REST then
		return 1
	end
	return 1 - 2 * (u - leg - SPRINT_REST) / dash
end

function RangeUtil.position(t, now: number): Vector3
	local age = now - t.born
	local amp = math.max(0.5, t.amp or 8)
	local w = (t.speed or 0) / amp -- keeps the speed along the path about `speed` studs a second
	local x, y, z = t.x, t.y, t.z
	local pattern = t.pattern
	if pattern == "slide" then
		z += amp * math.sin(age * w + t.phase)
	elseif pattern == "bob" then
		z += amp * math.sin(age * w + t.phase)
		y += 3 * math.sin(age * 2.3 + t.phase)
	elseif pattern == "zigzag" then
		z += amp * math.sin(age * w + t.phase)
		x += amp * 0.5 * math.sin(age * w * 1.7 + t.phase * 2)
	elseif pattern == "sprint" then
		z += amp * sprint(age, t.speed or 0, amp, t.phase)
	elseif pattern == "float" then
		z += amp * math.cos(age * w + t.phase)
		y += amp * 0.4 * math.sin(age * w + t.phase)
		x += 3 * math.sin(age * w * 0.5)
	end
	return Vector3.new(x, y, z)
end

-- Popups vanish after their `life`.
function RangeUtil.expired(t, now: number): boolean
	return t.life ~= nil and now - t.born >= t.life
end

-- Read a target's parameters back from its model's attributes (clients).
function RangeUtil.fromModel(model: Instance)
	return {
		pattern = model:GetAttribute("Pattern"),
		x = model:GetAttribute("X0") or 0,
		y = model:GetAttribute("Y0") or 0,
		z = model:GetAttribute("Z0") or 0,
		speed = model:GetAttribute("Speed") or 0,
		amp = model:GetAttribute("Amp") or 8,
		phase = model:GetAttribute("Phase") or 0,
		born = model:GetAttribute("Born") or 0,
		life = model:GetAttribute("Life"),
	}
end

return RangeUtil
