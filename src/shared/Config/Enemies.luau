-- Viking enemies and bosses.
-- Stats are for level 1; EnemyService scales them by level:
--   health * (1 + HEALTH_PER_LEVEL * (level - 1)), damage * (1 + DAMAGE_PER_LEVEL * (level - 1))

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Enemies = {}

Enemies.HEALTH_PER_LEVEL = 0.45
Enemies.DAMAGE_PER_LEVEL = 0.2

Enemies.Vikings = {
	Raider = {
		id = "Raider", name = "Viking Raider",
		health = 55, damage = 7, speed = 14, defense = 2,
		attackRange = 7, attackCooldown = 1.6,
		throwDamage = 0.6, throwCooldown = 4.5, throwRange = 55, preferredRange = 0,
		xpMult = 1, gearChance = 0.16, seedChance = 0.02, goldMult = 1,
		scale = 1.0,
		look = { shirt = rgb(150, 40, 35), pants = rgb(90, 70, 50), beard = rgb(200, 110, 40), weapon = "axe", shield = true },
	},
	AxeThrower = {
		id = "AxeThrower", name = "Axe Thrower",
		health = 45, damage = 8, speed = 13, defense = 1,
		attackRange = 6, attackCooldown = 1.8,
		throwDamage = 1.0, throwCooldown = 2.4, throwRange = 70, preferredRange = 35,
		xpMult = 1.1, gearChance = 0.18, seedChance = 0.02, goldMult = 1.1,
		scale = 0.95,
		look = { shirt = rgb(50, 95, 60), pants = rgb(70, 60, 45), beard = rgb(120, 70, 30), weapon = "axe", shield = false, quiver = true },
	},
	Shieldbearer = {
		id = "Shieldbearer", name = "Shieldbearer",
		health = 110, damage = 8, speed = 11, defense = 18,
		attackRange = 7, attackCooldown = 1.8,
		throwDamage = 0.5, throwCooldown = 5, throwRange = 45, preferredRange = 0,
		xpMult = 1.4, gearChance = 0.22, seedChance = 0.03, goldMult = 1.3,
		scale = 1.12,
		look = { shirt = rgb(60, 70, 120), pants = rgb(60, 55, 50), beard = rgb(230, 200, 120), weapon = "hammer", shield = true, bigShield = true },
	},
	Berserker = {
		id = "Berserker", name = "Berserker",
		health = 70, damage = 13, speed = 19, defense = 0,
		attackRange = 7, attackCooldown = 1.1,
		throwDamage = 0.6, throwCooldown = 4, throwRange = 50, preferredRange = 0,
		xpMult = 1.4, gearChance = 0.22, seedChance = 0.03, goldMult = 1.3,
		scale = 1.05,
		look = { shirt = rgb(120, 90, 60), pants = rgb(60, 40, 30), beard = rgb(160, 40, 20), weapon = "twinAxe", shield = false, warpaint = true },
	},
	Hornblower = {
		id = "Hornblower", name = "Hornblower", alarm = true,
		health = 60, damage = 8, speed = 13, defense = 4,
		attackRange = 7, attackCooldown = 1.7,
		throwDamage = 0.6, throwCooldown = 5, throwRange = 50, preferredRange = 0,
		xpMult = 1.3, gearChance = 0.2, seedChance = 0.03, goldMult = 1.3,
		scale = 1.0, aggroRange = 60,
		look = { shirt = rgb(150, 120, 40), pants = rgb(60, 50, 40), beard = rgb(220, 170, 90), weapon = "horn", shield = false, cape = rgb(120, 90, 30) },
	},
	Chieftain = {
		id = "Chieftain", name = "Viking Chieftain", elite = true,
		health = 280, damage = 16, speed = 14, defense = 20,
		attackRange = 9, attackCooldown = 1.5,
		throwDamage = 1.0, throwCooldown = 3.5, throwRange = 70, preferredRange = 0,
		xpMult = 4, gearChance = 1.0, seedChance = 0.08, goldMult = 4, minRarity = "Uncommon",
		scale = 1.4,
		look = { shirt = rgb(110, 20, 20), pants = rgb(40, 30, 25), beard = rgb(240, 240, 240), weapon = "greatAxe", shield = true, cape = rgb(160, 20, 20), crown = true },
	},
}

-- One mini-boss lives in each camp (keyed by camp id). They're big versions of a viking type
-- with a skull on their health bar, a telegraphed slam, better loot and a long respawn.
--   slam: radius, mult (x their damage), cooldown, delay (telegraph time)
Enemies.MiniBosses = {
	RaiderCamp = {
		id = "BjornBruiser", base = "Raider", name = "Bjorn the Bruiser", level = 5,
		healthMult = 7, damageMult = 1.5, scale = 1.75, respawn = 180,
		slam = { radius = 13, mult = 1.8, cooldown = 9, delay = 1.3 },
		look = { shirt = rgb(120, 30, 30), pants = rgb(70, 50, 35), beard = rgb(230, 120, 40), weapon = "greatAxe", shield = false, cape = rgb(90, 20, 20), warpaint = true },
	},
	FishingVillage = {
		id = "OldSaltSigrid", base = "AxeThrower", name = "Old Salt Sigrid", level = 11,
		healthMult = 6.5, damageMult = 1.5, scale = 1.7, respawn = 200,
		slam = { radius = 14, mult = 1.8, cooldown = 9, delay = 1.3 },
		look = { shirt = rgb(40, 80, 110), pants = rgb(60, 55, 45), hair = rgb(235, 235, 240), weapon = "twinAxe", shield = false, cape = rgb(30, 60, 90), quiver = true },
	},
	LonghouseHold = {
		id = "ThaneUlfric", base = "Shieldbearer", name = "Thane Ulfric Ironside", level = 18,
		healthMult = 6.5, damageMult = 1.55, scale = 1.8, respawn = 220,
		slam = { radius = 15, mult = 2.0, cooldown = 8, delay = 1.2 },
		look = { shirt = rgb(50, 60, 110), pants = rgb(45, 45, 50), beard = rgb(170, 170, 180), weapon = "hammer", shield = true, bigShield = true, cape = rgb(40, 50, 100), crown = true },
	},
	JarlsFortress = {
		id = "HildaBloodaxe", base = "Berserker", name = "Hilda Bloodaxe", level = 29,
		healthMult = 7, damageMult = 1.6, scale = 1.9, respawn = 240,
		slam = { radius = 16, mult = 2.1, cooldown = 7, delay = 1.1 },
		look = { shirt = rgb(110, 20, 30), pants = rgb(40, 25, 25), hair = rgb(200, 60, 30), weapon = "twinAxe", shield = false, cape = rgb(80, 10, 20), warpaint = true, crown = true },
	},
}
Enemies.MINI_BOSS_LOOT = { minRarity = "Rare", seedChance = 0.3, eggChance = 0.12, goldMult = 10, xpMult = 8 }

-- Boss attacks are shared building blocks; each boss picks a set and tunes them.
--   Cleave:      melee swing in front of the boss
--   AxeVolley:   throws axes at several players
--   GroundSlam:  telegraphed ring around the boss
--   RuneStrikes: telegraphed circles under players
--   Summon:      calls in viking adds
Enemies.Bosses = {
	JarlRagnar = {
		id = "JarlRagnar", name = "Jarl Ragnar Frostbeard", title = "The Frost Jarl",
		scale = 3.2, speed = 15,
		look = { shirt = rgb(70, 110, 160), pants = rgb(50, 60, 80), beard = rgb(235, 245, 255), weapon = "greatAxe", shield = true, cape = rgb(200, 230, 255), crown = true, glow = rgb(140, 220, 255) },
		color = rgb(140, 220, 255),
		attacks = {
			Cleave = { cooldown = 2.4, mult = 1.0, range = 16 },
			AxeVolley = { cooldown = 7, mult = 0.8, count = 4 },
			GroundSlam = { cooldown = 11, mult = 2.2, radius = 24, delay = 1.6, slowPct = 40 },
			Summon = { add = "Raider", count = 3 },
		},
		uniques = { "FrostbeardCrown", "RagnarsIcebreaker" },
	},
	Grimhilda = {
		id = "Grimhilda", name = "Grimhilda the Stormcaller", title = "Witch of the Fjords",
		scale = 2.9, speed = 13,
		look = { shirt = rgb(60, 30, 90), pants = rgb(40, 25, 60), beard = nil, hair = rgb(230, 230, 240), weapon = "staff", shield = false, cape = rgb(90, 40, 140), glow = rgb(190, 120, 255) },
		color = rgb(190, 120, 255),
		attacks = {
			Cleave = { cooldown = 3, mult = 0.9, range = 14 },
			RuneStrikes = { cooldown = 7, mult = 1.6, radius = 10, delay = 1.7, count = 5 },
			AxeVolley = { cooldown = 9, mult = 0.7, count = 6 },
			Summon = { add = "AxeThrower", count = 3 },
		},
		uniques = { "StormcallerCharm", "GrimhildasVeil" },
	},
	Hrothgar = {
		id = "Hrothgar", name = "Hrothgar the Dragonslayer", title = "Bane of Wings",
		scale = 3.5, speed = 16,
		look = { shirt = rgb(90, 60, 40), pants = rgb(50, 40, 30), beard = rgb(90, 50, 20), weapon = "greatAxe", shield = true, bigShield = true, cape = rgb(40, 40, 40), crown = true, glow = rgb(255, 120, 60) },
		color = rgb(255, 120, 60),
		attacks = {
			Cleave = { cooldown = 2.2, mult = 1.1, range = 18 },
			GroundSlam = { cooldown = 10, mult = 2.4, radius = 26, delay = 1.5 },
			RuneStrikes = { cooldown = 9, mult = 1.5, radius = 9, delay = 1.8, count = 4 },
			Summon = { add = "Berserker", count = 3 },
		},
		uniques = { "DragonslayerBane", "HrothgarsHeart" },
	},
}

Enemies.BossOrder = { "JarlRagnar", "Grimhilda", "Hrothgar" }

return Enemies
