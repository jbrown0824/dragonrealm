-- Water depth check: builds the world and measures every lake and the river.
--   * no water column may hang over the void (a bowl carved below the lake bed)
--   * at most MAX_SHALLOW of a lake's water may be shallower than 3 studs (you'd see the bottom)
--   * the longships need at least 4 studs of water under their whole footprint
-- Prints a line per water body and "N water problems" at the end.
local WorldBuilder = require(__proxy("Server/World/WorldBuilder"))
local Zones = require(__proxy("Shared/Config/Zones"))
WorldBuilder.build()
TERRAIN_PREPARE()

local MAX_SHALLOW = 0.15
local problems = 0

local function measure(name: string, x0: number, x1: number, z0: number, z1: number)
	local n, shallow, total, deepest, void = 0, 0, 0, 0, 0
	for z = z0, z1, 2 do
		for x = x0, x1, 2 do
			local top, mat = TERRAIN_TOP(x, z, 500, false)
			if mat == "Water" then
				local bed = TERRAIN_TOP(x, z, 500, true)
				n += 1
				if not bed then
					void += 1
				else
					local d = top - bed
					total += d
					deepest = math.max(deepest, d)
					if d < 3 then
						shallow += 1
					end
				end
			end
		end
	end
	local share = n > 0 and shallow / n or 0
	local ok = void == 0 and share <= MAX_SHALLOW
	if not ok then
		problems += 1
	end
	print(string.format("%s %-12s water %5d  avg depth %5.1f  max %5.1f  shallow %4.1f%%  over the void %d", ok and "ok  " or "BAD ", name, n, n > 0 and total / n or 0, deepest, share * 100, void))
end

for _, lake in ipairs(Zones.Lakes) do
	local c = lake.center
	measure(lake.id, c.X - 90, c.X + 90, c.Z - 140, c.Z + 140)
end
measure("River", -640, 640, 230, 330)

-- Longships (Camps.luau): 34 long and 7.5 wide, keel about 3 below the waterline.
for _, ship in ipairs(workspace:GetDescendants()) do
	if ship.Name == "Longship" then
		-- the keel (the longest part) gives the ship's position and heading
		local keel = nil
		for _, part in ipairs(ship:GetDescendants()) do
			if part:IsA("BasePart") and (not keel or part.Size.Z > keel.Size.Z) then
				keel = part
			end
		end
		local cf = keel.CFrame
		local shallowest = math.huge
		for dz = -15, 15, 3 do
			for dx = -3, 3, 3 do
				local p = cf * Vector3.new(dx, 0, dz)
				local top = TERRAIN_TOP(p.X, p.Z, 500, false) or -99
				local bed = TERRAIN_TOP(p.X, p.Z, 500, true) or -999
				shallowest = math.min(shallowest, top - bed)
			end
		end
		local ok = shallowest >= 4
		if not ok then
			problems += 1
		end
		print(string.format("%s longship at %d, %d: shallowest water under it %.1f", ok and "ok  " or "BAD ", cf.Position.X, cf.Position.Z, shallowest))
	end
end
print(problems .. " water problems")
