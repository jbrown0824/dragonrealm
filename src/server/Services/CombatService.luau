-- Casting abilities, hit detection, damage math, status effects (slow, stun, poison, burn),
-- server-simulated projectiles and delayed strikes. Clients only draw the effects; every hit
-- is decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local StatCalc = require(Shared.StatCalc)
local Tuning = require(Shared.Tuning)
local Remotes = require(Shared.Remotes)

local CombatService = {}
local S

local cooldowns = {} -- [Player] = { [abilityId] = readyAt }
local status = {} -- [Model] = { slowPct, slowUntil, stunUntil, dots = {} }
local projectiles = {} -- [id] = projectile
local auras = {} -- [Player] = aura
local pendingNumbers = {} -- [Player] = { {pos, amount, kind} }
local mapParams = RaycastParams.new()

local function now()
	return os.clock()
end

local function broadcastVFX(data, except: Player?)
	local remote = Remotes.event("VFX")
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= except then
			remote:FireClient(p, data)
		end
	end
end
CombatService.broadcastVFX = broadcastVFX

local function queueNumber(player: Player?, pos: Vector3, amount: number, kind: string)
	if not player then
		return
	end
	local list = pendingNumbers[player]
	if not list then
		list = {}
		pendingNumbers[player] = list
	end
	if #list < 40 then
		table.insert(list, { pos = pos, amount = math.floor(amount + 0.5), kind = kind })
	end
end
CombatService.queueNumber = queueNumber

local function isFiniteVector(v): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function applyDefense(amount: number, defense: number, attackerLevel: number): number
	local reduction = defense / (defense + Game.DEFENSE_CONSTANT + 5 * attackerLevel)
	return amount * (1 - math.min(reduction, Game.MAX_DAMAGE_REDUCTION))
end

local function playerFromModel(model: Model): Player?
	return Players:GetPlayerFromCharacter(model)
end

---------------------------------------------------------------- status effects

local function getStatus(model: Model)
	local s = status[model]
	if not s then
		s = { slowPct = 0, slowUntil = 0, stunUntil = 0, dots = {} }
		status[model] = s
	end
	return s
end

local function refreshModel(model: Model)
	local p = playerFromModel(model)
	if p then
		S.PlayerService.refreshMovement(p)
	end
end

function CombatService.applySlow(model: Model, pct: number, duration: number)
	local s = getStatus(model)
	local t = now()
	if s.slowUntil < t or pct >= s.slowPct then
		s.slowPct = math.clamp(pct, 0, 80)
	end
	s.slowUntil = math.max(s.slowUntil, t + duration)
	model:SetAttribute("Slowed", true)
	refreshModel(model)
	task.delay(duration + 0.05, function()
		if model.Parent and now() >= s.slowUntil then
			model:SetAttribute("Slowed", false)
			refreshModel(model)
		end
	end)
end

function CombatService.applyStun(model: Model, duration: number)
	local s = getStatus(model)
	s.stunUntil = math.max(s.stunUntil, now() + duration)
	model:SetAttribute("Stunned", true)
	refreshModel(model)
	task.delay(duration + 0.05, function()
		if model.Parent and now() >= s.stunUntil then
			model:SetAttribute("Stunned", false)
			refreshModel(model)
		end
	end)
end

function CombatService.applyDot(model: Model, kind: string, total: number, duration: number, attacker: Player?)
	if total <= 0 then
		return
	end
	local s = getStatus(model)
	local ticks = math.max(1, math.floor(duration / 0.5))
	for _, dot in ipairs(s.dots) do
		if dot.kind == kind and dot.attacker == attacker then
			local remaining = dot.perTick * dot.ticks + total
			dot.ticks = math.max(dot.ticks, ticks)
			dot.perTick = remaining / dot.ticks
			return
		end
	end
	table.insert(s.dots, { kind = kind, perTick = total / ticks, ticks = ticks, attacker = attacker })
	model:SetAttribute(kind == "poison" and "Poisoned" or "Burning", true)
end

function CombatService.isStunned(model: Model): boolean
	local s = status[model]
	return s ~= nil and s.stunUntil > now()
end

function CombatService.speedMultiplier(model: Model): number
	local s = status[model]
	if not s then
		return 1
	end
	local t = now()
	if s.stunUntil > t then
		return 0
	end
	if s.slowUntil > t then
		return 1 - s.slowPct / 100
	end
	return 1
end

function CombatService.clearStatus(model: Model)
	status[model] = nil
end

---------------------------------------------------------------- damage

function CombatService.canPvP(player: Player): boolean
	return player:GetAttribute("InBattleZone") == true and not S.BossService.isInFight(player)
end

-- Everything a player could hit right now.
function CombatService.collectTargets(attacker: Player?)
	local list = {}
	for _, e in ipairs(S.EnemyService.alive()) do
		table.insert(list, { model = e.model, humanoid = e.humanoid, root = e.root, radius = e.radius, enemy = e })
	end
	if attacker and CombatService.canPvP(attacker) then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= attacker and CombatService.canPvP(other) then
				local character, humanoid, root = S.PlayerService.getCharacter(other)
				if character then
					local scale = character:GetAttribute("DragonScale") or 1
					table.insert(list, { model = character, humanoid = humanoid, root = root, radius = 3 * scale, player = other })
				end
			end
		end
	end
	return list
end

local function applyEffects(attacker: Player?, target, effects, dealt: number, fromPos: Vector3?)
	if not effects or dealt <= 0 then
		return
	end
	local model = target.model
	if (effects.slowPct or 0) > 0 then
		CombatService.applySlow(model, effects.slowPct, effects.slowDuration or 2)
	end
	if (effects.stun or 0) > 0 then
		local duration = effects.stun
		if target.player then
			duration *= 0.4
		elseif target.enemy and target.enemy.isBoss then
			duration *= 0.25
		end
		CombatService.applyStun(model, duration)
	end
	if (effects.poisonPct or 0) > 0 then
		CombatService.applyDot(model, "poison", dealt * effects.poisonPct / 100, 4, attacker)
	end
	if (effects.burnPct or 0) > 0 then
		CombatService.applyDot(model, "burn", dealt * effects.burnPct / 100, 3, attacker)
	end
	if (effects.knockback or 0) > 0 and fromPos and target.enemy and not target.enemy.isBoss then
		local root = target.root
		local away = root.Position - fromPos
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 0.1 then
			root.AssemblyLinearVelocity = away.Unit * effects.knockback + Vector3.new(0, 14, 0)
		end
	end
end

function CombatService.damageEnemy(attacker: Player?, info, amount: number, crit: boolean, opts)
	opts = opts or {}
	if info.dead then
		return 0
	end
	local humanoid = info.humanoid
	amount = math.max(1, math.floor(amount + 0.5))
	local before = humanoid.Health
	humanoid.Health = math.max(0, before - amount)
	local dealt = before - humanoid.Health

	-- Training dummies soak up everything and report it to the DPS meter.
	if info.dummy then
		humanoid.Health = humanoid.MaxHealth
		dealt = amount
		if attacker then
			queueNumber(attacker, info.root.Position + Vector3.new(0, info.height, 0), amount, opts.dotKind or (crit and "crit" or "hit"))
			if info.onHit then
				info.onHit(attacker, amount)
			end
		end
		return dealt
	end

	if attacker then
		info.damageBy[attacker] = (info.damageBy[attacker] or 0) + dealt
		S.EnemyService.onDamaged(info, attacker)
		local kind = opts.dotKind or (crit and "crit" or "hit")
		queueNumber(attacker, info.root.Position + Vector3.new(0, info.height, 0), amount, kind)
		if not opts.dotKind then
			local stats = S.PlayerService.getStats(attacker)
			local steal = (stats and stats.lifesteal or 0) + (opts.lifestealBonus or 0)
			if steal > 0 then
				S.PlayerService.heal(attacker, dealt * steal / 100)
			end
		end
	end

	if humanoid.Health <= 0 then
		S.EnemyService.kill(info, attacker)
	end
	return dealt
end

-- Damage a player's dragon. opts: attackerPlayer, sourceLevel, crit, melee, enemyInfo, dotKind,
-- lifestealBonus, ignoreSafe (hurts even in town: the sparring golem), nonLethal (never below 1 HP)
function CombatService.damagePlayer(victim: Player, amount: number, opts)
	opts = opts or {}
	local character, humanoid, root = S.PlayerService.getCharacter(victim)
	local st = S.PlayerService.state[victim]
	if not character or not st or not st.stats then
		return 0
	end
	if victim:GetAttribute("GodMode") then
		queueNumber(victim, root.Position + Vector3.new(0, 4, 0), 0, "dodge")
		return 0
	end
	-- Vikings can't hurt you in town.
	if not opts.attackerPlayer and not opts.ignoreSafe then
		local area = Zones.areaAt(root.Position)
		if area and area.safe then
			return 0
		end
	end
	local stats = st.stats

	if not opts.dotKind and math.random() * 100 < stats.dodge then
		queueNumber(victim, root.Position + Vector3.new(0, 4, 0), 0, "dodge")
		if opts.attackerPlayer then
			queueNumber(opts.attackerPlayer, root.Position + Vector3.new(0, 4, 0), 0, "dodge")
		end
		return 0
	end

	if not opts.dotKind then
		amount = applyDefense(amount, stats.defense, opts.sourceLevel or 1)
	end
	amount = math.max(1, math.floor(amount + 0.5))
	st.lastDamaged = now()

	if humanoid.Health - amount <= 0 and (stats.cheatDeath or 0) > 0 and now() >= st.cheatDeathReady then
		st.cheatDeathReady = now() + 90
		humanoid.Health = humanoid.MaxHealth * 0.3
		S.PlayerService.notify(victim, "Undying Titan! You refused to fall.", Color3.fromRGB(255, 200, 80), "🛡️")
		broadcastVFX({ kind = "levelUp", character = character })
		return 0
	end

	local before = humanoid.Health
	humanoid.Health = math.max(opts.nonLethal and math.min(1, before) or 0, before - amount)
	local dealt = before - humanoid.Health

	queueNumber(victim, root.Position + Vector3.new(0, 5, 0), amount, opts.dotKind or "taken")
	if opts.attackerPlayer then
		queueNumber(opts.attackerPlayer, root.Position + Vector3.new(0, 5, 0), amount, opts.dotKind or (opts.crit and "crit" or "hit"))
		if not opts.dotKind then
			local aStats = S.PlayerService.getStats(opts.attackerPlayer)
			local steal = (aStats and aStats.lifesteal or 0) + (opts.lifestealBonus or 0)
			if steal > 0 then
				S.PlayerService.heal(opts.attackerPlayer, dealt * steal / 100)
			end
		end
	end

	-- Thorns reflect melee hits back at vikings.
	if opts.melee and opts.enemyInfo and stats.thorns > 0 and not opts.enemyInfo.dead then
		CombatService.damageEnemy(victim, opts.enemyInfo, amount * stats.thorns / 100, false, { dotKind = "thorns" })
	end

	if humanoid.Health <= 0 and opts.attackerPlayer then
		S.PvPService.onKill(opts.attackerPlayer, victim)
	end
	return dealt
end

-- One hit from a player's ability on one target.
local function hitTarget(ctx, target, mult: number, effects, fromPos: Vector3?, critBonus: number?)
	local stats = ctx.stats
	if target.humanoid.Health <= 0 then
		return
	end
	local dmg = stats.attack * mult * ctx.ambush * Tuning.global("playerDamage")
	local crit = math.random() * 100 < stats.critChance + (critBonus or 0)
	if crit then
		dmg *= stats.critDamage / 100
	end
	if target.humanoid.Health / math.max(1, target.humanoid.MaxHealth) < 0.3 then
		dmg *= 1 + stats.executePct / 100
	end

	if target.enemy then
		local e = target.enemy
		if e.isBoss then
			dmg *= 1 + stats.bossPct / 100
		end
		dmg = applyDefense(dmg, e.defense, stats.level)
		local dealt = CombatService.damageEnemy(ctx.player, e, dmg, crit, { lifestealBonus = effects and effects.lifestealBonus })
		applyEffects(ctx.player, target, effects, dealt, fromPos)
	elseif target.player then
		dmg *= (1 + stats.pvpPct / 100) * Game.PVP_DAMAGE_MULT
		local dealt = CombatService.damagePlayer(target.player, dmg, {
			attackerPlayer = ctx.player,
			sourceLevel = stats.level,
			crit = crit,
			lifestealBonus = effects and effects.lifestealBonus,
		})
		applyEffects(ctx.player, target, effects, dealt, fromPos)
	end
end

local function aoe(ctx, center: Vector3, radius: number, mult: number, effects, verticalReach: number?)
	local count = 0
	for _, target in ipairs(CombatService.collectTargets(ctx.player)) do
		local offset = target.root.Position - center
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if flat <= radius + target.radius and math.abs(offset.Y) <= (verticalReach or radius) + target.radius then
			hitTarget(ctx, target, mult, effects, center)
			count += 1
		end
	end
	return count
end

---------------------------------------------------------------- projectiles

local function closestPointOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return a
	end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return a + ab * t
end

local function explodeProjectile(id: string, proj, pos: Vector3)
	projectiles[id] = nil
	broadcastVFX({ kind = "projectileHit", id = id, pos = pos, radius = proj.ability.radius, classId = proj.ctx.classId, abilityId = proj.ability.id })
	aoe(proj.ctx, pos, proj.ability.radius, proj.ability.damageMult, proj.ability.effects, proj.ability.radius)
end

local function stepProjectiles(dt: number)
	for id, proj in pairs(projectiles) do
		local step = proj.speed * dt
		local from = proj.pos
		local to = from + proj.dir * step
		local hitPos = nil
		local ray = workspace:Raycast(from, proj.dir * step, mapParams)
		if ray then
			hitPos = ray.Position
			to = ray.Position
		end
		local bestDist = math.huge
		for _, target in ipairs(CombatService.collectTargets(proj.ctx.player)) do
			local p = closestPointOnSegment(from, to, target.root.Position)
			local d = (p - target.root.Position).Magnitude
			if d <= proj.hitRadius + target.radius then
				local along = (p - from).Magnitude
				if along < bestDist then
					bestDist = along
					hitPos = p
				end
			end
		end
		proj.pos = to
		proj.traveled += step
		if hitPos then
			explodeProjectile(id, proj, hitPos)
		elseif proj.traveled >= proj.range then
			explodeProjectile(id, proj, to)
		end
	end
end

---------------------------------------------------------------- casting

local function groundBelow(pos: Vector3): Vector3
	local ray = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), mapParams)
	if ray then
		return ray.Position
	end
	return Vector3.new(pos.X, 0, pos.Z)
end

local function setStealth(player: Player, on: boolean)
	local st = S.PlayerService.state[player]
	local character = player.Character
	if not st then
		return
	end
	if on then
		if character then
			character:SetAttribute("Stealthed", true)
		end
		S.EnemyService.dropAggro(player)
	else
		st.stealthUntil = 0
		if character then
			character:SetAttribute("Stealthed", false)
		end
	end
end

local function flatDirection(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local d = to - from
	d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude < 0.1 then
		d = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if d.Magnitude < 0.1 then
		return Vector3.new(0, 0, -1)
	end
	return d.Unit
end

local function cast(player: Player, abilityId: string, aim: Vector3, projectileId: string?)
	local character, humanoid, root = S.PlayerService.getCharacter(player)
	local st = S.PlayerService.state[player]
	if not character or not st or not st.stats then
		return
	end
	if CombatService.isStunned(character) then
		return
	end
	local stats = st.stats
	if not table.find(stats.abilities, abilityId) then
		return
	end
	local ability = StatCalc.resolveAbility(abilityId, stats.classId, stats)
	if not ability then
		return
	end

	local cds = cooldowns[player]
	if not cds then
		cds = {}
		cooldowns[player] = cds
	end
	local t = now()
	if t < (cds[abilityId] or 0) - 0.15 then
		return
	end
	cds[abilityId] = t + (player:GetAttribute("NoCooldowns") and math.min(ability.cooldown, 0.2) or ability.cooldown)

	if not isFiniteVector(aim) then
		aim = root.Position + root.CFrame.LookVector * 30
	end
	local offset = aim - root.Position
	if offset.Magnitude > 300 then
		aim = root.Position + offset.Unit * 300
	end

	local ctx = { player = player, stats = stats, classId = stats.classId, ambush = 1 }
	local damaging = ability.kind ~= "buff" and ability.kind ~= "heal"
	if damaging and t < st.stealthUntil then
		ctx.ambush = 1 + st.ambushMult
		setStealth(player, false)
	end

	local head = character:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	local origin = mouth and mouth.WorldPosition or root.Position

	if ability.kind == "breath" then
		local dir = aim - origin
		if dir.Magnitude < 1 then
			dir = root.CFrame.LookVector
		end
		dir = dir.Unit
		broadcastVFX({ kind = "breath", character = character, dir = dir, classId = stats.classId, duration = ability.cooldown + 0.15 }, player)
		local cosLimit = math.cos(math.rad(ability.angle))
		for _, target in ipairs(CombatService.collectTargets(player)) do
			local to = target.root.Position - origin
			local dist = to.Magnitude
			if dist <= ability.range + target.radius then
				if dist < 5 + target.radius or dir:Dot(to.Unit) >= cosLimit then
					hitTarget(ctx, target, ability.damageMult, ability.effects, origin, ability.critBonus)
				end
			end
		end
	elseif ability.kind == "projectile" then
		local baseDir = aim - origin
		if baseDir.Magnitude < 1 then
			baseDir = root.CFrame.LookVector
		end
		baseDir = baseDir.Unit
		local count = ability.count or 1
		local spread = ability.spread or 0
		local baseId = (type(projectileId) == "string" and #projectileId < 60) and projectileId or (player.UserId .. "_" .. math.floor(t * 1000))
		local list = {}
		for i = 1, count do
			local angle = 0
			if count > 1 then
				angle = -spread / 2 + spread * (i - 1) / (count - 1)
			end
			local dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(angle)) * baseDir
			local id = baseId .. "_" .. i
			projectiles[id] = {
				ctx = ctx,
				ability = ability,
				pos = origin,
				dir = dir,
				speed = ability.speed,
				range = ability.range,
				traveled = 0,
				hitRadius = (ability.size or 1.5) * 0.8 + 1,
			}
			table.insert(list, { id = id, dir = dir })
		end
		broadcastVFX({ kind = "projectiles", origin = origin, list = list, speed = ability.speed, range = ability.range, size = ability.size, classId = stats.classId, abilityId = abilityId }, player)
	elseif ability.kind == "nova" then
		local center = root.Position
		broadcastVFX({ kind = "nova", pos = center, radius = ability.radius, classId = stats.classId, abilityId = abilityId }, nil)
		aoe(ctx, center, ability.radius, ability.damageMult, ability.effects, 14)
	elseif ability.kind == "strike" then
		local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		local target = aim
		if flat.Magnitude > ability.castRange then
			target = root.Position + flat.Unit * ability.castRange
		end
		local pos = groundBelow(target)
		broadcastVFX({ kind = "strike", pos = pos, radius = ability.radius, delay = ability.delay, style = ability.style, classId = stats.classId }, nil)
		task.delay(ability.delay, function()
			if player.Parent then
				aoe(ctx, pos, ability.radius, ability.damageMult, ability.effects, ability.radius + 10)
			end
		end)
	elseif ability.kind == "dash" then
		local dir = flatDirection(root.Position, aim, root.CFrame.LookVector)
		local start = root.Position
		local finish = start + dir * ability.distance
		local ray = workspace:Raycast(start, dir * ability.distance, mapParams)
		if ray then
			finish = ray.Position - dir * 3
		end
		broadcastVFX({ kind = "dash", character = character, from = start, to = finish, classId = stats.classId }, player)
		for _, target in ipairs(CombatService.collectTargets(player)) do
			local p = closestPointOnSegment(start, finish, target.root.Position)
			if (p - target.root.Position).Magnitude <= ability.width / 2 + target.radius then
				hitTarget(ctx, target, ability.damageMult, ability.effects, start)
			end
		end
	elseif ability.kind == "buff" then
		if ability.stats then
			S.PlayerService.addBuff(player, ability.id, ability.duration, ability.stats)
		end
		if ability.healPct then
			S.PlayerService.heal(player, humanoid.MaxHealth * ability.healPct / 100)
		end
		if ability.stealth then
			st.stealthUntil = t + ability.duration
			st.ambushMult = ability.ambushMult or 1
			setStealth(player, true)
			task.delay(ability.duration, function()
				if player.Parent and st.stealthUntil > 0 and now() >= st.stealthUntil - 0.05 then
					setStealth(player, false)
				end
			end)
		end
		if ability.aura then
			auras[player] = {
				untilTime = t + ability.duration,
				nextTick = t,
				radius = ability.aura.radius,
				mult = ability.aura.mult * (1 + stats.abilityPct / 100),
				interval = ability.aura.interval,
				effects = { slowPct = ability.aura.slowPct, slowDuration = 1.5 },
			}
		end
		broadcastVFX({ kind = "buff", character = character, duration = ability.duration, classId = stats.classId, abilityId = abilityId }, nil)
	elseif ability.kind == "heal" then
		S.PlayerService.heal(player, humanoid.MaxHealth * (ability.healPct or 0) / 100)
		if ability.buff then
			S.PlayerService.addBuff(player, ability.id, ability.buff.duration, ability.buff.stats)
		end
		broadcastVFX({ kind = "heal", character = character, classId = stats.classId }, nil)
	end
end

---------------------------------------------------------------- loops

local function tickStatus()
	for model, s in pairs(status) do
		if not model.Parent then
			status[model] = nil
			continue
		end
		local victim = playerFromModel(model)
		local info = S.EnemyService.getInfo(model)
		local hasPoison, hasBurn = false, false
		for i = #s.dots, 1, -1 do
			local dot = s.dots[i]
			dot.ticks -= 1
			if info and not info.dead then
				CombatService.damageEnemy(dot.attacker, info, dot.perTick, false, { dotKind = dot.kind })
			elseif victim and dot.attacker then
				CombatService.damagePlayer(victim, dot.perTick, { attackerPlayer = dot.attacker, dotKind = dot.kind })
			end
			if dot.ticks <= 0 then
				table.remove(s.dots, i)
			elseif dot.kind == "poison" then
				hasPoison = true
			else
				hasBurn = true
			end
		end
		if model:GetAttribute("Poisoned") and not hasPoison then
			model:SetAttribute("Poisoned", false)
		end
		if model:GetAttribute("Burning") and not hasBurn then
			model:SetAttribute("Burning", false)
		end
	end
end

local function tickAuras()
	local t = now()
	for player, aura in pairs(auras) do
		local character, _, root = S.PlayerService.getCharacter(player)
		if not character or t >= aura.untilTime or not player.Parent then
			auras[player] = nil
		elseif t >= aura.nextTick then
			aura.nextTick = t + aura.interval
			local stats = S.PlayerService.getStats(player)
			if stats then
				local ctx = { player = player, stats = stats, classId = stats.classId, ambush = 1 }
				aoe(ctx, root.Position, aura.radius, aura.mult, aura.effects, 14)
			end
		end
	end
end

function CombatService.init(services)
	S = services
end

function CombatService.start()
	local map = workspace:WaitForChild("Map")
	mapParams.FilterType = Enum.RaycastFilterType.Include
	mapParams.FilterDescendantsInstances = { map, workspace.Terrain }
	mapParams.IgnoreWater = true

	Remotes.event("CastAbility").OnServerEvent:Connect(function(player, abilityId, aim, projectileId)
		if type(abilityId) ~= "string" then
			return
		end
		cast(player, abilityId, aim, projectileId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
		auras[player] = nil
		pendingNumbers[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		stepProjectiles(dt)
		tickAuras()
		for player, list in pairs(pendingNumbers) do
			if #list > 0 and player.Parent then
				Remotes.event("DamageNumber"):FireClient(player, list)
			end
			pendingNumbers[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			tickStatus()
		end
	end)
end

return CombatService
