-- Village dragons who live in town (CivilianService). They stroll between the plaza, the streets
-- and their houses (Zones.TownWalk), go inside for a while, and say hello if you chat with them.
-- They can't be attacked and never leave town.
--
-- `plan` borrows a dragon type's body; `scale` keeps them smaller than players (and hatchlings
-- tiny). `home` is their house index in Zones.Houses.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function colors(primary, secondary, belly, accent, eyes, wing, horn)
	return { primary = primary, secondary = secondary, belly = belly, accent = accent, eyes = eyes, wing = wing, horn = horn }
end

local Civilians = {}

Civilians.WALK_SPEED = 9
Civilians.LINGER = { 4, 9 } -- seconds to pause at a street corner
Civilians.INDOORS = { 12, 25 } -- seconds to stay inside a house
Civilians.HOME_CHANCE = 0.45 -- chance the next trip is into a house (theirs, usually)
Civilians.CHAT_PAUSE = 5 -- seconds they stop to talk when you chat with them

-- Things any villager might say.
Civilians.CommonLines = {
	"Lovely day for a glide, isn't it?",
	"Watch out for vikings past the river!",
	"Have you tried the flowers at your lair? Full blooms sometimes drop Pet Treats!",
	"The Hatchery just got a fresh batch of eggs.",
	"My grandmother says Hrothgar the Dragonslayer is twice the size of a longhouse!",
	"Come inside and warm your wings by the fire sometime!",
}

Civilians.List = {
	{ id = "Cinderbeard", name = "Old Cinderbeard", plan = "Behemoth", scale = 0.72, home = 1,
		colors = colors(rgb(120, 95, 80), rgb(80, 60, 50), rgb(200, 175, 140), rgb(255, 150, 70), rgb(255, 210, 120), rgb(110, 85, 70), rgb(230, 225, 210)),
		lines = { "In my day we flew to Frostfang Ridge and back before breakfast!", "Mind my back, youngster. Too many winters." } },
	{ id = "Pip", name = "Pip", plan = "Stormwing", scale = 0.42, home = 4,
		colors = colors(rgb(140, 200, 255), rgb(255, 255, 255), rgb(230, 245, 255), rgb(255, 230, 90), rgb(60, 120, 220), rgb(170, 215, 255), rgb(255, 250, 230)),
		lines = { "When I grow up I'm going to be a dragon just like you!", "Wanna race? ...Wait, I can't fly yet." } },
	{ id = "Mossgleam", name = "Auntie Mossgleam", plan = "Venomspine", scale = 0.62, home = 9,
		colors = colors(rgb(110, 150, 90), rgb(70, 100, 60), rgb(215, 220, 160), rgb(250, 180, 200), rgb(255, 240, 150), rgb(95, 130, 80), rgb(140, 100, 70)),
		lines = { "Water your flowers, dear! Thirsty plants give smaller harvests.", "I've been knitting nests all morning." } },
	{ id = "Sootsnout", name = "Sootsnout", plan = "Shadowstalker", scale = 0.55, home = 7,
		colors = colors(rgb(70, 60, 75), rgb(40, 35, 45), rgb(130, 115, 130), rgb(255, 120, 60), rgb(255, 170, 80), rgb(55, 45, 60), rgb(30, 25, 30)),
		lines = { "Psst. Every viking camp has a treasure chest in the middle. Hold E to open it!", "Achoo! Sorry. Chimney duty." } },
	{ id = "Frostwhisk", name = "Grandma Frostwhisk", plan = "Frostwyrm", scale = 0.6, home = 5,
		colors = colors(rgb(220, 230, 245), rgb(170, 190, 220), rgb(250, 250, 255), rgb(190, 150, 255), rgb(120, 160, 255), rgb(205, 215, 240), rgb(245, 245, 255)),
		lines = { "Would you like a cookie? They're only a little bit frozen.", "Wrap up warm if you visit Frostfang Ridge!" } },
	{ id = "Twiggle", name = "Twiggle", plan = "Venomspine", scale = 0.4, home = 10,
		colors = colors(rgb(240, 170, 60), rgb(200, 110, 40), rgb(255, 225, 150), rgb(120, 220, 120), rgb(90, 60, 30), rgb(230, 150, 70), rgb(255, 235, 200)),
		lines = { "I found a shiny rock! ...It's just a rock.", "Did you know nano dragons love treats? Feed yours!" } },
	{ id = "Blaze", name = "Captain Blaze (retired)", plan = "Stormwing", scale = 0.7, home = 8,
		colors = colors(rgb(180, 60, 50), rgb(240, 170, 60), rgb(250, 210, 160), rgb(255, 230, 120), rgb(255, 240, 180), rgb(160, 50, 45), rgb(90, 60, 40)),
		lines = { "Team up with friends for champions. Everyone who helps gets loot!", "Back in my day the Hornblowers had REAL horns." } },
}

return Civilians
