-- Loads and saves player profiles with DataStoreService.
-- In Studio without "Enable Studio Access to API Services", saving is skipped and everyone
-- starts fresh each session (a warning is printed).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)

local DataService = {}

local AUTOSAVE_INTERVAL = 120
local PROFILE_VERSION = 1

local store = nil
local storeAvailable = true
local profiles = {} -- [Player] = profile
local noSave = {} -- [Player] = true when loading failed (so we never overwrite real data)

local function defaultProfile()
	return {
		version = PROFILE_VERSION,
		class = nil,
		level = 1,
		xp = 0,
		gold = Game.START_GOLD,
		talents = {},
		inventory = {},
		equipped = {},
		seeds = Util.deepCopy(Game.START_SEEDS),
		plots = {},
		plotsUnlocked = Game.START_PLOTS,
		quests = { active = {}, done = {} },
		glory = 0,
		bossKills = 0,
		vikingKills = 0,
		flowersHarvested = 0,
		-- added in the survival / pets update
		hunger = Game.HUNGER_MAX,
		food = {}, -- [foodId] = count
		potions = {}, -- [potionId] = rank
		eggs = {}, -- [eggId] = count
		pets = {}, -- list of { uid, species, level?, golden? }
		petsEquipped = {}, -- list of pet uids
		petCounter = 0,
		treats = 0, -- Pet Treats from harvesting, fed to pets to level them up
		shopStock = false, -- StockService: this player's limited stock at the town vendors
		-- added in the collections / paragon / store update
		paragon = 0, -- levels past the cap (xp keeps counting)
		loadout = {}, -- ability ids on keys 2-5 (see TalentUtil.resolveLoadout)
		championKills = 0,
		petBook = {}, -- [species] = 1 hatched, 2 made golden
		bookSynced = false, -- pets owned before the pet book existed have been added to it
		achievements = {}, -- [achievementId] = tiers reached
		milestones = {}, -- [pet milestone index as string] = true
		skins = {}, -- [skinId] = true
		skin = "Classic",
		titles = {}, -- [title] = true
		title = "",
		passes = {}, -- [passId] = true (Robux game passes, remembered for Studio tests)
		receipts = {}, -- recent Robux purchase ids, so a purchase is never granted twice
		starterPack = false, -- bought the Starter Pack
		goldRushLeft = 0, -- seconds of Gold Rush (Robux boost) left; only counts down while playing
		robots = { water = false, harvest = 0 },
		tutorial = 0, -- step reached; -1 = finished or skipped
		tutorialRewarded = false,
		codes = {}, -- [code] = true once redeemed
		animalsHunted = 0,
		fishCaught = 0,
		chestsOpened = 0,
		-- added in the day/night update
		raidsRepelled = 0, -- night raids on Dragon Town beaten (RaidService)
		rangeLevel = 0, -- highest target practice level cleared (RangeService)
		settings = { minimap = true },
		-- added in the friendlier-intro update
		menus = {}, -- [menu id from Game.MENUS] = 1 shown / 2 clicked (HUD)
		bagDot = false, -- gear was auto-equipped since the Bag was last opened
	}
end

-- Fill in any keys added to the default profile since this save was made.
local function reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = Util.deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Game.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		storeAvailable = false
		warn("[DataService] DataStore unavailable, progress will not save:", result)
	end
end

function DataService.load(player: Player)
	local data = nil
	if store and storeAvailable then
		local success, err
		for attempt = 1, 3 do
			success, err = pcall(function()
				data = store:GetAsync(keyFor(player))
			end)
			if success then
				break
			end
			task.wait(attempt)
		end
		if not success then
			local msg = tostring(err)
			if msg:find("403") or msg:find("Studio") or msg:find("API") then
				storeAvailable = false
				warn("[DataService] DataStores are off in Studio. Enable 'Studio Access to API Services' in Game Settings > Security to test saving.")
			else
				noSave[player] = true
				warn("[DataService] Failed to load data for", player.Name, msg)
			end
		end
	end

	if type(data) ~= "table" then
		data = defaultProfile()
	else
		-- Dragons from before the tutorial existed don't need the new-player tour.
		local veteran = data.tutorial == nil and data.class ~= nil
		-- ...and dragons from before the menu unlocks keep every menu button.
		local hadMenus = data.menus ~= nil or data.class == nil
		data = reconcile(data, defaultProfile())
		if veteran then
			data.tutorial = -1
		end
		if not hadMenus then
			for _, id in ipairs(Game.MENUS) do
				data.menus[id] = 2
			end
		end
	end
	if not player.Parent then
		return nil
	end
	profiles[player] = data
	return data
end

function DataService.get(player: Player)
	return profiles[player]
end

function DataService.didLoadFail(player: Player): boolean
	return noSave[player] == true
end

function DataService.save(player: Player)
	local data = profiles[player]
	if not data or not store or not storeAvailable or noSave[player] then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
	end
end

function DataService.release(player: Player)
	DataService.save(player)
	profiles[player] = nil
	noSave[player] = nil
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(DataService.save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
