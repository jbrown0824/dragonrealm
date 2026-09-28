-- The 🎁 Codes window: type a promo code for a free reward (or the admin code to unlock the
-- admin panel). The server decides what every code does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Codes = {}
local App

local window, box, status
local busy = false

local function redeem()
	if busy or box.Text == "" then
		return
	end
	busy = true
	status.Text = "Checking..."
	status.TextColor3 = C.subtext
	task.spawn(function()
		local ok, message = Remotes.func("RedeemCode"):InvokeServer(box.Text)
		busy = false
		status.Text = message or (ok and "Done!" or "That didn't work.")
		status.TextColor3 = ok and C.good or C.bad
		if ok then
			box.Text = ""
			App.Sfx.play("Quest")
		end
	end)
end

function Codes.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🎁 Codes", Vector2.new(460, 250))
	close.Activated:Connect(function()
		App.Windows.close("Codes")
	end)
	Theme.label({ Size = UDim2.new(1, 0, 0, 36), TextSize = 14, TextColor3 = C.subtext, Text = "Got a code? Type it in for a free reward. Each code works once per dragon.", Parent = content })
	box = Theme.make("TextBox", {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, -130, 0, 44),
		BackgroundColor3 = C.panel2,
		TextColor3 = C.text,
		PlaceholderText = "Enter code",
		PlaceholderColor3 = C.subtext,
		Font = Theme.Fonts.bold,
		TextSize = 20,
		Text = "",
		ClearTextOnFocus = false,
		Parent = content,
	})
	Theme.corner(box, 8)
	Theme.pad(box, 8)
	box.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	Theme.button("Redeem", Color3.fromRGB(70, 140, 80), redeem, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 44), Size = UDim2.fromOffset(120, 44), Parent = content })
	status = Theme.label({ Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 40), TextSize = 15, Text = "", Parent = content })
	App.Windows.register("Codes", window, function()
		status.Text = ""
	end)

	Remotes.event("AdminState").OnClientEvent:Connect(function(isAdmin)
		App.HUD.setAdmin(isAdmin == true)
		if isAdmin then
			App.Windows.close("Codes")
			App.Windows.open("Admin")
		end
	end)
end

return Codes
