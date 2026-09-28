-- Town shops: buy gear at the Armory, sell at the Hoard Exchange, upgrade at the Anvil of Ages.

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
local tabButtons = {}
local goldLabel
local list
local stock = {}
local stockLevel = nil
local busy = false

local TAB_INFO = {
	Buy = { title = "⚔️ Emberforge Armory", hint = "Fresh gear for your level. Rarer gear drops from vikings and bosses!" },
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
			Position = UDim2.new(1, -300, 0, 15),
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
		Size = UDim2.new(1, badge and -460 or -300, 0, 22),
		TextSize = 16,
		TextColor3 = ItemUtil.rarityColor(item.rarity),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = Items.SlotInfo[item.slot].icon .. " " .. ItemUtil.displayName(item),
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -300, 0, 24),
		TextSize = 12,
		Font = Theme.Fonts.body,
		TextColor3 = C.subtext,
		Text = extra or (item.rarity .. "  •  iLvl " .. item.ilvl .. "  •  " .. table.concat(ItemUtil.describeStats(ItemUtil.getStats(item)), ", ")),
		Parent = frame,
	})
	Theme.label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -140, 0.5, 0),
		Size = UDim2.fromOffset(150, 24),
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
			App.Notifications.toast(result or "Couldn't do that.", C.bad, "🛒")
		else
			App.Sfx.play("Coin")
			if successText then
				App.Notifications.toast(successText, C.good, "🛒")
			end
		end
	end)
end

function Shop.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	titleLabel.Text = TAB_INFO[tab].title
	goldLabel.Text = string.format("💰 %s gold   <font color=\"#B9AFD2\">%s</font>", Util.formatNumber(p.gold), TAB_INFO[tab].hint)
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == tab and C.accentDark or C.panel3
	end
	Theme.clear(list)

	if tab == "Buy" then
		for i, entry in ipairs(stock) do
			local item = entry.item
			local affordable = p.gold >= entry.price
			local worn = p.equipped[item.slot] and App.State.findItem(p.equipped[item.slot])
			local badge = ItemUtil.isUpgrade(item, worn) and { text = "⬆️ Better than yours", color = Color3.fromRGB(110, 230, 110) } or nil
			row(i, item, Util.formatNumber(entry.price) .. " 💰", "Buy", Color3.fromRGB(60, 140, 70), affordable, function()
				act("BuyItem", entry.index, "Bought " .. ItemUtil.displayName(item) .. "! Equip it from your Bag.")
			end, nil, badge)
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
							App.Notifications.toast(result or "Couldn't sell that.", C.bad, "🛒")
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
			row(i, item, maxed and "MAX" or (Util.formatNumber(cost) .. " 💰"), maxed and "Maxed" or ("Upgrade to +" .. nextItem.up), Color3.fromRGB(70, 100, 180), not maxed and p.gold >= cost, function()
				act("UpgradeItem", item.id, "Upgraded to " .. ItemUtil.displayName(nextItem) .. "!")
			end, extra, badge)
		end
		if #items == 0 then
			Theme.label({ Size = UDim2.new(1, 0, 0, 40), TextSize = 15, TextColor3 = C.subtext, Text = "You have no gear to upgrade yet.", Parent = list })
		end
	end
end

local function loadStock()
	stockLevel = App.State.profile and App.State.profile.level
	task.spawn(function()
		stock = Remotes.func("GetShopStock"):InvokeServer() or {}
		if window.Visible then
			Shop.refresh()
		end
	end)
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
	for i, name in ipairs({ "Buy", "Sell", "Upgrade" }) do
		tabButtons[name] = Theme.button(name, C.panel3, function()
			tab = name
			if name == "Buy" then
				loadStock()
			end
			Shop.refresh()
		end, { Position = UDim2.fromOffset((i - 1) * 110, 0), Size = UDim2.fromOffset(100, 32), Parent = content })
	end
	goldLabel = Theme.label({ Position = UDim2.fromOffset(340, 0), Size = UDim2.new(1, -340, 0, 32), TextSize = 13, Text = "", Parent = content })
	list = Theme.scroll(content, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	Theme.list(list, 6)

	App.Windows.register("Shop", window, function()
		loadStock()
		Shop.refresh()
	end)
	App.State.changed:Connect(function()
		if window.Visible then
			local p = App.State.profile
			if tab == "Buy" and p and p.level ~= stockLevel then
				loadStock()
			end
			Shop.refresh()
		end
	end)
	Remotes.event("OpenShop").OnClientEvent:Connect(function(which)
		Shop.open(which)
	end)
end

return Shop
