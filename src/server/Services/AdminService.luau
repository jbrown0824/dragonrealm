-- Codes and admin mode. Players type codes into the 🎁 Codes window: promo codes give a one-time
-- reward, and the admin code (Config/AdminConfig, server-only) unlocks the admin panel for the
-- rest of the session. Admins can change any dragon's level and type, hand out items, start
-- bosses, and tune balance live (Shared/Tuning) for everyone on the server.

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
local Tuning = require(Shared.Tuning)
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
ACTIONS.miniBosses = function()
	S.CampService.respawnMiniBosses()
	return true, "Mini-bosses respawned."
end
ACTIONS.tuneGlobal = function(_, _, args)
	if not table.find(Tuning.GLOBAL_KEYS, args.key) then
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
