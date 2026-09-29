-- Night raids on Dragon Town (server/Services/RaidService). When night falls there's a CHANCE of
-- a raid, and after PITY_NIGHTS nights in a row without one the next night always brings one.
-- Longships row down the river and run aground below town; waves of vikings march in,
-- Torchbearers set houses alight, and the villagers (brave, but not very strong) join the fight.
--   Repelled: every raider is beaten before dawn. Everyone who helped (hit a raider or put out a
--             fire) gets the Rewards.
--   Lost:     dawn comes with raiders still in town, or MAX_BURNED houses burn down. The raiders
--             loot the market and every shop stays shut for SHOPS_CLOSED seconds.
-- Burned houses are rebuilt REBUILD seconds after the raid, win or lose.

local Raids = {}

Raids.CHANCE = 1 / 3
Raids.PITY_NIGHTS = 5 -- nights in a row without a raid before one is guaranteed
Raids.WARNING = 20 -- seconds from the war horn to the first wave coming ashore
Raids.WAVE_GAP = 40 -- seconds between waves
Raids.MAX_BURNED = 5 -- the village falls when this many houses have burned down
Raids.SHOPS_CLOSED = 180
Raids.REBUILD = 150

-- Raiders are around the level of the dragons online (their average, minus LEVEL_BELOW).
Raids.LEVEL_BELOW = 1
Raids.LEVEL_RANGE = { 1, 26 }
Raids.EXTRA_PER_PLAYER = 0.5 -- every dragon online past the first adds half as many raiders again
Raids.MAX_SCALE = 3 -- ...up to this many times the numbers below

-- Each wave: how many of each viking come ashore (for one dragon online). `leader` adds the Raid
-- Captain, a big Chieftain with a telegraphed slam.
Raids.Waves = {
	{ Raider = 3, Torchbearer = 2 },
	{ Raider = 2, AxeThrower = 2, Torchbearer = 2 },
	{ Berserker = 2, Torchbearer = 2, leader = true },
}
Raids.Captain = {
	base = "Chieftain", name = "Raid Captain", scale = 1.55,
	healthMult = 2.5, healthPerPlayer = 0.75, damageMult = 1.1,
	slam = { radius = 13, mult = 1.7, cooldown = 9, delay = 1.4 },
	look = { shirt = Color3.fromRGB(60, 40, 30), pants = Color3.fromRGB(40, 30, 25), beard = Color3.fromRGB(30, 25, 20), weapon = "greatAxe", shield = true, cape = Color3.fromRGB(30, 30, 35), crown = true, warpaint = true },
}

-- Houses
Raids.TORCH_TIME = 3 -- seconds a Torchbearer stands at a door to set the house alight
Raids.BURN_TIME = 45 -- a burning house burns down after this long unless someone puts it out
Raids.DOUSE_HOLD = 2 -- hold E at the door this long to beat out the flames

-- Villagers join the fight: they puff small bursts of fire at raiders near them. They wear
-- raiders down but can't finish them (never below VILLAGER_FLOOR of their health), so a raid is
-- never won without dragons.
Raids.VILLAGER_DAMAGE = 0.04 -- share of the raider's max health per puff
Raids.VILLAGER_FLOOR = 0.3
Raids.VILLAGER_INTERVAL = 2.5
Raids.VILLAGER_RANGE = 18
Raids.VILLAGER_LINES = { "For the village!", "Get out of our town!", "Not my garden!", "Shoo! Shoo!" }

-- For everyone who helped repel a raid.
Raids.Rewards = {
	xpShare = 0.3, -- of the XP you need for your next level (or Paragon level)
	gold = { base = 60, perLevel = 15 },
	gearChance = 0.6, gearRarity = "Rare",
	eggChance = 0.2,
	treats = 2,
}

-- Where the longships run aground: they row along the river from x = `fromX` (the west one out
-- of the fjord channel from the Fishing Village) to `shipX` (clear of the bridge), and the raiders
-- jump off onto the beach at `shore`. From there they join the villagers' walking graph
-- (Zones.TownWalk) at ENTRY_NODE to find their way between the houses.
Raids.Landings = {
	{ shipX = -52, fromX = -446, shore = Vector3.new(-40, 0, 244) },
	{ shipX = 52, fromX = 330, shore = Vector3.new(40, 0, 244) },
}
Raids.ENTRY_NODE = "N4"
Raids.SHIP_ROW_TIME = 18 -- seconds the longships take to row in (inside the WARNING)

return Raids
