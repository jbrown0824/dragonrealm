-- Viking NPCs: spawning at camps, simple AI (wander, chase, melee, throw axes, leash home),
-- death rewards, and respawning. Bosses and their adds are also registered here so combat
-- can find them, but BossService drives the boss's own AI.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Enemies = require(Shared.Config.Enemies)
local Zones = require(Shared.Config.Zones)

local VikingBuilder = require(script.Parent.Parent.World.VikingBuilder)

local EnemyService = {}
local S

local enemies = {} -- [Model] = info
local folder: Folder
local mapParams = RaycastParams.new()
local THROW_SPEED = 75

local aliveCache = {}
local aliveCacheFrame = -1
local frame = 0

local function now()
	return os.clock()
end

---------------------------------------------------------------- nametags

local function statusIcons(model: Model): string
	local icons = ""
	if model:GetAttribute("Stunned") then
		icons ..= "💫"
	end
	if model:GetAttribute("Slowed") then
		icons ..= "❄️"
	end
	if model:GetAttribute("Poisoned") then
		icons ..= "☠️"
	end
	if model:GetAttribute("Burning") then
		icons ..= "🔥"
	end
	return icons
end

local function updateNametag(e)
	local tag = e.nametag
	if not tag then
		return
	end
	local pct = math.clamp(e.humanoid.Health / math.max(1, e.humanoid.MaxHealth), 0, 1)
	tag.Bar.Fill.Size = UDim2.fromScale(pct, 1)
	tag.Status.Text = statusIcons(e.model)
end

local function createNametag(e)
	local head = e.model:FindFirstChild("Head", true)
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(180, 54)
	gui.StudsOffset = Vector3.new(0, 2.2 * e.scale, 0)
	gui.MaxDistance = e.isBoss and 400 or 110
	gui.LightInfluence = 0
	gui.AlwaysOnTop = e.isBoss

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextStrokeTransparency = 0.4
	name.Text = string.format("%s  Lv %d", e.displayName, e.level)
	name.TextColor3 = (e.isBoss and Color3.fromRGB(255, 90, 90)) or (e.def.elite and Color3.fromRGB(255, 200, 70)) or Color3.new(1, 1, 1)
	name.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 23)
	bar.Size = UDim2.fromOffset(120, 9)
	bar.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 50)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	for _, f in ipairs({ bar, fill }) do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(0, 34)
	statusLabel.Size = UDim2.new(1, 0, 0, 18)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Parent = gui

	gui.Parent = head
	e.nametag = gui
	for _, attr in ipairs({ "Stunned", "Slowed", "Poisoned", "Burning" }) do
		e.model:GetAttributeChangedSignal(attr):Connect(function()
			updateNametag(e)
		end)
	end
end

---------------------------------------------------------------- spawning

local function groundAt(pos: Vector3): Vector3
	local ray = workspace:Raycast(Vector3.new(pos.X, 150, pos.Z), Vector3.new(0, -400, 0), mapParams)
	if ray then
		return ray.Position
	end
	return Vector3.new(pos.X, 0, pos.Z)
end
EnemyService.groundAt = groundAt

-- opts: camp, scale, healthMult, damageMult, customAI, isBoss, displayName, look, leash, aggroRange,
--       arena (only targets boss-fight participants), noRewards, onDeath
function EnemyService.spawn(typeId: string, level: number, position: Vector3, opts)
	opts = opts or {}
	local def = Enemies.Vikings[typeId] or opts.def
	if not def then
		warn("[EnemyService] Unknown enemy type", typeId)
		return nil
	end
	local scale = opts.scale or def.scale
	local displayName = opts.displayName or def.name
	local model, hipHeight = VikingBuilder.build(opts.look or def.look, scale, displayName)

	local maxHealth = math.floor(def.health * (1 + Enemies.HEALTH_PER_LEVEL * (level - 1)) * (opts.healthMult or 1))
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.AutomaticScalingEnabled = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = opts.speed or def.speed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 45
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid.Parent = model

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Enemies"
		end
	end

	local ground = groundAt(position)
	model:PivotTo(CFrame.new(ground + Vector3.new(0, hipHeight + scale + 0.5, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model.Parent = folder
	local root = model.PrimaryPart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	CollectionService:AddTag(model, "Viking")

	local e = {
		model = model,
		humanoid = humanoid,
		root = root,
		def = def,
		typeId = typeId,
		displayName = displayName,
		level = level,
		scale = scale,
		radius = 1.4 * scale,
		height = 3.6 * scale,
		damage = def.damage * (1 + Enemies.DAMAGE_PER_LEVEL * (level - 1)) * (opts.damageMult or 1),
		defense = def.defense * (1 + 0.15 * (level - 1)),
		baseSpeed = opts.speed or def.speed,
		spawnPos = ground,
		camp = opts.camp,
		damageBy = {},
		target = nil,
		nextAttack = 0,
		nextThrow = now() + math.random() * 2,
		wanderAt = now() + math.random() * 4,
		lastPos = root.Position,
		stuckTime = 0,
		dead = false,
		returning = false,
		isBoss = opts.isBoss == true,
		customAI = opts.customAI == true,
		arena = opts.arena == true,
		noRewards = opts.noRewards == true,
		onDeath = opts.onDeath,
		leash = opts.leash or Game.ENEMY_LEASH,
		aggroRange = opts.aggroRange or 42,
	}
	enemies[model] = e
	createNametag(e)
	humanoid.HealthChanged:Connect(function()
		updateNametag(e)
	end)
	return e
end

local function spawnInCamp(camp, typeId: string)
	local angle = math.random() * math.pi * 2
	local dist = math.sqrt(math.random()) * camp.radius
	local pos = camp.center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	local def = Enemies.Vikings[typeId]
	local level = def and def.elite and camp.levels[2] or math.random(camp.levels[1], camp.levels[2])
	EnemyService.spawn(typeId, level, pos, { camp = camp })
end

---------------------------------------------------------------- queries

function EnemyService.getInfo(model: Model)
	return enemies[model]
end

function EnemyService.alive()
	if aliveCacheFrame == frame then
		return aliveCache
	end
	local list = {}
	for _, e in pairs(enemies) do
		if not e.dead and e.model.Parent then
			table.insert(list, e)
		end
	end
	aliveCache = list
	aliveCacheFrame = frame
	return list
end

function EnemyService.dropAggro(player: Player)
	for _, e in pairs(enemies) do
		if e.target == player then
			e.target = nil
		end
	end
end

local function targetRoot(e, player: Player)
	if not player or not player.Parent then
		return nil
	end
	local character, _, root = S.PlayerService.getCharacter(player)
	if not character or character:GetAttribute("Stealthed") then
		return nil
	end
	if e.arena then
		if not S.BossService.isInFight(player) then
			return nil
		end
	else
		local area = Zones.areaAt(root.Position)
		if area and area.safe then
			return nil
		end
		if (root.Position - e.spawnPos).Magnitude > e.leash + 40 then
			return nil
		end
	end
	return root
end
EnemyService.targetRoot = targetRoot

function EnemyService.onDamaged(e, attacker: Player)
	if e.dead or e.returning then
		return
	end
	if not e.target or not targetRoot(e, e.target) then
		if targetRoot(e, attacker) then
			e.target = attacker
		end
	end
end

---------------------------------------------------------------- death

local function reward(player: Player, e)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	local xp = (12 + 7 * e.level) * (e.def.xpMult or 1)
	if profile.level - e.level >= Game.LOW_LEVEL_XP_PENALTY_GAP then
		xp *= Game.LOW_LEVEL_XP_MULT
	end
	profile.vikingKills += 1
	S.PlayerService.addXP(player, xp)
	S.LootService.dropForEnemy(player, e, e.root.Position)
	S.QuestService.progress(player, "kill", e.typeId, 1)
end

function EnemyService.kill(e, killer: Player?)
	if e.dead then
		return
	end
	e.dead = true
	-- Let the body tumble onto the ground instead of sinking through it when the joints break.
	for _, p in ipairs(e.model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = true
			p.Massless = false
		end
	end
	e.humanoid.Health = 0
	S.CombatService.clearStatus(e.model)
	if e.nametag then
		e.nametag.Enabled = false
	end
	if e.onDeath then
		task.spawn(e.onDeath, e, killer)
	end
	if not e.noRewards then
		for player, dealt in pairs(e.damageBy) do
			if player.Parent and dealt > 0 then
				reward(player, e)
			end
		end
	end
	S.CombatService.broadcastVFX({ kind = "enemyDeath", pos = e.root.Position })
	task.delay(3, function()
		enemies[e.model] = nil
		e.model:Destroy()
	end)
	if e.camp then
		task.delay(Game.ENEMY_RESPAWN + math.random() * 6, function()
			spawnInCamp(e.camp, e.typeId)
		end)
	end
end

function EnemyService.despawn(e)
	e.dead = true
	enemies[e.model] = nil
	e.model:Destroy()
end

---------------------------------------------------------------- AI

local function face(e, pos: Vector3)
	local p = e.root.Position
	local flat = Vector3.new(pos.X, p.Y, pos.Z)
	if (flat - p).Magnitude > 0.5 then
		e.root.CFrame = CFrame.lookAt(p, flat)
	end
end

function EnemyService.throwAt(e, player: Player, root: BasePart, damage: number, style: string?)
	local from = e.root.Position + Vector3.new(0, 1.8 * e.scale, 0)
	local dist = (root.Position - from).Magnitude
	local lead = root.AssemblyLinearVelocity * (dist / THROW_SPEED) * 0.5
	local targetPos = root.Position + lead
	local travel = (targetPos - from).Magnitude / THROW_SPEED
	e.model:SetAttribute("Throw", now())
	S.CombatService.broadcastVFX({ kind = "throw", from = from, to = targetPos, time = travel, style = style or "axe" })
	task.delay(travel, function()
		for _, p in ipairs(Players:GetPlayers()) do
			local character, _, r = S.PlayerService.getCharacter(p)
			if character and (r.Position - targetPos).Magnitude <= 5 + 2.5 * (character:GetAttribute("DragonScale") or 1) then
				S.CombatService.damagePlayer(p, damage, { sourceLevel = e.level })
			end
		end
	end)
end

local function meleeSwing(e, player: Player)
	e.model:SetAttribute("Swing", now())
	task.delay(0.3, function()
		if e.dead then
			return
		end
		local root = targetRoot(e, player)
		if not root then
			return
		end
		local offset = root.Position - e.root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local reach = e.def.attackRange + 3 * ((player.Character and player.Character:GetAttribute("DragonScale")) or 1) + 2
		if flat <= reach and math.abs(offset.Y) <= 9 then
			S.CombatService.damagePlayer(player, e.damage, { sourceLevel = e.level, melee = true, enemyInfo = e })
		end
	end)
end

local function findTarget(e)
	local best, bestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = targetRoot(e, player)
		if root then
			local offset = root.Position - e.root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= e.aggroRange and math.abs(offset.Y) <= 70 and flat < bestDist then
				best, bestDist = player, flat
			end
		end
	end
	return best
end

local function think(e, t: number, dt: number)
	local humanoid = e.humanoid
	local root = e.root
	local speedMult = S.CombatService.speedMultiplier(e.model)
	humanoid.WalkSpeed = e.baseSpeed * speedMult
	if speedMult == 0 then
		humanoid:MoveTo(root.Position)
		return
	end

	-- Head home and heal up after being dragged too far.
	if e.returning then
		if (root.Position - e.spawnPos).Magnitude < 15 then
			e.returning = false
		else
			humanoid:MoveTo(e.spawnPos)
			return
		end
	end
	if not e.arena and (root.Position - e.spawnPos).Magnitude > e.leash then
		e.target = nil
		e.returning = true
		e.damageBy = {}
		humanoid.Health = humanoid.MaxHealth
		humanoid:MoveTo(e.spawnPos)
		return
	end

	local troot = e.target and targetRoot(e, e.target)
	if not troot then
		e.target = findTarget(e)
		troot = e.target and targetRoot(e, e.target)
	end

	if troot then
		local def = e.def
		local offset = troot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local vertical = math.abs(offset.Y)
		local targetRadius = 3 * ((e.target.Character and e.target.Character:GetAttribute("DragonScale")) or 1)
		local inMelee = flat <= def.attackRange + targetRadius and vertical <= 8

		if inMelee then
			humanoid:MoveTo(root.Position)
			face(e, troot.Position)
			if t >= e.nextAttack then
				e.nextAttack = t + def.attackCooldown
				meleeSwing(e, e.target)
			end
			return
		end

		local wantsThrow = vertical > 8 or def.preferredRange > 0 or flat > def.attackRange * 3
		if wantsThrow and t >= e.nextThrow and (offset.Magnitude <= def.throwRange) then
			e.nextThrow = t + def.throwCooldown * (0.8 + math.random() * 0.4)
			face(e, troot.Position)
			EnemyService.throwAt(e, e.target, troot, e.damage * def.throwDamage, def.look.weapon == "hammer" and "hammer" or "axe")
		end

		if def.preferredRange > 0 then
			if flat < def.preferredRange * 0.6 then
				local away = Vector3.new(-offset.X, 0, -offset.Z)
				if away.Magnitude > 0.1 then
					humanoid:MoveTo(root.Position + away.Unit * 12)
				end
			elseif flat > def.preferredRange then
				humanoid:MoveTo(troot.Position)
			else
				humanoid:MoveTo(root.Position)
				face(e, troot.Position)
			end
		else
			humanoid:MoveTo(Vector3.new(troot.Position.X, root.Position.Y, troot.Position.Z))
		end

		-- Jump if stuck on something while chasing.
		local moved = (root.Position - e.lastPos).Magnitude
		if moved < 0.4 * dt * 5 and flat > def.attackRange + targetRadius + 2 then
			e.stuckTime += dt
			if e.stuckTime > 1 then
				humanoid.Jump = true
				e.stuckTime = 0
			end
		else
			e.stuckTime = 0
		end
		e.lastPos = root.Position
		return
	end

	-- Idle: wander around home.
	if t >= e.wanderAt then
		e.wanderAt = t + 4 + math.random() * 6
		local angle = math.random() * math.pi * 2
		local r = math.random() * 22
		humanoid:MoveTo(e.spawnPos + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
	end
end

function EnemyService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
end

function EnemyService.start()
	local map = workspace:WaitForChild("Map")
	mapParams.FilterType = Enum.RaycastFilterType.Include
	mapParams.FilterDescendantsInstances = { map, workspace.Terrain }
	mapParams.IgnoreWater = true

	RunService.Heartbeat:Connect(function()
		frame += 1
	end)

	for _, camp in ipairs(Zones.Camps) do
		for typeId, count in pairs(camp.spawns) do
			for _ = 1, count do
				spawnInCamp(camp, typeId)
			end
		end
	end

	local warned = false
	local dt = 0.2
	while true do
		task.wait(dt)
		local t = now()
		for _, e in pairs(enemies) do
			if not e.dead and not e.customAI and e.model.Parent then
				local ok, err = pcall(think, e, t, dt)
				if not ok and not warned then
					warned = true
					warn("[EnemyService] AI error:", err)
				end
			end
		end
	end
end

return EnemyService
