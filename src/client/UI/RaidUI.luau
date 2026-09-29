-- The night raid bar (RaidService): longships incoming, raiders left, the wave, burned houses and
-- time until dawn, with a button to fly home to town. After a lost raid it counts down until the
-- shops reopen. Everything comes from workspace attributes, so late joiners see it too. It can
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

local bar, title, info, homeButton, stroke, pill
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

function RaidUI.update()
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
		info.Text = string.format("Vikings land below town in <b>%s</b>. Defend Dragon Town!", lands)
		short = "⚔️ Raid lands in " .. lands
	elseif phase == "fighting" then
		local left = workspace:GetAttribute("RaidLeft") or 0
		local dawn = Util.formatTime((workspace:GetAttribute("RaidEndsAt") or now) - now)
		title.Text = "⚔️ Viking raid!"
		info.Text = string.format("<b>%d</b> raider%s left  •  wave %d/%d  •  🏚️ %d/%d  •  dawn in %s",
			left, left == 1 and "" or "s",
			workspace:GetAttribute("RaidWave") or 1, workspace:GetAttribute("RaidWaves") or 1,
			workspace:GetAttribute("HousesBurned") or 0, workspace:GetAttribute("RaidMaxBurned") or 5,
			dawn)
		short = string.format("⚔️ Raid: %d left  •  dawn %s", left, dawn)
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
