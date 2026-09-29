-- Toasts, big announcements, floating damage numbers, zone titles and the death screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Theme)

local Notifications = {}
local App

local toastHolder
local announceFrame
local zoneFrame
local deathFrame
local announceToken = 0
local zoneToken = 0
local TOAST_SECONDS = 9
local TOAST_TOP = 250 -- left side, well below the player card (HUD coordinates)

-- In-battle numbers: white = your hit, yellow = critical hit, red = damage you took,
-- blue = a dodge (yours) or a miss (the other dragon dodged you).
local NUMBER_STYLES = {
	hit = { color = Color3.fromRGB(255, 255, 255), size = 28 },
	crit = { color = Color3.fromRGB(255, 215, 50), size = 40, suffix = "!", tag = "CRIT!" },
	taken = { color = Color3.fromRGB(255, 80, 80), size = 28, prefix = "-" },
	dodge = { color = Color3.fromRGB(120, 210, 255), size = 30, text = "DODGE!" },
	miss = { color = Color3.fromRGB(170, 200, 230), size = 26, text = "MISS" },
	poison = { color = Color3.fromRGB(130, 230, 80), size = 22 },
	burn = { color = Color3.fromRGB(255, 150, 50), size = 22 },
	thorns = { color = Color3.fromRGB(200, 120, 255), size = 22 },
	gold = { color = Color3.fromRGB(255, 210, 60), size = 22, prefix = "+", suffix = " 💰" },
	target = { color = Color3.fromRGB(255, 225, 90), size = 32, prefix = "+", suffix = " 🎯" },
}

function Notifications.toast(text: string, color: Color3?, icon: string?)
	local frame = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = -math.floor(os.clock() * 1000),
		Parent = toastHolder,
	})
	Theme.corner(frame, 8)
	Theme.stroke(frame, color or Theme.Colors.accent, 1.5, 0.2)
	Theme.pad(frame, 8)
	local label = Theme.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		TextColor3 = color or Theme.Colors.text,
		Text = (icon and (icon .. "  ") or "") .. text,
		Parent = frame,
	})
	-- keep at most 6 (3 on phones)
	local items = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = (App.Windows.mobile and 3 or 6), #items do
		items[i]:Destroy()
	end
	task.delay(TOAST_SECONDS, function()
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			task.wait(0.5)
			frame:Destroy()
		end
	end)
end

-- Push the toast column down so it never covers something above it (the tutorial panel).
function Notifications.setTopInset(bottomOfAbove: number?)
	if App.Windows.mobile then
		return -- phones keep toasts at the top center, under the bars
	end
	toastHolder.Position = UDim2.fromOffset(12, math.max(TOAST_TOP, (bottomOfAbove or 0) + 10))
end

function Notifications.announce(data)
	announceToken += 1
	local token = announceToken
	announceFrame.Title.Text = data.title or ""
	announceFrame.Title.TextColor3 = data.color or Theme.Colors.accent
	announceFrame.Body.Text = data.text or ""
	announceFrame.Visible = true
	announceFrame.Title.TextTransparency = 0
	announceFrame.Body.TextTransparency = 0
	announceFrame.Position = UDim2.new(0.5, 0, 0.2, -20)
	TweenService:Create(announceFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0.2, 0) }):Play()
	if data.sound == "horn" then
		App.Sfx.play("Horn", 0.8)
	elseif data.title == "LEVEL UP!" then
		App.Sfx.play("LevelUp")
	end
	task.delay(data.duration or 4, function()
		if token ~= announceToken then
			return
		end
		TweenService:Create(announceFrame.Title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		TweenService:Create(announceFrame.Body, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		task.wait(0.6)
		if token == announceToken then
			announceFrame.Visible = false
		end
	end)
end

function Notifications.damageNumbers(list)
	for _, entry in ipairs(list) do
		local style = NUMBER_STYLES[entry.kind] or NUMBER_STYLES.hit
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = entry.pos + Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
		attachment.Parent = workspace.Terrain
		local gui = Instance.new("BillboardGui")
		gui.Name = "DamageNumber"
		gui.Adornee = attachment
		gui.Size = UDim2.fromOffset(160, 70)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 200
		local text = style.text or ((style.prefix or "") .. Util.formatNumber(entry.amount) .. (style.suffix or ""))
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 1)
		label.Size = UDim2.new(1, 0, 0, 44)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = math.floor(style.size * 1.5)
		label.TextColor3 = style.color
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = gui
		local tag
		if style.tag then
			tag = Instance.new("TextLabel")
			tag.BackgroundTransparency = 1
			tag.AnchorPoint = Vector2.new(0.5, 1)
			tag.Position = UDim2.new(0.5, 0, 1, -40)
			tag.Size = UDim2.new(1, 0, 0, 22)
			tag.Font = Enum.Font.FredokaOne
			tag.TextSize = 20
			tag.TextColor3 = Color3.fromRGB(255, 150, 40)
			tag.TextStrokeTransparency = 0
			tag.Text = style.tag
			tag.Parent = gui
		end
		-- directly under PlayerGui (not in a folder) so it always renders
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		-- pop in big, settle, then float up and fade
		TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = style.size }):Play()
		TweenService:Create(gui, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 5, 0) }):Play()
		task.delay(0.5, function()
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			if tag then
				TweenService:Create(tag, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
		task.delay(1.15, function()
			gui:Destroy()
			attachment:Destroy()
		end)
		if entry.kind == "gold" then
			App.Sfx.play("Coin", 0.4)
		elseif entry.kind == "hit" or entry.kind == "crit" then
			App.Sfx.play("Hit", 0.35)
		end
	end
end

function Notifications.zoneTitle(zoneId: string)
	local area = Zones.getArea(zoneId)
	if not area then
		return
	end
	zoneToken += 1
	local token = zoneToken
	zoneFrame.Name_.Text = area.name
	zoneFrame.Name_.TextColor3 = area.color or Theme.Colors.accent
	zoneFrame.Sub.Text = area.subtitle or ""
	zoneFrame.Visible = true
	zoneFrame.Name_.TextTransparency = 1
	zoneFrame.Sub.TextTransparency = 1
	TweenService:Create(zoneFrame.Name_, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	TweenService:Create(zoneFrame.Sub, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.delay(3, function()
		if token ~= zoneToken then
			return
		end
		TweenService:Create(zoneFrame.Name_, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		TweenService:Create(zoneFrame.Sub, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
	end)
end

function Notifications.death(seconds: number)
	deathFrame.Visible = true
	deathFrame.BackgroundTransparency = 1
	TweenService:Create(deathFrame, TweenInfo.new(0.6), { BackgroundTransparency = 0.45 }):Play()
	task.spawn(function()
		for s = math.ceil(seconds), 1, -1 do
			deathFrame.Info.Text = string.format("Respawning in %d...", s)
			task.wait(1)
		end
		deathFrame.Visible = false
	end)
end

function Notifications.init(app)
	app.Windows.toast = Notifications.toast
	App = app
	local overlay = App.Windows.guis.Overlay
	local top = App.Windows.guis.Top

	-- Toasts live in the HUD layer: windows open on top of them, never the other way around.
	toastHolder = Theme.make("Frame", {
		Name = "Toasts",
		Position = UDim2.fromOffset(12, TOAST_TOP),
		Size = UDim2.fromOffset(330, 300),
		BackgroundTransparency = 1,
		Parent = App.Windows.guis.HUD,
	})
	Theme.list(toastHolder, 6)
	if App.Windows.mobile then
		toastHolder.AnchorPoint = Vector2.new(0.5, 0)
		toastHolder.Position = UDim2.new(0.5, 0, 0, 104)
		toastHolder.Size = UDim2.fromOffset(380, 200)
	end

	announceFrame = Theme.make("Frame", {
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(760, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = top,
	})
	Theme.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 56),
		Font = Theme.Fonts.title,
		TextSize = 48,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		Parent = announceFrame,
	})
	Theme.label({
		Name = "Body",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 50),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = announceFrame,
	})

	zoneFrame = Theme.make("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(600, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = overlay,
	})
	Theme.label({
		Name = "Name_",
		Size = UDim2.new(1, 0, 0, 44),
		Font = Theme.Fonts.title,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = zoneFrame,
	})
	Theme.label({
		Name = "Sub",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.subtext,
		TextStrokeTransparency = 0.4,
		Parent = zoneFrame,
	})

	deathFrame = Theme.make("Frame", {
		Name = "Death",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(40, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 5,
		Parent = overlay,
	})
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 70),
		Font = Theme.Fonts.title,
		TextSize = 56,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 120, 110),
		Text = "You were defeated!",
		ZIndex = 6,
		Parent = deathFrame,
	})
	Theme.label({
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(500, 36),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Parent = deathFrame,
	})


	Remotes.event("Notify").OnClientEvent:Connect(function(data)
		Notifications.toast(data.text, data.color, data.icon)
		if data.icon == "📜" or data.icon == "🏆" then
			App.Sfx.play("Quest")
		elseif data.icon == "✨" then
			App.Sfx.play("Loot")
		end
	end)
	Remotes.event("Announce").OnClientEvent:Connect(Notifications.announce)
	Remotes.event("DamageNumber").OnClientEvent:Connect(Notifications.damageNumbers)
	Remotes.event("ZoneChanged").OnClientEvent:Connect(Notifications.zoneTitle)
	Remotes.event("Died").OnClientEvent:Connect(Notifications.death)
end

return Notifications
