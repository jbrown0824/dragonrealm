-- Lair Workshop (opened from the Bot Dock in your lair): buy the Drizzle-Bot that waters your
-- plants and the Reap-Bot that harvests (and later replants) them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Robots = {}
local App

local window, list
local busy = false

local function buy(kind: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, err = Remotes.func("BuyRobot"):InvokeServer(kind)
		busy = false
		if ok then
			App.Sfx.play("Coin")
			App.Windows.notify("Your new robot is warming up at the Bot Dock!", Color3.fromRGB(150, 230, 255), "🤖")
		else
			App.Windows.notify(err or "Couldn't buy that.", C.bad, "🤖")
		end
	end)
end

local function row(order: number, icon: string, title: string, body: string, owned: boolean, cost: number?, buttonText: string, onBuy)
	local p = App.State.profile
	local frame = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 96), BackgroundColor3 = C.panel2, LayoutOrder = order, Parent = list })
	Theme.corner(frame, 10)
	Theme.label({ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(64, 80), TextSize = 46, TextXAlignment = Enum.TextXAlignment.Center, Text = icon, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(80, 8), Size = UDim2.new(1, -260, 0, 24), Font = Theme.Fonts.title, TextSize = 20, TextColor3 = owned and C.good or C.accent, Text = title .. (owned and "  ✅" or ""), Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(80, 34), Size = UDim2.new(1, -260, 0, 56), TextSize = 13, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextYAlignment = Enum.TextYAlignment.Top, Text = body, Parent = frame })
	local button = Theme.button(cost and (buttonText .. "\n" .. Util.formatNumber(cost) .. " 💰") or buttonText, Color3.fromRGB(60, 120, 170), onBuy, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(160, 56),
		TextSize = 15,
		Parent = frame,
	})
	Theme.setButtonEnabled(button, cost ~= nil and p.gold >= cost)
	if cost then
		Theme.onDisabledClick(button, function()
			App.Store.needGold(cost)
		end)
	end
end

function Robots.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	Theme.clear(list)
	local robots = p.robots or {}
	local water = Game.ROBOTS.Water
	row(1, "💧", water.name, water.desc .. " It waits a moment before stepping in, so you can still water by hand.", robots.water == true, not robots.water and water.cost or nil, robots.water and "Owned" or "Buy", function()
		buy("Water")
	end)
	local harvest = Game.ROBOTS.Harvest
	local level = robots.harvest or 0
	local nextInfo = harvest.levels[level + 1]
	local desc
	if level == 0 then
		desc = harvest.levels[1].desc
	elseif nextInfo then
		desc = "Level 1: harvests full-bloom flowers for you.\n" .. nextInfo.desc
	else
		desc = "Level 2: harvests full-bloom flowers and replants the same seed. Your garden runs itself!"
	end
	row(2, "🌾", harvest.name .. (level > 0 and (" (Level " .. level .. ")") or ""), desc, level > 0, nextInfo and nextInfo.cost or nil, level == 0 and "Buy" or (nextInfo and "Upgrade to Lv 2" or "Maxed"), function()
		buy("Harvest")
	end)
	Theme.label({ Size = UDim2.new(1, -10, 0, 40), LayoutOrder = 3, TextSize = 12, TextColor3 = C.subtext, Text = "Robots only work while you're in the game (that's when your garden grows). They start and park at the Bot Dock.", Parent = list })
end

function Robots.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🤖 Lair Workshop", Vector2.new(640, 380))
	close.Activated:Connect(function()
		App.Windows.close("Robots")
	end)
	list = Theme.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Theme.list(list, 8)
	App.Windows.register("Robots", window, Robots.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Robots.refresh()
		end
	end)
end

return Robots
