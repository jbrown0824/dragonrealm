-- Dungeons: small group adventures (1-4 dragons) with packs of monsters, a mini-boss and a boss at
-- the end. Each dungeon has a fixed level (it doesn't grow with the dragons in it); mob and boss
-- health and damage only shift a little with the group's size (GROUP_HEALTH / GROUP_DAMAGE).
--
-- Layouts are data. Coordinates are local to the dungeon's origin (Dungeons.origin) and y is the
-- floor height. DungeonBuilder carves them out of terrain rock:
--   spaces:   box   { at, size = Vector2 (x width, z depth), height }
--             round { at, radius, height, dome? }                     (dome: a rounded ceiling)
--             path  { points = { floor points }, width, height }      (tunnels; slopes follow the y)
--   features: pillars { points, radius, height }   pool { min, max, depth, water }
--             walkway { from, to, width }   ledge { min, max }   ramp { from, to, width }
--             lava { min, max, depth }   bridge { from, to, width }
--             spiral { center, inner, outer, from, to, topY, bottomY, baseY } (angles in degrees,
--                    0 = +x, 90 = +z; a ramp winding down around a pit whose floor is at baseY)
--   decor:    brazier { at }  sarcophagus { at, face }  stones { center, radius, count, skip }
--             throne { at, face }  bones { at, spread, count }  anvils { at }  forge { at, face }
--             rack { at, face }  chains { from, to }  runes { center, radius }  shields { at, face }
--   packs:    { at, mobs = { typeId... } } or { spots = { { typeId, at }... } }
--   hazards:  lava a dragon shouldn't stand in: { min, max } boxes or { center, radius, top }
--   routes:   extra walks the dungeon check makes sure are open (over the bridges, up the ramps);
--             rooms with `hub = false` have no walkable middle (a lava channel, a pit)
-- Mob types live in Enemies.Dungeon; bosses (their moves and traits, see server/Combat/BossKit)
-- are below.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local V = Vector3.new
local V2 = Vector2.new

local Dungeons = {}

Dungeons.UNLOCK_LEVEL = 15 -- the 🏰 Dungeons menu button shows up here
Dungeons.MAX_GROUP = 4

-- Health and damage by how many dragons came in (1, 2, 3, 4). Admin Tuning "groupScaling"
-- stretches how far below 1 the small groups go.
Dungeons.GROUP_HEALTH = { 0.55, 0.7, 0.85, 1 }
Dungeons.GROUP_DAMAGE = { 0.7, 0.8, 0.9, 1 }

-- Combat rules inside a dungeon
Dungeons.COMBAT_LINGER = 5 -- a mob counts as "in combat" this long after its last hit either way
Dungeons.EVADE_TIME = 12 -- no damage either way for this long: the mob gives up and walks home
Dungeons.RETURN_STUCK = 8 -- walking home this long without getting there: put it back home
Dungeons.MOB_REGEN = 0.04 -- of max health per second while out of combat
Dungeons.BOSS_REGEN = 0.02
Dungeons.REVIVE_DELAY = 3 -- after the group is out of combat, the knocked-out get back up
Dungeons.REVIVE_HEALTH = 0.5
Dungeons.WIPE_DELAY = 4 -- everyone down: back to the entrance, and the monsters reset
Dungeons.LAVA_BURN = 0.06 -- of max health per second standing in lava
Dungeons.MOB_LEASH = 90
Dungeons.BOSS_AGGRO = 42 -- a boss wakes up when a dragon comes this close (or hits it)

-- Groups and the queue
Dungeons.INVITE_TIME = 30
Dungeons.READY_TIME = 30
Dungeons.QUEUE_PARTIAL_AFTER = 90 -- after this long in the queue, 2 or 3 dragons are enough to go
Dungeons.CLEARED_STAY = 180 -- after the boss falls you can look around this long, then it's home time

-- Loot
Dungeons.BOSS_XP = 0.35 -- of your level's XP bar (Paragon XP past the cap)
Dungeons.MINI_XP = 0.1
Dungeons.BOSS_RARITY = { Epic = 75, Legendary = 25 }
Dungeons.MINI_MIN_RARITY = "Rare"
Dungeons.UNIQUE_CHANCE = 0.12 -- a dungeon relic (lifesteal / regen gear)
Dungeons.EGG_CHANCE = 0.05 -- the dungeon's own egg...
Dungeons.EGG_PITY = 0.01 -- ...plus this much per clear without one (reset when it drops)
Dungeons.CHEST_GEAR_CHANCE = 0.3 -- the bonus chest's chance of Rare+ gear

-- Interiors are built far off the map (the Boss Arena is at +3000): each dungeon in its own row,
-- one copy ("slot") per group playing it at the same time.
Dungeons.ORIGIN = V(-3200, 0, -1600)
Dungeons.ROW_SPACING = 1600
Dungeons.SLOT_SPACING = 1400

Dungeons.Order = { "Barrow", "Forge" }

Dungeons.List = {
	Barrow = {
		id = "Barrow", name = "The Draugr Barrow", icon = "💀", minLevel = 15, level = 16, ilvl = 17,
		color = rgb(120, 255, 190),
		story = "Viking jarls lie restless in this flooded burial mound. Wade through the crypts and put the Hollow King back in his grave.",
		entrance = V(-140, 0, 720), entranceFacing = V(0, 0, -1), giver = "Ylva",
		theme = { shell = "Rock", floor = "Slate", accent = rgb(120, 255, 190), light = rgb(130, 255, 200), ambient = rgb(40, 58, 54) },
		spawn = V(0, 0, 8), exit = V(0, 0, -4),
		spaces = {
			{ id = "Gate", kind = "box", at = V(0, 0, 20), size = V2(72, 56), height = 36 },
			{ id = "Descent", kind = "path", points = { V(0, 0, 40), V(0, -6, 92), V(-44, -12, 132), V(-44, -14, 184) }, width = 30, height = 32 },
			{ id = "Gallery", kind = "box", at = V(-44, -14, 240), size = V2(64, 120), height = 40 },
			{ id = "AlcoveW1", kind = "box", at = V(-84, -14, 206), size = V2(16, 20), height = 22 },
			{ id = "AlcoveW2", kind = "box", at = V(-84, -14, 240), size = V2(16, 20), height = 22 },
			{ id = "AlcoveW3", kind = "box", at = V(-84, -14, 274), size = V2(16, 20), height = 22 },
			{ id = "AlcoveE1", kind = "box", at = V(-4, -14, 206), size = V2(16, 20), height = 22 },
			{ id = "AlcoveE2", kind = "box", at = V(-4, -14, 240), size = V2(16, 20), height = 22 },
			{ id = "AlcoveE3", kind = "box", at = V(-4, -14, 274), size = V2(16, 20), height = 22 },
			{ id = "Winding", kind = "path", points = { V(-44, -14, 296), V(-44, -14, 322), V(4, -20, 352), V(58, -24, 368) }, width = 26, height = 30 },
			{ id = "Crypt", kind = "box", at = V(110, -24, 370), size = V2(116, 100), height = 42 },
			{ id = "TreasuryWay", kind = "path", points = { V(110, -24, 414), V(110, -24, 458) }, width = 22, height = 26 },
			{ id = "Treasury", kind = "round", at = V(110, -24, 478), radius = 24, height = 26 },
			{ id = "Deep", kind = "path", points = { V(162, -24, 370), V(200, -30, 372), V(232, -36, 410), V(232, -40, 494) }, width = 28, height = 32 },
			{ id = "Mound", kind = "round", at = V(232, -40, 548), radius = 62, height = 30, dome = true },
		},
		features = {
			{ kind = "pillars", points = { V(-64, -14, 200), V(-24, -14, 200), V(-64, -14, 224), V(-24, -14, 224), V(-64, -14, 256), V(-24, -14, 256), V(-64, -14, 280), V(-24, -14, 280) }, radius = 3.5, height = 40 },
			{ kind = "pool", min = V(72, -24, 336), max = V(148, -24, 404), depth = 3, water = 2.2 },
			{ kind = "walkway", from = V(72, -24, 370), to = V(148, -24, 370), width = 12 },
			{ kind = "walkway", from = V(110, -24, 336), to = V(110, -24, 404), width = 12 },
		},
		decor = {
			{ kind = "brazier", at = V(-28, 0, 40) }, { kind = "brazier", at = V(28, 0, 40) },
			{ kind = "shields", at = V(-35, 0, 20), face = V(1, 0, 0) }, { kind = "shields", at = V(35, 0, 20), face = V(-1, 0, 0) },
			{ kind = "brazier", at = V(-68, -14, 186) }, { kind = "brazier", at = V(-20, -14, 186) },
			{ kind = "brazier", at = V(-68, -14, 294) }, { kind = "brazier", at = V(-20, -14, 294) },
			{ kind = "sarcophagus", at = V(-86, -14, 206), face = V(1, 0, 0) }, { kind = "sarcophagus", at = V(-86, -14, 240), face = V(1, 0, 0) },
			{ kind = "sarcophagus", at = V(-86, -14, 274), face = V(1, 0, 0) }, { kind = "sarcophagus", at = V(-2, -14, 206), face = V(-1, 0, 0) },
			{ kind = "sarcophagus", at = V(-2, -14, 240), face = V(-1, 0, 0) }, { kind = "sarcophagus", at = V(-2, -14, 274), face = V(-1, 0, 0) },
			{ kind = "bones", at = V(-44, -14, 240), spread = 26, count = 10 },
			{ kind = "brazier", at = V(60, -24, 328) }, { kind = "brazier", at = V(160, -24, 328) },
			{ kind = "brazier", at = V(60, -24, 412) }, { kind = "brazier", at = V(160, -24, 412) },
			{ kind = "bones", at = V(110, -24, 370), spread = 40, count = 8 },
			{ kind = "brazier", at = V(97, -24, 492) }, { kind = "brazier", at = V(123, -24, 492) },
			{ kind = "stones", center = V(232, -40, 548), radius = 52, count = 12, skip = V(0, 0, -1) },
			{ kind = "throne", at = V(232, -40, 598), face = V(0, 0, -1) },
			{ kind = "runes", center = V(232, -40, 560), radius = 22 },
			{ kind = "bones", at = V(232, -40, 560), spread = 36, count = 12 },
		},
		packs = {
			{ at = V(0, -5, 78), mobs = { "DraugrRaider", "DraugrRaider" } },
			{ at = V(-44, -14, 206), mobs = { "DraugrRaider", "DraugrThrower", "BarrowHound" } },
			{ at = V(-44, -14, 268), mobs = { "BarrowHound", "BarrowHound", "DraugrThrower" } },
			{ at = V(62, -24, 350), mobs = { "DraugrRaider", "DraugrRaider", "DraugrThrower" } },
			{ at = V(110, -24, 472), mobs = { "BarrowHound", "BarrowHound", "BarrowHound" } },
			{ at = V(232, -38, 440), mobs = { "DraugrRaider", "DraugrThrower", "DraugrRaider", "BarrowHound" } },
			{ at = V(232, -40, 502), mobs = { "DraugrThrower", "DraugrThrower", "DraugrRaider" } },
		},
		chest = V(110, -24, 492),
		miniBoss = { id = "Grimvald", at = V(140, -24, 370), room = "Crypt" },
		boss = { id = "Haldor", at = V(232, -40, 562), room = "Mound" },
		hazards = {},
		loot = { relics = { "HollowKingsCrown", "GravewardensMantle", "DraugrFang" }, egg = "BarrowEgg", gold = 900, miniGold = 350 },
		title = "Barrow Breaker", -- (first clear)
		victory = "The Hollow King rests again.",
	},

	Forge = {
		id = "Forge", name = "The Rune Forge", icon = "🔥", minLevel = 30, level = 31, ilvl = 33,
		color = rgb(255, 140, 60),
		story = "The vikings forge dragonslayer blades in the fire of a chained elder dragon. Break in, beat the Runemaster and set the dragon free.",
		entrance = V(150, 0, 735), entranceFacing = V(0, 0, -1), giver = "Kael",
		theme = { shell = "Basalt", floor = "Basalt", accent = rgb(255, 130, 50), light = rgb(255, 150, 80), ambient = rgb(62, 42, 36) },
		spawn = V(0, 0, 10), exit = V(0, 0, -2),
		spaces = {
			{ id = "Gate", kind = "box", at = V(0, 0, 24), size = V2(84, 60), height = 50 },
			{ id = "Approach", kind = "path", points = { V(0, 0, 48), V(0, 0, 110) }, width = 40, height = 44 },
			{ id = "Hall", kind = "box", at = V(0, 0, 164), size = V2(124, 120), height = 66 },
			{ id = "Link", kind = "path", points = { V(0, 0, 218), V(0, 0, 252) }, width = 52, height = 52 },
			{ id = "River", kind = "box", at = V(0, 0, 290), size = V2(140, 90), height = 62, hub = false },
			{ id = "Mouth", kind = "path", points = { V(30, 0, 330), V(30, 0, 372) }, width = 34, height = 40 },
			{ id = "Shaft", kind = "round", at = V(30, -44, 440), radius = 76, height = 104, floor = "CrackedLava", hub = false },
			{ id = "Undercroft", kind = "path", points = { V(-40, -36, 440), V(-86, -36, 440), V(-86, -36, 488) }, width = 32, height = 38 },
			{ id = "Smithy", kind = "box", at = V(-86, -36, 532), size = V2(112, 100), height = 50 },
			{ id = "Descent", kind = "path", points = { V(-86, -36, 576), V(-86, -40, 618), V(-30, -44, 650), V(0, -44, 690) }, width = 36, height = 44 },
			{ id = "Heart", kind = "round", at = V(0, -44, 768), radius = 88, height = 40, dome = true },
		},
		features = {
			{ kind = "ledge", min = V(-62, 0, 124), max = V(-40, 10, 188) },
			{ kind = "ramp", from = V(-51, 10, 188), to = V(-51, 0, 214), width = 18 },
			{ kind = "ledge", min = V(40, 0, 124), max = V(62, 10, 188) },
			{ kind = "ramp", from = V(51, 10, 188), to = V(51, 0, 214), width = 18 },
			{ kind = "lava", min = V(-70, 0, 280), max = V(70, 0, 302), depth = 4 },
			{ kind = "bridge", from = V(-36, 0, 276), to = V(-36, 0, 306), width = 14 },
			{ kind = "bridge", from = V(30, 0, 276), to = V(30, 0, 306), width = 24 },
			{ kind = "spiral", center = V(30, 0, 440), inner = 34, outer = 76, from = -90, to = 180, topY = 0, bottomY = -36, baseY = -44 },
			{ kind = "ledge", min = V(-34, -44, 812), max = V(34, -32, 852) },
		},
		decor = {
			{ kind = "brazier", at = V(-32, 0, 44) }, { kind = "brazier", at = V(32, 0, 44) },
			{ kind = "rack", at = V(-40, 0, 20), face = V(1, 0, 0) }, { kind = "rack", at = V(40, 0, 20), face = V(-1, 0, 0) },
			{ kind = "forge", at = V(-20, 0, 216), face = V(0, 0, -1) }, { kind = "forge", at = V(20, 0, 216), face = V(0, 0, -1) },
			{ kind = "anvils", at = V(0, 0, 120) },
			{ kind = "brazier", at = V(-51, 10, 128) }, { kind = "brazier", at = V(51, 10, 128) },
			{ kind = "chains", from = V(-70, 40, 250), to = V(70, 40, 330) }, { kind = "chains", from = V(70, 40, 250), to = V(-70, 40, 330) },
			{ kind = "brazier", at = V(-64, 0, 252) }, { kind = "brazier", at = V(64, 0, 252) },
			{ kind = "brazier", at = V(-64, 0, 328) }, { kind = "brazier", at = V(64, 0, 328) },
			{ kind = "chains", from = V(-46, 50, 440), to = V(106, 50, 440) },
			{ kind = "forge", at = V(-138, -36, 510), face = V(1, 0, 0) }, { kind = "forge", at = V(-138, -36, 554), face = V(1, 0, 0) },
			{ kind = "anvils", at = V(-110, -36, 512) }, { kind = "anvils", at = V(-62, -36, 516) },
			{ kind = "anvils", at = V(-110, -36, 560) }, { kind = "anvils", at = V(-62, -36, 562) },
			{ kind = "rack", at = V(-34, -36, 540), face = V(-1, 0, 0) },
			{ kind = "runes", center = V(0, -44, 760), radius = 30 },
			{ kind = "brazier", at = V(-60, -44, 712) }, { kind = "brazier", at = V(60, -44, 712) },
			{ kind = "brazier", at = V(-78, -44, 790) }, { kind = "brazier", at = V(78, -44, 790) },
		},
		packs = {
			{ at = V(0, 0, 140), mobs = { "ForgeGuard", "ForgeGuard", "EmberBerserker" } },
			{ spots = { { "RuneSmith", V(-51, 10, 150) }, { "RuneSmith", V(51, 10, 160) }, { "ForgeGuard", V(0, 0, 192) } } },
			{ at = V(0, 0, 320), mobs = { "ForgeGuard", "EmberBerserker", "LavaHound" } },
			{ at = V(69, -18, 479), mobs = { "LavaHound", "LavaHound", "RuneSmith" } },
			{ at = V(-22, -33, 459), mobs = { "ForgeGuard", "EmberBerserker" } },
			{ at = V(-86, -36, 500), mobs = { "EmberBerserker", "EmberBerserker", "RuneSmith" } },
			{ at = V(-58, -42, 634), mobs = { "ForgeGuard", "ForgeGuard", "LavaHound" } },
		},
		routes = {
			{ V(0, 0, 250), V(30, 0, 268), V(30, 0, 312), V(30, 0, 334) }, -- over the wide bridge
			{ V(0, 0, 250), V(-36, 0, 270), V(-36, 0, 312), V(0, 0, 322) }, -- over the narrow one
			{ V(-51, 10, 150), V(-51, 10, 186), V(-51, 0, 214), V(0, 0, 196) }, -- off the west ledge
			{ V(51, 10, 160), V(51, 10, 186), V(51, 0, 214), V(0, 0, 196) }, -- off the east ledge
		},
		miniBoss = { id = "Brakki", at = V(-86, -36, 548), room = "Smithy" },
		boss = { id = "Sigrun", at = V(0, -44, 760), room = "Heart" },
		-- the elder dragon chained on the ledge at the back of the Heart (its fire lanes come
		-- from `breath`, a point on the floor in front of it)
		chained = { at = V(0, -32, 836), face = V(0, 0, -1), breath = V(0, -44, 806) },
		hazards = {
			{ min = V(-70, -6, 280), max = V(70, -1.5, 302) },
			{ center = V(30, -44, 440), radius = 76, top = -40 },
		},
		loot = { relics = { "ChainbreakerTalons", "HeartOfTheForge", "RuneforgedTailguard" }, egg = "ForgeEgg", gold = 2400, miniGold = 900 },
		title = "Chainbreaker",
		victory = "The elder dragon is free!",
	},
}

-- Bosses and mini-bosses. `health` and `hit` are for a group of 4 (GROUP_HEALTH / GROUP_DAMAGE
-- shrink them for smaller groups); `hit` is a basic hit before each move's `mult`.
-- Moves (BossKit): Cleave, GroundSlam, RuneStrikes, AxeVolley, Leap, Charge, Whirlwind, Harpoon, Lane.
-- Traits: summons = { { at, add, count } }  enrage = { at }  secondLife = { health, delay, name,
--         speedMult, moves }  phases = { { at, moves, shield = { add, count } } }
local GRAVE = rgb(120, 255, 190)
local DRAUGR_SKIN = rgb(150, 178, 168)
Dungeons.Bosses = {
	Grimvald = {
		id = "Grimvald", name = "Grimvald the Bone-Warden", mini = true, scale = 2.0, speed = 13, health = 30000, hit = 70,
		color = GRAVE,
		look = { shirt = rgb(70, 90, 85), pants = rgb(40, 45, 45), beard = rgb(200, 210, 200), skin = DRAUGR_SKIN, eyes = GRAVE,
			weapon = "hammer", shield = true, bigShield = true, cape = rgb(40, 60, 55) },
		moves = {
			Cleave = { cooldown = 2.4, mult = 1.0, range = 12 },
			GroundSlam = { cooldown = 9, mult = 1.8, radius = 16, delay = 1.3 },
			Charge = { cooldown = 10, mult = 1.6, length = 60, width = 12, delay = 1.2 },
		},
		summons = { { at = 0.5, add = "BarrowHound", count = 2 } },
	},
	Haldor = {
		id = "Haldor", name = "Haldor the Hollow King", scale = 3.0, speed = 12, health = 80000, hit = 90,
		color = GRAVE,
		look = { shirt = rgb(50, 70, 65), pants = rgb(35, 40, 40), beard = rgb(220, 230, 220), skin = DRAUGR_SKIN, eyes = GRAVE,
			weapon = "greatAxe", shield = false, cape = rgb(30, 50, 45), crown = true, glow = GRAVE },
		moves = {
			Cleave = { cooldown = 2.4, mult = 1.0, range = 16 },
			GroundSlam = { cooldown = 11, mult = 2.2, radius = 22, delay = 1.6 },
		},
		summons = { { at = 0.5, add = "DraugrRaider", count = 3 } },
		secondLife = {
			health = 0.4, delay = 6, name = "Haldor Unbound", speedMult = 1.3,
			moves = {
				Cleave = { cooldown = 2.2, mult = 1.0, range = 16 },
				RuneStrikes = { cooldown = 7, mult = 1.5, radius = 10, delay = 1.7, count = 5, style = "poison" },
				Leap = { cooldown = 10, mult = 2.0, radius = 16, delay = 1.4, pick = "far" },
			},
		},
	},
	Brakki = {
		id = "Brakki", name = "Brakki Anvil-Jarl", mini = true, scale = 2.2, speed = 15, health = 60000, hit = 150,
		color = rgb(255, 140, 60),
		look = { shirt = rgb(100, 50, 30), pants = rgb(50, 35, 30), beard = rgb(40, 30, 25), weapon = "hammer", shield = false,
			cape = rgb(90, 40, 20), warpaint = true, glow = rgb(255, 140, 60) },
		moves = {
			Cleave = { cooldown = 2.2, mult = 1.0, range = 13 },
			Leap = { cooldown = 9, mult = 1.8, radius = 16, delay = 1.3, pick = "far" },
			AxeVolley = { cooldown = 6, mult = 0.8, count = 4, style = "hammer" },
		},
		enrage = { at = 0.3 },
	},
	Sigrun = {
		id = "Sigrun", name = "Runemaster Sigrun", scale = 3.0, speed = 12, health = 240000, hit = 170,
		color = rgb(255, 150, 60),
		look = { shirt = rgb(120, 50, 30), pants = rgb(50, 30, 25), hair = rgb(255, 170, 90), weapon = "staff", shield = false,
			cape = rgb(160, 60, 20), crown = true, glow = rgb(255, 150, 60) },
		moves = {
			Cleave = { cooldown = 2.6, mult = 1.0, range = 15 },
			RuneStrikes = { cooldown = 7, mult = 1.5, radius = 10, delay = 1.7, count = 5, style = "meteor" },
			Harpoon = { cooldown = 11, mult = 0.8, minHeight = 14 },
			Lane = { cooldown = 18, mult = 2.2, width = 16, delay = 2.0 },
		},
		phases = {
			{ at = 0.6, shield = { add = "ForgeGuard", count = 3 },
				moves = {
					Cleave = { cooldown = 2.6, mult = 1.0, range = 15 },
					RuneStrikes = { cooldown = 6, mult = 1.5, radius = 10, delay = 1.7, count = 6, style = "meteor" },
					Lane = { cooldown = 14, mult = 2.2, width = 16, delay = 2.0 },
				} },
			{ at = 0.3,
				moves = {
					Cleave = { cooldown = 2.4, mult = 1.1, range = 15 },
					Whirlwind = { cooldown = 12, mult = 0.6, radius = 15, duration = 4, tick = 0.5 },
					Lane = { cooldown = 10, mult = 2.2, width = 16, delay = 1.8 },
					Harpoon = { cooldown = 11, mult = 0.8, minHeight = 14 },
				} },
		},
	},
}

function Dungeons.get(id: string)
	return Dungeons.List[id]
end

function Dungeons.origin(id: string, slot: number): Vector3
	local row = table.find(Dungeons.Order, id) or 1
	return Dungeons.ORIGIN + V(-(slot - 1) * Dungeons.SLOT_SPACING, 0, (row - 1) * Dungeons.ROW_SPACING)
end

function Dungeons.groupHealth(n: number): number
	return Dungeons.GROUP_HEALTH[math.clamp(n, 1, #Dungeons.GROUP_HEALTH)]
end

function Dungeons.groupDamage(n: number): number
	return Dungeons.GROUP_DAMAGE[math.clamp(n, 1, #Dungeons.GROUP_DAMAGE)]
end

-- The mobs of a pack as { typeId, local position } (packs list either one spot or a spot each).
function Dungeons.packMobs(pack)
	local list = {}
	if pack.spots then
		for _, s in ipairs(pack.spots) do
			table.insert(list, { s[1], s[2] })
		end
	else
		local n = #pack.mobs
		for i, typeId in ipairs(pack.mobs) do
			local a = (i / n) * math.pi * 2
			local r = n > 1 and 6 or 0
			table.insert(list, { typeId, pack.at + V(math.cos(a) * r, 0, math.sin(a) * r) })
		end
	end
	return list
end

-- The dungeons a dragon of this level can enter, and the one it unlocks next.
function Dungeons.unlocked(level: number): { string }
	local list = {}
	for _, id in ipairs(Dungeons.Order) do
		if level >= Dungeons.List[id].minLevel then
			table.insert(list, id)
		end
	end
	return list
end

return Dungeons
