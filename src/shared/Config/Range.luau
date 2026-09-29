-- Target practice range in town (server/Services/RangeService, UI/Range). Stand on a lane's
-- firing mat and pick a level: your own targets pop up and move around the field, and you knock
-- them down with Fireball. While you practice, left click fires Fireball too, its cooldown drops
-- to FIREBALL_COOLDOWN, and every other ability rests.
--
-- Knock down `needed` targets within `time` to clear a level. The first clear of a level pays
-- `xp` (a share of the XP you need for your next level); replays pay REPLAY_XP of that.
-- AFK mode fires by itself at slow targets and pays a little XP for every one it knocks down.
-- Starting a session swings the camera round behind you, looking down the lane, CAMERA_ZOOM back.
--
-- Target patterns (shared/RangeUtil): still, slide (side to side), bob (slide + up and down),
-- zigzag (side to side and back and forth), sprint (dashes across the lane at `speed`, resting a
-- moment at each side), float (loops in the
-- air), popup (stands still, but vanishes after `life` seconds).

local Range = {}

Range.FIREBALL_COOLDOWN = 0.6
Range.SPLASH = 1.2 -- a practice blast knocks down targets this close (studs past the target's edge)
Range.PROJECTILE_RADIUS = 0.8 -- a practice fireball's own size when checking what it flew into
Range.CAMERA_ZOOM = 24
Range.REPLAY_XP = 0.12
Range.GOLD_CHANCE = 0.12 -- gold targets count double
Range.RESPAWN = 0.5 -- a knocked-down target's replacement pops up after this long
Range.LEAVE_DISTANCE = 24 -- walk (or fly) this far from your mat and the session ends
Range.MAT_RANGE = 16 -- how close to a mat you need to be to start

Range.Levels = {
	{ name = "Warm-up", time = 40, needed = 8, count = 2, patterns = { "still" }, speed = 0, size = 5, xp = 0.12 },
	{ name = "Sliders", time = 40, needed = 10, count = 2, patterns = { "slide" }, speed = 7, size = 4.6, xp = 0.15 },
	{ name = "Quick Sliders", time = 40, needed = 12, count = 3, patterns = { "slide" }, speed = 11, size = 4.2, xp = 0.18 },
	{ name = "Bobbers", time = 40, needed = 12, count = 3, patterns = { "slide", "bob" }, speed = 11, size = 4, xp = 0.2 },
	{ name = "Zigzag", time = 45, needed = 14, count = 3, patterns = { "zigzag", "bob" }, speed = 13, size = 3.7, xp = 0.24 },
	{ name = "Pop-ups", time = 40, needed = 14, count = 3, patterns = { "popup" }, speed = 0, size = 3.5, life = 2, xp = 0.28 },
	{ name = "Sprinters", time = 45, needed = 14, count = 3, patterns = { "sprint", "slide" }, speed = 13, size = 3.5, xp = 0.32 },
	{ name = "High Flyers", time = 45, needed = 15, count = 3, patterns = { "float", "bob" }, speed = 16, size = 3.2, high = true, xp = 0.36 },
	{ name = "Chaos", time = 50, needed = 18, count = 4, patterns = { "sprint", "zigzag", "float", "popup" }, speed = 17, size = 3.1, life = 1.7, xp = 0.42 },
	{ name = "Dead Eye", time = 50, needed = 20, count = 4, patterns = { "sprint", "zigzag", "float", "popup" }, speed = 21, size = 2.7, life = 1.4, xp = 0.5 },
}

-- AFK practice: fires by itself every `fireEvery` seconds at slow targets, and every target it
-- knocks down pays xpPerMinute * fireEvery / 60 (a share of the XP for your next level), so about
-- 40 minutes a level at any level if nearly every shot lands. Your own shots count too, but no
-- faster than one paid hit per fireEvery. Roblox still logs out anyone idle for 20 minutes.
Range.AFK = { count = 2, patterns = { "slide" }, speed = 4, size = 5, fireEvery = 2.5, xpPerMinute = 0.025 }
function Range.afkXpPerHit(xpForNextLevel: number): number
	return math.max(1, math.floor(xpForNextLevel * Range.AFK.xpPerMinute * Range.AFK.fireEvery / 60 + 0.5))
end

return Range
