-- The dragon types. Each has its own look, fire style, stats, skill tree and a signature ability
-- (Config/Abilities) that unlocks at Game.SIGNATURE_LEVEL.
-- Talent trees live in Config/Talents; abilities in Config/Abilities.
--
-- Legendary dragons (`pass` set) are bought with Robux: the game pass Config/Store.Passes[pass]
-- unlocks the type for good (choosing it, or transforming into it for free). They're a little
-- stronger than the five free ones, and each has:
--   * its own primary attack instead of a breath cone: `breath.kind` ("projectile": a stream of
--     shots, "beam": a piercing ray) with that kind's fields, plus its own `name`, `icon`, `desc`
--   * a `bonus` ability that unlocks at Game.BONUS_LEVEL, on top of the signature
-- `icon` is the type's emblem (HUD card), `fire.icon` the primary attack's key.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Classes = {}

Classes.Order = { "Shadowstalker", "Stormwing", "Behemoth", "Frostwyrm", "Venomspine", "Tidecaller", "Solaris" }

Classes.Shadowstalker = {
	id = "Shadowstalker",
	name = "Shadowstalker",
	icon = "🌑",
	signature = "RendingClaws", -- unique ability unlocked at Game.SIGNATURE_LEVEL
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
		icon = "💜",
		colorA = rgb(205, 120, 255),
		colorB = rgb(70, 10, 120),
		texture = "rbxasset://textures/particles/fire_main.dds",
		lightEmission = 0.8,
		size = 2.4,
		style = "shadow",
	},
	stats = {
		health = 100, healthPerLevel = 21,
		attack = 12, attackPerLevel = 3.1,
		defense = 4, defensePerLevel = 1.35,
		crit = 12, critDamage = 160,
		speed = 21, stamina = 110,
	},
	breath = { range = 24, angle = 32, cooldown = 0.45, mult = 1.0, critBonus = 8 },
	statBars = { health = 2, attack = 4, speed = 4, defense = 2 },
}

Classes.Stormwing = {
	id = "Stormwing",
	name = "Stormwing",
	icon = "⚡",
	signature = "SparkBolt", -- unique ability unlocked at Game.SIGNATURE_LEVEL
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
		icon = "🌬️",
		colorA = rgb(215, 250, 255),
		colorB = rgb(40, 110, 255),
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		size = 1.9,
		style = "storm",
	},
	stats = {
		health = 92, healthPerLevel = 18,
		attack = 11, attackPerLevel = 2.85,
		defense = 3, defensePerLevel = 1.2,
		crit = 8, critDamage = 150,
		speed = 25, stamina = 170,
	},
	breath = { range = 27, angle = 28, cooldown = 0.35, mult = 0.8 },
	statBars = { health = 2, attack = 3, speed = 5, defense = 1 },
}

Classes.Behemoth = {
	id = "Behemoth",
	name = "Behemoth",
	icon = "🌋",
	signature = "TailSweep", -- unique ability unlocked at Game.SIGNATURE_LEVEL
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
		icon = "🔥",
		colorA = rgb(255, 200, 60),
		colorB = rgb(200, 30, 0),
		texture = "rbxasset://textures/particles/fire_main.dds",
		lightEmission = 0.9,
		size = 3.2,
		style = "magma",
	},
	stats = {
		health = 160, healthPerLevel = 33,
		attack = 14, attackPerLevel = 3.5,
		defense = 9, defensePerLevel = 2.7,
		crit = 4, critDamage = 150,
		speed = 15, stamina = 70,
	},
	breath = { range = 22, angle = 38, cooldown = 0.75, mult = 1.55, knockback = 18 },
	statBars = { health = 5, attack = 5, speed = 1, defense = 5 },
}

Classes.Frostwyrm = {
	id = "Frostwyrm",
	name = "Frostwyrm",
	icon = "❄️",
	signature = "FrostShards", -- unique ability unlocked at Game.SIGNATURE_LEVEL
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
		icon = "❄️",
		colorA = rgb(255, 255, 255),
		colorB = rgb(90, 180, 255),
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 0.5,
		size = 2.2,
		style = "frost",
	},
	stats = {
		health = 112, healthPerLevel = 22,
		attack = 11, attackPerLevel = 3.0,
		defense = 6, defensePerLevel = 2.0,
		crit = 6, critDamage = 150,
		speed = 19, stamina = 110,
	},
	breath = { range = 25, angle = 32, cooldown = 0.5, mult = 0.95, slowPct = 30, slowDuration = 2 },
	statBars = { health = 3, attack = 3, speed = 3, defense = 3 },
}

Classes.Venomspine = {
	id = "Venomspine",
	name = "Venomspine",
	icon = "🐍",
	signature = "VenomSpit", -- unique ability unlocked at Game.SIGNATURE_LEVEL
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
		icon = "🧪",
		colorA = rgb(200, 255, 90),
		colorB = rgb(40, 130, 10),
		texture = "rbxasset://textures/particles/smoke_main.dds",
		lightEmission = 0.7,
		size = 2.4,
		style = "venom",
	},
	stats = {
		health = 106, healthPerLevel = 21,
		attack = 10, attackPerLevel = 2.7,
		defense = 5, defensePerLevel = 1.6,
		crit = 6, critDamage = 150,
		speed = 20, stamina = 110,
	},
	breath = { range = 24, angle = 34, cooldown = 0.5, mult = 0.8, poisonPct = 45 },
	statBars = { health = 3, attack = 4, speed = 3, defense = 2 },
}

---------------------------------------------------------------- Legendary dragons (Robux)

-- A sea dragon: fin wings like a manta's, a sail down its back, gill frills and whiskers, and a
-- whale's fluke for a tail. It doesn't breathe a cone: it spits a quick stream of water orbs
-- that reach much farther, splash and soak (slow) what they hit.
Classes.Tidecaller = {
	id = "Tidecaller",
	name = "Tidecaller",
	icon = "🌊",
	pass = "TidecallerDragon",
	signature = "Riptide",
	bonus = "TidalSurge", -- unlocks at Game.BONUS_LEVEL
	role = "Legendary • Tides",
	tagline = "The sea remembers every shore.",
	description = "A sea dragon from the deep. Rapid water shots from range, whirlpools that drag vikings in, and healing tides.",
	scale = 1.06,
	build = "sea",
	colors = {
		primary = rgb(22, 112, 132),
		secondary = rgb(12, 58, 92),
		belly = rgb(196, 238, 226),
		accent = rgb(80, 255, 225),
		eyes = rgb(255, 222, 110),
		wing = rgb(40, 190, 205),
		horn = rgb(232, 248, 246),
	},
	fire = {
		name = "Tide Shot",
		icon = "💧",
		colorA = rgb(190, 250, 255),
		colorB = rgb(20, 120, 225),
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 0.8,
		size = 1.0,
		style = "tide",
	},
	stats = {
		health = 124, healthPerLevel = 24,
		attack = 13, attackPerLevel = 3.3,
		defense = 6, defensePerLevel = 1.9,
		crit = 10, critDamage = 160,
		speed = 22, stamina = 150,
	},
	-- hold to fire: 3+ orbs a second out to 95 studs (a breath cone reaches ~24)
	breath = {
		kind = "projectile", name = "Tide Shot", icon = "💧",
		desc = "Hold to spit a rapid stream of water orbs. They reach far, splash, and soak what they hit (slowed).",
		range = 95, cooldown = 0.3, mult = 0.7, speed = 150, radius = 3.5, size = 0.9, count = 1,
		slowPct = 15, slowDuration = 1.5,
	},
	statBars = { health = 4, attack = 5, speed = 4, defense = 3 },
}

-- A radiant sun dragon: ivory scales under gilded armor, feathered wings over a sunlit membrane,
-- a blazing sunburst halo behind a crown of horns, and a phoenix-plume tail. Its primary attack is a beam of
-- sunlight that pierces everything in a long line.
Classes.Solaris = {
	id = "Solaris",
	name = "Solaris",
	icon = "☀️",
	pass = "SolarisDragon",
	signature = "SolarFlare",
	bonus = "Sunfall", -- unlocks at Game.BONUS_LEVEL
	role = "Legendary • Sunfire",
	tagline = "Kneel, and be warmed. Stand, and be burned.",
	description = "A crowned dragon of the sun. A piercing beam of sunlight, pillars of sunfire from the sky, and a phoenix's rebirth.",
	scale = 1.12,
	build = "radiant",
	colors = {
		primary = rgb(252, 245, 230),
		secondary = rgb(236, 180, 64),
		belly = rgb(255, 226, 160),
		accent = rgb(255, 146, 20),
		eyes = rgb(255, 250, 200),
		wing = rgb(255, 202, 86),
		horn = rgb(255, 224, 140),
	},
	fire = {
		name = "Solar Beam",
		icon = "🔆",
		colorA = rgb(255, 248, 190),
		colorB = rgb(255, 140, 20),
		texture = "rbxasset://textures/particles/sparkles_main.dds",
		lightEmission = 1,
		size = 1.6,
		style = "solar",
	},
	stats = {
		health = 118, healthPerLevel = 23,
		attack = 12, attackPerLevel = 3.15,
		defense = 5, defensePerLevel = 1.7,
		crit = 8, critDamage = 150,
		speed = 21, stamina = 140,
	},
	-- hold to keep the beam on: it pierces everything along a 55-stud line
	breath = {
		kind = "beam", name = "Solar Beam", icon = "🔆",
		desc = "Hold to pour out a beam of sunlight. It burns through everything in a long line, and wins more crits.",
		range = 55, width = 5, cooldown = 0.25, mult = 0.6, critBonus = 5,
	},
	statBars = { health = 3, attack = 4, speed = 4, defense = 3 },
}


function Classes.get(id: string)
	local c = Classes[id]
	if type(c) == "table" and c.id then
		return c
	end
	return nil
end

return Classes
