-- The night raid bar (RaidService): longships incoming, raiders left, the wave, burned houses and
-- time until dawn, with a button to fly home to town. After a lost raid it counts down until the
-- shops reopen. Everything comes from workspace attributes, so late joiners see it too.
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

local bar, title, info, homeButton, stroke
local accumulated = 0

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
		return
	end
	local hud = App.Windows.guis.HUD
	local boss = hud:FindFirstChild("BossBanner")
	local pill = hud:FindFirstChild("BossPill")
	local y = 8
	if boss and boss.Visible then
		y = 112
	elseif pill and pill.Visible then
		y = 48
	end
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, y)
	bar.Size = UDim2.fromOffset(500, 58)
end

function RaidUI.update()
	local phase = workspace:GetAttribute("RaidPhase")
	local now = workspace:GetServerTimeNow()
	local closedUntil = workspace:GetAttribute("ShopsClosedUntil")
	if phase == "incoming" then
		title.Text = "⚔️ Longships on the river!"
		info.Text = string.format("Vikings land below town in <b>%s</b>. Defend Dragon Town!", Util.formatTime((workspace:GetAttribute("RaidLandsAt") or now) - now))
	elseif phase == "fighting" then
		local left = workspace:GetAttribute("RaidLeft") or 0
		title.Text = "⚔️ Viking raid!"
		info.Text = string.format("<b>%d</b> raider%s left  •  wave %d/%d  •  🏚️ %d/%d  •  dawn in %s",
			left, left == 1 and "" or "s",
			workspace:GetAttribute("RaidWave") or 1, workspace:GetAttribute("RaidWaves") or 1,
			workspace:GetAttribute("HousesBurned") or 0, workspace:GetAttribute("RaidMaxBurned") or 5,
			Util.formatTime((workspace:GetAttribute("RaidEndsAt") or now) - now))
	elseif closedUntil and closedUntil > now then
		title.Text = "🔒 The market was looted"
		info.Text = string.format("The shops reopen in <b>%s</b>.", Util.formatTime(closedUntil - now))
	else
		bar.Visible = false
		return
	end
	local raiding = phase ~= nil
	bar.Visible = true
	stroke.Color = raiding and RAID_COLOR or CLOSED_COLOR
	title.TextColor3 = raiding and RAID_COLOR or CLOSED_COLOR
	homeButton.Visible = raiding and not inTown()
	title.Size = UDim2.new(1, homeButton.Visible and -120 or -20, 0, 24)
	info.Size = UDim2.new(1, homeButton.Visible and -120 or -20, 0, 22)
	place()
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
		Size = UDim2.new(1, -20, 0, 24),
		Font = Theme.Fonts.title,
		TextSize = 19,
		TextColor3 = RAID_COLOR,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	info = Theme.label({
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -20, 0, 22),
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
