-- The "Choose Your Dragon" screen with spinning 3D previews. Also used by Elder Pyrrhus to
-- transform into a different dragon type later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Game = require(Shared.Config.Game)
local DragonBuilder = require(Shared.DragonBuilder)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local ClassSelect = {}
local App

local frame
local title, subtitle, cancelButton
local cards = {}
local mode = "choose"
local busy = false
local spinConnection

local function statPips(parent: Instance, y: number, label: string, value: number, color: Color3)
	Theme.label({
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(70, 16),
		TextSize = 13,
		TextColor3 = C.subtext,
		Text = label,
		Parent = parent,
	})
	for i = 1, 5 do
		local pip = Theme.make("Frame", {
			Position = UDim2.fromOffset(72 + (i - 1) * 22, y + 2),
			Size = UDim2.fromOffset(18, 12),
			BackgroundColor3 = i <= value and color or Color3.fromRGB(60, 55, 75),
			Parent = parent,
		})
		Theme.corner(pip, 3)
	end
end

local function transformCost(): number
	local p = App.State.profile
	return p and Game.transformCost(p.level) or 0
end

local function choose(classId: string)
	if busy then
		return
	end
	busy = true
	if mode == "choose" then
		local ok = Remotes.func("ChooseClass"):InvokeServer(classId)
		if ok then
			ClassSelect.hide()
		end
	else
		local ok, err = Remotes.func("Transform"):InvokeServer(classId)
		if ok then
			ClassSelect.hide()
		elseif err then
			App.Notifications.toast(err, C.bad, "🐉")
		end
	end
	busy = false
end

local function buildCard(parent: Instance, classId: string, index: number)
	local class = Classes.get(classId)
	local card = Theme.make("Frame", {
		Name = classId,
		Size = UDim2.fromOffset(196, 470),
		BackgroundColor3 = C.panel,
		LayoutOrder = index,
		Parent = parent,
	})
	Theme.corner(card, 14)
	local stroke = Theme.stroke(card, class.colors.accent, 2.5, 0.2)

	local viewport = Theme.make("ViewportFrame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 160),
		BackgroundColor3 = Color3.fromRGB(35, 30, 50),
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-1, -1.5, -0.5),
		Parent = card,
	})
	Theme.corner(viewport, 10)
	local model = DragonBuilder.build(classId, { anchored = true, noParticles = true })
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	Theme.label({
		Position = UDim2.fromOffset(10, 170),
		Size = UDim2.new(1, -20, 0, 28),
		Font = Theme.Fonts.title,
		TextSize = 24,
		TextColor3 = class.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = class.name,
		Parent = card,
	})
	Theme.label({
		Position = UDim2.fromOffset(10, 198),
		Size = UDim2.new(1, -20, 0, 18),
		TextSize = 14,
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = class.role,
		Parent = card,
	})
	Theme.label({
		Position = UDim2.fromOffset(10, 218),
		Size = UDim2.new(1, -20, 0, 34),
		TextSize = 12,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.subtext,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "\"" .. class.tagline .. "\"",
		Parent = card,
	})
	local statsFrame = Theme.make("Frame", {
		Position = UDim2.fromOffset(14, 256),
		Size = UDim2.new(1, -28, 0, 76),
		BackgroundTransparency = 1,
		Parent = card,
	})
	statPips(statsFrame, 0, "Health", class.statBars.health, Color3.fromRGB(230, 80, 80))
	statPips(statsFrame, 19, "Attack", class.statBars.attack, Color3.fromRGB(255, 170, 60))
	statPips(statsFrame, 38, "Speed", class.statBars.speed, Color3.fromRGB(90, 200, 255))
	statPips(statsFrame, 57, "Defense", class.statBars.defense, Color3.fromRGB(150, 150, 170))

	Theme.label({
		Position = UDim2.fromOffset(10, 336),
		Size = UDim2.new(1, -20, 0, 18),
		TextSize = 14,
		TextColor3 = class.fire.colorA,
		TextStrokeColor3 = class.fire.colorB,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "🔥 " .. class.fire.name,
		Parent = card,
	})
	Theme.label({
		Position = UDim2.fromOffset(12, 356),
		Size = UDim2.new(1, -24, 0, 62),
		TextSize = 12,
		Font = Theme.Fonts.body,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = class.description,
		Parent = card,
	})
	local button = Theme.button("Choose", class.colors.accent:Lerp(Color3.new(0, 0, 0), 0.35), function()
		choose(classId)
	end, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 38),
		TextSize = 18,
		Parent = card,
	})

	cards[classId] = { card = card, model = model, camera = camera, button = button, stroke = stroke, offset = index * 1.3 }
end

local function positionCamera(entry, angle: number)
	local cf, size = entry.model:GetBoundingBox()
	local center = cf.Position
	local dist = math.max(size.X, size.Z, size.Y) * 1.25 + 4
	local pos = center + Vector3.new(math.sin(angle) * dist, dist * 0.35, math.cos(angle) * dist)
	entry.camera.CFrame = CFrame.lookAt(pos, center)
end

function ClassSelect.show(newMode: string?)
	mode = newMode or "choose"
	frame.Visible = true
	App.Windows.close()
	local p = App.State.profile
	if mode == "transform" then
		local cost = transformCost()
		title.Text = "Transform Your Dragon"
		subtitle.Text = cost > 0 and string.format("Changing type costs %d gold. Your level and gear stay; skill points are refunded.", cost)
			or "Free up to level " .. Game.TRANSFORM_FREE_UNTIL_LEVEL .. "! Your level and gear stay; skill points are refunded."
		cancelButton.Visible = true
	else
		title.Text = "Choose Your Dragon"
		subtitle.Text = "Each dragon has its own look, fire, stats and skill tree. You can transform later at Elder Pyrrhus."
		cancelButton.Visible = false
	end
	for classId, entry in pairs(cards) do
		local current = mode == "transform" and p and p.class == classId
		entry.button.Text = current and "Current" or (mode == "transform" and "Transform" or "Choose")
		Theme.setButtonEnabled(entry.button, not current)
	end
	if not spinConnection then
		local t = 0
		spinConnection = RunService.RenderStepped:Connect(function(dt)
			t += dt
			for _, entry in pairs(cards) do
				positionCamera(entry, t * 0.6 + entry.offset)
			end
		end)
	end
end

function ClassSelect.hide()
	frame.Visible = false
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

function ClassSelect.isVisible(): boolean
	return frame.Visible
end

function ClassSelect.init(app)
	App = app
	frame = Theme.make("Frame", {
		Name = "ClassSelect",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 8, 20),
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 1,
		Parent = App.Windows.guis.Overlay,
	})
	Theme.make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(60, 30, 80), Color3.fromRGB(10, 10, 20)),
		Rotation = 90,
		Parent = frame,
	})
	title = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(800, 56),
		Font = Theme.Fonts.title,
		TextSize = 50,
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Text = "Choose Your Dragon",
		Parent = frame,
	})
	subtitle = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(900, 24),
		TextSize = 17,
		TextColor3 = C.subtext,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = frame,
	})
	local scroller = Theme.scroll(frame, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 134),
		Size = UDim2.new(1, -40, 0, 490),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
	})
	local row = Theme.make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = scroller,
	})
	Theme.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), Parent = row })
	Theme.list(row, 14, true)
	for i, classId in ipairs(Classes.Order) do
		buildCard(row, classId, i)
	end
	-- center the row when it fits
	local function recenter()
		local width = row.AbsoluteSize.X / (App.Windows.scale or 1)
		local avail = scroller.AbsoluteSize.X / (App.Windows.scale or 1)
		row.Position = UDim2.fromOffset(math.max(0, (avail - width) / 2), 0)
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(recenter)
	scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(recenter)

	cancelButton = Theme.button("Cancel", C.panel3, function()
		ClassSelect.hide()
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 632),
		Size = UDim2.fromOffset(160, 40),
		Visible = false,
		Parent = frame,
	})

	-- First time: show the picker and park the camera over town.
	local function check()
		local p = App.State.profile
		if p and not p.class and not frame.Visible then
			ClassSelect.show("choose")
		end
	end
	App.State.changed:Connect(check)
	check()

	RunService:BindToRenderStep("DragonMenuCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local p = App.State.profile
		local character = Players.LocalPlayer.Character
		if (not p or not p.class) and not character then
			camera.CameraType = Enum.CameraType.Scriptable
			local t = os.clock() * 0.05
			camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(t) * 120, 70, math.cos(t) * 120 + 20), Vector3.new(0, 10, 0))
		elseif camera.CameraType == Enum.CameraType.Scriptable and character then
			camera.CameraType = Enum.CameraType.Custom
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end)
end

return ClassSelect
