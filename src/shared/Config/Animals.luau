-- Wild animals in the hunting grounds. Killing one leaves a carcass you can eat on the spot
-- (refills hunger) or pack up as food for later. Stats are for level 1 and scale with level
-- like vikings do (Enemies.HEALTH_PER_LEVEL / DAMAGE_PER_LEVEL).
--
-- behavior:
--   flee        runs away when a dragon comes close or hurts it; never fights back
--   neutral     minds its own business until you hurt it, then fights
--   aggressive  attacks any dragon that comes within aggroRange
-- look: body sizes in studs (before `scale`) and parts for AnimalBuilder.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Animals = {}

Animals.Deer = {
	id = "Deer", name = "Red Deer", behavior = "flee", fleeRange = 30,
	health = 40, damage = 0, speed = 24, defense = 0,
	xpMult = 0.6, meat = "Venison", scale = 1.0,
	look = { body = rgb(160, 100, 60), belly = rgb(235, 215, 185), legs = rgb(120, 80, 50), nose = rgb(40, 30, 25),
		bodyL = 4.4, bodyH = 1.9, bodyW = 1.6, legLen = 2.9, legThick = 0.45, neckLen = 2.0, headL = 1.5,
		antlers = true, tail = "short", ears = true },
}

Animals.Goat = {
	id = "Goat", name = "Mountain Goat", behavior = "flee", fleeRange = 24,
	health = 34, damage = 0, speed = 20, defense = 1,
	xpMult = 0.5, meat = "GoatChop", scale = 0.85,
	look = { body = rgb(225, 222, 212), belly = rgb(245, 243, 235), legs = rgb(150, 140, 130), nose = rgb(60, 55, 50),
		bodyL = 3.6, bodyH = 1.9, bodyW = 1.6, legLen = 2.1, legThick = 0.45, neckLen = 1.2, headL = 1.3,
		curledHorns = true, beard = true, tail = "short", ears = true },
}

Animals.Boar = {
	id = "Boar", name = "Wild Boar", behavior = "neutral",
	health = 75, damage = 8, speed = 18, defense = 3,
	attackRange = 5, attackCooldown = 1.5,
	xpMult = 0.8, meat = "BoarHaunch", scale = 1.0,
	look = { body = rgb(90, 65, 45), belly = rgb(120, 95, 70), legs = rgb(60, 45, 35), nose = rgb(190, 130, 120),
		bodyL = 4.0, bodyH = 2.3, bodyW = 2.0, legLen = 1.4, legThick = 0.6, neckLen = 0.5, headL = 1.8,
		tusks = true, mane = rgb(50, 35, 25), tail = "thin", ears = true },
}

Animals.Wolf = {
	id = "Wolf", name = "Timber Wolf", behavior = "aggressive", aggroRange = 38,
	health = 58, damage = 10, speed = 23, defense = 2,
	attackRange = 5, attackCooldown = 1.3,
	xpMult = 0.9, meat = "WolfSteak", scale = 1.0,
	look = { body = rgb(120, 115, 110), belly = rgb(200, 195, 185), legs = rgb(95, 90, 88), nose = rgb(25, 25, 28),
		bodyL = 3.8, bodyH = 1.7, bodyW = 1.4, legLen = 2.2, legThick = 0.42, neckLen = 1.0, headL = 1.6,
		snout = true, pointyEars = true, tail = "bushy", eyes = rgb(255, 210, 60) },
}

Animals.SnowWolf = {
	id = "SnowWolf", name = "Frost Wolf", behavior = "aggressive", aggroRange = 42,
	health = 64, damage = 11, speed = 24, defense = 3,
	attackRange = 5, attackCooldown = 1.2,
	xpMult = 1.0, meat = "WolfSteak", scale = 1.1,
	look = { body = rgb(230, 235, 245), belly = rgb(250, 252, 255), legs = rgb(200, 205, 220), nose = rgb(40, 45, 60),
		bodyL = 3.8, bodyH = 1.7, bodyW = 1.4, legLen = 2.2, legThick = 0.42, neckLen = 1.0, headL = 1.6,
		snout = true, pointyEars = true, tail = "bushy", eyes = rgb(120, 220, 255) },
}

Animals.Bear = {
	id = "Bear", name = "Cave Bear", behavior = "aggressive", aggroRange = 30,
	health = 190, damage = 20, speed = 17, defense = 8,
	attackRange = 7, attackCooldown = 1.8,
	xpMult = 2.2, meat = "BearRoast", scale = 1.6,
	look = { body = rgb(95, 65, 40), belly = rgb(120, 85, 55), legs = rgb(75, 50, 32), nose = rgb(30, 22, 18),
		bodyL = 4.2, bodyH = 2.6, bodyW = 2.4, legLen = 1.6, legThick = 0.85, neckLen = 0.6, headL = 1.6,
		roundEars = true, hump = true, tail = "short" },
}

function Animals.get(id: string)
	local a = Animals[id]
	if type(a) == "table" and a.id then
		return a
	end
	return nil
end

return Animals
