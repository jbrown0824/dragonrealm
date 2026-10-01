-- Data-consistency and logic tests for the shared modules.
local Config = Shared.Config
local Game = require(Config.Game)
local Classes = require(Config.Classes)
local Talents = require(Config.Talents)
local Abilities = require(Config.Abilities)
local Items = require(Config.Items)
local Seeds = require(Config.Seeds)
local Enemies = require(Config.Enemies)
local Quests = require(Config.Quests)
local Zones = require(Config.Zones)
local Potions = require(Config.Potions)
local Pets = require(Config.Pets)
local Animals = require(Config.Animals)
local Food = require(Config.Food)
local Civilians = require(Config.Civilians)
local Collections = require(Config.Collections)
local Skins = require(Config.Skins)
local StoreInfo = require(Config.Store)
local Shops = require(Config.Shops)
local Raids = require(Config.Raids)
local Range = require(Config.Range)
local DayNight = require(Shared.DayNight)
local RangeUtil = require(Shared.RangeUtil)
local StatCalc = require(Shared.StatCalc)
local BonusUtil = require(Shared.BonusUtil)
local Tuning = require(Shared.Tuning)
local ItemUtil = require(Shared.ItemUtil)
local TalentUtil = require(Shared.TalentUtil)
local QuestUtil = require(Shared.QuestUtil)
local Util = require(Shared.Util)

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end
local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

---------------------------------------------------------------- talents
for _, classId in ipairs(Classes.Order) do
	local class = Classes.get(classId)
	check(class ~= nil, "class " .. classId)
	local branches = Talents[classId]
	check(branches and #branches == 3, classId .. " has 3 branches")
	local totalRanks = 0
	for bi, branch in ipairs(branches) do
		local ranks = 0
		local keys = {}
		for _, t in ipairs(branch.talents) do
			keys[t.key] = t
		end
		local perTier = {}
		for _, t in ipairs(branch.talents) do
			ranks += t.maxRank
			perTier[t.tier] = (perTier[t.tier] or 0) + 1
			check(t.tier >= 1 and t.tier <= 5, t.id .. " tier")
			check(t.col == 1 or t.col == 2 or t.col == 1.5, t.id .. " col")
			for stat, v in pairs(t.effects) do
				check(StatCalc.STAT_INFO[stat] ~= nil, t.id .. " unknown stat " .. stat)
				check(finite(v), t.id .. " effect value")
			end
			if t.ability then
				check(Abilities.get(t.ability) ~= nil, t.id .. " ability " .. t.ability)
				check(t.maxRank == 1, t.id .. " ability talent should be 1 rank")
			end
			if t.mods then
				for abilityId, mod in pairs(t.mods) do
					check(Abilities.get(abilityId) ~= nil, t.id .. " mod ability " .. abilityId)
					for k in pairs(mod) do
						check(({ dmgPct = 1, cdFlat = 1, radiusPct = 1, durFlat = 1, stunFlat = 1, healPct = 1 })[k] ~= nil, t.id .. " mod key " .. k)
					end
				end
			end
			if t.requires then
				local req = keys[t.requires]
				check(req ~= nil, t.id .. " requires missing " .. t.requires)
				check(req and req.tier < t.tier, t.id .. " requires lower tier")
			end
			local d = TalentUtil.describe(t, 1)
			check(type(d) == "string" and #d > 0, t.id .. " description")
		end
		check(ranks == 21, string.format("%s branch %d ranks=%d", classId, bi, ranks))
		check(perTier[5] == 1, classId .. " branch " .. bi .. " has one capstone")
		totalRanks += ranks
	end
	-- no duplicate grid positions
	for bi, branch in ipairs(branches) do
		local seen = {}
		for _, t in ipairs(branch.talents) do
			local k = t.tier .. ":" .. t.col
			check(not seen[k], classId .. " branch " .. bi .. " duplicate slot " .. k)
			seen[k] = true
		end
	end
end

---------------------------------------------------------------- abilities
for id, a in pairs(Abilities) do
	if type(a) == "table" and a.id then
		check(a.id == id, "ability id mismatch " .. id)
		check(a.icon and a.name and a.desc, id .. " has icon/name/desc")
		local k = a.kind
		if k == "projectile" then
			check(a.speed and a.range and a.radius and a.mult and a.cooldown, id .. " projectile fields")
		elseif k == "strike" then
			check(a.radius and a.delay and a.castRange and a.mult and a.cooldown, id .. " strike fields")
		elseif k == "nova" then
			check(a.radius and a.mult and a.cooldown, id .. " nova fields")
		elseif k == "dash" then
			check(a.distance and a.width and a.mult and a.cooldown, id .. " dash fields")
		elseif k == "buff" then
			check(a.duration and a.cooldown, id .. " buff fields")
			if a.stats then
				for s in pairs(a.stats) do
					check(StatCalc.STAT_INFO[s] ~= nil, id .. " buff stat " .. s)
				end
			end
		elseif k == "heal" then
			check(a.healPct and a.cooldown, id .. " heal fields")
		elseif k ~= "breath" then
			check(false, id .. " unknown kind " .. tostring(k))
		end
	end
end
-- every non-basic ability is unlocked by exactly one talent
local unlockedBy = {}
for _, t in pairs(Talents.byId) do
	if t.ability then
		unlockedBy[t.ability] = (unlockedBy[t.ability] or 0) + 1
	end
end
local signatures = {}
for _, classId in ipairs(Classes.Order) do
	local sig = Classes.get(classId).signature
	check(sig and Abilities.get(sig) and Abilities.get(sig).signature, classId .. " has a signature ability")
	check(sig and not signatures[sig], classId .. " signature is unique")
	signatures[sig or ""] = true
	local low = StatCalc.compute(classId, Game.SIGNATURE_LEVEL - 1, {}, {}, {})
	local high = StatCalc.compute(classId, Game.SIGNATURE_LEVEL, {}, {}, {})
	check(#low.abilities == 2 and high.abilities[3] == sig, classId .. " signature unlocks at level " .. Game.SIGNATURE_LEVEL)
end
for id, a in pairs(Abilities) do
	if type(a) == "table" and a.id and id ~= "Breath" and id ~= "Fireball" and not signatures[id] then
		check(unlockedBy[id] == 1, id .. " unlocked by " .. tostring(unlockedBy[id]) .. " talents")
	end
end

---------------------------------------------------------------- stats + talent spending simulation
local function gearAt(level, rarity)
	local eq = {}
	for _, slot in ipairs(Items.Slots) do
		eq[slot] = ItemUtil.new(slot, level, rarity)
	end
	return eq
end

for _, classId in ipairs(Classes.Order) do
	local talents = {}
	-- Greedy: fill branch 1 top to bottom (capstone), then branch 2.
	for level = 2, Game.LEVEL_CAP do
		local learned = false
		for bi = 1, 3 do
			for _, t in ipairs(Talents[classId][bi].talents) do
				if not learned and TalentUtil.canLearn(classId, level, talents, t.id) then
					talents[t.id] = (talents[t.id] or 0) + 1
					learned = true
				end
			end
		end
		check(learned, classId .. " could spend a point at level " .. level)
	end
	check(TalentUtil.available(Game.LEVEL_CAP, talents) == 0, classId .. " spent all points")
	local capstones = 0
	for id, r in pairs(talents) do
		if Talents.byId[id].tier == 5 and r > 0 then
			capstones += 1
		end
	end
	check(capstones == 1, classId .. " exactly one capstone reachable (got " .. capstones .. ")")
	-- can't spend when no points
	local ok = TalentUtil.canLearn(classId, Game.LEVEL_CAP, talents, Talents[classId][3].talents[1].id)
	check(not ok, classId .. " cannot overspend")

	for _, level in ipairs({ 1, 10, 20, 30 }) do
		local s = StatCalc.compute(classId, level, gearAt(level, "Rare"), level == 30 and talents or {}, { { stats = { attackPct = 10 } } })
		for _, k in ipairs({ "maxHealth", "attack", "defense", "speed", "stamina", "critChance", "critDamage" }) do
			check(finite(s[k]) and s[k] >= 0, classId .. " stat " .. k .. " at " .. level)
		end
		for _, abilityId in ipairs(s.abilities) do
			local a = StatCalc.resolveAbility(abilityId, classId, s)
			check(a and finite(a.cooldown) and a.cooldown > 0, classId .. " resolve " .. abilityId)
			check(finite(a.damageMult or 0), classId .. " dmgMult " .. abilityId)
		end
		check(finite(StatCalc.power(s)), classId .. " power")
	end
end

-- auto-fill spends every point down one branch, respecting tiers
for _, classId in ipairs(Classes.Order) do
	for bi = 1, 3 do
		local talents = {}
		local learned = TalentUtil.autoFill(classId, Game.LEVEL_CAP, talents, bi)
		local branchRanks = 0
		for _, t in ipairs(Talents[classId][bi].talents) do
			branchRanks += t.maxRank
		end
		check(learned == math.min(branchRanks, TalentUtil.totalPoints(Game.LEVEL_CAP)), classId .. " auto-fill branch " .. bi .. " spent " .. learned)
		check(TalentUtil.spentInBranch(talents, classId, bi) == learned, classId .. " auto-fill stays in branch " .. bi)
		local capstone = false
		for id in pairs(talents) do
			capstone = capstone or Talents.byId[id].tier == 5
		end
		check(capstone, classId .. " auto-fill reaches the capstone in branch " .. bi)
	end
	local few = {}
	check(TalentUtil.autoFill(classId, 4, few, 1) == 3, classId .. " auto-fill at level 4 spends 3")
end

---------------------------------------------------------------- items
for _, slot in ipairs(Items.Slots) do
	for _, rarity in ipairs(Items.RarityOrder) do
		for _, ilvl in ipairs({ 1, 8, 16, 24, 30, 32 }) do
			local item = ItemUtil.new(slot, ilvl, rarity)
			local s = ItemUtil.getStats(item)
			check(next(s) ~= nil, "item stats " .. slot .. rarity)
			check(#ItemUtil.displayName(item) > 3, "item name")
			check(ItemUtil.sellPrice(item) > 0 and ItemUtil.buyPrice(item) > ItemUtil.sellPrice(item), "prices " .. slot .. rarity .. ilvl)
			local c1 = ItemUtil.upgradeCost(item)
			item.up = 5
			check(ItemUtil.upgradeCost(item) > c1, "upgrade cost grows")
		end
	end
end
for id, u in pairs(Items.Uniques) do
	check(table.find(Items.Slots, u.slot) ~= nil, "unique slot " .. id)
	local item = ItemUtil.new(u.slot, 30, "Legendary", id)
	check(ItemUtil.displayName(item) == u.name, "unique name " .. id)
end

---------------------------------------------------------------- enemies & bosses
for id, b in pairs(Enemies.Bosses) do
	check(table.find(Enemies.BossOrder, id) ~= nil, "boss in order " .. id)
	for name, cfg in pairs(b.attacks) do
		check(({ Cleave = 1, AxeVolley = 1, GroundSlam = 1, RuneStrikes = 1, Summon = 1 })[name] ~= nil, id .. " attack " .. name)
		if name == "Summon" then
			check(Enemies.Vikings[cfg.add] ~= nil, id .. " summon type")
		else
			check(cfg.cooldown ~= nil, id .. " " .. name .. " cooldown")
		end
	end
	for _, u in ipairs(b.uniques) do
		check(Items.Uniques[u] ~= nil, id .. " unique " .. u)
	end
end

---------------------------------------------------------------- quests
local zoneIds = {}
for _, a in ipairs(Zones.Areas) do
	zoneIds[a.id] = true
end
local validTypes = { kill = 1, plant = 1, care = 1, harvest = 1, buy = 1, sell = 1, upgrade = 1, pvpKill = 1, bossJoin = 1, bossKill = 1, visitZone = 1, level = 1,
	hunt = 1, fish = 1, eat = 1, openChest = 1, miniBoss = 1, hatch = 1, potion = 1, dungeonClear = 1, dungeonKill = 1 }
for _, q in ipairs(Quests.List) do
	check(Quests.Givers[q.giver] ~= nil, q.id .. " giver")
	check(validTypes[q.objective.type] ~= nil, q.id .. " objective type")
	check(q.objective.count and q.objective.count > 0, q.id .. " count")
	if q.after then
		check(Quests.byId[q.after] ~= nil, q.id .. " after")
		check(Quests.byId[q.after].giver == q.giver, q.id .. " chain stays with same giver")
	end
	local t = q.objective.target
	if q.objective.type == "kill" then
		check(t == "any" or Enemies.Vikings[t] ~= nil, q.id .. " kill target")
	elseif q.objective.type == "visitZone" then
		check(zoneIds[t] ~= nil, q.id .. " zone target")
	elseif q.objective.type == "harvest" then
		check(t == "Flower" or t == "any", q.id .. " harvest target")
	elseif q.objective.type == "hunt" then
		check(t == "any" or Animals.get(t) ~= nil, q.id .. " hunt target")
	end
	for eggId in pairs(q.rewards.eggs or {}) do
		check(Pets.Eggs[eggId] ~= nil, q.id .. " egg reward " .. eggId)
	end
	for seedId in pairs(q.rewards.seeds or {}) do
		check(Seeds.get(seedId) ~= nil, q.id .. " seed reward " .. seedId)
	end
	if q.rewards.gear then
		check(Items.Rarities[q.rewards.gear.rarity] ~= nil, q.id .. " gear rarity")
	end
end
-- a brand-new player sees first quests from every giver in town (the dungeon keepers wait for
-- their dungeon's level)
local fresh = { active = {}, done = {} }
for _, g in ipairs(Quests.GiverOrder) do
	local offer = QuestUtil.nextOffer(g, fresh, Quests.Givers[g].dungeon and 30 or 1)
	check(offer ~= nil, "giver " .. g .. " has a first offer")
end
-- walk the Elder chain
local state = { active = {}, done = {} }
local steps = 0
while true do
	local offer = QuestUtil.nextOffer("Elder", state, 30)
	if not offer or steps > 20 then
		break
	end
	state.active[offer.id] = offer.objective.count
	check(QuestUtil.isComplete(offer.id, state), "complete " .. offer.id)
	check(QuestUtil.giverState("Elder", state, 30) == "turnin", "turnin state " .. offer.id)
	state.active[offer.id] = nil
	state.done[offer.id] = 1
	steps += 1
end
check(steps == 9, "Elder chain has 9 steps (" .. steps .. ")")

---------------------------------------------------------------- zones
local function areaId(pos)
	local a = Zones.areaAt(pos)
	return a and a.id or "nil"
end
check(areaId(Zones.SPAWN) == "Town", "spawn in town")
check(areaId(Vector3.new(0, 5, -265)) == "BattleZone", "battle zone center")
for _, camp in ipairs(Zones.Camps) do
	check(areaId(camp.center) == camp.id, "camp area " .. camp.id .. " got " .. areaId(camp.center))
	check(Zones.inWorld(camp.center), "camp in world " .. camp.id)
end
for _, shop in ipairs(Zones.Shops) do
	check(areaId(shop.position) == "Town", "shop in town " .. shop.id)
end
for id, g in pairs(Zones.QuestGivers) do
	if Quests.Givers[id].dungeon then
		check(areaId(g.position) ~= "Town", "dungeon keeper out by its cave " .. id)
	else
		check(areaId(g.position) == "Town", "giver in town " .. id)
	end
end
check(areaId(Zones.WarHorn) == "Town", "war horn in town")
local bz = Zones.getArea("BattleZone")
for _, b in ipairs(Zones.Bases) do
	check(areaId(b.center) == "Town", "base in town " .. b.index)
	-- base footprint (BaseSize.Z wide across the facing, BaseSize.X deep along it)
	local depthHalf, widthHalf = Zones.BaseSize.X / 2, Zones.BaseSize.Z / 2
	local halfX = math.abs(b.facing.X) > 0.5 and depthHalf or widthHalf
	local halfZ = math.abs(b.facing.X) > 0.5 and widthHalf or depthHalf
	local overlapBZ = b.center.X + halfX > bz.min.X and b.center.X - halfX < bz.max.X and b.center.Z + halfZ > bz.min.Z and b.center.Z - halfZ < bz.max.Z
	check(not overlapBZ, "base " .. b.index .. " overlaps battle zone")
	for _, o in ipairs(Zones.Bases) do
		if o.index > b.index then
			local sep = math.abs(b.center.X - o.center.X) >= halfX * 2 or math.abs(b.center.Z - o.center.Z) >= halfZ * 2
			check(sep, "bases " .. b.index .. "/" .. o.index .. " overlap")
		end
	end
end
check(not Zones.inWorld(Zones.BossArena.center), "boss arena outside main world bounds")
local town = Zones.getArea("Town")
for _, b in ipairs(Zones.Bases) do
	-- the base's front edge must stay off the ring road (x = +-140, 12 wide)
	local front = math.abs(b.center.X) - Zones.BaseSize.X / 2
	check(front >= 146, "base " .. b.index .. " front edge on the road: " .. front)
end
for _, area in ipairs(Zones.HuntingGrounds) do
	check(Zones.areaAt((area.min + area.max) / 2).id == area.id, "hunting ground area " .. area.id)
	check(Zones.inWorld(area.min) and Zones.inWorld(area.max), "hunting ground in world " .. area.id)
	local overlapTown = area.max.X > town.min.X and area.min.X < town.max.X and area.max.Z > town.min.Z and area.min.Z < town.max.Z
	check(not overlapTown, "hunting ground overlaps town " .. area.id)
	for _, camp in ipairs(Zones.Camps) do
		local cx = math.clamp(camp.center.X, area.min.X, area.max.X)
		local cz = math.clamp(camp.center.Z, area.min.Z, area.max.Z)
		check(math.sqrt((cx - camp.center.X) ^ 2 + (cz - camp.center.Z) ^ 2) > camp.radius, area.id .. " overlaps camp " .. camp.id)
	end
	for typeId, n in pairs(area.spawns) do
		check(Animals.get(typeId) ~= nil and n > 0, area.id .. " spawn " .. typeId)
	end
	check(area.levels[1] <= area.levels[2], area.id .. " levels")
end
for _, camp in ipairs(Zones.Camps) do
	check(camp.chest and camp.chest.hold > 0, camp.id .. " chest")
	check(camp.boss and camp.boss.Magnitude < camp.radius, camp.id .. " mini-boss spot inside camp")
	local mb = Enemies.MiniBosses[camp.id]
	check(mb ~= nil and Enemies.Vikings[mb.base] ~= nil, camp.id .. " mini-boss")
	check(mb and mb.slam and mb.slam.radius > 0 and mb.respawn > 30, camp.id .. " mini-boss slam/respawn")
	check(camp.name ~= nil, camp.id .. " name")
	for typeId in pairs(camp.spawns) do
		check(Enemies.Vikings[typeId] ~= nil, camp.id .. " viking " .. typeId)
	end
end
check(Zones.getCamp("JarlsFortress").alarm == true and (Zones.getCamp("JarlsFortress").spawns.Hornblower or 0) > 0, "fortress has hornblowers + alarm")
for _, spot in ipairs(Zones.FishingSpots) do
	check(Food.FishTables[spot.kind] ~= nil and Food.FishingDifficulty[spot.kind] ~= nil, "fishing spot kind " .. spot.id)
	check(Zones.inWorld(spot.pos), "fishing spot in world " .. spot.id)
end
for _, lake in ipairs(Zones.Lakes) do
	check(#lake.lobes > 0 and Zones.inWorld(lake.center), "lake " .. lake.id)
	for _, lobe in ipairs(lake.lobes) do
		check(lobe[3] > 0 and lobe[4] > 0, lake.id .. " lobe size")
	end
end
for _, shop in ipairs(Zones.Shops) do
	check((shop.tab ~= nil) ~= (shop.panel ~= nil), "shop has a tab or a panel " .. shop.id)
end
check(Zones.getShop("Alchemist") ~= nil and Zones.getShop("Hatchery") ~= nil, "new shops")

---------------------------------------------------------------- potions, pets, animals, food
for _, id in ipairs(Potions.Order) do
	local potion = Potions.get(id)
	check(potion ~= nil, "potion " .. id)
	for stat, v in pairs(potion.stats) do
		check(StatCalc.STAT_INFO[stat] ~= nil and finite(v), id .. " potion stat " .. stat)
	end
	local last = 0
	for rank = 0, Potions.maxRank() - 1 do
		local cost = Potions.cost(id, rank)
		check(cost ~= nil and cost > last, id .. " cost grows at rank " .. rank)
		last = cost or last
	end
	check(Potions.cost(id, Potions.maxRank()) == nil, id .. " maxes out")
end
for id, sp in pairs(Pets.Species) do
	check(Classes.get(sp.plan) ~= nil, id .. " pet plan")
	check(Pets.RarityColors[sp.rarity] ~= nil, id .. " pet rarity")
	for stat in pairs(sp.stats) do
		check(StatCalc.STAT_INFO[stat] ~= nil, id .. " pet stat " .. stat)
	end
	for _, key in ipairs({ "primary", "secondary", "belly", "accent", "eyes", "wing", "horn" }) do
		check(sp.look.colors[key] ~= nil, id .. " pet color " .. key)
	end
end
for _, eggId in ipairs(Pets.EggOrder) do
	local egg = Pets.Eggs[eggId]
	for rarity, w in pairs(egg.weights) do
		check(w > 0 and #Pets.speciesFor(eggId, rarity) > 0, eggId .. " has " .. rarity .. " species")
	end
end
check(Game.petSlots(1) == 1 and Game.petSlots(10) == 2 and Game.petSlots(30) == 3, "pet slots by level")
for id, a in pairs(Animals) do
	if type(a) == "table" and a.id then
		check(Food.get(a.meat) ~= nil, id .. " meat")
		check(({ flee = 1, neutral = 1, aggressive = 1 })[a.behavior] ~= nil, id .. " behavior")
		check(a.look.bodyL and a.look.legLen and a.look.headL, id .. " look")
		check(a.behavior == "flee" or (a.attackRange and a.attackCooldown and a.damage > 0), id .. " can fight")
	end
end
for kind, tbl in pairs(Food.FishTables) do
	for fishId in pairs(tbl) do
		check(Food.get(fishId) ~= nil and Food.get(fishId).kind == "fish", kind .. " fish " .. fishId)
	end
end
for _, id in ipairs(Food.Order) do
	check(Food.get(id) ~= nil and Food.get(id).food > 0 and Food.get(id).sell > 0, "food " .. id)
end
for _, seedId in ipairs(Seeds.Order) do
	check(Seeds[seedId].sunBias == nil, seedId .. " has no sun needs any more")
end

---------------------------------------------------------------- hunger, bonuses, respawns, tuning
check(Game.hungerLevel(Game.HUNGER_MAX) == nil, "full = not hungry")
check(Game.hungerLevel(5) and Game.hungerLevel(5).id == "Starving", "starving")
check(Game.hungerLevel(20) and Game.hungerLevel(20).id == "Hungry", "hungry")
for i = 2, #Game.CAMP_RESPAWN_MULT do
	check(Game.CAMP_RESPAWN_MULT[i] <= Game.CAMP_RESPAWN_MULT[i - 1], "respawn multiplier shrinks with more dragons")
end
check(Game.campRespawnMult(1) > Game.campRespawnMult(4) and Game.campRespawnMult(0) == 1, "respawn multiplier values")
check(Game.transformCost(1) == 0 and Game.transformCost(20) == 50, "transform cost")
do
	local profile = { level = 15, hunger = 5, potions = { WingTonic = 2, IronBellyStew = 5 }, pets = { { uid = "a", species = "EmberKit" }, { uid = "b", species = "SparkSprite" }, { uid = "c", species = "VoidWhelp" } }, petsEquipped = { "a", "b", "c" } }
	check(#BonusUtil.activePets(profile) == 2, "only 2 pets follow at level 15")
	local s = StatCalc.compute("Stormwing", 15, {}, {}, BonusUtil.entries(profile))
	local fed = StatCalc.compute("Stormwing", 15, {}, {}, BonusUtil.entries({ level = 15, hunger = 90, potions = profile.potions, pets = profile.pets, petsEquipped = profile.petsEquipped }))
	check(s.attack < fed.attack, "starving lowers attack")
	check(fed.hungerPct == 50, "iron belly stew slows hunger (" .. tostring(fed.hungerPct) .. ")")
	check(fed.flightSpeedPct == 0 and s.flightSpeedPct < 0, "hunger slows flight")
	check(fed.staminaPct == 24, "wing tonic x2 = +24% stamina")
end
do
	local stats = StatCalc.compute("Behemoth", 20, {}, {}, {})
	local before = StatCalc.resolveAbility("Fireball", "Behemoth", stats)
	Tuning.apply({ abilities = { Fireball = { dmg = 2, cd = 0.5 } }, talents = { ["Behemoth.ThickHide"] = 2 } })
	local after = StatCalc.resolveAbility("Fireball", "Behemoth", stats)
	check(math.abs(after.damageMult - before.damageMult * 2) < 1e-6, "tuning doubles fireball damage")
	check(after.cooldown < before.cooldown, "tuning shortens fireball cooldown")
	local tuned = StatCalc.compute("Behemoth", 20, {}, { ["Behemoth.ThickHide"] = 3 }, {})
	check(tuned.defensePct == 8 * 3 * 2, "tuning scales skill values (" .. tostring(tuned.defensePct) .. ")")
	Tuning.reset()
	check(Tuning.isDefault(), "tuning reset")
end

---------------------------------------------------------------- every ability has its own icon
do
	local seen = {}
	for id, ability in pairs(Abilities) do
		if type(ability) == "table" and ability.icon then
			check(seen[ability.icon] == nil, string.format("icon %s used by both %s and %s", ability.icon, tostring(seen[ability.icon]), id))
			seen[ability.icon] = id
		end
	end
end

---------------------------------------------------------------- pet levels, golden merges, treats
check(#Pets.LEVEL_COSTS == Pets.MAX_LEVEL - 1, "a treat cost for every pet level-up")
check(math.abs(Pets.multiplier(Pets.MAX_LEVEL, false) - 2) < 1e-6, "a max-level pet has double boosts")
check(Pets.multiplier(1, true) == Pets.GOLDEN_MULT, "golden multiplies boosts")
for _, rarity in ipairs(Pets.RarityOrder) do
	check(Pets.MergeGold[rarity] ~= nil, "merge cost for " .. rarity)
end
do
	local speciesId = next(Pets.Species)
	local plain = { uid = "a", species = speciesId }
	local grown = { uid = "b", species = speciesId, level = 3, golden = true }
	check(BonusUtil.petScore(grown) > BonusUtil.petScore(plain), "levelled golden pets rank higher")
	local profile = { level = 30, pets = { plain, grown }, petsEquipped = { "b" } }
	local stats = BonusUtil.petStats(profile)
	for stat, v in pairs(Pets.get(speciesId).stats) do
		check(math.abs((stats[stat] or 0) - v * Pets.multiplier(3, true)) < 1e-6, "equipped pet boosts scale with level + golden: " .. stat)
	end
end
for _, id in ipairs(Seeds.Order) do
	local t = Seeds[id].treats
	check(t ~= nil and t[1] > 0 and t[1] <= 1 and t[2] >= 1 and t[3] >= t[2], "treat drops for " .. id)
end

---------------------------------------------------------------- village dragons
do
	local W = Zones.TownWalk
	check(#W.houseLinks == #Zones.Houses, "every house door joins the walking graph")
	for _, e in ipairs(W.edges) do
		check(W.nodes[e[1]] ~= nil and W.nodes[e[2]] ~= nil, "walk edge nodes exist: " .. e[1] .. "-" .. e[2])
	end
	for _, link in ipairs(W.houseLinks) do
		check(W.nodes[link] ~= nil, "house link node exists: " .. link)
	end
	-- the graph is connected
	local seen, queue = { PN = true }, { "PN" }
	while #queue > 0 do
		local n = table.remove(queue)
		for _, e in ipairs(W.edges) do
			local other = (e[1] == n and e[2]) or (e[2] == n and e[1]) or nil
			if other and not seen[other] then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	for name in pairs(W.nodes) do
		check(seen[name], "walk node reachable: " .. name)
	end
	local ids = {}
	for _, c in ipairs(Civilians.List) do
		check(not ids[c.id], "unique villager id " .. c.id)
		ids[c.id] = true
		check(Classes.get(c.plan) ~= nil, "villager body plan exists: " .. c.plan)
		check(Zones.Houses[c.home] ~= nil, "villager home exists: " .. c.name)
		check(#c.lines >= 1, "villager has something to say: " .. c.name)
		check(c.scale > 0.2 and c.scale < 1, "villagers are smaller than players: " .. c.name)
		check(Civilians.RaidSpeed[c.age or ""] ~= nil, "villager has an age with a raid speed: " .. c.name)
	end
	-- during a raid they hurry at different paces, so they don't arrive in one clump
	local speeds = Civilians.RaidSpeed
	check(speeds.young > speeds.adult and speeds.adult > speeds.old and speeds.old >= Civilians.WALK_SPEED, "raid speeds: youngsters run, grown-ups jog, old-timers walk")
	local ages = {}
	for _, c in ipairs(Civilians.List) do
		ages[c.age] = true
	end
	check(ages.young and ages.adult and ages.old, "the village has young, grown-up and old dragons")
	local town = Zones.getArea("Town")
	for name, pos in pairs(W.nodes) do
		check(town == nil or Zones.areaAt(pos) == town, "walk node is in town: " .. name)
	end
end

---------------------------------------------------------------- collections, skins, store, shops
do
	local function checkReward(reward, where)
		for eggId in pairs(reward.eggs or {}) do
			check(Pets.Eggs[eggId] ~= nil, where .. ": egg " .. eggId .. " exists")
		end
		if reward.skin then
			check(Skins.get(reward.skin) ~= nil, where .. ": skin " .. reward.skin .. " exists")
		end
	end
	for i, m in ipairs(Collections.PetMilestones) do
		checkReward(m.reward, "milestone " .. i)
	end
	for _, a in ipairs(Collections.Achievements) do
		check(#a.tiers == 3, a.id .. " has three tiers")
		for t = 2, #a.tiers do
			check(a.tiers[t].count > a.tiers[t - 1].count, a.id .. " tiers go up")
		end
		for t, tier in ipairs(a.tiers) do
			checkReward(tier.reward, a.id .. " tier " .. t)
		end
	end
	for _, id in ipairs(Skins.Order) do
		local skin = Skins.get(id)
		check(skin ~= nil, "skin in order exists: " .. id)
		if skin and skin.colors then
			for _, key in ipairs({ "primary", "secondary", "belly", "accent", "eyes", "wing", "horn" }) do
				check(skin.colors[key] ~= nil, id .. " skin has " .. key)
			end
		end
	end
	-- every skin except Classic can be earned somewhere (achievements, pet book or the store)
	local earnable = { Classic = true }
	for _, m in ipairs(Collections.PetMilestones) do
		earnable[m.reward.skin or ""] = true
	end
	for _, a in ipairs(Collections.Achievements) do
		for _, tier in ipairs(a.tiers) do
			earnable[tier.reward.skin or ""] = true
		end
	end
	for _, product in pairs(StoreInfo.Products) do
		earnable[product.skin or ""] = true
	end
	for _, id in ipairs(Skins.Order) do
		check(earnable[id], "skin " .. id .. " can be unlocked")
	end
	for _, key in ipairs(StoreInfo.ProductOrder) do
		local product = StoreInfo.Products[key]
		check(product ~= nil and product.robux > 0, "store product " .. key)
		for eggId in pairs(product and product.eggs or {}) do
			check(Pets.Eggs[eggId] ~= nil, key .. " egg exists")
		end
	end
	-- paid random items: anything that gives eggs, gold, more gold or egg stock is flagged, and the
	-- restricted regions' Starter Pack is one fixed pet that can't be turned into gold
	for key, product in pairs(StoreInfo.Products) do
		local random = product.eggs ~= nil or product.goldMinutes ~= nil or product.goldRushMinutes ~= nil or product.restock == true or product.epicGear == true
		check(not random or product.paidRandom == true, key .. " gives eggs or gold, so it's paidRandom")
		check(not (product.paidRandom and product.restrictedOnly), key .. " isn't both paidRandom and restrictedOnly")
		if product.pet then
			local species = Pets.get(product.pet.species)
			check(species ~= nil and (species.stats.goldPct or 0) == 0, key .. "'s pet exists and gives no gold")
			check(not product.paidRandom and product.restrictedOnly == true and product.once == true, key .. " is the restricted regions' Starter Pack")
			check(Pets.releaseGold({ species = product.pet.species, bought = true }) == 0 and Pets.releaseGold({ species = product.pet.species }) > 0, "a bought pet releases for no gold")
		end
	end
	check(StoreInfo.Passes.DoubleGold.paidRandom == true, "2x Gold is paidRandom")
	check(StoreInfo.offered("product", "MythicEgg", true) and not StoreInfo.offered("product", "MythicEgg", false) and not StoreInfo.offered("product", "MythicEgg", nil), "paidRandom items only where allowed")
	check(StoreInfo.offered("product", "StarterPet", false) and not StoreInfo.offered("product", "StarterPet", true) and not StoreInfo.offered("product", "StarterPet", nil), "the one-pet Starter Pack only where restricted")
	check(StoreInfo.offered("product", "TreatBag", nil) and StoreInfo.offered("pass", "DoubleXP", false), "everything else is always for sale")
	check(#Pets.speciesFor("SecretEgg", "Secret") == 4, "the Secret Egg hatches four Secret pets")
	local mythicSecret = Pets.speciesFor("MythicEgg", "Secret")
	check(#mythicSecret == 1 and mythicSecret[1] == "AuroraSerpent", "the Mythic Egg's Secret is the Aurora Serpent")
	check(not table.find(Pets.speciesFor("SecretEgg", "Secret"), "AuroraSerpent"), "the Aurora Serpent only comes from Mythic Eggs")
	for id, sp in pairs(Pets.Species) do
		check(sp.egg == nil or Pets.Eggs[sp.egg] ~= nil, id .. " is tied to a real egg")
	end
	-- the Mythic Egg: Epic and up, a 1% Secret, sold for Robux (cheaper than the Secret Egg) and found free
	local mythic = Pets.Eggs.MythicEgg
	local mythicTotal = 0
	for _, w in pairs(mythic.weights) do
		mythicTotal += w
	end
	check(not mythic.weights.Common and not mythic.weights.Uncommon and not mythic.weights.Rare, "Mythic Eggs never hatch below Epic")
	check(math.abs(mythic.weights.Secret / mythicTotal - 0.01) < 1e-6, "Mythic Eggs have a 1% Secret")
	check(StoreInfo.Products[mythic.store] ~= nil and StoreInfo.Products[mythic.store].eggs.MythicEgg == 1, "the Mythic Egg is in the Store")
	check(StoreInfo.Products.MythicEgg.robux < StoreInfo.Products.SecretEgg.robux, "the Mythic Egg costs less than the Secret Egg")
	check(mythic.desc:find("free") ~= nil and StoreInfo.Products.MythicEgg.desc:find("free") ~= nil, "the Mythic Egg says free players can find it too")
	for _, eggId in ipairs(Pets.EggOrder) do
		local egg = Pets.Eggs[eggId]
		check(egg.store == nil or StoreInfo.Products[egg.store] ~= nil, eggId .. " store product exists")
	end
	-- passes
	for _, passId in ipairs(StoreInfo.PassOrder) do
		local pass = StoreInfo.Passes[passId]
		check(pass ~= nil and pass.robux > 0 and pass.desc ~= nil, "store pass " .. passId)
	end
	check(StoreInfo.FLIGHT_MULT > 1 and StoreInfo.WAYFINDER_COOLDOWN > 0, "handy pass numbers")
	-- places (the world map list and Wayfinder teleports)
	local placeIds = {}
	local B = Zones.WorldBounds
	for _, place in ipairs(Zones.places()) do
		check(not placeIds[place.id], "place ids are unique: " .. place.id)
		placeIds[place.id] = true
		if place.id ~= "home" then
			check(place.pos ~= nil and place.drop ~= nil, "place " .. place.id .. " has a spot")
			check(place.drop.X > B.min.X and place.drop.X < B.max.X and place.drop.Z > B.min.Z and place.drop.Z < B.max.Z, "place " .. place.id .. " is on the map")
		end
	end
	-- nobody gets teleported into a lake
	for _, place in ipairs(Zones.places()) do
		for _, lake in ipairs(Zones.Lakes) do
			for _, lobe in ipairs(lake.lobes) do
				local c = lake.center + Vector3.new(lobe[1], 0, lobe[2])
				if place.drop then
					check(Vector3.new(place.drop.X - c.X, 0, place.drop.Z - c.Z).Magnitude > lobe[3] + 4, "place " .. place.id .. " isn't in " .. lake.id)
				end
			end
		end
	end
	for _, camp in ipairs(Zones.Camps) do
		local drop = Zones.getPlace("camp:" .. camp.id).drop
		check((drop - camp.center).Magnitude > camp.radius, "Wayfinder sets you down outside " .. camp.id)
	end
	check(Zones.getPlace("home") ~= nil and Zones.getPlace("nowhere") == nil, "place lookup")
	check(StoreInfo.goldFor(20, 30) > StoreInfo.goldFor(20, 1) * 5, "gold packs grow with level")
	for eggId in pairs(Shops.Eggs) do
		check(Pets.Eggs[eggId] and Pets.Eggs[eggId].price ~= nil, "the hatchery only stocks eggs with a price: " .. eggId)
	end
	for rarity in pairs(Shops.Gear.rarityWeights) do
		check(Shops.Gear.amount[rarity] ~= nil, "gear stock amount for " .. rarity)
	end
end

---------------------------------------------------------------- paragon and the ability loadout
do
	check(TalentUtil.totalPoints(Game.LEVEL_CAP, Game.PARAGON_POINT_EVERY * 3) == Game.LEVEL_CAP - 1 + 3, "Paragon adds a point every few levels")
	check(Game.paragonXp(10) > Game.paragonXp(0), "Paragon levels get a bit harder")
	-- a Paragon level is worth a real chunk of a level, and they keep counting past the cap
	local function paragonHp(n)
		return StatCalc.compute("Shadowstalker", Game.LEVEL_CAP, gearAt(Game.LEVEL_CAP, "Rare"), {}, { { stats = BonusUtil.paragonStats(n) } }).maxHealth
	end
	check(paragonHp(1) - paragonHp(0) >= 8, "an early Paragon level adds real health (" .. (paragonHp(1) - paragonHp(0)) .. ")")
	check(paragonHp(Game.PARAGON_BONUS_CAP + 20) > paragonHp(Game.PARAGON_BONUS_CAP), "Paragon levels past the cap still add stats")
	local abilities = { "Breath", "Fireball", "Sig", "A", "B", "C", "D", "E" }
	local out = TalentUtil.resolveLoadout(abilities, { "E", false, "Missing", "A" }, "Sig")
	check(out[1] == "E" and out[4] == "A", "loadout keeps the player's picks")
	check(out[2] == "B" and out[3] == "C", "empty or stale keys fill with the rest in order")
	local few = TalentUtil.resolveLoadout({ "Breath", "Fireball", "A" }, nil, "Sig")
	check(few[1] == "A" and few[2] == nil, "loadout with one ability")
end

---------------------------------------------------------------- day and night
do
	check(Game.NIGHT_SECONDS < Game.DAY_SECONDS, "nights are shorter than days")
	check(math.abs(DayNight.clockTime(0) - Game.DAWN_HOUR) < 1e-6, "the cycle starts at dawn")
	check(math.abs(DayNight.clockTime(Game.DAY_SECONDS) - Game.DUSK_HOUR) < 1e-6, "dusk at the end of the day")
	check(not DayNight.isNight(Game.DAY_SECONDS - 1) and DayNight.isNight(Game.DAY_SECONDS + 1), "night starts at dusk")
	for _, hour in ipairs({ 0, 3, 6, 10, 12, 17.5, 18, 21 }) do
		local offset = DayNight.offsetFor(1000, hour)
		local clock = DayNight.clockTime(DayNight.phase(1000, offset))
		check(math.abs(clock - hour) < 1e-6, "offsetFor puts the clock at " .. hour .. " (" .. clock .. ")")
	end
	local last = -1
	for t = 0, DayNight.cycleLength() - 1, 5 do
		local c = (DayNight.clockTime(t) - Game.DAWN_HOUR) % 24
		check(c >= last, "the clock only moves forward (t=" .. t .. ")")
		last = c
	end
	check(DayNight.darkness(12) == 0 and DayNight.darkness(0) == 1, "noon is light, midnight is dark")
	check(DayNight.format(13.5) == "1:30 PM" and DayNight.format(0.25) == "12:15 AM", "clock text")
end

---------------------------------------------------------------- night raids
do
	check(Raids.CHANCE > 0 and Raids.CHANCE <= 1 and Raids.PITY_NIGHTS >= 1, "raid chance and pity")
	check(Raids.MAX_BURNED <= #Zones.Houses, "the village can burn")
	-- villagers and quest givers help more when few dragons are online, and can finish stragglers
	local d1, f1 = Raids.villagerHelp(1)
	local d2, f2 = Raids.villagerHelp(2)
	local d3, f3 = Raids.villagerHelp(3)
	check(d1 > d2 and d2 > d3 and d3 == 1, "villager fire hits harder with fewer dragons online")
	check(f1 < f2 and f2 < f3 and f3 == Raids.VILLAGER_FINISH_AFTER, "villagers finish raiders sooner with fewer dragons online")
	check(Raids.villagerHelp(0) == d1 and Raids.villagerHelp(12) == 1, "villager help for an empty or full server")
	check(f3 < Raids.FIGHT_TIME, "a straggler can be finished by the villagers before the raid's time runs out")
	-- the raid keeps its own clock: time to fight after the last wave, and a nightfall raid still
	-- ends before dawn (only a late one runs on into the morning)
	check(Raids.FIGHT_TIME >= 120, "time to fight after the last wave")
	-- the ships row at full speed for most of the trip
	check(Raids.SHIP_SLOWDOWN > 0 and Raids.SHIP_SLOWDOWN <= 0.3 and Raids.SHIP_ROW_TIME < Raids.WARNING, "the longships don't crawl up to the beach")
	-- water for the fires
	check(Raids.WATER_LOADS >= 1 and Raids.POUR_TIME > 0 and Raids.DOUSE_TIME > 0, "water loads and pouring")
	-- one dragon has to stay over a fire a while; a load of water is enough for a whole fire alone
	check(Raids.DOUSE_TIME >= 2 and Raids.POUR_TIME >= Raids.DOUSE_TIME, "putting a fire out takes a few seconds, and one load does it")
	check(Raids.DOUSE_REGROW > Raids.DOUSE_TIME and Raids.REGROW_DELAY > 0, "a fire creeps back slower than it's put out")
	check(Raids.FLAMES_FADE > 0 and Raids.STEAM_TIME > 0, "put-out flames die away slowly")
	check(Raids.POUR_REACH >= Zones.HouseSize.X / 2 and Raids.POUR_HEIGHT > Zones.HouseSize.Y + 10, "hovering over any part of a house's roof pours the water on it")
	check(Raids.DECK_DAMAGE_TAKEN > 0.2 and Raids.DECK_DAMAGE_TAKEN < 1, "vikings on deck take less damage, but can still be beaten")
	check(#Zones.Wells >= 2, "town wells")
	for i, well in ipairs(Zones.Wells) do
		check(Zones.isIn("Town", well), "well " .. i .. " is in town")
		for h, house in ipairs(Zones.Houses) do
			local d = Vector3.new(house.pos.X - well.X, 0, house.pos.Z - well.Z).Magnitude
			check(d > Zones.HouseSize.X / 2 + 6, "well " .. i .. " is clear of house " .. h)
		end
	end
	-- every house is a short flight from water: a well, or the river below town (z ~ 250+)
	for h, house in ipairs(Zones.Houses) do
		local nearest = math.abs(250 - house.pos.Z)
		for _, well in ipairs(Zones.Wells) do
			nearest = math.min(nearest, Vector3.new(house.pos.X - well.X, 0, house.pos.Z - well.Z).Magnitude)
		end
		check(nearest < 150, "house " .. h .. " is a short flight from water (" .. math.floor(nearest) .. " studs)")
	end
	check(Raids.COLLAPSE_TIME > 0 and Raids.DIE_DOWN > 0 and Raids.SMOLDER > 0, "houses burn down over a while")
	check(Raids.RETREAT_TIME > 10 and Raids.RETREAT_SPEED >= 1, "a lost raid's raiders have time to run back to their ships")
	check(Raids.ELDER_DAMAGE > Raids.VILLAGER_DAMAGE and Raids.ELDER_RANGE > Raids.VILLAGER_RANGE, "quest givers hit harder and reach further than villagers")
	local lastMax, lastRaiders = 0, 0
	for t, tier in ipairs(Raids.Tiers) do
		check(tier.maxLevel > lastMax, "raid tier " .. t .. " covers higher levels than the one before")
		lastMax = tier.maxLevel
		check(#tier.waves == Raids.WAVES, "raid tier " .. t .. " has " .. Raids.WAVES .. " waves")
		check(Raids.WARNING + Raids.WAVE_GAP * (#tier.waves - 1) + Raids.FIGHT_TIME < Game.NIGHT_SECONDS, "raid tier " .. t .. ": a raid that starts at nightfall is over by dawn")
		check(tier.burnTime > 0 and tier.captainHealth > 0 and tier.levelBelow >= 0, "raid tier " .. t .. " numbers")
		local raiders, leaders = 0, 0
		for i, wave in ipairs(tier.waves) do
			for typeId, count in pairs(wave) do
				if typeId == "leader" then
					leaders += 1
				else
					raiders += count
					check(Enemies.Vikings[typeId] ~= nil and count > 0, "raid tier " .. t .. " wave " .. i .. " viking " .. tostring(typeId))
				end
			end
		end
		check(leaders == 1, "raid tier " .. t .. " has one Raid Captain")
		check(raiders >= lastRaiders, "raid tier " .. t .. " is no smaller than the gentler one")
		lastRaiders = raiders
	end
	check(lastMax == math.huge, "the last raid tier covers every level")
	check(Raids.tierFor(1) == Raids.Tiers[1] and Raids.tierFor(30) == Raids.Tiers[#Raids.Tiers], "raid tier by level")
	check(Raids.CROWD >= 1 and Raids.CHASE_RANGE > 20 and Raids.FLYER_HEIGHT > 5, "raider chase limits")
	check(Raids.VILLAGER_HITS >= 1 and Raids.VILLAGER_KNOCKOUT > 0, "villager knockouts")
	for _, approach in pairs(Zones.LairApproach) do
		check(Zones.TownWalk.nodes[approach.from] ~= nil, "lair approach starts on the street graph")
	end
	for _, base in ipairs(Zones.Bases) do
		check(Zones.baseAt(base.center) == base and Zones.baseAt(Zones.lairGate(base)) == base, "lair " .. base.index .. " contains its own gate")
	end
	check(Zones.baseAt(Vector3.new(0, 0, 0)) == nil, "the plaza is nobody's lair")
	check(Enemies.Vikings[Raids.Captain.base] ~= nil, "raid captain base type")
	check(Enemies.Vikings.Torchbearer ~= nil and Enemies.Vikings.Torchbearer.look.weapon == "torch", "torchbearers carry torches")
	check(Zones.TownWalk.nodes[Raids.ENTRY_NODE] ~= nil, "raid entry node exists")
	for i, landing in ipairs(Raids.Landings) do
		check(Zones.isIn("Town", landing.shore), "raid landing " .. i .. " is in town")
		check(math.abs(landing.shipX) > 30, "raid longship " .. i .. " is clear of the bridge")
	end
	check(Raids.VILLAGER_FLOOR > 0, "villagers can't finish raiders off")
	check(Raids.Rewards.xpShare > 0 and Raids.Rewards.gold.base > 0, "raid rewards")
	check(Collections.getAchievement("Defender") ~= nil and Collections.getAchievement("Sharpshooter") ~= nil, "raid and range achievements")
end

---------------------------------------------------------------- target practice
do
	local patterns = { still = true, slide = true, bob = true, zigzag = true, sprint = true, float = true, popup = true }
	local R = Zones.Range
	local lastXp = 0
	for i, def in ipairs(Range.Levels) do
		check(def.needed > 0 and def.time > 0 and def.count > 0 and def.size > 0, "range level " .. i .. " numbers")
		check(def.xp > lastXp, "range level " .. i .. " pays more than the one before")
		lastXp = def.xp
		-- enough shots to clear it, even missing half of them
		check(def.time / Range.FIREBALL_COOLDOWN >= def.needed * 2, "range level " .. i .. " is clearable")
		for _, pattern in ipairs(def.patterns) do
			check(patterns[pattern] == true, "range level " .. i .. " pattern " .. pattern)
			if pattern == "popup" then
				check((def.life or 0) > 0, "range level " .. i .. " popups have a life")
			end
		end
	end
	check(Range.AFK.xpPerMinute * 60 < Range.Levels[#Range.Levels].xp * 10, "AFK practice is slower than playing")
	check(Range.afkXpPerHit(100) >= 1 and Range.afkXpPerHit(8000) > Range.afkXpPerHit(1000), "AFK XP per hit grows with the level, never 0")
	check(Range.SPLASH >= Range.PROJECTILE_RADIUS, "a practice fireball that touches a target knocks it down")
	local lastSize = math.huge
	for i, def in ipairs(Range.Levels) do
		check(def.size <= lastSize, "range level " .. i .. " targets are no bigger than the level before")
		lastSize = def.size
	end
	-- targets stay in their lane and in front of the backstop
	for _, pattern in pairs({ "slide", "bob", "zigzag", "sprint", "float" }) do
		local amp = R.laneHalf
		local t = { pattern = pattern, x = (R.near + R.far) / 2, y = 8, z = R.lanes[1], speed = 18, amp = amp, phase = 1, born = 0 }
		for k = 0, 200 do
			local p = RangeUtil.position(t, k * 0.137)
			check(math.abs(p.Z - R.lanes[1]) <= R.laneHalf + 1e-6, pattern .. " stays in its lane")
			check(p.X > R.backstop and p.X < R.matX - 6, pattern .. " stays on the field")
			check(p.Y > 0, pattern .. " stays above the ground")
		end
	end
	-- sliders and sprinters never move faster than their level's speed, and sprinters rest at each side
	for _, pattern in ipairs({ "slide", "sprint" }) do
		local t = { pattern = pattern, x = 0, y = 8, z = 0, speed = 13, amp = R.laneHalf, phase = 2, born = 0 }
		local fastest, still = 0, 0
		local dt = 0.02
		for k = 0, 1000 do
			local a, b = RangeUtil.position(t, k * dt), RangeUtil.position(t, (k + 1) * dt)
			local v = math.abs(b.Z - a.Z) / dt
			fastest = math.max(fastest, v)
			if v < 0.01 then
				still += dt
			end
		end
		check(fastest <= t.speed * 1.02, pattern .. " moves at most `speed` studs a second (" .. math.floor(fastest) .. ")")
		if pattern == "sprint" then
			check(still > 2, "sprinters rest between dashes")
		end
	end
	check(RangeUtil.expired({ born = 0, life = 2 }, 2.5) and not RangeUtil.expired({ born = 0 }, 99), "popups vanish, others don't")
	-- the practice camera (CAMERA_ZOOM behind the mat, looking down the lane) has open air around
	-- it: a house wall there made Roblox pull the camera in
	local camX = R.matX + Range.CAMERA_ZOOM
	for _, house in ipairs(Zones.Houses) do
		local halfX = house.facing.X ~= 0 and Zones.HouseSize.Z / 2 or Zones.HouseSize.X / 2
		local halfZ = house.facing.X ~= 0 and Zones.HouseSize.X / 2 or Zones.HouseSize.Z / 2
		for _, z in ipairs(R.lanes) do
			local dx = math.max(0, math.abs(camX - house.pos.X) - halfX)
			local dz = math.max(0, math.abs(z - house.pos.Z) - halfZ)
			check(math.max(dx, dz) >= 6, "the practice camera on lane z " .. z .. " clears house at " .. house.pos.X .. ", " .. house.pos.Z)
		end
	end
end

---------------------------------------------------------------- dungeons
do
	local Dungeons = require(Config.Dungeons)
	local DungeonNav = require(Shared.DungeonNav)
	local BOSS_MOVES = { Cleave = 1, GroundSlam = 1, RuneStrikes = 1, AxeVolley = 1, Leap = 1, Charge = 1, Whirlwind = 1, Harpoon = 1, Lane = 1 }
	local function flatDist(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end
	check(Dungeons.UNLOCK_LEVEL == Dungeons.List[Dungeons.Order[1]].minLevel, "the first dungeon unlocks with the 🏰 button")
	local lastLevel = 0
	local entrances = {}
	for _, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		check(def and def.id == id, "dungeon " .. id)
		check(def.minLevel > lastLevel and def.minLevel <= Game.LEVEL_CAP, id .. " unlocks after the one before, by the level cap")
		lastLevel = def.minLevel
		check(def.level >= def.minLevel and def.ilvl >= def.level, id .. " levels")
		-- the cave mouth: on the map, clear of camps, lakes, the river, town and the other mouth
		local e = def.entrance
		check(Zones.inWorld(e) and areaId(e) ~= "Town", id .. " entrance is out in the wilds")
		for _, camp in ipairs(Zones.Camps) do
			check(flatDist(e, camp.center) > camp.radius + 60, id .. " entrance is clear of " .. camp.id)
		end
		for _, lake in ipairs(Zones.Lakes) do
			for _, lobe in ipairs(lake.lobes) do
				check(flatDist(e, lake.center + Vector3.new(lobe[1], 0, lobe[2])) > lobe[3] + 40, id .. " entrance is clear of " .. lake.id)
			end
		end
		for _, other in ipairs(entrances) do
			check(flatDist(e, other) > 120, id .. " entrance is apart from the others")
		end
		table.insert(entrances, e)
		local giver = Quests.Givers[def.giver]
		check(giver ~= nil and giver.dungeon == id and Zones.QuestGivers[def.giver] ~= nil, id .. " keeper")
		check(Zones.QuestGivers[def.giver] and flatDist(Zones.QuestGivers[def.giver].position, e) < 60, id .. " keeper stands by the mouth")
		check(Zones.getPlace("dungeon:" .. id) ~= nil, id .. " is on the map and a Wayfinder stop")
		-- spaces fit in their slot and the boss rooms exist
		local rooms = {}
		local reachX, reachZ = 0, 0
		for _, sp in ipairs(def.spaces) do
			check(({ box = 1, round = 1, path = 1 })[sp.kind] ~= nil, id .. " space kind " .. tostring(sp.id))
			if sp.kind == "path" then
				check(#sp.points >= 2 and sp.width >= 20 and sp.height >= 24, id .. " tunnel " .. sp.id .. " is big enough for dragons")
				for _, p in ipairs(sp.points) do
					reachX, reachZ = math.max(reachX, math.abs(p.X)), math.max(reachZ, math.abs(p.Z))
				end
			else
				rooms[sp.id] = sp
				local r = sp.kind == "round" and sp.radius or math.max(sp.size.X, sp.size.Y) / 2
				reachX, reachZ = math.max(reachX, math.abs(sp.at.X) + r), math.max(reachZ, math.abs(sp.at.Z) + r)
			end
		end
		check(reachX < Dungeons.SLOT_SPACING / 2 - 40 and reachZ < Dungeons.ROW_SPACING - 60, id .. " fits in its slot (" .. reachX .. ", " .. reachZ .. ")")
		check(rooms[def.boss.room] ~= nil and rooms[def.miniBoss.room] ~= nil, id .. " boss rooms")
		check(Dungeons.Bosses[def.boss.id] ~= nil and not Dungeons.Bosses[def.boss.id].mini, id .. " boss")
		check(Dungeons.Bosses[def.miniBoss.id] ~= nil and Dungeons.Bosses[def.miniBoss.id].mini, id .. " mini-boss")
		for pi, pack in ipairs(def.packs) do
			local mobs = Dungeons.packMobs(pack)
			check(#mobs >= 2 and #mobs <= 4, id .. " pack " .. pi .. " has 2-4 monsters")
			for _, m in ipairs(mobs) do
				local mdef = Enemies.Dungeon[m[1]]
				check(mdef ~= nil and mdef.dungeon == id, id .. " pack " .. pi .. " monster " .. tostring(m[1]))
			end
		end
		for _, relic in ipairs(def.loot.relics) do
			local u = Items.Uniques[relic]
			check(u ~= nil and u.dungeon == id and u.special ~= nil and not u.quest, id .. " relic " .. relic)
		end
		local egg = Pets.Eggs[def.loot.egg]
		check(egg ~= nil and egg.dungeon == id and egg.price == nil and egg.store == nil and table.find(Pets.EggOrder, def.loot.egg) ~= nil, id .. " egg can't be bought")
		for rarity in pairs(egg and egg.weights or {}) do
			for _, sp in ipairs(Pets.speciesFor(def.loot.egg, rarity)) do
				check(Pets.Species[sp].egg == def.loot.egg, id .. " egg only hatches its own pets: " .. sp)
			end
		end
		check(def.title ~= nil and table.find(Collections.allTitles(), def.title) ~= nil, id .. " first-clear title")
		check(def.victory ~= nil and def.story ~= nil, id .. " texts")
	end
	for id in pairs(Enemies.Dungeon) do
		check(Enemies.Vikings[id] == nil, "dungeon monster ids are their own: " .. id)
	end
	-- bosses: every move and trait exists, and the phases come in order
	for bossId, b in pairs(Dungeons.Bosses) do
		local function movesOk(moves, where)
			for name, cfg in pairs(moves) do
				check(BOSS_MOVES[name] ~= nil and (cfg.cooldown or 0) > 0 and (cfg.mult or 0) > 0, bossId .. where .. " move " .. name)
			end
		end
		movesOk(b.moves, "")
		check(b.health > 0 and b.hit > 0 and b.scale > 1 and b.look ~= nil, bossId .. " numbers")
		for _, s in ipairs(b.summons or {}) do
			check(Enemies.Dungeon[s.add] ~= nil and s.at > 0 and s.at < 1 and s.count > 0, bossId .. " summons " .. tostring(s.add))
		end
		if b.secondLife then
			check(b.secondLife.health > 0 and b.secondLife.health < 1 and b.secondLife.delay > 0 and b.secondLife.name ~= nil, bossId .. " second life")
			movesOk(b.secondLife.moves, " (second life)")
		end
		local lastAt = 1
		for i, ph in ipairs(b.phases or {}) do
			check(ph.at < lastAt, bossId .. " phase " .. i .. " comes after the one before")
			lastAt = ph.at
			movesOk(ph.moves, " phase " .. i)
			if ph.shield then
				check(Enemies.Dungeon[ph.shield.add] ~= nil and ph.shield.count > 0, bossId .. " shield guards")
			end
		end
		check(not b.enrage or (b.enrage.at > 0 and b.enrage.at < 1), bossId .. " enrage")
	end
	check(Dungeons.Bosses.Grimvald.enrage == nil and Dungeons.Bosses.Grimvald.moves.Charge ~= nil, "Grimvald charges and never enrages")
	check(Dungeons.Bosses.Haldor.secondLife ~= nil and Dungeons.Bosses.Haldor.secondLife.moves.Leap ~= nil and Dungeons.Bosses.Haldor.enrage == nil, "Haldor rises again, and leaps")
	check(Dungeons.Bosses.Brakki.moves.Leap ~= nil and Dungeons.Bosses.Brakki.enrage ~= nil, "Brakki leaps and enrages")
	check(Dungeons.Bosses.Sigrun.moves.Harpoon ~= nil and Dungeons.Bosses.Sigrun.moves.Lane ~= nil and #Dungeons.Bosses.Sigrun.phases == 2, "Sigrun: harpoon, fire lanes, two phases")
	-- the dungeon keepers' quests
	for _, q in ipairs(Quests.List) do
		local t = q.objective.type
		if t == "dungeonClear" or t == "dungeonKill" then
			local def = Dungeons.get(q.objective.target)
			check(def ~= nil and q.minLevel >= def.minLevel and Quests.Givers[q.giver].dungeon == def.id, q.id .. " belongs to its dungeon")
		end
		if q.rewards.unique then
			local u = Items.Uniques[q.rewards.unique]
			check(u ~= nil and u.quest == true, q.id .. " quest relic")
		end
	end
	-- relics: a flat lifesteal / regen that doesn't grow with level or upgrades, and shows in tooltips
	local low = ItemUtil.getStats(ItemUtil.new("Claws", 10, "Legendary", "DraugrFang"))
	local highItem = ItemUtil.new("Claws", 30, "Legendary", "DraugrFang")
	highItem.up = 5
	check(low.lifesteal == Items.Uniques.DraugrFang.special.lifesteal and ItemUtil.getStats(highItem).lifesteal == low.lifesteal, "relic lifesteal doesn't grow")
	check(table.concat(ItemUtil.describeStats(low), " "):find("Lifesteal") ~= nil, "relic tooltips show their lifesteal")
	check(ItemUtil.score(ItemUtil.new("Head", 17, "Legendary", "HollowKingsCrown")) > ItemUtil.score(ItemUtil.new("Head", 17, "Legendary")), "a relic beats a plain item of its level")
	-- caps: every relic plus three golden level-5 lifesteal/regen pets on top of full talent builds
	local lsGear, regenGear = {}, {}
	for id, u in pairs(Items.Uniques) do
		if u.special then
			local item = ItemUtil.new(u.slot, 30, "Legendary", id)
			if (u.special.lifesteal or 0) > ((lsGear[u.slot] and ItemUtil.getStats(lsGear[u.slot]).lifesteal) or 0) then
				lsGear[u.slot] = item
			end
			if (u.special.regen or 0) > ((regenGear[u.slot] and ItemUtil.getStats(regenGear[u.slot]).regen) or 0) then
				regenGear[u.slot] = item
			end
		end
	end
	local pets = {}
	for _, species in ipairs({ "HeartbloomWyrm", "DraugrDrake", "ChainbreakerWyrm" }) do
		table.insert(pets, { stats = BonusUtil.petBoosts({ species = species, level = Pets.MAX_LEVEL, golden = true }), extra = true })
	end
	local bare = StatCalc.compute("Shadowstalker", 30, lsGear, {}, pets)
	check(bare.extraLifesteal > Game.EXTRA_LIFESTEAL_CAP and bare.lifesteal <= Game.EXTRA_LIFESTEAL_CAP + 1e-6, "gear and pets stop at their lifesteal cap (" .. bare.extraLifesteal .. " -> " .. bare.lifesteal .. ")")
	local regenBare = StatCalc.compute("Venomspine", 30, regenGear, {}, pets)
	check(regenBare.extraRegen > Game.EXTRA_REGEN_CAP and math.abs(regenBare.regen - Game.EXTRA_REGEN_CAP) < 1e-6, "gear and pets stop at their regen cap (" .. regenBare.extraRegen .. ")")
	local function fullBranch(classId, want)
		local talents = {}
		for bi = 1, 3 do
			local stacked = false
			for _, t in ipairs(Talents[classId][bi].talents) do
				if (t.effects[want] or 0) > 0 then
					stacked = true
				end
			end
			if stacked then
				TalentUtil.autoFill(classId, Game.LEVEL_CAP, talents, bi)
				return talents
			end
		end
		return talents
	end
	local ls = StatCalc.compute("Shadowstalker", 30, lsGear, fullBranch("Shadowstalker", "lifesteal"), pets)
	check(ls.lifesteal <= Game.LIFESTEAL_CAP + 1e-6, "a full lifesteal build stays under the cap (" .. ls.lifesteal .. ")")
	local rg = StatCalc.compute("Venomspine", 30, regenGear, fullBranch("Venomspine", "regen"), pets)
	check(rg.regen <= Game.REGEN_CAP + 1e-6 and rg.regen > Game.EXTRA_REGEN_CAP, "a full regen build stays under the cap (" .. rg.regen .. ")")
	Tuning.values.global.extraLifestealCap = 0.5
	check(StatCalc.compute("Shadowstalker", 30, lsGear, {}, pets).lifesteal <= Game.EXTRA_LIFESTEAL_CAP * 0.5 + 1e-6, "the admin panel can lower the gear-and-pets cap")
	Tuning.reset()
	check(#Pets.speciesFor("SecretEgg", "Secret") == 4 and table.find(Pets.speciesFor("SecretEgg", "Secret"), "HeartbloomWyrm") ~= nil, "the Secret Egg can hatch the Heartbloom Wyrm")

	-- balance: an average dragon of the dungeon's level (Rare gear, no talents) against its boss and
	-- packs, for groups of 1-4. StatCalc.dps is the same yardstick the world bosses are sized by.
	-- Real play is kinder than that bare dragon: talents, pets and potions (REAL_DPS, REAL_HP),
	-- breath and area spells hitting most of a pack (AOE), not every monster hitting all the time
	-- (SPREAD), and a boss's telegraphed moves dodged about half the time (DODGE). The targets, for
	-- that fight (the first playtest found a lone dragon cruising through at the old numbers):
	--   * a lone dragon of the dungeon's level beats a pack, but comes out hurt (it lasts 1.2-2.2x
	--     as long as the fight: half to most of its health gone)
	--   * a lone dragon of the dungeon's level loses to the final boss (it needs better gear, or
	--     lifesteal / regen, or friends)
	--   * four dragons beat the boss in 60-150 s
	local REAL_DPS, REAL_HP, AOE, SPREAD, DODGE = 1.3, 1.2, 1.8, 0.8, 0.5
	print("Dungeon | dragons | boss HP  kill(s) lasts(s) | pack HP kill(s) lasts(s)")
	for _, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		local level = def.minLevel + 1
		local dps, hp, defense = 0, 0, 0
		for _, classId in ipairs(Classes.Order) do
			local st = StatCalc.compute(classId, level, gearAt(level, "Rare"), {}, {})
			dps += StatCalc.dps(st) / #Classes.Order
			hp += st.maxHealth / #Classes.Order
			defense += st.defense / #Classes.Order
		end
		dps *= REAL_DPS
		hp *= REAL_HP
		local boss = Dungeons.Bosses[def.boss.id]
		local bossLevel = def.level + 2
		local bossBlock = 1 - defense / (defense + Game.DEFENSE_CONSTANT + 5 * bossLevel)
		-- (the level gap: the boss is 2 levels above these dragons, the monsters level with them)
		local toBoss, fromBoss = StatCalc.levelGap(level - bossLevel), StatCalc.levelGap(bossLevel - level)
		local perHit = 0 -- the boss's damage per second on the dragon it's fighting (per unit of `hit`)
		for name, cfg in pairs(boss.moves) do
			perHit += (cfg.mult or 1) / cfg.cooldown * (name == "Cleave" and 1 or DODGE)
		end
		for n = 1, 4 do
			local bossHp = boss.health * Dungeons.groupHealth(n) * (1 + (boss.secondLife and boss.secondLife.health or 0))
			local bossTime = bossHp / (dps * toBoss * n)
			local bossDps = boss.hit * Dungeons.groupDamage(n) * perHit * bossBlock * fromBoss
			local bossLasts = hp * n / bossDps -- (it turns on each dragon in turn)
			local packHp, packHit = 0, 0
			for _, pack in ipairs(def.packs) do
				for _, m in ipairs(Dungeons.packMobs(pack)) do
					local mdef = Enemies.Dungeon[m[1]]
					local mob = def.level
					packHp += mdef.health * (1 + Enemies.HEALTH_PER_LEVEL * (mob - 1)) * Dungeons.groupHealth(n) / #def.packs
					local hit = mdef.damage * (1 + Enemies.DAMAGE_PER_LEVEL * (mob - 1)) * Dungeons.groupDamage(n) * StatCalc.levelGap(mob - level)
					hit *= 1 - defense / (defense + Game.DEFENSE_CONSTANT + 5 * mob)
					packHit += hit / mdef.attackCooldown * SPREAD / #def.packs
				end
			end
			local packTime = packHp / (dps * n * AOE)
			local lasts = hp * n / packHit
			print(string.format("%-7s | %7d | %7d %6.0f %6.0f | %7d %6.1f %6.1f", id, n, bossHp, bossTime, bossLasts, packHp, packTime, lasts))
			if n == 4 then
				check(bossTime >= 60 and bossTime <= 150, id .. ": four dragons beat the boss in 60-150 s (" .. math.floor(bossTime) .. ")")
			end
			if n == 1 then
				local ratio = lasts / packTime
				check(ratio >= 1.2 and ratio <= 2.2, string.format("%s: a lone dragon beats a pack but comes out hurt (lasts %.1fx the fight)", id, ratio))
				check(bossLasts < bossTime, string.format("%s: a lone dragon of the dungeon's level loses to the boss (%.0fs vs %.0fs to win)", id, bossLasts, bossTime))
			end
		end
	end
	-- the first clear pays far more XP than the ones after; bosses leap at any range
	check(Dungeons.FIRST_CLEAR_XP >= Dungeons.BOSS_XP * 3, "the first clear's XP bonus is big")
	check(Dungeons.GROUP_DAMAGE[1] >= 0.9, "a dragon on its own takes nearly full hits")
	-- the monsters' map: every pack, boss and the hoard can be reached from the entrance, never
	-- through lava; wanderers and patrols
	for _, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		local reachable = true
		for _, pack in ipairs(def.packs) do
			for _, m in ipairs(Dungeons.packMobs(pack)) do
				local path = DungeonNav.route(def, def.spawn, m[2])
				if not path then
					reachable = false
				else
					local last = def.spawn
					for _, node in ipairs(path) do
						if DungeonNav.crossesHazard(def, last, node) then
							reachable = false
						end
						last = node
					end
				end
			end
		end
		check(reachable and DungeonNav.route(def, def.spawn, def.boss.at) ~= nil, id .. ": every monster can be walked to from the entrance, never through lava")
		local patrols, wanderers = 0, 0
		for _, pack in ipairs(def.packs) do
			if pack.patrol then
				patrols += 1
			end
			for _, m in ipairs(Dungeons.packMobs(pack)) do
				if (pack.idle or Enemies.Dungeon[m[1]].idle) == "wander" then
					wanderers += 1
				end
			end
		end
		check(patrols >= 1 and wanderers >= 3, id .. ": a patrol and some wanderers (not all standing still)")
	end
end

---------------------------------------------------------------- levels, the level gap, lifesteal paths
do
	-- Levelling up counts for more (each level ~3.3% health and ~3.9% attack at 15, was ~2.4% and
	-- ~3%), gear a little less, so a dragon with Rare gear of its level is about as strong as it
	-- was before (these are the old numbers: health, attack).
	local BEFORE = {
		Shadowstalker = { [5] = { 298, 35.2 }, [15] = { 633, 76.2 }, [30] = { 1134, 136.7 } },
		Stormwing = { [5] = { 282, 33.4 }, [15] = { 597, 72.4 }, [30] = { 1068, 129.9 } },
		Behemoth = { [5] = { 394, 38.4 }, [15] = { 819, 82.4 }, [30] = { 1455, 147.4 } },
		Frostwyrm = { [5] = { 314, 33.8 }, [15] = { 659, 73.8 }, [30] = { 1175, 132.8 } },
		Venomspine = { [5] = { 304, 32.0 }, [15] = { 639, 70.0 }, [30] = { 1140, 126.0 } },
	}
	for _, classId in ipairs(Classes.Order) do
		for _, level in ipairs({ 5, 15, 30 }) do
			local st = StatCalc.compute(classId, level, gearAt(level, "Rare"), {}, {})
			local old = BEFORE[classId][level]
			local band = level == 5 and 0.08 or 0.07
			check(math.abs(st.maxHealth / old[1] - 1) <= band and math.abs(st.attack / old[2] - 1) <= band,
				string.format("%s %d with at-level Rare gear is about as strong as before (%d hp, %.1f atk; was %d, %.1f)", classId, level, st.maxHealth, st.attack, old[1], old[2]))
		end
		local a = StatCalc.compute(classId, 15, gearAt(15, "Rare"), {}, {})
		local b = StatCalc.compute(classId, 16, gearAt(15, "Rare"), {}, {})
		check(b.attack / a.attack - 1 >= 0.035 and b.maxHealth / a.maxHealth - 1 >= 0.03,
			string.format("%s: a level-up alone (15 -> 16, same gear) is worth ~4%% (%.1f%% attack, %.1f%% health)", classId, (b.attack / a.attack - 1) * 100, (b.maxHealth / a.maxHealth - 1) * 100))
	end

	-- the level gap: mild at first, bigger past 10, capped, and the same both ways
	check(StatCalc.levelGap(0) == 1, "no level gap at the same level")
	local last = 1
	local rising = true
	for d = 1, 40 do
		local g = StatCalc.levelGap(d)
		if g < last then
			rising = false
		end
		last = g
		check(math.abs(StatCalc.levelGap(-d) - math.max(1 / g, Game.LEVEL_GAP.floor)) < 1e-9, "the level gap works the same both ways (" .. d .. ")")
	end
	check(rising, "the level gap never shrinks as the gap grows")
	check(StatCalc.levelGap(2) < 1.08 and StatCalc.levelGap(3) < 1.12, "a couple of levels barely matter (x" .. Util.fmt(Util.round(StatCalc.levelGap(2), 3)) .. ")")
	check(StatCalc.levelGap(10) >= 1.4 and StatCalc.levelGap(10) <= 1.8, "ten levels matter (x" .. Util.fmt(Util.round(StatCalc.levelGap(10), 2)) .. ")")
	check(StatCalc.levelGap(40) <= Game.LEVEL_GAP.cap + 1e-9 and StatCalc.levelGap(-40) >= Game.LEVEL_GAP.floor - 1e-9, "the level gap is capped (no one-shotting paragons)")
	Tuning.values.global.levelGapCap = 0.5
	check(StatCalc.levelGap(40) <= Game.LEVEL_GAP.cap * 0.5 + 1e-9, "the admin panel can lower the level gap's cap")
	Tuning.reset()

	-- lifesteal: only one talent path (Nightmare) stacks two lifesteal talents, and even that
	-- stays well under the old 18%
	local doubled = {}
	for _, classId in ipairs(Classes.Order) do
		for _, branch in ipairs(Talents[classId]) do
			local n, total = 0, 0
			for _, t in ipairs(branch.talents) do
				if (t.effects.lifesteal or 0) > 0 then
					n += 1
					total += t.effects.lifesteal * t.maxRank
				end
			end
			if n >= 2 then
				table.insert(doubled, classId .. "/" .. branch.id)
				check(total < 14, branch.id .. ": its lifesteal talents add up to less than 14% (" .. total .. ")")
			end
			check(total <= 13.5, classId .. "/" .. branch.id .. ": at most 13.5% lifesteal from talents (" .. total .. ")")
		end
	end
	check(#doubled == 1 and doubled[1] == "Shadowstalker/Nightmare", "only Nightmare stacks two lifesteal talents (" .. table.concat(doubled, ", ") .. ")")

	-- the Forge Egg: better odds than the Barrow's, and a 1% Secret that only it hatches
	local fw, bw = Pets.Eggs.ForgeEgg.weights, Pets.Eggs.BarrowEgg.weights
	check((fw.Rare or 0) <= 20 and (fw.Rare or 0) < (bw.Rare or 0), "the Forge Egg rolls Rare far less than the Barrow Egg")
	check(fw.Secret == 1 and #Pets.speciesFor("ForgeEgg", "Secret") == 1 and Pets.speciesFor("ForgeEgg", "Secret")[1] == "ForgeheartWyrmling", "the Forge Egg's 1% Secret is the Forgeheart Wyrmling")
	check(table.find(Pets.speciesFor("SecretEgg", "Secret"), "ForgeheartWyrmling") == nil, "the Secret Egg can't hatch the Forgeheart Wyrmling")
	local wyrmling = BonusUtil.petBoosts({ uid = "x", species = "ForgeheartWyrmling", level = Pets.MAX_LEVEL or 10, golden = true })
	check(wyrmling.breathRange == 50, "the Forgeheart Wyrmling's breath range doesn't grow with level or gold (" .. tostring(wyrmling.breathRange) .. ")")
	local plain = StatCalc.resolveAbility("Breath", "Stormwing", StatCalc.compute("Stormwing", 30, {}, {}, {}))
	local longer = StatCalc.resolveAbility("Breath", "Stormwing", StatCalc.compute("Stormwing", 30, {}, {}, { { stats = { breathRange = 50 } } }))
	check(math.abs(longer.range / plain.range - 1.5) < 1e-6, "+50% breath range reaches 50% farther")

	-- the mini-boss door opens itself once the packs on the way are beaten
	local Dungeons = require(Config.Dungeons)
	local DungeonNav = require(Shared.DungeonNav)
	for _, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		local list = def.miniBoss.autoOpen
		check(list ~= nil and #list > 0, id .. ": the mini-boss lists the packs on the way to it")
		local miniAt = DungeonNav.routeLength(def, def.spawn, def.miniBoss.at)
		for _, index in ipairs(list or {}) do
			local pack = def.packs[index]
			check(pack ~= nil and DungeonNav.routeLength(def, def.spawn, pack.at or Dungeons.packMobs(pack)[1][2]) < miniAt, string.format("%s: pack %d is on the way to the mini-boss", id, index))
		end
	end
end

---------------------------------------------------------------- balance report
local total = 0
for l = 1, Game.LEVEL_CAP - 1 do
	total += Game.xpToNext(l)
end
print(string.format("XP to reach level %d: %s", Game.LEVEL_CAP, Util.formatNumber(total)))
print("Level | Class        | HP    ATK   DEF  | viking(lvl) HP   hits-to-kill | viking dmg/hit  hits-to-die")
for _, level in ipairs({ 1, 5, 10, 18, 25, 30 }) do
	local vikingType = level < 5 and "Raider" or (level < 10 and "AxeThrower" or (level < 18 and "Shieldbearer" or "Berserker"))
	local v = Enemies.Vikings[vikingType]
	local vHP = v.health * (1 + Enemies.HEALTH_PER_LEVEL * (level - 1))
	local vDmg = v.damage * (1 + Enemies.DAMAGE_PER_LEVEL * (level - 1))
	local vDef = v.defense * (1 + 0.15 * (level - 1))
	for _, classId in ipairs(Classes.Order) do
		local s = StatCalc.compute(classId, level, gearAt(level, "Uncommon"), {}, {})
		local breath = StatCalc.resolveAbility("Breath", classId, s)
		local perHit = s.attack * breath.damageMult * (1 - vDef / (vDef + Game.DEFENSE_CONSTANT + 5 * level))
		local taken = vDmg * (1 - s.defense / (s.defense + Game.DEFENSE_CONSTANT + 5 * level))
		print(string.format("%5d | %-12s | %5d %5.1f %4.1f | %-12s %5d %5.1f        | %5.1f          %5.1f", level, classId, s.maxHealth, s.attack, s.defense, vikingType .. "(" .. level .. ")", vHP, vHP / perHit, taken, s.maxHealth / taken))
	end
end

print(failures == 0 and "ALL TESTS PASSED" or ("FAILURES: " .. failures))
