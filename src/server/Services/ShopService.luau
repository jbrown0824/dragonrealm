-- The three gear shops in town, one job each: the Emberforge Armory buys (limited stock from
-- StockService), the Hoard Exchange sells (gear and food) and the Anvil of Ages upgrades. Each
-- stall's prompt opens its own page.
-- Other stalls (the Bubbling Cauldron, the Hatchery) are tagged "PanelPrompt" and just open
-- their window; PotionService and PetService handle the buying.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local ItemUtil = require(Shared.ItemUtil)
local Remotes = require(Shared.Remotes)

local ShopService = {}
local S

local SHOP_RANGE = 45

-- Is the player standing near one of these shops (by id)? With no ids: any gear shop.
function ShopService.isNear(player: Player, ids: { string }?): boolean
	local _, _, root = S.PlayerService.getCharacter(player)
	if not root then
		return false
	end
	for _, shop in ipairs(Zones.Shops) do
		local match = if ids then table.find(ids, shop.id) ~= nil else shop.tab ~= nil
		if match and (root.Position - shop.position).Magnitude <= SHOP_RANGE then
			return true
		end
	end
	return false
end

local function onBuy(player: Player, index)
	if type(index) ~= "number" then
		return false, "Invalid item."
	end
	if not ShopService.isNear(player, { "Armory" }) then
		return false, "Visit the Emberforge Armory to buy gear."
	end
	local stock = S.StockService.get(player)
	local entry = stock and stock.gear[index]
	local profile = S.PlayerService.getProfile(player)
	if not entry or not profile then
		return false, "That item is no longer for sale."
	end
	if entry.left <= 0 then
		return false, "Sold out! New stock arrives soon."
	end
	if #profile.inventory >= Game.INVENTORY_LIMIT then
		return false, "Your bag is full. Sell something first!"
	end
	local item = ItemUtil.new(entry.slot, profile.level, entry.rarity)
	local price = ItemUtil.buyPrice(item)
	if not S.PlayerService.spendGold(player, price) then
		return false, string.format("You need %d gold.", price)
	end
	S.StockService.take(player, "gear", index)
	S.PlayerService.addItem(player, item, true)
	S.QuestService.progress(player, "buy", nil, 1)
	return true, item
end

local function onSell(player: Player, itemId)
	if type(itemId) ~= "string" then
		return false, "Invalid item."
	end
	if not ShopService.isNear(player, { "Exchange" }) then
		return false, "Visit the Hoard Exchange to sell gear."
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
	if not ShopService.isNear(player, { "Forge" }) then
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
	Remotes.func("BuyItem").OnServerInvoke = onBuy
	Remotes.func("SellItem").OnServerInvoke = onSell
	Remotes.func("UpgradeItem").OnServerInvoke = onUpgrade

	for _, prompt in ipairs(CollectionService:GetTagged("ShopPrompt")) do
		prompt.Triggered:Connect(function(player)
			Remotes.event("OpenShop"):FireClient(player, prompt:GetAttribute("ShopTab"), prompt:GetAttribute("ShopName"))
		end)
	end
	for _, prompt in ipairs(CollectionService:GetTagged("PanelPrompt")) do
		prompt.Triggered:Connect(function(player)
			Remotes.event("OpenPanel"):FireClient(player, prompt:GetAttribute("Panel"))
		end)
	end
end

return ShopService
