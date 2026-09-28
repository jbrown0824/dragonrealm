-- Village dragons (Config/Civilians) who stroll around Dragon Town along Zones.TownWalk, pop
-- into the houses for a while and stop to chat when you talk to them.
--
-- They're server NPCs with a Humanoid, tagged "Civilian" and "Dragon" (so every client animates
-- them like any dragon). They live in workspace.Civilians, outside Map, so attacks, aim and the
-- services' raycasts never see them, and they're in the "Dragons" collision group so they don't
-- bump into players.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Civilians = require(Shared.Config.Civilians)
local Zones = require(Shared.Config.Zones)
local DragonBuilder = require(Shared.DragonBuilder)

local CivilianService = {}
local S

local folder: Folder
local graph = {} -- [node] = { neighbor nodes }
local positions = {} -- [node] = Vector3 (ground level)
local streetNodes = {} -- nodes a villager may stroll to
local villagers = {} -- list of { def, model, humanoid, root, node, pauseUntil, height }


---------------------------------------------------------------- the walking graph

local function link(a: string, b: string)
	table.insert(graph[a], b)
	table.insert(graph[b], a)
end

local function buildGraph()
	for name, pos in pairs(Zones.TownWalk.nodes) do
		positions[name] = pos
		graph[name] = {}
		table.insert(streetNodes, name)
	end
	table.sort(streetNodes)
	for _, edge in ipairs(Zones.TownWalk.edges) do
		link(edge[1], edge[2])
	end
	for i, house in ipairs(Zones.Houses) do
		local door = "Door" .. i
		positions[door] = Zones.houseDoor(house)
		graph[door] = {}
		link(door, Zones.TownWalk.houseLinks[i])
	end
end

-- The nodes to walk through (not including `from`) to get to `to`, fewest hops first.
function CivilianService.route(from: string, to: string): { string }
	local prev = { [from] = from }
	local queue = { from }
	local head = 1
	while head <= #queue and not prev[to] do
		local node = queue[head]
		head += 1
		for _, nextNode in ipairs(graph[node] or {}) do
			if not prev[nextNode] then
				prev[nextNode] = node
				table.insert(queue, nextNode)
			end
		end
	end
	local path = {}
	if not prev[to] then
		return path
	end
	local node = to
	while node ~= from do
		table.insert(path, 1, node)
		node = prev[node]
	end
	return path
end

---------------------------------------------------------------- walking

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function waitWhileChatting(v)
	while os.clock() < v.pauseUntil and v.model.Parent do
		v.humanoid:MoveTo(v.root.Position)
		task.wait(0.3)
	end
end

-- Walk to `pos` (ground/floor level). If something blocks the way for too long, hop there so a
-- villager can never get stuck behind a lamp post forever.
local function walkTo(v, pos: Vector3)
	local deadline = os.clock() + flatDistance(v.root.Position, pos) / Civilians.WALK_SPEED + 5
	local lastPush = 0
	while v.model.Parent do
		if os.clock() < v.pauseUntil then
			waitWhileChatting(v)
			deadline += Civilians.CHAT_PAUSE
			lastPush = 0
		end
		if flatDistance(v.root.Position, pos) < 2.5 then
			return
		end
		if os.clock() > deadline then
			v.model:PivotTo(CFrame.new(pos + Vector3.new(0, v.height, 0)) * v.root.CFrame.Rotation)
			return
		end
		-- Humanoid:MoveTo gives up after 8 seconds, so keep nudging it.
		if os.clock() - lastPush > 3 then
			lastPush = os.clock()
			v.humanoid:MoveTo(pos)
		end
		task.wait(0.25)
	end
end

local function goToNode(v, node: string)
	for _, step in ipairs(CivilianService.route(v.node, node)) do
		walkTo(v, positions[step])
		v.node = step
	end
end

local function rest(v, range)
	local untilTime = os.clock() + range[1] + math.random() * (range[2] - range[1])
	v.humanoid:MoveTo(v.root.Position)
	while os.clock() < untilTime and v.model.Parent do
		task.wait(0.5)
	end
end

-- Go through the door, potter about a spot or two inside, and come back out.
local function visitHouse(v, index: number)
	local house = Zones.Houses[index]
	goToNode(v, "Door" .. index)
	local floor = Vector3.new(0, Zones.HOUSE_FLOOR, 0)
	local entry = Zones.housePoint(house, Zones.HouseEntry.X, Zones.HouseEntry.Z) + floor
	walkTo(v, entry)
	for _ = 1, math.random(1, 2) do
		local spot = Zones.HouseSpots[math.random(1, #Zones.HouseSpots)]
		walkTo(v, Zones.housePoint(house, spot.X, spot.Z) + floor)
		rest(v, { Civilians.INDOORS[1] / 2, Civilians.INDOORS[2] / 2 })
	end
	walkTo(v, entry)
	walkTo(v, positions["Door" .. index])
end

local function live(v)
	task.wait(math.random() * 4)
	while v.model.Parent do
		local ok, err = pcall(function()
			if math.random() < Civilians.HOME_CHANCE then
				local index = math.random() < 0.7 and v.def.home or math.random(1, #Zones.Houses)
				visitHouse(v, index)
			else
				goToNode(v, streetNodes[math.random(1, #streetNodes)])
				rest(v, Civilians.LINGER)
			end
		end)
		if not ok then
			warn("[CivilianService]", v.def.name, err)
			task.wait(2)
		end
	end
end

---------------------------------------------------------------- the villagers

local function nametag(model: Model, def)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7 * def.scale + 2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 22)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 18
	name.TextColor3 = Color3.fromRGB(255, 240, 200)
	name.TextStrokeTransparency = 0.3
	name.Text = def.name
	name.Parent = gui
	local role = Instance.new("TextLabel")
	role.BackgroundTransparency = 1
	role.Position = UDim2.fromOffset(0, 22)
	role.Size = UDim2.new(1, 0, 0, 16)
	role.Font = Enum.Font.GothamBold
	role.TextSize = 12
	role.TextColor3 = Color3.fromRGB(170, 220, 160)
	role.TextStrokeTransparency = 0.4
	role.Text = "Villager"
	role.Parent = gui
	gui.Parent = model.PrimaryPart
end

local function chat(v, player: Player)
	local _, _, root = S.PlayerService.getCharacter(player)
	if root then
		local here = v.root.Position
		v.root.CFrame = CFrame.lookAt(here, Vector3.new(root.Position.X, here.Y, root.Position.Z))
	end
	v.pauseUntil = os.clock() + Civilians.CHAT_PAUSE
	local lines = v.def.lines
	local text = (math.random() < 0.6 and lines[math.random(1, #lines)]) or Civilians.CommonLines[math.random(1, #Civilians.CommonLines)]
	S.PlayerService.notify(player, string.format("%s: \"%s\"", v.def.name, text), Color3.fromRGB(255, 240, 200), "💬")
end

local function spawnVillager(def, startNode: string)
	local model, hipHeight = DragonBuilder.build(def.plan, { scale = def.scale, colors = def.colors, noParticles = true, name = def.name })
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = Civilians.WALK_SPEED
	humanoid.MaxSlopeAngle = 60
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.Parent = model
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Dragons"
		end
	end
	local root = model.PrimaryPart
	local height = hipHeight + root.Size.Y / 2 + 0.3
	model:PivotTo(CFrame.new(positions[startNode] + Vector3.new(0, height, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model:SetAttribute("CivilianId", def.id)
	nametag(model, def)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Chat"
	prompt.ObjectText = def.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	CollectionService:AddTag(model, "Civilian")
	CollectionService:AddTag(model, "Dragon")
	local v = { def = def, model = model, humanoid = humanoid, root = root, node = startNode, pauseUntil = 0, height = height }
	prompt.Triggered:Connect(function(player)
		chat(v, player)
	end)
	table.insert(villagers, v)
	task.spawn(live, v)
	return v
end

function CivilianService.villagers()
	return villagers
end

function CivilianService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Civilians"
	folder.Parent = workspace
	buildGraph()
end

function CivilianService.start()
	for i, def in ipairs(Civilians.List) do
		spawnVillager(def, streetNodes[(i * 5) % #streetNodes + 1])
	end
end

return CivilianService
