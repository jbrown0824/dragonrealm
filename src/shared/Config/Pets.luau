-- Nano dragon pets. Buy eggs at the Hatchery (or find rare ones on mini-bosses, bosses and camp
-- chests), hatch them, and up to Game.petSlots(level) pets follow you around and boost you.
--
-- Each species is a tiny dragon that borrows the body plan of one of the five dragon types
-- (`plan`) with its own colors. `stats` use the same keys as talents (StatCalc.STAT_INFO).

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Pets = {}

-- "Secret" pets come from the Secret Egg in the 💎 Store (Robux), except the Aurora Serpent: a
-- 1% chance in every Mythic Egg (species with `egg` set only hatch from that egg). The dungeon
-- eggs' species are tied the same way.
-- Pet boosts that don't grow with the pet's level or golden-ness (a pet's breath range stays +50%).
Pets.FIXED_STATS = { breathRange = true }

Pets.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }
Pets.ReleaseGold = { Common = 50, Uncommon = 120, Rare = 300, Epic = 800, Legendary = 2000, Secret = 3000 }

-- Growing pets: feed them Pet Treats (from harvesting flowers) to level them up. Every level adds
-- LEVEL_BONUS to their boosts (level 5 = double). Merge MERGE_COUNT of the same species into one
-- ✨ Golden pet: GOLDEN_MULT times the boosts, a golden sparkle, and it keeps the best level.
Pets.MAX_LEVEL = 5
Pets.LEVEL_COSTS = { 3, 6, 10, 15 } -- treats to go from level N to N+1
Pets.LEVEL_BONUS = 0.25
Pets.GOLDEN_MULT = 1.5
Pets.MERGE_COUNT = 3
Pets.MergeGold = { Common = 100, Uncommon = 250, Rare = 600, Epic = 1500, Legendary = 4000, Secret = 6000 }
Pets.GOLDEN_LOOK = { -- painted over the species colors for golden pets
	accent = Color3.fromRGB(255, 205, 60),
	horn = Color3.fromRGB(255, 215, 90),
	eyes = Color3.fromRGB(255, 250, 200),
	fireA = Color3.fromRGB(255, 235, 140),
	fireB = Color3.fromRGB(255, 170, 30),
}

local function palette(primary, secondary, belly, accent, eyes, wing, horn, fireA, fireB)
	return {
		colors = { primary = primary, secondary = secondary, belly = belly, accent = accent, eyes = eyes, wing = wing, horn = horn },
		fire = { colorA = fireA, colorB = fireB },
	}
end

Pets.Species = {
	---------------------------------------------------------------- Common
	CinderNibbler = { name = "Cinder Nibbler", rarity = "Common", plan = "Behemoth", stats = { goldPct = 6 },
		look = palette(rgb(200, 110, 60), rgb(120, 70, 40), rgb(240, 190, 130), rgb(255, 160, 40), rgb(255, 220, 90), rgb(170, 90, 50), rgb(240, 225, 200), rgb(255, 190, 80), rgb(220, 70, 20)) },
	PuddleWyrmling = { name = "Puddle Wyrmling", rarity = "Common", plan = "Frostwyrm", stats = { staminaPct = 8 },
		look = palette(rgb(70, 170, 190), rgb(40, 110, 140), rgb(190, 235, 240), rgb(120, 240, 255), rgb(255, 255, 255), rgb(90, 190, 210), rgb(220, 245, 250), rgb(180, 245, 255), rgb(40, 140, 200)) },
	MossbackPip = { name = "Mossback Pip", rarity = "Common", plan = "Venomspine", stats = { hungerPct = 8 },
		look = palette(rgb(110, 140, 70), rgb(70, 90, 45), rgb(200, 210, 140), rgb(190, 230, 100), rgb(255, 240, 120), rgb(90, 120, 60), rgb(120, 90, 60), rgb(210, 250, 120), rgb(80, 150, 40)) },

	---------------------------------------------------------------- Uncommon
	SparkSprite = { name = "Spark Sprite", rarity = "Uncommon", plan = "Stormwing", stats = { speedPct = 5 },
		look = palette(rgb(250, 220, 80), rgb(255, 255, 240), rgb(255, 250, 210), rgb(120, 200, 255), rgb(90, 180, 255), rgb(255, 235, 140), rgb(255, 255, 255), rgb(255, 255, 200), rgb(90, 170, 255)) },
	EmberKit = { name = "Ember Kit", rarity = "Uncommon", plan = "Shadowstalker", stats = { attackPct = 5 },
		look = palette(rgb(190, 50, 40), rgb(240, 120, 50), rgb(250, 190, 120), rgb(255, 200, 60), rgb(255, 240, 150), rgb(150, 30, 30), rgb(60, 30, 25), rgb(255, 210, 90), rgb(210, 40, 10)) },
	PebbleGuardian = { name = "Pebble Guardian", rarity = "Uncommon", plan = "Behemoth", stats = { healthPct = 7 },
		look = palette(rgb(150, 150, 155), rgb(100, 100, 110), rgb(200, 195, 185), rgb(120, 220, 170), rgb(150, 255, 200), rgb(125, 125, 135), rgb(230, 225, 215), rgb(170, 255, 210), rgb(40, 150, 110)) },

	---------------------------------------------------------------- Rare
	FrostbiteGlider = { name = "Frostbite Glider", rarity = "Rare", plan = "Frostwyrm", stats = { flightSpeedPct = 10 },
		look = palette(rgb(235, 245, 255), rgb(160, 200, 240), rgb(255, 255, 255), rgb(140, 210, 255), rgb(60, 170, 255), rgb(200, 225, 250), rgb(255, 255, 255), rgb(255, 255, 255), rgb(100, 180, 255)) },
	DuskwingImp = { name = "Duskwing Imp", rarity = "Rare", plan = "Shadowstalker", stats = { critChance = 4 },
		look = palette(rgb(70, 40, 110), rgb(30, 20, 50), rgb(120, 90, 160), rgb(255, 90, 200), rgb(255, 120, 230), rgb(45, 25, 70), rgb(20, 10, 30), rgb(255, 130, 230), rgb(110, 20, 140)) },
	HoneyscaleDrake = { name = "Honeyscale Drake", rarity = "Rare", plan = "Stormwing", stats = { goldPct = 12, xpPct = 5 },
		look = palette(rgb(230, 160, 40), rgb(140, 80, 20), rgb(255, 225, 150), rgb(255, 240, 120), rgb(90, 50, 20), rgb(240, 180, 70), rgb(80, 50, 30), rgb(255, 230, 120), rgb(230, 120, 20)) },

	---------------------------------------------------------------- Epic
	Thunderhatch = { name = "Thunderhatch", rarity = "Epic", plan = "Stormwing", stats = { attackPct = 8, speedPct = 6 },
		look = palette(rgb(30, 50, 120), rgb(80, 220, 255), rgb(150, 200, 255), rgb(120, 255, 255), rgb(200, 255, 255), rgb(40, 80, 170), rgb(220, 240, 255), rgb(200, 255, 255), rgb(40, 120, 255)) },
	ToxiclingHydra = { name = "Toxicling Hydra", rarity = "Epic", plan = "Venomspine", stats = { healthPct = 10, hungerPct = 12 },
		look = palette(rgb(25, 30, 30), rgb(60, 70, 60), rgb(150, 255, 90), rgb(150, 255, 60), rgb(200, 255, 80), rgb(35, 45, 40), rgb(170, 255, 90), rgb(200, 255, 100), rgb(40, 160, 20)) },
	RosequartzWyrm = { name = "Rosequartz Wyrm", rarity = "Epic", plan = "Frostwyrm", stats = { xpPct = 12, lootPct = 10 },
		look = palette(rgb(250, 170, 200), rgb(210, 120, 170), rgb(255, 225, 235), rgb(255, 150, 210), rgb(255, 80, 170), rgb(250, 190, 215), rgb(255, 240, 250), rgb(255, 200, 230), rgb(230, 80, 160)) },

	---------------------------------------------------------------- Legendary
	SolarSeraph = { name = "Solar Seraph", rarity = "Legendary", plan = "Stormwing", stats = { attackPct = 12, goldPct = 15 },
		look = palette(rgb(255, 250, 235), rgb(255, 200, 60), rgb(255, 255, 255), rgb(255, 215, 80), rgb(255, 170, 30), rgb(255, 235, 170), rgb(255, 215, 90), rgb(255, 255, 210), rgb(255, 160, 30)) },
	VoidWhelp = { name = "Void Whelp", rarity = "Legendary", plan = "Shadowstalker", stats = { critChance = 6, critDamage = 20, attackPct = 6 },
		look = palette(rgb(15, 12, 22), rgb(40, 30, 60), rgb(30, 25, 45), rgb(70, 255, 240), rgb(90, 255, 255), rgb(20, 15, 30), rgb(70, 255, 240), rgb(120, 255, 255), rgb(20, 90, 140)) },
	MagmaTitanling = { name = "Magma Titanling", rarity = "Legendary", plan = "Behemoth", stats = { healthPct = 15, defensePct = 10, attackPct = 6 },
		look = palette(rgb(40, 32, 30), rgb(25, 20, 20), rgb(90, 50, 30), rgb(255, 110, 20), rgb(255, 170, 40), rgb(50, 35, 30), rgb(255, 120, 30), rgb(255, 200, 60), rgb(220, 40, 0)) },

	---------------------------------------------------------------- Secret (Robux Secret Egg)
	-- `aura` is the sparkle they always trail.
	PrismaticWyrmlet = { name = "Prismatic Wyrmlet", rarity = "Secret", plan = "Frostwyrm", stats = { xpPct = 15, goldPct = 15, lootPct = 10 }, aura = rgb(255, 150, 240),
		look = palette(rgb(185, 150, 255), rgb(120, 230, 255), rgb(255, 250, 255), rgb(255, 120, 220), rgb(255, 255, 150), rgb(255, 185, 240), rgb(255, 255, 255), rgb(255, 170, 240), rgb(90, 220, 255)) },
	CelestialDrake = { name = "Celestial Drake", rarity = "Secret", plan = "Stormwing", stats = { attackPct = 12, critChance = 5, flightSpeedPct = 12 }, aura = rgb(255, 225, 140),
		look = palette(rgb(22, 26, 72), rgb(255, 215, 120), rgb(60, 70, 140), rgb(150, 200, 255), rgb(255, 255, 255), rgb(40, 50, 125), rgb(255, 220, 130), rgb(255, 250, 220), rgb(255, 200, 80)) },
	PhantomNibbler = { name = "Phantom Nibbler", rarity = "Secret", plan = "Shadowstalker", stats = { healthPct = 14, defensePct = 10, dodge = 5 }, aura = rgb(120, 255, 220),
		look = palette(rgb(205, 232, 242), rgb(120, 160, 180), rgb(240, 250, 255), rgb(120, 255, 220), rgb(120, 255, 220), rgb(170, 210, 225), rgb(232, 242, 246), rgb(170, 255, 235), rgb(40, 170, 150)) },
	-- only in Mythic Eggs (1%): night-sky scales with the northern lights rippling down its frills
	AuroraSerpent = { name = "Aurora Serpent", rarity = "Secret", plan = "Venomspine", egg = "MythicEgg", stats = { lootPct = 15, critDamage = 20, attackPct = 8 }, aura = rgb(130, 255, 190),
		look = palette(rgb(20, 40, 60), rgb(60, 220, 170), rgb(90, 120, 170), rgb(170, 110, 255), rgb(150, 255, 220), rgb(40, 90, 110), rgb(200, 255, 235), rgb(160, 255, 210), rgb(140, 80, 255)) },
	-- a heart-red wyrm with a rosy glow: a little lifesteal and regen (they share the gear-and-pets
	-- cap, Game.EXTRA_LIFESTEAL_CAP / EXTRA_REGEN_CAP)
	HeartbloomWyrm = { name = "Heartbloom Wyrm", rarity = "Secret", plan = "Frostwyrm", stats = { lifesteal = 1.5, regen = 0.12, healthPct = 8 }, aura = rgb(255, 110, 150),
		look = palette(rgb(200, 40, 70), rgb(120, 20, 45), rgb(255, 190, 200), rgb(255, 120, 160), rgb(255, 230, 240), rgb(230, 80, 110), rgb(255, 215, 225), rgb(255, 170, 190), rgb(220, 30, 80)) },

	---------------------------------------------------------------- Dungeon eggs (only from the dungeon's boss)
	BarrowWisp = { name = "Barrow Wisp", rarity = "Rare", plan = "Frostwyrm", egg = "BarrowEgg", stats = { dodge = 3, speedPct = 5 },
		look = palette(rgb(170, 215, 205), rgb(110, 160, 150), rgb(225, 245, 240), rgb(120, 255, 190), rgb(160, 255, 210), rgb(150, 200, 190), rgb(235, 245, 240), rgb(170, 255, 215), rgb(60, 200, 150)) },
	Bonewing = { name = "Bonewing", rarity = "Epic", plan = "Stormwing", egg = "BarrowEgg", stats = { defensePct = 10, healthPct = 6 },
		look = palette(rgb(235, 228, 210), rgb(40, 38, 42), rgb(250, 245, 235), rgb(120, 255, 190), rgb(120, 255, 190), rgb(60, 58, 64), rgb(250, 245, 230), rgb(170, 255, 215), rgb(60, 200, 150)) },
	DraugrDrake = { name = "Draugr Drake", rarity = "Legendary", plan = "Shadowstalker", egg = "BarrowEgg", stats = { lifesteal = 1.5, attackPct = 8, critChance = 3 },
		look = palette(rgb(40, 70, 66), rgb(20, 35, 34), rgb(150, 178, 168), rgb(120, 255, 190), rgb(140, 255, 200), rgb(30, 55, 52), rgb(200, 215, 205), rgb(150, 255, 210), rgb(40, 190, 140)) },
	AnvilWhelp = { name = "Anvil Whelp", rarity = "Rare", plan = "Behemoth", egg = "ForgeEgg", stats = { defensePct = 8, attackPct = 3 },
		look = palette(rgb(95, 95, 105), rgb(55, 55, 62), rgb(160, 150, 140), rgb(255, 130, 50), rgb(255, 170, 60), rgb(80, 80, 90), rgb(60, 55, 55), rgb(255, 190, 80), rgb(255, 90, 20)) },
	RuneforgedDrake = { name = "Runeforged Drake", rarity = "Epic", plan = "Venomspine", egg = "ForgeEgg", stats = { abilityPct = 8, cooldownPct = 4 },
		look = palette(rgb(35, 30, 32), rgb(20, 16, 18), rgb(90, 60, 45), rgb(255, 140, 50), rgb(255, 180, 70), rgb(45, 38, 40), rgb(255, 140, 60), rgb(255, 200, 90), rgb(255, 100, 20)) },
	-- only in Forge Eggs (1%): a molten-hearted wyrmling whose breath reaches half again as far
	-- (breathRange is one of Pets.FIXED_STATS: pet levels and gold don't grow it)
	ForgeheartWyrmling = { name = "Forgeheart Wyrmling", rarity = "Secret", plan = "Shadowstalker", egg = "ForgeEgg", stats = { breathRange = 50, attackPct = 4 }, aura = rgb(255, 170, 60),
		look = palette(rgb(40, 22, 18), rgb(20, 12, 10), rgb(255, 150, 60), rgb(255, 190, 70), rgb(255, 240, 150), rgb(90, 30, 18), rgb(255, 200, 110), rgb(255, 230, 120), rgb(255, 90, 20)) },
	-- the freed elder dragon's hatchling
	ChainbreakerWyrm = { name = "Chainbreaker Wyrm", rarity = "Legendary", plan = "Stormwing", egg = "ForgeEgg", stats = { regen = 0.15, healthPct = 10, attackPct = 6 },
		look = palette(rgb(170, 40, 25), rgb(90, 20, 15), rgb(255, 200, 120), rgb(255, 210, 90), rgb(255, 230, 120), rgb(200, 60, 30), rgb(255, 210, 110), rgb(255, 220, 110), rgb(255, 110, 20)) },
}

-- Eggs. `weights` pick the rarity; the species is then random within that rarity
-- (Pets.speciesFor). `store` = the 💎 Store product that sells it for Robux.
-- Eggs without a price can't be bought: they drop from mini-bosses, bosses and chests. Dungeon
-- eggs (`dungeon` = where) only drop from that dungeon's boss, and hatch pets found nowhere else.
Pets.EggOrder = { "EmberEgg", "StormEgg", "MythicEgg", "SecretEgg", "BarrowEgg", "ForgeEgg" }
Pets.Eggs = {
	EmberEgg = { name = "Ember Egg", icon = "🥚", price = 400, color = rgb(255, 150, 90),
		weights = { Common = 62, Uncommon = 30, Rare = 7, Epic = 1 },
		desc = "A warm, common egg. Usually hatches a Common or Uncommon nano dragon." },
	StormEgg = { name = "Storm Egg", icon = "🌩️", price = 2000, color = rgb(120, 180, 255),
		weights = { Uncommon = 45, Rare = 38, Epic = 14, Legendary = 3 },
		desc = "Crackles with energy. Good odds of a Rare, and a small chance of Legendary." },
	MythicEgg = { name = "Mythic Egg", icon = "🌟", price = nil, color = rgb(255, 210, 90), store = "MythicEgg",
		weights = { Epic = 72, Legendary = 27, Secret = 1 },
		desc = "Always Epic or Legendary, with a 1% chance of the Aurora Serpent (a Secret found nowhere else). Found free on mini-bosses, bosses and camp chests." },
	SecretEgg = { name = "Secret Egg", icon = "🔮", price = nil, robux = true, store = "SecretEgg", color = rgb(255, 150, 240),
		weights = { Secret = 100 },
		desc = "A shimmering egg from the 💎 Store. Always hatches one of the four Secret nano dragons." },
	BarrowEgg = { name = "Barrow Egg", icon = "💀", price = nil, dungeon = "Barrow", color = rgb(120, 255, 190),
		weights = { Rare = 65, Epic = 28, Legendary = 7 },
		desc = "Cold as a grave and faintly glowing. Only Haldor the Hollow King drops it, and it hatches nano dragons found nowhere else." },
	ForgeEgg = { name = "Forge Egg", icon = "🔥", price = nil, dungeon = "Forge", color = rgb(255, 140, 60),
		weights = { Rare = 20, Epic = 55, Legendary = 24, Secret = 1 },
		desc = "Still hot from the Rune Forge. Only Runemaster Sigrun drops it, and it hatches nano dragons found nowhere else, with a 1% chance of the Forgeheart Wyrmling (+50% breath range)." },
}

Pets.RarityColors = {
	Common = rgb(205, 205, 205),
	Uncommon = rgb(90, 225, 90),
	Rare = rgb(80, 160, 255),
	Epic = rgb(195, 95, 255),
	Legendary = rgb(255, 165, 40),
	Secret = rgb(255, 120, 230),
}

function Pets.get(speciesId: string)
	return Pets.Species[speciesId]
end

-- How much a pet's boosts are multiplied by its level and golden-ness.
function Pets.multiplier(level: number?, golden: boolean?): number
	return (1 + Pets.LEVEL_BONUS * ((level or 1) - 1)) * (golden and Pets.GOLDEN_MULT or 1)
end

function Pets.displayName(pet): string
	local species = Pets.get(pet.species)
	return (pet.golden and "✨ Golden " or "") .. (species and species.name or pet.species)
end

-- The species an egg can hatch at `rarity`: the ones found only in this egg (`egg` = its id), or
-- if it has none of that rarity, every species of that rarity that isn't tied to another egg.
function Pets.speciesFor(eggId: string, rarity: string)
	local own, open = {}, {}
	for id, s in pairs(Pets.Species) do
		if s.rarity == rarity then
			if s.egg == eggId then
				table.insert(own, id)
			elseif s.egg == nil then
				table.insert(open, id)
			end
		end
	end
	local list = #own > 0 and own or open
	table.sort(list)
	return list
end

function Pets.speciesOfRarity(rarity: string)
	local list = {}
	for id, s in pairs(Pets.Species) do
		if s.rarity == rarity then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

return Pets
