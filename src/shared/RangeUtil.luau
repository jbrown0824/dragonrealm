-- Where a practice target is at a given moment (Config/Range patterns). Shared so the server
-- (hit checks) and every client (drawing the targets) agree without sending positions around:
-- the server stamps each target with its pattern and birth time, and both sides compute from
-- workspace:GetServerTimeNow().
--
-- t = { pattern, x, y, z (home spot), speed, amp (how far across the lane), phase, born, life? }

local RangeUtil = {}

-- A triangle wave between -1 and 1 (for sprinting straight back and forth).
local function triangle(u: number): number
	local k = u % 4
	return k < 2 and (k - 1) or (3 - k)
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
		z += amp * triangle(age * (t.speed or 0) / amp * 2 + t.phase)
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
