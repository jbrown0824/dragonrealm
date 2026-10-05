-- The 💎 Store: Robux game passes and developer products (StoreService, UI/Store).
--
-- SETUP, once per game, in the Creator Dashboard (create.roblox.com > your game > Monetization):
--   1. Create the Game Passes below (the legendary dragons too) and paste each one's id into `assetId`.
--   2. Create a Developer Product for each entry in Products and paste its id into `productId`.
--   3. Set their prices to the `robux` shown here (the Store shows these numbers; Roblox charges
--      whatever the dashboard says, so keep them the same).
-- Until an id is filled in, the item still shows in the Store. In Studio, "Buy" on an item with
-- no id grants it for free so you can test; in a live game it says the item is coming soon.
--
-- PAID RANDOM ITEMS: eggs hatch a random pet, and they can be bought with Robux (the Mythic and
-- Secret Eggs, the Starter Pack's eggs) or with gold, which Robux can buy too. Where the law
-- restricts that (PolicyService's ArePaidRandomItemsRestricted, checked by StoreService when a
-- player joins), everything marked `paidRandom` is off the shelf: the eggs, and every way to turn
-- Robux into gold (gold packs, the Gold Rush, 2x Gold, the Starter Pack) or into more egg stock
-- (Restock). Those players still hatch eggs with gold they earn by playing. They get their own
-- Starter Pack instead (`restrictedOnly`): one particular pet, nothing random and no gold. That
-- pet is marked `bought` and releases for no gold, so it can't be turned into gold for eggs.

local Store = {}

Store.STARTER_MAX_LEVEL = 10 -- the Starter Pack is offered, and advertised on screen, below this level
Store.GOLD_RUSH_BONUS = 1 -- +100% gold while a Gold Rush lasts (added to the 2x Gold pass: 3x with both)
Store.GOLD_RUSH_MAX_MINUTES = 300 -- a Gold Rush can't stack past this much time

-- Passes are forever. `handy` ones are quality-of-life (the Store lists them in their own section).
Store.WAYFINDER_COOLDOWN = 20 -- seconds between Wayfinder teleports
Store.FLIGHT_MULT = 2 -- 2x Flight Time: this many times your flight stamina
Store.PassOrder = { "DoubleXP", "DoubleGold", "DoubleFlight", "NeverHungry", "Wayfinder" }
Store.Passes = {
	DoubleXP = { assetId = 2003504534, name = "2x XP", icon = "📘", robux = 199,
		desc = "Double XP from everything, forever. Level up (and earn Paragon levels) twice as fast." },
	DoubleGold = { assetId = 1998225968, paidRandom = true, name = "2x Gold", icon = "💰", robux = 199,
		desc = "Double the gold you earn from vikings, quests, chests, harvests and battles, forever." },
	DoubleFlight = { assetId = 2002460765, name = "2x Flight Time", icon = "🦅", robux = 99, handy = true,
		desc = "Twice the flight stamina, so you stay in the air twice as long. Stacks with Wing Tonic and pets." },
	NeverHungry = { assetId = 2003324547, name = "Never Hungry", icon = "🍖", robux = 79, handy = true,
		desc = "Your dragon is always full: no hunger to watch and never slowed by Hungry or Starving." },
	Wayfinder = { assetId = 2001674828, name = "Wayfinder", icon = "🧭", robux = 149, handy = true,
		desc = "Teleport to any place on the world map (M) with the 🌀 button next to it. Not in combat or boss fights; a short cooldown between jumps." },
}

-- Legendary dragons: a pass per dragon type (Config/Classes `pass`). Owning one unlocks that type
-- for good: choose it, or transform into it for free (Elder Pyrrhus, or its showcase in the town
-- square). Nothing random, so no `paidRandom`.
Store.DragonOrder = { "TidecallerDragon", "SolarisDragon" }
Store.Passes.TidecallerDragon = { assetId = 0, dragon = "Tidecaller", name = "Tidecaller", icon = "🌊", robux = 399,
	desc = "Unlock the Tidecaller, a legendary sea dragon: rapid water shots that reach far, whirlpools, healing tides and a great wave at level 10." }
Store.Passes.SolarisDragon = { assetId = 0, dragon = "Solaris", name = "Solaris", icon = "☀️", robux = 999,
	desc = "Unlock Solaris, the crowned sun dragon: a piercing beam of sunlight, a blazing halo and phoenix plumes, and pillars of sunfire at level 10." }

-- The pass that unlocks a dragon type, or nil.
function Store.passForDragon(classId: string): string?
	for _, key in ipairs(Store.DragonOrder) do
		if Store.Passes[key].dragon == classId then
			return key
		end
	end
	return nil
end

Store.ProductOrder = { "StarterPack", "StarterPet", "GoldRush", "GoldSmall", "GoldMedium", "GoldLarge", "MythicEgg", "SecretEgg", "TreatBag", "Restock" }
Store.Products = {
	-- the cheap one: a short boost you feel right away (its clock only runs while you play)
	GoldRush = { productId = 3715732110, paidRandom = true, name = "Gold Rush", icon = "💸", robux = 9, goldRushMinutes = 30,
		desc = "+100% gold for 30 minutes of play (the clock only runs while you're in the game). Stacks with 2x Gold. Buy more to add time." },
	StarterPack = { productId = 3715731857, paidRandom = true, name = "Starter Pack", icon = "🎁", robux = 49, once = true,
		desc = "A head start for new dragons: an hour's worth of gold, 2 Storm Eggs, 30 Pet Treats, an Epic piece of gear and the Sunrise skin.",
		goldMinutes = 60, eggs = { StormEgg = 2 }, treats = 30, epicGear = true, skin = "Sunrise" },
	-- the Starter Pack where paid random items are restricted: one chosen pet, nothing random
	-- (change `pet` to give a different species or level; keep it a species without goldPct)
	StarterPet = { productId = 3715749854, restrictedOnly = true, name = "Starter Pack", icon = "🎁", robux = 49, once = true,
		desc = "A head start for new dragons: Thunderhatch, an Epic nano dragon that hits harder and flies faster.",
		pet = { species = "Thunderhatch", level = 1 } },
	GoldSmall = { productId = 3715732494, paidRandom = true, name = "Pouch of Gold", icon = "💰", robux = 25, goldMinutes = 20,
		desc = "About 20 minutes of adventuring's worth of gold." },
	GoldMedium = { productId = 3715732588, paidRandom = true, name = "Chest of Gold", icon = "💰", robux = 99, goldMinutes = 100,
		desc = "About 1.5 hours of adventuring's worth of gold." },
	GoldLarge = { productId = 3715733488, paidRandom = true, name = "Dragon's Hoard", icon = "💰", robux = 399, goldMinutes = 500,
		desc = "About 8 hours of adventuring's worth of gold." },
	MythicEgg = { productId = 3715733605, paidRandom = true, name = "Mythic Egg", icon = "🌟", robux = 49, eggs = { MythicEgg = 1 },
		desc = "Always an Epic or Legendary nano dragon, with a 1% chance of the Aurora Serpent. Also found free on champions, bosses and camp chests." },
	SecretEgg = { productId = 3715733640, paidRandom = true, name = "Secret Egg", icon = "🔮", robux = 149, eggs = { SecretEgg = 1 },
		desc = "Hatches one of four Secret nano dragons you can't get anywhere else." },
	TreatBag = { productId = 3715733838, name = "Bag of Treats", icon = "🍬", robux = 29, treats = 40,
		desc = "40 Pet Treats to level up your nano dragons." },
	Restock = { productId = 3715733885, paidRandom = true, name = "Restock Shops", icon = "🔄", robux = 15, restock = true,
		desc = "Fresh stock at the Armory, the Hatchery and the Cauldron, right now." },
}

-- Gold packs are sized by how strong you are, not a fixed number: roughly how much gold a
-- dragon of your level (and Paragon) earns per minute of play. A level 1 dragon and a level 30
-- dragon both get about "20 minutes' worth", which means very different amounts.
function Store.goldPerMinute(level: number, paragon: number?): number
	return 30 * (1 + 0.3 * (level - 1)) * (1 + 0.01 * math.min(paragon or 0, 100))
end

function Store.goldFor(minutes: number, level: number, paragon: number?): number
	local gold = Store.goldPerMinute(level, paragon) * minutes
	-- round to a friendly number
	local step = gold >= 100000 and 5000 or (gold >= 10000 and 500 or 50)
	return math.max(step, math.floor(gold / step + 0.5) * step)
end

-- Is this pass or product for sale to a player? `allowed` is their PaidRandomItems attribute:
-- true where paid random items are allowed, false where they're restricted, nil until we know.
-- `paidRandom` items need true; `restrictedOnly` ones (their stand-ins) need false.
function Store.offered(kind: string, key: string, allowed: boolean?): boolean
	local info = if kind == "pass" then Store.Passes[key] else Store.Products[key]
	if not info then
		return false
	elseif info.paidRandom then
		return allowed == true
	elseif info.restrictedOnly then
		return allowed == false
	end
	return true
end

function Store.productByAssetId(productId: number): string?
	for key, product in pairs(Store.Products) do
		if product.productId ~= 0 and product.productId == productId then
			return key
		end
	end
	return nil
end

return Store
