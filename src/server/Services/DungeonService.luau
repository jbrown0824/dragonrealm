-- Dungeons (Config/Dungeons): groups of up to 4 dragons, the queue that matches them up, ready
-- checks, and the runs themselves.
--
-- Groups: a leader invites dragons in the server (friends can hop over to your server with Roblox's
-- own Join). The leader either goes in now with whoever's in the group, or queues it to be matched
-- with other groups and solo dragons (LocalMatchmaker: one server for now; the seam where a
-- cross-server matchmaker plugs in). A match (or "Enter now" with a group) starts a ready check;
-- everyone who says yes is carried into their own copy of the dungeon (DungeonBuilder carves one
-- per group playing it, off the map).
--
-- In a run the WoW rules apply: pulling one monster pulls its pack, a dragon knocked out stays down
-- until the group is out of combat (then gets up beside a friend), and if everyone falls the group
-- wakes at the entrance while the monsters reset (bosses back to full). Monsters that nobody hurts
-- (and that hurt nobody) for Dungeons.EVADE_TIME give up and walk home, healing slowly. Bosses fight
-- with BossKit moves plus their traits (summons, enrage, phases with a rune shield, a second life).
-- Beating the boss gives everyone in the run their own loot: gear at the dungeon's item level, a
-- chance of a relic (lifesteal / regen) and of the dungeon's egg (with pity).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dungeons = require(Shared.Config.Dungeons)
local Enemies = require(Shared.Config.Enemies)
local Game = require(Shared.Config.Game)
local Items = require(Shared.Config.Items)
local Pets = require(Shared.Config.Pets)
local Tuning = require(Shared.Tuning)
local ItemUtil = require(Shared.ItemUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local BossKit = require(script.Parent.Parent.Combat.BossKit)
local DungeonBuilder = require(script.Parent.Parent.World.DungeonBuilder)
local AnimalBuilder = require(script.Parent.Parent.World.AnimalBuilder)

local DungeonService = {}
local S

local folder: Folder
local groups = {} -- [id] = { id, leader, members = { Player }, queued = dungeonId?, queuedAt }
local groupOf = {} -- [Player] = group
local invites = {} -- [Player] = { [groupId] = expiresAt }
local runs = {} -- [id] = run
local runOf = {} -- [Player] = run
local slots = {} -- [dungeonId] = { [slot] = { built, runId } }
local checks = {} -- ready checks: [id] = check
local checkOf = {} -- [Player] = check
local nextId = 0
local dirty = true

local GOLD = Color3.fromRGB(255, 215, 80)
local INFO = Color3.fromRGB(200, 230, 255)
local BAD = Color3.fromRGB(255, 140, 120)

local function now(): number
	return os.clock()
end

-- os.clock time -> server time (what clients count down to)
local function serverTime(t: number): number
	return workspace:GetServerTimeNow() + (t - now())
end

local function newId(): number
	nextId += 1
	return nextId
end

local function notify(player: Player, text: string, color: Color3?, icon: string?, open: string?)
	S.PlayerService.notify(player, text, color, icon, open)
end

local function announce(player: Player, title: string, text: string, color: Color3, duration: number?)
	Remotes.event("Announce"):FireClient(player, { title = title, text = text, color = color, duration = duration or 5 })
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Group size scaling, stretched by the admin "Small-group discount".
local function groupScale(list, n: number): number
	local base = list[math.clamp(n, 1, #list)]
	return math.max(0.1, 1 - (1 - base) * Tuning.global("groupScaling"))
end

---------------------------------------------------------------- the matchmaker (one server)

-- Queued groups by dungeon, oldest first. `poll` returns the matches ready to go: 4 dragons, or 2-3
-- once the oldest group has waited Dungeons.QUEUE_PARTIAL_AFTER.
local LocalMatchmaker = { queue = {} }

function LocalMatchmaker.enqueue(group, dungeonId: string, front: boolean?)
	local list = LocalMatchmaker.queue[dungeonId] or {}
	LocalMatchmaker.queue[dungeonId] = list
	if front then
		table.insert(list, 1, group)
	else
		table.insert(list, group)
	end
end

function LocalMatchmaker.dequeue(group)
	for _, list in pairs(LocalMatchmaker.queue) do
		local i = table.find(list, group)
		if i then
			table.remove(list, i)
		end
	end
end

function LocalMatchmaker.looking(dungeonId: string): number
	local n = 0
	for _, g in ipairs(LocalMatchmaker.queue[dungeonId] or {}) do
		n += #g.members
	end
	return n
end

function LocalMatchmaker.poll(t: number)
	local matches = {}
	for dungeonId, list in pairs(LocalMatchmaker.queue) do
		if #list > 0 then
			local picked, total = {}, 0
			for _, g in ipairs(list) do
				if total + #g.members <= Dungeons.MAX_GROUP then
					table.insert(picked, g)
					total += #g.members
				end
				if total == Dungeons.MAX_GROUP then
					break
				end
			end
			if total == Dungeons.MAX_GROUP or (total >= 2 and t - list[1].queuedAt >= Dungeons.QUEUE_PARTIAL_AFTER) then
				for _, g in ipairs(picked) do
					table.remove(list, table.find(list, g))
				end
				table.insert(matches, { dungeonId = dungeonId, groups = picked })
			end
		end
	end
	return matches
end

DungeonService.matchmaker = LocalMatchmaker

---------------------------------------------------------------- queries

function DungeonService.inRun(player: Player): boolean
	return runOf[player] ~= nil
end

function DungeonService.runOf(player: Player)
	return runOf[player]
end

function DungeonService.groupOf(player: Player)
	return groupOf[player]
end

-- Where a dragon in a run (re)spawns: the entrance of its dungeon.
function DungeonService.spawnCFrame(player: Player): CFrame?
	local run = runOf[player]
	if not run then
		return nil
	end
	return run.built.spawn * CFrame.new(math.random(-10, 10), 0, math.random(-4, 4))
end

-- Everyone in the run a monster belongs to (they share every kill).
function DungeonService.rewardees(e)
	local run = e.run and runs[e.run]
	local list = {}
	if run then
		for player in pairs(run.members) do
			if player.Parent then
				table.insert(list, player)
			end
		end
	end
	return list
end

local function aliveMembers(run)
	local list = {}
	for player, m in pairs(run.members) do
		local character, _, root = S.PlayerService.getCharacter(player)
		if character and not m.dead then
			table.insert(list, { player = player, root = root, character = character })
		end
	end
	return list
end

local function memberCount(run): number
	local n = 0
	for _ in pairs(run.members) do
		n += 1
	end
	return n
end

---------------------------------------------------------------- state for the clients

local function stateFor(player: Player)
	local data = { looking = {} }
	for _, id in ipairs(Dungeons.Order) do
		data.looking[id] = LocalMatchmaker.looking(id)
	end
	local group = groupOf[player]
	if group then
		local members = {}
		for _, p in ipairs(group.members) do
			local profile = S.PlayerService.getProfile(p)
			table.insert(members, { userId = p.UserId, name = p.DisplayName, level = profile and profile.level or 1, class = profile and profile.class })
		end
		data.group = { id = group.id, leader = group.leader.UserId, members = members }
		if group.queued then
			data.queue = { dungeonId = group.queued, since = serverTime(group.queuedAt), size = #group.members, looking = LocalMatchmaker.looking(group.queued) }
		end
	end
	local check = checkOf[player]
	if check then
		local accepted = 0
		for _ in pairs(check.accepted) do
			accepted += 1
		end
		data.check = { dungeonId = check.dungeonId, endsAt = serverTime(check.expiresAt), accepted = accepted, total = #check.members, mine = check.accepted[player] == true }
	end
	local run = runOf[player]
	if run then
		local cleared = 0
		for _, pack in ipairs(run.packs) do
			if pack.cleared then
				cleared += 1
			end
		end
		local boss = run.bosses.boss
		local m = run.members[player]
		data.run = {
			dungeonId = run.def.id,
			packs = #run.packs,
			cleared = cleared,
			inCombat = run.inCombat,
			boss = boss and boss.def.name,
			bossHp = boss and not boss.e.dead and boss.engaged and boss.e.humanoid.Health / boss.e.humanoid.MaxHealth or nil,
			done = run.cleared,
			closesAt = run.closeAt and serverTime(run.closeAt),
			dead = m and m.dead or false,
			wipe = run.wipeAt ~= nil,
			alive = #aliveMembers(run),
			size = memberCount(run),
		}
	end
	local mine = {}
	for groupId, expires in pairs(invites[player] or {}) do
		local g = groups[groupId]
		if g and expires > now() then
			table.insert(mine, { groupId = groupId, from = g.leader.DisplayName, endsAt = serverTime(expires) })
		end
	end
	data.invites = mine
	return data
end

local function push(player: Player)
	if player.Parent then
		Remotes.event("DungeonState"):FireClient(player, stateFor(player))
	end
end

local function pushAll()
	dirty = false
	for _, player in ipairs(Players:GetPlayers()) do
		push(player)
	end
end

local function markDirty()
	dirty = true
end

---------------------------------------------------------------- groups

local function ensureGroup(player: Player)
	local group = groupOf[player]
	if not group then
		group = { id = newId(), leader = player, members = { player } }
		groups[group.id] = group
		groupOf[player] = group
	end
	return group
end

local function unqueue(group, why: string?)
	if group.queued then
		LocalMatchmaker.dequeue(group)
		group.queued = nil
		group.queuedAt = nil
		if why then
			for _, p in ipairs(group.members) do
				notify(p, why, INFO, "🏰")
			end
		end
	end
	markDirty()
end

local declineCheck -- (forward: a ready check someone said no to)

local function removeFromGroup(player: Player)
	local group = groupOf[player]
	if not group then
		return
	end
	if checkOf[player] then
		declineCheck(checkOf[player], player)
	end
	unqueue(group, #group.members > 1 and (player.DisplayName .. " left the group, so it left the queue.") or nil)
	groupOf[player] = nil
	table.remove(group.members, table.find(group.members, player))
	if #group.members == 0 then
		groups[group.id] = nil
	elseif group.leader == player then
		group.leader = group.members[1]
		notify(group.leader, "You're the group leader now.", INFO, "👑")
	end
	markDirty()
end

-- Can this dragon go into this dungeon right now? (level, not already busy)
local function canEnter(player: Player, def, ignoreLevel: boolean?): (boolean, string?)
	local profile = S.PlayerService.getProfile(player)
	if not profile or not profile.class then
		return false, player.DisplayName .. " hasn't chosen a dragon yet."
	end
	if not ignoreLevel and profile.level < def.minLevel then
		return false, string.format("%s needs to be level %d for %s.", player.DisplayName, def.minLevel, def.name)
	end
	if runOf[player] then
		return false, player.DisplayName .. " is already in a dungeon."
	end
	if S.BossService.isInFight(player) then
		return false, player.DisplayName .. " is fighting a world boss."
	end
	return true
end

---------------------------------------------------------------- slots (copies of each dungeon)

local function slotFor(def)
	local list = slots[def.id] or {}
	slots[def.id] = list
	for index, slot in ipairs(list) do
		if not slot.runId then
			return index, slot
		end
	end
	local slot = { built = DungeonBuilder.interior(def, Dungeons.origin(def.id, #list + 1), folder) }
	if slot.built.chained then
		slot.built.chainedHome = slot.built.chained:GetPivot()
	end
	table.insert(list, slot)
	return #list, slot
end

-- A reused copy gets its chained dragon (and chains) back.
local function resetSlot(built)
	if built.chained then
		built.chained.Parent = built.model
		built.chained:PivotTo(built.chainedHome)
		if built.chains then
			built.chains.Parent = built.model
		end
	end
end

---------------------------------------------------------------- runs: monsters

local onMobDeath, onBossDeath, onBossLethal -- (forward)

local function floorAt(pos: Vector3): Vector3
	return DungeonBuilder.floorAt(pos)
end

local function spawnMob(run, typeId: string, pos: Vector3, pack)
	local mdef = Enemies.Dungeon[typeId]
	local id = run.def.id
	local ground = floorAt(pos)
	local opts = {
		def = mdef,
		ground = ground,
		run = run.id,
		pack = pack and pack.index,
		healthMult = run.hpMult * Tuning.dungeon(id, "mobHp"),
		damageMult = run.dmgMult * Tuning.dungeon(id, "mobDmg"),
		leash = Dungeons.MOB_LEASH,
		aggroRange = mdef.aggroRange,
	}
	if mdef.builder == "animal" then
		local look = mdef.look
		opts.builder = AnimalBuilder.build
		opts.tag = "Animal"
		opts.tagOffset = (look.bodyH + 1.4) * mdef.scale
		opts.radius = math.max(look.bodyW, look.bodyL * 0.5) * 0.7 * mdef.scale
		opts.height = (look.legLen + look.bodyH) * mdef.scale
	end
	opts.onDeath = function(e)
		onMobDeath(run, e)
	end
	local level = run.def.level + math.random(-1, 1)
	local e = S.EnemyService.spawn(typeId, level, pos, opts)
	if e then
		e.home = ground
		table.insert(run.mobs, e)
		if pack then
			table.insert(pack.mobs, e)
		end
	end
	return e
end

local function spawnPacks(run)
	for i, pack in ipairs(run.def.packs) do
		local p = { index = i, mobs = {}, cleared = false }
		run.packs[i] = p
		for _, entry in ipairs(Dungeons.packMobs(pack)) do
			spawnMob(run, entry[1], run.built.origin + entry[2], p)
		end
	end
end

-- Monsters that heard the fight: everyone in the pack goes for the same dragon.
function DungeonService.pullPack(e, player: Player)
	local run = e.run and runs[e.run]
	if not run or not e.pack then
		return
	end
	local pack = run.packs[e.pack]
	for _, other in ipairs(pack and pack.mobs or {}) do
		if other ~= e and not other.dead and not other.target and not other.returning and S.EnemyService.targetRoot(other, player) then
			other.target = player
			other.lastCombat = now()
		end
	end
end

local function participants(run, boss)
	local list = {}
	local room = boss.room
	for _, p in ipairs(aliveMembers(run)) do
		local d = p.root.Position - room.center
		if flat(d).Magnitude <= room.radius + 24 and math.abs(d.Y) < 70 then
			table.insert(list, p)
		end
	end
	return list
end

local function spawnBoss(run, kind: string)
	local def = run.def
	local spec = kind == "mini" and def.miniBoss or def.boss
	local bdef = Dungeons.Bosses[spec.id]
	local room = run.built.rooms[spec.room]
	local pos = run.built.origin + spec.at
	local ground = floorAt(pos)
	local level = def.level + (bdef.mini and 1 or 2)
	local edef = { id = bdef.id, name = bdef.name, health = 1, damage = 1, defense = 10 + level, speed = bdef.speed, look = bdef.look, elite = true, xpMult = 0 }
	local boss = { kind = kind, def = bdef, room = room, home = ground, engaged = false, phase = 0, summoned = {}, adds = {} }
	local e = S.EnemyService.spawn(bdef.id, level, pos, {
		def = edef,
		ground = ground,
		look = bdef.look,
		scale = bdef.scale,
		displayName = bdef.name,
		isBoss = not bdef.mini,
		miniBoss = bdef.mini == true,
		customAI = true,
		noRewards = true,
		run = run.id,
		speed = bdef.speed,
		onDeath = function(_, killer)
			onBossDeath(run, boss, killer)
		end,
	})
	boss.e = e
	local maxHp = math.floor(bdef.health * run.hpMult * Tuning.dungeon(def.id, "bossHp"))
	e.humanoid.MaxHealth = maxHp
	e.humanoid.Health = maxHp
	e.defense = 10 + level
	e.radius = 2.2 * bdef.scale
	e.height = 3.6 * bdef.scale
	e.lastCombat = now() - 60
	e.onLethal = function()
		return onBossLethal(run, boss)
	end
	boss.brain = BossKit.new(S, {
		boss = e,
		level = level,
		hit = bdef.hit * run.dmgMult * Tuning.dungeon(def.id, "bossDmg"),
		color = bdef.color,
		moves = bdef.moves,
		participants = function()
			return participants(run, boss)
		end,
		over = function()
			return run.ended or not boss.engaged or boss.down == true
		end,
		center = room.center,
		radius = room.radius,
		ground = floorAt,
		laneFrom = def.chained and floorAt(run.built.origin + def.chained.breath) or nil,
		speed = bdef.speed,
		grace = 1,
	})
	boss.brain.home = ground
	run.bosses[kind] = boss
	return boss
end

---------------------------------------------------------------- runs: loot

local function relicOrEgg(player: Player, run, lines)
	local def = run.def
	local profile = S.PlayerService.getProfile(player)
	local stats = S.PlayerService.getStats(player)
	local luck = (1 + (stats and stats.lootPct or 0) / 100) * Tuning.dungeon(def.id, "loot")
	if math.random() < Dungeons.UNIQUE_CHANCE * luck then
		local relicId = def.loot.relics[math.random(1, #def.loot.relics)]
		local item = S.LootService.rollUnique(relicId, def.ilvl)
		S.PlayerService.addItem(player, item)
		table.insert(lines, "✨ " .. Items.Uniques[relicId].name)
	end
	local pity = profile.dungeons.pity[def.id] or 0
	if math.random() < (Dungeons.EGG_CHANCE + pity) * luck then
		profile.dungeons.pity[def.id] = 0
		S.PetService.addEgg(player, def.loot.egg, 1)
		local egg = Pets.Eggs[def.loot.egg]
		table.insert(lines, egg.icon .. " " .. egg.name .. "!")
		announce(player, egg.icon .. " " .. string.upper(egg.name) .. "!", "A pet you can't find anywhere else. Hatch it in 🐲 Pets.", egg.color, 5)
	else
		profile.dungeons.pity[def.id] = pity + Dungeons.EGG_PITY
	end
end

local function xpShare(profile, share: number): number
	if profile.level >= Game.LEVEL_CAP then
		return Game.paragonXp(profile.paragon or 0) * share
	end
	return Game.xpToNext(profile.level) * share
end

local function lootMini(run, boss)
	local def = run.def
	for player in pairs(run.members) do
		local profile = S.PlayerService.getProfile(player)
		if player.Parent and profile then
			local item = S.LootService.rollGear(def.ilvl, 0, Dungeons.MINI_MIN_RARITY)
			S.PlayerService.addItem(player, item)
			S.LootService.grant(player, { xp = math.floor(xpShare(profile, Dungeons.MINI_XP)), gold = def.loot.miniGold })
			notify(player, string.format("%s is down! Loot: %s, %s gold.", boss.def.name, ItemUtil.displayName(item), Util.formatNumber(def.loot.miniGold)), GOLD, "💀")
		end
	end
end

local function freeDragon(run)
	local built = run.built
	if not built.chained then
		return
	end
	local model = built.chained
	S.CombatService.broadcastVFX({ kind = "shatter", pos = model:GetPivot().Position })
	if built.chains then
		built.chains.Parent = nil
	end
	local start = model:GetPivot()
	task.spawn(function()
		task.wait(1)
		local t0 = now()
		while now() - t0 < 3 do
			if run.ended or not model.Parent then
				return
			end
			local i = (now() - t0) * 20 -- up and away, faster and faster
			model:PivotTo(start * CFrame.new(0, i * i * 0.04, -i * 0.9) * CFrame.Angles(math.rad(-math.min(i, 25)), 0, 0))
			task.wait(0.05)
		end
		model.Parent = nil
	end)
end

local function clearRun(run)
	local def = run.def
	run.cleared = true
	run.closeAt = now() + Dungeons.CLEARED_STAY
	freeDragon(run)
	for player in pairs(run.members) do
		local profile = S.PlayerService.getProfile(player)
		if player.Parent and profile then
			local lines = {}
			local rarity = Util.weightedPick(Dungeons.BOSS_RARITY) or "Epic"
			local item = S.LootService.rollGear(def.ilvl, 0, nil, rarity)
			S.PlayerService.addItem(player, item)
			table.insert(lines, ItemUtil.displayName(item))
			relicOrEgg(player, run, lines)
			local gold = def.loot.gold
			S.LootService.grant(player, { xp = math.floor(xpShare(profile, Dungeons.BOSS_XP)), gold = gold })
			table.insert(lines, Util.formatNumber(gold) .. " gold")
			local first = (profile.dungeons.clears[def.id] or 0) == 0
			profile.dungeons.clears[def.id] = (profile.dungeons.clears[def.id] or 0) + 1
			profile.dungeonClears = (profile.dungeonClears or 0) + 1
			if first and def.title and not profile.titles[def.title] then
				S.AchievementService.grant(player, { title = def.title })
				table.insert(lines, "🏷️ title \"" .. def.title .. "\"")
			end
			S.QuestService.progress(player, "dungeonClear", def.id, 1)
			S.AchievementService.check(player)
			announce(player, "🏆 DUNGEON CLEARED!", def.name .. "  •  " .. def.victory, GOLD, 6)
			notify(player, "Your loot: " .. table.concat(lines, ", "), GOLD, "🏆")
			S.PlayerService.markDirty(player)
		end
	end
	markDirty()
end

local function openChest(player: Player, prompt: Instance)
	local run = runOf[player]
	if not run or not run.built.chest or not prompt:IsDescendantOf(run.built.model) then
		return
	end
	if run.chestOpened[player] then
		notify(player, "You already took your share of this hoard.", INFO, "💰")
		return
	end
	run.chestOpened[player] = true
	local def = run.def
	local gold = math.floor(def.loot.gold * 0.4)
	local parts = { Util.formatNumber(gold) .. " gold" }
	S.LootService.grant(player, { gold = gold, seeds = { [S.LootService.rollSeed(1)] = 1 } })
	table.insert(parts, "a seed")
	if math.random() < Dungeons.CHEST_GEAR_CHANCE then
		local item = S.LootService.rollGear(def.ilvl, 0, "Rare")
		S.PlayerService.addItem(player, item)
		table.insert(parts, ItemUtil.displayName(item))
	end
	S.CombatService.broadcastVFX({ kind = "chest", pos = run.built.chest.Position })
	notify(player, "Hidden hoard: " .. table.concat(parts, ", ") .. "!", GOLD, "💰")
end

---------------------------------------------------------------- runs: deaths and bosses

onMobDeath = function(run, e)
	if run.ended then
		return
	end
	for player in pairs(run.members) do
		if player.Parent then
			S.QuestService.progress(player, "dungeonKill", run.def.id, 1)
		end
	end
	if e.pack then
		local pack = run.packs[e.pack]
		if pack and not pack.cleared then
			local left = 0
			for _, m in ipairs(pack.mobs) do
				if not m.dead then
					left += 1
				end
			end
			pack.cleared = left == 0
		end
	end
	markDirty()
end

-- Haldor's second life: at 0 health he collapses instead of dying, then rises again.
onBossLethal = function(run, boss)
	local life = boss.def.secondLife
	if not life or boss.lifeUsed or run.ended then
		return false
	end
	boss.lifeUsed = true
	boss.down = true
	local e = boss.e
	e.humanoid.Health = 1
	e.immune = true
	BossKit.reset(boss.brain)
	local root = e.root
	root.Anchored = true
	local stand = e.model:GetPivot()
	e.model:PivotTo(stand * CFrame.new(0, -e.humanoid.HipHeight * 0.6, 0) * CFrame.Angles(math.rad(-35), 0, 0))
	e.model:SetAttribute("Collapsed", true)
	for player in pairs(run.members) do
		notify(player, boss.def.name .. " falls... but the barrow's magic stirs!", boss.def.color, "💀")
	end
	task.delay(life.delay, function()
		if run.ended or e.dead or not e.model.Parent then
			return
		end
		e.model:PivotTo(stand)
		root.Anchored = false
		e.model:SetAttribute("Collapsed", nil)
		e.humanoid.Health = e.humanoid.MaxHealth * life.health
		e.immune = false
		boss.down = false
		boss.brain.moves = life.moves
		boss.brain.speed = boss.def.speed * (life.speedMult or 1)
		S.EnemyService.rename(e, life.name)
		S.CombatService.broadcastVFX({ kind = "rise", pos = root.Position, color = boss.def.color })
		for player in pairs(run.members) do
			announce(player, "💀 " .. string.upper(life.name) .. "!", "He's back, and angrier. Watch for his leap!", boss.def.color, 4)
		end
		markDirty()
	end)
	return true
end

onBossDeath = function(run, boss)
	if run.ended then
		return
	end
	for _, add in ipairs(boss.adds) do
		if not add.dead then
			S.EnemyService.kill(add)
		end
	end
	if boss.kind == "mini" then
		lootMini(run, boss)
	else
		clearRun(run)
	end
	markDirty()
end

local function setShield(boss, on: boolean)
	local e = boss.e
	e.immune = on
	boss.shielded = on
	e.model:SetAttribute("RuneShield", on or nil)
	local existing = e.model:FindFirstChild("RuneShield")
	if on and not existing then
		local bubble = Instance.new("Part")
		bubble.Name = "RuneShield"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.new(1, 1, 1) * (e.height * 1.6 + 6)
		bubble.Color = boss.def.color
		bubble.Material = Enum.Material.ForceField
		bubble.Transparency = 0.3
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.Massless = true
		bubble.CFrame = e.root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = e.root
		weld.Part1 = bubble
		weld.Parent = bubble
		bubble.Parent = e.model
	elseif not on and existing then
		existing:Destroy()
	end
end

local function summon(run, boss, add: string, count: number)
	local e = boss.e
	local list = {}
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local pos = BossKit.inRoom(boss.brain, e.root.Position + Vector3.new(math.cos(a) * 16, 0, math.sin(a) * 16), 8)
		local m = spawnMob(run, add, pos, nil)
		if m then
			m.summoned = true
			m.aggroRange = 200
			table.insert(boss.adds, m)
			table.insert(list, m)
			local best, bestDist = nil, math.huge
			for _, p in ipairs(aliveMembers(run)) do
				local d = (p.root.Position - m.root.Position).Magnitude
				if d < bestDist then
					best, bestDist = p.player, d
				end
			end
			m.target = best
			m.lastCombat = now()
		end
	end
	return list
end

local function bossTraits(run, boss)
	local e, def, brain = boss.e, boss.def, boss.brain
	local pct = e.humanoid.Health / math.max(1, e.humanoid.MaxHealth)
	for i, s in ipairs(def.summons or {}) do
		if pct <= s.at and not boss.summoned[i] and not boss.lifeUsed then
			boss.summoned[i] = true
			summon(run, boss, s.add, s.count)
			for player in pairs(run.members) do
				notify(player, def.name .. " calls for help!", BAD, "⚠️")
			end
		end
	end
	if def.enrage and pct <= def.enrage.at and not boss.enraged then
		boss.enraged = true
		brain.cdMult, brain.dmgMult = 0.7, 1.25
		brain.speed = def.speed * 1.35
		for player in pairs(run.members) do
			notify(player, def.name .. " is enraged!", BAD, "😡")
		end
	end
	for i, ph in ipairs(def.phases or {}) do
		if pct <= ph.at and boss.phase < i then
			boss.phase = i
			brain.moves = ph.moves
			if ph.shield then
				boss.shieldAdds = summon(run, boss, ph.shield.add, ph.shield.count)
				setShield(boss, true)
				for player in pairs(run.members) do
					announce(player, "🛡️ RUNE SHIELD!", string.format("%s can't be hurt while her %d guards stand. Beat them!", def.name, ph.shield.count), def.color, 4)
				end
			else
				for player in pairs(run.members) do
					notify(player, def.name .. " fights harder!", BAD, "⚠️")
				end
			end
		end
	end
	if boss.shielded then
		local standing = 0
		for _, m in ipairs(boss.shieldAdds or {}) do
			if not m.dead then
				standing += 1
			end
		end
		if standing == 0 then
			setShield(boss, false)
			for player in pairs(run.members) do
				notify(player, "The rune shield shatters!", GOLD, "💥")
			end
			S.CombatService.broadcastVFX({ kind = "shatter", pos = e.root.Position })
		end
	end
	-- never out of its room
	local d = e.root.Position - boss.room.center
	if not e.root.Anchored and (flat(d).Magnitude > boss.room.radius + 10 or d.Y < -20) then
		e.model:PivotTo(CFrame.new(boss.home + Vector3.new(0, e.humanoid.HipHeight + e.root.Size.Y / 2 + 1, 0)))
	end
end

-- Put a boss back as it was (a wipe): full health, first phase, no shield, dormant at home.
local function resetBoss(boss)
	local e = boss.e
	if e.dead then
		return
	end
	BossKit.reset(boss.brain)
	for _, add in ipairs(boss.adds) do
		if not add.dead then
			S.EnemyService.despawn(add)
		end
	end
	boss.adds = {}
	boss.summoned = {}
	boss.phase = 0
	boss.enraged = false
	boss.lifeUsed = false
	boss.down = false
	boss.engaged = false
	setShield(boss, false)
	e.immune = false
	e.model:SetAttribute("Collapsed", nil)
	e.root.Anchored = false
	boss.brain.moves = boss.def.moves
	boss.brain.cdMult, boss.brain.dmgMult = 1, 1
	boss.brain.speed = boss.def.speed
	S.EnemyService.rename(e, boss.def.name)
	e.humanoid.Health = e.humanoid.MaxHealth
	e.model:PivotTo(CFrame.new(boss.home + Vector3.new(0, e.humanoid.HipHeight + e.root.Size.Y / 2 + 1, 0)))
end

---------------------------------------------------------------- runs: starting, leaving, ending

local function startRun(dungeonId: string, members: { Player })
	local def = Dungeons.get(dungeonId)
	local slotIndex, slot = slotFor(def)
	resetSlot(slot.built)
	local n = #members
	local run = {
		id = newId(),
		def = def,
		slot = slotIndex,
		built = slot.built,
		members = {},
		mobs = {},
		packs = {},
		bosses = {},
		chestOpened = {},
		startedAt = now(),
		calmSince = now(),
		inCombat = false,
		hpMult = groupScale(Dungeons.GROUP_HEALTH, n),
		dmgMult = groupScale(Dungeons.GROUP_DAMAGE, n),
	}
	slot.runId = run.id
	runs[run.id] = run
	spawnPacks(run)
	spawnBoss(run, "mini")
	spawnBoss(run, "boss")
	for _, player in ipairs(members) do
		local group = groupOf[player]
		if group then
			unqueue(group)
		end
		local _, _, root = S.PlayerService.getCharacter(player)
		local returnCF = root and root.CFrame or S.PlayerService.getSpawnCFrame(player)
		run.members[player] = { dead = false, returnCF = returnCF }
		runOf[player] = run
		player:SetAttribute("InDungeon", def.id)
		player:SetAttribute("DungeonRun", run.id)
		S.EnemyService.dropAggro(player)
		if root then
			S.PlayerService.teleport(player, DungeonService.spawnCFrame(player))
		else
			S.PlayerService.spawn(player, DungeonService.spawnCFrame(player))
		end
		-- (the zone title shows the dungeon's name, so the goal goes in a toast rather than a banner on top of it)
		notify(player, string.format("Beat %s at the bottom! Hit one monster and its whole pack comes.", Dungeons.Bosses[def.boss.id].name), def.color, "⚔️")
	end
	markDirty()
	return run
end

local function endRun(run)
	if run.ended then
		return
	end
	run.ended = true
	for _, e in ipairs(run.mobs) do
		if not e.dead and e.model.Parent then
			S.EnemyService.despawn(e)
		end
	end
	for _, boss in pairs(run.bosses) do
		if boss.e and not boss.e.dead and boss.e.model.Parent then
			S.EnemyService.despawn(boss.e)
		end
	end
	local slot = slots[run.def.id] and slots[run.def.id][run.slot]
	if slot and slot.runId == run.id then
		slot.runId = nil
	end
	runs[run.id] = nil
	markDirty()
end

-- Take a dragon out of its run and back to where it came in from (or nowhere: it left the game).
local function leaveRun(player: Player, why: string?)
	local run = runOf[player]
	if not run then
		return false, "You're not in a dungeon."
	end
	local m = run.members[player]
	run.members[player] = nil
	runOf[player] = nil
	player:SetAttribute("InDungeon", nil)
	player:SetAttribute("DungeonRun", nil)
	S.EnemyService.dropAggro(player)
	if player.Parent then
		local cf = m and m.returnCF or S.PlayerService.getSpawnCFrame(player)
		if S.PlayerService.getCharacter(player) then
			S.PlayerService.teleport(player, cf)
		else
			S.PlayerService.spawn(player, cf)
		end
		if why then
			notify(player, why, INFO, "🏰")
		end
	end
	if next(run.members) == nil then
		endRun(run)
	end
	markDirty()
	return true
end
DungeonService.leaveRun = leaveRun

---------------------------------------------------------------- ready checks

local function launch(check)
	checks[check.id] = nil
	local def = Dungeons.get(check.dungeonId)
	local ready = {}
	for _, p in ipairs(check.members) do
		checkOf[p] = nil
		if p.Parent and canEnter(p, def, check.ignoreLevel) then
			table.insert(ready, p)
		end
	end
	if #ready > 0 then
		startRun(check.dungeonId, ready)
	end
	markDirty()
end

local function startCheck(dungeonId: string, groupList, accepted: Player?, ignoreLevel: boolean?)
	local check = { id = newId(), dungeonId = dungeonId, groups = groupList, members = {}, accepted = {}, expiresAt = now() + Dungeons.READY_TIME, ignoreLevel = ignoreLevel }
	for _, g in ipairs(groupList) do
		for _, p in ipairs(g.members) do
			table.insert(check.members, p)
			checkOf[p] = check
		end
	end
	if accepted then
		check.accepted[accepted] = true
	end
	checks[check.id] = check
	local def = Dungeons.get(dungeonId)
	local all = true
	for _, p in ipairs(check.members) do
		if not check.accepted[p] then
			all = false
			notify(p, string.format("Your group for %s is ready! Press Enter to go in.", def.name), def.color, "🏰")
		end
	end
	if all then
		launch(check)
	else
		markDirty()
	end
	return check
end

-- Someone said no (or didn't answer in time): their group leaves the queue, and every other group
-- goes back to the front of it.
declineCheck = function(check, decliner: Player?)
	if not checks[check.id] then
		return
	end
	checks[check.id] = nil
	local def = Dungeons.get(check.dungeonId)
	for _, p in ipairs(check.members) do
		checkOf[p] = nil
	end
	for _, g in ipairs(check.groups) do
		local out = false
		for _, p in ipairs(g.members) do
			if p == decliner or (decliner == nil and not check.accepted[p]) then
				out = true
			end
		end
		if out or not g.queued then
			local who = decliner and decliner.DisplayName or "Someone"
			for _, p in ipairs(g.members) do
				notify(p, g.queued and string.format("%s didn't go in, so your group left the queue for %s.", who, def.name)
					or string.format("%s isn't ready. Try again when everyone is.", who), INFO, "🏰")
			end
			g.queued = nil
			g.queuedAt = nil
		else
			LocalMatchmaker.enqueue(g, check.dungeonId, true)
			for _, p in ipairs(g.members) do
				notify(p, "Someone wasn't ready. You're back at the front of the queue.", INFO, "🏰")
			end
		end
	end
	markDirty()
end

---------------------------------------------------------------- remote actions

local ACTIONS = {}

ACTIONS.state = function(player)
	push(player)
	return true
end

ACTIONS.seen = function(player)
	local profile = S.PlayerService.getProfile(player)
	if profile then
		local seen = 0
		for _, id in ipairs(Dungeons.unlocked(profile.level)) do
			seen = math.max(seen, Dungeons.List[id].minLevel)
		end
		profile.dungeons.seen = seen
		S.PlayerService.markDirty(player)
	end
	return true
end

ACTIONS.invite = function(player, args)
	local target = Players:GetPlayerByUserId(tonumber(args.userId) or 0)
	if not target or target == player then
		return false, "That dragon isn't here."
	end
	local profile = S.PlayerService.getProfile(target)
	if not profile or profile.level < Dungeons.UNLOCK_LEVEL then
		return false, string.format("%s needs to be level %d for dungeons.", target.DisplayName, Dungeons.UNLOCK_LEVEL)
	end
	if runOf[player] then
		return false, "Finish your dungeon first."
	end
	local group = ensureGroup(player)
	if group.leader ~= player then
		return false, "Only the group leader can invite."
	end
	if group.queued or checkOf[player] then
		return false, "Leave the queue first."
	end
	if groupOf[target] == group then
		return false, target.DisplayName .. " is already in your group."
	end
	if #group.members >= Dungeons.MAX_GROUP then
		return false, "Your group is full."
	end
	invites[target] = invites[target] or {}
	invites[target][group.id] = now() + Dungeons.INVITE_TIME
	Remotes.event("DungeonInvite"):FireClient(target, { groupId = group.id, from = player.DisplayName, endsAt = serverTime(now() + Dungeons.INVITE_TIME) })
	markDirty()
	return true, "Invite sent to " .. target.DisplayName .. "."
end

ACTIONS.accept = function(player, args)
	local groupId = tonumber(args.groupId)
	local group = groupId and groups[groupId]
	local mine = invites[player]
	if not group or not mine or not mine[groupId] or mine[groupId] < now() then
		return false, "That invite has run out."
	end
	mine[groupId] = nil
	if runOf[player] then
		return false, "Finish your dungeon first."
	end
	if #group.members >= Dungeons.MAX_GROUP then
		return false, "That group is full now."
	end
	if group.queued or checkOf[group.leader] then
		return false, "That group is in the queue right now. Ask them to invite you again."
	end
	if groupOf[player] then
		removeFromGroup(player)
	end
	table.insert(group.members, player)
	groupOf[player] = group
	for _, p in ipairs(group.members) do
		if p ~= player then
			notify(p, player.DisplayName .. " joined your group!", INFO, "🤝")
		end
	end
	markDirty()
	return true, "You joined " .. group.leader.DisplayName .. "'s group."
end

ACTIONS.decline = function(player, args)
	local groupId = tonumber(args.groupId)
	local group = groupId and groups[groupId]
	if invites[player] and groupId then
		invites[player][groupId] = nil
	end
	if group and group.leader.Parent then
		notify(group.leader, player.DisplayName .. " said no thanks.", INFO, "🤝")
	end
	markDirty()
	return true
end

ACTIONS.leaveGroup = function(player)
	if not groupOf[player] then
		return false, "You're not in a group."
	end
	removeFromGroup(player)
	return true, "You left the group."
end

ACTIONS.kick = function(player, args)
	local group = groupOf[player]
	local target = Players:GetPlayerByUserId(tonumber(args.userId) or 0)
	if not group or group.leader ~= player then
		return false, "Only the group leader can do that."
	end
	if not target or groupOf[target] ~= group or target == player then
		return false, "They're not in your group."
	end
	removeFromGroup(target)
	notify(target, "You were removed from the group.", INFO, "🤝")
	return true, target.DisplayName .. " left the group."
end

local function checkMembers(group, def, ignoreLevel: boolean?): (boolean, string?)
	for _, p in ipairs(group.members) do
		local ok, why = canEnter(p, def, ignoreLevel)
		if not ok then
			return false, why
		end
	end
	return true
end

ACTIONS.queue = function(player, args)
	local def = Dungeons.get(args.dungeonId)
	if not def then
		return false, "Unknown dungeon."
	end
	local group = ensureGroup(player)
	if group.leader ~= player then
		return false, "Only the group leader can queue."
	end
	if group.queued then
		return false, "You're already in the queue."
	end
	if checkOf[player] then
		return false, "Your group is already getting ready."
	end
	local ok, why = checkMembers(group, def)
	if not ok then
		return false, why
	end
	if #group.members >= Dungeons.MAX_GROUP then
		return false, "Your group is already full: press Enter now!"
	end
	group.queued = def.id
	group.queuedAt = now()
	LocalMatchmaker.enqueue(group, def.id)
	for _, p in ipairs(group.members) do
		notify(p, string.format("Looking for dragons for %s...", def.name), def.color, "🏰")
	end
	markDirty()
	return true
end

ACTIONS.unqueue = function(player)
	if checkOf[player] then
		declineCheck(checkOf[player], player)
		return true, "You left the queue."
	end
	local group = groupOf[player]
	if not group or not group.queued then
		return false, "You're not in the queue."
	end
	unqueue(group, #group.members > 1 and (player.DisplayName .. " took the group out of the queue.") or nil)
	return true, "You left the queue."
end

ACTIONS.enter = function(player, args)
	local def = Dungeons.get(args.dungeonId)
	if not def then
		return false, "Unknown dungeon."
	end
	local group = ensureGroup(player)
	if group.leader ~= player then
		return false, "Only the group leader can take the group in."
	end
	if checkOf[player] then
		return false, "Your group is already getting ready."
	end
	local ok, why = checkMembers(group, def)
	if not ok then
		return false, why
	end
	unqueue(group)
	startCheck(def.id, { group }, player)
	return true
end

ACTIONS.ready = function(player, args)
	local check = checkOf[player]
	if not check then
		return false, "There's nothing to get ready for."
	end
	if args.yes then
		check.accepted[player] = true
		local all = true
		for _, p in ipairs(check.members) do
			if not check.accepted[p] then
				all = false
			end
		end
		if all then
			launch(check)
		end
		markDirty()
		return true
	end
	declineCheck(check, player)
	return true
end

ACTIONS.leaveRun = function(player)
	return leaveRun(player, "You left the dungeon.")
end

local function onAction(player: Player, action, args)
	local fn = type(action) == "string" and ACTIONS[action]
	if not fn then
		return false, "Unknown action."
	end
	return fn(player, type(args) == "table" and args or {})
end

-- Admin panel: straight into a dungeon on your own, whatever your level.
function DungeonService.adminEnter(player: Player, dungeonId: string)
	local def = Dungeons.get(dungeonId)
	if not def then
		return false, "Unknown dungeon."
	end
	if runOf[player] then
		leaveRun(player)
	end
	if groupOf[player] then
		removeFromGroup(player)
	end
	if S.BossService.isInFight(player) then
		return false, "Finish the boss fight first."
	end
	startRun(dungeonId, { player })
	return true, "Into " .. def.name .. "!"
end

-- Called by PlayerService when a dragon levels up: announce newly unlocked dungeons.
function DungeonService.onLevel(player: Player, old: number, new: number)
	for index, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		if old < def.minLevel and new >= def.minLevel then
			task.delay(4.3, function() -- after the LEVEL UP banner
				if not player.Parent then
					return
				end
				if index == 1 then
					announce(player, "🏰 DUNGEONS UNLOCKED!", string.format("Team up with up to %d dragons in %s. Open 🏰 Dungeons in the menu.", Dungeons.MAX_GROUP, def.name), def.color, 6)
				else
					announce(player, def.icon .. " NEW DUNGEON!", def.name .. " is open to you now. Find it in 🏰 Dungeons.", def.color, 6)
				end
				notify(player, string.format("%s unlocked! Go alone, bring friends, or let the queue find you a group.", def.name), def.color, "🏰", "Dungeons")
			end)
		end
	end
end

-- Called by PlayerService when a dragon dies. true = it's in a run (no timed respawn: it gets up
-- when the group is out of combat, or at the entrance after a wipe).
function DungeonService.onPlayerDied(player: Player): boolean
	local run = runOf[player]
	if not run or not run.members[player] then
		return false
	end
	run.members[player].dead = true
	run.members[player].diedAt = now()
	markDirty()
	return true
end

---------------------------------------------------------------- the run tick

local function engaged(e, t: number): boolean
	return e.target ~= nil or t - (e.lastCombat or 0) < Dungeons.COMBAT_LINGER
end

local function revive(player: Player, cf: CFrame)
	S.PlayerService.spawn(player, cf)
	local _, humanoid = S.PlayerService.getCharacter(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth * Dungeons.REVIVE_HEALTH
	end
end

local function inHazard(run, pos: Vector3): boolean
	local origin = run.built.origin
	for _, h in ipairs(run.def.hazards or {}) do
		if h.min then
			local a, b = origin + h.min, origin + h.max
			if pos.X >= a.X and pos.X <= b.X and pos.Z >= a.Z and pos.Z <= b.Z and pos.Y >= a.Y - 2 and pos.Y <= b.Y + 3 then
				return true
			end
		else
			local c = origin + h.center
			if flat(pos - c).Magnitude <= h.radius and pos.Y <= origin.Y + h.top + 3 then
				return true
			end
		end
	end
	return false
end

local function wipeReset(run)
	for i = #run.mobs, 1, -1 do
		local e = run.mobs[i]
		if not e.dead and e.model.Parent then
			if e.summoned then
				S.EnemyService.despawn(e)
				table.remove(run.mobs, i)
			else
				e.target = nil
				e.returning = false
				e.lastCombat = 0
				e.humanoid.Health = e.humanoid.MaxHealth
				e.model:PivotTo(CFrame.new(e.home + Vector3.new(0, e.humanoid.HipHeight + e.root.Size.Y / 2 + 0.5, 0)))
			end
		end
	end
	for _, boss in pairs(run.bosses) do
		resetBoss(boss)
	end
	for player, m in pairs(run.members) do
		m.dead = false
		if player.Parent then
			S.PlayerService.spawn(player, DungeonService.spawnCFrame(player))
		end
	end
	run.wipeAt = nil
	markDirty()
end

local function tickRun(run, t: number, dt: number)
	for player in pairs(run.members) do
		if not player.Parent then
			run.members[player] = nil
			runOf[player] = nil
		end
	end
	if next(run.members) == nil then
		endRun(run)
		return
	end
	if run.cleared and run.closeAt and t >= run.closeAt then
		for player in pairs(run.members) do
			leaveRun(player, "The dungeon is quiet now. Back out you go!")
		end
		return
	end

	-- monsters: combat state, giving up, walking home, healing slowly
	local inCombat = false
	for _, e in ipairs(run.mobs) do
		if not e.dead and e.model.Parent then
			if e.target and t - (e.lastCombat or 0) > Dungeons.EVADE_TIME then
				e.target = nil
				e.returning = true
			end
			if e.returning then
				e.returnSince = e.returnSince or t
				if t - e.returnSince > Dungeons.RETURN_STUCK then
					e.model:PivotTo(CFrame.new(e.home + Vector3.new(0, e.humanoid.HipHeight + e.root.Size.Y / 2 + 0.5, 0)))
					e.returning = false
				end
			else
				e.returnSince = nil
			end
			if engaged(e, t) then
				inCombat = true
			elseif e.humanoid.Health < e.humanoid.MaxHealth then
				e.humanoid.Health = math.min(e.humanoid.MaxHealth, e.humanoid.Health + e.humanoid.MaxHealth * Dungeons.MOB_REGEN * dt)
			end
		end
	end
	for _, boss in pairs(run.bosses) do
		local e = boss.e
		if not e.dead and e.model.Parent then
			if boss.engaged then
				inCombat = true
				if not boss.down and t - (e.lastCombat or 0) > Dungeons.EVADE_TIME then
					-- nobody's fighting it: it goes back to its spot
					boss.engaged = false
					BossKit.reset(boss.brain)
					e.humanoid:MoveTo(boss.home)
				end
			else
				local near = false
				for _, p in ipairs(participants(run, boss)) do
					if (p.root.Position - e.root.Position).Magnitude <= Dungeons.BOSS_AGGRO then
						near = true
					end
				end
				if near or t - (e.lastCombat or 0) < 1 then
					boss.engaged = true
					e.lastCombat = t
					for player in pairs(run.members) do
						notify(player, boss.def.name .. " wakes up!", boss.def.color, "💀")
					end
					markDirty()
				elseif e.humanoid.Health < e.humanoid.MaxHealth and not boss.shielded then
					e.humanoid.Health = math.min(e.humanoid.MaxHealth, e.humanoid.Health + e.humanoid.MaxHealth * Dungeons.BOSS_REGEN * dt)
				end
			end
			if boss.engaged then
				bossTraits(run, boss)
			end
		end
	end
	if inCombat ~= run.inCombat then
		run.inCombat = inCombat
		markDirty()
	end
	if inCombat then
		run.calmSince = t
	end

	-- dragons: lava, straying out of the cave, getting back up, and wipes
	local alive, dead = 0, 0
	for player, m in pairs(run.members) do
		local character, humanoid, root = S.PlayerService.getCharacter(player)
		if character and not m.dead then
			alive += 1
			if inHazard(run, root.Position) then
				S.CombatService.damagePlayer(player, humanoid.MaxHealth * Dungeons.LAVA_BURN * dt, { dotKind = "burn", ignoreSafe = true })
			end
			local b = run.built.bounds
			local p = root.Position
			if p.X < b.min.X or p.X > b.max.X or p.Y < b.min.Y or p.Y > b.max.Y or p.Z < b.min.Z or p.Z > b.max.Z then
				S.PlayerService.teleport(player, DungeonService.spawnCFrame(player))
			end
		else
			dead += 1
			m.dead = true
		end
	end
	if alive == 0 and dead > 0 then
		if not run.wipeAt then
			run.wipeAt = t + Dungeons.WIPE_DELAY
			for player in pairs(run.members) do
				notify(player, "Your whole group fell! Back to the entrance... and the monsters heal up.", BAD, "💀")
			end
			markDirty()
		elseif t >= run.wipeAt then
			wipeReset(run)
		end
	elseif dead > 0 and alive > 0 and not inCombat and t - run.calmSince >= Dungeons.REVIVE_DELAY then
		local helpers = aliveMembers(run)
		for player, m in pairs(run.members) do
			if m.dead and player.Parent then
				local friend = helpers[math.random(1, #helpers)]
				local spot = floorAt(friend.root.Position + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)))
				m.dead = false
				revive(player, CFrame.new(spot + Vector3.new(0, 6, 0)))
				notify(player, "Your group's out of combat: back on your feet!", INFO, "💚")
			end
		end
		markDirty()
	end
end

local function thinkBosses()
	local t = now()
	for _, run in pairs(runs) do
		if not run.ended then
			for _, boss in pairs(run.bosses) do
				if boss.engaged and not boss.down and not boss.e.dead then
					BossKit.think(boss.brain, t)
				elseif not boss.engaged and not boss.e.dead and not boss.e.root.Anchored then
					if flat(boss.e.root.Position - boss.home).Magnitude > 6 then
						boss.e.humanoid:MoveTo(boss.home)
					end
				end
			end
		end
	end
end

local function tickQueues(t: number)
	for _, match in ipairs(LocalMatchmaker.poll(t)) do
		startCheck(match.dungeonId, match.groups) -- (they stay `queued` until they go in or someone says no)
	end
	for _, check in pairs(checks) do
		if t >= check.expiresAt then
			declineCheck(check, nil)
		end
	end
	for player, list in pairs(invites) do
		for groupId, expires in pairs(list) do
			if expires < t or not groups[groupId] then
				list[groupId] = nil
			end
		end
		if next(list) == nil then
			invites[player] = nil
		end
	end
end

---------------------------------------------------------------- lifecycle

function DungeonService.init(services)
	S = services
end

function DungeonService.start()
	local map = workspace:WaitForChild("Map")
	folder = Instance.new("Folder")
	folder.Name = "Dungeons"
	folder.Parent = map

	Remotes.func("DungeonAction").OnServerInvoke = onAction

	local function hookExit(prompt: Instance)
		prompt.Triggered:Connect(function(player)
			local run = runOf[player]
			if run and prompt:IsDescendantOf(run.built.model) then
				leaveRun(player, "You left the dungeon.")
			end
		end)
	end
	local function hookChest(prompt: Instance)
		prompt.Triggered:Connect(function(player)
			openChest(player, prompt)
		end)
	end
	for _, prompt in ipairs(CollectionService:GetTagged("DungeonExit")) do
		hookExit(prompt)
	end
	for _, prompt in ipairs(CollectionService:GetTagged("DungeonChest")) do
		hookChest(prompt)
	end
	CollectionService:GetInstanceAddedSignal("DungeonExit"):Connect(hookExit)
	CollectionService:GetInstanceAddedSignal("DungeonChest"):Connect(hookChest)

	Players.PlayerRemoving:Connect(function(player)
		if runOf[player] then
			leaveRun(player)
		end
		removeFromGroup(player)
		invites[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		task.wait(3)
		push(player)
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.1 then
			return
		end
		accum = 0
		local ok, err = pcall(thinkBosses)
		if not ok then
			warn("[DungeonService] boss AI error:", err)
		end
	end)

	local lastPush = 0
	local dt = 0.25
	while true do
		task.wait(dt)
		local t = now()
		local ok, err = pcall(function()
			tickQueues(t)
			for _, run in pairs(runs) do
				if not run.ended then
					tickRun(run, t, dt)
				end
			end
		end)
		if not ok then
			warn("[DungeonService]", err)
		end
		if dirty or t - lastPush >= 1 then
			lastPush = t
			pushAll()
		end
	end
end

return DungeonService
