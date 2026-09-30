-- Village dragons (Config/Civilians) who stroll around Dragon Town along Zones.TownWalk, pop
-- into the houses for a while and stop to chat when you talk to them.
--
-- They're server NPCs with a Humanoid, tagged "Civilian" and "Dragon" (so every client animates
-- them like any dragon). They live in workspace.Civilians, outside Map, so attacks, aim and the
-- services' raycasts never see them, and they're in the "Dragons" collision group so they don't
-- bump into players.
--
-- During a night raid (RaidService) they drop what they're doing, come out of their houses and
-- puff little bursts of fire at the raiders, spreading out over them rather than mobbing one.
-- They hurry at their own pace (Civilians.RaidSpeed by age: the youngsters run, the old-timers
-- walk) and wait by their own street between waves, so they don't move about in one clump.
-- They're brave but weak: a few axe hits
-- (Raids.VILLAGER_HITS) knock one out, sprawled on the ground with its eyes shut (the model
-- attribute "KnockedOut" tells clients to pose it) until it gets back up.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Civilians = require(Shared.Config.Civilians)
local Raids = require(Shared.Config.Raids)
local Zones = require(Shared.Config.Zones)
local DragonBuilder = require(Shared.DragonBuilder)

local WorldUtil = require(script.Parent.Parent.World.WorldUtil)

local CivilianService = {}
local S

local folder: Folder
local graph = {} -- [node] = { neighbor nodes }
local positions = {} -- [node] = Vector3 (ground level)
local streetNodes = {} -- nodes a villager may stroll to
local villagers = {} -- list of { def, model, humanoid, root, node, pauseUntil, height, role, inside?, defending?, hits?, knockedOut? }
local raiding = false


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

function CivilianService.nodePos(name: string): Vector3?
	return positions[name]
end

-- The walking-graph node nearest a point (doors included unless streetsOnly).
function CivilianService.nearestNode(pos: Vector3, streetsOnly: boolean?): string
	local best, bestDist = streetNodes[1], math.huge
	for name, p in pairs(positions) do
		if not (streetsOnly and name:sub(1, 4) == "Door") then
			local d = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude
			if d < bestDist then
				best, bestDist = name, d
			end
		end
	end
	return best
end

---------------------------------------------------------------- walking

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A raid just started and this villager hasn't noticed yet: drop the errand. (Or it's out cold.)
local function called(v): boolean
	return (raiding and not v.defending) or v.knockedOut == true
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
	local deadline = os.clock() + flatDistance(v.root.Position, pos) / math.max(1, v.humanoid.WalkSpeed) + 5
	local lastPush = 0
	while v.model.Parent do
		if called(v) then
			return
		end
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
		if called(v) then
			return
		end
		v.node = step
	end
end

local function rest(v, range)
	local untilTime = os.clock() + range[1] + math.random() * (range[2] - range[1])
	v.humanoid:MoveTo(v.root.Position)
	while os.clock() < untilTime and v.model.Parent and not called(v) do
		task.wait(0.5)
	end
end

-- Go through the door, potter about a spot or two inside, and come back out.
local function visitHouse(v, index: number)
	local house = Zones.Houses[index]
	goToNode(v, "Door" .. index)
	local floor = Vector3.new(0, Zones.HOUSE_FLOOR, 0)
	local entry = Zones.housePoint(house, Zones.HouseEntry.X, Zones.HouseEntry.Z) + floor
	if called(v) then
		return
	end
	v.inside = index
	walkTo(v, entry)
	for _ = 1, math.random(1, 2) do
		local spot = Zones.HouseSpots[math.random(1, #Zones.HouseSpots)]
		walkTo(v, Zones.housePoint(house, spot.X, spot.Z) + floor)
		rest(v, { Civilians.INDOORS[1] / 2, Civilians.INDOORS[2] / 2 })
	end
	if called(v) then
		return -- defend() walks them out
	end
	walkTo(v, entry)
	walkTo(v, positions["Door" .. index])
	v.inside = nil
end

---------------------------------------------------------------- raids

local function face(v, pos: Vector3)
	local here = v.root.Position
	if flatDistance(here, pos) > 0.5 then
		v.root.CFrame = CFrame.lookAt(here, Vector3.new(pos.X, here.Y, pos.Z))
	end
end

-- How many other villagers are going after this raider.
local function foesOn(e, except): number
	local n = 0
	for _, other in ipairs(villagers) do
		if other ~= except and other.foe == e and other.defending and not other.knockedOut then
			n += 1
		end
	end
	return n
end

-- The raider to go after: a near one, but one with fewer villagers already on it, so they
-- spread out over the raiders instead of trooping after the same one.
local function pickFoe(v)
	local best, bestScore = nil, math.huge
	for _, e in ipairs(S.RaidService.raiders()) do
		local d = flatDistance(v.root.Position, e.root.Position)
		if d < 260 then
			local score = d + foesOn(e, v) * 35
			if score < bestScore then
				best, bestScore = e, score
			end
		end
	end
	return best
end

-- Out of the house, then after a raider: along the streets while it's far away, straight at it
-- once close, and a puff of fire whenever it's in range. With no raider ashore (before the first
-- wave, between waves) they wait by their own street.
local function defend(v)
	v.defending = true
	local base = Civilians.RaidSpeed[v.def.age or "adult"] or Civilians.WALK_SPEED
	v.humanoid.WalkSpeed = base * (1 + (math.random() * 2 - 1) * Civilians.RAID_SPEED_JITTER)
	if v.inside then
		local house = Zones.Houses[v.inside]
		walkTo(v, Zones.housePoint(house, Zones.HouseEntry.X, Zones.HouseEntry.Z) + Vector3.new(0, Zones.HOUSE_FLOOR, 0))
		walkTo(v, positions["Door" .. v.inside])
		v.node = "Door" .. v.inside
		v.inside = nil
	end
	local post = Zones.TownWalk.houseLinks[v.def.home] or "PN"
	local shouted = false
	while raiding and v.model.Parent do
		if v.foe and (v.foe.dead or not v.foe.model.Parent or v.foe.aboard or os.clock() >= (v.foeUntil or 0)) then
			v.foe = nil
		end
		if not v.foe and not v.knockedOut then
			v.foe = pickFoe(v)
			v.foeUntil = os.clock() + 8 + math.random() * 6
		end
		local e = v.foe
		if v.knockedOut then
			v.foe = nil
			task.wait(0.5)
		elseif not e then
			-- one street node at a time toward their post, so they notice the next raider at once
			local path = CivilianService.route(v.node, post)
			if path[1] then
				walkTo(v, positions[path[1]])
				v.node = path[1]
			else
				v.humanoid:MoveTo(v.root.Position)
				task.wait(0.6)
			end
		else
			local dist = flatDistance(v.root.Position, e.root.Position)
			if dist > 40 then
				-- one street node closer
				local path = CivilianService.route(v.node, CivilianService.nearestNode(e.root.Position))
				if path[1] then
					walkTo(v, positions[path[1]])
					v.node = path[1]
				else
					v.humanoid:MoveTo(e.root.Position)
					task.wait(0.5)
				end
			elseif dist > Raids.VILLAGER_RANGE then
				v.humanoid:MoveTo(e.root.Position)
				task.wait(0.4)
			else
				v.humanoid:MoveTo(v.root.Position)
				face(v, e.root.Position)
				if os.clock() >= (v.nextPuff or 0) then
					v.nextPuff = os.clock() + Raids.VILLAGER_INTERVAL * (0.8 + math.random() * 0.4)
					S.RaidService.villagerPuff(v, e)
					if not shouted and math.random() < 0.5 then
						shouted = true
						CivilianService.say(v, Raids.VILLAGER_LINES[math.random(1, #Raids.VILLAGER_LINES)])
					end
				end
				task.wait(0.3)
			end
		end
	end
	v.defending = false
	v.foe = nil
	v.humanoid.WalkSpeed = Civilians.WALK_SPEED
	v.node = CivilianService.nearestNode(v.root.Position, true)
end

---------------------------------------------------------------- knocked out

local function groundY(v): number
	return S.EnemyService.groundAt(v.root.Position, 4).Y
end

local function getUp(v)
	if not v.knockedOut or not v.model.Parent then
		return
	end
	v.knockedOut = false
	v.hits = 0
	v.model:SetAttribute("KnockedOut", nil)
	v.role.Text = "Villager"
	WorldUtil.standDragon(v.model, v.root, v.height, groundY(v))
	v.node = CivilianService.nearestNode(v.root.Position, true)
	CivilianService.say(v, "I'm okay!")
end

local function knockOut(v)
	v.knockedOut = true
	v.model:SetAttribute("KnockedOut", true)
	v.role.Text = "💫 Knocked out"
	v.humanoid:MoveTo(v.root.Position)
	WorldUtil.layDragon(v.model, v.root, groundY(v))
	task.delay(Raids.VILLAGER_KNOCKOUT, function()
		getUp(v)
	end)
end

-- A raider's axe hit a villager.
function CivilianService.hurt(v)
	if v.knockedOut or not v.model.Parent then
		return
	end
	v.hits = (v.hits or 0) + 1
	if v.hits >= Raids.VILLAGER_HITS then
		knockOut(v)
	elseif math.random() < 0.5 then
		CivilianService.say(v, Raids.VILLAGER_HURT_LINES[math.random(1, #Raids.VILLAGER_HURT_LINES)])
	end
end

function CivilianService.setRaid(on: boolean)
	raiding = on
end

-- A speech bubble over a villager for a few seconds, for everyone nearby.
function CivilianService.say(v, text: string)
	CivilianService.speak(v.root, 7 * v.def.scale + 5.5, text)
end

-- A speech bubble `height` studs over `part` for a few seconds (villagers, and the quest givers
-- during a raid).
function CivilianService.speak(part: BasePart, height: number, text: string)
	local old = part:FindFirstChild("Speech")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Speech"
	gui.Size = UDim2.fromOffset(190, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local bubble = Instance.new("TextLabel")
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
	bubble.TextColor3 = Color3.fromRGB(60, 40, 30)
	bubble.Font = Enum.Font.GothamBold
	bubble.TextScaled = true
	bubble.Text = text
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble
	gui.Parent = part
	game:GetService("Debris"):AddItem(gui, 3)
end

local function live(v)
	task.wait(math.random() * 4)
	while v.model.Parent do
		local ok, err = pcall(function()
			if v.knockedOut then
				task.wait(0.5)
			elseif raiding then
				defend(v)
			elseif math.random() < Civilians.HOME_CHANCE then
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
	return role
end

local function chat(v, player: Player)
	if v.knockedOut then
		S.PlayerService.notify(player, v.def.name .. " is out cold! They'll be back on their feet soon.", Color3.fromRGB(255, 240, 200), "💫")
		return
	end
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
	local role = nametag(model, def)
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
	local v = { def = def, model = model, humanoid = humanoid, root = root, node = startNode, pauseUntil = 0, height = height, role = role }
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
