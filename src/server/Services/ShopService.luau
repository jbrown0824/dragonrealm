-- The three gear shops in town, one job each: the Emberforge Armory buys (limited stock from
-- StockService), the Hoard Exchange sells (gear and food) and the Anvil of Ages upgrades. Each
-- stall's prompt opens its own page.
-- Other stalls (the Bubbling Cauldron, the Hatchery) are tagged "PanelPrompt" and just open
-- their window; PotionService and PetService handle the buying.
--
-- After a lost night raid (RaidService) every town vendor closes for a while: they refuse to
-- trade (every vendor checks ShopService.closedMessage), the prompts say "Closed" and a board
-- hangs over each counter. Clients count down from the workspace attribute "ShopsClosedUntil".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Zones = require(Shared.Config.Zones)
local ItemUtil = require(Shared.ItemUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local ShopService = {}
local S

local SHOP_RANGE = 45
local closedUntil = 0
local closedBoards = {}

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

---------------------------------------------------------------- closing after a raid

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Why the vendors won't trade right now, or nil when they're open.
function ShopService.closedMessage(): string?
	local left = closedUntil - serverNow()
	if left <= 0 then
		return nil
	end
	return string.format("The raiders looted the market! The shops reopen in %s.", Util.formatTime(left))
end

local function vendorPrompts()
	local list = {}
	for _, prompt in ipairs(CollectionService:GetTagged("ShopPrompt")) do
		table.insert(list, prompt)
	end
	for _, prompt in ipairs(CollectionService:GetTagged("PanelPrompt")) do
		local panel = prompt:GetAttribute("Panel")
		if panel == "Potions" or panel == "Hatchery" then
			table.insert(list, prompt)
		end
	end
	return list
end

local function closedBoard(shop)
	local town = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Town")
	if not town then
		return nil
	end
	local cf = CFrame.lookAt(shop.position, shop.position + Vector3.new(shop.facing.X, 0, shop.facing.Z).Unit)
	local board = Instance.new("Part")
	board.Name = "ClosedBoard"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.Size = Vector3.new(13, 3.4, 0.3)
	board.CFrame = cf * CFrame.new(0, 8, -5.2) * CFrame.Angles(0, 0, math.rad(-4))
	board.Color = Color3.fromRGB(90, 60, 38)
	board.Material = Enum.Material.WoodPlanks
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 120, 90)
	label.TextStrokeTransparency = 0.3
	label.Text = "🔒 CLOSED\nRaided! Back soon"
	label.Parent = gui
	gui.Parent = board
	board.Parent = town
	return board
end

function ShopService.reopen()
	closedUntil = 0
	workspace:SetAttribute("ShopsClosedUntil", nil)
	for _, prompt in ipairs(vendorPrompts()) do
		local text = prompt:GetAttribute("OpenText")
		if text then
			prompt.ActionText = text
		end
	end
	for _, board in ipairs(closedBoards) do
		board:Destroy()
	end
	closedBoards = {}
end

-- Close every town vendor for `seconds`.
function ShopService.close(seconds: number)
	closedUntil = serverNow() + seconds
	workspace:SetAttribute("ShopsClosedUntil", closedUntil)
	for _, prompt in ipairs(vendorPrompts()) do
		if not prompt:GetAttribute("OpenText") then
			prompt:SetAttribute("OpenText", prompt.ActionText)
		end
		prompt.ActionText = "🔒 Closed"
	end
	if #closedBoards == 0 then
		for _, shop in ipairs(Zones.Shops) do
			local board = closedBoard(shop)
			if board then
				table.insert(closedBoards, board)
			end
		end
	end
	local token = closedUntil
	task.delay(seconds, function()
		if closedUntil == token then
			ShopService.reopen()
		end
	end)
end

---------------------------------------------------------------- trading

local function onBuy(player: Player, index)
	if type(index) ~= "number" then
		return false, "Invalid item."
	end
	if not ShopService.isNear(player, { "Armory" }) then
		return false, "Visit the Emberforge Armory to buy gear."
	end
	local closed = ShopService.closedMessage()
	if closed then
		return false, closed
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
	local closed = ShopService.closedMessage()
	if closed then
		return false, closed
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
	local closed = ShopService.closedMessage()
	if closed then
		return false, closed
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
			local closed = ShopService.closedMessage()
			if closed then
				S.PlayerService.notify(player, closed, Color3.fromRGB(255, 140, 100), "🔒")
				return
			end
			Remotes.event("OpenShop"):FireClient(player, prompt:GetAttribute("ShopTab"), prompt:GetAttribute("ShopName"))
		end)
	end
	for _, prompt in ipairs(CollectionService:GetTagged("PanelPrompt")) do
		prompt.Triggered:Connect(function(player)
			local panel = prompt:GetAttribute("Panel")
			local closed = ShopService.closedMessage()
			if closed and (panel == "Potions" or panel == "Hatchery") then
				S.PlayerService.notify(player, closed, Color3.fromRGB(255, 140, 100), "🔒")
				return
			end
			Remotes.event("OpenPanel"):FireClient(player, panel, prompt:GetAttribute("DungeonId") or prompt:GetAttribute("DragonClass"))
		end)
	end
end

return ShopService
