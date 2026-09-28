-- Plants for the farm plots at each dragon's base.
-- Every plant grows through 4 stages. During each stage it gets thirsty a few times and
-- growth pauses until you water it. If you don't water it in time it keeps growing anyway,
-- but its quality drops, and quality scales the harvest value. Harvesting a full Flower also
-- gives seeds back.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Seeds = {}

Seeds.Order = { "Emberbloom", "Frostpetal", "SunfireLily", "MoonshadeOrchid", "Dragonfruit" }

Seeds.Stages = { "Seed", "Seedling", "Sprout", "Flower" }
Seeds.StageIcons = { "🌰", "🌱", "🌿", "🌸" }
Seeds.StageValue = { 0.08, 0.22, 0.5, 1.0 } -- fraction of full value when harvested at each stage

Seeds.MISSED_WATER_LOSS = 15 -- quality lost each time a plant goes thirsty for too long
Seeds.MIN_QUALITY = 40 -- a neglected plant still blooms, worth at least this % of full value
Seeds.BONUS_SEED_QUALITY = 85 -- flowers at or above this quality can give a bonus seed
Seeds.MUTATION_CHANCE = 0.06 -- chance a flower harvest also yields a seed one rarity higher
-- Full flowers can also drop Pet Treats (feed them to nano dragons to level them up).
-- treats = { chance, min, max } per plant; sprouts get a quarter of the chance for 1 treat.

Seeds.Emberbloom = {
	id = "Emberbloom", name = "Emberbloom", rarity = "Common",
	stageTime = 35, needsPerStage = 1, needWindow = 40,
	value = 120, dropWeight = 50, treats = { 0.5, 1, 1 },
	bloom = rgb(255, 120, 30), leaf = rgb(90, 170, 60),
	desc = "A hardy flame-flower. Great for new gardeners.",
}

Seeds.Frostpetal = {
	id = "Frostpetal", name = "Frostpetal", rarity = "Uncommon",
	stageTime = 50, needsPerStage = 2, needWindow = 40,
	value = 260, dropWeight = 26, treats = { 0.7, 1, 2 },
	bloom = rgb(170, 225, 255), leaf = rgb(110, 170, 150),
	desc = "A thirsty blossom that loves cool water.",
}

Seeds.SunfireLily = {
	id = "SunfireLily", name = "Sunfire Lily", rarity = "Rare",
	stageTime = 70, needsPerStage = 2, needWindow = 35,
	value = 480, dropWeight = 14, treats = { 1, 1, 2 },
	bloom = rgb(255, 225, 60), leaf = rgb(120, 180, 50),
	desc = "Glows like a tiny sun when it blooms.",
}

Seeds.MoonshadeOrchid = {
	id = "MoonshadeOrchid", name = "Moonshade Orchid", rarity = "Epic",
	stageTime = 95, needsPerStage = 3, needWindow = 35,
	value = 850, dropWeight = 7, treats = { 1, 2, 3 },
	bloom = rgb(170, 100, 255), leaf = rgb(70, 120, 90),
	desc = "A rare night-blooming orchid. Needs careful attention.",
}

Seeds.Dragonfruit = {
	id = "Dragonfruit", name = "Dragonfruit", rarity = "Legendary",
	stageTime = 130, needsPerStage = 3, needWindow = 30,
	value = 1700, dropWeight = 3, treats = { 1, 3, 5 },
	bloom = rgb(255, 50, 120), leaf = rgb(60, 150, 70),
	desc = "The legendary fruit of dragons. Worth a fortune.",
}

function Seeds.get(id: string)
	local s = Seeds[id]
	if type(s) == "table" and s.id then
		return s
	end
	return nil
end

return Seeds
