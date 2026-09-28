-- Dragon skins: color palettes that work on every dragon type (the body shape, ember core, runes
-- and wings stay the same; only the colors change). Unlocked from the 📖 Collection
-- (achievements and pet book milestones) or the 💎 Store, and picked in the Collection window.
-- `unlock` is shown to players who don't have it yet.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function skin(id, name, unlock, primary, secondary, belly, accent, eyes, wing, horn, fireA, fireB)
	return {
		id = id,
		name = name,
		unlock = unlock,
		colors = { primary = primary, secondary = secondary, belly = belly, accent = accent, eyes = eyes, wing = wing, horn = horn },
		fire = { colorA = fireA, colorB = fireB },
	}
end

local Skins = {}

-- "Classic" is each dragon type's own colors.
Skins.Order = { "Classic", "Sunrise", "Obsidian", "Bloodmoon", "Royal", "Verdant", "Frostbite", "Gilded", "Starlight", "Sunforged", "Voidborn", "Sandstorm" }

Skins.List = {
	Classic = { id = "Classic", name = "Classic", unlock = "Your dragon's own colors." },
	Sunrise = skin("Sunrise", "Sunrise", "Comes with the Starter Pack in the 💎 Store.",
		rgb(255, 150, 90), rgb(255, 210, 120), rgb(255, 235, 200), rgb(255, 100, 140), rgb(255, 250, 200), rgb(250, 130, 110), rgb(255, 240, 220), rgb(255, 220, 140), rgb(255, 90, 60)),
	Obsidian = skin("Obsidian", "Obsidian", "Viking Slayer III: defeat 2,500 vikings.",
		rgb(30, 28, 34), rgb(60, 55, 66), rgb(80, 40, 36), rgb(255, 90, 40), rgb(255, 120, 40), rgb(45, 40, 50), rgb(200, 190, 180), rgb(255, 150, 60), rgb(200, 40, 10)),
	Bloodmoon = skin("Bloodmoon", "Bloodmoon", "Champion Hunter III: defeat 50 camp champions.",
		rgb(120, 20, 30), rgb(40, 10, 15), rgb(170, 60, 60), rgb(255, 60, 60), rgb(255, 230, 120), rgb(90, 15, 25), rgb(30, 20, 20), rgb(255, 90, 90), rgb(140, 0, 20)),
	Royal = skin("Royal", "Royal", "Boss Slayer III: defeat 50 world bosses.",
		rgb(90, 50, 160), rgb(255, 205, 80), rgb(200, 170, 240), rgb(255, 215, 90), rgb(255, 240, 160), rgb(120, 70, 190), rgb(255, 215, 110), rgb(220, 180, 255), rgb(140, 60, 220)),
	Verdant = skin("Verdant", "Verdant", "Green Claws III: harvest 1,000 flowers.",
		rgb(70, 150, 70), rgb(160, 220, 90), rgb(220, 240, 170), rgb(255, 130, 180), rgb(255, 240, 120), rgb(90, 170, 80), rgb(120, 90, 60), rgb(200, 255, 140), rgb(60, 170, 60)),
	Frostbite = skin("Frostbite", "Frostbite", "Angler III: catch 500 fish.",
		rgb(230, 242, 255), rgb(150, 200, 240), rgb(255, 255, 255), rgb(90, 190, 255), rgb(70, 160, 255), rgb(190, 225, 250), rgb(240, 250, 255), rgb(220, 245, 255), rgb(80, 170, 255)),
	Gilded = skin("Gilded", "Gilded", "Pet book: collect 3 Golden pets.",
		rgb(230, 180, 60), rgb(160, 110, 30), rgb(255, 230, 150), rgb(255, 240, 170), rgb(255, 255, 220), rgb(240, 200, 90), rgb(255, 245, 200), rgb(255, 240, 150), rgb(255, 170, 30)),
	Starlight = skin("Starlight", "Starlight", "Pet book: discover 15 different pet species.",
		rgb(30, 40, 90), rgb(120, 150, 255), rgb(70, 80, 150), rgb(255, 255, 200), rgb(255, 255, 255), rgb(50, 60, 130), rgb(230, 235, 255), rgb(255, 255, 230), rgb(140, 170, 255)),
	Sunforged = skin("Sunforged", "Sunforged", "Pet book: collect 15 Golden pets.",
		rgb(255, 200, 70), rgb(255, 120, 30), rgb(255, 245, 200), rgb(255, 255, 255), rgb(255, 120, 40), rgb(255, 170, 60), rgb(255, 255, 240), rgb(255, 255, 200), rgb(255, 140, 20)),
	Voidborn = skin("Voidborn", "Voidborn", "Paragon III: reach Paragon 100.",
		rgb(12, 10, 20), rgb(40, 30, 70), rgb(25, 20, 40), rgb(80, 255, 240), rgb(100, 255, 255), rgb(20, 15, 35), rgb(80, 255, 240), rgb(140, 255, 255), rgb(20, 100, 160)),
	Sandstorm = skin("Sandstorm", "Sandstorm", "Wild Hunter III: hunt 1,000 animals.",
		rgb(210, 175, 120), rgb(150, 110, 70), rgb(240, 220, 180), rgb(255, 150, 60), rgb(255, 210, 90), rgb(190, 150, 100), rgb(245, 235, 210), rgb(255, 210, 120), rgb(220, 110, 30)),
}

function Skins.get(id: string?)
	return id and Skins.List[id] or nil
end

return Skins
