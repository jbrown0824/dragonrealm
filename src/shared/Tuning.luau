-- Live balance overrides set from the admin panel (AdminService). The server owns them and
-- sends every change to all clients, so StatCalc gives the same numbers on both sides.
-- They only last until the server restarts: use "Print changes" in the admin panel to get
-- lines you can paste into the Config files.
--
--   global:    playerDamage, enemyHealth, enemyDamage, xp, gold (multipliers, 1 = normal)
--   abilities: [abilityId] = { dmg = x, cd = x } multipliers on damage and cooldown
--   talents:   [talentId] = x, multiplies every stat the talent gives

local Tuning = {}

Tuning.GLOBAL_KEYS = { "playerDamage", "enemyHealth", "enemyDamage", "xp", "gold" }
Tuning.GLOBAL_LABELS = {
	playerDamage = "Dragon damage",
	enemyHealth = "Viking & animal health",
	enemyDamage = "Viking & animal damage",
	xp = "XP earned",
	gold = "Gold earned",
}

local function fresh()
	return { global = {}, abilities = {}, talents = {} }
end

Tuning.values = fresh()

function Tuning.global(key: string): number
	return Tuning.values.global[key] or 1
end

function Tuning.ability(abilityId: string): (number, number)
	local a = Tuning.values.abilities[abilityId]
	if not a then
		return 1, 1
	end
	return a.dmg or 1, a.cd or 1
end

function Tuning.talent(talentId: string): number
	return Tuning.values.talents[talentId] or 1
end

-- Replace everything (clients call this with the server's snapshot).
function Tuning.apply(values)
	local v = fresh()
	if type(values) == "table" then
		for k, x in pairs(values.global or {}) do
			v.global[k] = x
		end
		for k, x in pairs(values.abilities or {}) do
			v.abilities[k] = { dmg = x.dmg, cd = x.cd }
		end
		for k, x in pairs(values.talents or {}) do
			v.talents[k] = x
		end
	end
	Tuning.values = v
end

function Tuning.reset()
	Tuning.values = fresh()
end

function Tuning.isDefault(): boolean
	return next(Tuning.values.global) == nil and next(Tuning.values.abilities) == nil and next(Tuning.values.talents) == nil
end

return Tuning
