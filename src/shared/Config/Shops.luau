-- Limited stock at three town vendors: the Emberforge Armory (gear), Nestmother's Hatchery
-- (eggs) and the Bubbling Cauldron (potions). Every RESTOCK_SECONDS all three restock at once
-- (one clock for the whole server, shown as a countdown) with random items in random amounts.
--
-- Stock is per player: buying something never empties the shelf for your friends. It's saved
-- with your profile, so rejoining doesn't reroll it. The Robux "Restock now" rerolls it early.

local Shops = {}

Shops.RESTOCK_SECONDS = 5 * 60

-- Gear: `count` different items, each a random slot and rarity at your level. There's always
-- at least `minEpic` Epic item.
Shops.Gear = {
	count = { 6, 8 },
	rarityWeights = { Common = 40, Uncommon = 33, Rare = 20, Epic = 7 },
	amount = { Common = { 1, 3 }, Uncommon = { 1, 2 }, Rare = { 1, 1 }, Epic = { 1, 1 } },
	minEpic = 1,
}

-- Eggs: each egg shows up with `chance`, in `amount` copies. (Mythic eggs are never sold.)
Shops.Eggs = {
	EmberEgg = { chance = 1, amount = { 2, 5 } },
	StormEgg = { chance = 0.6, amount = { 1, 2 } },
}

-- Potions: `count` different potions in stock (never ones you've fully brewed), `amount` ranks
-- of each.
Shops.Potions = {
	count = { 3, 5 },
	amount = { 1, 2 },
}

return Shops
