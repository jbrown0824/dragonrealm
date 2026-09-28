-- Stat bonuses that don't come from gear or talents: potions, equipped pets and hunger.
-- Returned as StatCalc buff entries ({ stats = {...} }) so server and client agree.

local Config = script.Parent.Config
local Game = require(Config.Game)
local Potions = require(Config.Potions)
local Pets = require(Config.Pets)

local BonusUtil = {}

local function add(into, stats, times: number?)
	for stat, v in pairs(stats) do
		into[stat] = (into[stat] or 0) + v * (times or 1)
	end
end

function BonusUtil.potionStats(potions)
	local total = {}
	for id, rank in pairs(potions or {}) do
		local p = Potions.get(id)
		if p and rank > 0 then
			add(total, p.stats, math.min(rank, Potions.maxRank()))
		end
	end
	return total
end

function BonusUtil.findPet(profile, uid: string)
	for i, pet in ipairs(profile.pets or {}) do
		if pet.uid == uid then
			return pet, i
		end
	end
	return nil
end

-- Pets actually following you (respects the slot count for your level).
function BonusUtil.activePets(profile)
	local list = {}
	local slots = Game.petSlots(profile.level or 1)
	for _, uid in ipairs(profile.petsEquipped or {}) do
		local pet = BonusUtil.findPet(profile, uid)
		if pet and Pets.get(pet.species) and #list < slots then
			table.insert(list, pet)
		end
	end
	return list
end

-- A pet's boosts after its level and golden bonus.
function BonusUtil.petBoosts(pet)
	local species = Pets.get(pet.species)
	local out = {}
	if species then
		local mult = Pets.multiplier(pet.level, pet.golden)
		for stat, v in pairs(species.stats) do
			out[stat] = v * mult
		end
	end
	return out
end

-- One number to rank pets by: how much their (levelled, golden) boosts add up to, with rarity
-- breaking ties.
function BonusUtil.petScore(pet): number
	local species = Pets.get(pet.species)
	if not species then
		return 0
	end
	local total = 0
	for _, v in pairs(BonusUtil.petBoosts(pet)) do
		total += v
	end
	return total * 10 + (table.find(Pets.RarityOrder, species.rarity) or 0)
end

-- The uids of your best pets, as many as you have slots for.
function BonusUtil.bestPets(profile)
	local list = table.clone(profile.pets or {})
	table.sort(list, function(a, b)
		return BonusUtil.petScore(a) > BonusUtil.petScore(b)
	end)
	local uids = {}
	for i = 1, math.min(#list, Game.petSlots(profile.level or 1)) do
		table.insert(uids, list[i].uid)
	end
	return uids
end

function BonusUtil.petStats(profile)
	local total = {}
	for _, pet in ipairs(BonusUtil.activePets(profile)) do
		add(total, BonusUtil.petBoosts(pet))
	end
	return total
end

-- Every non-gear, non-talent bonus as StatCalc buff entries.
function BonusUtil.entries(profile)
	local list = {}
	table.insert(list, { stats = BonusUtil.potionStats(profile.potions) })
	table.insert(list, { stats = BonusUtil.petStats(profile) })
	local hungry = Game.hungerLevel(profile.hunger or Game.HUNGER_MAX)
	if hungry then
		table.insert(list, { stats = hungry.stats })
	end
	return list
end

return BonusUtil
