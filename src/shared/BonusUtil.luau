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

-- One number to rank pets by: rarity first, then how much their boosts add up to.
function BonusUtil.petScore(speciesId: string): number
	local species = Pets.get(speciesId)
	if not species then
		return 0
	end
	local total = 0
	for _, v in pairs(species.stats) do
		total += v
	end
	return (table.find(Pets.RarityOrder, species.rarity) or 0) * 100 + total
end

-- The uids of your best pets, as many as you have slots for.
function BonusUtil.bestPets(profile)
	local list = table.clone(profile.pets or {})
	table.sort(list, function(a, b)
		return BonusUtil.petScore(a.species) > BonusUtil.petScore(b.species)
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
		add(total, Pets.get(pet.species).stats)
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
