-- DPS meter for the training dummies: a panel over whichever dummy you're hitting, with your
-- damage per second, total damage and time. Only you see your numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local Training = {}
local App

local meters = {} -- [Model] = { gui, dps, total, time }
Training.hit = Signal.new() -- fired whenever you damage a dummy (the tutorial listens)

local function meterFor(dummy: Model)
	local m = meters[dummy]
	if m and m.gui.Parent then
		return m
	end
	local head = dummy:FindFirstChild("Head") or dummy.PrimaryPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "DPSMeter"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(190, 74)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local function label(name: string, y: number, h: number, size: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(6, y)
		l.Size = UDim2.new(1, -12, 0, h)
		l.Font = Enum.Font.FredokaOne
		l.TextSize = size
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.5
		l.Text = ""
		l.Parent = frame
		return l
	end
	label("Dps", 2, 34, 30, Color3.fromRGB(255, 215, 90))
	label("Info", 38, 30, 14, Color3.fromRGB(220, 215, 235))
	gui.Parent = App.Windows.guis.HUD.Parent
	m = { gui = gui, frame = frame }
	meters[dummy] = m
	return m
end

local function onStats(data)
	local dummy = data.dummy
	if typeof(dummy) ~= "Instance" or not dummy.Parent then
		return
	end
	local m = meterFor(dummy)
	m.gui.Enabled = true
	m.frame.Dps.Text = string.format("%s DPS", Util.formatNumber(data.dps))
	m.frame.Info.Text = string.format("%s damage in %ss%s", Util.formatNumber(data.total), Util.fmt(data.time), data.final and "  (final)" or "")
	m.frame.Dps.TextColor3 = data.final and Color3.fromRGB(140, 230, 120) or Color3.fromRGB(255, 215, 90)
	m.shownAt = os.clock()
	Training.hit:Fire(data)
	if data.final then
		local token = m.shownAt
		task.delay(8, function()
			if m.shownAt == token then
				m.gui.Enabled = false
			end
		end)
	end
end

function Training.init(app)
	App = app
	Remotes.event("DummyStats").OnClientEvent:Connect(onStats)
end

return Training
