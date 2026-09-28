-- The Bubbling Cauldron: buy permanent potion upgrades for your dragon. Stock is limited and
-- refills every few minutes (StockService), so not every potion is always on the shelf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PotionInfo = require(Shared.Config.Potions)
local StatCalc = require(Shared.StatCalc)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Potions = {}
local App

local window, list, goldLabel
local busy = false

local function statText(stats, ranks: number): string
	local parts = {}
	for stat, v in pairs(stats) do
		local info = StatCalc.STAT_INFO[stat]
		table.insert(parts, string.format("+%s%% %s", Util.fmt(v * ranks), info and info.label or stat))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function buy(potionId: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = Remotes.func("BuyPotion"):InvokeServer(potionId)
		busy = false
		if ok then
			App.Sfx.play("Coin")
			local p = PotionInfo.get(potionId)
			App.Windows.notify(string.format("You drank %s (rank %d)! %s", p.name, result, statText(p.stats, 1)), p.color, p.icon)
		else
			App.Windows.notify(result or "Couldn't buy that.", C.bad, "🧪")
		end
	end)
end

function Potions.headerText(p): string
	return string.format("💰 %s gold   <font color=\"#B9AFD2\">Potions are permanent: each rank stacks.</font>   <font color=\"#8CE678\">%s</font>", Util.formatNumber(p.gold), App.Shop.restockText(p))
end

function Potions.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	goldLabel.Text = Potions.headerText(p)
	Theme.clear(list)
	local stock = p.shopStock and p.shopStock.potions or {}
	for i, id in ipairs(PotionInfo.Order) do
		local potion = PotionInfo.get(id)
		local rank = (p.potions and p.potions[id]) or 0
		local cost = PotionInfo.cost(id, rank)
		local left = stock[id] or 0
		local row = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 70), BackgroundColor3 = C.panel2, LayoutOrder = i, Parent = list })
		Theme.corner(row, 8)
		Theme.stroke(row, potion.color, 1.5, 0.4)
		Theme.label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(50, 60), TextSize = 36, TextXAlignment = Enum.TextXAlignment.Center, Text = potion.icon, Parent = row })
		Theme.label({
			Position = UDim2.fromOffset(64, 6),
			Size = UDim2.new(0, 220, 0, 22),
			Font = Theme.Fonts.title,
			TextSize = 19,
			TextColor3 = potion.color,
			TextWrapped = false,
			Text = potion.name,
			Parent = row,
		})
		-- rank pips (drawn: circle glyphs don't render in Roblox fonts)
		for k = 1, PotionInfo.maxRank() do
			local pip = Theme.make("Frame", {
				Position = UDim2.fromOffset(290 + (k - 1) * 16, 11),
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = k <= rank and C.gold or C.panel,
				Parent = row,
			})
			Theme.corner(pip, 6)
			Theme.stroke(pip, C.gold, 1.5, k <= rank and 0 or 0.3)
		end
		local now = rank > 0 and ("Now: " .. statText(potion.stats, rank) .. "   ") or ""
		Theme.label({
			Position = UDim2.fromOffset(64, 30),
			Size = UDim2.new(1, -250, 0, 34),
			TextSize = 12,
			Font = Theme.Fonts.body,
			TextColor3 = C.subtext,
			Text = potion.desc .. "\n" .. now .. (cost and ("Next: " .. statText(potion.stats, rank + 1)) or "<font color=\"#6EDC6E\">Fully brewed!</font>"),
			Parent = row,
		})
		local soldOut = cost ~= nil and left <= 0
		local button = Theme.button(not cost and "MAX" or (soldOut and "Sold out" or (Util.formatNumber(cost) .. " 💰")), Color3.fromRGB(70, 140, 80), function()
			buy(id)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(150, 38), Parent = row })
		Theme.setButtonEnabled(button, cost ~= nil and not soldOut and p.gold >= cost)
		if cost then
			Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 48), Size = UDim2.fromOffset(150, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = soldOut and C.bad or C.good, Text = soldOut and "Out of stock" or string.format("%d in stock", left), Parent = row })
		end
	end
end

function Potions.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🧪 Bubbling Cauldron", Vector2.new(720, 560))
	close.Activated:Connect(function()
		App.Windows.close("Potions")
	end)
	goldLabel = Theme.label({ Size = UDim2.new(1, -170, 0, 26), TextSize = 14, Text = "", Parent = content })
	Theme.button("🔄 Restock now (R$)", Color3.fromRGB(40, 150, 70), function()
		App.Store.buy("product", "Restock")
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(160, 26), TextSize = 13, Parent = content })
	list = Theme.scroll(content, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32) })
	Theme.list(list, 6)
	App.Windows.register("Potions", window, Potions.refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			if window.Visible and App.State.profile then
				goldLabel.Text = Potions.headerText(App.State.profile)
			end
		end
	end)
	App.State.changed:Connect(function()
		if window.Visible then
			Potions.refresh()
		end
	end)
end

return Potions
