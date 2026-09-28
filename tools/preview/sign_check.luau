-- Build the world and report every sign whose bottom edge is close to (or under) the terrain.
local WorldBuilder = require(__proxy("Server/World/WorldBuilder"))
WorldBuilder.build()
TERRAIN_PREPARE()
local worst = {}
for _, inst in ipairs(ALL_INSTANCES) do
	if inst._props and inst._props.Name == "Sign" and inst._props.Size and inst._parent then
		local cf, size = inst._props.CFrame, inst._props.Size
		local lowest = math.huge
		local ground = -math.huge
		for _, sx in ipairs({ -0.5, 0, 0.5 }) do
			local p = cf * Vector3.new(sx * size.X, -size.Y / 2, 0)
			lowest = math.min(lowest, p.Y)
			local g = TERRAIN_TOP(p.X, p.Z, 400, false) or 0
			ground = math.max(ground, g)
		end
		table.insert(worst, { gap = lowest - ground, pos = cf.p, path = tostring(inst._parent._props.Name) })
	end
end
table.sort(worst, function(a, b) return a.gap < b.gap end)
for i = 1, math.min(12, #worst) do
	local w = worst[i]
	print(string.format("%6.2f clearance  %-20s at %.0f, %.0f, %.0f", w.gap, w.path, w.pos.X, w.pos.Y, w.pos.Z))
end
print(#worst .. " signs checked")
