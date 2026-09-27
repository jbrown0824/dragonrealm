-- Plants for the farm plots at each dragon's base.
-- Every plant grows through 4 stages. During each stage it asks for water or sun a few
-- times; growth pauses until you give it what it wants. Ignore a need for too long and the
-- plant loses health; give it the wrong thing and it loses a little. Health scales the
-- harvest value. Harvesting a full Flower also gives seeds back.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Seeds = {}

Seeds.Order = { "Emberbloom", "Frostpetal", "SunfireLily", "MoonshadeOrchid", "Dragonfruit" }

Seeds.Stages = { "Seed", "Seedling", "Sprout", "Flower" }
Seeds.StageIcons = { "🌰", "🌱", "🌿", "🌸" }
Seeds.StageValue = { 0.08, 0.22, 0.5, 1.0 } -- fraction of full value when harvested at each stage

Seeds.NEED_PENALTY = 25 -- health lost when a need is ignored until it expires
Seeds.WRONG_CARE_PENALTY = 10 -- health lost for watering a plant that wanted sun (or vice versa)
Seeds.GOOD_CARE_BONUS = 4
Seeds.MUTATION_CHANCE = 0.06 -- chance a flower harvest also yields a seed one rarity higher

Seeds.Emberbloom = {
	id = "Emberbloom", name = "Emberbloom", rarity = "Common",
	stageTime = 35, needsPerStage = 1, needWindow = 40, sunBias = 0.5,
	value = 120, dropWeight = 50,
	bloom = rgb(255, 120, 30), leaf = rgb(90, 170, 60),
	desc = "A hardy flame-flower. Great for new gardeners.",
}

Seeds.Frostpetal = {
	id = "Frostpetal", name = "Frostpetal", rarity = "Uncommon",
	stageTime = 50, needsPerStage = 2, needWindow = 40, sunBias = 0.3,
	value = 260, dropWeight = 26,
	bloom = rgb(170, 225, 255), leaf = rgb(110, 170, 150),
	desc = "Loves water, hates too much sun.",
}

Seeds.SunfireLily = {
	id = "SunfireLily", name = "Sunfire Lily", rarity = "Rare",
	stageTime = 70, needsPerStage = 2, needWindow = 35, sunBias = 0.75,
	value = 480, dropWeight = 14,
	bloom = rgb(255, 225, 60), leaf = rgb(120, 180, 50),
	desc = "Drinks sunlight like water.",
}

Seeds.MoonshadeOrchid = {
	id = "MoonshadeOrchid", name = "Moonshade Orchid", rarity = "Epic",
	stageTime = 95, needsPerStage = 3, needWindow = 35, sunBias = 0.4,
	value = 850, dropWeight = 7,
	bloom = rgb(170, 100, 255), leaf = rgb(70, 120, 90),
	desc = "A rare night-blooming orchid. Needs careful attention.",
}

Seeds.Dragonfruit = {
	id = "Dragonfruit", name = "Dragonfruit", rarity = "Legendary",
	stageTime = 130, needsPerStage = 3, needWindow = 30, sunBias = 0.55,
	value = 1700, dropWeight = 3,
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
