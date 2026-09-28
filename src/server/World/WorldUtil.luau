-- Small helpers shared by WorldBuilder, Camps and Wilds.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DragonBuilder = require(Shared.DragonBuilder)

local Props = require(script.Parent.Props)

local WorldUtil = {}

WorldUtil.terrain = workspace.Terrain
WorldUtil.rng = Random.new(20260926)

function WorldUtil.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function WorldUtil.facingCF(pos: Vector3, facing: Vector3): CFrame
	local dir = Vector3.new(facing.X, 0, facing.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(pos, pos + dir.Unit)
end

-- A flat terrain strip (road / path) from a to b, top surface at y = 0.
function WorldUtil.terrainPath(a: Vector3, b: Vector3, width: number, material: Enum.Material)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(Vector3.new(mid.X, -2, mid.Z), Vector3.new(b.X, -2, b.Z))
	WorldUtil.terrain:FillBlock(cf, Vector3.new(width, 4, len + width), material)
end

-- Note: Roblox only honors CanQuery = false on parts with CanCollide = false, so solid invisible
-- walls still block raycasts. That's why barriers live in workspace.Barriers, outside Map:
-- the services raycast against Map + Terrain and never see them.
function WorldUtil.invisibleWall(parent: Instance, size: Vector3, cf: CFrame)
	local p = Props.part(parent, size, cf, Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- A decorative / NPC dragon standing on the ground at `pos`.
function WorldUtil.placeDragon(parent: Instance, classId: string, pos: Vector3, facing: Vector3, options)
	options = options or {}
	options.anchored = true
	local model, hipHeight = DragonBuilder.build(classId, options)
	local root = model.PrimaryPart
	local height = hipHeight + root.Size.Y / 2
	model:PivotTo(WorldUtil.facingCF(pos + Vector3.new(0, height, 0), facing))
	model.Parent = parent
	if not options.tint then
		CollectionService:AddTag(model, "Dragon") -- clients animate wings/tail (statues stay still)
	end
	return model
end

-- Distance from p to the segment a-b, ignoring height.
function WorldUtil.flatDistToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
	return (ap - ab * t).Magnitude
end

return WorldUtil
