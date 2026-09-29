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
	hunt = 1, fish = 1, eat = 1, openChest = 1, miniBoss = 1, hatch = 1, potion = 1 }
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
-- a brand-new player sees first quests from every giver
local fresh = { active = {}, done = {} }
for _, g in ipairs(Quests.GiverOrder) do
	local offer = QuestUtil.nextOffer(g, fresh, 1)
	check(offer ~= nil, "giver " .. g .. " has a level-1 offer")
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
	check(areaId(g.position) == "Town", "giver in town " .. id)
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
		check(w > 0 and #Pets.speciesOfRarity(rarity) > 0, eggId .. " has " .. rarity .. " species")
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
	end
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
	check(#Pets.speciesOfRarity("Secret") == 3, "three Secret pets")
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
	local lastMax, lastRaiders = 0, 0
	for t, tier in ipairs(Raids.Tiers) do
		check(tier.maxLevel > lastMax, "raid tier " .. t .. " covers higher levels than the one before")
		lastMax = tier.maxLevel
		check(#tier.waves == Raids.WAVES, "raid tier " .. t .. " has " .. Raids.WAVES .. " waves")
		check(Raids.WARNING + Raids.WAVE_GAP * (#tier.waves - 1) < Game.NIGHT_SECONDS - 60, "raid tier " .. t .. ": every wave lands with time to fight before dawn")
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
