-- Everything dragons can fight that isn't another dragon: vikings (camp spawning, AI, death
-- rewards, respawning), wild animals (spawned by WildlifeService, AI here), mini-bosses
-- (spawned by CampService) and training dummies (registered by TrainingService). Bosses are
-- registered here too so combat can find them, but BossService drives the boss's own AI.
--
-- AI behaviors (def.behavior, vikings are "aggressive"):
--   aggressive  attacks dragons that come within aggroRange
--   neutral     only fights back once hurt
--   flee        runs from nearby dragons, never attacks
-- Vikings with def.alarm (Hornblowers) in a camp with `alarm = true` blow a horn when they spot
-- a dragon; if they finish, every viking in the camp hunts that dragon for a while.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Enemies = require(Shared.Config.Enemies)
local Zones = require(Shared.Config.Zones)
local Tuning = require(Shared.Tuning)
local Remotes = require(Shared.Remotes)

local VikingBuilder = require(script.Parent.Parent.World.VikingBuilder)

local EnemyService = {}
local S

local enemies = {} -- [Model] = info
local folder: Folder
local mapParams = RaycastParams.new()
local terrainParams = RaycastParams.new()
local propParams = OverlapParams.new()
local THROW_SPEED = 75
local HORN_TIME = 2.5

local aliveCache = {}
local aliveCacheFrame = -1
local frame = 0

local function now()
	return os.clock()
end

---------------------------------------------------------------- nametags

local function statusIcons(model: Model): string
	local icons = ""
	if model:GetAttribute("Blowing") then
		icons ..= "📯"
	end
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
	local head = e.model:FindFirstChild("Head", true) or e.root
	if not head then
		return
	end
	local big = e.isBoss or e.miniBoss
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(big and 220 or 180, 54)
	gui.StudsOffset = Vector3.new(0, e.tagOffset or 2.2 * e.scale, 0)
	gui.MaxDistance = e.isBoss and 400 or (e.miniBoss and 200 or 110)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = e.isBoss

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextStrokeTransparency = 0.4
	name.Text = e.dummy and e.displayName or string.format("%s  Lv %d", e.displayName, e.level)
	if e.isBoss then
		name.TextColor3 = Color3.fromRGB(255, 90, 90)
	elseif e.miniBoss then
		name.TextColor3 = Color3.fromRGB(255, 140, 60)
	elseif e.def.elite then
		name.TextColor3 = Color3.fromRGB(255, 200, 70)
	elseif e.kind == "animal" then
		name.TextColor3 = e.def.behavior == "aggressive" and Color3.fromRGB(255, 170, 150) or Color3.fromRGB(200, 240, 180)
	else
		name.TextColor3 = Color3.new(1, 1, 1)
	end
	name.Parent = gui

	local barWidth = big and 150 or 120
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, big and 10 or 0, 0, 23)
	bar.Size = UDim2.fromOffset(barWidth, big and 11 or 9)
	bar.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = e.dummy and Color3.fromRGB(220, 180, 90) or (e.miniBoss and Color3.fromRGB(255, 110, 40) or Color3.fromRGB(230, 60, 50))
	fill.BorderSizePixel = 0
	fill.Parent = bar
	for _, f in ipairs({ bar, fill }) do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end
	if e.miniBoss or e.isBoss then
		-- A skull next to the health bar marks bosses and camp champions.
		local skull = Instance.new("TextLabel")
		skull.Name = "Skull"
		skull.BackgroundTransparency = 1
		skull.AnchorPoint = Vector2.new(1, 0.5)
		skull.Position = UDim2.new(0, -3, 0.5, 0)
		skull.Size = UDim2.fromOffset(22, 22)
		skull.Font = Enum.Font.GothamBold
		skull.TextScaled = true
		skull.Text = "💀"
		skull.Parent = bar
	end

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(0, 35)
	statusLabel.Size = UDim2.new(1, 0, 0, 18)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Parent = gui

	gui.Parent = head
	e.nametag = gui
	for _, attr in ipairs({ "Stunned", "Slowed", "Poisoned", "Burning", "Blowing" }) do
		e.model:GetAttributeChangedSignal(attr):Connect(function()
			updateNametag(e)
		end)
	end
end

---------------------------------------------------------------- queries

-- The first surface below a point (props included). Casts from `fromAbove` studs above `pos`
-- so roofs and tree tops higher up are ignored.
local function groundAt(pos: Vector3, fromAbove: number?): Vector3
	local origin = pos + Vector3.new(0, fromAbove or 40, 0)
	local ray = workspace:Raycast(origin, Vector3.new(0, -400, 0), mapParams)
	if ray then
		return ray.Position
	end
	return Vector3.new(pos.X, 0, pos.Z)
end
EnemyService.groundAt = groundAt

-- The terrain surface only (spawn points: never on a roof, tent or tree). The second value is
-- the terrain material hit, so callers can avoid spawning in water.
local function terrainGround(pos: Vector3): (Vector3, Enum.Material?)
	local ray = workspace:Raycast(pos + Vector3.new(0, 120, 0), Vector3.new(0, -400, 0), terrainParams)
	if ray then
		return ray.Position, ray.Material
	end
	return Vector3.new(pos.X, 0, pos.Z), nil
end
EnemyService.terrainGround = terrainGround

local function spotIsClear(ground: Vector3): boolean
	local parts = workspace:GetPartBoundsInBox(CFrame.new(ground + Vector3.new(0, 5, 0)), Vector3.new(7, 8, 7), propParams)
	return #parts == 0
end
EnemyService.spotIsClear = spotIsClear

-- Dry, open ground to stand on (not water, not inside a prop).
function EnemyService.isGoodSpawn(pos: Vector3): (boolean, Vector3)
	local ground, material = terrainGround(pos)
	if material == Enum.Material.Water or ground.Y < Zones.WATER_LEVEL - 0.5 then
		return false, ground
	end
	return spotIsClear(ground), ground
end

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

-- Living dragons within `radius` (flat distance) of a point.
function EnemyService.dragonsNear(pos: Vector3, radius: number): number
	local n = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root = S.PlayerService.getCharacter(player)
		if root then
			local d = root.Position - pos
			if Vector3.new(d.X, 0, d.Z).Magnitude <= radius then
				n += 1
			end
		end
	end
	return n
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
	if e.dead or e.returning or e.dummy then
		return
	end
	if e.def.behavior == "flee" then
		e.fleeFrom = attacker
		e.fleeUntil = now() + 6
		return
	end
	if not e.target or not targetRoot(e, e.target) then
		if targetRoot(e, attacker) then
			e.target = attacker
		end
	end
end

---------------------------------------------------------------- registering

-- Register any model as something dragons can hit. opts:
--   def, typeId, displayName, level, scale, kind ("viking" | "animal" | "dummy" | "boss"),
--   camp, area, customAI, isBoss, miniBoss, arena, noRewards, onDeath, onHit, dummy, keepBody,
--   leash, aggroRange, speed, damage, defense, tagOffset, radius, height
function EnemyService.register(model: Model, humanoid: Humanoid, root: BasePart, opts)
	local def = opts.def or {}
	local scale = opts.scale or def.scale or 1
	local level = opts.level or 1
	local e = {
		model = model,
		humanoid = humanoid,
		root = root,
		def = def,
		kind = opts.kind or "viking",
		typeId = opts.typeId or def.id,
		displayName = opts.displayName or def.name or model.Name,
		level = level,
		scale = scale,
		radius = opts.radius or 1.4 * scale,
		height = opts.height or 3.6 * scale,
		damage = opts.damage or (def.damage or 0) * (1 + Enemies.DAMAGE_PER_LEVEL * (level - 1)) * (opts.damageMult or 1) * Tuning.global("enemyDamage"),
		defense = opts.defense or (def.defense or 0) * (1 + 0.15 * (level - 1)),
		baseSpeed = opts.speed or def.speed or 0,
		spawnPos = opts.spawnPos or root.Position,
		camp = opts.camp,
		area = opts.area,
		damageBy = {},
		target = nil,
		nextAttack = 0,
		nextThrow = now() + math.random() * 2,
		nextSlam = now() + 3,
		wanderAt = now() + math.random() * 4,
		lastPos = root.Position,
		stuckTime = 0,
		dead = false,
		returning = false,
		isBoss = opts.isBoss == true,
		miniBoss = opts.miniBoss == true,
		dummy = opts.dummy == true,
		customAI = opts.customAI == true or opts.dummy == true,
		arena = opts.arena == true,
		noRewards = opts.noRewards == true or opts.dummy == true,
		keepBody = opts.keepBody == true,
		onDeath = opts.onDeath,
		onHit = opts.onHit,
		leash = opts.leash or Game.ENEMY_LEASH,
		aggroRange = opts.aggroRange or def.aggroRange or 42,
		tagOffset = opts.tagOffset,
		slam = opts.slam,
	}
	enemies[model] = e
	createNametag(e)
	humanoid.HealthChanged:Connect(function()
		updateNametag(e)
	end)
	return e
end

local function makeHumanoid(model: Model, hipHeight: number, maxHealth: number, speed: number)
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
	humanoid.WalkSpeed = speed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 45
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid.Parent = model
	return humanoid
end

-- Spawn a viking (or, with opts.builder, any creature). opts are passed on to register, plus:
--   builder(look, scale, name) -> model, hipHeight   (default VikingBuilder.build)
--   look, healthMult, tag ("Viking" by default)
function EnemyService.spawn(typeId: string, level: number, position: Vector3, opts)
	opts = opts or {}
	local def = opts.def or Enemies.Vikings[typeId]
	if not def then
		warn("[EnemyService] Unknown enemy type", typeId)
		return nil
	end
	local scale = opts.scale or def.scale
	local displayName = opts.displayName or def.name
	local build = opts.builder or VikingBuilder.build
	local model, hipHeight = build(opts.look or def.look, scale, displayName)

	local maxHealth = math.floor(def.health * (1 + Enemies.HEALTH_PER_LEVEL * (level - 1)) * (opts.healthMult or 1) * Tuning.global("enemyHealth"))
	local humanoid = makeHumanoid(model, hipHeight, math.max(1, maxHealth), opts.speed or def.speed)
	if opts.keepBody then
		humanoid.BreakJointsOnDeath = false
	end

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Enemies"
		end
	end

	local ground = terrainGround(position)
	model:PivotTo(CFrame.new(ground + Vector3.new(0, hipHeight + model.PrimaryPart.Size.Y / 2 + 0.5, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	model.Parent = folder
	local root = model.PrimaryPart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	CollectionService:AddTag(model, opts.tag or "Viking")

	opts.def = def
	opts.typeId = typeId
	opts.level = level
	opts.scale = scale
	opts.displayName = displayName
	opts.spawnPos = ground
	return EnemyService.register(model, humanoid, root, opts)
end

local function spawnInCamp(camp, typeId: string)
	local pos = camp.center
	for _ = 1, 15 do
		local angle = math.random() * math.pi * 2
		local dist = math.sqrt(math.random()) * camp.radius
		pos = camp.center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		if EnemyService.isGoodSpawn(pos) then
			break
		end
	end
	local def = Enemies.Vikings[typeId]
	local level = def and def.elite and camp.levels[2] or math.random(camp.levels[1], camp.levels[2])
	EnemyService.spawn(typeId, level, pos, { camp = camp })
end

-- Make every viking in a camp go after one dragon (alarm horn, or someone opening the chest).
function EnemyService.alarmCamp(camp, player: Player)
	local t = now()
	for _, e in pairs(enemies) do
		if e.camp == camp and not e.dead and e.kind == "viking" then
			e.alarmedUntil = t + Game.ALARM_DURATION
			e.returning = false
			if targetRoot(e, player) then
				e.target = player
			end
		end
	end
end

---------------------------------------------------------------- death

local function reward(player: Player, e)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	if e.kind == "animal" then
		local xp = (8 + 5 * e.level) * (e.def.xpMult or 1)
		if profile.level - e.level >= Game.LOW_LEVEL_XP_PENALTY_GAP then
			xp *= Game.LOW_LEVEL_XP_MULT
		end
		profile.animalsHunted += 1
		S.PlayerService.addXP(player, xp)
		local got = S.PlayerService.addGold(player, math.random(1, 3) * (1 + 0.2 * e.level), true)
		S.CombatService.queueNumber(player, e.root.Position + Vector3.new(0, 4, 0), got, "gold")
		S.QuestService.progress(player, "hunt", e.typeId, 1)
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
	if e.miniBoss then
		S.QuestService.progress(player, "miniBoss", e.typeId, 1)
	end
end

function EnemyService.kill(e, killer: Player?)
	if e.dead or e.dummy then
		return
	end
	e.dead = true
	e.model:SetAttribute("Blowing", nil)
	if not e.keepBody then
		-- Let the body tumble onto the ground instead of sinking through it when the joints break.
		for _, p in ipairs(e.model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = true
				p.Massless = false
			end
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
		-- Everyone who helped gets their own drops, so teaming up never means losing the loot.
		-- Champions only reward helpers who are still around the camp.
		for player, dealt in pairs(e.damageBy) do
			if player.Parent and dealt > 0 and (not e.miniBoss or EnemyService.playerNearCamp(player, e.camp)) then
				reward(player, e)
			end
		end
	end
	if not e.keepBody then
		S.CombatService.broadcastVFX({ kind = "enemyDeath", pos = e.root.Position })
		task.delay(3, function()
			enemies[e.model] = nil
			e.model:Destroy()
		end)
	end
	if e.camp and e.kind == "viking" and not e.miniBoss then
		-- Fewer dragons in the camp = slower respawns, so a lone dragon can actually clear it.
		local dragons = EnemyService.dragonsNear(e.camp.center, e.camp.radius + 40)
		local delay = Game.ENEMY_RESPAWN * Game.campRespawnMult(dragons) + math.random() * 6
		task.delay(delay, function()
			spawnInCamp(e.camp, e.typeId)
		end)
	end
end

function EnemyService.playerNearCamp(player: Player, camp): boolean
	if not camp then
		return true
	end
	local _, _, root = S.PlayerService.getCharacter(player)
	return root ~= nil and (root.Position - camp.center).Magnitude <= camp.radius + 120
end

-- Forget a body that was kept around (animal carcasses) and remove it.
function EnemyService.forget(e)
	enemies[e.model] = nil
	if e.model.Parent then
		e.model:Destroy()
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

-- dmgOpts are passed to CombatService.damagePlayer (e.g. ignoreSafe / nonLethal for sparring).
-- `fromPos` overrides where the axe leaves from (default: just above the thrower's shoulders).
function EnemyService.throwAt(e, player: Player, root: BasePart, damage: number, style: string?, dmgOpts, fromPos: Vector3?)
	local from = fromPos or e.root.Position + Vector3.new(0, 1.8 * e.scale, 0)
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
				local o = { sourceLevel = e.level }
				for k, v in pairs(dmgOpts or {}) do
					o[k] = v
				end
				S.CombatService.damagePlayer(p, damage, o)
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
		local reach = (e.def.attackRange or 6) + 3 * ((player.Character and player.Character:GetAttribute("DragonScale")) or 1) + 2
		if flat <= reach and math.abs(offset.Y) <= 9 + e.scale * 2 then
			S.CombatService.damagePlayer(player, e.damage, { sourceLevel = e.level, melee = true, enemyInfo = e })
		end
	end)
end

-- Mini-boss special: a telegraphed ground slam that hits every dragon inside the ring.
local function slam(e)
	local cfg = e.slam
	local center = groundAt(e.root.Position, 8)
	S.CombatService.broadcastVFX({ kind = "telegraph", pos = center, radius = cfg.radius, duration = cfg.delay, color = Color3.fromRGB(255, 110, 40) })
	e.model:SetAttribute("Swing", now() + cfg.delay - 0.3)
	e.busyUntil = now() + cfg.delay + 0.3
	task.delay(cfg.delay, function()
		if e.dead then
			return
		end
		S.CombatService.broadcastVFX({ kind = "slam", pos = center, radius = cfg.radius, color = Color3.fromRGB(255, 140, 60) })
		for _, player in ipairs(Players:GetPlayers()) do
			local character, _, root = S.PlayerService.getCharacter(player)
			if character then
				local offset = root.Position - center
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= cfg.radius + 3 and offset.Y < 14 then
					S.CombatService.damagePlayer(player, e.damage * cfg.mult, { sourceLevel = e.level })
				end
			end
		end
	end)
end

-- Hornblower: stop, blow the horn for a moment, then (if still alive and not stunned) the whole
-- camp comes for the dragon.
local function startHorn(e, player: Player)
	local t = now()
	e.hornUntil = t + HORN_TIME
	e.hornTarget = player
	e.nextHorn = t + Game.ALARM_COOLDOWN
	e.model:SetAttribute("Blowing", true)
	S.CombatService.broadcastVFX({ kind = "hornWindup", pos = e.root.Position, time = HORN_TIME })
	for _, p in ipairs(Players:GetPlayers()) do
		local _, _, root = S.PlayerService.getCharacter(p)
		if root and (root.Position - e.root.Position).Magnitude < 160 then
			S.PlayerService.notify(p, "A Hornblower is raising the alarm! Stop him before he finishes!", Color3.fromRGB(255, 190, 80), "📯")
		end
	end
end

local function finishHorn(e)
	local player = e.hornTarget
	e.hornUntil = nil
	e.hornTarget = nil
	e.model:SetAttribute("Blowing", nil)
	if not player or not player.Parent or not e.camp then
		return
	end
	EnemyService.alarmCamp(e.camp, player)
	S.CombatService.broadcastVFX({ kind = "alarm", pos = e.root.Position })
	for _, p in ipairs(Players:GetPlayers()) do
		local _, _, root = S.PlayerService.getCharacter(p)
		if root and (root.Position - e.camp.center).Magnitude < e.camp.radius + 120 then
			Remotes.event("Announce"):FireClient(p, {
				title = "📯 ALARM!",
				text = "The whole " .. e.camp.name .. " is coming for you!",
				color = Color3.fromRGB(255, 120, 60),
				duration = 3,
				sound = "horn",
			})
		end
	end
end

local function findTarget(e)
	local best, bestDist = nil, math.huge
	local range = e.aggroRange
	if e.alarmedUntil and now() < e.alarmedUntil then
		range = math.max(range, (e.camp and e.camp.radius or 60) + 40)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = targetRoot(e, player)
		if root then
			local offset = root.Position - e.root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= range and math.abs(offset.Y) <= 70 and flat < bestDist then
				best, bestDist = player, flat
			end
		end
	end
	return best
end

local function wander(e, t: number, radius: number)
	if t >= e.wanderAt then
		e.wanderAt = t + 4 + math.random() * 6
		local angle = math.random() * math.pi * 2
		local r = math.random() * radius
		e.humanoid:MoveTo(e.spawnPos + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
	end
end

-- Timid animals: bolt away from the nearest dragon (or whoever hurt them).
local function thinkFlee(e, t: number)
	local threat = nil
	if e.fleeFrom and e.fleeUntil and t < e.fleeUntil then
		threat = targetRoot(e, e.fleeFrom)
	end
	if not threat then
		local range = e.def.fleeRange or 25
		for _, player in ipairs(Players:GetPlayers()) do
			local root = targetRoot(e, player)
			if root and (root.Position - e.root.Position).Magnitude < range then
				threat = root
				break
			end
		end
	end
	if threat then
		local away = e.root.Position - threat.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.1 then
			away = Vector3.new(1, 0, 0)
		end
		-- Veer back toward home if running would take it too far away.
		local goal = e.root.Position + away.Unit * 24
		if (goal - e.spawnPos).Magnitude > e.leash then
			goal = e.root.Position + (away.Unit + (e.spawnPos - e.root.Position).Unit * 1.2).Unit * 24
		end
		e.humanoid.WalkSpeed = e.baseSpeed * 1.25 * S.CombatService.speedMultiplier(e.model)
		e.humanoid:MoveTo(goal)
		return
	end
	wander(e, t, 30)
end

local function think(e, t: number, dt: number)
	local humanoid = e.humanoid
	local root = e.root
	local speedMult = S.CombatService.speedMultiplier(e.model)
	humanoid.WalkSpeed = e.baseSpeed * speedMult
	if speedMult == 0 then
		humanoid:MoveTo(root.Position)
		if e.hornUntil then
			-- Stunned mid-blow: the alarm fails.
			e.hornUntil = nil
			e.hornTarget = nil
			e.model:SetAttribute("Blowing", nil)
		end
		return
	end

	-- Blowing the alarm horn: stand still until it's done.
	if e.hornUntil then
		humanoid:MoveTo(root.Position)
		if t >= e.hornUntil then
			finishHorn(e)
		end
		return
	end
	if e.busyUntil and t < e.busyUntil then
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
	local leash = e.leash
	if e.alarmedUntil and t < e.alarmedUntil then
		leash += 60
	end
	if not e.arena and (root.Position - e.spawnPos).Magnitude > leash then
		e.target = nil
		e.returning = true
		e.damageBy = {}
		humanoid.Health = humanoid.MaxHealth
		humanoid:MoveTo(e.spawnPos)
		return
	end

	local behavior = e.def.behavior or "aggressive"
	if behavior == "flee" then
		thinkFlee(e, t)
		return
	end

	local troot = e.target and targetRoot(e, e.target)
	if not troot then
		e.target = nil
		if behavior == "aggressive" then
			e.target = findTarget(e)
		end
		troot = e.target and targetRoot(e, e.target)
	end

	if troot then
		local def = e.def
		-- Hornblowers sound the alarm the first time they spot someone.
		if def.alarm and e.camp and e.camp.alarm and t >= (e.nextHorn or 0) and not (e.alarmedUntil and t < e.alarmedUntil) then
			face(e, troot.Position)
			startHorn(e, e.target)
			return
		end

		local offset = troot.Position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		local vertical = math.abs(offset.Y)
		local attackRange = def.attackRange or 6
		local targetRadius = 3 * ((e.target.Character and e.target.Character:GetAttribute("DragonScale")) or 1)
		local inMelee = flat <= attackRange + targetRadius + e.scale and vertical <= 8 + e.scale * 2

		if e.slam and t >= e.nextSlam and flat <= e.slam.radius and vertical <= 14 then
			e.nextSlam = t + e.slam.cooldown
			humanoid:MoveTo(root.Position)
			face(e, troot.Position)
			slam(e)
			return
		end

		if inMelee then
			humanoid:MoveTo(root.Position)
			face(e, troot.Position)
			if t >= e.nextAttack then
				e.nextAttack = t + (def.attackCooldown or 1.5)
				meleeSwing(e, e.target)
			end
			return
		end

		if def.throwCooldown then
			local wantsThrow = vertical > 8 or (def.preferredRange or 0) > 0 or flat > attackRange * 3
			if wantsThrow and t >= e.nextThrow and (offset.Magnitude <= def.throwRange) then
				e.nextThrow = t + def.throwCooldown * (0.8 + math.random() * 0.4)
				face(e, troot.Position)
				EnemyService.throwAt(e, e.target, troot, e.damage * def.throwDamage, def.look.weapon == "hammer" and "hammer" or "axe")
			end
		end

		if (def.preferredRange or 0) > 0 then
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
		if moved < 0.4 * dt * 5 and flat > attackRange + targetRadius + 2 then
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
	wander(e, t, e.kind == "animal" and 30 or 22)
end

---------------------------------------------------------------- admin helpers

function EnemyService.respawnCamps()
	for _, e in pairs(enemies) do
		if e.camp and e.kind == "viking" and not e.miniBoss and not e.dead then
			EnemyService.despawn(e)
		end
	end
	for _, camp in ipairs(Zones.Camps) do
		for typeId, count in pairs(camp.spawns) do
			for _ = 1, count do
				spawnInCamp(camp, typeId)
			end
		end
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
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	terrainParams.IgnoreWater = false
	propParams.FilterType = Enum.RaycastFilterType.Include
	propParams.FilterDescendantsInstances = { map }

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
