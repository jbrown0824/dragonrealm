-- The 💎 Store window (Robux): the Starter Pack (for new dragons), boosts (a cheap Gold Rush and
-- the 2x passes), handy passes (flight time, never hungry, Wayfinder teleports), gold packs sized
-- to your level, the Mythic and Secret Eggs and a few extras. Buying
-- opens Roblox's own purchase prompt; StoreService grants the item when Roblox confirms. Items
-- without an id yet (see Config/Store) can be tested for free in Studio.
--
-- The game never pops the Store open by itself. The only nudges are the Starter Pack button on
-- the HUD (new dragons) and, when you click to buy something you can't afford, a "Get gold"
-- button in that window's message (Store.needGold), which opens the Store at the gold packs.

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
local focus = nil -- how the Store was opened: "Gold" (from a Get gold button) puts the gold packs first
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

-- Time left on a Gold Rush, or nil.
local function goldRushLeft(p): number?
	local ends = p.goldRushEnds
	local left = ends and ends - workspace:GetServerTimeNow()
	return left and left > 0 and left or nil
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

	local function starterSection()
		if p.starterPack or p.level >= StoreInfo.STARTER_MAX_LEVEL then
			return
		end
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

	-- the forever passes: the 2x boosts, or the handy ones
	local function passCards(handy: boolean)
		for _, key in ipairs(StoreInfo.PassOrder) do
			local pass = StoreInfo.Passes[key]
			if (pass.handy == true) == handy then
				card(nextOrder(), pass.icon, pass.name .. (handy and "" or " (forever)"), pass.desc, nil, pass.robux, p.passes and p.passes[key] == true, function()
					Store.buy("pass", key)
				end)
			end
		end
	end

	local function boostSection()
		section(nextOrder(), "⚡ Boosts")
		local rush = products.GoldRush
		local left = goldRushLeft(p)
		local rushCard = card(nextOrder(), rush.icon, rush.name, rush.desc,
			left and string.format("<font color=\"#6EDC6E\">Active: %s of play left.</font>", Util.formatTime(left)) or nil,
			rush.robux, false, function()
				Store.buy("product", "GoldRush")
			end, left and 100 or nil)
		if focus == "GoldRush" then
			rushCard.UIStroke.Color = C.gold
			rushCard.UIStroke.Thickness = 2.5
		end
		passCards(false)
	end

	local function handySection()
		section(nextOrder(), "🧰 Handy (forever)")
		passCards(true)
	end

	local function goldSection()
		section(nextOrder(), "💰 Gold")
		for _, key in ipairs({ "GoldSmall", "GoldMedium", "GoldLarge" }) do
			local product = products[key]
			local frame = card(nextOrder(), product.icon, string.format("%s: %s gold", product.name, Util.formatNumber(gold[key] or 0)), product.desc, nil, product.robux, false, function()
				Store.buy("product", key)
			end)
			if focus == "Gold" then
				frame.UIStroke.Color = C.gold
				frame.UIStroke.Thickness = 2.5
			end
		end
	end

	local function eggSection()
		section(nextOrder(), "🥚 Eggs")
		local mythic = products.MythicEgg
		local odds = {}
		local egg = PetInfo.Eggs.MythicEgg
		for _, rarity in ipairs(PetInfo.RarityOrder) do
			if egg.weights[rarity] then
				table.insert(odds, string.format("<font color=\"%s\">%s %d%%</font>", Theme.colorHex(PetInfo.RarityColors[rarity]), rarity, egg.weights[rarity]))
			end
		end
		card(nextOrder(), mythic.icon, mythic.name, mythic.desc, table.concat(odds, "   "), mythic.robux, false, function()
			Store.buy("product", "MythicEgg")
		end, 100)
		local secret = products.SecretEgg
		local lines = {}
		for _, id in ipairs(PetInfo.speciesFor("SecretEgg", "Secret")) do
			local species = PetInfo.get(id)
			table.insert(lines, string.format("<font color=\"%s\">%s</font>: %s", Theme.colorHex(PetInfo.RarityColors.Secret), species.name, statText(species.stats)))
		end
		card(nextOrder(), secret.icon, secret.name, secret.desc, table.concat(lines, "\n"), secret.robux, false, function()
			Store.buy("product", "SecretEgg")
		end, 124)
	end

	local function extrasSection()
		section(nextOrder(), "✨ Extras")
		for _, key in ipairs({ "TreatBag", "Restock" }) do
			local product = products[key]
			card(nextOrder(), product.icon, product.name, product.desc, nil, product.robux, false, function()
				Store.buy("product", key)
			end)
		end
	end

	-- opened from a "Get gold" button: the gold first
	local sections = focus == "Gold" and { goldSection, boostSection, starterSection, eggSection, handySection, extrasSection }
		or { starterSection, boostSection, goldSection, eggSection, handySection, extrasSection }
	for _, build in ipairs(sections) do
		build()
	end
	Theme.label({ Size = UDim2.new(1, -10, 0, 40), LayoutOrder = nextOrder(), TextSize = 12, TextColor3 = C.subtext,
		Text = "Purchases are made with Robux through Roblox. Ask a grown-up before buying anything!", Parent = list })
end

-- Open the Store. `productKey` "Gold" puts the gold packs first; "GoldRush" outlines the Gold Rush.
function Store.open(productKey: string?)
	focus = productKey
	App.Windows.open("Store")
	list.CanvasPosition = Vector2.zero
end

-- A click on a buy button you can't afford: how much gold is missing, and a button to the gold
-- packs. The Store only opens if they click it.
function Store.needGold(cost: number)
	local p = App.State.profile
	local short = cost - (p and p.gold or 0)
	if short <= 0 then
		return
	end
	App.Windows.notify(string.format("You need %s more gold.", Util.formatNumber(short)), C.gold, "💰", {
		text = "💎 Get gold",
		color = ROBUX_GREEN,
		onClick = function()
			Store.open("Gold")
		end,
	})
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
	App.Windows.register("Store", window, Store.refresh, function()
		focus = nil
	end)
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
