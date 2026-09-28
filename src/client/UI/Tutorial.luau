-- The new-player tour: a small panel with one goal at a time, a glowing marker over where to
-- go, and a Skip button. Steps complete themselves when you do the thing (walk, fly, hit a
-- dummy...). Progress is saved on the server (TutorialService), which pays out a one-time
-- reward at the end. It can be restarted from the Help window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Tutorial = {}
local App

local player = Players.LocalPlayer
local panel, stepLabel, titleLabel, bodyLabel, nextButton, skipButton
local marker, markerAttachment, beam, beamStart
local current = nil -- index into STEPS, or nil when not running
local stepState = {}
local dummyHit = false
local skipArmed = false

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function homePosition(): Vector3?
	local p = App.State.profile
	local bases = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Bases")
	local base = p and p.baseIndex and bases and bases:FindFirstChild("Base" .. p.baseIndex)
	local home = base and base:FindFirstChild("HomeSpawn")
	return home and home.Position
end

local STEPS = {
	{ title = "Welcome to Dragon Realm!", text = "You're a young dragon in Dragon Town. This quick tour shows you the basics. You can skip it any time.", button = "Let's go!" },
	{ title = "Stretch your legs", text = "Walk around with <b>WASD</b> (or the thumbstick). <b>Space</b> jumps.",
		check = function(s)
			local r = root()
			if not r then
				return false
			end
			s.start = s.start or r.Position
			return (r.Position - s.start).Magnitude > 25
		end },
	{ title = "Take flight", text = "Press <b>F</b> (or jump, then press <b>Space</b> again) to fly. Space = up, Ctrl or C = down. Flying uses your blue stamina bar.",
		check = function(s)
			local flying = App.Movement.isFlying()
			if flying then
				s.since = s.since or os.clock()
				return os.clock() - s.since > 1.5
			end
			s.since = nil
			return false
		end },
	{ title = "Touch down", text = "Fly down to the ground (or press <b>F</b>) to land and rest your wings.",
		check = function()
			return not App.Movement.isFlying()
		end },
	{ title = "Breathe fire!", text = "Head to the <b>Training Dummies</b> (follow the marker). Hold <b>Left Mouse</b> to breathe fire at one and watch your DPS!",
		target = function()
			return Zones.Training.dummies[2] + Vector3.new(0, 11, 0)
		end,
		check = function()
			return dummyHit
		end },
	{ title = "Fireball", text = "Now press <b>Q</b> to hurl a fireball at the dummy. At level 3 your dragon learns its very own move on key <b>1</b>, and skill-tree abilities go on <b>2-4</b>.",
		target = function()
			return Zones.Training.dummies[2] + Vector3.new(0, 11, 0)
		end,
		check = function()
			local remaining = App.Combat.getCooldown("Fireball")
			return remaining > 0
		end },
	{ title = "Your first quest", text = "Talk to <b>Elder Pyrrhus</b> (the ❗ by the plaza) and accept a quest. Dragons with ❗ have quests; ❓ means one is ready to hand in.",
		target = function()
			return Zones.QuestGivers.Elder.position + Vector3.new(0, 14, 0)
		end,
		check = function()
			local p = App.State.profile
			return p ~= nil and (next(p.quests.active) ~= nil or next(p.quests.done) ~= nil)
		end },
	{ title = "Your lair", text = "Press <b>H</b> (or the 🏠 button) to fly home to your lair.",
		target = function()
			local home = homePosition()
			return home and home + Vector3.new(0, 10, 0)
		end,
		check = function()
			local r = root()
			local home = homePosition()
			return r ~= nil and home ~= nil and (r.Position - home).Magnitude < 60
		end },
	{ title = "Plant a seed", text = "Walk up to a planting spot (the one you face glows) and press <b>E</b> to plant. When it gets thirsty (💧) press <b>R</b> to water it. Full flowers give seeds back!",
		check = function()
			local p = App.State.profile
			return p ~= nil and p.garden ~= nil and #p.garden > 0
		end },
	{ title = "Stay fed", text = "The orange bar is your <b>hunger</b>. Hunt animals in <b>Elk Meadows</b> (west) or <b>Whisperwood</b> (east), or fish at the 🎣 spots, then press <b>G</b> to eat. Hungry dragons fly and fight worse!", button = "Got it" },
	{ title = "Pets & potions", text = "<b>Nestmother's Hatchery</b> sells eggs that hatch into nano dragon pets (<b>P</b>). The <b>Bubbling Cauldron</b> sells permanent potions. Your lair's <b>Bot Dock</b> sells garden robots.", button = "Cool!" },
	{ title = "You're ready!", text = "Cross the bridge south to fight vikings, open camp chests and beat camp champions (💀). Finish the tour for <b>150 gold and a dragon egg</b>!", button = "Finish tour" },
}

-- Keep notification toasts below the tour panel while it's showing.
local function updateToastInset()
	if panel.Visible then
		local scale = App.Windows.scale or 1
		App.Notifications.setTopInset(132 + panel.AbsoluteSize.Y / scale)
	else
		App.Notifications.setTopInset(nil)
	end
end

local function clearGuide()
	marker.Enabled = false
	beam.Enabled = false
end

local function showStep()
	local step = STEPS[current]
	stepState = {}
	skipArmed = false
	skipButton.Text = "Skip tour"
	panel.Visible = true
	stepLabel.Text = string.format("TOUR  %d / %d", current, #STEPS)
	titleLabel.Text = step.title
	bodyLabel.Text = step.text
	nextButton.Visible = step.button ~= nil
	nextButton.Text = step.button or ""
	panel.Position = UDim2.new(0, -360, 0, 132)
	TweenService:Create(panel, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(0, 12, 0, 132) }):Play()
	clearGuide()
	task.defer(updateToastInset)
end

local function finish(skipped: boolean)
	current = nil
	panel.Visible = false
	clearGuide()
	App.Waypoint.setSuppressed(false)
	updateToastInset()
	Remotes.event("TutorialStep"):FireServer(skipped and -2 or -1)
end

local function advance()
	App.Sfx.play("Quest")
	if current >= #STEPS then
		finish(false)
		return
	end
	current += 1
	Remotes.event("TutorialStep"):FireServer(current)
	showStep()
end

-- Start (or resume) the tour if the profile says it isn't finished.
local function maybeStart()
	local p = App.State.profile
	if current or not p or not p.class or p.tutorial == nil or p.tutorial < 0 then
		return
	end
	if App.ClassSelect.isVisible() then
		return
	end
	current = math.clamp(p.tutorial, 1, #STEPS)
	showStep()
end

function Tutorial.restart()
	current = nil
	Remotes.event("TutorialStep"):FireServer(1)
	task.delay(0.5, maybeStart)
end

function Tutorial.init(app)
	App = app
	panel = Theme.make("Frame", {
		Name = "Tutorial",
		Position = UDim2.new(0, 12, 0, 132),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = App.Windows.guis.HUD,
	})
	Theme.corner(panel, 12)
	Theme.stroke(panel, C.accent, 2)
	Theme.pad(panel, 10)
	Theme.list(panel, 4)
	stepLabel = Theme.label({ Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = C.subtext, LayoutOrder = 1, Parent = panel })
	titleLabel = Theme.label({ Size = UDim2.new(1, 0, 0, 24), Font = Theme.Fonts.title, TextSize = 21, TextColor3 = C.accent, LayoutOrder = 2, Parent = panel })
	bodyLabel = Theme.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, Font = Theme.Fonts.body, LayoutOrder = 3, Parent = panel })
	local buttons = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 4, Parent = panel })
	nextButton = Theme.button("Next", Color3.fromRGB(60, 140, 70), function()
		if current then
			advance()
		end
	end, { Size = UDim2.fromOffset(140, 30), TextSize = 14, Parent = buttons })
	skipButton = Theme.button("Skip tour", C.panel3, function()
		if not current then
			return
		end
		if not skipArmed then
			skipArmed = true
			skipButton.Text = "Really skip?"
			return
		end
		finish(true)
		App.Notifications.toast("Tour skipped. You can restart it from the ❓ Help window.", C.subtext, "🎓")
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(110, 30), TextSize = 13, Parent = buttons })

	-- Guide: a floating marker at the goal and a glowing line to it from your dragon.
	markerAttachment = Instance.new("Attachment")
	markerAttachment.Name = "TutorialTarget"
	markerAttachment.Parent = workspace.Terrain
	marker = Instance.new("BillboardGui")
	marker.Name = "TutorialMarker"
	marker.Adornee = markerAttachment
	marker.Size = UDim2.fromOffset(120, 70)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Enabled = false
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.Font = Enum.Font.FredokaOne
	arrow.TextScaled = true
	arrow.TextColor3 = Color3.fromRGB(255, 215, 80)
	arrow.TextStrokeTransparency = 0.2
	arrow.Text = "⬇"
	arrow.Parent = marker
	marker.Parent = player:WaitForChild("PlayerGui")
	beam = Instance.new("Beam")
	beam.Name = "TutorialBeam"
	beam.Attachment1 = markerAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.8
	beam.Width1 = 0.8
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 215, 80))
	beam.Transparency = NumberSequence.new(0.35)
	beam.LightEmission = 1
	beam.Segments = 2
	beam.Enabled = false
	beam.Parent = workspace.Terrain

	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateToastInset)
	App.Training.hit:Connect(function()
		dummyHit = true
	end)
	App.State.changed:Connect(maybeStart)

	RunService.Heartbeat:Connect(function()
		if not current then
			return
		end
		local step = STEPS[current]
		-- guide
		local target = step.target and step.target()
		local r = root()
		App.Waypoint.setSuppressed(target ~= nil)
		if target and r then
			markerAttachment.WorldPosition = target
			marker.Enabled = true
			arrow.Text = string.format("⬇\n%d studs", math.floor((r.Position - target).Magnitude))
			if not beamStart or beamStart.Parent ~= r then
				beamStart = Instance.new("Attachment")
				beamStart.Name = "TutorialBeamStart"
				beamStart.Parent = r
			end
			beam.Attachment0 = beamStart
			beam.Enabled = (r.Position - target).Magnitude > 25
		else
			clearGuide()
		end
		-- goal
		if step.check then
			local ok, done = pcall(step.check, stepState)
			if ok and done then
				advance()
			end
		end
	end)
end

return Tutorial
