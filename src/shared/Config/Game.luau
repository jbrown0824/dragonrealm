-- Global tuning knobs. Tweak these to change pacing without touching game code.

local Game = {}

Game.NAME = "Dragon Realm"
Game.DATASTORE_NAME = "DragonRealm_Profiles_v1"

-- Leveling
Game.LEVEL_CAP = 30
Game.TALENT_POINTS_PER_TIER = 4 -- points needed in a branch to unlock each next tier
Game.SIGNATURE_LEVEL = 3 -- each dragon type's own ability unlocks here (goes on key 1)
Game.LOW_LEVEL_XP_PENALTY_GAP = 6 -- enemies this many levels below you give reduced XP
Game.LOW_LEVEL_XP_MULT = 0.25

-- Economy / starting kit
Game.START_GOLD = 60
Game.START_SEEDS = { Emberbloom = 3 }
Game.INVENTORY_LIMIT = 60
Game.MAX_UPGRADE = 10
Game.RESPEC_COST_PER_LEVEL = 20
Game.TRANSFORM_FREE_UNTIL_LEVEL = 5
Game.TRANSFORM_COST = 50

-- Farming
Game.START_PLOTS = 6
Game.MAX_PLOTS = 12
Game.PLOT_COSTS = { 400, 900, 1800, 3000, 4500, 7000 } -- cost of plot 7, 8, ... 12

-- Garden robots, bought at the Bot Dock in your lair.
Game.ROBOTS = {
	Water = { name = "Drizzle-Bot", icon = "💧", cost = 1500, delay = 3,
		desc = "Hovers over your garden and waters any plant that asks for it." },
	Harvest = { name = "Reap-Bot", icon = "🌾", delay = 2, levels = {
		{ cost = 5000, desc = "Harvests flowers the moment they reach full bloom and brings you the gold and seeds." },
		{ cost = 12000, desc = "Upgrade: also replants the same seed in the empty spot." },
	} },
}

-- Combat
Game.RESPAWN_TIME = 4
Game.OUT_OF_COMBAT_TIME = 6 -- seconds without taking damage before fast regen kicks in
Game.OUT_OF_COMBAT_REGEN = 0.04 -- fraction of max health per second
-- Lifesteal (% of damage dealt healed) and regen (% of max health healed per second) caps. Gear
-- relics and pets share their own smaller cap on top of what talents give, so stacking them never
-- makes a dragon unkillable. All four can be tuned live in the admin panel.
Game.LIFESTEAL_CAP = 30
Game.REGEN_CAP = 3
Game.EXTRA_LIFESTEAL_CAP = 8
Game.EXTRA_REGEN_CAP = 0.8

-- Level gap: hitting something lower level than you hurts it more, something higher level less.
-- With d = your level - theirs: d > 0 multiplies the damage by 1 + linear*d + curve*d^2 (mild for
-- the first few levels, bigger past 10), at most `cap`; d < 0 divides by the same (at least
-- `floor`). It works both ways (dragons hitting monsters, monsters hitting dragons), but not in
-- PvP or the world boss arena. The admin Balance page tunes linear, curve and cap.
Game.LEVEL_GAP = { linear = 0.02, curve = 0.004, cap = 2.5, floor = 0.4 }
Game.DEFENSE_CONSTANT = 100 -- damage reduction = def / (def + DEFENSE_CONSTANT + 5 * attackerLevel)
Game.MAX_DAMAGE_REDUCTION = 0.75
Game.PVP_DAMAGE_MULT = 0.45 -- keeps battles in the Battle Zone from ending instantly
Game.HOME_TELEPORT_COOLDOWN = 15

-- Player dragons and the camera. Dragons are 20-40 studs long, so Roblox's default 12.5-stud
-- camera starts inside the tail. Your first dragon each session starts the camera about a body
-- length back (Movement.frameDragon); you can still zoom in to CAMERA_MIN_ZOOM or out to MAX.
Game.PLAYER_DRAGON_SCALE = 0.9 -- player dragons only (villagers, pets and statues keep their size)
Game.CAMERA_START_ZOOM = 1.0 -- x the dragon's length, plus 6 studs
Game.CAMERA_MIN_ZOOM = 10
Game.CAMERA_MAX_ZOOM = 160

-- Flight
Game.FLIGHT_DRAIN = 9 -- stamina per second while flying
Game.FLIGHT_REGEN = 16 -- stamina per second while grounded
Game.FLIGHT_SPEED_MULT = 2.2
Game.FLIGHT_SPEED_BONUS = 12
Game.MAX_FLIGHT_HEIGHT = 260

-- Hunger. A full belly lasts about 17 minutes out in the wilds (twice that in town).
Game.HUNGER_MAX = 100
Game.HUNGER_DRAIN = 0.1 -- per second
Game.HUNGER_FLYING_MULT = 1.6
Game.HUNGER_TOWN_MULT = 0.5
Game.HUNGER_AFTER_DEATH = 30 -- you respawn with at least this much
Game.HUNGER_LEVELS = { -- checked in order; the first one you're below applies
	{ below = 12, id = "Starving", icon = "😵", color = Color3.fromRGB(255, 80, 80),
		stats = { attackPct = -25, flightSpeedPct = -35, staminaPct = -40 } },
	{ below = 35, id = "Hungry", icon = "😋", color = Color3.fromRGB(255, 190, 80),
		stats = { attackPct = -10, flightSpeedPct = -15, staminaPct = -20 } },
}
Game.FOOD_BAG_LIMIT = 30
Game.EAT_HEAL_PCT = 10 -- eating also heals this % of max health

-- Pets
Game.PET_LIMIT = 30
Game.PET_SLOT_LEVELS = { 1, 10, 20 } -- one more pet can follow you at each of these levels

-- Day and night (shared/DayNight). A day runs from DAWN_HOUR to DUSK_HOUR on the Lighting
-- clock, and the night wraps round from dusk to dawn in less real time, so nights pass quicker.
Game.DAY_SECONDS = 9 * 60
Game.NIGHT_SECONDS = 6 * 60
Game.DAWN_HOUR = 6
Game.DUSK_HOUR = 18
Game.START_HOUR = 10 -- where the clock starts when a server boots

-- Bosses
Game.BOSS_FIRST_SPAWN = 5 * 60 -- seconds after the server starts until the first boss
Game.BOSS_INTERVAL = 15 * 60 -- seconds between boss spawns
Game.BOSS_WARNING = 90 -- warning + queue window before the boss spawns
Game.BOSS_FIGHT_DURATION = 5 * 60
Game.BOSS_TARGET_FIGHT_SECONDS = 100 -- boss HP is tuned so the queued group kills it in about this long
Game.BOSS_HIT_FRACTION = 0.1 -- a basic boss hit takes about this fraction of the group's average max health
Game.BOSS_LIVES = 3 -- deaths allowed per player in a boss fight before they're knocked out

-- Enemies
Game.ENEMY_RESPAWN = 18
Game.ENEMY_LEASH = 110
-- Vikings respawn slower while few dragons are in their camp, so a lone dragon can clear it
-- and open the chest. Index = dragons in the camp (1, 2, 3, 4 or more). Empty camps use 1.
Game.CAMP_RESPAWN_MULT = { 2.6, 1.8, 1.3, 1.0 }
Game.CHEST_RESPAWN = 5 * 60
Game.ALARM_DURATION = 30 -- how long a sounded alarm keeps the whole camp hunting you
Game.ALARM_COOLDOWN = 40
Game.ANIMAL_RESPAWN = 35

function Game.xpToNext(level: number): number
	return math.floor(60 * level ^ 1.45 + 40)
end

-- Paragon: past the level cap, XP keeps filling Paragon levels. Each one adds a small permanent
-- bonus (up to PARAGON_BONUS_CAP levels), and every PARAGON_POINT_EVERY levels gives an extra
-- skill point, so long-time players can slowly fill more of their skill tree.
Game.PARAGON_POINT_EVERY = 5
Game.PARAGON_BONUS = { attackPct = 0.3, healthPct = 0.3 } -- per Paragon level
Game.PARAGON_BONUS_CAP = 100

function Game.paragonXp(paragon: number): number
	return math.floor(8000 * (1 + 0.02 * paragon))
end

function Game.transformCost(level: number): number
	return level < Game.TRANSFORM_FREE_UNTIL_LEVEL and 0 or Game.TRANSFORM_COST
end

function Game.petSlots(level: number): number
	local n = 0
	for _, need in ipairs(Game.PET_SLOT_LEVELS) do
		if level >= need then
			n += 1
		end
	end
	return n
end

function Game.hungerLevel(hunger: number)
	for _, lvl in ipairs(Game.HUNGER_LEVELS) do
		if hunger < lvl.below then
			return lvl
		end
	end
	return nil
end

function Game.campRespawnMult(dragons: number): number
	if dragons <= 0 then
		return 1
	end
	return Game.CAMP_RESPAWN_MULT[math.min(dragons, #Game.CAMP_RESPAWN_MULT)]
end

return Game
