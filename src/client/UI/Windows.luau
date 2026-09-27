-- Creates the ScreenGuis and manages the pop-up windows (only one open at a time).
-- All UI is designed for a 1100x700 screen and scaled with UIScale to fit.

local Players = game:GetService("Players")

local Windows = {
	guis = {},
	registry = {},
	current = nil,
}

local BASE = Vector2.new(1100, 700)

local function makeGui(name: string, order: number, ignoreInset: boolean)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = ignoreInset
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local vp = camera.ViewportSize
	local s = math.clamp(math.min(vp.X / BASE.X, vp.Y / BASE.Y), 0.55, 1.35)
	Windows.scale = s
	for _, gui in pairs(Windows.guis) do
		gui.Scale.Scale = s
	end
end

function Windows.init()
	Windows.guis.HUD = makeGui("DragonHUD", 1, false)
	Windows.guis.Windows = makeGui("DragonWindows", 5, false)
	Windows.guis.Overlay = makeGui("DragonOverlay", 10, true)
	Windows.guis.Top = makeGui("DragonTop", 20, true)
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		updateScale()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end)
end

-- Size of the virtual (unscaled) screen, useful for layout math.
function Windows.virtualSize(): Vector2
	local vp = workspace.CurrentCamera.ViewportSize
	local s = Windows.scale or 1
	return Vector2.new(vp.X / s, vp.Y / s)
end

function Windows.register(name: string, frame: GuiObject, onOpen, onClose)
	Windows.registry[name] = { frame = frame, onOpen = onOpen, onClose = onClose }
end

function Windows.open(name: string, ...)
	local entry = Windows.registry[name]
	if not entry then
		return
	end
	if Windows.current and Windows.current ~= name then
		Windows.close(Windows.current)
	end
	Windows.current = name
	entry.frame.Visible = true
	if entry.onOpen then
		entry.onOpen(...)
	end
end

function Windows.close(name: string?)
	name = name or Windows.current
	local entry = name and Windows.registry[name]
	if not entry then
		return
	end
	entry.frame.Visible = false
	if Windows.current == name then
		Windows.current = nil
	end
	if entry.onClose then
		entry.onClose()
	end
end

function Windows.toggle(name: string, ...)
	if Windows.current == name then
		Windows.close(name)
	else
		Windows.open(name, ...)
	end
end

function Windows.isOpen(name: string): boolean
	return Windows.current == name
end

return Windows
