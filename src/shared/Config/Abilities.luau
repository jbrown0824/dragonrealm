-- Every castable ability. Abilities are data-driven: the `kind` decides which code runs,
-- the other fields tune it. Breath and Fireball are known by every dragon; the rest are
-- unlocked from the skill tree (see Config/Talents).
--
-- kinds:
--   breath      cone in front of the dragon (class-specific params in Config/Classes)
--   projectile  fireball-style shots: count, spread (deg), speed, range, radius
--   nova        burst around the dragon: radius
--   strike      delayed blast at the aim point: radius, delay, castRange
--   dash        lunge forward, damaging everything along the path: distance, width
--   buff        timed self buff: duration, stats, stealth, aura, healPct
--   heal        instant heal (healPct of max health), optional follow-up buff
--
-- effects (optional) on damaging abilities:
--   slowPct/slowDuration, stun (seconds), poisonPct / burnPct (% of the hit dealt again
--   over a few seconds), knockback (studs/sec), lifestealBonus (% of damage healed)

local Abilities = {}

Abilities.Breath = {
	id = "Breath",
	name = "Dragon Breath",
	icon = "🔥",
	kind = "breath",
	desc = "Breathe your element in a cone in front of you. Hold to keep breathing.",
}

Abilities.Fireball = {
	id = "Fireball",
	name = "Fireball",
	icon = "☄️",
	kind = "projectile",
	cooldown = 4,
	mult = 2.0,
	speed = 120,
	range = 170,
	radius = 7,
	size = 1.8,
	count = 1,
	desc = "Hurl an exploding ball of your element at your aim point.",
}

---------------------------------------------------------------- signature abilities
-- Every dragon type gets its own one at Game.SIGNATURE_LEVEL (see Classes.X.signature).
Abilities.RendingClaws = {
	id = "RendingClaws", name = "Rending Claws", icon = "💢", kind = "nova", signature = true,
	cooldown = 7, mult = 2.2, radius = 11,
	effects = { lifestealBonus = 25 },
	desc = "Rake everything around you with shadow claws, healing for 25% of the damage dealt.",
}
Abilities.SparkBolt = {
	id = "SparkBolt", name = "Spark Bolt", icon = "⚡", kind = "projectile", signature = true,
	cooldown = 6, mult = 2.3, count = 1, speed = 210, range = 190, radius = 4, size = 1.1,
	effects = { stun = 0.7 },
	desc = "Fire a crackling bolt of lightning that stuns whatever it hits.",
}
Abilities.TailSweep = {
	id = "TailSweep", name = "Tail Sweep", icon = "💫", kind = "nova", signature = true,
	cooldown = 8, mult = 2.1, radius = 14,
	effects = { knockback = 32 },
	desc = "Spin and smash everything around you with your club tail, knocking it back.",
}
Abilities.FrostShards = {
	id = "FrostShards", name = "Frost Shards", icon = "💎", kind = "projectile", signature = true,
	cooldown = 7, mult = 1.15, count = 3, spread = 18, speed = 150, range = 140, radius = 5, size = 1.2,
	effects = { slowPct = 35, slowDuration = 2.5 },
	desc = "Spit three shards of ice that chill and slow what they hit.",
}
Abilities.VenomSpit = {
	id = "VenomSpit", name = "Venom Spit", icon = "🟢", kind = "projectile", signature = true,
	cooldown = 6, mult = 1.2, count = 1, speed = 115, range = 150, radius = 7, size = 1.6,
	effects = { poisonPct = 130 },
	desc = "Spit a big glob of venom that splashes and keeps poisoning everything it touched.",
}

---------------------------------------------------------------- Shadowstalker
Abilities.ShadowPounce = {
	id = "ShadowPounce", name = "Shadow Pounce", icon = "🐾", kind = "dash",
	cooldown = 8, mult = 2.4, distance = 30, width = 9,
	desc = "Lunge forward through the shadows, savaging everything in your path.",
}
Abilities.DeathMark = {
	id = "DeathMark", name = "Death Mark", icon = "💀", kind = "strike", ultimate = true,
	cooldown = 30, mult = 8, radius = 11, delay = 1.0, castRange = 90, style = "shadow",
	desc = "Mark a spot for death. After a moment it erupts in shadowflame for massive damage.",
}
Abilities.Vanish = {
	id = "Vanish", name = "Vanish", icon = "👁️", kind = "buff",
	cooldown = 22, duration = 6, stealth = true, ambushMult = 2,
	desc = "Turn invisible. Vikings lose track of you and your next hit deals +200% damage.",
}
Abilities.Eclipse = {
	id = "Eclipse", name = "Eclipse", icon = "🌑", kind = "buff", ultimate = true,
	cooldown = 45, duration = 8, stats = { attackPct = 40, dodge = 35 },
	desc = "Blot out the sun: +40% attack and +35% dodge for 8 seconds.",
}
Abilities.NightmareBurst = {
	id = "NightmareBurst", name = "Nightmare Burst", icon = "😱", kind = "nova",
	cooldown = 12, mult = 2.2, radius = 16,
	effects = { slowPct = 40, slowDuration = 3 },
	desc = "Release a wave of nightmares that damages and slows nearby enemies.",
}
Abilities.UmbralDevour = {
	id = "UmbralDevour", name = "Umbral Devour", icon = "🕳️", kind = "nova", ultimate = true,
	cooldown = 40, mult = 5, radius = 24,
	effects = { lifestealBonus = 30 },
	desc = "Devour the life of everything around you, healing for 30% of the damage dealt.",
}

---------------------------------------------------------------- Stormwing
Abilities.Thunderclap = {
	id = "Thunderclap", name = "Thunderclap", icon = "👏", kind = "nova",
	cooldown = 12, mult = 2.0, radius = 14,
	effects = { stun = 1 },
	desc = "Clap your wings together with a boom of thunder, stunning nearby enemies.",
}
Abilities.LightningStorm = {
	id = "LightningStorm", name = "Lightning Storm", icon = "🌩️", kind = "strike", ultimate = true,
	cooldown = 35, mult = 7, radius = 18, delay = 0.7, castRange = 100, style = "lightning",
	desc = "Call down a storm of lightning on your aim point.",
}
Abilities.GaleDash = {
	id = "GaleDash", name = "Gale Dash", icon = "💨", kind = "dash",
	cooldown = 5, mult = 1.5, distance = 40, width = 8,
	desc = "Burst forward on the wind, slicing through enemies.",
}
Abilities.Cyclone = {
	id = "Cyclone", name = "Cyclone", icon = "🌪️", kind = "buff", ultimate = true,
	cooldown = 40, duration = 8, stats = { speedPct = 60, dodge = 30 },
	aura = { radius = 12, mult = 0.5, interval = 0.5 },
	desc = "Become a living cyclone: +60% speed, +30% dodge, and shred anything near you.",
}
Abilities.ArcVolley = {
	id = "ArcVolley", name = "Arc Volley", icon = "🔱", kind = "projectile",
	cooldown = 10, mult = 1.6, count = 3, spread = 12, speed = 150, range = 160, radius = 6, size = 1.4,
	desc = "Fire three bolts of ball lightning in a spread.",
}
Abilities.StormBarrage = {
	id = "StormBarrage", name = "Storm Barrage", icon = "🌟", kind = "projectile", ultimate = true,
	cooldown = 30, mult = 1.8, count = 7, spread = 30, speed = 150, range = 170, radius = 7, size = 1.6,
	desc = "Unleash seven bolts of lightning in a wide fan.",
}

---------------------------------------------------------------- Behemoth
Abilities.IronScales = {
	id = "IronScales", name = "Iron Scales", icon = "🛡️", kind = "buff",
	cooldown = 20, duration = 6, stats = { defensePct = 150, thorns = 20 },
	desc = "Harden your scales: +150% defense and reflect 20% of melee damage for 6 seconds.",
}
Abilities.Eruption = {
	id = "Eruption", name = "Eruption", icon = "🌋", kind = "nova",
	cooldown = 14, mult = 2.6, radius = 18,
	effects = { burnPct = 40 },
	desc = "The ground around you erupts with magma, burning enemies.",
}
Abilities.Meteor = {
	id = "Meteor", name = "Meteor", icon = "🌠", kind = "strike", ultimate = true,
	cooldown = 35, mult = 9, radius = 16, delay = 1.2, castRange = 100, style = "meteor",
	effects = { burnPct = 30 },
	desc = "Pull a burning meteor from the sky onto your aim point.",
}
Abilities.GroundSlam = {
	id = "GroundSlam", name = "Ground Slam", icon = "💥", kind = "nova",
	cooldown = 10, mult = 2.4, radius = 14,
	effects = { stun = 1.5, knockback = 30 },
	desc = "Slam the earth, stunning and knocking back nearby enemies.",
}
Abilities.Rampage = {
	id = "Rampage", name = "Rampage", icon = "😤", kind = "buff", ultimate = true,
	cooldown = 45, duration = 10, stats = { attackPct = 50, defensePct = 30, speedPct = 25 },
	desc = "Go on a rampage: +50% attack, +30% defense and +25% speed for 10 seconds.",
}

---------------------------------------------------------------- Frostwyrm
Abilities.FrostNova = {
	id = "FrostNova", name = "Frost Nova", icon = "💠", kind = "nova",
	cooldown = 14, mult = 1.6, radius = 16,
	effects = { stun = 2 },
	desc = "Blast out a ring of frost that freezes nearby enemies solid.",
}
Abilities.IceFortress = {
	id = "IceFortress", name = "Ice Fortress", icon = "🏰", kind = "buff", ultimate = true,
	cooldown = 50, duration = 8, stats = { defensePct = 200 }, healPct = 30,
	desc = "Encase yourself in ice: heal 30% and gain +200% defense for 8 seconds.",
}
Abilities.IcicleRain = {
	id = "IcicleRain", name = "Icicle Rain", icon = "☔", kind = "strike",
	cooldown = 12, mult = 3, radius = 14, delay = 0.8, castRange = 90, style = "ice",
	effects = { slowPct = 40, slowDuration = 3 },
	desc = "Rain jagged icicles on your aim point, slowing survivors.",
}
Abilities.Blizzard = {
	id = "Blizzard", name = "Blizzard", icon = "🌨️", kind = "buff", ultimate = true,
	cooldown = 40, duration = 8,
	aura = { radius = 20, mult = 0.7, interval = 0.5, slowPct = 50 },
	desc = "Surround yourself with a raging blizzard that damages and slows everything nearby.",
}
Abilities.GlacialLance = {
	id = "GlacialLance", name = "Glacial Lance", icon = "🗡️", kind = "projectile",
	cooldown = 8, mult = 3.5, count = 1, speed = 190, range = 200, radius = 4, size = 1.2,
	effects = { slowPct = 50, slowDuration = 2 },
	desc = "Launch a razor-sharp lance of ice that hits hard and slows.",
}
Abilities.AbsoluteZero = {
	id = "AbsoluteZero", name = "Absolute Zero", icon = "🥶", kind = "nova", ultimate = true,
	cooldown = 45, mult = 6, radius = 22,
	effects = { stun = 3 },
	desc = "Drop the temperature to absolute zero, freezing and shattering everything around you.",
}

---------------------------------------------------------------- Venomspine
Abilities.PlagueCloud = {
	id = "PlagueCloud", name = "Plague Cloud", icon = "☁️", kind = "strike",
	cooldown = 12, mult = 1.5, radius = 16, delay = 0.5, castRange = 90, style = "poison",
	effects = { poisonPct = 150 },
	desc = "Spit a cloud of plague onto your aim point. Heavy poison damage over time.",
}
Abilities.Epidemic = {
	id = "Epidemic", name = "Epidemic", icon = "🦠", kind = "nova", ultimate = true,
	cooldown = 40, mult = 3, radius = 24,
	effects = { poisonPct = 200 },
	desc = "Explode in a burst of toxins that poisons everything nearby for huge damage over time.",
}
Abilities.VenomFeast = {
	id = "VenomFeast", name = "Venom Feast", icon = "🍖", kind = "heal",
	cooldown = 20, healPct = 25,
	buff = { duration = 6, stats = { attackPct = 20 } },
	desc = "Feast on your venom: heal 25% of max health and gain +20% attack for 6 seconds.",
}
Abilities.AcidWave = {
	id = "AcidWave", name = "Acid Wave", icon = "🌊", kind = "projectile",
	cooldown = 10, mult = 1.2, count = 5, spread = 40, speed = 110, range = 120, radius = 6, size = 1.4,
	effects = { poisonPct = 60 },
	desc = "Spray five globs of acid in a wide fan.",
}
Abilities.ToxicDeluge = {
	id = "ToxicDeluge", name = "Toxic Deluge", icon = "☠️", kind = "strike", ultimate = true,
	cooldown = 35, mult = 7, radius = 20, delay = 1.0, castRange = 100, style = "poison",
	effects = { poisonPct = 100 },
	desc = "Drown an area in a flood of toxic venom.",
}

function Abilities.get(id: string)
	local a = Abilities[id]
	if type(a) == "table" and a.id then
		return a
	end
	return nil
end

return Abilities
