-- Server smoke test: adds fake players and walks them through the game's features on a
-- virtual clock. Prints every script error with a traceback, plus any failed expectations.
-- Run: ./run.sh (boot.luau is prepended)
-- Dungeons: unlocking, groups and invites, the queue and ready checks, a Barrow run (pulls, the
-- give-up fail-safe, knocked out until the fight's over, a wipe, Grimvald, Haldor's second life and
-- leap, loot and pity, the hoard, Ylva's quest) and a solo Forge run (harpoon, fire lanes, the rune
-- shield, phases, Brakki's enrage, the freed dragon, admin tuning). (Its own function: the main
-- scenario is out of local variables.)
local function dungeonScenario(p1, p2, profile)
	step("dungeons: unlock + groups")
	local Dungeons = require(__proxy("Shared/Config/Dungeons"))
	local Pets = require(__proxy("Shared/Config/Pets"))
	local DungeonBuilder = require(__proxy("Server/World/DungeonBuilder"))
	local Props = require(__proxy("Server/World/Props"))
	local profile2 = S.PlayerService.getProfile(p2)
	local function dungeon(p, name, args)
		return invoke("DungeonAction", p, name, args or {})
	end
	local function lastRemote(name, p)
		for i = #REMOTE_LOG, 1, -1 do
			local entry = REMOTE_LOG[i]
			if entry.remote == name and (entry.player == p or entry.all) then
				return entry.args[1]
			end
		end
		return nil
	end
	local function vfxSince(kind: string, from: number): number
		local n = 0
		for i = from + 1, #REMOTE_LOG do
			local entry = REMOTE_LOG[i]
			if entry.remote == "VFX" and type(entry.args[1]) == "table" and entry.args[1].kind == kind then
				n += 1
			end
		end
		return n
	end
	local function flatDist(a: Vector3, b: Vector3): number
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	S.PlayerService.setLevel(p2, 14)
	local okLow, whyLow = dungeon(p2, "queue", { dungeonId = "Barrow" })
	check(not okLow and tostring(whyLow):find("level 15") ~= nil, "level 14 can't go into the Barrow (" .. tostring(whyLow) .. ")")
	dungeon(p2, "leaveGroup")
	local announced = remoteCount("Announce", p2)
	S.PlayerService.addXP(p2, Game.xpToNext(14) + 5, true)
	check(profile2.level == 15, "p2 reaches level 15")
	task.wait(5)
	check(remoteCount("Announce", p2) >= announced + 2, "LEVEL UP, then DUNGEONS UNLOCKED")
	local unlockToast = false
	for _, entry in ipairs(REMOTE_LOG) do
		if entry.remote == "Notify" and entry.player == p2 and entry.args[1].open == "Dungeons" then
			unlockToast = true
		end
	end
	check(unlockToast, "the unlock toast offers to open the Dungeons window")
	check(profile2.dungeons.seen == 0, "the 🏰 badge waits for the window")
	check(dungeon(p2, "seen") and profile2.dungeons.seen == 15, "...and clears once it's been seen")
	-- p2 picks up Ylva's quest at the Barrow's mouth first
	local ylva = Zones.QuestGivers.Ylva.position
	tp(p2, Vector3.new(ylva.X, Props.groundY(ylva.X, ylva.Z) + 6, ylva.Z - 12))
	task.wait(0.3)
	local okQuest, whyQuest = invoke("AcceptQuest", p2, "D1")
	check(okQuest, "Ylva's quest: " .. tostring(whyQuest))
	local cameFrom = rootOf(p2).Position

	local okInvite, whyInvite = dungeon(p1, "invite", { userId = 102 })
	check(okInvite, "invite: " .. tostring(whyInvite))
	local invite = lastRemote("DungeonInvite", p2)
	check(invite ~= nil and invite.from == p1.DisplayName, "p2 got the invite")
	check(dungeon(p2, "accept", { groupId = invite and invite.groupId }), "p2 joins")
	local group = S.DungeonService.groupOf(p1)
	check(group ~= nil and S.DungeonService.groupOf(p2) == group and #group.members == 2 and group.leader == p1, "one group of two, p1 leads")
	check(not dungeon(p2, "queue", { dungeonId = "Barrow" }), "only the leader queues the group")
	check(not dungeon(p1, "queue", { dungeonId = "Forge" }), "everyone in the group must be high enough level")

	step("dungeons: queue + ready check")
	local partial = Dungeons.QUEUE_PARTIAL_AFTER
	Dungeons.QUEUE_PARTIAL_AFTER = 3
	check(dungeon(p1, "queue", { dungeonId = "Barrow" }), "queue for the Barrow")
	check(S.DungeonService.matchmaker.looking("Barrow") == 2, "2 dragons looking")
	task.wait(1.2)
	local st = lastRemote("DungeonState", p1)
	check(st and st.queue and st.queue.dungeonId == "Barrow", "the pill shows the queue")
	task.wait(3)
	st = lastRemote("DungeonState", p2)
	check(st and st.check ~= nil and st.check.total == 2, "after a while 2 dragons are enough: a ready check")
	check(dungeon(p2, "ready", { yes = false }), "p2 isn't ready")
	check(not group.queued and S.DungeonService.matchmaker.looking("Barrow") == 0, "saying no takes the group out of the queue")
	check(dungeon(p1, "queue", { dungeonId = "Barrow" }), "queue again")
	task.wait(4)
	check(dungeon(p1, "ready", { yes = true }), "p1 is ready")
	check(S.DungeonService.runOf(p1) == nil, "nobody goes in until everyone's ready")
	check(dungeon(p2, "ready", { yes = true }), "p2 is ready")
	Dungeons.QUEUE_PARTIAL_AFTER = partial
	task.wait(0.5)
	local run = S.DungeonService.runOf(p1)
	check(run ~= nil and S.DungeonService.runOf(p2) == run, "both dragons are in the same run")

	step("dungeons: the Draugr Barrow")
	local origin = run.built.origin
	check(p1:GetAttribute("InDungeon") == "Barrow" and p1:GetAttribute("DungeonRun") == run.id, "run attributes")
	check(rootOf(p1) ~= nil and (rootOf(p1).Position - origin).Magnitude < 60, "teleported to the entrance")
	local mobCount = 0
	for _, pack in ipairs(Dungeons.List.Barrow.packs) do
		mobCount += #Dungeons.packMobs(pack)
	end
	check(#run.mobs == mobCount, "every pack spawned (" .. #run.mobs .. "/" .. mobCount .. ")")
	local onFloor = true
	for _, e in ipairs(run.mobs) do
		local floor = DungeonBuilder.floorAt(e.home)
		if math.abs(e.home.Y - floor.Y) > 1 or e.home.Y > origin.Y + 2 or e.root.Position.Y > e.home.Y + 12 then
			onFloor = false
		end
	end
	check(onFloor, "monsters stand on the cave floor, not on its roof")
	check(run.bosses.boss ~= nil and run.bosses.mini ~= nil, "a mini-boss and a boss are waiting")
	check(run.hpMult == Dungeons.GROUP_HEALTH[2] and run.dmgMult == Dungeons.GROUP_DAMAGE[2], "a group of 2 gets the 2-dragon scaling")
	local barrowHp = Dungeons.Bosses.Haldor.health * Dungeons.GROUP_HEALTH[2]
	check(math.abs(run.bosses.boss.e.humanoid.MaxHealth - barrowHp) < 2, "Haldor's health is set for the group")
	task.wait(1.5)
	check((rootOf(p1).Position - origin).Magnitude < 80, "ZoneService leaves dragons in a dungeon alone")
	local annP1 = remoteCount("Announce", p1)
	check(invoke("AdminAction", p1, "bossNow", { seconds = 200 }), "a world boss warning")
	task.wait(1)
	check(remoteCount("Announce", p1) == annP1, "no world boss warning reaches a dragon in a dungeon")
	check(not invoke("BossQueue", p1, true), "and it can't queue for the world boss")
	check(not invoke("TeleportHome", p1), "no flying home from a dungeon")

	step("dungeons: pulls, giving up, getting back up")
	local pack = run.packs[1]
	local a, b = pack.mobs[1], pack.mobs[2]
	tp(p1, a.root.Position + Vector3.new(0, 3, 10))
	S.CombatService.damageEnemy(p1, a, 1, false)
	task.wait(0.4)
	check(a.target == p1 and b.target == p1, "hitting one draugr pulls its whole pack")
	check(run.inCombat, "the run is in combat")
	local _, hum2 = S.PlayerService.getCharacter(p2)
	hum2.Health = 0
	task.wait(Game.RESPAWN_TIME + 2)
	check(rootOf(p2) == nil and run.members[p2].dead, "knocked out mid-fight: no respawn yet")
	check(lastRemote("Died", p2) == -1, "the death screen waits for the group")
	-- the fail-safe: nobody's hit anybody for Dungeons.EVADE_TIME, so the monster gives up
	a.customAI = true
	a.target = p1
	a.lastCombat = os.clock() - Dungeons.EVADE_TIME - 1
	task.wait(0.5)
	check(a.target == nil and a.returning, "a monster nobody fights gives up and walks home")
	a.customAI = false
	-- out of combat: p2 gets back up beside p1
	rootOf(p1).Parent:SetAttribute("Stealthed", true)
	task.wait(Dungeons.COMBAT_LINGER + Dungeons.REVIVE_DELAY + 1.5)
	check(rootOf(p2) ~= nil and not run.members[p2].dead, "out of combat (the pack lost p1): p2 is back up")
	check(rootOf(p2) and flatDist(rootOf(p2).Position, rootOf(p1).Position) < 20, "...beside p1")
	local _, humUp = S.PlayerService.getCharacter(p2)
	check(humUp and humUp.Health < humUp.MaxHealth * 0.8, "...not at full health (a revive, not a respawn)")
	local idle = run.packs[3].mobs[1] -- (a pack nobody's touched)
	idle.humanoid.Health = idle.humanoid.MaxHealth * 0.5
	task.wait(2)
	local frac = idle.humanoid.Health / idle.humanoid.MaxHealth
	check(frac > 0.52 and frac < 0.8, "out of combat, monsters heal slowly (" .. string.format("%.2f", frac) .. ")")
	rootOf(p1).Parent:SetAttribute("Stealthed", nil)

	step("dungeons: Grimvald and a wipe")
	invoke("AdminAction", p1, "god", { on = true })
	invoke("AdminAction", p1, "god", { on = true, userId = 102 })
	local grim = run.bosses.mini
	tp(p1, grim.e.root.Position + Vector3.new(0, 3, 14))
	tp(p2, grim.e.root.Position + Vector3.new(0, 3, -14))
	task.wait(0.6)
	check(grim.engaged, "Grimvald wakes when dragons come close")
	S.CombatService.damageEnemy(p1, grim.e, grim.e.humanoid.MaxHealth * 0.6, false)
	task.wait(0.6)
	check(grim.summoned[1] and #grim.adds == 2, "at half health Grimvald calls two Barrow Hounds")
	check(not grim.enraged, "Grimvald never enrages")
	local gold2 = profile2.gold
	S.CombatService.damageEnemy(p1, grim.e, 1e9, false)
	task.wait(0.6)
	check(grim.e.dead and profile2.gold > gold2, "Grimvald down: loot for everyone in the run")
	check(#grim.adds == 0 or grim.adds[1].dead, "his hounds fall with him")
	-- the boss: wake him, hurt him, then everybody falls
	invoke("AdminAction", p1, "god", { on = false })
	invoke("AdminAction", p1, "god", { on = false, userId = 102 })
	local boss = run.bosses.boss
	tp(p1, boss.e.root.Position + Vector3.new(0, 3, 20))
	tp(p2, boss.e.root.Position + Vector3.new(0, 3, -20))
	S.CombatService.damageEnemy(p1, boss.e, boss.e.humanoid.MaxHealth * 0.3, false)
	task.wait(0.6)
	check(boss.engaged, "hitting Haldor wakes him")
	for _, p in ipairs({ p1, p2 }) do
		local _, h = S.PlayerService.getCharacter(p)
		if h then
			h.Health = 0
		end
	end
	task.wait(Dungeons.WIPE_DELAY + 1)
	check(rootOf(p1) ~= nil and rootOf(p2) ~= nil, "a wipe: everyone gets up...")
	check((rootOf(p1).Position - run.built.spawn.Position).Magnitude < 30, "...at the entrance")
	check(boss.e.humanoid.Health == boss.e.humanoid.MaxHealth and not boss.engaged, "Haldor heals to full and goes back to sleep")
	check(a.dead or (a.home and flatDist(a.root.Position, a.home) < 8 and a.humanoid.Health == a.humanoid.MaxHealth), "pulled monsters reset too")

	step("dungeons: Haldor's second life")
	invoke("AdminAction", p1, "god", { on = true })
	invoke("AdminAction", p1, "god", { on = true, userId = 102 })
	tp(p1, boss.e.root.Position + Vector3.new(0, 3, 16))
	tp(p2, boss.e.root.Position + Vector3.new(0, 3, -16))
	task.wait(0.5)
	S.CombatService.damageEnemy(p1, boss.e, 1e9, false)
	task.wait(0.3)
	check(not boss.e.dead and boss.lifeUsed and boss.e.immune, "at 0 Haldor collapses instead of dying")
	check(S.CombatService.damageEnemy(p1, boss.e, 100, false) == 0, "...and can't be hurt while he's down")
	check(not run.cleared, "no loot yet")
	task.wait(Dungeons.Bosses.Haldor.secondLife.delay + 1)
	local hp = boss.e.humanoid.Health / boss.e.humanoid.MaxHealth
	check(not boss.e.immune and math.abs(hp - Dungeons.Bosses.Haldor.secondLife.health) < 0.05, "he rises again at 40% (" .. string.format("%.2f", hp) .. ")")
	check(boss.brain.moves.Leap ~= nil and boss.e.displayName == "Haldor Unbound", "...as Haldor Unbound, who leaps")
	-- the leap: p2 stands far across the mound
	local room = boss.room
	local farSpot = DungeonBuilder.floorAt(room.center + Vector3.new(0, 2, -44))
	tp(p1, boss.e.root.Position + Vector3.new(6, 3, 6))
	tp(p2, farSpot + Vector3.new(0, 4, 0))
	local leapt = false
	for _ = 1, 40 do
		task.wait(0.25)
		if flatDist(boss.e.root.Position, farSpot) < 14 then
			leapt = true
			break
		end
	end
	check(leapt, "Haldor Unbound leaps across the mound onto the farthest dragon")

	step("dungeons: loot, the hoard, the quest")
	local clears = profile2.dungeons.clears.Barrow or 0
	local items2 = #profile2.inventory
	profile2.dungeons.pity.Barrow = 1 -- (pity this high guarantees the egg)
	S.CombatService.damageEnemy(p1, boss.e, 1e9, false)
	task.wait(1)
	check(boss.e.dead and run.cleared, "Haldor falls for good: the Barrow is cleared")
	check(profile2.dungeons.clears.Barrow == clears + 1 and profile2.dungeonClears >= 1, "the clear is counted")
	check((profile2.eggs.BarrowEgg or 0) >= 1 and profile2.dungeons.pity.Barrow == 0, "pity guarantees the Barrow Egg, then resets")
	check(#profile2.inventory > items2, "boss gear")
	check(profile2.titles["Barrow Breaker"] == true, "first clear: the Barrow Breaker title")
	check(profile2.quests.active.D1 == 1, "Ylva's quest is done")
	local okPet, pet = invoke("HatchEgg", p2, "BarrowEgg")
	check(okPet and Pets.Species[pet.species] and Pets.Species[pet.species].egg == "BarrowEgg", "the Barrow Egg hatches a Barrow pet")
	local hoard = run.built.chest and run.built.chest:FindFirstChildOfClass("ProximityPrompt")
	check(hoard ~= nil, "the hidden hoard")
	if hoard then
		local g0 = profile2.gold
		hoard.Triggered:Fire(p2)
		task.wait(0.2)
		local g1 = profile2.gold
		hoard.Triggered:Fire(p2)
		task.wait(0.2)
		check(g1 > g0 and profile2.gold == g1, "the hoard pays each dragon once")
	end
	check(dungeon(p2, "leaveRun"), "p2 leaves")
	task.wait(0.3)
	check(S.DungeonService.runOf(p2) == nil and p2:GetAttribute("InDungeon") == nil, "out of the run")
	check(rootOf(p2) ~= nil and (rootOf(p2).Position - cameFrom).Magnitude < 10, "back where p2 came in from")
	local items3 = #profile2.inventory
	local okTurn, whyTurn = invoke("TurnInQuest", p2, "D1")
	check(okTurn, "turn in to Ylva: " .. tostring(whyTurn))
	local relic = profile2.inventory[#profile2.inventory]
	check(#profile2.inventory > items3 and relic.uniq == "BarrowlightLantern" and relic.ilvl == Dungeons.List.Barrow.ilvl, "the Barrowlight Lantern, at the Barrow's item level")
	check(dungeon(p1, "leaveRun"), "p1 leaves")
	task.wait(0.5)
	check(run.ended, "the run ends when everyone's gone")

	step("dungeons: the Rune Forge")
	check(invoke("AdminAction", p1, "enterDungeon", { dungeonId = "Forge" }), "admin: into the Forge alone")
	local forge = S.DungeonService.runOf(p1)
	check(forge ~= nil and forge.def.id == "Forge" and forge.hpMult == Dungeons.GROUP_HEALTH[1], "a solo Forge run")
	check(forge.built.chained ~= nil and forge.built.chained.Parent ~= nil, "the elder dragon hangs in its chains")
	local sig = forge.bosses.boss
	-- hovering high above Sigrun: she harpoons you down
	local sigFloor = sig.home
	tp(p1, sigFloor + Vector3.new(8, 32, 8))
	local pulled = false
	for _ = 1, 40 do
		task.wait(0.25)
		local r = rootOf(p1)
		if r and r.Position.Y < sigFloor.Y + 12 then
			pulled = true
			break
		end
	end
	check(sig.engaged, "Sigrun wakes")
	check(pulled, "her harpoon drags a hovering dragon down")
	local log0 = #REMOTE_LOG
	task.wait(4)
	check(sig.brain.nextMove.Lane ~= nil and vfxSince("telegraph", log0) > 3, "the chained dragon breathes a fire lane across the room")
	S.CombatService.damageEnemy(p1, sig.e, sig.e.humanoid.MaxHealth * 0.45, false)
	task.wait(0.6)
	check(sig.phase == 1 and sig.shielded and sig.e.immune, "at 60% Sigrun raises her rune shield")
	check(sig.shieldAdds and #sig.shieldAdds == 3, "...with three Forge Guards")
	check(S.CombatService.damageEnemy(p1, sig.e, 1000, false) == 0, "she can't be hurt behind it")
	for _, g in ipairs(sig.shieldAdds or {}) do
		S.CombatService.damageEnemy(p1, g, 1e9, false)
	end
	task.wait(0.6)
	check(not sig.shielded and not sig.e.immune, "the shield shatters when the guards fall")
	S.CombatService.damageEnemy(p1, sig.e, sig.e.humanoid.MaxHealth * 0.3, false)
	task.wait(0.6)
	check(sig.phase == 2 and sig.brain.moves.Whirlwind ~= nil, "below 30% she whirls")
	local brakki = forge.bosses.mini
	S.CombatService.damageEnemy(p1, brakki.e, brakki.e.humanoid.MaxHealth * 0.75, false)
	task.wait(0.8)
	check(brakki.engaged and brakki.enraged, "Brakki enrages at 30%")
	local forgeClears = profile.dungeons.clears.Forge or 0
	log0 = #REMOTE_LOG
	S.CombatService.damageEnemy(p1, sig.e, 1e9, false)
	task.wait(1)
	check(forge.cleared and profile.dungeons.clears.Forge == forgeClears + 1, "Sigrun falls: the Forge is cleared")
	check(vfxSince("shatter", log0) >= 1, "the elder dragon's chains shatter")
	task.wait(4.5)
	check(forge.built.chained.Parent == nil, "...and it flies off, free")
	check(invoke("AdminAction", p1, "tuneDungeon", { dungeonId = "Forge", key = "bossHp", value = 2 }) and Tuning.dungeon("Forge", "bossHp") == 2, "admin: tune a dungeon")
	local okReport, report = invoke("AdminAction", p1, "printTuning", {})
	check(okReport and tostring(report):find("Dungeons.Bosses.Sigrun.health") ~= nil, "the tuning report has the new boss health")
	invoke("AdminAction", p1, "resetTuning", {})
	check(dungeon(p1, "leaveRun"), "p1 leaves the Forge")
	task.wait(0.5)
	check(forge.ended, "the Forge run ends")
	-- the same copy of the Forge is used again, with its dragon back in chains
	check(invoke("AdminAction", p1, "enterDungeon", { dungeonId = "Forge" }), "the Forge again")
	local again = S.DungeonService.runOf(p1)
	check(again and again.built == forge.built and again.built.chained.Parent ~= nil, "the next group finds the elder dragon chained again")
	dungeon(p1, "leaveRun")
	invoke("AdminAction", p1, "god", { on = false })
	invoke("AdminAction", p1, "god", { on = false, userId = 102 })
	task.wait(1)

end

task.spawn(function()
	task.wait(3)
	-- keep it daytime (no nightfall raids) until the day/night section below
	S.DayNightService.setHour(6.5)
	local p1 = addPlayer(101, "Tester")
	local p2 = addPlayer(102, "Buddy")
	task.wait(1)
	step("choose class")
	check(invoke("GetProfile", p1) ~= nil, "GetProfile")
	check(invoke("ChooseClass", p1, "Behemoth") == true, "ChooseClass p1")
	check(invoke("ChooseClass", p2, "Stormwing") == true, "ChooseClass p2")
	task.wait(1)
	check(rootOf(p1) ~= nil, "p1 has a dragon")
	local profile = S.PlayerService.getProfile(p1)
	check(profile.hunger >= Game.HUNGER_MAX - 1, "starts full")

	step("abilities")
	for _, abilityId in ipairs(S.PlayerService.getStats(p1).abilities) do
		fire("CastAbility", p1, abilityId, rootOf(p1).Position + Vector3.new(0, 0, -20), "t1")
	end
	task.wait(2)

	step("tutorial")
	fire("TutorialStep", p1, 4)
	task.wait(0.2)
	check(profile.tutorial == 4, "tutorial step saved")
	fire("TutorialStep", p1, -1)
	task.wait(0.2)
	check(profile.tutorial == -1 and profile.tutorialRewarded, "tutorial finished + rewarded")
	check((profile.eggs.EmberEgg or 0) >= 1, "tutorial egg")

	step("codes + admin")
	local ok, msg = invoke("RedeemCode", p1, "dragonrealm")
	check(ok, "promo code: " .. tostring(msg))
	ok = invoke("RedeemCode", p1, "DRAGONREALM")
	check(not ok, "promo code only once")
	check(not invoke("AdminAction", p1, "gold", { amount = 5 }), "not admin before code")
	ok, msg = invoke("RedeemCode", p1, "DRAGONLORD")
	check(ok and S.AdminService.isAdmin(p1), "admin code: " .. tostring(msg))
	check(invoke("AdminAction", p1, "gold", { amount = 200000 }), "admin gold")
	check(invoke("AdminAction", p1, "setLevel", { level = 12 }) and profile.level == 12, "admin set level")
	check(invoke("AdminAction", p1, "setLevel", { level = 30, userId = 102 }) and S.PlayerService.getProfile(p2).level == 30, "admin set other player's level")
	check(invoke("AdminAction", p1, "setClass", { classId = "Venomspine" }) and profile.class == "Venomspine", "admin set class")
	task.wait(1)
	for _, action in ipairs({ "seeds", "food", "heal", "resetChests", "respawnCamps", "miniBosses", "unlockPlots", "robots" }) do
		check(invoke("AdminAction", p1, action, {}), "admin " .. action)
	end
	check(invoke("AdminAction", p1, "item", { rarity = "Epic" }), "admin item")
	check(invoke("AdminAction", p1, "egg", { eggId = "MythicEgg" }), "admin egg")
	check(invoke("AdminAction", p1, "potions", { rank = 2 }) and profile.potions.WingTonic == 2, "admin potions")
	check(invoke("AdminAction", p1, "god", { on = true }) and p1:GetAttribute("GodMode"), "god mode")
	check(invoke("AdminAction", p1, "god", { on = false }), "god mode off")
	check(invoke("AdminAction", p1, "teleport", { place = "RaiderCamp" }), "admin teleport")
	check(invoke("AdminAction", p1, "tuneGlobal", { key = "playerDamage", value = 1.5 }) and Tuning.global("playerDamage") == 1.5, "tune global")
	check(invoke("AdminAction", p1, "tuneAbility", { abilityId = "Fireball", field = "dmg", value = 1.3 }), "tune ability")
	check(invoke("AdminAction", p1, "tuneAbility", { abilityId = "Breath", field = "cd", value = 0.8 }), "tune breath")
	check(invoke("AdminAction", p1, "tuneTalent", { talentId = "Venomspine.ToxicGlands", value = 2 }), "tune talent")
	ok, msg = invoke("AdminAction", p1, "printTuning", {})
	check(ok and type(msg) == "string" and msg:find("Fireball"), "print tuning")
	check(invoke("AdminAction", p1, "resetTuning", {}) and Tuning.isDefault(), "reset tuning")
	check(invoke("GetTuning", p1) ~= nil, "GetTuning")

	step("farming + robots")
	tp(p1, S.FarmService.getHomeCFrame(p1).Position)
	task.wait(0.5)
	check(invoke("PlantSeed", p1, 1, "Emberbloom") == true, "plant seed")
	check(invoke("PlantSeed", p1, 2, "Frostpetal") == true, "plant second seed")
	-- water plot 2 by hand through its prompt when it gets thirsty
	local base = nil
	for _, m in ipairs(CollectionService:GetTagged("PlayerBase")) do
		if m:GetAttribute("OwnerUserId") == p1.UserId then
			base = m
		end
	end
	check(base ~= nil, "found my base")
	check(base and base:FindFirstChild("BotDock") ~= nil, "base has a bot dock")
	for t = 1, 20 do
		task.wait(10)
		local pl = profile.plots[1]
		if t % 4 == 0 then
			print(string.format("   plot1 %s stage=%s need=%s prog=%.0f quality=%s  flowers=%d robots=%s/%s", pl and pl.seed or "-", pl and pl.stage or "-", pl and tostring(pl.need) or "-", pl and pl.progress or 0, pl and pl.quality or "-", profile.flowersHarvested, tostring(profile.robots.water), tostring(profile.robots.harvest)))
		end
	end
	local p1plots = profile.plots
	check(p1plots[1] == false or (p1plots[1] and p1plots[1].stage >= 1), "plot 1 exists")
	check(profile.flowersHarvested >= 1, "reap-bot harvested a flower (" .. tostring(profile.flowersHarvested) .. ")")
	check(p1plots[1] ~= false, "reap-bot lv2 replanted plot 1")

	step("buy robots without admin gifts")
	check(S.PlayerService.getProfile(p2).robots.water == false, "p2 has no robots")
	tp(p2, S.FarmService.getHomeCFrame(p2).Position)
	S.PlayerService.addGold(p2, 50000)
	check(invoke("BuyRobot", p2, "Water"), "buy water bot")
	check(invoke("BuyRobot", p2, "Harvest"), "buy reap bot")
	check(invoke("BuyRobot", p2, "Harvest"), "upgrade reap bot")
	check(not invoke("BuyRobot", p2, "Harvest"), "reap bot maxed")

	step("potions + eggs + pets")
	tp(p1, Zones.getShop("Alchemist").position + Vector3.new(0, 5, -8))
	local potionStock = S.StockService.get(p1).potions
	local potionId = next(potionStock)
	check(potionId ~= nil, "the cauldron has potions in stock")
	ok, msg = invoke("BuyPotion", p1, potionId)
	check(ok, "buy potion: " .. tostring(msg))
	potionStock[potionId] = 0
	check(not invoke("BuyPotion", p1, potionId), "sold-out potions can't be bought")
	tp(p1, Zones.getShop("Hatchery").position + Vector3.new(0, 5, -8))
	local petsBeforeBuy = #profile.pets
	S.StockService.get(p1).eggs.EmberEgg = 1
	check(invoke("BuyEgg", p1, "EmberEgg") and #profile.pets == petsBeforeBuy + 1, "buying an egg hatches it")
	check(not invoke("BuyEgg", p1, "EmberEgg"), "eggs run out of stock")
	check(not invoke("BuyEgg", p1, "MythicEgg"), "mythic eggs aren't sold")
	local pets = {}
	for _ = 1, 3 do
		local okHatch, pet = invoke("HatchEgg", p1, "EmberEgg")
		if okHatch then
			table.insert(pets, pet)
		end
	end
	local okMythic, mythicPet = invoke("HatchEgg", p1, "MythicEgg")
	check(okMythic and mythicPet, "hatch mythic egg")
	check(#profile.pets >= 2, "hatched pets: " .. #profile.pets)
	for _, pet in ipairs(profile.pets) do
		invoke("EquipPet", p1, pet.uid)
	end
	check(#profile.petsEquipped == Game.petSlots(profile.level), "equipped up to the slot limit")
	check(p1.Character:GetAttribute("Pets") ~= "", "character shows pets")
	check(invoke("UnequipPet", p1, profile.petsEquipped[1]), "unequip")
	local okRelease = invoke("ReleasePet", p1, profile.pets[1].uid)
	check(okRelease, "release pet")

	step("limited stock")
	local Shops = require(__proxy("Shared/Config/Shops"))
	local stock = S.StockService.get(p1)
	local gearCount = 0
	for _, row in ipairs(stock.gear) do
		gearCount += row.left -- (the same slot and rarity twice is one row)
	end
	check(gearCount >= Shops.Gear.count[1], "armory has gear in stock")
	local epics = 0
	for _, entry in ipairs(stock.gear) do
		if entry.rarity == "Epic" then
			epics += 1
		end
	end
	check(epics >= 1, "the armory always has an Epic")
	tp(p1, Zones.getShop("Armory").position + Vector3.new(0, 5, -8))
	S.PlayerService.addGold(p1, 2e6)
	local lastIndex = #stock.gear
	local entry = stock.gear[lastIndex]
	local leftBefore = entry.left
	ok, msg = invoke("BuyItem", p1, lastIndex)
	check(ok and entry.left == leftBefore - 1, "buying gear uses up stock: " .. tostring(msg))
	entry.left = 0
	check(not invoke("BuyItem", p1, lastIndex), "sold-out gear can't be bought")
	check(S.StockService.get(p2) ~= S.StockService.get(p1), "every dragon has their own stock")
	check(invoke("AdminAction", p1, "restockShops", {}), "admin restock")
	check(S.StockService.get(p1) ~= stock, "restock rerolls the shelves")

	step("hunger + food")
	fire("TutorialStep", p1, 0)
	S.SurvivalService.setHunger(p1, 5)
	task.wait(1.5)
	check(S.PlayerService.getStats(p1).attackPct < 0, "starving lowers attack")
	check(p1:GetAttribute("Hunger") ~= nil, "hunger attribute")
	ok, msg = invoke("EatFood", p1, nil)
	check(ok, "eat best food: " .. tostring(msg))
	tp(p1, Zones.getShop("Exchange").position + Vector3.new(0, 5, -8))
	local foodId = next(profile.food)
	if foodId then
		ok, msg = invoke("SellFood", p1, foodId, 1)
		check(ok, "sell food: " .. tostring(msg))
	end

	step("fishing")
	local spot = CollectionService:GetTagged("FishingSpot")[1]
	local spotPos = spot:GetPivot().Position
	tp(p1, spotPos + Vector3.new(0, 8, -16))
	local fishBefore = profile.fishCaught
	local prompt = spot:FindFirstChildWhichIsA("ProximityPrompt", true)
	prompt.Triggered:Fire(p1)
	task.wait(8)
	-- find the bite token the server sent
	local token = nil
	for i = #REMOTE_LOG, 1, -1 do
		local e = REMOTE_LOG[i]
		if e.remote == "Fishing" and e.player == p1 and e.args[1].phase == "bite" then
			token = e.args[1].token
			break
		end
	end
	check(token ~= nil, "fish bit")
	fire("FishingAction", p1, "reel", token, true)
	task.wait(0.5)
	check(profile.fishCaught == fishBefore + 1, "caught a fish")

	step("training dummies + sparring")
	local dummy = findEnemy(function(e)
		return e.dummy and e.model:GetAttribute("Kind") == "Dummy"
	end)
	check(dummy ~= nil, "dummy registered")
	local statsBefore = remoteCount("DummyStats", p1)
	if dummy then
		for _ = 1, 5 do
			S.CombatService.damageEnemy(p1, dummy, 100, false)
			task.wait(0.3)
		end
		check(dummy.humanoid.Health == dummy.humanoid.MaxHealth and not dummy.dead, "dummy never dies")
	end
	check(remoteCount("DummyStats", p1) > statsBefore, "DPS meter updates sent")
	local pen = Zones.Training.pen
	tp(p1, (pen.min + pen.max) / 2 + Vector3.new(0, 5, 0))
	local _, hum = S.PlayerService.getCharacter(p1)
	hum.Health = 5
	task.wait(6)
	check(hum.Health >= 1 and hum.Health <= 6, "sparring golem never knocks you out (" .. hum.Health .. ")")
	hum.Health = hum.MaxHealth

	step("hunting")
	local animal = findEnemy(function(e)
		return e.kind == "animal"
	end)
	check(animal ~= nil, "animals spawned")
	if animal then
		tp(p1, animal.root.Position + Vector3.new(0, 6, 6))
		local hunted = profile.animalsHunted
		S.CombatService.damageEnemy(p1, animal, 1e6, false)
		task.wait(0.5)
		check(profile.animalsHunted == hunted + 1, "animal hunt counted")
		local eatPrompt = animal.root:FindFirstChildWhichIsA("ProximityPrompt")
		check(eatPrompt ~= nil, "carcass has eat prompt")
		S.SurvivalService.setHunger(p1, 20)
		if eatPrompt then
			eatPrompt.Triggered:Fire(p1)
			task.wait(0.5)
			check(profile.hunger > 20, "eating the carcass filled hunger")
		end
	end
	-- a neutral boar fights back, a deer runs
	local boar = findEnemy(function(e)
		return e.typeId == "Boar"
	end)
	if boar then
		tp(p1, boar.root.Position + Vector3.new(0, 4, 8))
		S.CombatService.damageEnemy(p1, boar, 1, false)
		task.wait(1)
		check(boar.target == p1, "boar fights back")
	end

	step("camp chest + alarm + mini-boss")
	local camp = Zones.getCamp("RaiderCamp")
	tp(p1, camp.center + Vector3.new(4, 5, 4))
	local chest = nil
	for _, m in ipairs(CollectionService:GetTagged("CampChest")) do
		if m:GetAttribute("CampId") == "RaiderCamp" then
			chest = m
		end
	end
	check(chest ~= nil, "raider camp chest")
	if chest then
		local cp = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
		cp.PromptButtonHoldBegan:Fire(p1)
		task.wait(0.2)
		local alarmed = 0
		for _, e in ipairs(S.EnemyService.alive()) do
			if e.camp == camp and e.target == p1 then
				alarmed += 1
			end
		end
		check(alarmed > 2, "opening the chest alerted the camp (" .. alarmed .. ")")
		local opened = profile.chestsOpened
		cp.Triggered:Fire(p1)
		task.wait(0.5)
		check(profile.chestsOpened == opened + 1, "chest opened")
		check(not S.CampService.chestReadyFor(p1, camp.id), "chest is empty for the opener")
		check(S.CampService.chestReadyFor(p2, camp.id), "chest is still full for other dragons")
		cp.Triggered:Fire(p1)
		task.wait(0.2)
		check(profile.chestsOpened == opened + 1, "can't loot the same chest twice")
	end
	local boss = findEnemy(function(e)
		return e.miniBoss and e.camp == camp
	end)
	check(boss ~= nil, "mini-boss spawned")
	if boss then
		check(boss.nametag and boss.nametag.Bar:FindFirstChild("Skull") ~= nil, "mini-boss has a skull")
		task.wait(12) -- let it slam
		-- a friend who helped and is still around gets their own drops too
		p2:SetAttribute("GodMode", true)
		tp(p2, camp.center + Vector3.new(-6, 5, -6))
		local helperKills = S.PlayerService.getProfile(p2).vikingKills
		S.CombatService.damageEnemy(p2, boss, 5, false)
		S.CombatService.damageEnemy(p1, boss, 1e7, false)
		task.wait(0.5)
		check(boss.dead, "mini-boss died")
		check(S.PlayerService.getProfile(p2).vikingKills == helperKills + 1, "the helper got champion loot too")
		tp(p2, Zones.SPAWN)
		task.wait(0.2)
		check(not S.EnemyService.playerNearCamp(p2, camp), "helpers who left the camp don't count")
		p2:SetAttribute("GodMode", nil)
	end
	-- respawn timing: with one dragon in camp, the next raider takes longer than the base time
	local raider = findEnemy(function(e)
		return e.camp == camp and not e.miniBoss and e.kind == "viking"
	end)
	if raider then
		S.CombatService.damageEnemy(p1, raider, 1e7, false)
	end

	step("village dragons")
	local villagers = S.CivilianService.villagers()
	check(#villagers == #require(__proxy("Shared/Config/Civilians")).List, "villagers spawned (" .. #villagers .. ")")
	local route = S.CivilianService.route("PN", "Door7")
	check(route[#route] == "Door7" and #route >= 3, "a villager can find the way to a house (" .. table.concat(route, ">") .. ")")
	local startSpots = {}
	for i, v in ipairs(villagers) do
		startSpots[i] = v.root.Position
		check(v.model:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil, "villager can chat: " .. v.def.name)
	end
	if villagers[1] then
		local prompt = villagers[1].model:FindFirstChildWhichIsA("ProximityPrompt", true)
		prompt.Triggered:Fire(p1)
		task.wait(0.2)
		check(villagers[1].pauseUntil > os.clock(), "a villager stops to chat")
	end
	task.wait(40)
	local moved = 0
	for i, v in ipairs(villagers) do
		if (v.root.Position - startSpots[i]).Magnitude > 5 then
			moved += 1
		end
		check(v.model.Parent ~= nil and v.humanoid.Health > 0, "villager still around: " .. v.def.name)
	end
	check(moved >= 3, "villagers stroll around town (" .. moved .. " moved)")

	step("hornblower alarm")
	local fortress = Zones.getCamp("JarlsFortress")
	S.PlayerService.getProfile(p2).level = 30
	local horn = findEnemy(function(e)
		return e.typeId == "Hornblower"
	end)
	check(horn ~= nil, "hornblowers spawned")
	if horn then
		p2:SetAttribute("GodMode", true) -- the whole fortress (and its champion) would flatten p2 before we count
		tp(p2, horn.root.Position + Vector3.new(10, 3, 10))
		task.wait(1)
		check(horn.model:GetAttribute("Blowing") == true or horn.alarmedUntil ~= nil, "hornblower started the alarm")
		task.wait(4)
		local hunting, alarmed, total = 0, 0, 0
		for _, e in ipairs(S.EnemyService.alive()) do
			if e.camp == fortress then
				total += 1
				if e.target == p2 then
					hunting += 1
				end
				if e.alarmedUntil then
					alarmed += 1
				end
			end
		end
		check(hunting > 3, string.format("the whole fortress hunts the dragon after the alarm (%d hunting, %d alarmed, %d alive, horn dead=%s blowing=%s)", hunting, alarmed, total, tostring(horn.dead), tostring(horn.model:GetAttribute("Blowing"))))
		tp(p2, Zones.SPAWN)
		p2:SetAttribute("GodMode", nil)
	end

	step("world boss")
	check(invoke("AdminAction", p1, "bossNow", { seconds = 5 }), "admin boss")
	check(invoke("BossQueue", p1, true), "join boss queue")
	check(invoke("BossQueue", p2, true), "p2 joins boss queue")
	task.wait(8)
	check(S.BossService.isInFight(p1), "in boss fight")
	task.wait(6)
	check(invoke("LeaveBossFight", p1), "leave fight")
	local bossInfo = findEnemy(function(e)
		return e.isBoss
	end)
	check(bossInfo ~= nil, "boss spawned")
	local bossKills = S.PlayerService.getProfile(p2).bossKills
	if bossInfo then
		S.CombatService.damageEnemy(p2, bossInfo, 1e12, false)
	end
	task.wait(12)
	check(S.PlayerService.getProfile(p2).bossKills == bossKills + 1, "boss kill rewarded")

	step("old save migration")
	SIM_SAVES = { Player_103 = {
		version = 1, class = "Shadowstalker", level = 9, xp = 10, gold = 500, talents = {}, inventory = {}, equipped = {},
		seeds = { Emberbloom = 1 }, plotsUnlocked = 6, quests = { active = {}, done = { E1 = 1 } }, glory = 0,
		bossKills = 0, vikingKills = 20, flowersHarvested = 1,
		plots = {
			{ seed = "Emberbloom", stage = 2, progress = 5, health = 70, need = "sun", needLeft = 20, needsDone = 0, nextNeedAt = 10, withered = false },
			{ seed = "Frostpetal", stage = 1, progress = 1, health = 0, need = false, needLeft = 0, needsDone = 0, nextNeedAt = 10, withered = true },
			false, false, false, false, false, false, false, false, false, false,
		},
	} }
	local p3 = addPlayer(103, "Veteran")
	task.wait(3)
	local vet = S.PlayerService.getProfile(p3)
	check(vet ~= nil and vet.tutorial == -1, "veterans skip the tutorial")
	check(vet.plots[1].need == "water" and vet.plots[1].quality == 70 and vet.plots[1].health == nil, "sun need migrated to water")
	check(vet.plots[2].withered == nil and vet.plots[2].quality >= 40, "withered plant revived at low quality")
	check(vet.hunger > Game.HUNGER_MAX - 2 and vet.potions ~= nil and vet.robots.water == false, "new fields added to old save")
	task.wait(60)
	check(vet.plots[2].stage >= 1, "revived plant keeps growing")

	step("death + respawn")
	local _, hum2, deadRoot = S.PlayerService.getCharacter(p1)
	S.SurvivalService.setHunger(p1, 0)
	hum2.Health = 0
	task.wait(0.2)
	check(deadRoot.Anchored, "a fallen dragon lies down where it fell")
	task.wait(Game.RESPAWN_TIME + 1)
	check(rootOf(p1) ~= nil, "respawned")
	check(profile.hunger >= Game.HUNGER_AFTER_DEATH - 1, "respawn hunger floor (" .. profile.hunger .. ")")

	step("paragon + loadout")
	local TalentUtil = require(__proxy("Shared/TalentUtil"))
	local Classes = require(__proxy("Shared/Config/Classes"))
	S.PlayerService.setLevel(p1, Game.LEVEL_CAP)
	profile.talents = {}
	S.PlayerService.recompute(p1)
	local hpBeforeParagon = S.PlayerService.getStats(p1).maxHealth
	S.PlayerService.addXP(p1, Game.paragonXp(0) * 6, true)
	check(profile.paragon >= 5, "XP past the cap fills Paragon levels (" .. profile.paragon .. ")")
	check(TalentUtil.available(profile.level, profile.talents, profile.paragon) == Game.LEVEL_CAP - 1 + math.floor(profile.paragon / Game.PARAGON_POINT_EVERY), "Paragon levels give skill points")
	check(S.PlayerService.getStats(p1).maxHealth > hpBeforeParagon, "Paragon levels add a little health")
	profile.paragon = 200 -- enough points for every branch
	S.PlayerService.recompute(p1)
	for branch = 1, 3 do
		invoke("AutoSpendBranch", p1, branch)
	end
	local signature = Classes.get(profile.class).signature
	local tree = TalentUtil.treeAbilities(S.PlayerService.getStats(p1).abilities, signature)
	check(#tree > TalentUtil.LOADOUT_SLOTS, "more abilities than keys (" .. #tree .. ")")
	check(invoke("SetLoadout", p1, { tree[#tree], tree[1], tree[2], tree[3] }), "set loadout")
	check(TalentUtil.resolveLoadout(S.PlayerService.getStats(p1).abilities, profile.loadout, signature)[1] == tree[#tree], "the chosen ability goes on key 2")

	step("collection + achievements")
	local species = profile.pets[1] and profile.pets[1].species
	check(species ~= nil and profile.petBook[species] ~= nil, "the pet book records hatched pets")
	profile.vikingKills = math.max(profile.vikingKills, 60)
	local goldBefore = profile.gold
	task.wait(4)
	check((profile.achievements.Vikings or 0) >= 1 and profile.gold > goldBefore, "achievement reached and rewarded")
	check(not invoke("SetSkin", p1, "Obsidian"), "locked skins can't be worn")
	profile.skins.Obsidian = true
	check(invoke("SetSkin", p1, "Obsidian") and profile.skin == "Obsidian", "wear a skin")
	task.wait(0.5)
	check(rootOf(p1) ~= nil, "dragon rebuilt in its new skin")
	check(not invoke("SetTitle", p1, "Viking Bane"), "titles have to be earned")
	profile.titles["Viking Bane"] = true
	check(invoke("SetTitle", p1, "Viking Bane"), "wear a title")

	step("store")
	local StoreInfo = require(__proxy("Shared/Config/Store"))
	check(S.StoreService.xpMultiplier(p1) == 1, "no XP pass yet")
	check(invoke("StudioPurchase", p1, "pass", "DoubleXP"), "Studio test purchase of a pass")
	check(S.StoreService.xpMultiplier(p1) == 2, "2x XP is active")
	local stormBefore = profile.eggs.StormEgg or 0
	check(invoke("StudioPurchase", p1, "product", "StarterPack") and profile.starterPack and profile.skins.Sunrise, "starter pack")
	check((profile.eggs.StormEgg or 0) == stormBefore + 2, "starter pack eggs")
	check(not invoke("StudioPurchase", p1, "product", "StarterPack"), "the starter pack is once only")
	-- Gold Rush: +100% gold for 30 minutes of play, counting down only while you're online
	local goldMult = S.StoreService.goldMultiplier(p1)
	check(invoke("StudioPurchase", p1, "product", "GoldRush") and profile.goldRushLeft == 30 * 60, "gold rush bought")
	check(S.StoreService.goldMultiplier(p1) == goldMult + StoreInfo.GOLD_RUSH_BONUS, "gold rush adds +100% gold")
	check(S.PlayerService.snapshot(p1).goldRushEnds ~= nil, "the HUD gets the gold rush countdown")
	local rushLeft = profile.goldRushLeft
	task.wait(11)
	check(profile.goldRushLeft < rushLeft and profile.goldRushLeft > rushLeft - 20, "gold rush counts down while playing")
	invoke("StudioPurchase", p1, "product", "GoldRush")
	check(profile.goldRushLeft > rushLeft, "buying another adds time")
	profile.goldRushLeft = 3
	task.wait(6)
	check(profile.goldRushLeft == 0 and S.StoreService.goldMultiplier(p1) == goldMult, "gold rush ends")
	check(S.PlayerService.snapshot(p1).goldRushEnds == nil, "no countdown once it's over")
	-- a real Roblox receipt: granted once, even if Roblox sends it again
	StoreInfo.Products.GoldSmall.productId = 12345
	local mps = game:GetService("MarketplaceService")
	local receipt = { PlayerId = p1.UserId, ProductId = 12345, PurchaseId = "receipt-1" }
	local gold0 = profile.gold
	check(mps.ProcessReceipt(receipt) == Enum.ProductPurchaseDecision.PurchaseGranted and profile.gold > gold0, "receipt granted")
	local gold1 = profile.gold
	check(mps.ProcessReceipt(receipt) == Enum.ProductPurchaseDecision.PurchaseGranted and profile.gold == gold1, "the same receipt is never granted twice")
	StoreInfo.Products.GoldSmall.productId = 0
	check(invoke("StudioPurchase", p1, "product", "SecretEgg") and profile.eggs.SecretEgg == 1, "secret egg")
	while #profile.pets >= Game.PET_LIMIT do
		table.remove(profile.pets)
	end
	local okSecret, secretPet = invoke("HatchEgg", p1, "SecretEgg")
	check(okSecret and require(__proxy("Shared/Config/Pets")).get(secretPet.species).rarity == "Secret", "the secret egg hatches a Secret pet")
	check(okSecret and secretPet.species ~= "AuroraSerpent", "the Secret Egg never hatches the Mythic Egg's Aurora Serpent")
	-- the Mythic Egg: sold for Robux too, and never hatches below Epic
	local mythicBefore = profile.eggs.MythicEgg or 0
	check(invoke("StudioPurchase", p1, "product", "MythicEgg") and profile.eggs.MythicEgg == mythicBefore + 1, "a Mythic Egg from the Store")
	while #profile.pets >= Game.PET_LIMIT do
		table.remove(profile.pets)
	end
	local okMythicBuy, boughtPet = invoke("HatchEgg", p1, "MythicEgg")
	local boughtRarity = okMythicBuy and require(__proxy("Shared/Config/Pets")).get(boughtPet.species).rarity
	check(boughtRarity == "Epic" or boughtRarity == "Legendary" or boughtRarity == "Secret", "Mythic Eggs hatch Epic or better (" .. tostring(boughtRarity) .. ")")
	-- handy passes: 2x Flight Time, Never Hungry, Wayfinder
	local stamina0 = S.PlayerService.getStats(p1).stamina
	check(invoke("StudioPurchase", p1, "pass", "DoubleFlight"), "2x Flight Time bought")
	check(math.abs(S.PlayerService.getStats(p1).stamina - stamina0 * StoreInfo.FLIGHT_MULT) < 0.01, "2x Flight Time doubles flight stamina")
	check(invoke("StudioPurchase", p1, "pass", "NeverHungry"), "Never Hungry bought")
	profile.hunger = 40
	task.wait(1.5)
	check(profile.hunger == Game.HUNGER_MAX, "Never Hungry keeps you full")
	tp(p1, S.FarmService.getHomeCFrame(p1).Position)
	task.wait(5)
	local okTp, whyTp = invoke("TeleportTo", p1, "square")
	check(not okTp and tostring(whyTp):find("Wayfinder") ~= nil, "teleporting needs the Wayfinder pass")
	check(invoke("StudioPurchase", p1, "pass", "Wayfinder"), "Wayfinder bought")
	local campDrop = Zones.getPlace("camp:RaiderCamp").drop
	check(invoke("TeleportTo", p1, "camp:RaiderCamp"), "Wayfinder teleports to a camp")
	local at = rootOf(p1).Position
	check(Vector3.new(at.X - campDrop.X, 0, at.Z - campDrop.Z).Magnitude < 3, "... to the edge of it (" .. math.floor(at.X) .. ", " .. math.floor(at.Z) .. ")")
	check(not invoke("TeleportTo", p1, "range"), "Wayfinder has a cooldown")
	check(not invoke("TeleportTo", p1, "nowhere"), "unknown places are refused")
	task.wait(StoreInfo.WAYFINDER_COOLDOWN + 1)
	check(invoke("TeleportTo", p1, "range"), "Wayfinder works again after the cooldown")
	tp(p1, S.FarmService.getHomeCFrame(p1).Position)

	step("admin: paragon, pets, collection, store")
	local function admin(action, args)
		args = args or {}
		args.userId = p2.UserId
		local okAdmin, message = invoke("AdminAction", p1, action, args)
		check(okAdmin, "admin " .. action .. ": " .. tostring(message))
		return okAdmin
	end
	local buddy = S.PlayerService.getProfile(p2)
	admin("setParagon", { value = 12 })
	check(buddy.level == Game.LEVEL_CAP and buddy.paragon == 12, "admin sets Paragon (and level 30)")
	admin("addParagon", { amount = 3 })
	check(buddy.paragon == 15, "admin adds Paragon levels")
	local petsBeforeAdmin = #buddy.pets
	admin("pet", { species = "CelestialDrake", golden = true, level = 4 })
	local newPet = buddy.pets[#buddy.pets]
	check(#buddy.pets == petsBeforeAdmin + 1 and newPet.golden and newPet.level == 4, "admin gives a golden level 4 Secret pet")
	admin("treats", { amount = 20 })
	admin("petBook", { mode = "golden" })
	local anyMissing = false
	for id in pairs(require(__proxy("Shared/Config/Pets")).Species) do
		anyMissing = anyMissing or buddy.petBook[id] ~= 2
	end
	check(not anyMissing, "admin fills the pet book")
	admin("skins", { mode = "wear", skin = "Royal" })
	check(buddy.skin == "Royal" and buddy.skins.Royal, "admin puts a skin on")
	admin("titles", { mode = "set", title = "Boss Breaker" })
	check(buddy.title == "Boss Breaker", "admin sets a title")
	admin("achievements", { mode = "reach" })
	check((buddy.achievements.Vikings or 0) == 3, "admin maxes achievements")
	admin("pass", { pass = "DoubleGold", on = true })
	check(S.StoreService.goldMultiplier(p2) == 2, "admin turns on 2x Gold")
	admin("pass", { pass = "DoubleGold", on = false })
	check(S.StoreService.goldMultiplier(p2) == 1, "admin turns 2x Gold off")
	admin("product", { product = "TreatBag" })
	admin("starterReset")
	admin("restockMine")
	admin("clearPets")
	check(#buddy.pets == 0, "admin releases every pet")

	step("day and night")
	local DayNight = require(__proxy("Shared/DayNight"))
	local Raids = require(__proxy("Shared/Config/Raids"))
	local chance = Raids.CHANCE
	Raids.CHANCE = 0 -- no raids by chance in here: the pity rule and the admin still start them
	check(Game.NIGHT_SECONDS < Game.DAY_SECONDS, "nights are shorter than days")
	S.DayNightService.setHour(12)
	local _, noon = DayNight.now()
	check(not S.DayNightService.isNight() and workspace:GetAttribute("Night") == false, "noon is daytime")
	check(math.abs(noon - 12) < 0.1, "the clock reads noon (" .. noon .. ")")
	for n = 1, Raids.PITY_NIGHTS do
		S.DayNightService.setHour(20)
		task.wait(0.6)
		check(workspace:GetAttribute("Night") == true and not S.RaidService.isActive(), "a quiet night " .. n)
		S.DayNightService.setHour(8)
		task.wait(0.6)
	end
	check(S.RaidService.quietNights() == Raids.PITY_NIGHTS, "quiet nights counted (" .. S.RaidService.quietNights() .. ")")
	S.DayNightService.setHour(20)
	task.wait(0.6)
	check(S.RaidService.isActive(), "after " .. Raids.PITY_NIGHTS .. " quiet nights a raid is guaranteed")

	step("night raid: repelled")
	invoke("AdminAction", p1, "god", { on = true })
	invoke("AdminAction", p1, "god", { on = true, userId = 102 })
	check(workspace:GetAttribute("RaidPhase") == "incoming", "longships incoming")
	check(#workspace.RaidShips:GetChildren() == #Raids.Landings, "longships on the river")
	local function passengers()
		return #S.RaidService.aboard()
	end
	check(passengers() > 0, "the raiders ride in on the longships (" .. passengers() .. ")")
	check((workspace:GetAttribute("RaidLeft") or 0) == passengers(), "the vikings on deck count as raiders left (" .. tostring(workspace:GetAttribute("RaidLeft")) .. ")")
	-- the ships row in at full speed and only slow down at the very end
	local rowShip = workspace.RaidShips:GetChildren()[1]
	local rowFrom = rowShip.PrimaryPart.Position.X
	-- the vikings on deck are real raiders: a dragon can fight them on the way in
	local deckOnes = S.RaidService.aboard()
	local onDeck, overboardOne = deckOnes[1], deckOnes[2]
	local hitHard = 0
	local okTargets = false
	for _, t in ipairs(S.CombatService.collectTargets(p1)) do
		if t.enemy == onDeck then
			okTargets = true
		end
	end
	check(okTargets, "a viking on deck is something dragons can hit")
	if onDeck then
		check(onDeck.model:GetAttribute("Shielded") == true, "vikings on deck huddle behind their shields")
		S.CombatService.damageEnemy(p1, onDeck, onDeck.humanoid.MaxHealth * 0.4, false)
		hitHard = onDeck.humanoid.MaxHealth - onDeck.humanoid.Health
		check(math.abs(hitHard - onDeck.humanoid.MaxHealth * 0.4 * Raids.DECK_DAMAGE_TAKEN) <= 1, "...and take less damage there (" .. math.floor(hitHard) .. ")")
	end
	local leftBefore = workspace:GetAttribute("RaidLeft") or 0
	if overboardOne then
		S.CombatService.damageEnemy(p1, overboardOne, 1e9, false)
		task.wait(0.4)
		check(overboardOne.root.Position.Y < workspace.RaidShips:GetChildren()[1].PrimaryPart.Position.Y + 20 and not overboardOne.root:FindFirstChild("ShipWeld"), "a viking beaten on deck tumbles off the ship")
		check((workspace:GetAttribute("RaidLeft") or 0) == leftBefore - 1, "...and counts as beaten")
		task.wait(1.5)
		check(overboardOne.model.Parent == nil, "...and is gone with a splash")
	end
	task.wait(Raids.SHIP_ROW_TIME / 2 - 1.9)
	local rowLanding = Raids.Landings[1]
	local share = (rowShip.PrimaryPart.Position.X - rowFrom) / (rowLanding.shipX - rowLanding.fromX)
	check(share > 0.45 and share < 0.65, "halfway through the row the ships are about halfway there (" .. string.format("%.2f", share) .. ")")
	tp(p1, S.FarmService.getHomeCFrame(p1).Position)
	tp(p2, S.FarmService.getHomeCFrame(p2).Position)
	task.wait(Raids.WARNING - Raids.SHIP_ROW_TIME / 2 + 0.1)
	check(workspace:GetAttribute("RaidPhase") == "fighting" and #S.RaidService.raiders() < (workspace:GetAttribute("RaidLeft") or 0), "they leap ashore one after another")
	local wave1 = workspace:GetAttribute("RaidLeft") or 0
	task.wait(wave1 * Raids.HOP_GAP + Raids.LEAP_TIME + 1)
	check(#S.RaidService.raiders() == wave1 and passengers() == 0, "the whole wave is ashore, nobody left standing on deck (" .. #S.RaidService.raiders() .. "/" .. wave1 .. ", " .. passengers() .. " aboard)")
	if onDeck then
		check(not onDeck.dead and onDeck.humanoid.MaxHealth - onDeck.humanoid.Health >= hitHard * 0.99 and not onDeck.customAI and not onDeck.root.Anchored,
			"a viking hurt on deck lands still hurt, and fights like any raider")
		check(onDeck.model:GetAttribute("Shielded") == nil and onDeck.damageTakenMult == nil, "...without its deck shield")
	end
	local ship1 = workspace.RaidShips:GetChildren()[1]
	local moored = ship1 and ship1.PrimaryPart.Position
	task.wait(3)
	check(ship1 and (ship1.PrimaryPart.Position - moored).Magnitude > 10, "the longships row back out for the next wave")
	check(workspace:GetAttribute("RaidNextWaveAt") ~= nil, "the raid bar knows when the next wave lands")
	task.wait(Raids.SHIP_OUT_TIME)
	check(passengers() > 0, "the next wave climbs aboard upriver")
	local raiders = S.RaidService.raiders()
	check(#raiders > 0 and raiders[1].raid, "raiders in town (" .. #raiders .. ")")
	local r1 = raiders[1]
	tp(p1, r1.root.Position + Vector3.new(10, 5, 0))
	task.wait(0.2)
	check(S.EnemyService.targetRoot(r1, p1) ~= nil, "raiders can fight dragons inside town")
	tp(p1, r1.root.Position + Vector3.new(Raids.CHASE_RANGE + 20, 5, 0))
	task.wait(0.2)
	check(S.EnemyService.targetRoot(r1, p1) == nil, "raiders give up on a dragon that gets away")
	-- a dragon on the beach with every raider nearby: only a few go after it, the rest find others
	tp(p1, Vector3.new(0, 5, 247))
	task.wait(3)
	local onMe = 0
	for _, e in ipairs(S.RaidService.raiders()) do
		local d = e.root.Position - rootOf(p1).Position
		if e.target == p1 and Vector3.new(d.X, 0, d.Z).Magnitude >= 12 then
			onMe += 1
		end
	end
	check(onMe <= Raids.CROWD, "at most " .. Raids.CROWD .. " raiders pile onto one dragon (" .. onMe .. ")")
	local goals = {}
	for _, e in ipairs(S.RaidService.raiders()) do
		if e.goal then
			goals[e.goal.kind] = true
		end
	end
	check(goals.house ~= nil, "torchbearers head for the houses")
	check(goals.villager ~= nil or goals.dragon ~= nil, "fighters pick their own victims")
	tp(p1, S.FarmService.getHomeCFrame(p1).Position)
	-- villagers can be knocked out, and get back up
	local victim = S.CivilianService.villagers()[1]
	for _ = 1, Raids.VILLAGER_HITS do
		S.CivilianService.hurt(victim)
	end
	check(victim.knockedOut and victim.model:GetAttribute("KnockedOut") == true and victim.root.Anchored, "a villager hit enough times is knocked out")
	check(S.RaidService.isActive(), "the raid goes on")
	task.wait(Raids.VILLAGER_KNOCKOUT + 1)
	check(not victim.knockedOut and not victim.root.Anchored, "knocked-out villagers get back up")
	-- a beaten raider topples over before it vanishes
	local faller = S.RaidService.raiders()[1]
	if faller then
		S.CombatService.damageEnemy(p1, faller, 1e9, false)
		task.wait(1)
		check(faller.root.Anchored and faller.root.CFrame.UpVector.Y < 0.5, "a beaten viking falls over (up " .. faller.root.CFrame.UpVector.Y .. ")")
	end
	task.wait(2)
	local defending = 0
	for _, v in ipairs(S.CivilianService.villagers()) do
		if v.defending then
			defending += 1
		end
	end
	check(defending > 0, "villagers come out to fight (" .. defending .. ")")
	-- the quest givers are busy: no quests during a raid
	local someQuest = require(__proxy("Shared/Config/Quests")).List[1].id
	local okQuest, whyQuest = invoke("AcceptQuest", p1, someQuest)
	check(not okQuest and whyQuest == Raids.QUEST_BUSY, "no quests during a raid (" .. tostring(whyQuest) .. ")")
	-- ...because they're breathing fire at raiders who come near their posts
	local elder = nil
	for _, model in ipairs(game:GetService("CollectionService"):GetTagged("QuestGiver")) do
		if model:GetAttribute("GiverId") == "Elder" then
			elder = model
		end
	end
	local near = S.RaidService.raiders()[1]
	if elder and near then
		local look0 = elder:GetPivot().LookVector
		local post = Zones.QuestGivers.Elder.position
		near.root.CFrame = CFrame.new(post + Vector3.new(0, 3, -12))
		local hp = near.humanoid.Health
		task.wait(0.8)
		check(near.dead or near.humanoid.Health < hp, "the Elder breathes fire at a raider near its post")
		check(elder:GetPivot().LookVector:Dot(look0) < 0.999, "the Elder turns to face the raider")
	end
	-- villager fire can't finish a raider fresh off the boat, but can once it's been ashore a while
	local villager = S.CivilianService.villagers()[2]
	local fresh, old = S.RaidService.raiders()[1], S.RaidService.raiders()[2]
	if villager and fresh and old and fresh ~= old then
		fresh.landedAt = workspace:GetServerTimeNow()
		for _ = 1, 60 do
			S.RaidService.villagerPuff(villager, fresh)
		end
		check(not fresh.dead and fresh.humanoid.Health >= fresh.humanoid.MaxHealth * Raids.VILLAGER_FLOOR * 0.95, "villagers alone can't finish a raider fresh off the boat")
		old.landedAt = workspace:GetServerTimeNow() - Raids.VILLAGER_FINISH_AFTER - 1
		check(S.RaidService.villagerFloor(old) == 0, "the floor wears away the longer a raider is ashore")
		for _ = 1, 60 do
			if old.dead then
				break
			end
			S.RaidService.villagerPuff(villager, old)
		end
		check(old.dead, "villagers can finish a raider that's been ashore a while")
	end
	local lit = nil
	for _ = 1, 90 do
		task.wait(1)
		for i = 1, #Zones.Houses do
			if S.RaidService.houseState(i) == "burning" then
				lit = i
			end
		end
		if lit then
			break
		end
	end
	check(lit ~= nil, "a torchbearer walked to a house and set it alight")
	if lit then
		-- dragons breathe fire, so they need water: skim the river, then hover over the fire
		local house = workspace.Map.Town:FindFirstChild("House" .. lit)
		check(house:FindFirstChildWhichIsA("ProximityPrompt", true) == nil, "no \"beat out the flames\" prompt any more")
		local over = Zones.Houses[lit].pos + Vector3.new(4, 30, 0)
		tp(p1, over)
		task.wait(0.5)
		check(S.RaidService.houseState(lit) == "burning" and S.RaidService.douseProgress(lit) == 0, "hovering over a fire without water does nothing")
		tp(p1, Vector3.new(0, Zones.WATER_LEVEL + 3, 280))
		task.wait(0.5)
		check(p1:GetAttribute("Water") == Raids.WATER_LOADS, "skimming the river scoops up water (" .. tostring(p1:GetAttribute("Water")) .. ")")
		check(rootOf(p1):FindFirstChild("WaterDrips") ~= nil, "water drips off a dragon carrying it")
		tp(p2, Zones.Wells[1] + Vector3.new(5, 4, 0))
		task.wait(0.5)
		check(p2:GetAttribute("Water") == Raids.WATER_LOADS, "a dragon at a town well scoops up water")
		-- pouring takes a while: one dragon alone needs Raids.DOUSE_TIME seconds over the fire
		local started = SIM.now
		tp(p1, over)
		task.wait(1.3)
		local soaked = S.RaidService.douseProgress(lit)
		check(S.RaidService.houseState(lit) == "burning" and soaked > 0.15 and soaked < 0.6, "a quick pass isn't enough: the fire is only part soaked (" .. string.format("%.2f", soaked) .. ")")
		local stream = rootOf(p1):FindFirstChild("WaterPour")
		check(p1:GetAttribute("Pouring") == true and stream ~= nil and stream.Enabled, "water pours out of the dragon while it hovers there")
		-- ...and a second dragon pouring on the same house puts it out sooner
		tp(p2, Zones.Houses[lit].pos + Vector3.new(-4, 32, 2))
		for _ = 1, 40 do
			task.wait(0.2)
			if S.RaidService.houseState(lit) ~= "burning" then
				break
			end
		end
		check(S.RaidService.houseState(lit) == "ok", "enough water puts the fire out")
		check(SIM.now - started < Raids.DOUSE_TIME, "two dragons pouring together were quicker than one (" .. string.format("%.1f", SIM.now - started) .. "s)")
		local left1 = p1:GetAttribute("Water") or 0
		check(left1 < Raids.WATER_LOADS and left1 > Raids.WATER_LOADS - 1, "they shared the work: less than one load of water used (" .. string.format("%.2f", left1) .. " left)")
		task.wait(0.3)
		check(not p1:GetAttribute("Pouring") and not (stream and stream.Enabled), "the pouring stops when the fire's out")
		-- the flames die away rather than blinking off, and the steam lingers
		local function flames(): number
			local n = 0
			for _, d in ipairs(house:GetDescendants()) do
				if d:IsA("Fire") and d.Enabled and d:FindFirstAncestor("FireFX") then
					n += 1
				end
			end
			return n
		end
		check(flames() > 0, "the flames are still dying down just after it's put out")
		task.wait(Raids.FLAMES_FADE + 0.5)
		check(flames() == 0 and house:FindFirstChild("FireFX") ~= nil, "...then they're gone and the steam lingers")
		-- a half-soaked fire left alone creeps back
		local other = nil
		for i = 1, #Zones.Houses do
			if not other and i ~= lit and S.RaidService.ignite(i) then
				other = i
			end
		end
		tp(p2, S.FarmService.getHomeCFrame(p2).Position)
		tp(p1, Zones.Houses[other].pos + Vector3.new(0, 30, 0))
		task.wait(1.4)
		local wet = S.RaidService.douseProgress(other)
		tp(p1, S.FarmService.getHomeCFrame(p1).Position)
		task.wait(Raids.REGROW_DELAY + 2)
		check(wet > 0 and S.RaidService.douseProgress(other) < wet - 0.05, "a fire nobody's pouring on creeps back (" .. string.format("%.2f -> %.2f", wet, S.RaidService.douseProgress(other)) .. ")")
		tp(p2, S.FarmService.getHomeCFrame(p2).Position)
	end
	local repelled = profile.raidsRepelled
	local buddyRepelled = S.PlayerService.getProfile(p2).raidsRepelled
	for _ = 1, 150 do
		for _, e in ipairs(S.RaidService.raiders()) do
			S.CombatService.damageEnemy(p1, e, 1e9, false)
		end
		task.wait(1)
		if not S.RaidService.isActive() then
			break
		end
	end
	check(not S.RaidService.isActive() and workspace:GetAttribute("RaidPhase") == nil, "the raid is over")
	check(profile.raidsRepelled == repelled + 1, "the defender got the raid reward")
	check(S.PlayerService.getProfile(p2).raidsRepelled == buddyRepelled + 1, "a dragon who only helped pour water on a fire gets the reward too")
	check(S.ShopService.closedMessage() == nil, "shops stay open after a win")
	task.wait(0.5)
	check(p1:GetAttribute("Water") == nil, "the water's gone when the raid ends")
	task.wait(26)
	check(#workspace.RaidShips:GetChildren() == 0, "the longships rowed away")

	step("night raid: lost")
	S.DayNightService.setHour(19)
	local okRaid, raidMsg = invoke("AdminAction", p1, "raidNow", {})
	check(okRaid, "admin starts a raid: " .. tostring(raidMsg))
	task.wait(Raids.WARNING + 1)
	S.DayNightService.setHour(6.5) -- daybreak
	task.wait(0.6)
	check(S.RaidService.isActive(), "dawn doesn't end a raid: it keeps its own clock")
	local torched = {}
	for i = 1, #Zones.Houses do
		if #torched < Raids.MAX_BURNED and S.RaidService.ignite(i) then
			table.insert(torched, i)
		end
	end
	-- a house burning down caves in rather than turning black all at once
	local ruin = workspace.Map.Town:FindFirstChild("House" .. torched[1])
	local roofPart, roofY = nil, -math.huge
	for _, d in ipairs(ruin:GetDescendants()) do
		if d:IsA("WedgePart") and d.Position.Y > roofY then
			roofPart, roofY = d, d.Position.Y
		end
	end
	local roofColor = roofPart.Color
	-- the carved dragon heads on the ends of the ridge beam
	local heads = {}
	for _, d in ipairs(ruin:GetDescendants()) do
		if d:IsA("BasePart") and d:FindFirstChildOfClass("SpecialMesh") and d.Position.Y > roofY + 4 then
			table.insert(heads, { part = d, y = d.Position.Y })
		end
	end
	local headGap = #heads == 2 and (heads[1].part.Position - heads[2].part.Position).Magnitude or 0
	task.wait(Raids.Tiers[#Raids.Tiers].burnTime + 0.6)
	check(not S.RaidService.isActive(), "the raid is lost when " .. Raids.MAX_BURNED .. " houses burn")
	check(S.RaidService.houseState(torched[1]) == "burned", "burned houses stay burned for a while")
	check(roofPart.Position.Y > roofY - 1, "the roof holds a moment while the flames roar")
	local fled = {}
	for _, e in ipairs(S.EnemyService.alive()) do
		if e.raid and e.retreating then
			table.insert(fled, e)
		end
	end
	check(#fled > 0, "the raiders don't vanish when they win: they run for their ships (" .. #fled .. ")")
	check(fled[1] == nil or fled[1].model:FindFirstChild("LootSack") ~= nil, "...with a sack of loot each")
	task.wait(Raids.COLLAPSE_TIME + 1.5)
	check(roofPart.Position.Y < roofY - 4, "the roof caves in (" .. string.format("%.1f", roofY - roofPart.Position.Y) .. " studs)")
	check(roofPart.Color ~= roofColor, "the walls and roof are charred")
	check(#heads == 2 and math.abs((heads[1].part.Position - heads[2].part.Position).Magnitude - headGap) < 0.05
		and heads[1].part.Position.Y < heads[1].y - 5 and heads[2].part.Position.Y < heads[2].y - 5,
		"the ridge beam comes down in one piece, dragon heads and all (" .. #heads .. " heads)")
	task.wait(Raids.RETREAT_TIME + 30)
	local stillHere = 0
	for _, e in ipairs(S.EnemyService.alive()) do
		if e.raid then
			stillHere += 1
		end
	end
	check(stillHere == 0 and #workspace.RaidShips:GetChildren() == 0, "the raiders sailed off with the loot (" .. stillHere .. " left, " .. #workspace.RaidShips:GetChildren() .. " ships)")
	check(S.ShopService.closedMessage() ~= nil and workspace:GetAttribute("ShopsClosedUntil") ~= nil, "the shops close after a lost raid")
	tp(p1, Zones.getShop("Armory").position + Vector3.new(0, 5, -10))
	task.wait(0.2)
	local okBuy, whyBuy = invoke("BuyItem", p1, 1)
	check(not okBuy and tostring(whyBuy):find("looted") ~= nil, "the Armory won't trade while closed (" .. tostring(whyBuy) .. ")")
	task.wait(math.max(Raids.SHOPS_CLOSED, Raids.REBUILD) + 1)
	check(S.ShopService.closedMessage() == nil and workspace:GetAttribute("ShopsClosedUntil") == nil, "the shops reopen")
	check(S.RaidService.houseState(torched[1]) == "ok", "burned houses are rebuilt")
	check(math.abs(roofPart.Position.Y - roofY) < 0.01 and roofPart.Color == roofColor, "...roof and all")
	step("raids wait for bosses")
	S.DayNightService.setHour(8)
	task.wait(0.6)
	check(invoke("AdminAction", p1, "bossNow", { seconds = 10 }), "a boss warning")
	Raids.CHANCE = 1
	S.DayNightService.setHour(19)
	task.wait(0.6)
	check(not S.RaidService.isActive() and S.RaidService.isPending(), "a raid rolled during a boss warning waits")
	task.wait(14) -- nobody queued, so the boss moves on
	check(S.RaidService.isActive(), "the raid starts once the boss is gone")
	-- a raid that runs out of time is lost (a short clock here: 4 seconds after the last wave)
	local fightTime = Raids.FIGHT_TIME
	Raids.FIGHT_TIME = 4 - Raids.WAVE_GAP * (#Raids.Tiers[1].waves - 1)
	task.wait(Raids.WARNING + 6)
	check(not S.RaidService.isActive() and S.ShopService.closedMessage() ~= nil, "time runs out with raiders in town: the raid is lost")
	Raids.FIGHT_TIME = fightTime
	invoke("AdminAction", p1, "shops", { open = true })
	Raids.CHANCE = chance
	S.DayNightService.setHour(9)
	invoke("AdminAction", p1, "god", { on = false })
	invoke("AdminAction", p1, "god", { on = false, userId = 102 })

	step("target practice")
	local Range = require(__proxy("Shared/Config/Range"))
	local mat = Vector3.new(Zones.Range.matX, 6, Zones.Range.lanes[1])
	tp(p1, mat)
	tp(p2, mat + Vector3.new(0, 0, 4))
	task.wait(0.3)
	check(not invoke("RangeAction", p1, "start", 3), "locked levels can't be started")
	check(invoke("RangeAction", p1, "start", 1), "start level 1 on a mat")
	check(p1:GetAttribute("RangeMode") == "level", "practice mode on")
	check(#S.RangeService.targetsFor(p1) == Range.Levels[1].count, "my targets popped up")
	check(#S.RangeService.targetsFor(p2) == 0, "other dragons can't hit my targets")
	check(not invoke("RangeAction", p2, "start", 1), "a lane is one dragon's at a time")
	local function xpScore()
		return profile.level * 1e9 + (profile.paragon or 0) * 1e6 + profile.xp
	end
	local score0 = xpScore()
	for shot = 1, 60 do
		if not p1:GetAttribute("RangeMode") then
			break
		end
		local targets = S.RangeService.targetsFor(p1) -- (none for a moment when one blast got both)
		if targets[1] then
			fire("CastAbility", p1, "Fireball", targets[1].root.Position, "range" .. shot)
		end
		task.wait(0.7)
	end
	check(profile.rangeLevel == 1, "level 1 cleared (best " .. tostring(profile.rangeLevel) .. ")")
	check(xpScore() > score0, "clearing a level gives XP")
	check(p1:GetAttribute("RangeMode") == nil and #S.RangeService.targetsFor(p1) == 0, "the session ended")
	check(invoke("RangeAction", p1, "afk"), "start AFK practice")
	local score1 = xpScore()
	for shot = 1, 8 do
		local targets = S.RangeService.targetsFor(p1)
		if targets[1] then
			fire("CastAbility", p1, "Fireball", targets[1].root.Position, "afk" .. shot)
		end
		task.wait(0.7)
	end
	check(xpScore() > score1, "AFK practice pays XP for the targets it hits")
	tp(p1, mat + Vector3.new(60, 0, 0))
	task.wait(0.5)
	check(p1:GetAttribute("RangeMode") == nil, "walking off the mat ends practice")

	dungeonScenario(p1, p2, profile)

	step("snapshot + leave")
	local snap = S.PlayerService.snapshot(p1)
	check(snap and snap.garden and snap.pets and snap.isAdmin == true, "snapshot fields")
	task.wait(30)
	p2.Parent = nil
	Players.PlayerRemoving:Fire(p2)
	task.wait(2)
	SIM.done = true
end)

local limit = 2400
while not SIM.done and SIM.now < limit do
	SIM.step(0.1)
end
print(string.format("\nsimulated %.0f seconds", SIM.now))
for _, e in ipairs(SIM.errors) do
	print(string.format("\nERROR (x%d): %s\n%s", e.count, e.msg, e.trace))
end
print(string.format("%d script errors, %d failed checks", #SIM.errors, #failures))
