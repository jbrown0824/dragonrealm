-- Target practice (RangeService). The window at a lane's firing mat (pick a level or AFK
-- practice), the session panel while you shoot (targets hit, time left, Stop), and the targets
-- themselves: this client moves every PracticeTarget from its attributes (shared/RangeUtil), so
-- they glide smoothly with nothing streamed. In AFK mode it also aims and fires for you.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RangeInfo = require(Shared.Config.Range)
local RangeUtil = require(Shared.RangeUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Range = {}
local App

local window, list
local panel, panelTitle, panelInfo
local session = nil -- the latest RangeState while practicing
local params = {} -- [Model] = RangeUtil params, read once from the attributes
local busy = false
local nextAuto = 0

local player = Players.LocalPlayer

local function levelXpText(def): string
	return string.format("+%d%% of a level", math.floor(def.xp * 100 + 0.5))
end

local function send(action: string, level: number?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, err = Remotes.func("RangeAction"):InvokeServer(action, level)
		busy = false
		if ok then
			if action ~= "stop" then
				App.Windows.close("Range")
				App.Sfx.play("Click")
			end
		else
			App.Windows.notify(err or "Couldn't start.", C.bad, "🎯")
		end
	end)
end

local function row(order: number, icon: string, title: string, body: string, titleColor: Color3, buttonText: string, buttonColor: Color3, enabled: boolean, onClick)
	local frame = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 58), BackgroundColor3 = C.panel2, LayoutOrder = order, Parent = list })
	Theme.corner(frame, 10)
	Theme.label({ Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(50, 50), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Text = icon, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(60, 6), Size = UDim2.new(1, -200, 0, 22), Font = Theme.Fonts.title, TextSize = 18, TextColor3 = titleColor, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = title, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(60, 30), Size = UDim2.new(1, -200, 0, 22), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = body, Parent = frame })
	local button = Theme.button(buttonText, buttonColor, onClick, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(120, 40),
		TextSize = 15,
		Parent = frame,
	})
	Theme.setButtonEnabled(button, enabled)
end

function Range.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	Theme.clear(list)
	local best = p.rangeLevel or 0
	Theme.label({
		Size = UDim2.new(1, -10, 0, 34),
		LayoutOrder = 0,
		TextSize = 13,
		TextColor3 = C.subtext,
		Text = string.format("Stand on a firing mat. <b>Left click or Q</b> fires Fireball (%.1fs cooldown); other abilities rest while you practice. Walk off the mat to stop.", RangeInfo.FIREBALL_COOLDOWN),
		Parent = list,
	})
	row(1, "😴", "AFK practice", string.format("Fires by itself at slow targets. About %d%% of a level every 10 minutes.", math.floor(RangeInfo.AFK.xpPerMinute * 1000 + 0.5)),
		Color3.fromRGB(150, 200, 255), "Start AFK", Color3.fromRGB(70, 110, 170), true, function()
			send("afk")
		end)
	for i, def in ipairs(RangeInfo.Levels) do
		local cleared = i <= best
		local unlocked = i <= best + 1
		local body = string.format("Hit %d targets in %ds  •  %s", def.needed, def.time, cleared and ("replay: " .. levelXpText({ xp = def.xp * RangeInfo.REPLAY_XP })) or ("first clear: " .. levelXpText(def)))
		row(i + 1, cleared and "✅" or (unlocked and "🎯" or "🔒"), string.format("%d. %s", i, def.name), body,
			cleared and C.good or (unlocked and C.accent or C.subtext),
			unlocked and (cleared and "Replay" or "Start") or "Locked", Color3.fromRGB(190, 90, 50), unlocked, function()
				send("start", i)
			end)
	end
end

---------------------------------------------------------------- session panel

local function placePanel()
	if App.Windows.mobile then
		local raidBar = App.Windows.guis.HUD:FindFirstChild("RaidBar")
		panel.AnchorPoint = Vector2.new(0, 1)
		panel.Position = UDim2.new(0, 130, 1, (raidBar and raidBar.Visible) and -72 or -8)
		panel.Size = UDim2.fromOffset(372, 58)
	else
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.new(0.5, 0, 1, -168)
		panel.Size = UDim2.fromOffset(440, 58)
	end
end

local function updatePanel()
	local s = session
	if not s or not player:GetAttribute("RangeMode") then
		panel.Visible = false
		return
	end
	panel.Visible = true
	placePanel()
	if s.mode == "afk" then
		panelTitle.Text = "😴 AFK practice"
		panelInfo.Text = string.format("Targets hit: <b>%d</b>  •  XP every %ds while you stay on the mat", s.hits, RangeInfo.AFK.tick)
	else
		local left = math.max(0, (s.endsAt or 0) - workspace:GetServerTimeNow())
		panelTitle.Text = string.format("🎯 Level %d: %s", s.level, s.name)
		panelInfo.Text = string.format("Hits <b>%d / %d</b>  •  time left <b>%s</b>", s.hits, s.needed, Util.formatTime(math.ceil(left)))
	end
end

local RESULT_TEXT = {
	time = "Time's up!",
	walked = "You left the firing mat.",
	died = "You were knocked out.",
	raid = "Vikings in town! Practice is over.",
	stopped = "Practice stopped.",
}

local function onState(data)
	if type(data) ~= "table" then
		return
	end
	local result = data.result
	if not result then
		session = data
		updatePanel()
		return
	end
	session = nil
	updatePanel()
	if result.reason == "restart" or result.reason == "left" then
		return
	end
	if result.cleared then
		App.Sfx.play("LevelUp")
		App.Notifications.announce({
			title = data.level > 0 and string.format("LEVEL %d CLEARED!", data.level) or "PRACTICE DONE",
			text = string.format("%d / %d targets  •  +%s XP%s", result.hits, result.needed, Util.formatNumber(result.xp or 0), result.first and "  •  next level unlocked!" or ""),
			color = Color3.fromRGB(255, 215, 80),
			duration = 4,
		})
		task.delay(1.5, function()
			if not player:GetAttribute("RangeMode") then
				App.Windows.open("Range")
			end
		end)
	elseif data.mode == "level" then
		App.Notifications.toast(string.format("%s %d / %d targets. Try again!", RESULT_TEXT[result.reason] or "Practice over.", result.hits or 0, result.needed or 0), Color3.fromRGB(255, 190, 110), "🎯")
	else
		App.Notifications.toast(RESULT_TEXT[result.reason] or "AFK practice over.", Color3.fromRGB(150, 200, 255), "😴")
	end
end

---------------------------------------------------------------- targets

-- Where my closest target will be when a fireball gets there (AFK mode aims with this).
local function autoAim(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local best, bestDist = nil, math.huge
	for model, t in pairs(params) do
		if model.Parent and model:GetAttribute("OwnerUserId") == player.UserId and not RangeUtil.expired(t, now) then
			local pos = RangeUtil.position(t, now)
			local d = (pos - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = t, d
			end
		end
	end
	if not best then
		return nil
	end
	local travel = bestDist / 120 + 0.1 -- Fireball speed, plus a little for the trip to the server
	return RangeUtil.position(best, now + travel)
end

local function step()
	local now = workspace:GetServerTimeNow()
	for model, t in pairs(params) do
		if not model.Parent then
			params[model] = nil
		else
			model:PivotTo(CFrame.new(RangeUtil.position(t, now)))
		end
	end
	if player:GetAttribute("RangeMode") == "afk" and os.clock() >= nextAuto then
		nextAuto = os.clock() + RangeInfo.AFK.fireEvery
		local aim = autoAim()
		if aim then
			App.Combat.cast("Fireball", aim)
		end
	end
end

local function watch(model: Instance)
	if model:IsA("Model") then
		params[model] = RangeUtil.fromModel(model)
	end
end

function Range.open()
	App.Windows.open("Range")
end

function Range.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🏹 Target Practice", Vector2.new(620, 470))
	close.Activated:Connect(function()
		App.Windows.close("Range")
	end)
	list = Theme.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Theme.list(list, 6)
	App.Windows.register("Range", window, Range.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Range.refresh()
		end
	end)

	panel = Theme.make("Frame", {
		Name = "RangePanel",
		BackgroundColor3 = Color3.fromRGB(28, 24, 18),
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(panel, 12)
	Theme.stroke(panel, C.accent, 2)
	panelTitle = Theme.label({ Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -110, 0, 24), Font = Theme.Fonts.title, TextSize = 18, TextColor3 = C.accent, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = panel })
	panelInfo = Theme.label({ Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -110, 0, 22), TextSize = 13, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = panel })
	Theme.button("Stop", Color3.fromRGB(120, 60, 60), function()
		send("stop")
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(86, 38), TextSize = 15, Parent = panel })

	Remotes.event("RangeState").OnClientEvent:Connect(onState)
	for _, model in ipairs(CollectionService:GetTagged("PracticeTarget")) do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal("PracticeTarget"):Connect(watch)
	player:GetAttributeChangedSignal("RangeMode"):Connect(function()
		nextAuto = os.clock() + 1
		updatePanel()
		App.HUD.refresh()
	end)
	RunService.RenderStepped:Connect(step)
	task.spawn(function()
		while true do
			task.wait(0.25)
			updatePanel()
		end
	end)
end

return Range
