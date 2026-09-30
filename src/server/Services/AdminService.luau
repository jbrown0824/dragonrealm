-- Codes and admin mode. Players type codes into the 🎁 Codes window: promo codes give a one-time
-- reward, and the admin code (Config/AdminConfig, server-only) unlocks the admin panel for the
-- rest of the session. Admins can change any dragon's level, Paragon and type, hand out items,
-- pets, treats, skins and titles, fill the pet book and achievements, switch Robux passes and
-- products on for testing, restock shops, start bosses, jump into a dungeon, and tune balance
-- live (Shared/Tuning) for everyone on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Classes = require(Shared.Config.Classes)
local Abilities = require(Shared.Config.Abilities)
local Talents = require(Shared.Config.Talents)
local Seeds = require(Shared.Config.Seeds)
local Pets = require(Shared.Config.Pets)
local Items = require(Shared.Config.Items)
local Zones = require(Shared.Config.Zones)
local Skins = require(Shared.Config.Skins)
local Collections = require(Shared.Config.Collections)
local StoreInfo = require(Shared.Config.Store)
local Dungeons = require(Shared.Config.Dungeons)
local Tuning = require(Shared.Tuning)
local TalentUtil = require(Shared.TalentUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local AdminConfig = require(script.Parent.Parent.Config.AdminConfig)

local AdminService = {}
local S

local admins = {} -- [Player] = true
local attempts = {} -- [Player] = { times }

function AdminService.isAdmin(player: Player): boolean
	return admins[player] == true
end

---------------------------------------------------------------- codes

local function rateLimited(player: Player): boolean
	local list = attempts[player] or {}
	local t = os.clock()
	local recent = {}
	for _, at in ipairs(list) do
		if t - at < 60 then
			table.insert(recent, at)
		end
	end
	table.insert(recent, t)
	attempts[player] = recent
	return #recent > 6
end

local function grantPromo(player: Player, reward)
	if reward.gold then
		S.PlayerService.addGold(player, reward.gold)
	end
	if reward.xp then
		S.PlayerService.addXP(player, reward.xp, true)
	end
	for seedId, n in pairs(reward.seeds or {}) do
		S.PlayerService.addSeeds(player, seedId, n)
	end
	for eggId, n in pairs(reward.eggs or {}) do
		S.PetService.addEgg(player, eggId, n)
	end
	for foodId, n in pairs(reward.food or {}) do
		S.SurvivalService.addFood(player, foodId, n)
	end
end

local function onRedeem(player: Player, code)
	if type(code) ~= "string" or #code > 40 then
		return false, "That's not a code."
	end
	if rateLimited(player) then
		return false, "Slow down! Try again in a minute."
	end
	code = code:upper():gsub("%s", "")
	if code == AdminConfig.CODE:upper() then
		local allowed = AdminConfig.ALLOWED_USER_IDS
		if #allowed > 0 and not table.find(allowed, player.UserId) then
			return false, "That code doesn't work for you."
		end
		admins[player] = true
		Remotes.event("AdminState"):FireClient(player, true)
		S.PlayerService.markDirty(player)
		print(string.format("[Admin] %s (%d) unlocked admin mode", player.Name, player.UserId))
		return true, "Admin mode unlocked! Open it with the 🛠️ button."
	end
	local reward = AdminConfig.PROMO_CODES[code]
	local profile = S.PlayerService.getProfile(player)
	if not reward or not profile then
		return false, "Unknown code."
	end
	if profile.codes[code] then
		return false, "You already redeemed that code."
	end
	profile.codes[code] = true
	grantPromo(player, reward)
	S.PlayerService.markDirty(player)
	return true, "Code redeemed! Enjoy your reward."
end

---------------------------------------------------------------- tuning

local function broadcastTuning()
	Remotes.event("TuningChanged"):FireAllClients(Tuning.values)
	for _, player in ipairs(Players:GetPlayers()) do
		S.PlayerService.recompute(player)
	end
end

local function fmt(n: number): string
	return tostring(Util.round(n, 2))
end

-- Human-readable list of every change, for pasting into Config files.
local function tuningReport(): string
	local lines = { "-- Dragon Realm balance changes (session only). Copy the new numbers into the Config files:" }
	for _, key in ipairs(Tuning.GLOBAL_KEYS) do
		local v = Tuning.values.global[key]
		if v and v ~= 1 then
			table.insert(lines, string.format("-- %s: x%s  (applied in code as a multiplier)", Tuning.GLOBAL_LABELS[key], fmt(v)))
		end
	end
	local CAP_CONFIG = { lifestealCap = "LIFESTEAL_CAP", regenCap = "REGEN_CAP", extraLifestealCap = "EXTRA_LIFESTEAL_CAP", extraRegenCap = "EXTRA_REGEN_CAP" }
	for _, key in ipairs(Tuning.CAP_KEYS) do
		local v = Tuning.values.global[key]
		if v and v ~= 1 then
			local name = CAP_CONFIG[key]
			table.insert(lines, string.format("Game.%s = %s  -- was %s", name, fmt(Game[name] * v), fmt(Game[name])))
		end
	end
	local scaling = Tuning.values.global.groupScaling
	if scaling and scaling ~= 1 then
		for _, list in ipairs({ "GROUP_HEALTH", "GROUP_DAMAGE" }) do
			local parts = {}
			for _, x in ipairs(Dungeons[list]) do
				table.insert(parts, fmt(math.max(0.1, 1 - (1 - x) * scaling)))
			end
			table.insert(lines, string.format("Dungeons.%s = { %s }", list, table.concat(parts, ", ")))
		end
	end
	for _, id in ipairs(Dungeons.Order) do
		local t = Tuning.values.dungeons[id]
		local def = Dungeons.get(id)
		if t then
			for _, key in ipairs(Tuning.DUNGEON_KEYS) do
				local v = t[key]
				if v and v ~= 1 then
					if key == "bossHp" or key == "bossDmg" then
						for _, which in ipairs({ def.miniBoss, def.boss }) do
							local b = Dungeons.Bosses[which.id]
							local field = key == "bossHp" and "health" or "hit"
							table.insert(lines, string.format("Dungeons.Bosses.%s.%s = %s  -- was %s", which.id, field, fmt(b[field] * v), fmt(b[field])))
						end
					else
						table.insert(lines, string.format("-- %s %s: x%s  (monster health/damage in Enemies.Dungeon, luck in Dungeons.UNIQUE_CHANCE / EGG_CHANCE)", def.name, Tuning.DUNGEON_LABELS[key], fmt(v)))
					end
				end
			end
		end
	end
	local abilityIds = {}
	for id in pairs(Tuning.values.abilities) do
		table.insert(abilityIds, id)
	end
	table.sort(abilityIds)
	for _, id in ipairs(abilityIds) do
		local a = Abilities.get(id)
		local t = Tuning.values.abilities[id]
		if id == "Breath" then
			for _, classId in ipairs(Classes.Order) do
				local b = Classes.get(classId).breath
				if (t.dmg or 1) ~= 1 then
					table.insert(lines, string.format("Classes.%s.breath.mult = %s  -- was %s", classId, fmt(b.mult * t.dmg), fmt(b.mult)))
				end
				if (t.cd or 1) ~= 1 then
					table.insert(lines, string.format("Classes.%s.breath.cooldown = %s  -- was %s", classId, fmt(b.cooldown * t.cd), fmt(b.cooldown)))
				end
			end
		elseif a then
			if (t.dmg or 1) ~= 1 and a.mult then
				table.insert(lines, string.format("Abilities.%s.mult = %s  -- was %s", id, fmt(a.mult * t.dmg), fmt(a.mult)))
			end
			if (t.cd or 1) ~= 1 and a.cooldown then
				table.insert(lines, string.format("Abilities.%s.cooldown = %s  -- was %s", id, fmt(a.cooldown * t.cd), fmt(a.cooldown)))
			end
		end
	end
	local talentIds = {}
	for id in pairs(Tuning.values.talents) do
		table.insert(talentIds, id)
	end
	table.sort(talentIds)
	for _, id in ipairs(talentIds) do
		local talent = Talents.byId[id]
		local scale = Tuning.values.talents[id]
		if talent and scale ~= 1 then
			local parts = {}
			for stat, v in pairs(talent.effects) do
				table.insert(parts, string.format("%s = %s (was %s)", stat, fmt(v * scale), fmt(v)))
			end
			table.insert(lines, string.format("Talents %s: %s", id, #parts > 0 and table.concat(parts, ", ") or ("x" .. fmt(scale) .. " (no stat effects)")))
		end
	end
	if #lines == 1 then
		table.insert(lines, "-- (nothing changed)")
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------- actions

local function placeCFrame(place: string): CFrame?
	if place == "Town" then
		return CFrame.new(Zones.SPAWN + Vector3.new(0, 4, 0))
	elseif place == "Training" then
		return CFrame.new(Zones.Training.dummies[2] + Vector3.new(0, 8, -20))
	end
	local camp = Zones.getCamp(place)
	if camp then
		return CFrame.new(camp.center + Vector3.new(0, 60, -camp.radius - 30))
	end
	for _, area in ipairs(Zones.HuntingGrounds) do
		if area.id == place then
			return CFrame.new((area.min + area.max) / 2 + Vector3.new(0, 40, 0))
		end
	end
	return nil
end

local function targetOf(admin: Player, args): Player
	local id = type(args) == "table" and tonumber(args.userId)
	return (id and Players:GetPlayerByUserId(id)) or admin
end

local ACTIONS = {}

ACTIONS.setLevel = function(_, target, args)
	S.PlayerService.setLevel(target, tonumber(args.level) or 1)
	return true, string.format("%s is now level %d.", target.DisplayName, S.PlayerService.getProfile(target).level)
end
ACTIONS.setClass = function(_, target, args)
	if not Classes.get(args.classId) then
		return false, "Unknown dragon type."
	end
	S.PlayerService.setClass(target, args.classId)
	return true, target.DisplayName .. " is now a " .. args.classId .. "."
end
ACTIONS.gold = function(_, target, args)
	S.PlayerService.addGold(target, math.clamp(tonumber(args.amount) or 0, 0, 10000000))
	return true, "Gold added."
end
ACTIONS.resetTalents = function(_, target)
	S.PlayerService.getProfile(target).talents = {}
	S.PlayerService.recompute(target)
	return true, "Skill points refunded."
end
ACTIONS.potions = function(_, target, args)
	S.PotionService.setAll(target, tonumber(args.rank) or 0)
	return true, "Potions set."
end
ACTIONS.item = function(_, target, args)
	if not Items.Rarities[args.rarity] then
		return false, "Unknown rarity."
	end
	local profile = S.PlayerService.getProfile(target)
	S.PlayerService.addItem(target, S.LootService.rollGear(profile.level, 0, nil, args.rarity))
	return true, "Item given."
end
ACTIONS.egg = function(_, target, args)
	if not Pets.Eggs[args.eggId] then
		return false, "Unknown egg."
	end
	S.PetService.addEgg(target, args.eggId, 1)
	return true, "Egg given."
end
ACTIONS.seeds = function(_, target)
	for _, id in ipairs(Seeds.Order) do
		S.PlayerService.addSeeds(target, id, 3, true)
	end
	return true, "3 of every seed given."
end
ACTIONS.food = function(_, target)
	for _, id in ipairs({ "SilverSalmon", "BoarHaunch", "BearRoast" }) do
		S.SurvivalService.addFood(target, id, 2)
	end
	return true, "Food given."
end
ACTIONS.hunger = function(_, target, args)
	S.SurvivalService.setHunger(target, tonumber(args.value) or Game.HUNGER_MAX)
	return true, "Hunger set."
end
ACTIONS.heal = function(_, target)
	local _, humanoid = S.PlayerService.getCharacter(target)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	return true, "Healed."
end
ACTIONS.god = function(_, target, args)
	target:SetAttribute("GodMode", args.on == true or nil)
	return true, args.on and "God mode ON." or "God mode off."
end
ACTIONS.noCooldowns = function(_, target, args)
	target:SetAttribute("NoCooldowns", args.on == true or nil)
	return true, args.on and "No cooldowns ON." or "Cooldowns back to normal."
end
ACTIONS.teleport = function(_, target, args)
	local cf = type(args.place) == "string" and placeCFrame(args.place)
	if not cf then
		return false, "Unknown place."
	end
	if S.BossService.isInFight(target) then
		return false, "Can't teleport out of a boss fight."
	end
	S.PlayerService.teleport(target, cf)
	return true, "Teleported."
end
ACTIONS.unlockPlots = function(_, target)
	local profile = S.PlayerService.getProfile(target)
	profile.plotsUnlocked = Game.MAX_PLOTS
	S.FarmService.refreshPlayer(target)
	return true, "All plots unlocked."
end
ACTIONS.robots = function(_, target)
	local profile = S.PlayerService.getProfile(target)
	profile.robots.water = true
	profile.robots.harvest = #Game.ROBOTS.Harvest.levels
	S.FarmService.refreshPlayer(target)
	return true, "Robots given."
end
ACTIONS.tutorial = function(_, target)
	S.PlayerService.getProfile(target).tutorial = 0
	S.PlayerService.markDirty(target)
	return true, "Tutorial will restart."
end
---------------------------------------------------------------- paragon, pets, collection, store

ACTIONS.setParagon = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	local value = math.clamp(math.floor(tonumber(args.value) or 0), 0, 5000)
	if value > 0 and profile.level < Game.LEVEL_CAP then
		S.PlayerService.setLevel(target, Game.LEVEL_CAP)
	end
	profile.paragon = value
	profile.xp = 0
	if TalentUtil.available(profile.level, profile.talents, profile.paragon) < 0 then
		profile.talents = {} -- fewer points than already spent: refund them
	end
	S.PlayerService.recompute(target)
	return true, string.format("%s is now Paragon %d (%d skill points to spend).", target.DisplayName, value, TalentUtil.available(profile.level, profile.talents, profile.paragon))
end
ACTIONS.addParagon = function(admin, target, args)
	local profile = S.PlayerService.getProfile(target)
	return ACTIONS.setParagon(admin, target, { value = (profile.paragon or 0) + (tonumber(args.amount) or 1) })
end
ACTIONS.treats = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	profile.treats = math.max(0, (profile.treats or 0) + math.clamp(math.floor(tonumber(args.amount) or 0), -100000, 100000))
	return true, string.format("%s has %d treats.", target.DisplayName, profile.treats)
end
ACTIONS.pet = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	if not Pets.get(args.species) then
		return false, "Unknown pet."
	end
	if #profile.pets >= Game.PET_LIMIT then
		return false, "Their nest is full (" .. Game.PET_LIMIT .. ")."
	end
	S.PetService.givePet(target, args.species, args.golden == true, tonumber(args.level))
	return true, string.format("Gave %s%s (level %d).", args.golden and "a Golden " or "a ", Pets.get(args.species).name, tonumber(args.level) or 1)
end
ACTIONS.clearPets = function(_, target)
	local profile = S.PlayerService.getProfile(target)
	profile.pets = {}
	profile.petsEquipped = {}
	S.PlayerService.recompute(target)
	S.PetService.applyToCharacter(target)
	return true, "All pets released (no gold)."
end
ACTIONS.petBook = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	if args.mode == "clear" then
		profile.petBook = {}
		profile.milestones = {}
		profile.bookSynced = true
		return true, "Pet book and its milestones cleared (rewards won't come back until you collect again)."
	end
	for id in pairs(Pets.Species) do
		profile.petBook[id] = math.max(profile.petBook[id] or 0, args.mode == "golden" and 2 or 1)
	end
	S.AchievementService.check(target)
	return true, args.mode == "golden" and "Every species found and made golden." or "Every species found."
end
ACTIONS.skins = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	if args.mode == "unlockAll" then
		for id in pairs(Skins.List) do
			profile.skins[id] = true
		end
		return true, "Every skin unlocked."
	elseif args.mode == "lockAll" then
		profile.skins = {}
		S.AchievementService.wearSkin(target, "Classic")
		return true, "Skins locked again (back to Classic)."
	elseif args.mode == "wear" and Skins.get(args.skin) then
		profile.skins[args.skin] = true
		S.AchievementService.wearSkin(target, args.skin)
		return true, "Wearing " .. Skins.get(args.skin).name .. "."
	end
	return false, "Unknown skin."
end
ACTIONS.titles = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	if args.mode == "unlockAll" then
		for _, title in ipairs(Collections.allTitles()) do
			profile.titles[title] = true
		end
		return true, "Every title unlocked."
	elseif args.mode == "clear" then
		profile.titles = {}
		profile.title = ""
		S.PlayerService.recompute(target)
		return true, "Titles cleared."
	elseif args.mode == "set" and type(args.title) == "string" then
		if args.title ~= "" then
			profile.titles[args.title] = true
		end
		profile.title = args.title
		S.PlayerService.recompute(target) -- refreshes the nametag
		return true, args.title == "" and "Title removed." or ("Title set: " .. args.title)
	end
	return false, "Unknown title action."
end
ACTIONS.achievements = function(_, target, args)
	local profile = S.PlayerService.getProfile(target)
	if args.mode == "reset" then
		profile.achievements = {}
		return true, "Achievements reset (they'll be earned again from current stats in a few seconds)."
	end
	-- "reach": raise every counted stat to its top tier (level and Paragon have their own buttons)
	for _, a in ipairs(Collections.Achievements) do
		if a.stat ~= "level" and a.stat ~= "paragon" then
			profile[a.stat] = math.max(tonumber(profile[a.stat]) or 0, a.tiers[#a.tiers].count)
		end
	end
	S.AchievementService.check(target)
	return true, "Every achievement stat maxed (rewards granted)."
end
ACTIONS.pass = function(_, target, args)
	if not StoreInfo.Passes[args.pass] then
		return false, "Unknown pass."
	end
	local profile = S.PlayerService.getProfile(target)
	profile.passes[args.pass] = args.on == true or nil
	S.PlayerService.recompute(target) -- 2x Flight Time changes stats
	return true, string.format("%s %s for %s (test).", StoreInfo.Passes[args.pass].name, args.on and "ON" or "off", target.DisplayName)
end
ACTIONS.product = function(_, target, args)
	if not StoreInfo.Products[args.product] then
		return false, "Unknown product."
	end
	return true, "Given (test): " .. S.StoreService.grantProduct(target, args.product)
end
ACTIONS.starterReset = function(_, target)
	S.PlayerService.getProfile(target).starterPack = false
	return true, "Starter Pack can be bought (and is advertised) again."
end
ACTIONS.restockMine = function(_, target)
	S.StockService.restockNow(target)
	return true, target.DisplayName .. "'s shops restocked."
end

ACTIONS.bossNow = function(_, _, args)
	return S.BossService.adminStart(math.clamp(tonumber(args.seconds) or 30, 5, 600))
end
ACTIONS.respawnCamps = function()
	S.EnemyService.respawnCamps()
	return true, "Vikings respawned."
end
ACTIONS.resetChests = function()
	S.CampService.resetChests()
	return true, "Chests refilled."
end
ACTIONS.restockShops = function()
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		S.StockService.restockNow(player)
	end
	return true, "Every shop restocked."
end
ACTIONS.setHour = function(_, _, args)
	local hour = tonumber(args.hour)
	if not hour then
		return false, "Pick an hour."
	end
	S.DayNightService.setHour(hour)
	return true, string.format("The clock is now %02d:00.", math.floor(hour) % 24)
end
ACTIONS.raidNow = function()
	return S.RaidService.begin()
end
ACTIONS.raidEnd = function(_, _, args)
	return S.RaidService.stop(args.won == true)
end
ACTIONS.burnHouse = function()
	for index = 1, #Zones.Houses do
		if S.RaidService.houseState(index) == "ok" then
			S.RaidService.ignite(index)
			return true, "House " .. index .. " is on fire."
		end
	end
	return false, "Every house is already burning or burned."
end
ACTIONS.rebuildHouses = function()
	S.RaidService.rebuildAll()
	return true, "Every house rebuilt."
end
ACTIONS.shops = function(_, _, args)
	if args.open then
		S.ShopService.reopen()
		return true, "Shops reopened."
	end
	S.ShopService.close(tonumber(args.seconds) or 60)
	return true, "Shops closed."
end
ACTIONS.miniBosses = function()
	S.CampService.respawnMiniBosses()
	return true, "Mini-bosses respawned."
end
ACTIONS.tuneGlobal = function(_, _, args)
	if not Tuning.isGlobalKey(args.key) then
		return false, "Unknown setting."
	end
	local v = math.clamp(tonumber(args.value) or 1, 0.1, 10)
	Tuning.values.global[args.key] = v ~= 1 and v or nil
	broadcastTuning()
	return true, string.format("%s x%s", Tuning.GLOBAL_LABELS[args.key], fmt(v))
end
ACTIONS.tuneAbility = function(_, _, args)
	if not Abilities.get(args.abilityId) or (args.field ~= "dmg" and args.field ~= "cd") then
		return false, "Unknown ability."
	end
	local v = math.clamp(tonumber(args.value) or 1, 0.1, 10)
	local entry = Tuning.values.abilities[args.abilityId] or {}
	entry[args.field] = v ~= 1 and v or nil
	Tuning.values.abilities[args.abilityId] = next(entry) and entry or nil
	broadcastTuning()
	return true, "Ability tuned."
end
ACTIONS.tuneTalent = function(_, _, args)
	if not Talents.byId[args.talentId] then
		return false, "Unknown skill."
	end
	local v = math.clamp(tonumber(args.value) or 1, 0, 10)
	Tuning.values.talents[args.talentId] = v ~= 1 and v or nil
	broadcastTuning()
	return true, "Skill tuned."
end
ACTIONS.tuneDungeon = function(_, _, args)
	if not Dungeons.get(args.dungeonId) or not table.find(Tuning.DUNGEON_KEYS, args.key) then
		return false, "Unknown dungeon setting."
	end
	local v = math.clamp(tonumber(args.value) or 1, 0.1, 10)
	local entry = Tuning.values.dungeons[args.dungeonId] or {}
	entry[args.key] = v ~= 1 and v or nil
	Tuning.values.dungeons[args.dungeonId] = next(entry) and entry or nil
	broadcastTuning()
	return true, string.format("%s %s x%s (next run)", Dungeons.get(args.dungeonId).name, Tuning.DUNGEON_LABELS[args.key], fmt(v))
end
ACTIONS.enterDungeon = function(_, target, args)
	if not Dungeons.get(args.dungeonId) then
		return false, "Unknown dungeon."
	end
	return S.DungeonService.adminEnter(target, args.dungeonId)
end
ACTIONS.dungeonReset = function(_, target)
	local profile = S.PlayerService.getProfile(target)
	profile.dungeons = { seen = 0, clears = {}, pity = {} }
	profile.dungeonClears = 0
	return true, "Dungeon clears, pity and the unlock badge reset."
end
ACTIONS.resetTuning = function()
	Tuning.reset()
	broadcastTuning()
	return true, "Balance reset to the Config values."
end
ACTIONS.printTuning = function()
	local report = tuningReport()
	print(report)
	return true, report
end

local function onAction(player: Player, action, args)
	if not admins[player] then
		return false, "You're not an admin."
	end
	local fn = type(action) == "string" and ACTIONS[action]
	if not fn then
		return false, "Unknown admin action."
	end
	args = type(args) == "table" and args or {}
	local target = targetOf(player, args)
	if not S.PlayerService.getProfile(target) then
		return false, "That player isn't loaded."
	end
	local ok, result, message = pcall(fn, player, target, args)
	if not ok then
		warn("[Admin]", action, result)
		return false, "Error: " .. tostring(result)
	end
	S.PlayerService.markDirty(target)
	return result, message
end

function AdminService.init(services)
	S = services
end

function AdminService.start()
	Remotes.func("RedeemCode").OnServerInvoke = onRedeem
	Remotes.func("AdminAction").OnServerInvoke = onAction
	Remotes.func("GetTuning").OnServerInvoke = function()
		return Tuning.values
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
		attempts[player] = nil
	end)
end

return AdminService
