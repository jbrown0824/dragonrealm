-- The night raid bar (RaidService): longships incoming, raiders left, the wave, burned houses and
-- the time left to beat them, with a button to fly home to town. After a lost raid it counts down
-- until the shops reopen. Under it, while a house burns or you carry water, a chip says how many
-- splashes you have or where to get water. Everything comes from workspace attributes, so late
-- joiners see it too. It pops up big at the top when the longships are sighted, when they land and
-- when the shops close, then glides over to the side once you get going (SideDock: the left column
-- on computers, under the boss banner when that's up; the bottom-left stack on phones), the water
-- chip with it. It can be minimized to a small pill in the same spot (click the pill to open it
-- again; a new raid opens it by itself).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Raids = require(Shared.Config.Raids)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Theme)
local SideDock = require(script.Parent.SideDock)
local C = Theme.Colors

local RaidUI = {}
local App

local bar, title, info, homeButton, stroke, pill, waterChip, dock, chipDock
local accumulated = 0
local minimized = false
local lastPhase = nil
local lastShown = nil -- what the bar showed last: "incoming" | "fighting" | "closed" | nil

local RAID_COLOR = Color3.fromRGB(255, 110, 70)
local CLOSED_COLOR = Color3.fromRGB(255, 190, 90)

local function inTown(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and Zones.isIn("Town", root.Position)
end

local function inDungeon(): boolean
	return Players.LocalPlayer:GetAttribute("InDungeon") ~= nil
end

function RaidUI.setMinimized(on: boolean)
	minimized = on
	if not on then
		SideDock.raise(dock) -- (opened on purpose: it gets the room on a phone)
	end
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

-- The water chip: it rides with the raid bar (SideDock puts it under it). A gauge along its bottom
-- shows how much water you carry (it runs down as you pour).
local function updateWater()
	local water = Players.LocalPlayer:GetAttribute("Water") or 0
	local fires = burningHouses()
	local shown = water > 0 or fires > 0
	SideDock.show(chipDock, shown and "box" or nil)
	if not shown then
		return
	end
	local gauge = waterChip:FindFirstChild("Gauge")
	gauge.Visible = water > 0
	gauge.Fill.Size = UDim2.fromScale(math.clamp(water / Raids.WATER_LOADS, 0, 1), 1)
	if Players.LocalPlayer:GetAttribute("Pouring") then
		waterChip.Text = "💧 Pouring! Stay over the fire until it's out"
		waterChip.BackgroundColor3 = Color3.fromRGB(20, 80, 140)
	elseif water > 0 then
		waterChip.Text = "💧 Water! Hover over a burning house to pour it"
		waterChip.BackgroundColor3 = Color3.fromRGB(20, 60, 110)
	else
		waterChip.Text = string.format("🔥 %d house%s on fire! Dive into the river or a well for water", fires, fires == 1 and "" or "s")
		waterChip.BackgroundColor3 = Color3.fromRGB(90, 30, 15)
	end
end

function RaidUI.update()
	if inDungeon() then
		-- off in a dungeon: the raid (if any) shows again when you come back
		SideDock.show(dock, nil)
		SideDock.show(chipDock, nil)
		return
	end
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
	local showing = phase or ((closedUntil and closedUntil > now) and "closed" or nil)
	if showing and showing ~= lastShown then
		SideDock.pop(dock) -- longships sighted, the vikings landing, the shops closing: up top for a moment
	end
	lastShown = showing
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
		SideDock.show(dock, nil)
		return
	end
	local raiding = phase ~= nil
	SideDock.show(dock, minimized and "pill" or "box")
	pill.Text = short .. "  (open)"
	if minimized then
		return
	end
	stroke.Color = raiding and RAID_COLOR or CLOSED_COLOR
	title.TextColor3 = raiding and RAID_COLOR or CLOSED_COLOR
	homeButton.Visible = raiding and not inTown()
	bar.Size = UDim2.fromOffset(SideDock.WIDTH, homeButton.Visible and 104 or 70)
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
		Size = UDim2.new(1, -48, 0, 24),
		Font = Theme.Fonts.title,
		TextSize = 19,
		TextColor3 = RAID_COLOR,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	info = Theme.label({
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 0, 34),
		TextSize = 13,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd, -- (two lines at most)
		Parent = bar,
	})
	homeButton = Theme.button("🏠 Fly home to defend the town", C.blue, function()
		App.HUD.goHome()
	end, {
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 0, 28),
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
		Size = UDim2.fromOffset(SideDock.WIDTH, 32),
		TextSize = 14,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.stroke(pill, RAID_COLOR, 2)
	waterChip = Theme.label({
		Name = "WaterChip",
		Size = UDim2.fromOffset(SideDock.WIDTH, 44),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(20, 60, 110),
		TextColor3 = Color3.fromRGB(215, 240, 255),
		TextSize = 14,
		Font = Theme.Fonts.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, -- (two lines at most)
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 4), Parent = waterChip })
	Theme.corner(waterChip, 10)
	Theme.stroke(waterChip, Color3.fromRGB(140, 200, 255), 1.5)
	local gauge = Theme.make("Frame", {
		Name = "Gauge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = Color3.fromRGB(10, 25, 45),
		BorderSizePixel = 0,
		Visible = false,
		Parent = waterChip,
	})
	Theme.make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(120, 200, 255),
		BorderSizePixel = 0,
		Parent = gauge,
	})
	dock = SideDock.add(bar, { pill = pill })
	chipDock = SideDock.add(waterChip, { follow = dock })
	RunService.RenderStepped:Connect(function(dt)
		accumulated += dt
		if accumulated >= 0.25 then
			accumulated = 0
			RaidUI.update()
		end
	end)
end

return RaidUI
