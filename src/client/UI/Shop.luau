-- Town shops, one job each: buy gear at the Armory (limited stock that restocks every few
-- minutes), sell gear and food at the Hoard Exchange, upgrade at the Anvil of Ages. The window
-- shows only the page of the shop you're visiting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Food = require(Shared.Config.Food)
local Game = require(Shared.Config.Game)
local ItemUtil = require(Shared.ItemUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Shop = {}
local App

local window, content, titleLabel
local tab = "Buy"
local goldLabel
local list
local restockButton
local busy = false

local TAB_INFO = {
	Buy = { title = "⚔️ Emberforge Armory", hint = "Limited stock for your level, always with one Epic." },
	Sell = { title = "💰 Hoard Exchange", hint = "Sell gear you don't need (unequip it first), and extra food." },
	Upgrade = { title = "🔨 Anvil of Ages", hint = "Each upgrade adds +10% to an item's stats, up to +" .. Game.MAX_UPGRADE .. "." },
}

-- badge: optional { text, color } shown as a tag on the row (EQUIPPED, better than yours...)
local function row(order: number, item, rightText: string, buttonText: string, buttonColor: Color3, enabled: boolean, onClick, extra: string?, badge)
	local frame = Theme.make("Frame", {
		Size = UDim2.new(1, -10, 0, 58),
		BackgroundColor3 = badge and badge.color:Lerp(C.panel2, 0.8) or C.panel2,
		LayoutOrder = order,
		Parent = list,
	})
	Theme.corner(frame, 8)
	Theme.stroke(frame, badge and badge.color or ItemUtil.rarityColor(item.rarity), badge and 2.5 or 1.5, badge and 0 or 0.4)
	if badge then
		local tag = Theme.label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -330, 0, 15),
			Size = UDim2.fromOffset(150, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = badge.color,
			TextColor3 = Color3.fromRGB(15, 25, 15),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = badge.text,
			ZIndex = 3,
			Parent = frame,
		})
		Theme.corner(tag, 6)
	end
	Theme.label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, badge and -470 or -335, 0, 22),
		TextSize = 16,
		TextColor3 = ItemUtil.rarityColor(item.rarity),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = Items.SlotInfo[item.slot].icon .. " " .. ItemUtil.displayName(item),
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -335, 0, 24),
		TextSize = 12,
		Font = Theme.Fonts.body,
		TextColor3 = C.subtext,
		Text = extra or (item.rarity .. "  •  iLvl " .. item.ilvl .. "  •  " .. table.concat(ItemUtil.describeStats(ItemUtil.getStats(item)), ", ")),
		Parent = frame,
	})
	Theme.label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -140, 0.5, 0),
		Size = UDim2.fromOffset(185, 24),
		TextSize = 16,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = rightText,
		Parent = frame,
	})
	local button = Theme.button(buttonText, buttonColor, onClick, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(120, 38),
		Parent = frame,
	})
	Theme.setButtonEnabled(button, enabled)
	return button
end

local function act(remoteName: string, arg, successText: string?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = Remotes.func(remoteName):InvokeServer(arg)
		busy = false
		if not ok then
			App.Windows.notify(result or "Couldn't do that.", C.bad, "🛒")
		else
			App.Sfx.play("Coin")
			if successText then
				App.Windows.notify(successText, C.good, "🛒")
			end
		end
	end)
end

-- "Restocks in 3:12" (shared by the Armory, the Hatchery and the Cauldron).
function Shop.restockText(p): string
	local left = math.max(0, (p.restockAt or 0) - workspace:GetServerTimeNow())
	return "🔄 Restocks in " .. Util.formatTime(left)
end

function Shop.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	titleLabel.Text = TAB_INFO[tab].title
	restockButton.Visible = tab == "Buy" and App.Store.available("product", "Restock")
	goldLabel.Text = string.format("💰 %s gold   <font color=\"#B9AFD2\">%s</font>%s", Util.formatNumber(p.gold), TAB_INFO[tab].hint,
		tab == "Buy" and ("   <font color=\"#8CE678\">" .. Shop.restockText(p) .. "</font>") or "")
	Theme.clear(list)

	if tab == "Buy" then
		local gear = p.shopStock and p.shopStock.gear or {}
		for i, entry in ipairs(gear) do
			local item = ItemUtil.new(entry.slot, p.level, entry.rarity)
			local price = ItemUtil.buyPrice(item)
			local soldOut = entry.left <= 0
			local worn = p.equipped[item.slot] and App.State.findItem(p.equipped[item.slot])
			local badge = not soldOut and ItemUtil.isUpgrade(item, worn) and { text = "⬆️ Better than yours", color = Color3.fromRGB(110, 230, 110) } or nil
			local stockText = soldOut and "<font color=\"#F05A5A\">SOLD OUT</font>" or string.format("%d left  •  ", entry.left)
			local button = row(i, item, soldOut and stockText or (stockText .. Util.formatNumber(price) .. " 💰"), soldOut and "Sold out" or "Buy", Color3.fromRGB(60, 140, 70), not soldOut and p.gold >= price, function()
				act("BuyItem", i, "Bought " .. ItemUtil.displayName(item) .. "! Equip it from your Bag.")
			end, nil, badge)
			if not soldOut then
				Theme.onDisabledClick(button, function()
					App.Store.needGold(price)
				end)
			end
		end
	elseif tab == "Sell" then
		local n = 0
		for _, item in ipairs(p.inventory) do
			if p.equipped[item.slot] ~= item.id then
				n += 1
				row(n, item, "+" .. Util.formatNumber(ItemUtil.sellPrice(item)) .. " 💰", "Sell", Color3.fromRGB(170, 120, 40), true, function()
					act("SellItem", item.id)
				end)
			end
		end
		if n == 0 then
			Theme.label({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, TextSize = 15, TextColor3 = C.subtext, Text = "No gear to sell. (Equipped items can't be sold.)", Parent = list })
		end
		-- Food (fish and packed meat)
		for i, foodId in ipairs(Food.Order) do
			local count = p.food and p.food[foodId] or 0
			if count > 0 then
				local item = Food.get(foodId)
				local frame = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 50), BackgroundColor3 = C.panel2, LayoutOrder = 1000 + i, Parent = list })
				Theme.corner(frame, 8)
				Theme.label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -400, 1, 0), TextSize = 16, TextColor3 = item.color, Text = string.format("%s %s  x%d", item.icon, item.name, count), Parent = frame })
				Theme.label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -250, 0.5, 0), Size = UDim2.fromOffset(120, 24), TextSize = 15, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Right, Text = "+" .. item.sell .. " 💰 each", Parent = frame })
				Theme.button("Sell 1", Color3.fromRGB(170, 120, 40), function()
					act("SellFood", foodId)
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -128, 0.5, 0), Size = UDim2.fromOffset(110, 34), Parent = frame })
				Theme.button("Sell all", Color3.fromRGB(170, 120, 40), function()
					if busy then
						return
					end
					busy = true
					task.spawn(function()
						local ok, result = Remotes.func("SellFood"):InvokeServer(foodId, count)
						busy = false
						if ok then
							App.Sfx.play("Coin")
						else
							App.Windows.notify(result or "Couldn't sell that.", C.bad, "🛒")
						end
					end)
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 34), Parent = frame })
			end
		end
	else
		local items = table.clone(p.inventory)
		table.sort(items, function(a, b)
			local ea = p.equipped[a.slot] == a.id
			local eb = p.equipped[b.slot] == b.id
			if ea ~= eb then
				return ea
			end
			return ItemUtil.score(a) > ItemUtil.score(b)
		end)
		for i, item in ipairs(items) do
			local maxed = (item.up or 0) >= Game.MAX_UPGRADE
			local cost = ItemUtil.upgradeCost(item)
			local nextItem = table.clone(item)
			nextItem.up = (item.up or 0) + 1
			local now = ItemUtil.describeStats(ItemUtil.getStats(item))
			local after = ItemUtil.describeStats(ItemUtil.getStats(nextItem))
			local extra = maxed and "Fully upgraded!" or (table.concat(now, ", ") .. "  →  <font color=\"#6EDC6E\">" .. table.concat(after, ", ") .. "</font>")
			local badge = p.equipped[item.slot] == item.id and { text = "✅ EQUIPPED", color = Color3.fromRGB(110, 230, 110) } or nil
			local button = row(i, item, maxed and "MAX" or (Util.formatNumber(cost) .. " 💰"), maxed and "Maxed" or ("Upgrade to +" .. nextItem.up), Color3.fromRGB(70, 100, 180), not maxed and p.gold >= cost, function()
				act("UpgradeItem", item.id, "Upgraded to " .. ItemUtil.displayName(nextItem) .. "!")
			end, extra, badge)
			if not maxed then
				Theme.onDisabledClick(button, function()
					App.Store.needGold(cost)
				end)
			end
		end
		if #items == 0 then
			Theme.label({ Size = UDim2.new(1, 0, 0, 40), TextSize = 15, TextColor3 = C.subtext, Text = "You have no gear to upgrade yet.", Parent = list })
		end
	end
end

function Shop.open(which: string?)
	tab = which or "Buy"
	App.Windows.open("Shop")
end

function Shop.init(app)
	App = app
	local close, titleBar
	window, content, close, titleBar = Theme.window(App.Windows.guis.Windows, "Shop", Vector2.new(780, 540))
	titleLabel = titleBar.Title
	close.Activated:Connect(function()
		App.Windows.close("Shop")
	end)
	goldLabel = Theme.label({ Size = UDim2.new(1, -170, 0, 32), TextSize = 14, Text = "", Parent = content })
	restockButton = Theme.button("🔄 Restock now (R$)", Color3.fromRGB(40, 150, 70), function()
		App.Store.buy("product", "Restock")
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(160, 28), TextSize = 13, Parent = content })
	list = Theme.scroll(content, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	Theme.list(list, 6)

	App.Windows.register("Shop", window, Shop.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Shop.refresh()
		end
	end)
	-- keep the restock countdown ticking
	task.spawn(function()
		while true do
			task.wait(1)
			local p = App.State.profile
			if window.Visible and tab == "Buy" and p then
				goldLabel.Text = string.format("💰 %s gold   <font color=\"#B9AFD2\">%s</font>   <font color=\"#8CE678\">%s</font>", Util.formatNumber(p.gold), TAB_INFO.Buy.hint, Shop.restockText(p))
			end
		end
	end)
	Remotes.event("OpenShop").OnClientEvent:Connect(function(which)
		Shop.open(which)
	end)
end

return Shop
