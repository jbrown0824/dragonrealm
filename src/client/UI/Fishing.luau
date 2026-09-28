-- Fishing on the client: a line from your dragon's mouth to the float, a "waiting for a bite"
-- panel, and the reel minigame (stop the swinging needle inside the green zone). The server
-- (FishingService) picks the fish and checks the timing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Food = require(Shared.Config.Food)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Fishing = {}
local App

local panel, title, hint, bar, zone, needle, reelButton
local line: Part? = nil
local spotPos: Vector3? = nil
local bite = nil -- { token, zoneStart, zoneWidth, speed, deadline, t0 }

local function mouthPos(): Vector3?
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	return mouth and mouth.WorldPosition or (character and character:GetPivot().Position)
end

local function stopLine()
	if line then
		line:Destroy()
		line = nil
	end
	spotPos = nil
end

local function hide()
	panel.Visible = false
	bite = nil
	stopLine()
end

local function needleX(): number
	-- ping-pong between 0 and 1
	local t = (os.clock() - bite.t0) * bite.speed
	local f = t % 2
	return f < 1 and f or 2 - f
end

local function reel()
	if not bite then
		return
	end
	local x = needleX()
	local success = x >= bite.zoneStart and x <= bite.zoneStart + bite.zoneWidth
	Remotes.event("FishingAction"):FireServer("reel", bite.token, success)
	bite = nil
	title.Text = success and "🎣 Reeling it in..." or "💦 Missed!"
	reelButton.Visible = false
end

local function onEvent(data)
	if data.phase == "cast" then
		spotPos = data.pos
		panel.Visible = true
		bar.Visible = false
		reelButton.Visible = false
		title.Text = "🎣 Waiting for a bite..."
		hint.Text = "Stay close. Walking away, flying or getting hit loses your line."
		App.Movement.faceToward(data.pos, 1.5)
		if not line then
			line = Instance.new("Part")
			line.Name = "FishingLine"
			line.Anchored = true
			line.CanCollide = false
			line.CanQuery = false
			line.CanTouch = false
			line.CastShadow = false
			line.Material = Enum.Material.Neon
			line.Color = Color3.fromRGB(235, 235, 245)
			line.Parent = workspace:FindFirstChild("ClientEffects") or workspace
		end
	elseif data.phase == "bite" then
		panel.Visible = true
		bar.Visible = true
		reelButton.Visible = true
		title.Text = "🐟 A BITE! Stop the needle in the green!"
		hint.Text = "Click REEL or press T"
		local width = data.zone or 0.25
		bite = {
			token = data.token,
			zoneWidth = width,
			zoneStart = 0.08 + math.random() * (0.84 - width),
			speed = data.speed or 1.2,
			deadline = os.clock() + (data.window or 4),
			t0 = os.clock() + math.random(),
		}
		zone.Position = UDim2.fromScale(bite.zoneStart, 0)
		zone.Size = UDim2.fromScale(width, 1)
		App.Sfx.play("Hit", 0.6)
	elseif data.phase == "caught" then
		local fish = Food.get(data.fish)
		title.Text = fish and string.format("You caught a %s %s!", fish.icon, fish.name) or "Caught!"
		hint.Text = ""
		bar.Visible = false
		reelButton.Visible = false
		App.Sfx.play("Loot")
		stopLine()
		task.delay(2, function()
			if not bite and not spotPos then
				panel.Visible = false
			end
		end)
	elseif data.phase == "stop" then
		if data.reason then
			App.Notifications.toast(data.reason, Color3.fromRGB(170, 210, 255), "🎣")
		end
		hide()
	end
end

function Fishing.init(app)
	App = app
	panel = Theme.make("Frame", {
		Name = "Fishing",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -178),
		Size = UDim2.fromOffset(420, 120),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(panel, 12)
	Theme.stroke(panel, Color3.fromRGB(120, 190, 255), 2)
	title = Theme.label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 26), Font = Theme.Fonts.title, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
	hint = Theme.label({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 18), TextSize = 12, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Center, Parent = panel })
	bar = Theme.make("Frame", { Position = UDim2.fromOffset(16, 58), Size = UDim2.new(1, -150, 0, 26), BackgroundColor3 = Color3.fromRGB(40, 60, 90), Visible = false, Parent = panel })
	Theme.corner(bar, 6)
	zone = Theme.make("Frame", { Size = UDim2.fromScale(0.25, 1), BackgroundColor3 = Color3.fromRGB(90, 220, 110), Parent = bar })
	Theme.corner(zone, 6)
	needle = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 5, 1, 10), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = bar })
	reelButton = Theme.button("REEL!", Color3.fromRGB(60, 140, 200), reel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 52), Size = UDim2.fromOffset(110, 40), TextSize = 20, Visible = false, Parent = panel })

	Remotes.event("Fishing").OnClientEvent:Connect(onEvent)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.T then
			reel()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if bite then
			needle.Position = UDim2.fromScale(needleX(), 0.5)
			if os.clock() > bite.deadline then
				reel()
			end
		end
		if line and spotPos then
			local from = mouthPos()
			if from then
				local dist = (spotPos - from).Magnitude
				-- a slightly sagging line: straight segment is good enough at this size
				line.Size = Vector3.new(0.08, 0.08, dist)
				line.CFrame = CFrame.lookAt((from + spotPos) / 2, spotPos)
			end
		end
	end)
end

return Fishing
