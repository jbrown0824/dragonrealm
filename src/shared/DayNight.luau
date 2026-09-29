-- The day/night clock, shared so the server (raids) and every client (sky, lamps, the clock on
-- the minimap) always agree. It runs off server time plus an offset the server keeps in the
-- workspace attribute "DayOffset" (admins can skip ahead), so nothing needs to be sent around.
--
-- One cycle is Game.DAY_SECONDS of day (dawn to dusk) then Game.NIGHT_SECONDS of night. A point
-- in the cycle ("t") counts seconds from dawn.

local Game = require(script.Parent.Config.Game)

local DayNight = {}

function DayNight.cycleLength(): number
	return Game.DAY_SECONDS + Game.NIGHT_SECONDS
end

-- Seconds since dawn for a server time and offset.
function DayNight.phase(serverNow: number, offset: number): number
	return (serverNow + offset) % DayNight.cycleLength()
end

-- How many dawns have passed (counts days; a night belongs to the day before it).
function DayNight.dayNumber(serverNow: number, offset: number): number
	return math.floor((serverNow + offset) / DayNight.cycleLength())
end

function DayNight.isNight(t: number): boolean
	return t >= Game.DAY_SECONDS
end

-- Lighting.ClockTime for a point in the cycle.
function DayNight.clockTime(t: number): number
	local dayHours = Game.DUSK_HOUR - Game.DAWN_HOUR
	if t < Game.DAY_SECONDS then
		return Game.DAWN_HOUR + dayHours * t / Game.DAY_SECONDS
	end
	return (Game.DUSK_HOUR + (24 - dayHours) * (t - Game.DAY_SECONDS) / Game.NIGHT_SECONDS) % 24
end

-- The offset that puts the clock at `hour` right now (hour between dawn and dusk = daytime).
function DayNight.offsetFor(serverNow: number, hour: number): number
	local t
	local dayHours = Game.DUSK_HOUR - Game.DAWN_HOUR
	local sinceDawn = (hour - Game.DAWN_HOUR) % 24
	if sinceDawn < dayHours then
		t = sinceDawn / dayHours * Game.DAY_SECONDS
	else
		t = Game.DAY_SECONDS + (sinceDawn - dayHours) / (24 - dayHours) * Game.NIGHT_SECONDS
	end
	return t - serverNow
end

-- Seconds until the light changes (dusk by day, dawn by night).
function DayNight.untilChange(t: number): number
	if t < Game.DAY_SECONDS then
		return Game.DAY_SECONDS - t
	end
	return DayNight.cycleLength() - t
end

-- How dark it is, 0 (full day) to 1 (deep night), easing through dusk and dawn.
function DayNight.darkness(clock: number): number
	local function ramp(a: number, b: number, x: number): number
		local k = math.clamp((x - a) / (b - a), 0, 1)
		return k * k * (3 - 2 * k)
	end
	if clock >= 12 then
		return ramp(Game.DUSK_HOUR - 1, Game.DUSK_HOUR + 1.5, clock)
	end
	return 1 - ramp(Game.DAWN_HOUR - 1.5, Game.DAWN_HOUR + 1, clock)
end

-- The clock right now, as seen from this machine.
function DayNight.now(): (number, number)
	local offset = workspace:GetAttribute("DayOffset") or 0
	local t = DayNight.phase(workspace:GetServerTimeNow(), offset)
	return t, DayNight.clockTime(t)
end

-- "7:30 PM" style.
function DayNight.format(clock: number): string
	local h = math.floor(clock) % 24
	local m = math.floor((clock % 1) * 60)
	local suffix = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

return DayNight
