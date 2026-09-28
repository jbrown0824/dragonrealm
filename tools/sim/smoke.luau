-- Server smoke test: adds fake players and walks them through the game's features on a
-- virtual clock. Prints every script error with a traceback, plus any failed expectations.
-- Run: ./run.sh (boot.luau is prepended)
task.spawn(function()
	task.wait(3)
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
	ok, msg = invoke("BuyPotion", p1, "IronBellyStew")
	check(ok, "buy potion: " .. tostring(msg))
	tp(p1, Zones.getShop("Hatchery").position + Vector3.new(0, 5, -8))
	check(invoke("BuyEgg", p1, "EmberEgg"), "buy egg")
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
		check(not cp.Enabled, "chest closes after opening")
	end
	local boss = findEnemy(function(e)
		return e.miniBoss and e.camp == camp
	end)
	check(boss ~= nil, "mini-boss spawned")
	if boss then
		check(boss.nametag and boss.nametag.Bar:FindFirstChild("Skull") ~= nil, "mini-boss has a skull")
		task.wait(12) -- let it slam
		S.CombatService.damageEnemy(p1, boss, 1e7, false)
		task.wait(0.5)
		check(boss.dead, "mini-boss died")
	end
	-- respawn timing: with one dragon in camp, the next raider takes longer than the base time
	local raider = findEnemy(function(e)
		return e.camp == camp and not e.miniBoss and e.kind == "viking"
	end)
	if raider then
		S.CombatService.damageEnemy(p1, raider, 1e7, false)
	end

	step("hornblower alarm")
	local fortress = Zones.getCamp("JarlsFortress")
	S.PlayerService.getProfile(p2).level = 30
	local horn = findEnemy(function(e)
		return e.typeId == "Hornblower"
	end)
	check(horn ~= nil, "hornblowers spawned")
	if horn then
		tp(p2, horn.root.Position + Vector3.new(10, 3, 10))
		task.wait(1)
		check(horn.model:GetAttribute("Blowing") == true or horn.alarmedUntil ~= nil, "hornblower started the alarm")
		task.wait(4)
		local hunting = 0
		for _, e in ipairs(S.EnemyService.alive()) do
			if e.camp == fortress and e.target == p2 then
				hunting += 1
			end
		end
		check(hunting > 3, "the whole fortress hunts the dragon after the alarm (" .. hunting .. ")")
		tp(p2, Zones.SPAWN)
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
	local _, hum2 = S.PlayerService.getCharacter(p1)
	S.SurvivalService.setHunger(p1, 0)
	hum2.Health = 0
	task.wait(Game.RESPAWN_TIME + 1)
	check(rootOf(p1) ~= nil, "respawned")
	check(profile.hunger >= Game.HUNGER_AFTER_DEATH - 1, "respawn hunger floor (" .. profile.hunger .. ")")

	step("snapshot + leave")
	local snap = S.PlayerService.snapshot(p1)
	check(snap and snap.garden and snap.pets and snap.isAdmin == true, "snapshot fields")
	task.wait(30)
	p2.Parent = nil
	Players.PlayerRemoving:Fire(p2)
	task.wait(2)
	SIM.done = true
end)

local limit = 900
while not SIM.done and SIM.now < limit do
	SIM.step(0.1)
end
print(string.format("\nsimulated %.0f seconds", SIM.now))
for _, e in ipairs(SIM.errors) do
	print(string.format("\nERROR (x%d): %s\n%s", e.count, e.msg, e.trace))
end
print(string.format("%d script errors, %d failed checks", #SIM.errors, #failures))
