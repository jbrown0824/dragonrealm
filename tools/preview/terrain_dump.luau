-- Build the world and dump a top-down terrain grid ("T x z height material") plus every part.
-- Region and step can be set by a header: TERRAIN_MIN_X, TERRAIN_MAX_X, TERRAIN_MIN_Z, TERRAIN_MAX_Z, TERRAIN_STEP
local WorldBuilder = require(__proxy("Server/World/WorldBuilder"))
WorldBuilder.build()
TERRAIN_PREPARE()
local x0, x1 = TERRAIN_MIN_X or -560, TERRAIN_MAX_X or 560
local z0, z1 = TERRAIN_MIN_Z or -420, TERRAIN_MAX_Z or 1120
local step = TERRAIN_STEP or 4
for z = z0, z1, step do
	local row = {}
	for x = x0, x1, step do
		local y, mat = TERRAIN_TOP(x, z, 500, false)
		table.insert(row, string.format("%d %d %.1f %s", x, z, y or -99, mat or "None"))
	end
	print("T " .. table.concat(row, " T "))
end
for _, line in ipairs(DUMP(workspace, "world")) do
	print(line)
end
