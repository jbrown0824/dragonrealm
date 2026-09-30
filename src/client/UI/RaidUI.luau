-- The night raid bar (RaidService): longships incoming, raiders left, the wave, burned houses and
-- the time left to beat them, with a button to fly home to town. After a lost raid it counts down
-- until the shops reopen. Under it, while a house burns or you carry water, a chip says how many
-- splashes you have or where to get water. Everything comes from workspace attributes, so late joiners see it too. It can
-- be minimized to a small pill (click the pill to open it again; a new raid opens it by itself).
-- Desktop: top center (under the boss banner when that's up). Phones: bottom left of center,
-- clear of the bars at the top and the thumb buttons on the right.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local RaidUI = {}
local App

local bar, title, info, homeButton, stroke, pill, waterChip
local accumulated = 0
local minimized = false
local lastPhase = nil

local RAID_COLOR = Color3.fromRGB(255, 110, 70)
local CLOSED_COLOR = Color3.fromRGB(255, 190, 90)

local function inTown(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and Zones.isIn("Town", root.Position)
end

local function place()
	if App.Windows.mobile then
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 130, 1, -8)
		bar.Size = UDim2.fromOffset(372, 58)
		pill.AnchorPoint = Vector2.new(0, 1)
		pill.Position = UDim2.new(0, 130, 1, -8)
		return
	end
	local hud = App.Windows.guis.HUD
	local boss = hud:FindFirstChild("BossBanner")
	local bossPill = hud:FindFirstChild("BossPill")
	local y = 8
	if boss and boss.Visible then
		y = 112
	elseif bossPill and bossPill.Visible then
		y = 48
	end
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, y)
	bar.Size = UDim2.fromOffset(500, 58)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, y)
end

function RaidUI.setMinimized(on: boolean)
	minimized = on
	RaidUI.update()
end

local function burningHouses(): number
	local town = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Town")
	local n = 0
	if town then
		for _, child in ipairs(town:GetChildren()) do
			if child:GetAttribute("Fire") == "burning" then
				n += 1
			end
		end
	end
	return n
end

-- The water chip: under the raid bar (or its pill) on desktop, above it on phones.
local function updateWater()
	local water = Players.LocalPlayer:GetAttribute("Water") or 0
	local fires = burningHouses()
	waterChip.Visible = water > 0 or fires > 0
	if not waterChip.Visible then
		return
	end
	if water > 0 then
		waterChip.Text = string.format("💧 %d splash%s of water: fly over a burning house!", water, water == 1 and "" or "es")
		waterChip.BackgroundColor3 = Color3.fromRGB(20, 60, 110)
	else
		waterChip.Text = string.format("🔥 %d house%s on fire! Dive into the river or a well for water", fires, fires == 1 and "" or "s")
		waterChip.BackgroundColor3 = Color3.fromRGB(90, 30, 15)
	end
	local above = (bar.Visible and bar) or (pill.Visible and pill) or nil
	if App.Windows.mobile then
		waterChip.AnchorPoint = Vector2.new(0, 1)
		waterChip.Size = UDim2.fromOffset(372, 28)
		waterChip.Position = UDim2.new(0, 130, 1, above and -(14 + above.Size.Y.Offset) or -8)
	else
		waterChip.AnchorPoint = Vector2.new(0.5, 0)
		waterChip.Size = UDim2.fromOffset(420, 28)
		local y = above and (above.Position.Y.Offset + above.Size.Y.Offset + 6) or 8
		waterChip.Position = UDim2.new(0.5, 0, 0, y)
	end
end

function RaidUI.update()
	RaidUI.updateBar()
	updateWater()
end

function RaidUI.updateBar()
	local phase = workspace:GetAttribute("RaidPhase")
	local now = workspace:GetServerTimeNow()
	local closedUntil = workspace:GetAttribute("ShopsClosedUntil")
	if phase == "incoming" and lastPhase ~= "incoming" then
		minimized = false -- a new raid: show it
	end
	lastPhase = phase
	local short
	if phase == "incoming" then
		local lands = Util.formatTime((workspace:GetAttribute("RaidLandsAt") or now) - now)
		title.Text = "⚔️ Longships on the river!"
		info.Text = string.format("Vikings land below town in <b>%s</b>. Fly out and fight them on their ships!", lands)
		short = "⚔️ Raid lands in " .. lands
	elseif phase == "fighting" then
		local left = workspace:GetAttribute("RaidLeft") or 0
		local clock = Util.formatTime(math.max(0, (workspace:GetAttribute("RaidEndsAt") or now) - now))
		local wave = workspace:GetAttribute("RaidWave") or 1
		local nextAt = workspace:GetAttribute("RaidNextWaveAt")
		local waveText = nextAt and string.format("wave %d in %s", wave + 1, Util.formatTime(nextAt - now))
			or string.format("wave %d/%d", wave, workspace:GetAttribute("RaidWaves") or 1)
		title.Text = "⚔️ Viking raid!"
		info.Text = string.format("<b>%d</b> raider%s left  •  %s  •  🏚️ %d/%d  •  ⏳ %s",
			left, left == 1 and "" or "s", waveText,
			workspace:GetAttribute("HousesBurned") or 0, workspace:GetAttribute("RaidMaxBurned") or 5,
			clock)
		short = string.format("⚔️ Raid: %d left  •  ⏳ %s", left, clock)
	elseif closedUntil and closedUntil > now then
		local open = Util.formatTime(closedUntil - now)
		title.Text = "🔒 The market was looted"
		info.Text = string.format("The shops reopen in <b>%s</b>.", open)
		short = "🔒 Shops open in " .. open
	else
		bar.Visible = false
		pill.Visible = false
		return
	end
	local raiding = phase ~= nil
	place()
	pill.Visible = minimized
	pill.Text = short .. "  (open)"
	bar.Visible = not minimized
	if minimized then
		return
	end
	stroke.Color = raiding and RAID_COLOR or CLOSED_COLOR
	title.TextColor3 = raiding and RAID_COLOR or CLOSED_COLOR
	homeButton.Visible = raiding and not inTown()
	title.Size = UDim2.new(1, homeButton.Visible and -150 or -50, 0, 24)
	info.Size = UDim2.new(1, homeButton.Visible and -150 or -50, 0, 22)
	homeButton.Position = UDim2.new(1, -40, 0.5, 0)
end

function RaidUI.init(app)
	App = app
	bar = Theme.make("Frame", {
		Name = "RaidBar",
		BackgroundColor3 = Color3.fromRGB(40, 18, 16),
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(bar, 12)
	stroke = Theme.stroke(bar, RAID_COLOR, 2)
	title = Theme.label({
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -50, 0, 24),
		Font = Theme.Fonts.title,
		TextSize = 19,
		TextColor3 = RAID_COLOR,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	info = Theme.label({
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -50, 0, 22),
		TextSize = 13,
		RichText = true,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	homeButton = Theme.button("🏠 Fly home", C.blue, function()
		App.HUD.goHome()
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(100, 38),
		TextSize = 14,
		Visible = false,
		Parent = bar,
	})
	local hide = Theme.minimizeButton(function()
		RaidUI.setMinimized(true)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(28, 28), ZIndex = 3, Parent = bar })
	hide:FindFirstChildOfClass("Frame").ZIndex = 4
	pill = Theme.button("", Color3.fromRGB(60, 25, 22), function()
		RaidUI.setMinimized(false)
	end, {
		Name = "RaidPill",
		Size = UDim2.fromOffset(320, 32),
		TextSize = 14,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.stroke(pill, RAID_COLOR, 2)
	waterChip = Theme.label({
		Name = "WaterChip",
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(20, 60, 110),
		TextColor3 = Color3.fromRGB(215, 240, 255),
		TextSize = 14,
		Font = Theme.Fonts.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(waterChip, 10)
	Theme.stroke(waterChip, Color3.fromRGB(140, 200, 255), 1.5)
	place()
	RunService.RenderStepped:Connect(function(dt)
		accumulated += dt
		if accumulated >= 0.25 then
			accumulated = 0
			RaidUI.update()
		end
	end)
end

return RaidUI
