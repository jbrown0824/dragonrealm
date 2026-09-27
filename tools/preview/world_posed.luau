local WorldBuilder = require(__proxy("Server/World/WorldBuilder"))
local DragonRig = require(__proxy("Shared/DragonRig"))
WorldBuilder.build()
-- pose every animated dragon the way clients will show it (folded, idle)
for _, inst in ipairs(ALL_INSTANCES) do
	if inst._tags and inst._tags.Dragon then
		local pose = DragonRig.pose(DragonRig.info(inst), { t = 0.3, mode = "ground", vy = 0, speed = 0 })
		for _, d in ipairs(inst:GetDescendants()) do
			if d.ClassName == "Motor6D" and pose[d.Name] then
				d.Transform = pose[d.Name]
			end
		end
		SOLVE(inst)
		inst:SetAttribute("__dragon", true)
		for _, d in ipairs(inst:GetDescendants()) do
			d.Name = "DRAGON:" .. inst.Name .. ":" .. d.Name
		end
	end
end
for _, line in ipairs(DUMP(workspace, "world")) do
	print(line)
end
