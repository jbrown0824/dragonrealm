-- Food: meat packed from hunted animals and fish caught at fishing spots. Eating refills your
-- hunger (`food` points out of Game.HUNGER_MAX). Food can also be sold at the Hoard Exchange.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Food = {}

Food.Order = { "Venison", "GoatChop", "BoarHaunch", "WolfSteak", "BearRoast", "Minnow", "RiverTrout", "SilverSalmon", "Frostfin", "GoldenCarp", "AncientEel" }

Food.Items = {
	-- meat
	Venison = { name = "Venison", icon = "🍖", kind = "meat", food = 32, sell = 10, color = rgb(210, 120, 100) },
	GoatChop = { name = "Goat Chop", icon = "🍖", kind = "meat", food = 26, sell = 8, color = rgb(220, 150, 130) },
	BoarHaunch = { name = "Boar Haunch", icon = "🍗", kind = "meat", food = 42, sell = 14, color = rgb(200, 110, 80) },
	WolfSteak = { name = "Wolf Steak", icon = "🥩", kind = "meat", food = 34, sell = 12, color = rgb(190, 90, 90) },
	BearRoast = { name = "Bear Roast", icon = "🍖", kind = "meat", food = 70, sell = 30, color = rgb(170, 90, 60) },
	-- fish
	Minnow = { name = "Minnow", icon = "🐟", kind = "fish", food = 10, sell = 4, color = rgb(190, 200, 210) },
	RiverTrout = { name = "River Trout", icon = "🐟", kind = "fish", food = 22, sell = 12, color = rgb(160, 190, 130) },
	SilverSalmon = { name = "Silver Salmon", icon = "🐠", kind = "fish", food = 30, sell = 22, color = rgb(230, 170, 150) },
	Frostfin = { name = "Frostfin", icon = "🐠", kind = "fish", food = 40, sell = 90, color = rgb(160, 220, 255) },
	GoldenCarp = { name = "Golden Carp", icon = "🐡", kind = "fish", food = 35, sell = 150, color = rgb(255, 210, 60) },
	AncientEel = { name = "Ancient Eel", icon = "🐍", kind = "fish", food = 60, sell = 400, color = rgb(150, 110, 220) },
}

-- What each kind of fishing spot can catch, as weights.
Food.FishTables = {
	River = { Minnow = 50, RiverTrout = 35, SilverSalmon = 12, GoldenCarp = 3 },
	Lake = { Minnow = 20, RiverTrout = 35, SilverSalmon = 32, GoldenCarp = 10, AncientEel = 3 },
	Ice = { SilverSalmon = 30, Frostfin = 50, GoldenCarp = 12, AncientEel = 8 },
}

-- Fishing minigame: after a bite you have `window` seconds to reel, and the green zone is
-- `zone` wide (fraction of the bar). Better spots are a little trickier.
Food.FishingDifficulty = {
	River = { zone = 0.3, speed = 1.1 },
	Lake = { zone = 0.24, speed = 1.35 },
	Ice = { zone = 0.2, speed = 1.6 },
}

function Food.get(id: string)
	return Food.Items[id]
end

return Food
