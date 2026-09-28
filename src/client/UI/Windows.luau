-- Creates the ScreenGuis and manages the pop-up windows (only one open at a time).
-- All UI is designed for a 1100x700 screen and scaled with UIScale to fit. Each window also
-- shrinks itself (a "Fit" UIScale) if it would still be too big for the screen.
--
-- Phones and tablets (touch, no keyboard) get `Windows.mobile`: the HUD uses its own, larger
-- scale (phones are short, and a HUD scaled like the windows was too small to read), and the
-- touch controls live in an unscaled "DragonTouch" gui positioned in screen points, next to
-- Roblox's own jump button.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Windows = {
	guis = {},
	registry = {},
	current = nil,
}

local BASE = Vector2.new(1100, 700)
local MOBILE_HUD = Vector2.new(900, 420) -- the HUD's design size on phones (below the top bar)
local TOP_BAR = 58

local function makeGui(name: string, order: number, ignoreInset: boolean, unscaled: boolean?)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = ignoreInset
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	if not unscaled then
		local scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Parent = gui
	end
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
	Windows.hudScale = s
	if Windows.mobile and math.min(vp.X, vp.Y) <= 500 then
		-- phones (tablets have room for the normal scale)
		Windows.hudScale = math.clamp(math.min(vp.X / MOBILE_HUD.X, (vp.Y - TOP_BAR) / MOBILE_HUD.Y), 0.55, 1.2)
	end
	for name, gui in pairs(Windows.guis) do
		local scale = gui:FindFirstChild("Scale")
		if scale then
			scale.Scale = name == "HUD" and Windows.hudScale or s
		end
	end
	if Windows.current then
		Windows.fit(Windows.current)
	end
end

function Windows.init()
	Windows.mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	Theme.mobile = Windows.mobile
	Windows.guis.HUD = makeGui("DragonHUD", 1, false)
	Windows.guis.Windows = makeGui("DragonWindows", 5, false)
	Windows.guis.Overlay = makeGui("DragonOverlay", 10, true)
	Windows.guis.Top = makeGui("DragonTop", 20, true)
	-- Round buttons in Roblox's top bar row, sized like Roblox's own (so not scaled with the UI).
	Windows.guis.TopBar = makeGui("DragonTopBar", 3, true, true)
	if Windows.mobile then
		Windows.guis.Touch = makeGui("DragonTouch", 2, true, true)
	end
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

-- Shrink a window that doesn't fit the screen (small or short screens).
function Windows.fit(name: string)
	local entry = Windows.registry[name]
	if not entry then
		return
	end
	local frame = entry.frame
	local fit = frame:FindFirstChild("Fit")
	if not fit then
		fit = Instance.new("UIScale")
		fit.Name = "Fit"
		fit.Parent = frame
	end
	local camera = workspace.CurrentCamera
	local s = Windows.scale or 1
	local vw, vh = camera.ViewportSize.X / s, (camera.ViewportSize.Y - TOP_BAR) / s
	local size = frame.Size
	local w, h = size.X.Offset + size.X.Scale * vw, size.Y.Offset + size.Y.Scale * vh
	fit.Scale = math.min(1, (vw - 12) / math.max(1, w), (vh - 12) / math.max(1, h))
end

Windows.toast = nil -- set by Notifications.init

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
	Windows.fit(name)
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

-- Tell the player something about what they just did in a window: it shows in the open
-- window's status banner (toasts sit behind windows), or as a toast when no window is open.
function Windows.notify(text: string, color: Color3?, icon: string?)
	local entry = Windows.current and Windows.registry[Windows.current]
	if entry and entry.frame.Visible and Theme.showBanner(entry.frame, (icon and (icon .. "  ") or "") .. text, color) then
		return
	end
	if Windows.toast then
		Windows.toast(text, color, icon)
	end
end

return Windows
