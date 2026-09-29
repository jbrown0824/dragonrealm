-- Keeps the day/night clock (shared/DayNight). It owns the workspace attributes "DayOffset" (the
-- clock itself: every client draws its own sky from it, see Controllers/Sky) and "Night", and
-- fires `nightfall` / `daybreak` for other services (RaidService). Admins can set the hour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local DayNight = require(Shared.DayNight)
local Signal = require(Shared.Signal)

local DayNightService = {}

DayNightService.nightfall = Signal.new() -- (dayNumber)
DayNightService.daybreak = Signal.new() -- (dayNumber)

local offset = 0
local night = false

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Seconds since dawn.
function DayNightService.phase(): number
	return DayNight.phase(serverNow(), offset)
end

function DayNightService.isNight(): boolean
	return night
end

function DayNightService.dayNumber(): number
	return DayNight.dayNumber(serverNow(), offset)
end

-- Seconds until dusk (by day) or dawn (by night).
function DayNightService.untilChange(): number
	return DayNight.untilChange(DayNightService.phase())
end

local function check()
	local isNight = DayNight.isNight(DayNightService.phase())
	if isNight == night then
		return
	end
	night = isNight
	workspace:SetAttribute("Night", night)
	if night then
		DayNightService.nightfall:Fire(DayNightService.dayNumber())
	else
		DayNightService.daybreak:Fire(DayNightService.dayNumber())
	end
end

-- Jump the clock to an hour (0-24). Crossing dusk or dawn fires the usual signals.
function DayNightService.setHour(hour: number)
	offset = DayNight.offsetFor(serverNow(), hour % 24)
	workspace:SetAttribute("DayOffset", offset)
	check()
end

function DayNightService.init()
	offset = DayNight.offsetFor(serverNow(), Game.START_HOUR)
	night = DayNight.isNight(DayNightService.phase())
	workspace:SetAttribute("DayOffset", offset)
	workspace:SetAttribute("Night", night)
end

function DayNightService.start()
	while true do
		task.wait(0.5)
		check()
	end
end

return DayNightService
