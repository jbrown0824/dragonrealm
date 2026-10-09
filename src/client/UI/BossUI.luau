-- Boss warning banner with the queue button, and the boss health bar during the fight.
-- It pops up big at the top when a boss is on its way and when your own fight starts, then glides
-- over to the side once you get going (SideDock). It can be minimized to a small pill in the same
-- spot (click the pill to open it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local SideDock = require(script.Parent.SideDock)
local C = Theme.Colors

local BossUI = {}
local App

local banner, titleLabel, infoLabel, queueButton
local hpBar, hpFill, hpText
local pill, dock
local busy = false
local minimized = false
local lastFighting = false
local lastPhase = nil

local function contains(list, value): boolean
	if not list then
		return false
	end
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function update()
	local data = App.State.boss
	local me = Players.LocalPlayer.UserId
	if not data or data.phase == "idle" or not data.name or Players.LocalPlayer:GetAttribute("InDungeon") then
		SideDock.show(dock, nil)
		minimized = false
		lastPhase = nil
		return
	end
	local now = workspace:GetServerTimeNow()
	local fightingNow = contains(data.participants, me)
	-- Pop back open (big, up top) when a boss is on its way and when your own fight starts.
	if fightingNow and not lastFighting then
		minimized = false
		SideDock.pop(dock)
	elseif data.phase == "warning" and lastPhase ~= "warning" then
		SideDock.pop(dock)
	end
	lastFighting = fightingNow
	lastPhase = data.phase
	SideDock.show(dock, minimized and "pill" or "box")
	-- (the pill also stands in for the banner on a phone short of room)
	if data.phase == "warning" then
		pill.Text = string.format("⚔️ Boss attacks in %s  (open)", Util.formatTime(data.spawnAt - now))
	else
		pill.Text = string.format("⚔️ Boss fight: %s left  (open)", Util.formatTime((data.endsAt or now) - now))
	end
	if minimized then
		return
	end

	if data.phase == "warning" then
		local inQueue = contains(data.queue, me)
		titleLabel.Text = "⚠️ " .. data.name
		infoLabel.Text = string.format("Attacks in <b>%s</b>  •  %d dragon%s in the queue", Util.formatTime(data.spawnAt - now), #data.queue, #data.queue == 1 and "" or "s")
		queueButton.Visible = true
		queueButton.Text = inQueue and "Leave Queue" or "⚔️ Join Queue"
		queueButton.BackgroundColor3 = inQueue and Color3.fromRGB(120, 60, 60) or Color3.fromRGB(190, 70, 40)
		hpBar.Visible = false
	else
		local fighting = contains(data.participants, me)
		queueButton.Visible = fighting and data.phase == "fight"
		queueButton.Text = "🚪 Leave Fight"
		queueButton.BackgroundColor3 = Color3.fromRGB(90, 70, 110)
		titleLabel.Text = (data.phase == "ending" and "🏁 " or "⚔️ ") .. data.name
		if fighting or data.phase == "ending" then
			hpBar.Visible = true
			local pct = (data.maxHp or 1) > 0 and math.clamp((data.hp or 0) / data.maxHp, 0, 1) or 0
			hpFill.Size = UDim2.fromScale(pct, 1)
			hpText.Text = string.format("%s / %s", Util.formatNumber(data.hp or 0), Util.formatNumber(data.maxHp or 0))
			local hearts = ""
			local lives = data.lives and data.lives[tostring(me)]
			if fighting and lives and data.maxLives then
				hearts = string.rep("❤️", lives) .. string.rep("🖤", math.max(0, data.maxLives - lives)) .. "  •  "
			end
			infoLabel.Text = data.phase == "ending" and "The battle is over!" or string.format("%sTime left: <b>%s</b>", hearts, Util.formatTime((data.endsAt or now) - now))
		else
			hpBar.Visible = false
			infoLabel.Text = string.format("%d dragon%s battling the boss right now!", data.participants and #data.participants or 0, (data.participants and #data.participants == 1) and " is" or "s are")
		end
	end
	-- stack the rows: title, info, then the health bar and the button when they show
	local y = 56
	if hpBar.Visible then
		hpBar.Position = UDim2.fromOffset(12, y)
		y += 24
	end
	if queueButton.Visible then
		queueButton.Position = UDim2.fromOffset(12, y)
		y += 38
	end
	banner.Size = UDim2.fromOffset(SideDock.WIDTH, y + 2)
end

function BossUI.init(app)
	App = app
	banner = Theme.make("Frame", {
		Name = "BossBanner",
		Size = UDim2.fromOffset(SideDock.WIDTH, 96),
		BackgroundColor3 = Color3.fromRGB(40, 16, 20),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(banner, 12)
	Theme.stroke(banner, Color3.fromRGB(255, 90, 60), 2)
	titleLabel = Theme.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -48, 0, 24),
		Font = Theme.Fonts.title,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 140, 100),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = banner,
	})
	infoLabel = Theme.label({
		Position = UDim2.fromOffset(12, 33),
		Size = UDim2.new(1, -24, 0, 18),
		TextSize = 13,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = banner,
	})
	queueButton = Theme.button("⚔️ Join Queue", Color3.fromRGB(190, 70, 40), function()
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local data = App.State.boss
			local me = Players.LocalPlayer.UserId
			local ok, err
			if data and data.phase == "fight" and contains(data.participants, me) then
				ok, err = Remotes.func("LeaveBossFight"):InvokeServer()
			else
				local inQueue = data and contains(data.queue, me)
				ok, err = Remotes.func("BossQueue"):InvokeServer(not inQueue)
			end
			if not ok and err then
				App.Notifications.toast(err, C.bad, "⚔️")
			end
			busy = false
		end)
	end, {
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 0, 32),
		TextSize = 16,
		Parent = banner,
	})
	hpBar, hpFill, hpText = Theme.bar(banner, Color3.fromRGB(220, 50, 50), UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 56))
	hpBar.Visible = false
	local hide = Theme.minimizeButton(function()
		minimized = true
		update()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(28, 28), ZIndex = 3, Parent = banner })
	hide:FindFirstChildOfClass("Frame").ZIndex = 4
	pill = Theme.button("", Color3.fromRGB(60, 25, 30), function()
		minimized = false
		SideDock.raise(dock)
		update()
	end, {
		Name = "BossPill",
		Size = UDim2.fromOffset(SideDock.WIDTH, 32),
		TextSize = 14,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.stroke(pill, Color3.fromRGB(255, 90, 60), 2)
	dock = SideDock.add(banner, { pill = pill })

	App.State.bossChanged:Connect(update)
	Players.LocalPlayer:GetAttributeChangedSignal("InDungeon"):Connect(update)
	RunService.RenderStepped:Connect(function()
		if SideDock.wants(dock) then
			update()
		end
	end)
end

return BossUI
