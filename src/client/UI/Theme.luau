-- Colors, fonts and small helpers for building UI in code.

local Theme = {}

Theme.Colors = {
	bg = Color3.fromRGB(18, 14, 26),
	panel = Color3.fromRGB(30, 24, 44),
	panel2 = Color3.fromRGB(44, 36, 64),
	panel3 = Color3.fromRGB(60, 50, 86),
	accent = Color3.fromRGB(255, 190, 70),
	accentDark = Color3.fromRGB(190, 120, 30),
	text = Color3.fromRGB(245, 240, 255),
	subtext = Color3.fromRGB(185, 175, 210),
	good = Color3.fromRGB(110, 220, 110),
	bad = Color3.fromRGB(240, 90, 90),
	hp = Color3.fromRGB(230, 70, 70),
	xp = Color3.fromRGB(170, 110, 255),
	stamina = Color3.fromRGB(80, 200, 255),
	gold = Color3.fromRGB(255, 210, 70),
	blue = Color3.fromRGB(80, 150, 255),
}

Theme.Fonts = {
	title = Enum.Font.FredokaOne,
	bold = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
}

-- Create an instance: Theme.make("Frame", { Size = ..., Parent = ... }, { children... })
function Theme.make(className: string, props, children)
	local inst = Instance.new(className)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(parent: Instance, radius: number?)
	return Theme.make("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return Theme.make("UIStroke", {
		Color = color or Color3.fromRGB(90, 75, 120),
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Theme.pad(parent: Instance, px: number)
	return Theme.make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		Parent = parent,
	})
end

function Theme.list(parent: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?)
	return Theme.make("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function Theme.label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.bold,
		TextColor3 = Theme.Colors.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return Theme.make("TextLabel", defaults)
end

function Theme.button(text: string, color: Color3?, onClick, props)
	local base = color or Theme.Colors.panel3
	local defaults = {
		Text = text,
		Font = Theme.Fonts.bold,
		TextSize = 16,
		TextColor3 = Theme.Colors.text,
		BackgroundColor3 = base,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(120, 36),
	}
	for k, v in pairs(props or {}) do
		defaults[k] = v
	end
	local button = Theme.make("TextButton", defaults)
	Theme.corner(button, 8)
	button.MouseEnter:Connect(function()
		if button.Active then
			button.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.15)
		end
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = base
	end)
	if onClick then
		button.Activated:Connect(function()
			if button.Active then
				onClick()
			end
		end)
	end
	return button
end

function Theme.setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.TextTransparency = enabled and 0 or 0.5
	button.BackgroundTransparency = enabled and 0 or 0.4
end

-- A progress bar. Returns container, fill, label.
function Theme.bar(parent: Instance, color: Color3, size: UDim2, position: UDim2?)
	local container = Theme.make("Frame", {
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Color3.fromRGB(20, 16, 28),
		BorderSizePixel = 0,
		Parent = parent,
	})
	Theme.corner(container, 6)
	Theme.stroke(container, Color3.fromRGB(0, 0, 0), 1.5, 0.3)
	local fill = Theme.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = container,
	})
	Theme.corner(fill, 6)
	Theme.make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = fill,
	})
	local label = Theme.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
		Text = "",
		Parent = container,
	})
	return container, fill, label
end

-- A centered window with a title bar and close button. Returns frame, content, closeButton.
function Theme.window(parent: Instance, title: string, size: Vector2)
	local frame = Theme.make("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.Colors.panel,
		Active = true, -- clicks on a window never fall through to the HUD (minimap) behind it
		Visible = false,
		Parent = parent,
	})
	Theme.corner(frame, 14)
	Theme.stroke(frame, Theme.Colors.accentDark, 2.5)
	local titleBar = Theme.make("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Theme.Colors.panel2,
		Parent = frame,
	})
	Theme.corner(titleBar, 14)
	Theme.label({
		Name = "Title",
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -70, 1, 0),
		Font = Theme.Fonts.title,
		TextSize = 24,
		TextColor3 = Theme.Colors.accent,
		Text = title,
		Parent = titleBar,
	})
	-- A round red "X" (plain letter: symbol glyphs like ✕ can show up as empty boxes)
	local close = Theme.button("X", Color3.fromRGB(200, 60, 70), nil, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Font = Theme.Fonts.title,
		TextSize = 22,
		Parent = titleBar,
	})
	close:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	Theme.stroke(close, Color3.fromRGB(255, 255, 255), 2, 0.3)
	local content = Theme.make("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Theme.pad(content, 12)
	return frame, content, close, titleBar
end

function Theme.scroll(parent: Instance, props)
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.accentDark,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}
	for k, v in pairs(props or {}) do
		defaults[k] = v
	end
	local scroll = Theme.make("ScrollingFrame", defaults)
	-- Room around the rows so their outlines (drawn outside each row) aren't clipped at the edges.
	Theme.make("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		Parent = scroll,
	})
	return scroll
end

function Theme.clear(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Theme.colorHex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

return Theme
