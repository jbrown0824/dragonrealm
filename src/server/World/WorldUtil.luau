-- Small helpers shared by WorldBuilder, Camps and Wilds (and a couple used by services).

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

-- Lay a dragon (built by DragonBuilder) down on its belly where it stands: knocked out, or dead.
-- The root is anchored and lowered so the belly rests on the ground at groundY; clients sprawl
-- its legs, neck and wings (DragonRig's "downed" pose). standDragon puts it back on its feet
-- (`height` = root height above the ground when standing).
local function flatLook(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	return look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
end

function WorldUtil.layDragon(model: Model, root: BasePart, groundY: number)
	root.Anchored = true
	local pos = Vector3.new(root.Position.X, groundY + root.Size.Y / 2 + 0.2, root.Position.Z)
	model:PivotTo(CFrame.lookAt(pos, pos + flatLook(root)))
end

function WorldUtil.standDragon(model: Model, root: BasePart, height: number, groundY: number)
	local pos = Vector3.new(root.Position.X, groundY + height, root.Position.Z)
	model:PivotTo(CFrame.lookAt(pos, pos + flatLook(root)))
	root.Anchored = false
end

return WorldUtil
