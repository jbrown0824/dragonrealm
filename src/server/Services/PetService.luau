-- Eggs and nano dragon pets. Buy eggs at Nestmother's Hatchery (or find them), hatch them for a
-- random pet, and equip up to Game.petSlots(level) pets. Equipped pets follow you around (drawn
-- by each client from the "Pets" attribute on your character) and boost your stats.
-- Pets level up on Pet Treats (from harvesting flowers), and three of a species merge into a
-- ✨ Golden one.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Pets = require(Shared.Config.Pets)
local BonusUtil = require(Shared.BonusUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local PetService = {}
local S

-- Tell every client which pets follow this dragon: "species:level:golden" entries, comma-separated.
function PetService.applyToCharacter(player: Player, character: Model?)
	character = character or player.Character
	local profile = S.PlayerService.getProfile(player)
	if not character or not profile then
		return
	end
	local ids = {}
	for _, pet in ipairs(BonusUtil.activePets(profile)) do
		table.insert(ids, string.format("%s:%d:%d", pet.species, pet.level or 1, pet.golden and 1 or 0))
	end
	character:SetAttribute("Pets", table.concat(ids, ","))
end

local function changed(player: Player)
	S.PlayerService.recompute(player)
	PetService.applyToCharacter(player)
	S.PlayerService.markDirty(player)
end

function PetService.addEgg(player: Player, eggId: string, count: number?)
	local profile = S.PlayerService.getProfile(player)
	local egg = Pets.Eggs[eggId]
	if not profile or not egg then
		return
	end
	profile.eggs[eggId] = (profile.eggs[eggId] or 0) + (count or 1)
	S.PlayerService.notify(player, string.format("You got a %s %s! Hatch it from the Pets menu (P).", egg.icon, egg.name), egg.color, "🥚")
	S.PlayerService.markDirty(player)
end

local function rollSpecies(eggId: string): string?
	local egg = Pets.Eggs[eggId]
	local rarity = egg and Util.weightedPick(egg.weights)
	local list = rarity and Pets.speciesOfRarity(rarity)
	if not list or #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function onBuyEgg(player: Player, eggId)
	local egg = type(eggId) == "string" and Pets.Eggs[eggId]
	if not egg or not egg.price then
		return false, "That egg isn't for sale."
	end
	if not S.ShopService.isNear(player, { "Hatchery" }) then
		return false, "Visit Nestmother's Hatchery in town to buy eggs."
	end
	if not S.PlayerService.spendGold(player, egg.price) then
		return false, string.format("You need %s gold.", Util.formatNumber(egg.price))
	end
	local profile = S.PlayerService.getProfile(player)
	profile.eggs[eggId] = (profile.eggs[eggId] or 0) + 1
	S.PlayerService.markDirty(player)
	return true
end

local function onHatch(player: Player, eggId)
	local profile = S.PlayerService.getProfile(player)
	if not profile or type(eggId) ~= "string" or (profile.eggs[eggId] or 0) <= 0 then
		return false, "You don't have that egg."
	end
	if #profile.pets >= Game.PET_LIMIT then
		return false, string.format("Your nest is full (%d pets). Release a pet first.", Game.PET_LIMIT)
	end
	local species = rollSpecies(eggId)
	if not species then
		return false, "The egg wobbled but didn't hatch. Try again."
	end
	profile.eggs[eggId] -= 1
	if profile.eggs[eggId] <= 0 then
		profile.eggs[eggId] = nil
	end
	profile.petCounter += 1
	local pet = { uid = "p" .. profile.petCounter .. "_" .. HttpService:GenerateGUID(false):sub(1, 6), species = species }
	table.insert(profile.pets, pet)
	-- Auto-equip into a free slot so new players see their first pet right away.
	if #profile.petsEquipped < Game.petSlots(profile.level) then
		table.insert(profile.petsEquipped, pet.uid)
	end
	S.QuestService.progress(player, "hatch", species, 1)
	changed(player)
	local info = Pets.get(species)
	if info.rarity == "Legendary" or info.rarity == "Epic" then
		Remotes.event("Announce"):FireAllClients({
			title = "🐲 " .. info.rarity:upper() .. " HATCH!",
			text = string.format("%s hatched a %s!", player.DisplayName, info.name),
			color = Pets.RarityColors[info.rarity],
			duration = 4,
		})
	end
	return true, pet
end

local function onEquip(player: Player, uid)
	local profile = S.PlayerService.getProfile(player)
	if not profile or type(uid) ~= "string" or not BonusUtil.findPet(profile, uid) then
		return false, "Pet not found."
	end
	if table.find(profile.petsEquipped, uid) then
		return true
	end
	-- Drop pets that no longer fit (e.g. after an admin level change), then check for room.
	while #profile.petsEquipped > Game.petSlots(profile.level) do
		table.remove(profile.petsEquipped)
	end
	if #profile.petsEquipped >= Game.petSlots(profile.level) then
		local nextLevel = Game.PET_SLOT_LEVELS[#profile.petsEquipped + 1]
		return false, nextLevel and string.format("All pet slots are full. You get another slot at level %d.", nextLevel) or "All pet slots are full. Unequip a pet first."
	end
	table.insert(profile.petsEquipped, uid)
	changed(player)
	return true
end

-- Let your best pets (by rarity, then boosts) follow you.
local function onEquipBest(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile or #profile.pets == 0 then
		return false, "You don't have any pets yet. Hatch an egg first!"
	end
	profile.petsEquipped = BonusUtil.bestPets(profile)
	changed(player)
	return true
end

local function onUnequip(player: Player, uid)
	local profile = S.PlayerService.getProfile(player)
	local i = profile and type(uid) == "string" and table.find(profile.petsEquipped, uid)
	if not i then
		return false
	end
	table.remove(profile.petsEquipped, i)
	changed(player)
	return true
end

local function onRelease(player: Player, uid)
	local profile = S.PlayerService.getProfile(player)
	local pet, index = nil, nil
	if profile and type(uid) == "string" then
		pet, index = BonusUtil.findPet(profile, uid)
	end
	if not pet then
		return false, "Pet not found."
	end
	table.remove(profile.pets, index)
	local eq = table.find(profile.petsEquipped, uid)
	if eq then
		table.remove(profile.petsEquipped, eq)
	end
	local info = Pets.get(pet.species)
	local base = Pets.ReleaseGold[info and info.rarity or "Common"] or 50
	local gold = S.PlayerService.addGold(player, math.floor(base * Pets.multiplier(pet.level, pet.golden)))
	changed(player)
	return true, gold
end

-- Feed a pet enough treats for its next level.
local function onFeed(player: Player, uid)
	local profile = S.PlayerService.getProfile(player)
	local pet = profile and type(uid) == "string" and BonusUtil.findPet(profile, uid)
	if not pet then
		return false, "Pet not found."
	end
	local level = pet.level or 1
	local cost = Pets.LEVEL_COSTS[level]
	if not cost then
		return false, "This pet is already at max level!"
	end
	if (profile.treats or 0) < cost then
		return false, string.format("You need %d 🍬 Pet Treats. Harvest full-grown flowers to find them.", cost)
	end
	profile.treats -= cost
	pet.level = level + 1
	changed(player)
	return true, pet.level
end

-- Merge the chosen pet with two more of the same species (not golden) into one Golden pet.
-- The golden pet keeps the highest level of the three and whichever of them was following you.
local function onMerge(player: Player, uid)
	local profile = S.PlayerService.getProfile(player)
	local pet = profile and type(uid) == "string" and BonusUtil.findPet(profile, uid)
	if not pet then
		return false, "Pet not found."
	end
	if pet.golden then
		return false, "This pet is already golden!"
	end
	local others = {}
	for _, other in ipairs(profile.pets) do
		if other ~= pet and other.species == pet.species and not other.golden then
			table.insert(others, other)
		end
	end
	if #others < Pets.MERGE_COUNT - 1 then
		return false, string.format("You need %d %s pets to merge.", Pets.MERGE_COUNT, Pets.get(pet.species).name)
	end
	-- Use up the lowest-level extras first.
	table.sort(others, function(a, b)
		return (a.level or 1) < (b.level or 1)
	end)
	local info = Pets.get(pet.species)
	local cost = Pets.MergeGold[info.rarity] or 100
	if not S.PlayerService.spendGold(player, cost) then
		return false, string.format("Merging costs %s gold.", Util.formatNumber(cost))
	end
	local wasEquipped = table.find(profile.petsEquipped, pet.uid) ~= nil
	local best = pet.level or 1
	for i = 1, Pets.MERGE_COUNT - 1 do
		local other = others[i]
		best = math.max(best, other.level or 1)
		wasEquipped = wasEquipped or table.find(profile.petsEquipped, other.uid) ~= nil
		local _, index = BonusUtil.findPet(profile, other.uid)
		table.remove(profile.pets, index)
		local eq = table.find(profile.petsEquipped, other.uid)
		if eq then
			table.remove(profile.petsEquipped, eq)
		end
	end
	pet.golden = true
	pet.level = best
	if wasEquipped and not table.find(profile.petsEquipped, pet.uid) then
		table.insert(profile.petsEquipped, pet.uid)
	end
	changed(player)
	if info.rarity == "Legendary" or info.rarity == "Epic" then
		Remotes.event("Announce"):FireAllClients({
			title = "✨ GOLDEN " .. info.rarity:upper() .. "!",
			text = string.format("%s merged a Golden %s!", player.DisplayName, info.name),
			color = Color3.fromRGB(255, 210, 70),
			duration = 4,
		})
	end
	return true, pet
end

function PetService.init(services)
	S = services
end

function PetService.start()
	Remotes.func("BuyEgg").OnServerInvoke = onBuyEgg
	Remotes.func("HatchEgg").OnServerInvoke = onHatch
	Remotes.func("EquipPet").OnServerInvoke = onEquip
	Remotes.func("UnequipPet").OnServerInvoke = onUnequip
	Remotes.func("EquipBestPets").OnServerInvoke = onEquipBest
	Remotes.func("ReleasePet").OnServerInvoke = onRelease
	Remotes.func("FeedPet").OnServerInvoke = onFeed
	Remotes.func("MergePets").OnServerInvoke = onMerge
end

return PetService
