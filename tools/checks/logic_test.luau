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
local StatCalc = require(Shared.StatCalc)
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
for id, a in pairs(Abilities) do
	if type(a) == "table" and a.id and id ~= "Breath" and id ~= "Fireball" then
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
local validTypes = { kill = 1, plant = 1, care = 1, harvest = 1, buy = 1, sell = 1, upgrade = 1, pvpKill = 1, bossJoin = 1, bossKill = 1, visitZone = 1, level = 1 }
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
	-- base footprint (92 wide along facing-perpendicular, 76 deep along facing)
	local halfX = math.abs(b.facing.X) > 0.5 and 38 or 46
	local halfZ = math.abs(b.facing.X) > 0.5 and 46 or 38
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
