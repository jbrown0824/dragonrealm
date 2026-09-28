-- World bosses. Every Game.BOSS_INTERVAL seconds a viking boss attacks. Three minutes before it
-- arrives the whole server is warned and anyone can join the queue. When it spawns, everyone
-- in the queue is teleported to the Boss Arena and the boss is scaled to their combined power:
-- its health is set so the group can kill it in about Game.BOSS_TARGET_FIGHT_SECONDS, and its
-- hits are tuned to the group's average health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Enemies = require(Shared.Config.Enemies)
local Zones = require(Shared.Config.Zones)
local StatCalc = require(Shared.StatCalc)
local Remotes = require(Shared.Remotes)

local BossService = {}
local S

local phase = "idle" -- "idle" | "warning" | "fight" | "ending"
local nextSpawnAt = 0
local bossRotation = 0
local currentBossId = nil
local queue = {} -- [Player] = true
local fight = nil

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function listUserIds(set)
	local ids = {}
	for player in pairs(set) do
		if player.Parent then
			table.insert(ids, player.UserId)
		end
	end
	return ids
end

local function broadcastState()
	local def = currentBossId and Enemies.Bosses[currentBossId]
	local data = {
		phase = phase,
		bossId = currentBossId,
		name = def and def.name,
		title = def and def.title,
		spawnAt = nextSpawnAt,
		queue = listUserIds(queue),
	}
	if fight then
		data.participants = listUserIds(fight.participants)
		data.endsAt = fight.endsAt
		data.maxLives = Game.BOSS_LIVES
		data.lives = {}
		for player, lives in pairs(fight.lives) do
			data.lives[tostring(player.UserId)] = lives
		end
		if fight.boss and not fight.boss.dead then
			data.hp = fight.boss.humanoid.Health
			data.maxHp = fight.boss.humanoid.MaxHealth
		else
			data.hp = 0
			data.maxHp = 1
		end
	end
	Remotes.event("BossState"):FireAllClients(data)
end

local function announce(title: string, text: string, color: Color3, duration: number?)
	Remotes.event("Announce"):FireAllClients({ title = title, text = text, color = color, duration = duration or 6, sound = "horn" })
end

---------------------------------------------------------------- queries used by other services

function BossService.isInFight(player: Player): boolean
	return fight ~= nil and fight.participants[player] == true
end

function BossService.getArenaSpawn(player: Player): CFrame?
	if not BossService.isInFight(player) then
		return nil
	end
	local c = Zones.BossArena.center
	local angle = math.random() * math.pi * 2
	local pos = c + Vector3.new(math.cos(angle) * 70, 6, math.sin(angle) * 70)
	return CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
end

-- Take a player out of the current fight (knocked out or left) and send them back to town.
local function removeFromFight(player: Player, reason: string)
	if not fight or not fight.participants[player] then
		return
	end
	fight.participants[player] = nil
	fight.out[player] = reason
	player:SetAttribute("InBossFight", false)
	if S.PlayerService.getCharacter(player) then
		S.PlayerService.teleport(player, S.PlayerService.getSpawnCFrame(player))
	end
	broadcastState()
end

-- Called by PlayerService whenever a dragon dies.
function BossService.onPlayerDied(player: Player)
	if not fight or phase ~= "fight" or not fight.participants[player] then
		return
	end
	local left = (fight.lives[player] or Game.BOSS_LIVES) - 1
	fight.lives[player] = left
	if left <= 0 then
		removeFromFight(player, "lives")
		S.PlayerService.notify(player, "You're out of lives! You'll wake up back in town.", Color3.fromRGB(255, 120, 110), "💔")
	else
		S.PlayerService.notify(player, string.format("You have %d %s left in this fight!", left, left == 1 and "life" or "lives"), Color3.fromRGB(255, 170, 120), "❤️")
		broadcastState()
	end
end

local function leaveFight(player: Player)
	if not fight or not fight.participants[player] then
		return false, "You're not in a boss fight."
	end
	removeFromFight(player, "left")
	S.PlayerService.notify(player, "You fled the boss fight.", Color3.fromRGB(220, 220, 230), "🚪")
	return true
end

---------------------------------------------------------------- queue

local function joinQueue(player: Player, join: boolean)
	if phase ~= "warning" then
		return false, "There is no boss to queue for right now."
	end
	local profile = S.PlayerService.getProfile(player)
	if not profile or not profile.class then
		return false, "Choose your dragon first!"
	end
	if join then
		queue[player] = true
		S.PlayerService.notify(player, "You joined the boss queue! You'll be teleported when the boss arrives.", Color3.fromRGB(255, 200, 90), "⚔️")
	else
		queue[player] = nil
	end
	broadcastState()
	return true
end

---------------------------------------------------------------- fight

local function participantsList()
	local list = {}
	for player in pairs(fight.participants) do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

local function aliveParticipants()
	local list = {}
	for player in pairs(fight.participants) do
		local character, _, root = S.PlayerService.getCharacter(player)
		if character then
			table.insert(list, { player = player, root = root, character = character })
		end
	end
	return list
end

local function telegraph(pos: Vector3, radius: number, delay: number, color: Color3?)
	S.CombatService.broadcastVFX({ kind = "telegraph", pos = pos, radius = radius, duration = delay, color = color })
end

local function hitPlayersInRadius(center: Vector3, radius: number, damage: number, maxHeight: number, effects)
	for _, p in ipairs(aliveParticipants()) do
		local offset = p.root.Position - center
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if flat <= radius + 3 and offset.Y <= maxHeight then
			S.CombatService.damagePlayer(p.player, damage, { sourceLevel = fight.level })
			if effects and effects.slowPct then
				S.CombatService.applySlow(p.character, effects.slowPct, 3)
			end
		end
	end
end

local function bossAttack(name: string, cfg, target)
	local boss = fight.boss
	local root = boss.root
	local hit = fight.hit * (cfg.mult or 1) * (fight.enraged and 1.25 or 1)

	if name == "Cleave" then
		boss.model:SetAttribute("Swing", os.clock())
		local range = cfg.range * (boss.scale / 3)
		task.delay(0.55, function()
			if boss.dead or not fight then
				return
			end
			local look = root.CFrame.LookVector
			for _, p in ipairs(aliveParticipants()) do
				local offset = p.root.Position - root.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if flat.Magnitude <= range + 4 and offset.Y < 20 then
					if flat.Magnitude < 6 or look:Dot(flat.Unit) > 0.2 then
						S.CombatService.damagePlayer(p.player, hit, { sourceLevel = fight.level })
					end
				end
			end
		end)
	elseif name == "GroundSlam" then
		local center = S.EnemyService.groundAt(root.Position, 10)
		telegraph(center, cfg.radius, cfg.delay, Color3.fromRGB(255, 60, 40))
		boss.model:SetAttribute("Swing", os.clock() + cfg.delay - 0.3)
		task.delay(cfg.delay, function()
			if boss.dead or not fight then
				return
			end
			S.CombatService.broadcastVFX({ kind = "slam", pos = center, radius = cfg.radius, color = Enemies.Bosses[currentBossId].color })
			hitPlayersInRadius(center, cfg.radius, hit, 14, { slowPct = cfg.slowPct })
		end)
	elseif name == "RuneStrikes" then
		local players = aliveParticipants()
		for i = 1, cfg.count do
			local p = players[((i - 1) % math.max(1, #players)) + 1]
			if p then
				local jitter = i > #players and Vector3.new(math.random(-25, 25), 0, math.random(-25, 25)) or Vector3.new()
				local pos = S.EnemyService.groundAt(p.root.Position + jitter, 10)
				telegraph(pos, cfg.radius, cfg.delay, Enemies.Bosses[currentBossId].color)
				task.delay(cfg.delay, function()
					if boss.dead or not fight then
						return
					end
					S.CombatService.broadcastVFX({ kind = "strike", pos = pos, radius = cfg.radius, delay = 0, style = "lightning", color = Enemies.Bosses[currentBossId].color })
					hitPlayersInRadius(pos, cfg.radius, hit, 25, nil)
				end)
			end
		end
	elseif name == "AxeVolley" then
		local players = aliveParticipants()
		for i = 1, math.min(cfg.count, #players * 2) do
			local p = players[((i - 1) % #players) + 1]
			task.delay((i - 1) * 0.2, function()
				if boss.dead or not fight or not p.root.Parent then
					return
				end
				S.EnemyService.throwAt(boss, p.player, p.root, hit, "axe")
			end)
		end
	end
end

local function summonAdds()
	local cfg = Enemies.Bosses[currentBossId].attacks.Summon
	if not cfg then
		return
	end
	local c = Zones.BossArena.center
	for i = 1, cfg.count do
		local angle = (i / cfg.count) * math.pi * 2
		local pos = c + Vector3.new(math.cos(angle) * 40, 0, math.sin(angle) * 40)
		local add = S.EnemyService.spawn(cfg.add, math.max(1, fight.level - 3), pos, {
			arena = true,
			noRewards = true,
			aggroRange = 200,
			leash = 400,
			healthMult = 0.6 + 0.2 * #participantsList(),
		})
		if add then
			table.insert(fight.adds, add)
		end
	end
	announce("⚠️ REINFORCEMENTS", Enemies.Bosses[currentBossId].name .. " calls for help!", Color3.fromRGB(255, 140, 60), 3)
end

local function cleanupFight()
	if not fight then
		return
	end
	for _, add in ipairs(fight.adds) do
		if not add.dead then
			S.EnemyService.despawn(add)
		end
	end
	if fight.boss and fight.boss.model.Parent and not fight.boss.dead then
		S.EnemyService.despawn(fight.boss)
	end
end

local function endFight(victory: boolean)
	if not fight or phase == "ending" then
		return
	end
	phase = "ending"
	local def = Enemies.Bosses[currentBossId]
	local players = participantsList()

	if victory then
		local names = {}
		local topPlayer, topDamage = nil, -1
		for player, dmg in pairs(fight.boss.damageBy) do
			if dmg > topDamage and player.Parent then
				topPlayer, topDamage = player, dmg
			end
		end
		for _, player in ipairs(players) do
			table.insert(names, player.DisplayName)
			local profile = S.PlayerService.getProfile(player)
			if profile then
				profile.bossKills += 1
				local ilvl = profile.level + 2
				local items = {}
				local rarity = math.random() < 0.3 and "Legendary" or "Epic"
				table.insert(items, S.LootService.rollGear(ilvl, 0, nil, rarity))
				if math.random() < 0.25 then
					local uniqueId = def.uniques[math.random(1, #def.uniques)]
					table.insert(items, S.LootService.rollUnique(uniqueId, ilvl))
				end
				local seeds = {}
				for _ = 1, math.random(1, 2) do
					local seedId = S.LootService.rollSeed(1.5)
					seeds[seedId] = (seeds[seedId] or 0) + 1
				end
				local gold = 400 + 80 * profile.level
				if player == topPlayer then
					gold = math.floor(gold * 1.5)
					local bonusSeed = S.LootService.rollSeed(3)
					seeds[bonusSeed] = (seeds[bonusSeed] or 0) + 1
					S.PlayerService.notify(player, "Top damage! +50% gold and a bonus seed.", Color3.fromRGB(255, 200, 60), "🥇")
				end
				local eggs = nil
				if math.random() < 0.35 then
					eggs = { [S.LootService.rollEgg(2)] = 1 }
				end
				S.LootService.grant(player, {
					xp = math.floor(Game.xpToNext(profile.level) * 0.6) + 500,
					gold = gold,
					items = items,
					seeds = seeds,
					eggs = eggs,
				})
				S.QuestService.progress(player, "bossKill", nil, 1)
			end
		end
		-- Dragons knocked out along the way still get a share of XP and gold.
		for player, reason in pairs(fight.out) do
			local profile = player.Parent and reason == "lives" and S.PlayerService.getProfile(player)
			if profile then
				S.LootService.grant(player, {
					xp = math.floor(Game.xpToNext(profile.level) * 0.2) + 150,
					gold = 120 + 25 * profile.level,
				})
				S.PlayerService.notify(player, "Your team beat the boss! You get a share of the rewards.", Color3.fromRGB(255, 215, 80), "🏆")
			end
		end
		announce("🏆 VICTORY!", string.format("%s was defeated by %s!", def.name, table.concat(names, ", ")), Color3.fromRGB(255, 215, 80), 8)
	else
		for _, player in ipairs(players) do
			S.PlayerService.addXP(player, 150 + 20 * ((S.PlayerService.getProfile(player) or {}).level or 1))
		end
		announce("⌛ The boss escaped", def.name .. " retreats to the fjords... Better luck next time!", Color3.fromRGB(200, 200, 220), 6)
	end
	broadcastState()

	task.delay(victory and 10 or 3, function()
		cleanupFight()
		local toReturn = participantsList()
		fight = nil
		phase = "idle"
		currentBossId = nil
		nextSpawnAt = serverNow() + Game.BOSS_INTERVAL
		for _, player in ipairs(toReturn) do
			player:SetAttribute("InBossFight", false)
			local character = S.PlayerService.getCharacter(player)
			if character then
				S.PlayerService.teleport(player, S.PlayerService.getSpawnCFrame(player))
			elseif player.Parent and not player.Character then
				S.PlayerService.spawn(player)
			end
		end
		broadcastState()
	end)
end

local function startFight()
	local def = Enemies.Bosses[currentBossId]
	local players = {}
	for player in pairs(queue) do
		if player.Parent and S.PlayerService.getProfile(player) and S.PlayerService.getStats(player) then
			table.insert(players, player)
		end
	end
	queue = {}

	if #players == 0 then
		announce("The boss moves on", def.name .. " found no challengers and returned to the fjords.", Color3.fromRGB(200, 200, 220), 5)
		phase = "idle"
		currentBossId = nil
		nextSpawnAt = serverNow() + Game.BOSS_INTERVAL
		broadcastState()
		return
	end

	-- Scale to the group.
	local totalDps, totalHealth, maxLevel = 0, 0, 1
	for _, player in ipairs(players) do
		local stats = S.PlayerService.getStats(player)
		local profile = S.PlayerService.getProfile(player)
		totalDps += StatCalc.dps(stats)
		totalHealth += stats.maxHealth
		maxLevel = math.max(maxLevel, profile.level)
	end
	local level = maxLevel + 2
	local maxHealth = math.max(600, totalDps * Game.BOSS_TARGET_FIGHT_SECONDS)
	local avgHealth = totalHealth / #players

	fight = {
		participants = {},
		lives = {},
		out = {},
		adds = {},
		level = level,
		hit = avgHealth * Game.BOSS_HIT_FRACTION * 1.3,
		endsAt = serverNow() + Game.BOSS_FIGHT_DURATION,
		nextAttack = {},
		summoned = {},
		enraged = false,
		target = nil,
		retargetAt = 0,
	}
	for _, player in ipairs(players) do
		fight.participants[player] = true
		fight.lives[player] = Game.BOSS_LIVES
		player:SetAttribute("InBossFight", true)
	end

	local c = Zones.BossArena.center
	local bossDef = { id = def.id, name = def.name, health = 1, damage = 1, defense = 10 + level, speed = def.speed, look = def.look, elite = true, xpMult = 0 }
	fight.boss = S.EnemyService.spawn(def.id, level, c, {
		def = bossDef,
		look = def.look,
		scale = def.scale,
		displayName = def.name,
		isBoss = true,
		customAI = true,
		noRewards = true,
		arena = true,
		speed = def.speed,
		onDeath = function()
			endFight(true)
		end,
	})
	local boss = fight.boss
	boss.humanoid.MaxHealth = maxHealth
	boss.humanoid.Health = maxHealth
	boss.defense = 10 + level
	boss.radius = 2.2 * def.scale
	boss.height = 3.6 * def.scale

	phase = "fight"
	for _, player in ipairs(players) do
		local character = S.PlayerService.getCharacter(player)
		if character then
			S.PlayerService.teleport(player, BossService.getArenaSpawn(player))
		else
			S.PlayerService.spawn(player)
		end
		S.QuestService.progress(player, "bossJoin", nil, 1)
	end
	announce("⚔️ THE BOSS HAS ARRIVED", string.format("%s, %s, faces %d brave dragon%s!", def.name, def.title, #players, #players > 1 and "s" or ""), Color3.fromRGB(255, 80, 60), 5)
	broadcastState()
end

local function thinkBoss()
	if not fight or phase ~= "fight" then
		return
	end
	local boss = fight.boss
	if not boss or boss.dead then
		return
	end
	local def = Enemies.Bosses[currentBossId]
	local t = os.clock()

	-- Participants who left the game or the arena are removed.
	for player in pairs(fight.participants) do
		if not player.Parent then
			fight.participants[player] = nil
		end
	end
	if next(fight.participants) == nil then
		endFight(false)
		return
	end
	if serverNow() >= fight.endsAt then
		endFight(false)
		return
	end

	local pct = boss.humanoid.Health / boss.humanoid.MaxHealth
	for _, threshold in ipairs({ 0.66, 0.33 }) do
		if pct <= threshold and not fight.summoned[threshold] then
			fight.summoned[threshold] = true
			summonAdds()
		end
	end
	if pct <= 0.25 and not fight.enraged then
		fight.enraged = true
		boss.baseSpeed = def.speed * 1.35
		announce("😡 ENRAGED", def.name .. " is enraged!", Color3.fromRGB(255, 60, 60), 3)
	end

	-- Safety net: if the boss ever ends up outside the arena, put it back in the middle.
	local bp = boss.root.Position
	local c = Zones.BossArena.center
	if Vector3.new(bp.X - c.X, 0, bp.Z - c.Z).Magnitude > Zones.BossArena.radius + 10 or bp.Y > c.Y + Zones.BossArena.wallHeight - 5 or bp.Y < c.Y - 40 then
		boss.model:PivotTo(CFrame.new(S.EnemyService.groundAt(c, 20) + Vector3.new(0, boss.humanoid.HipHeight + boss.root.Size.Y / 2 + 1, 0)))
	end

	local speedMult = S.CombatService.speedMultiplier(boss.model)
	boss.humanoid.WalkSpeed = boss.baseSpeed * speedMult
	if speedMult == 0 then
		boss.humanoid:MoveTo(boss.root.Position)
		return
	end

	local players = aliveParticipants()
	if #players == 0 then
		boss.humanoid:MoveTo(Zones.BossArena.center)
		return
	end
	if not fight.target or t >= fight.retargetAt or not S.PlayerService.getCharacter(fight.target.player) then
		fight.retargetAt = t + 4 + math.random() * 3
		local best, bestDist = nil, math.huge
		for _, p in ipairs(players) do
			local d = (p.root.Position - boss.root.Position).Magnitude + math.random() * 25
			if d < bestDist then
				best, bestDist = p, d
			end
		end
		fight.target = best
	end
	local target = fight.target
	local offset = target.root.Position - boss.root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local cleave = def.attacks.Cleave
	local cleaveRange = cleave and cleave.range * (boss.scale / 3) or 14

	if flat > cleaveRange * 0.8 then
		boss.humanoid:MoveTo(Vector3.new(target.root.Position.X, boss.root.Position.Y, target.root.Position.Z))
	else
		boss.humanoid:MoveTo(boss.root.Position)
		local p = boss.root.Position
		boss.root.CFrame = CFrame.lookAt(p, Vector3.new(target.root.Position.X, p.Y, target.root.Position.Z))
	end

	local cdMult = fight.enraged and 0.7 or 1
	local function ready(name)
		return def.attacks[name] and t >= (fight.nextAttack[name] or (fight.startedAt or 0))
	end
	local function use(name)
		fight.nextAttack[name] = t + def.attacks[name].cooldown * cdMult
		bossAttack(name, def.attacks[name], target)
	end

	if not fight.startedAt then
		fight.startedAt = t + 3 -- short grace period after teleporting in
		return
	end
	if t < fight.startedAt then
		return
	end
	if fight.busyUntil and t < fight.busyUntil then
		return
	end

	if ready("GroundSlam") then
		local near = 0
		for _, p in ipairs(players) do
			if (p.root.Position - boss.root.Position).Magnitude < def.attacks.GroundSlam.radius then
				near += 1
			end
		end
		if near > 0 then
			use("GroundSlam")
			fight.busyUntil = t + def.attacks.GroundSlam.delay
			return
		end
	end
	if ready("RuneStrikes") then
		use("RuneStrikes")
		fight.busyUntil = t + 1
		return
	end
	if ready("AxeVolley") and (flat > cleaveRange or math.random() < 0.4) then
		use("AxeVolley")
		fight.busyUntil = t + 1
		return
	end
	if ready("Cleave") and flat <= cleaveRange + 4 and offset.Y < 20 then
		use("Cleave")
		fight.busyUntil = t + 0.8
		return
	end
	-- Flyers staying out of reach get axes thrown at them.
	if ready("AxeVolley") and offset.Y > 15 then
		use("AxeVolley")
		fight.busyUntil = t + 1
	end
end

local function startWarning()
	bossRotation = (bossRotation % #Enemies.BossOrder) + 1
	currentBossId = Enemies.BossOrder[bossRotation]
	queue = {}
	phase = "warning"
	local def = Enemies.Bosses[currentBossId]
	local seconds = math.max(0, nextSpawnAt - serverNow())
	local minutes = math.floor(seconds / 60 + 0.5)
	local when = minutes >= 1 and string.format("%d minute%s", minutes, minutes == 1 and "" or "s") or string.format("%d seconds", math.floor(seconds))
	announce("⚠️ A BOSS APPROACHES", string.format("%s is coming in %s! Join the queue to fight for epic loot.", def.name, when), def.color, 8)
	broadcastState()
end

-- Admin panel: bring the next boss in `warningSeconds` (starting the warning now, or cutting
-- short a warning that's already counting down).
function BossService.adminStart(warningSeconds: number)
	if phase == "idle" then
		nextSpawnAt = serverNow() + warningSeconds
		startWarning()
		return true, "Boss warning started."
	elseif phase == "warning" then
		nextSpawnAt = math.min(nextSpawnAt, serverNow() + warningSeconds)
		broadcastState()
		return true, "The boss will arrive sooner."
	end
	return false, "A boss fight is already happening."
end

function BossService.init(services)
	S = services
end

function BossService.start()
	nextSpawnAt = serverNow() + Game.BOSS_FIRST_SPAWN

	Remotes.func("BossQueue").OnServerInvoke = function(player, join)
		return joinQueue(player, join == true)
	end
	Remotes.func("LeaveBossFight").OnServerInvoke = leaveFight

	local horn = workspace:WaitForChild("Map"):FindFirstChild("WarHornPrompt", true)
	if horn then
		horn.Triggered:Connect(function(player)
			if phase == "warning" then
				joinQueue(player, not queue[player])
			else
				local remaining = nextSpawnAt - Game.BOSS_WARNING - serverNow()
				if phase == "fight" then
					S.PlayerService.notify(player, "A boss fight is happening right now!", Color3.fromRGB(255, 160, 90), "⚔️")
				else
					S.PlayerService.notify(player, string.format("The war horn is quiet. Next boss warning in about %d:%02d.", math.max(0, remaining) // 60, math.max(0, remaining) % 60), Color3.fromRGB(220, 220, 240), "📯")
				end
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		queue[player] = nil
		if fight then
			fight.participants[player] = nil
		end
	end)

	-- Late joiners get the current state.
	Players.PlayerAdded:Connect(function()
		task.wait(3)
		broadcastState()
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.1 then
			return
		end
		accum = 0
		local ok, err = pcall(thinkBoss)
		if not ok then
			warn("[BossService] boss AI error:", err)
		end
	end)

	local lastBroadcast = 0
	while true do
		task.wait(0.5)
		local t = serverNow()
		if phase == "idle" and t >= nextSpawnAt - Game.BOSS_WARNING then
			startWarning()
		elseif phase == "warning" and t >= nextSpawnAt then
			startFight()
		end
		if (phase == "fight" or phase == "warning") and os.clock() - lastBroadcast >= 1 then
			lastBroadcast = os.clock()
			broadcastState()
		end
	end
end

return BossService
