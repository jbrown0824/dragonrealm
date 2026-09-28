-- Skill tree rules shared by the server (validation) and the client (UI).

local Config = script.Parent.Config
local Game = require(Config.Game)
local Talents = require(Config.Talents)
local Abilities = require(Config.Abilities)
local StatCalc = require(script.Parent.StatCalc)
local Util = require(script.Parent.Util)
local Tuning = require(script.Parent.Tuning)

local TalentUtil = {}

function TalentUtil.totalPoints(level: number): number
	return math.max(0, level - 1)
end

function TalentUtil.spent(talents): number
	local n = 0
	for _, rank in pairs(talents or {}) do
		n += rank
	end
	return n
end

function TalentUtil.available(level: number, talents): number
	return TalentUtil.totalPoints(level) - TalentUtil.spent(talents)
end

function TalentUtil.spentInBranch(talents, classId: string, branchIndex: number): number
	local n = 0
	for talentId, rank in pairs(talents or {}) do
		local t = Talents.byId[talentId]
		if t and t.classId == classId and t.branch == branchIndex then
			n += rank
		end
	end
	return n
end

function TalentUtil.tierRequirement(tier: number): number
	return (tier - 1) * Game.TALENT_POINTS_PER_TIER
end

-- Returns ok, reason
function TalentUtil.canLearn(classId: string, level: number, talents, talentId: string)
	local t = Talents.byId[talentId]
	if not t or t.classId ~= classId then
		return false, "That skill isn't in your tree."
	end
	local rank = talents[talentId] or 0
	if rank >= t.maxRank then
		return false, "Already maxed."
	end
	if TalentUtil.available(level, talents) <= 0 then
		return false, "No skill points left. Level up to earn more!"
	end
	local need = TalentUtil.tierRequirement(t.tier)
	local have = TalentUtil.spentInBranch(talents, classId, t.branch)
	if have < need then
		return false, string.format("Spend %d points in %s to unlock this tier.", need, Talents[classId][t.branch].name)
	end
	if t.requires then
		local reqId = classId .. "." .. t.requires
		local req = Talents.byId[reqId]
		if req and (talents[reqId] or 0) < req.maxRank then
			return false, "Requires " .. req.name .. "."
		end
	end
	return true
end

-- Spend as many points as possible down one branch: each tier's skills are filled (left, then
-- right) before moving on, and passes repeat because filling a tier unlocks the next.
-- Changes `talents` in place and returns how many ranks were learned.
function TalentUtil.autoFill(classId: string, level: number, talents, branchIndex: number): number
	local branch = Talents[classId] and Talents[classId][branchIndex]
	if not branch then
		return 0
	end
	local order = table.clone(branch.talents)
	table.sort(order, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.col < b.col
	end)
	local learned = 0
	local progress = true
	while progress do
		progress = false
		for _, t in ipairs(order) do
			while TalentUtil.canLearn(classId, level, talents, t.id) do
				talents[t.id] = (talents[t.id] or 0) + 1
				learned += 1
				progress = true
			end
		end
	end
	return learned
end

function TalentUtil.respecCost(level: number): number
	return Game.RESPEC_COST_PER_LEVEL * level
end

local function effectLine(stat: string, value: number): string
	local info = StatCalc.STAT_INFO[stat]
	if not info then
		return string.format("+%s %s", Util.fmt(value), stat)
	end
	if stat == "cheatDeath" then
		return "Cheat death"
	end
	if info.pct then
		return string.format("+%s%% %s", Util.fmt(value), info.label)
	end
	return string.format("+%s %s", Util.fmt(value), info.label)
end

local MOD_LABELS = {
	dmgPct = function(v) return string.format("+%s%% damage", Util.fmt(v)) end,
	cdFlat = function(v) return string.format("%ss cooldown", Util.fmt(v)) end,
	radiusPct = function(v) return string.format("+%s%% area", Util.fmt(v)) end,
	durFlat = function(v) return string.format("+%ss duration", Util.fmt(v)) end,
	stunFlat = function(v) return string.format("+%ss freeze/stun", Util.fmt(v)) end,
	healPct = function(v) return string.format("+%s%% healing", Util.fmt(v)) end,
}

-- Human readable description of a talent at a given rank (rank >= 1).
function TalentUtil.describe(talent, rank: number): string
	rank = math.max(rank, 1)
	if talent.ability then
		local a = Abilities.get(talent.ability)
		local kind = a and a.ultimate and "ULTIMATE" or "ABILITY"
		return string.format("[%s] %s", kind, a and a.desc or talent.ability)
	end
	if talent.desc then
		return talent.desc
	end
	local parts = {}
	local keys = {}
	for stat in pairs(talent.effects) do
		table.insert(keys, stat)
	end
	table.sort(keys)
	local scale = Tuning.talent(talent.id)
	for _, stat in ipairs(keys) do
		table.insert(parts, effectLine(stat, talent.effects[stat] * rank * scale))
	end
	if talent.mods then
		for abilityId, mod in pairs(talent.mods) do
			local a = Abilities.get(abilityId)
			local modParts = {}
			for k, v in pairs(mod) do
				local f = MOD_LABELS[k]
				if f then
					table.insert(modParts, f(v * rank))
				end
			end
			table.sort(modParts)
			table.insert(parts, string.format("%s: %s", a and a.name or abilityId, table.concat(modParts, ", ")))
		end
	end
	return table.concat(parts, "\n")
end

return TalentUtil
