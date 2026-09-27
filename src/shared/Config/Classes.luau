-- The five dragon types. Each has its own look, fire style, stats and skill tree.
-- Talent trees live in Config/Talents; abilities in Config/Abilities.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Classes = {}

Classes.Order = { "Shadowstalker", "Stormwing", "Behemoth", "Frostwyrm", "Venomspine" }

Classes.Shadowstalker = {
	id = "Shadowstalker",
	name = "Shadowstalker",
	role = "Stealthy",
	tagline = "Strike unseen. Vanish before they scream.",
	description = "A sleek night hunter. Huge critical hits, stealth, and purple shadowflame that drains life.",
	scale = 1.0,
	build = "sleek",
	colors = {
		primary = rgb(46, 34, 66),
		secondary = rgb(92, 70, 128),
		belly = rgb(70, 56, 92),
		accent = rgb(170, 90, 255),
		eyes = rgb(210, 120, 255),
		wing = rgb(34, 26, 48),
		horn = rgb(20, 16, 28),
	},
	fire = {
		name = "Shadowflame",
		colorA = rgb(205, 120, 255),
		colorB = rgb(70, 10, 120),
		texture = "rbxasset://textures/particles/fire_main.dds",
		lightEmission = 0.8,
		size = 2.4,
		style = "shadow",
	},
	stats = {
		health = 100, healthPerLevel = 15,
		attack = 12, attackPerLevel = 2.3,
		defense = 4, defensePerLevel = 1.0,
		crit = 12, critDamage = 160,
		speed = 21, stamina = 110,
	},
	breath = { range = 24, angle = 32, cooldown = 0.45, mult = 1.0, critBonus = 8 },
	statBars = { health = 2, attack = 4, speed = 4, defense = 2 },
}

Classes.Stormwing = {
	id = "Stormwing",
	name = "Stormwing",
	role = "Agile",
	tagline = "Faster than the thunder that follows.",
	description = "The fastest flyer in the realm. Crackling lightning breath, huge flight stamina and dodges.",
	scale = 0.92,
	build = "slender",
	colors = {
		primary = rgb(40, 110, 170),
		secondary = rgb(240, 210, 80),
		belly = rgb(190, 225, 245),
		accent = rgb(255, 230, 90),
		eyes = rgb(140, 240, 255),
		wing = rgb(70, 160, 220),
		horn = rgb(230, 230, 240),
	},
	fire = {
		name = "Storm Breath",
		colorA = rgb(215, 250, 255),
		colorB = rgb(40, 110, 255),
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		size = 1.9,
		style = "storm",
	},
	stats = {
		health = 92, healthPerLevel = 13,
		attack = 11, attackPerLevel = 2.1,
		defense = 3, defensePerLevel = 0.9,
		crit = 8, critDamage = 150,
		speed = 25, stamina = 170,
	},
	breath = { range = 27, angle = 28, cooldown = 0.35, mult = 0.8 },
	statBars = { health = 2, attack = 3, speed = 5, defense = 1 },
}

Classes.Behemoth = {
	id = "Behemoth",
	name = "Behemoth",
	role = "Strong but Slow",
	tagline = "Mountains move aside.",
	description = "A colossal armored dragon. Slow to move, but hits like a landslide and shrugs off blows. Breathes molten magma.",
	scale = 1.28,
	build = "bulky",
	colors = {
		primary = rgb(96, 84, 78),
		secondary = rgb(62, 56, 54),
		belly = rgb(160, 120, 88),
		accent = rgb(255, 115, 20),
		eyes = rgb(255, 170, 40),
		wing = rgb(84, 66, 58),
		horn = rgb(214, 198, 166),
	},
	fire = {
		name = "Magma Breath",
		colorA = rgb(255, 200, 60),
		colorB = rgb(200, 30, 0),
		texture = "rbxasset://textures/particles/fire_main.dds",
		lightEmission = 0.9,
		size = 3.2,
		style = "magma",
	},
	stats = {
		health = 160, healthPerLevel = 24,
		attack = 14, attackPerLevel = 2.6,
		defense = 9, defensePerLevel = 2.0,
		crit = 4, critDamage = 150,
		speed = 15, stamina = 70,
	},
	breath = { range = 22, angle = 38, cooldown = 0.75, mult = 1.55, knockback = 18 },
	statBars = { health = 5, attack = 5, speed = 1, defense = 5 },
}

Classes.Frostwyrm = {
	id = "Frostwyrm",
	name = "Frostwyrm",
	role = "Controller",
	tagline = "Everything slows down eventually.",
	description = "An icy wyrm whose freezing breath slows everything it touches. Freezes, shields and blizzards.",
	scale = 1.05,
	build = "sleek",
	colors = {
		primary = rgb(170, 215, 240),
		secondary = rgb(90, 150, 210),
		belly = rgb(235, 245, 255),
		accent = rgb(120, 220, 255),
		eyes = rgb(80, 200, 255),
		wing = rgb(140, 190, 230),
		horn = rgb(220, 240, 255),
	},
	fire = {
		name = "Frost Breath",
		colorA = rgb(255, 255, 255),
		colorB = rgb(90, 180, 255),
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 0.5,
		size = 2.2,
		style = "frost",
	},
	stats = {
		health = 112, healthPerLevel = 16,
		attack = 11, attackPerLevel = 2.2,
		defense = 6, defensePerLevel = 1.5,
		crit = 6, critDamage = 150,
		speed = 19, stamina = 110,
	},
	breath = { range = 25, angle = 32, cooldown = 0.5, mult = 0.95, slowPct = 30, slowDuration = 2 },
	statBars = { health = 3, attack = 3, speed = 3, defense = 3 },
}

Classes.Venomspine = {
	id = "Venomspine",
	name = "Venomspine",
	role = "Poisoner",
	tagline = "One breath is all it takes.",
	description = "A spiny, toxic dragon. Green venom-fire poisons enemies so they keep melting after you fly off.",
	scale = 1.0,
	build = "spiny",
	colors = {
		primary = rgb(60, 110, 50),
		secondary = rgb(30, 60, 30),
		belly = rgb(170, 200, 90),
		accent = rgb(150, 255, 60),
		eyes = rgb(230, 255, 70),
		wing = rgb(50, 90, 45),
		horn = rgb(30, 40, 25),
	},
	fire = {
		name = "Venom Fire",
		colorA = rgb(200, 255, 90),
		colorB = rgb(40, 130, 10),
		texture = "rbxasset://textures/particles/smoke_main.dds",
		lightEmission = 0.7,
		size = 2.4,
		style = "venom",
	},
	stats = {
		health = 106, healthPerLevel = 15,
		attack = 10, attackPerLevel = 2.0,
		defense = 5, defensePerLevel = 1.2,
		crit = 6, critDamage = 150,
		speed = 20, stamina = 110,
	},
	breath = { range = 24, angle = 34, cooldown = 0.5, mult = 0.8, poisonPct = 45 },
	statBars = { health = 3, attack = 4, speed = 3, defense = 2 },
}

function Classes.get(id: string)
	local c = Classes[id]
	if type(c) == "table" and c.id then
		return c
	end
	return nil
end

return Classes
