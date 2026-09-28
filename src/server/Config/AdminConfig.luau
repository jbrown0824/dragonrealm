-- Server-only settings for codes and admin mode. This file lives in ServerScriptService, so
-- players can never read it.
--
-- CHANGE CODE before you publish the game: anyone who knows it can open the admin panel.
-- To lock admin mode to specific accounts, put their user ids in ALLOWED_USER_IDS (then the
-- code only works for them). In Studio test sessions, players have negative user ids (-1, -2...).

return {
	CODE = "DRAGONLORD",
	ALLOWED_USER_IDS = {},

	-- Promo codes anyone can redeem once from the 🎁 Codes button.
	--   gold, xp, seeds = { SeedId = n }, eggs = { EggId = n }, food = { FoodId = n }
	PROMO_CODES = {
		DRAGONREALM = { gold = 250 },
		HATCHLING = { eggs = { EmberEgg = 1 } },
		GONEFISHING = { food = { SilverSalmon = 3 } },
	},
}
