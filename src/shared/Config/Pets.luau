-- Nano dragon pets. Buy eggs at the Hatchery (or find rare ones on mini-bosses, bosses and camp
-- chests), hatch them, and up to Game.petSlots(level) pets follow you around and boost you.
--
-- Each species is a tiny dragon that borrows the body plan of one of the five dragon types
-- (`plan`) with its own colors. `stats` use the same keys as talents (StatCalc.STAT_INFO).

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Pets = {}

Pets.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
Pets.ReleaseGold = { Common = 50, Uncommon = 120, Rare = 300, Epic = 800, Legendary = 2000 }

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
}

-- Eggs. `weights` pick the rarity; the species is then random within that rarity.
-- Eggs without a price can't be bought: they drop from mini-bosses, bosses and chests.
Pets.EggOrder = { "EmberEgg", "StormEgg", "MythicEgg" }
Pets.Eggs = {
	EmberEgg = { name = "Ember Egg", icon = "🥚", price = 400, color = rgb(255, 150, 90),
		weights = { Common = 62, Uncommon = 30, Rare = 7, Epic = 1 },
		desc = "A warm, common egg. Usually hatches a Common or Uncommon nano dragon." },
	StormEgg = { name = "Storm Egg", icon = "🌩️", price = 2000, color = rgb(120, 180, 255),
		weights = { Uncommon = 45, Rare = 38, Epic = 14, Legendary = 3 },
		desc = "Crackles with energy. Good odds of a Rare, and a small chance of Legendary." },
	MythicEgg = { name = "Mythic Egg", icon = "🌟", price = nil, color = rgb(255, 210, 90),
		weights = { Rare = 45, Epic = 40, Legendary = 15 },
		desc = "Only found on mini-bosses, bosses and camp chests. Never hatches anything below Rare." },
}

Pets.RarityColors = {
	Common = rgb(205, 205, 205),
	Uncommon = rgb(90, 225, 90),
	Rare = rgb(80, 160, 255),
	Epic = rgb(195, 95, 255),
	Legendary = rgb(255, 165, 40),
}

function Pets.get(speciesId: string)
	return Pets.Species[speciesId]
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
