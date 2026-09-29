-- Target practice range in town (server/Services/RangeService, UI/Range). Stand on a lane's
-- firing mat and pick a level: your own targets pop up and move around the field, and you knock
-- them down with Fireball. While you practice, left click fires Fireball too, its cooldown drops
-- to FIREBALL_COOLDOWN, and every other ability rests.
--
-- Knock down `needed` targets within `time` to clear a level. The first clear of a level pays
-- `xp` (a share of the XP you need for your next level); replays pay REPLAY_XP of that.
-- AFK mode fires by itself at slow targets and trickles in AFK.xpPerMinute instead.
--
-- Target patterns (shared/RangeUtil): still, slide (side to side), bob (slide + up and down),
-- zigzag (side to side and back and forth), sprint (dashes across the lane), float (loops in the
-- air), popup (stands still, but vanishes after `life` seconds).

local Range = {}

Range.FIREBALL_COOLDOWN = 0.6
Range.SPLASH = 3 -- a practice blast knocks down targets this close (studs past the target's edge)
Range.REPLAY_XP = 0.12
Range.GOLD_CHANCE = 0.12 -- gold targets count double
Range.RESPAWN = 0.5 -- a knocked-down target's replacement pops up after this long
Range.LEAVE_DISTANCE = 24 -- walk (or fly) this far from your mat and the session ends
Range.MAT_RANGE = 16 -- how close to a mat you need to be to start

Range.Levels = {
	{ name = "Warm-up", time = 40, needed = 8, count = 2, patterns = { "still" }, speed = 0, size = 7, xp = 0.12 },
	{ name = "Sliders", time = 40, needed = 10, count = 2, patterns = { "slide" }, speed = 5, size = 6.5, xp = 0.15 },
	{ name = "Quick Sliders", time = 40, needed = 12, count = 3, patterns = { "slide" }, speed = 8, size = 6, xp = 0.18 },
	{ name = "Bobbers", time = 40, needed = 12, count = 3, patterns = { "slide", "bob" }, speed = 8, size = 5.5, xp = 0.2 },
	{ name = "Zigzag", time = 45, needed = 14, count = 3, patterns = { "zigzag", "bob" }, speed = 10, size = 5, xp = 0.24 },
	{ name = "Pop-ups", time = 40, needed = 14, count = 3, patterns = { "popup" }, speed = 0, size = 5, life = 2.5, xp = 0.28 },
	{ name = "Sprinters", time = 45, needed = 15, count = 3, patterns = { "sprint", "zigzag" }, speed = 14, size = 4.5, xp = 0.32 },
	{ name = "High Flyers", time = 45, needed = 15, count = 3, patterns = { "float", "bob" }, speed = 12, size = 4.5, high = true, xp = 0.36 },
	{ name = "Chaos", time = 50, needed = 18, count = 4, patterns = { "sprint", "zigzag", "float", "popup" }, speed = 15, size = 4, life = 2.2, xp = 0.42 },
	{ name = "Dead Eye", time = 50, needed = 20, count = 4, patterns = { "sprint", "zigzag", "float", "popup" }, speed = 18, size = 3.5, life = 1.8, xp = 0.5 },
}

-- AFK practice: fire by yourself every `fireEvery` seconds at slow targets; XP trickles in every
-- `tick` seconds (xpPerMinute is a share of the XP for your next level, so about 40 minutes a
-- level at any level). Roblox still logs out players who don't touch anything for 20 minutes.
Range.AFK = { count = 2, patterns = { "slide" }, speed = 4, size = 6.5, fireEvery = 2.5, xpPerMinute = 0.025, tick = 15 }

return Range
