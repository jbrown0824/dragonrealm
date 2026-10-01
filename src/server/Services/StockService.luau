-- Limited, per-player stock for the Emberforge Armory (gear), Nestmother's Hatchery (eggs) and
-- the Bubbling Cauldron (potions), tuned in Config/Shops.
--
-- All three restock together on one server-wide clock (every Shops.RESTOCK_SECONDS of server
-- time). A player's stock lives on their profile (`shopStock`), so it's saved and rejoining
-- doesn't reroll it; it's rerolled when the clock ticks over, or early with the Robux restock.
-- The vendors (ShopService, PetService, PotionService) call StockService.left / take.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shops = require(Shared.Config.Shops)
local Items = require(Shared.Config.Items)
local Potions = require(Shared.Config.Potions)
local Util = require(Shared.Util)

local StockService = {}
local S

local function cycleNow(): number
	return math.floor(workspace:GetServerTimeNow() / Shops.RESTOCK_SECONDS)
end

-- Server time of the next restock (the client shows a countdown to it).
function StockService.nextRestockAt(): number
	return (cycleNow() + 1) * Shops.RESTOCK_SECONDS
end

local function roll(range): number
	return math.random(range[1], range[2])
end

local function generate(profile)
	local cfg = Shops.Gear
	local gear = {}
	local epics = 0
	for _ = 1, roll(cfg.count) do
		local rarity = Util.weightedPick(cfg.rarityWeights) or "Common"
		if rarity == "Epic" then
			epics += 1
		end
		table.insert(gear, { slot = Items.Slots[math.random(1, #Items.Slots)], rarity = rarity })
	end
	-- always at least one Epic
	for _, entry in ipairs(gear) do
		if epics >= cfg.minEpic then
			break
		end
		if entry.rarity ~= "Epic" then
			entry.rarity = "Epic"
			epics += 1
		end
	end
	-- The same slot and rarity twice becomes one row with more in stock. (Items are made at
	-- your level when you buy them, so leveling up mid-restock still gets you fresh gear.)
	local merged, byKey = {}, {}
	for _, entry in ipairs(gear) do
		local key = entry.slot .. entry.rarity
		local amount = roll(cfg.amount[entry.rarity])
		if byKey[key] then
			byKey[key].left += amount
		else
			entry.left = amount
			byKey[key] = entry
			table.insert(merged, entry)
		end
	end
	gear = merged
	table.sort(gear, function(a, b)
		local ra, rb = table.find(Items.RarityOrder, a.rarity) or 0, table.find(Items.RarityOrder, b.rarity) or 0
		if ra ~= rb then
			return ra > rb
		end
		return a.slot < b.slot
	end)

	local eggs = {}
	for eggId, egg in pairs(Shops.Eggs) do
		if math.random() < egg.chance then
			eggs[eggId] = roll(egg.amount)
		end
	end

	-- potions: a few you haven't fully brewed yet
	local candidates = {}
	for _, potionId in ipairs(Potions.Order) do
		if Potions.cost(potionId, profile.potions[potionId] or 0) then
			table.insert(candidates, potionId)
		end
	end
	local potions = {}
	for _ = 1, math.min(#candidates, roll(Shops.Potions.count)) do
		local potionId = table.remove(candidates, math.random(1, #candidates))
		potions[potionId] = roll(Shops.Potions.amount)
	end

	return { cycle = cycleNow(), gear = gear, eggs = eggs, potions = potions }
end

-- The player's current stock (restocked first if the clock has ticked over).
function StockService.get(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return nil
	end
	local stock = profile.shopStock
	if type(stock) ~= "table" or stock.cycle ~= cycleNow() then
		stock = generate(profile)
		profile.shopStock = stock
		S.PlayerService.markDirty(player)
	end
	return stock
end

-- How many are left: shop "gear" (key = index), "eggs" (egg id) or "potions" (potion id).
function StockService.left(player: Player, shop: string, key): number
	local stock = StockService.get(player)
	if not stock then
		return 0
	end
	if shop == "gear" then
		local entry = type(key) == "number" and stock.gear[key]
		return entry and entry.left or 0
	end
	local list = stock[shop]
	return list and list[key] or 0
end

function StockService.take(player: Player, shop: string, key): boolean
	if StockService.left(player, shop, key) <= 0 then
		return false
	end
	local stock = StockService.get(player)
	if shop == "gear" then
		stock.gear[key].left -= 1
	else
		stock[shop][key] -= 1
	end
	S.PlayerService.markDirty(player)
	return true
end

-- Reroll a player's stock right now (the Robux restock and the admin panel).
function StockService.restockNow(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	profile.shopStock = generate(profile)
	S.PlayerService.markDirty(player)
	S.PlayerService.notify(player, "The Armory, Hatchery and Cauldron have fresh stock for you!", Color3.fromRGB(140, 230, 120), "🛒")
end

function StockService.init(services)
	S = services
end

function StockService.start()
	-- Restock everyone when the clock ticks over (so open shop windows refresh on their own).
	local lastCycle = cycleNow()
	while true do
		task.wait(2)
		local cycle = cycleNow()
		if cycle ~= lastCycle then
			lastCycle = cycle
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = S.PlayerService.getProfile(player)
				if profile and profile.class then
					StockService.get(player)
					if not S.DungeonService.inRun(player) then -- (no shop news in a dungeon)
						S.PlayerService.notify(player, "The shops in town just restocked!", Color3.fromRGB(140, 230, 120), "🛒")
					end
				end
			end
		end
	end
end

return StockService
