-- The three town shops: Emberforge Armory (buy), Hoard Exchange (sell) and the Anvil of Ages
-- (upgrade). Shop stalls have ProximityPrompts that open the shop UI on the matching tab.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Items = require(Shared.Config.Items)
local Zones = require(Shared.Config.Zones)
local ItemUtil = require(Shared.ItemUtil)
local Remotes = require(Shared.Remotes)

local ShopService = {}
local S

local STOCK_RARITIES = { "Common", "Uncommon", "Rare" }
local SHOP_RANGE = 45

local stock = {} -- [Player] = { level, items = { item } }

local function nearShop(player: Player): boolean
	local _, _, root = S.PlayerService.getCharacter(player)
	if not root then
		return false
	end
	for _, shop in ipairs(Zones.Shops) do
		if (root.Position - shop.position).Magnitude <= SHOP_RANGE then
			return true
		end
	end
	return false
end

local function getStock(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return nil
	end
	local current = stock[player]
	if current and current.level == profile.level then
		return current
	end
	local items = {}
	for _, slot in ipairs(Items.Slots) do
		for _, rarity in ipairs(STOCK_RARITIES) do
			table.insert(items, ItemUtil.new(slot, profile.level, rarity))
		end
	end
	current = { level = profile.level, items = items }
	stock[player] = current
	return current
end

local function onGetStock(player: Player)
	local s = getStock(player)
	if not s then
		return {}
	end
	local list = {}
	for i, item in ipairs(s.items) do
		table.insert(list, { index = i, item = item, price = ItemUtil.buyPrice(item) })
	end
	return list
end

local function onBuy(player: Player, index)
	if type(index) ~= "number" then
		return false, "Invalid item."
	end
	if not nearShop(player) then
		return false, "Visit a shop in town to buy gear."
	end
	local s = getStock(player)
	local template = s and s.items[index]
	local profile = S.PlayerService.getProfile(player)
	if not template or not profile then
		return false, "That item is no longer for sale."
	end
	if #profile.inventory >= Game.INVENTORY_LIMIT then
		return false, "Your bag is full. Sell something first!"
	end
	local price = ItemUtil.buyPrice(template)
	if not S.PlayerService.spendGold(player, price) then
		return false, string.format("You need %d gold.", price)
	end
	local item = ItemUtil.new(template.slot, template.ilvl, template.rarity)
	S.PlayerService.addItem(player, item, true)
	S.QuestService.progress(player, "buy", nil, 1)
	return true, item
end

local function onSell(player: Player, itemId)
	if type(itemId) ~= "string" then
		return false, "Invalid item."
	end
	if not nearShop(player) then
		return false, "Visit a shop in town to sell gear."
	end
	local profile = S.PlayerService.getProfile(player)
	local item = profile and S.PlayerService.findItem(profile, itemId)
	if not item then
		return false, "Item not found."
	end
	if profile.equipped[item.slot] == itemId then
		return false, "Unequip it first."
	end
	local price = ItemUtil.sellPrice(item)
	S.PlayerService.removeItem(player, itemId)
	S.PlayerService.addGold(player, price)
	S.QuestService.progress(player, "sell", nil, 1)
	return true, price
end

local function onUpgrade(player: Player, itemId)
	if type(itemId) ~= "string" then
		return false, "Invalid item."
	end
	if not nearShop(player) then
		return false, "Visit the Anvil of Ages to upgrade gear."
	end
	local profile = S.PlayerService.getProfile(player)
	local item = profile and S.PlayerService.findItem(profile, itemId)
	if not item then
		return false, "Item not found."
	end
	if (item.up or 0) >= Game.MAX_UPGRADE then
		return false, "Already at max upgrade (+" .. Game.MAX_UPGRADE .. ")."
	end
	local cost = ItemUtil.upgradeCost(item)
	if not S.PlayerService.spendGold(player, cost) then
		return false, string.format("You need %d gold.", cost)
	end
	item.up = (item.up or 0) + 1
	if profile.equipped[item.slot] == itemId then
		S.PlayerService.recompute(player)
	end
	S.PlayerService.markDirty(player)
	S.QuestService.progress(player, "upgrade", nil, 1)
	return true, item
end

function ShopService.init(services)
	S = services
end

function ShopService.start()
	Remotes.func("GetShopStock").OnServerInvoke = onGetStock
	Remotes.func("BuyItem").OnServerInvoke = onBuy
	Remotes.func("SellItem").OnServerInvoke = onSell
	Remotes.func("UpgradeItem").OnServerInvoke = onUpgrade

	for _, prompt in ipairs(CollectionService:GetTagged("ShopPrompt")) do
		prompt.Triggered:Connect(function(player)
			Remotes.event("OpenShop"):FireClient(player, prompt:GetAttribute("ShopTab"), prompt:GetAttribute("ShopName"))
		end)
	end

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		stock[player] = nil
	end)
end

return ShopService
