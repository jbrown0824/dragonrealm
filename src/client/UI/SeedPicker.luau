-- Pick which seed to plant when you use an empty planting spot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seeds = require(Shared.Config.Seeds)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local SeedPicker = {}
local App

local window, list, titleLabel
local plotIndex = nil

local function refresh()
	local p = App.State.profile
	if not p then
		return
	end
	titleLabel.Text = "🌱 Plant in Spot " .. tostring(plotIndex or "?")
	Theme.clear(list)
	for i, seedId in ipairs(Seeds.Order) do
		local count = p.seeds[seedId] or 0
		if count > 0 then
			local seed = Seeds[seedId]
			local row = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 70), BackgroundColor3 = C.panel2, LayoutOrder = i, Parent = list })
			Theme.corner(row, 8)
			Theme.pad(row, 8)
			Theme.label({ Size = UDim2.new(1, -120, 0, 22), Font = Theme.Fonts.title, TextSize = 20, TextColor3 = seed.bloom, Text = string.format("%s  x%d", seed.name, count), Parent = row })
			Theme.label({
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, -120, 0, 30),
				TextSize = 12,
				Font = Theme.Fonts.body,
				TextColor3 = C.subtext,
				Text = string.format("%s • ~%s to bloom • thirsty %d× per stage • full bloom ~%d gold", seed.rarity, Util.formatTime(seed.stageTime * 3), seed.needsPerStage, seed.value),
				Parent = row,
			})
			Theme.button("Plant", Color3.fromRGB(60, 140, 70), function()
				local target = plotIndex
				App.Windows.close("SeedPicker")
				task.spawn(function()
					local ok, err = Remotes.func("PlantSeed"):InvokeServer(target, seedId)
					if not ok then
						App.Notifications.toast(err or "Couldn't plant there.", C.bad, "🌱")
					else
						App.Notifications.toast("Planted " .. seed.name .. "! Water it [R] when it gets thirsty 💧.", seed.bloom, "🌱")
					end
				end)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(100, 40), Parent = row })
		end
	end
end

function SeedPicker.init(app)
	App = app
	local content, close, titleBar
	window, content, close, titleBar = Theme.window(App.Windows.guis.Windows, "Plant a Seed", Vector2.new(560, 440))
	titleLabel = titleBar.Title
	close.Activated:Connect(function()
		App.Windows.close("SeedPicker")
	end)
	Theme.label({
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 13,
		TextColor3 = C.subtext,
		Text = "Plants grow Seed → Seedling → Sprout → Flower. Water them [R] when they get thirsty 💧 (a missed drink lowers their quality). Harvest [E] anytime: bigger plants are worth more, and flowers give seeds back!",
		Parent = content,
	})
	list = Theme.scroll(content, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	Theme.list(list, 6)
	App.Windows.register("SeedPicker", window, function(index)
		plotIndex = index
		refresh()
	end)
	Remotes.event("OpenSeedPicker").OnClientEvent:Connect(function(index)
		App.Windows.open("SeedPicker", index)
	end)
end

return SeedPicker
