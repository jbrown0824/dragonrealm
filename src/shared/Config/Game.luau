-- Global tuning knobs. Tweak these to change pacing without touching game code.

local Game = {}

Game.NAME = "Dragon Realm"
Game.DATASTORE_NAME = "DragonRealm_Profiles_v1"

-- Leveling
Game.LEVEL_CAP = 30
Game.TALENT_POINTS_PER_TIER = 4 -- points needed in a branch to unlock each next tier
Game.LOW_LEVEL_XP_PENALTY_GAP = 6 -- enemies this many levels below you give reduced XP
Game.LOW_LEVEL_XP_MULT = 0.25

-- Economy / starting kit
Game.START_GOLD = 60
Game.START_SEEDS = { Emberbloom = 3 }
Game.INVENTORY_LIMIT = 60
Game.MAX_UPGRADE = 10
Game.RESPEC_COST_PER_LEVEL = 20
Game.TRANSFORM_FREE_UNTIL_LEVEL = 5
Game.TRANSFORM_COST_PER_LEVEL = 100

-- Farming
Game.START_PLOTS = 6
Game.MAX_PLOTS = 12
Game.PLOT_COSTS = { 400, 900, 1800, 3000, 4500, 7000 } -- cost of plot 7, 8, ... 12

-- Combat
Game.RESPAWN_TIME = 4
Game.OUT_OF_COMBAT_TIME = 6 -- seconds without taking damage before fast regen kicks in
Game.OUT_OF_COMBAT_REGEN = 0.04 -- fraction of max health per second
Game.DEFENSE_CONSTANT = 100 -- damage reduction = def / (def + DEFENSE_CONSTANT + 5 * attackerLevel)
Game.MAX_DAMAGE_REDUCTION = 0.75
Game.PVP_DAMAGE_MULT = 0.45 -- keeps battles in the Battle Zone from ending instantly
Game.HOME_TELEPORT_COOLDOWN = 15

-- Flight
Game.FLIGHT_DRAIN = 9 -- stamina per second while flying
Game.FLIGHT_REGEN = 16 -- stamina per second while grounded
Game.FLIGHT_SPEED_MULT = 2.2
Game.FLIGHT_SPEED_BONUS = 12
Game.MAX_FLIGHT_HEIGHT = 260

-- Bosses
Game.BOSS_FIRST_SPAWN = 5 * 60 -- seconds after the server starts until the first boss
Game.BOSS_INTERVAL = 15 * 60 -- seconds between boss spawns
Game.BOSS_WARNING = 3 * 60 -- warning + queue window before the boss spawns
Game.BOSS_FIGHT_DURATION = 5 * 60
Game.BOSS_TARGET_FIGHT_SECONDS = 100 -- boss HP is tuned so the queued group kills it in about this long
Game.BOSS_HIT_FRACTION = 0.1 -- a basic boss hit takes about this fraction of the group's average max health

-- Enemies
Game.ENEMY_RESPAWN = 18
Game.ENEMY_LEASH = 110

function Game.xpToNext(level: number): number
	return math.floor(60 * level ^ 1.45 + 40)
end

return Game
