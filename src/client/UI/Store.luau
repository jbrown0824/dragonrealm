-- The 💎 Store window (Robux): the Starter Pack (for new dragons), game passes, gold packs sized
-- to your level, the Secret Egg and a few extras. Buying opens Roblox's own purchase prompt;
-- StoreService grants the item when Roblox confirms. Items without an id yet (see Config/Store)
-- can be tested for free in Studio.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreInfo = require(Shared.Config.Store)
local PetInfo = require(Shared.Config.Pets)
local StatCalc = require(Shared.StatCalc)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Store = {}
local App

local window, list
local focus = nil -- scroll to this product when opening
local ROBUX_GREEN = Color3.fromRGB(40, 150, 70)

local function statText(stats): string
	local parts = {}
	for stat, v in pairs(stats) do
		local info = StatCalc.STAT_INFO[stat]
		table.insert(parts, string.format("+%s%% %s", Util.fmt(v), info and info.label or stat))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- Start a purchase: Roblox's prompt when the item has an id, the Studio test grant otherwise.
function Store.buy(kind: string, key: string)
	local info = kind == "pass" and StoreInfo.Passes[key] or StoreInfo.Products[key]
	if not info then
		return
	end
	local id = kind == "pass" and info.assetId or info.productId
	if id and id ~= 0 then
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
		end
		return
	end
	task.spawn(function()
		local ok, message = Remotes.func("StudioPurchase"):InvokeServer(kind, key)
		App.Windows.notify(message or (ok and "Done!" or "Couldn't buy that."), ok and C.good or C.bad, "💎")
	end)
end

local function section(order: number, title: string)
	Theme.label({ Size = UDim2.new(1, -10, 0, 26), Font = Theme.Fonts.title, TextSize = 20, TextColor3 = C.accent, LayoutOrder = order, Text = title, Parent = list })
end

-- One store card. `extra` is optional detail text under the description.
local function card(order: number, icon: string, name: string, desc: string, extra: string?, price: number, owned: boolean, onBuy, height: number?)
	local frame = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, height or 84), BackgroundColor3 = C.panel2, LayoutOrder = order, Parent = list })
	Theme.corner(frame, 10)
	Theme.stroke(frame, owned and C.good or Color3.fromRGB(90, 200, 120), 1.5, 0.4)
	Theme.label({ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(60, 64), TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Text = icon, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(76, 8), Size = UDim2.new(1, -250, 0, 24), Font = Theme.Fonts.title, TextSize = 20, Text = name, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(76, 34), Size = UDim2.new(1, -250, 1, -40), TextSize = 13, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextYAlignment = Enum.TextYAlignment.Top,
		Text = desc .. (extra and ("\n" .. extra) or ""), Parent = frame })
	local button = Theme.button(owned and "✅ Owned" or ("R$ " .. price), ROBUX_GREEN, onBuy, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(150, 46),
		TextSize = 20,
		Font = Theme.Fonts.title,
		Parent = frame,
	})
	Theme.setButtonEnabled(button, not owned)
	return frame
end

function Store.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	Theme.clear(list)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local products = StoreInfo.Products
	local gold = p.goldPackAmounts or {}

	if not p.starterPack and p.level < StoreInfo.STARTER_MAX_LEVEL then
		section(nextOrder(), "🎁 Just for new dragons")
		local starter = products.StarterPack
		local frame = card(nextOrder(), starter.icon, starter.name, starter.desc,
			string.format("<font color=\"#FFD24A\">Right now: %s gold + everything above.</font> Only until level %d!", Util.formatNumber(gold.StarterPack or 0), StoreInfo.STARTER_MAX_LEVEL),
			starter.robux, false, function()
				Store.buy("product", "StarterPack")
			end, 100)
		frame.UIStroke.Color = Color3.fromRGB(255, 200, 80)
		frame.UIStroke.Thickness = 3
	end

	section(nextOrder(), "⚡ Boosts (forever)")
	for _, key in ipairs(StoreInfo.PassOrder) do
		local pass = StoreInfo.Passes[key]
		card(nextOrder(), pass.icon, pass.name, pass.desc, nil, pass.robux, p.passes and p.passes[key] == true, function()
			Store.buy("pass", key)
		end)
	end

	section(nextOrder(), "💰 Gold (sized to your level)")
	for _, key in ipairs({ "GoldSmall", "GoldMedium", "GoldLarge" }) do
		local product = products[key]
		card(nextOrder(), product.icon, string.format("%s: %s gold", product.name, Util.formatNumber(gold[key] or 0)), product.desc, nil, product.robux, false, function()
			Store.buy("product", key)
		end)
	end

	section(nextOrder(), "🔮 Secret nano dragons")
	local secret = products.SecretEgg
	local lines = {}
	for _, id in ipairs(PetInfo.speciesOfRarity("Secret")) do
		local species = PetInfo.get(id)
		table.insert(lines, string.format("<font color=\"%s\">%s</font>: %s", Theme.colorHex(PetInfo.RarityColors.Secret), species.name, statText(species.stats)))
	end
	card(nextOrder(), secret.icon, secret.name, secret.desc, table.concat(lines, "\n"), secret.robux, false, function()
		Store.buy("product", "SecretEgg")
	end, 124)

	section(nextOrder(), "✨ Extras")
	for _, key in ipairs({ "TreatBag", "Restock" }) do
		local product = products[key]
		card(nextOrder(), product.icon, product.name, product.desc, nil, product.robux, false, function()
			Store.buy("product", key)
		end)
	end
	Theme.label({ Size = UDim2.new(1, -10, 0, 40), LayoutOrder = nextOrder(), TextSize = 12, TextColor3 = C.subtext,
		Text = "Purchases are made with Robux through Roblox. Ask a grown-up before buying anything!", Parent = list })

	if focus then
		list.CanvasPosition = Vector2.zero
		focus = nil
	end
end

function Store.open(productKey: string?)
	focus = productKey
	App.Windows.open("Store")
end

function Store.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "💎 Store", Vector2.new(760, 580))
	close.Activated:Connect(function()
		App.Windows.close("Store")
	end)
	list = Theme.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Theme.list(list, 8)
	App.Windows.register("Store", window, Store.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Store.refresh()
		end
	end)
	-- a finished purchase refreshes the window once the server has granted it
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
		task.wait(1)
		if window.Visible then
			Store.refresh()
		end
	end)
end

return Store
