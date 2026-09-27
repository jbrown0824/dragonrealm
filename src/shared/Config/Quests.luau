-- Quests offered by the village dragons in town.
-- Each giver offers their quests in order; a quest shows up once its `after` quest is done
-- and you meet `minLevel`. Repeatable quests can be done again after turning them in.
--
-- objective.type:
--   kill (target = viking id or "any")  plant  care  harvest (target = "Flower" or "any")
--   buy  sell  upgrade  pvpKill  bossJoin  bossKill  visitZone (target = zone id)  level
-- rewards: xp, gold, seeds = { SeedId = count }, gear = { rarity = "Epic" } (item level = your level)

local Quests = {}

Quests.MAX_ACTIVE = 5

Quests.Givers = {
	Elder = {
		id = "Elder", name = "Elder Pyrrhus", title = "Keeper of the Flame",
		greeting = "Young one, the vikings grow bolder every day. Our town needs your fire.",
		idle = "Rest a while, then come back to me. There is always more to do.",
		look = "Behemoth",
	},
	Captain = {
		id = "Captain", name = "Captain Ashwing", title = "Guard Captain",
		greeting = "Soldier! Those raiders won't burn themselves. Well... actually they will, if you help.",
		idle = "No new orders right now. Keep your claws sharp.",
		look = "Stormwing",
	},
	Gardener = {
		id = "Gardener", name = "Gardener Fernscale", title = "Keeper of Seeds",
		greeting = "Oh! A new gardener? Every plant needs love... and the right amount of water and sun.",
		idle = "Go tend your garden, dear. Plants don't grow by themselves!",
		look = "Venomspine",
	},
	Scout = {
		id = "Scout", name = "Scout Wren", title = "Adventurer",
		greeting = "Psst! Want to see the most exciting parts of the realm? Battles! Bosses! Glory!",
		idle = "Nothing new to report. I'll let you know when something exciting happens!",
		look = "Shadowstalker",
	},
}

Quests.GiverOrder = { "Elder", "Captain", "Gardener", "Scout" }

Quests.List = {
	---------------------------------------------------------------- Elder (main story)
	{ id = "E1", giver = "Elder", name = "First Flames", minLevel = 1,
		desc = "Cross the bridge south into viking lands and defeat 3 vikings at the Raider Camp.",
		objective = { type = "kill", target = "any", count = 3 },
		rewards = { xp = 120, gold = 60 } },
	{ id = "E2", giver = "Elder", name = "Gear Up", minLevel = 1, after = "E1",
		desc = "Visit the Armory in the town square and buy a piece of gear, then equip it from your Bag.",
		objective = { type = "buy", count = 1 },
		rewards = { xp = 150, gold = 80 } },
	{ id = "E3", giver = "Elder", name = "Raider Trouble", minLevel = 2, after = "E2",
		desc = "Viking Raiders keep burning our crops. Defeat 10 of them.",
		objective = { type = "kill", target = "Raider", count = 10 },
		rewards = { xp = 350, gold = 150 } },
	{ id = "E4", giver = "Elder", name = "Forge Ahead", minLevel = 3, after = "E3",
		desc = "Visit the Anvil of Ages and upgrade any piece of gear.",
		objective = { type = "upgrade", count = 1 },
		rewards = { xp = 400, gold = 200 } },
	{ id = "E5", giver = "Elder", name = "The Fishing Village", minLevel = 6, after = "E4",
		desc = "Axe Throwers guard the fishing village to the west. Defeat 8 of them.",
		objective = { type = "kill", target = "AxeThrower", count = 8 },
		rewards = { xp = 800, gold = 350 } },
	{ id = "E6", giver = "Elder", name = "The Shield Wall", minLevel = 10, after = "E5",
		desc = "Break the Shieldbearers holding the Longhouse Hold. Defeat 10 of them.",
		objective = { type = "kill", target = "Shieldbearer", count = 10 },
		rewards = { xp = 1500, gold = 600 } },
	{ id = "E7", giver = "Elder", name = "Berserker Rage", minLevel = 14, after = "E6",
		desc = "Berserkers are storming out of the Longhouse Hold. Defeat 12 of them.",
		objective = { type = "kill", target = "Berserker", count = 12 },
		rewards = { xp = 2400, gold = 900 } },
	{ id = "E8", giver = "Elder", name = "The Jarl's Champions", minLevel = 19, after = "E7",
		desc = "Storm the Jarl's Fortress and defeat 3 Viking Chieftains.",
		objective = { type = "kill", target = "Chieftain", count = 3 },
		rewards = { xp = 4000, gold = 1600, gear = { rarity = "Epic" } } },
	{ id = "E9", giver = "Elder", name = "Legend of the Realm", minLevel = 15, after = "E8",
		desc = "Answer the war horn and help defeat one of the great viking bosses.",
		objective = { type = "bossKill", count = 1 },
		rewards = { xp = 6000, gold = 3000, gear = { rarity = "Legendary" } } },

	---------------------------------------------------------------- Captain (combat)
	{ id = "C1", giver = "Captain", name = "Scorched Camp", minLevel = 1,
		desc = "Defeat 15 vikings of any kind.",
		objective = { type = "kill", target = "any", count = 15 },
		rewards = { xp = 400, gold = 200 } },
	{ id = "C2", giver = "Captain", name = "Axe Dodger", minLevel = 7, after = "C1",
		desc = "Defeat 12 Axe Throwers. Keep moving so their axes miss!",
		objective = { type = "kill", target = "AxeThrower", count = 12 },
		rewards = { xp = 1000, gold = 450 } },
	{ id = "C3", giver = "Captain", name = "Break Their Shields", minLevel = 12, after = "C2",
		desc = "Defeat 15 Shieldbearers.",
		objective = { type = "kill", target = "Shieldbearer", count = 15 },
		rewards = { xp = 2000, gold = 800, gear = { rarity = "Rare" } } },
	{ id = "C4", giver = "Captain", name = "Bounty: Viking Horde", minLevel = 5, after = "C3", repeatable = true,
		desc = "Standing bounty: defeat 25 vikings. You can take this one again and again.",
		objective = { type = "kill", target = "any", count = 25 },
		rewards = { xp = 1500, gold = 700 } },

	---------------------------------------------------------------- Gardener (farming)
	{ id = "G1", giver = "Gardener", name = "Green Claws", minLevel = 1,
		desc = "Plant a seed in one of the planting spots at your base.",
		objective = { type = "plant", count = 1 },
		rewards = { xp = 100, gold = 50, seeds = { Emberbloom = 1 } } },
	{ id = "G2", giver = "Gardener", name = "Tender Care", minLevel = 1, after = "G1",
		desc = "Give your plants exactly what they ask for (water or sun) 5 times.",
		objective = { type = "care", count = 5 },
		rewards = { xp = 200, gold = 100, seeds = { Frostpetal = 1 } } },
	{ id = "G3", giver = "Gardener", name = "First Bloom", minLevel = 1, after = "G2",
		desc = "Grow a plant all the way to a Flower and harvest it.",
		objective = { type = "harvest", target = "Flower", count = 1 },
		rewards = { xp = 400, gold = 200, seeds = { SunfireLily = 1 } } },
	{ id = "G4", giver = "Gardener", name = "Green Thumb", minLevel = 5, after = "G3",
		desc = "Harvest 5 fully grown Flowers.",
		objective = { type = "harvest", target = "Flower", count = 5 },
		rewards = { xp = 1000, gold = 600, seeds = { MoonshadeOrchid = 1 } } },
	{ id = "G5", giver = "Gardener", name = "Master Gardener", minLevel = 10, after = "G4",
		desc = "Harvest 15 fully grown Flowers.",
		objective = { type = "harvest", target = "Flower", count = 15 },
		rewards = { xp = 2500, gold = 1500, seeds = { Dragonfruit = 1 } } },

	---------------------------------------------------------------- Scout (adventure)
	{ id = "S1", giver = "Scout", name = "Into the Battle Zone", minLevel = 1,
		desc = "Fly into the Battle Zone at the north end of town. (Careful: other dragons can fight you there!)",
		objective = { type = "visitZone", target = "BattleZone", count = 1 },
		rewards = { xp = 80, gold = 40 } },
	{ id = "S2", giver = "Scout", name = "First Glory", minLevel = 3, after = "S1",
		desc = "Win a battle against another dragon in the Battle Zone.",
		objective = { type = "pvpKill", count = 1 },
		rewards = { xp = 300, gold = 150 } },
	{ id = "S3", giver = "Scout", name = "Boss Hunter", minLevel = 5, after = "S1",
		desc = "When the war horn warns of a boss, join the queue and fight it.",
		objective = { type = "bossJoin", count = 1 },
		rewards = { xp = 600, gold = 300 } },
	{ id = "S4", giver = "Scout", name = "Glory Seeker", minLevel = 8, after = "S2",
		desc = "Win 10 battles in the Battle Zone.",
		objective = { type = "pvpKill", count = 10 },
		rewards = { xp = 1800, gold = 1000 } },
	{ id = "S5", giver = "Scout", name = "Slayer of Giants", minLevel = 12, after = "S3",
		desc = "Defeat 3 bosses.",
		objective = { type = "bossKill", count = 3 },
		rewards = { xp = 5000, gold = 3000, gear = { rarity = "Epic" } } },
	{ id = "S6", giver = "Scout", name = "Sell Your Spoils", minLevel = 2,
		desc = "Sell 3 pieces of gear at the Hoard Exchange.",
		objective = { type = "sell", count = 3 },
		rewards = { xp = 150, gold = 100 } },
}

Quests.byId = {}
for index, quest in ipairs(Quests.List) do
	quest.order = index
	Quests.byId[quest.id] = quest
end

return Quests
