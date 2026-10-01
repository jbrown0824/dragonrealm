-- The dungeon pill: a small panel out of the way (top left under the player card on computers, the
-- bottom-left stack on phones) that shows where you are with dungeons:
--   in the queue     "🏰 The Draugr Barrow • 2/4 • 3 looking • 0:42"   [X]
--   a ready check    "Your group is ready!" with a countdown bar and Enter / Not now
--   in a run         packs cleared, in or out of combat, the boss's health   [Leave]
-- Invites pop up as a toast with Join / No thanks. While you're knocked out in a run it keeps the
-- death screen's line up to date (your group is still fighting / everyone's down).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DungeonInfo = require(Shared.Config.Dungeons)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local DungeonHUD = {}
local App

local pill, title, info, barBack, barFill, enterButton, noButton, leaveButton, xButton
local mode = nil -- "queue" | "check" | "run" | nil
local pushedToasts = false

local PILL_Y = 180 -- desktop: under the player card and the offer button, above the toasts

local function send(action: string, args)
	task.spawn(function()
		local ok, msg = Remotes.func("DungeonAction"):InvokeServer(action, args or {})
		if not ok and msg then
			App.Notifications.toast(msg, C.bad, "🏰")
		end
	end)
end

local function nameOf(id: string): string
	local def = DungeonInfo.get(id)
	return def and def.name or id
end

local function place(height: number)
	if App.Windows.mobile then
		local hud = App.Windows.guis.HUD
		local raidBar, raidPill, range = hud:FindFirstChild("RaidBar"), hud:FindFirstChild("RaidPill"), hud:FindFirstChild("RangePanel")
		local lift = (raidBar and raidBar.Visible) and -72 or ((raidPill and raidPill.Visible) and -48 or -8)
		if range and range.Visible then
			lift -= 66
		end
		pill.AnchorPoint = Vector2.new(0, 1)
		pill.Position = UDim2.new(0, 130, 1, lift)
		pill.Size = UDim2.fromOffset(372, height)
	else
		pill.AnchorPoint = Vector2.new(0, 0)
		pill.Position = UDim2.fromOffset(12, PILL_Y)
		pill.Size = UDim2.fromOffset(320, height)
	end
end

local function hide()
	pill.Visible = false
	mode = nil
	if pushedToasts then
		pushedToasts = false
		App.Notifications.setTopInset(nil)
	end
end

local function show(height: number, color: Color3)
	pill.Visible = true
	place(height)
	pill.UIStroke.Color = color
	if not App.Windows.mobile then
		pushedToasts = true
		App.Notifications.setTopInset(PILL_Y + height)
	end
end

-- invite toasts by group id: they go away once the invite is answered (from the window too) or runs
-- out. The toast can arrive before the state that lists the invite, so only an invite the state has
-- shown and then dropped counts as answered.
local inviteToasts = {}

local function dropStaleInvites(state)
	local now = workspace:GetServerTimeNow()
	for groupId, t in pairs(inviteToasts) do
		local live = false
		for _, inv in ipairs(state and state.invites or {}) do
			if inv.groupId == groupId then
				live = true
			end
		end
		if live then
			t.seen = true
		end
		local joined = state and state.group and state.group.id == groupId
		if not t.frame.Parent or joined or (not live and (t.seen or now > t.endsAt)) then
			inviteToasts[groupId] = nil
			if t.frame.Parent then
				t.frame:Destroy()
			end
		end
	end
end

function DungeonHUD.update()
	local state = App.State.dungeon
	dropStaleInvites(state)
	if not state then
		hide()
		return
	end
	local now = workspace:GetServerTimeNow()
	enterButton.Visible, noButton.Visible, leaveButton.Visible, xButton.Visible, barBack.Visible = false, false, false, false, false
	info.Visible = false
	title.Size = UDim2.new(1, -60, 0, 22)
	info.Size = UDim2.new(1, -20, 0, 18)
	if state.check then
		local c = state.check
		local def = DungeonInfo.get(c.dungeonId)
		mode = "check"
		show(90, def.color)
		title.Size = UDim2.new(1, -16, 0, 22)
		title.Text = "🏰 Your group is ready!"
		title.TextColor3 = def.color
		info.Visible = true
		info.Text = string.format("%s  •  %d/%d ready  •  %s", def.name, c.accepted, c.total, Util.formatTime(math.max(0, c.endsAt - now)))
		barBack.Visible = true
		barFill.Size = UDim2.fromScale(math.clamp((c.endsAt - now) / DungeonInfo.READY_TIME, 0, 1), 1)
		barFill.BackgroundColor3 = def.color
		if c.mine then
			info.Text ..= "  •  waiting for the others"
		else
			enterButton.Visible = true
			noButton.Visible = true
		end
	elseif state.run then
		local r = state.run
		local def = DungeonInfo.get(r.dungeonId)
		mode = "run"
		show(40, def.color)
		leaveButton.Visible = true
		title.TextColor3 = C.text
		if r.done then
			title.Text = string.format("🏆 Cleared!  •  back out in %s", Util.formatTime(math.max(0, (r.closesAt or now) - now)))
		else
			local fight = r.inCombat and "⚔️ fighting" or "🕊️ safe"
			local boss = r.bossHp and string.format("  •  💀 %d%%", math.ceil(r.bossHp * 100)) or ""
			title.Text = string.format("%s Packs %d/%d  •  %s%s", def.icon, r.cleared, r.packs, fight, boss)
		end
		if r.dead then
			App.Notifications.setDeathInfo(r.wipe and "Your whole group is down... back to the entrance in a moment."
				or (r.inCombat and string.format("Your group is still fighting (%d/%d up). You'll get back up when it's over.", r.alive, r.size) or "Getting back up..."))
		end
	elseif state.queue then
		local q = state.queue
		local def = DungeonInfo.get(q.dungeonId)
		mode = "queue"
		show(54, def.color)
		xButton.Visible = true
		title.TextColor3 = C.text
		title.Text = string.format("🏰 %s  •  %s", nameOf(q.dungeonId), Util.formatTime(math.max(0, now - q.since)))
		info.Visible = true
		info.Size = UDim2.new(1, -50, 0, 18)
		info.Text = string.format("Your group %d/%d  •  👀 %d looking", q.size, DungeonInfo.MAX_GROUP, q.looking)
	else
		hide()
	end
end

local function onInvite(data)
	local frame = App.Notifications.toast(string.format("%s invited you to their dungeon group!", data.from), C.good, "🤝", {
		{ text = "Join", onClick = function()
			send("accept", { groupId = data.groupId })
		end },
		{ text = "No thanks", color = C.panel3, onClick = function()
			send("decline", { groupId = data.groupId })
		end },
	})
	inviteToasts[data.groupId] = { frame = frame, endsAt = data.endsAt or (workspace:GetServerTimeNow() + 30), seen = false }
	App.Sfx.play("Quest")
end

function DungeonHUD.init(app)
	App = app
	pill = Theme.make("Frame", {
		Name = "DungeonPill",
		BackgroundColor3 = Color3.fromRGB(24, 22, 30),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(pill, 10)
	Theme.stroke(pill, C.accent, 2)
	title = Theme.label({ Name = "Title", Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -60, 0, 22), TextSize = 14, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Parent = pill })
	info = Theme.label({ Name = "Info", Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 18), TextSize = 12, TextColor3 = C.subtext, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Visible = false, Parent = pill })
	barBack = Theme.make("Frame", { Position = UDim2.new(0, 10, 0, 50), Size = UDim2.new(1, -20, 0, 4), BackgroundColor3 = C.bg, Visible = false, Parent = pill })
	barFill = Theme.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = barBack })
	enterButton = Theme.button("⚔️ Enter", C.good, function()
		send("ready", { yes = true })
	end, { Name = "Enter", Position = UDim2.new(0, 10, 1, -32), Size = UDim2.new(0.5, -14, 0, 26), TextSize = 14, Visible = false, Parent = pill })
	noButton = Theme.button("Not now", Color3.fromRGB(120, 60, 60), function()
		send("ready", { yes = false })
	end, { Name = "NotNow", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 1, -32), Size = UDim2.new(0.5, -14, 0, 26), TextSize = 14, Visible = false, Parent = pill })
	leaveButton = Theme.button("Leave", Color3.fromRGB(120, 60, 60), function()
		send("leaveRun")
	end, { Name = "Leave", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(52, 26), TextSize = 13, Visible = false, Parent = pill })
	xButton = Theme.button("X", Color3.fromRGB(120, 60, 60), function()
		send("unqueue")
	end, { Name = "LeaveQueue", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(28, 26), TextSize = 13, Visible = false, Parent = pill })
	-- tapping the pill (not a button) opens the window
	local open = Theme.make("TextButton", { Name = "Open", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 0, Parent = pill })
	open.Activated:Connect(function()
		if mode ~= "run" then
			App.Windows.open("Dungeons")
		end
	end)

	App.State.dungeonChanged:Connect(DungeonHUD.update)
	Remotes.event("DungeonInvite").OnClientEvent:Connect(onInvite)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if pill.Visible then
				DungeonHUD.update() -- (countdowns)
			end
		end
	end)
	task.spawn(function()
		Remotes.func("DungeonAction"):InvokeServer("state", {})
	end)
end

return DungeonHUD
