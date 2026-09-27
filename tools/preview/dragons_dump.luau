-- Build every dragon type side by side in a given pose and dump the parts.
local DragonBuilder = require(__proxy("Shared/DragonBuilder"))
local DragonRig = require(__proxy("Shared/DragonRig"))
local Classes = require(__proxy("Shared/Config/Classes"))
local MODE = POSE_MODE or "ground"
local BREATH = POSE_BREATH or false
local T = POSE_T or 0.3
local SPEED = POSE_SPEED or 0
local VY = POSE_VY or 0
for i, classId in ipairs(Classes.Order) do
	local model = DragonBuilder.build(classId, {})
	model:PivotTo(CFrame.new((i - 3) * 24, 4.2 * (model:GetAttribute("DragonScale") or 1), 0))
	local info = DragonRig.info(model)
	local pose = DragonRig.pose(info, { t = T, mode = MODE, vy = VY, speed = SPEED, breathing = BREATH, blink = false })
	for _, d in ipairs(model:GetDescendants()) do
		if d.ClassName == "Motor6D" and pose[d.Name] then
			d.Transform = pose[d.Name]
		end
	end
	SOLVE(model)
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	for _, line in ipairs(DUMP(model, classId)) do
		print(line)
	end
	print("#count " .. classId .. " " .. count)
end
