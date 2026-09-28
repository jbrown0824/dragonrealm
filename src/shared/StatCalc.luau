-- Turns (dragon type + level + gear + talents + active buffs) into final stats.
-- Shared so the server (combat) and client (stat screen, tooltips) always agree.

local Config = script.Parent.Config
local Classes = require(Config.Classes)
local Talents = require(Config.Talents)
local Abilities = require(Config.Abilities)
local Game = require(Config.Game)
local ItemUtil = require(script.Parent.ItemUtil)
local Tuning = require(script.Parent.Tuning)

local StatCalc = {}

-- Every talent/buff stat key, how to label it, and whether it's a percentage.
StatCalc.STAT_INFO = {
	attackPct = { label = "Attack", pct = true },
	healthPct = { label = "Max Health", pct = true },
	defensePct = { label = "Defense", pct = true },
	critChance = { label = "Crit Chance", pct = true },
	critDamage = { label = "Crit Damage", pct = true },
	speedPct = { label = "Speed", pct = true },
	staminaPct = { label = "Flight Stamina", pct = true },
	flightSpeedPct = { label = "Flight Speed", pct = true },
	hungerPct = { label = "Slower Hunger", pct = true },
	dodge = { label = "Dodge Chance", pct = true },
	lifesteal = { label = "Lifesteal", pct = true },
	regen = { label = "Max Health regenerated per second", pct = true },
	cooldownPct = { label = "Cooldown Reduction", pct = true },
	breathPct = { label = "Breath Damage", pct = true },
	fireballPct = { label = "Fireball Damage", pct = true },
	abilityPct = { label = "Ability Damage", pct = true },
	poisonPct = { label = "Breath Poison (extra damage over time)", pct = true },
	burnPct = { label = "Breath Burn (extra damage over time)", pct = true },
	slowPct = { label = "Breath Slow", pct = true },
	executePct = { label = "Damage to enemies below 30% health", pct = true },
	bossPct = { label = "Damage to Bosses", pct = true },
	pvpPct = { label = "Damage to Dragons (PvP)", pct = true },
	thorns = { label = "Melee Damage Reflected", pct = true },
	goldPct = { label = "Gold Found", pct = true },
	xpPct = { label = "XP Earned", pct = true },
	lootPct = { label = "Better Loot Chance", pct = true },
	cheatDeath = { label = "Cheat Death", pct = false },
}

local ADDITIVE_KEYS = {
	"attackPct", "healthPct", "defensePct", "critChance", "critDamage", "speedPct", "staminaPct",
	"dodge", "lifesteal", "regen", "cooldownPct", "breathPct", "fireballPct", "abilityPct",
	"poisonPct", "burnPct", "slowPct", "executePct", "bossPct", "pvpPct", "thorns",
	"goldPct", "xpPct", "lootPct", "cheatDeath", "flightSpeedPct", "hungerPct",
}

local CAPS = { dodge = 50, cooldownPct = 40, critChance = 75, lifesteal = 30, hungerPct = 80 }

-- equipped: { [slot] = itemRecord }, talents: { [talentId] = rank },
-- buffs: { { stats = {...} } } (ability buffs, potions, pets and hunger all come in this way)
function StatCalc.compute(classId: string, level: number, equipped, talents, buffs)
	local class = Classes.get(classId) or Classes.get("Shadowstalker")
	local base = class.stats
	local lv = math.max(1, level) - 1

	local s = {
		classId = class.id,
		level = level,
		maxHealth = base.health + base.healthPerLevel * lv,
		attack = base.attack + base.attackPerLevel * lv,
		defense = base.defense + base.defensePerLevel * lv,
		speed = base.speed,
		stamina = base.stamina,
		abilities = { "Breath", "Fireball" },
		abilityMods = {},
	}
	for _, k in ipairs(ADDITIVE_KEYS) do
		s[k] = 0
	end
	s.critChance = base.crit
	s.critDamage = base.critDamage

	-- Gear: flat stats
	local gearSpeedPct = 0
	for _, item in pairs(equipped or {}) do
		local st = ItemUtil.getStats(item)
		s.attack += st.attack or 0
		s.maxHealth += st.health or 0
		s.defense += st.defense or 0
		s.critChance += st.crit or 0
		gearSpeedPct += st.speed or 0
	end
	s.speedPct += gearSpeedPct

	-- Talents
	local branchOrder = {}
	for talentId, rank in pairs(talents or {}) do
		local talent = Talents.byId[talentId]
		if talent and talent.classId == class.id and rank > 0 then
			rank = math.min(rank, talent.maxRank)
			local scale = Tuning.talent(talent.id)
			for stat, perRank in pairs(talent.effects) do
				s[stat] = (s[stat] or 0) + perRank * rank * scale
			end
			if talent.ability then
				table.insert(branchOrder, talent)
			end
			if talent.mods then
				for abilityId, mod in pairs(talent.mods) do
					local target = s.abilityMods[abilityId] or {}
					for k, v in pairs(mod) do
						target[k] = (target[k] or 0) + v * rank
					end
					s.abilityMods[abilityId] = target
				end
			end
		end
	end
	-- Unlocked abilities in a stable order: by branch, then tier.
	table.sort(branchOrder, function(a, b)
		if a.branch ~= b.branch then
			return a.branch < b.branch
		end
		return a.tier < b.tier
	end)
	if class.signature and level >= Game.SIGNATURE_LEVEL then
		table.insert(s.abilities, class.signature)
	end
	for _, talent in ipairs(branchOrder) do
		table.insert(s.abilities, talent.ability)
	end

	-- Buffs
	for _, buff in ipairs(buffs or {}) do
		for stat, v in pairs(buff.stats or {}) do
			s[stat] = (s[stat] or 0) + v
		end
	end

	-- Apply percentages
	s.maxHealth = math.floor(s.maxHealth * (1 + s.healthPct / 100))
	s.attack = s.attack * (1 + s.attackPct / 100)
	s.defense = s.defense * (1 + s.defensePct / 100)
	s.speed = s.speed * (1 + s.speedPct / 100)
	s.stamina = s.stamina * (1 + s.staminaPct / 100)

	for k, cap in pairs(CAPS) do
		s[k] = math.min(s[k], cap)
	end
	return s
end

-- Estimated damage per second, used to scale bosses to the group fighting them.
function StatCalc.dps(stats): number
	local critFactor = 1 + math.min(stats.critChance, 75) / 100 * (stats.critDamage / 100 - 1)
	return stats.attack * critFactor * 3
end

-- A simple "power level" number to show players.
function StatCalc.power(stats): number
	return math.floor(StatCalc.dps(stats) * 2 + stats.maxHealth * 0.2 + stats.defense * 2)
end

local function copyTable(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

-- Final numbers for one ability after class, talents and stats are applied.
function StatCalc.resolveAbility(abilityId: string, classId: string, stats)
	local base = Abilities.get(abilityId)
	if not base then
		return nil
	end
	local a = copyTable(base)
	a.effects = copyTable(base.effects or {})
	local dmgPct = stats.abilityPct

	if a.kind == "breath" then
		local class = Classes.get(classId)
		local cb = class and class.breath or {}
		a.range = cb.range or 24
		a.angle = cb.angle or 30
		a.cooldown = cb.cooldown or 0.5
		a.mult = cb.mult or 1
		a.critBonus = cb.critBonus or 0
		a.effects.slowPct = (cb.slowPct or 0) + stats.slowPct
		a.effects.slowDuration = cb.slowDuration or 2
		a.effects.poisonPct = (cb.poisonPct or 0) + stats.poisonPct
		a.effects.burnPct = stats.burnPct
		a.effects.knockback = cb.knockback
		dmgPct = stats.breathPct
	elseif abilityId == "Fireball" then
		dmgPct = stats.fireballPct
	end

	local mods = stats.abilityMods[abilityId] or {}
	dmgPct += mods.dmgPct or 0
	local tuneDmg, tuneCd = Tuning.ability(abilityId)
	a.damageMult = (a.mult or 0) * (1 + dmgPct / 100) * tuneDmg

	local cd = (a.cooldown or 1) * tuneCd
	if a.kind ~= "breath" then
		cd = cd * (1 - stats.cooldownPct / 100)
	end
	cd += mods.cdFlat or 0
	a.cooldown = math.max(cd, (base.cooldown or cd) * 0.3 * tuneCd, 0.2)

	if a.radius and mods.radiusPct then
		a.radius *= 1 + mods.radiusPct / 100
	end
	if a.duration and mods.durFlat then
		a.duration += mods.durFlat
	end
	if mods.stunFlat then
		a.effects.stun = (a.effects.stun or 0) + mods.stunFlat
	end
	if mods.healPct then
		a.healPct = (a.healPct or 0) + mods.healPct
	end
	return a
end

return StatCalc
