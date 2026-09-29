-- The 💎 Store: Robux game passes and developer products (StoreService, UI/Store).
--
-- SETUP, once per game, in the Creator Dashboard (create.roblox.com > your game > Monetization):
--   1. Create the two Game Passes below and paste each one's id into `assetId`.
--   2. Create a Developer Product for each entry in Products and paste its id into `productId`.
--   3. Set their prices to the `robux` shown here (the Store shows these numbers; Roblox charges
--      whatever the dashboard says, so keep them the same).
-- Until an id is filled in, the item still shows in the Store. In Studio, "Buy" on an item with
-- no id grants it for free so you can test; in a live game it says the item is coming soon.

local Store = {}

Store.STARTER_MAX_LEVEL = 10 -- the Starter Pack is offered, and advertised on screen, below this level
Store.GOLD_RUSH_BONUS = 1 -- +100% gold while a Gold Rush lasts (added to the 2x Gold pass: 3x with both)
Store.GOLD_RUSH_MAX_MINUTES = 300 -- a Gold Rush can't stack past this much time

Store.PassOrder = { "DoubleXP", "DoubleGold" }
Store.Passes = {
	DoubleXP = { assetId = 0, name = "2x XP", icon = "📘", robux = 199,
		desc = "Double XP from everything, forever. Level up (and earn Paragon levels) twice as fast." },
	DoubleGold = { assetId = 0, name = "2x Gold", icon = "💰", robux = 199,
		desc = "Double the gold you earn from vikings, quests, chests, harvests and battles, forever." },
}

Store.ProductOrder = { "StarterPack", "GoldRush", "GoldSmall", "GoldMedium", "GoldLarge", "SecretEgg", "TreatBag", "Restock" }
Store.Products = {
	-- the cheap one: a short boost you feel right away (its clock only runs while you play)
	GoldRush = { productId = 0, name = "Gold Rush", icon = "💸", robux = 9, goldRushMinutes = 30,
		desc = "+100% gold for 30 minutes of play (the clock only runs while you're in the game). Stacks with 2x Gold. Buy more to add time." },
	StarterPack = { productId = 0, name = "Starter Pack", icon = "🎁", robux = 49, once = true,
		desc = "A head start for new dragons: an hour's worth of gold, 2 Storm Eggs, 30 Pet Treats, an Epic piece of gear and the Sunrise skin.",
		goldMinutes = 60, eggs = { StormEgg = 2 }, treats = 30, epicGear = true, skin = "Sunrise" },
	GoldSmall = { productId = 0, name = "Pouch of Gold", icon = "💰", robux = 25, goldMinutes = 20,
		desc = "About 20 minutes of adventuring's worth of gold." },
	GoldMedium = { productId = 0, name = "Chest of Gold", icon = "💰", robux = 99, goldMinutes = 100,
		desc = "About 1.5 hours of adventuring's worth of gold." },
	GoldLarge = { productId = 0, name = "Dragon's Hoard", icon = "💰", robux = 399, goldMinutes = 500,
		desc = "About 8 hours of adventuring's worth of gold." },
	SecretEgg = { productId = 0, name = "Secret Egg", icon = "🔮", robux = 149, eggs = { SecretEgg = 1 },
		desc = "Hatches one of three Secret nano dragons you can't get anywhere else." },
	TreatBag = { productId = 0, name = "Bag of Treats", icon = "🍬", robux = 29, treats = 40,
		desc = "40 Pet Treats to level up your nano dragons." },
	Restock = { productId = 0, name = "Restock Shops", icon = "🔄", robux = 15, restock = true,
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

function Store.productByAssetId(productId: number): string?
	for key, product in pairs(Store.Products) do
		if product.productId ~= 0 and product.productId == productId then
			return key
		end
	end
	return nil
end

return Store
