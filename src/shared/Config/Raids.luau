-- Night raids on Dragon Town (server/Services/RaidService). When night falls there's a CHANCE of
-- a raid, and after PITY_NIGHTS nights in a row without one the next night always brings one.
-- Longships row down the river with the raiders aboard and run aground below town; waves of
-- vikings hop ashore. Torchbearers set houses alight, the rest pick their own victims (villagers,
-- or dragons anywhere in town, even at home in their lairs), and the villagers (brave, but not
-- very strong) join the fight until a raider knocks them out for a while.
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

-- Raiders are around the level of the dragons online (their average, minus the tier's
-- levelBelow), and there are more of them the more dragons are online.
Raids.LEVEL_RANGE = { 1, 26 }
Raids.EXTRA_PER_PLAYER = 0.5 -- every dragon online past the first adds half as many raiders again
Raids.MAX_SCALE = 3 -- ...up to this many times the numbers below

-- The raid's size depends on the strongest dragon online: the first tier whose maxLevel covers
-- them. Each wave lists how many of each viking come ashore (for one dragon online); `leader`
-- adds the Raid Captain. Gentler tiers also give burning houses longer before they fall.
Raids.Tiers = {
	{ maxLevel = 6, levelBelow = 2, captainHealth = 1.2, burnTime = 70, waves = {
		{ Raider = 2, Torchbearer = 1 },
		{ Raider = 2, Torchbearer = 2 },
		{ Raider = 1, Torchbearer = 1, leader = true },
	} },
	{ maxLevel = 14, levelBelow = 1, captainHealth = 1.8, burnTime = 55, waves = {
		{ Raider = 3, Torchbearer = 2 },
		{ Raider = 2, AxeThrower = 2, Torchbearer = 2 },
		{ Raider = 2, AxeThrower = 1, Torchbearer = 2, leader = true },
	} },
	{ maxLevel = math.huge, levelBelow = 1, captainHealth = 2.5, burnTime = 45, waves = {
		{ Raider = 3, Torchbearer = 2 },
		{ Raider = 2, AxeThrower = 2, Torchbearer = 2 },
		{ Berserker = 2, AxeThrower = 1, Torchbearer = 2, leader = true },
	} },
}
function Raids.tierFor(level: number)
	for _, tier in ipairs(Raids.Tiers) do
		if level <= tier.maxLevel then
			return tier
		end
	end
	return Raids.Tiers[#Raids.Tiers]
end
Raids.WAVES = 3 -- every tier has this many waves

-- The Raid Captain: a big Chieftain with a telegraphed slam (health x the tier's captainHealth).
Raids.Captain = {
	base = "Chieftain", name = "Raid Captain", scale = 1.55,
	healthPerPlayer = 0.75, damageMult = 1.1,
	slam = { radius = 13, mult = 1.7, cooldown = 9, delay = 1.4 },
	look = { shirt = Color3.fromRGB(60, 40, 30), pants = Color3.fromRGB(40, 30, 25), beard = Color3.fromRGB(30, 25, 20), weapon = "greatAxe", shield = true, cape = Color3.fromRGB(30, 30, 35), crown = true, warpaint = true },
}

-- How raiders fight. They give up on a dragon that gets CHASE_RANGE away (flat) and don't chase
-- one flying more than FLYER_HEIGHT above them (the ones with axes throw instead, the rest get on
-- with the raid). At most CROWD raiders go after the same dragon (unless it's right next to
-- them); the others pick another victim. Fighters pick a new victim every RETARGET seconds.
Raids.CHASE_RANGE = 60
Raids.FLYER_HEIGHT = 18
Raids.CROWD = 3
Raids.RETARGET = 15
Raids.VILLAGER_VICTIM_CHANCE = 0.45 -- how often a fighter goes after a villager instead of a dragon

-- Houses
Raids.TORCH_TIME = 3 -- seconds a Torchbearer stands at a door to set the house alight
Raids.DOUSE_HOLD = 2 -- hold E at the door this long to beat out the flames
-- (a burning house burns down after the tier's burnTime unless someone puts it out)

-- Villagers join the fight: they puff small bursts of fire at raiders near them. A raider fresh
-- off the boat can't be finished by villagers (their fire stops at VILLAGER_FLOOR of its health),
-- but that floor wears away over VILLAGER_FINISH_AFTER seconds ashore, so the last straggler
-- doesn't stand at 30% forever while the whole village breathes on him. With few dragons online
-- (FewDragons, by how many are playing) the villagers hit harder and finish raiders sooner.
Raids.VILLAGER_DAMAGE = 0.04 -- share of the raider's max health per puff
Raids.VILLAGER_FLOOR = 0.3
Raids.VILLAGER_FINISH_AFTER = 120
Raids.VILLAGER_INTERVAL = 2.5
Raids.VILLAGER_RANGE = 18
Raids.FewDragons = {
	[1] = { damage = 1.5, finish = 0.5 },
	[2] = { damage = 1.25, finish = 0.75 },
}
-- The quest givers fight too, from their posts (they're too old to chase anyone): a stronger puff
-- at any raider in reach, under the same wearing-away floor. They won't talk quests until the
-- raid is over.
Raids.ELDER_RANGE = 34
Raids.ELDER_DAMAGE = 0.07
Raids.ELDER_INTERVAL = 2.2
Raids.ELDER_LINES = { "To arms, dragons!", "Not in MY town!", "Back to your boats!", "Have some fire!" }
Raids.QUEST_BUSY = "Not now, the vikings are here! Come back after the raid."
Raids.VILLAGER_LINES = { "For the village!", "Get out of our town!", "Not my garden!", "Shoo! Shoo!" }
-- Raiders can knock villagers out: VILLAGER_HITS hits and they're down (sprawled, eyes shut) for
-- VILLAGER_KNOCKOUT seconds, then they get back up and back into the fight.
Raids.VILLAGER_HITS = 3
Raids.VILLAGER_KNOCKOUT = 25
Raids.VILLAGER_HURT_LINES = { "Ow!", "Oof!", "Hey, that hurt!" }

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
	{ shipX = -52, fromX = -446, shore = Vector3.new(-40, 0, 247) },
	{ shipX = 52, fromX = 330, shore = Vector3.new(40, 0, 247) },
}
Raids.ENTRY_NODE = "N4"
Raids.SHIP_ROW_TIME = 18 -- seconds the longships take to row in (inside the WARNING)
Raids.PASSENGERS = 10 -- room on each ship's deck (the wave rides in standing up, then leaps ashore)
Raids.HOP_GAP = 0.45 -- seconds between raiders leaping ashore
Raids.LEAP_TIME = 0.8 -- seconds a leap from the deck to the beach takes
Raids.LEAP_HEIGHT = 9 -- studs above the straight line at the top of the leap
Raids.SHIP_OUT_TIME = 12 -- seconds to row back upriver for the next wave (it returns in SHIP_ROW_TIME)

-- If it's time for a raid while a world boss is on its way or being fought, the raid waits for
-- it (as long as at least RAID_MIN_NIGHT seconds of night are left). Bosses wait for raids too.
Raids.RAID_MIN_NIGHT = 150
Raids.BOSS_AFTER_RAID = 30 -- a boss warning due during a raid starts this long after it ends

-- How much harder villager (and quest giver) fire hits, and how many seconds a raider has to be
-- ashore before it can finish him, with `dragons` players in the server.
function Raids.villagerHelp(dragons: number): (number, number)
	local few = Raids.FewDragons[math.max(1, dragons)]
	return few and few.damage or 1, Raids.VILLAGER_FINISH_AFTER * (few and few.finish or 1)
end

return Raids
