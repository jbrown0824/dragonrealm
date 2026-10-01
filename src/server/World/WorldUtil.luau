-- Small helpers shared by WorldBuilder, Camps and Wilds (and a couple used by services).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DragonBuilder = require(Shared.DragonBuilder)
local Quests = require(Shared.Config.Quests)

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

-- A quest giver: a dragon on a little platform, with its Talk prompt (tag QuestPrompt) and its
-- name. Town givers are built by WorldBuilder; the dungeon keepers also stand inside their dungeon.
function WorldUtil.questGiver(parent: Instance, giverId: string, at: Vector3, facing: Vector3): Model
	local giver = Quests.Givers[giverId]
	-- little platform
	Props.column(parent, at - Vector3.new(0, 0.5, 0), 1.2, 22, Color3.fromRGB(170, 160, 150), Enum.Material.Cobblestone)
	local model = WorldUtil.placeDragon(parent, giver.look, at + Vector3.new(0, 0.7, 0), facing, { scale = 1.05, name = giver.name })
	model:SetAttribute("GiverId", giverId)
	CollectionService:AddTag(model, "QuestGiver")

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = giver.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("GiverId", giverId)
	prompt.Parent = model.PrimaryPart
	CollectionService:AddTag(prompt, "QuestPrompt")

	local gui = Instance.new("BillboardGui")
	gui.Name = "GiverName"
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.6, 0)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(255, 225, 120)
	name.TextStrokeTransparency = 0.3
	name.Text = giver.name
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0, 0.6)
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(220, 220, 230)
	title.TextStrokeTransparency = 0.5
	title.Text = "<" .. giver.title .. ">"
	title.Parent = gui
	gui.Parent = model:FindFirstChild("Head") or model.PrimaryPart
	return model
end

-- Distance from p to the segment a-b, ignoring height.
-- Let an anchored enemy go again (after a pose, a leap, a throne): unanchored, with the server
-- keeping its physics. Unanchoring hands an assembly back to automatic network ownership, so the
-- nearest player's client would simulate it (Haldor stood up sunk into the floor that way).
function WorldUtil.release(root: BasePart, humanoid: Humanoid?)
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

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
