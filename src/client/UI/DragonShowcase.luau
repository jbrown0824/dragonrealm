-- The legendary dragons' showcase window: a spinning 3D model, what makes the dragon special (its
-- own primary attack, its signature, the level-10 ability and skill tree) and one button: its
-- Robux price until you own it (App.Store.buy), then "Become a ..." (a free Transform). Tabs
-- switch between the legendary dragons.
-- Opened by the showcase platforms in the town square (PanelPrompt `Panel = "DragonShowcase"`,
-- with the dragon as `DragonClass`) and from the Store's Legendary Dragons. Never by itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Abilities = require(Shared.Config.Abilities)
local Talents = require(Shared.Config.Talents)
local Game = require(Shared.Config.Game)
local StoreInfo = require(Shared.Config.Store)
local DragonBuilder = require(Shared.DragonBuilder)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local DragonShowcase = {}
local App

local window
local viewport, camera, nameLabel, roleLabel, taglineLabel, statsFrame, featureList, actionButton, noteLabel
local tabs = {} -- [classId] = button
local models = {} -- [classId] = Model (built once)
local current = nil -- the class shown
local spin = nil
local busy = false

local ROBUX_GREEN = Color3.fromRGB(40, 150, 70)
local BACKDROP = { Tidecaller = Color3.fromRGB(14, 40, 62), Solaris = Color3.fromRGB(70, 46, 18) }

-- The legendary dragons, in the Store's order.
local function legendary(): { string }
	local list = {}
	for _, key in ipairs(StoreInfo.DragonOrder) do
		table.insert(list, StoreInfo.Passes[key].dragon)
	end
	return list
end

local function owns(classId: string): boolean
	local class = Classes.get(classId)
	local p = App.State.profile
	return class.pass == nil or (p ~= nil and p.passes ~= nil and p.passes[class.pass] == true)
end

local function statPips(parent: Instance, y: number, label: string, value: number, color: Color3)
	Theme.label({ Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(64, 16), TextSize = 13, TextColor3 = C.subtext, Text = label, Parent = parent })
	for i = 1, 5 do
		local pip = Theme.make("Frame", {
			Position = UDim2.fromOffset(66 + (i - 1) * 20, y + 2),
			Size = UDim2.fromOffset(16, 12),
			BackgroundColor3 = i <= value and color or Color3.fromRGB(60, 55, 75),
			Parent = parent,
		})
		Theme.corner(pip, 3)
	end
end

-- One line of "what it does": an icon, a title and a sentence.
local function feature(order: number, icon: string, title: string, body: string, color: Color3?)
	local row = Theme.make("Frame", { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = C.panel2, LayoutOrder = order, Parent = featureList })
	Theme.corner(row, 8)
	Theme.label({ Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(40, 40), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Text = icon, Parent = row })
	Theme.label({ Position = UDim2.fromOffset(52, 4), Size = UDim2.new(1, -58, 0, 20), TextSize = 15, TextColor3 = color or C.accent, Text = title, Parent = row })
	Theme.label({ Position = UDim2.fromOffset(52, 24), Size = UDim2.new(1, -58, 0, 34), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.text, TextYAlignment = Enum.TextYAlignment.Top, Text = body, Parent = row })
end

local function showModel(classId: string)
	for id, model in pairs(models) do
		model.Parent = id == classId and viewport or nil
	end
	if not models[classId] then
		local model = DragonBuilder.build(classId, { anchored = true, noParticles = true })
		model:PivotTo(CFrame.new())
		model.Parent = viewport
		models[classId] = model
	end
	viewport.BackgroundColor3 = BACKDROP[classId] or Color3.fromRGB(35, 30, 50)
end

local function refreshButton()
	local class = Classes.get(current)
	local p = App.State.profile
	local pass = StoreInfo.Passes[class.pass]
	if p and p.class == current then
		actionButton.Text = "✅ You are a " .. class.name
		actionButton.BackgroundColor3 = C.panel3
		Theme.setButtonEnabled(actionButton, false)
		noteLabel.Text = "Transform back any time at Elder Pyrrhus."
	elseif owns(current) then
		actionButton.Text = "🐉 Become a " .. class.name .. " (free)"
		actionButton.BackgroundColor3 = class.colors.accent:Lerp(Color3.new(0, 0, 0), 0.4)
		Theme.setButtonEnabled(actionButton, true)
		noteLabel.Text = "It's yours! Your level and gear stay; skill points are refunded."
	else
		actionButton.Text = string.format("💎 Unlock for R$ %d", pass.robux)
		actionButton.BackgroundColor3 = ROBUX_GREEN
		Theme.setButtonEnabled(actionButton, true)
		noteLabel.Text = "Yours forever. Ask a grown-up before buying anything!"
	end
end

function DragonShowcase.show(classId: string?)
	local list = legendary()
	current = (classId and table.find(list, classId)) and classId or current or list[1]
	local class = Classes.get(current)
	for id, tab in pairs(tabs) do
		tab.BackgroundColor3 = id == current and Classes.get(id).colors.accent:Lerp(Color3.new(0, 0, 0), 0.35) or C.panel3
	end
	showModel(current)
	nameLabel.Text = class.icon .. " " .. class.name
	nameLabel.TextColor3 = class.colors.accent
	roleLabel.Text = class.role
	taglineLabel.Text = "\"" .. class.tagline .. "\""
	Theme.clear(statsFrame)
	statPips(statsFrame, 0, "Health", class.statBars.health, Color3.fromRGB(230, 80, 80))
	statPips(statsFrame, 18, "Attack", class.statBars.attack, Color3.fromRGB(255, 170, 60))
	statPips(statsFrame, 36, "Speed", class.statBars.speed, Color3.fromRGB(90, 200, 255))
	statPips(statsFrame, 54, "Defense", class.statBars.defense, Color3.fromRGB(150, 150, 170))

	Theme.clear(featureList)
	local primary = class.breath
	feature(1, primary.icon, primary.name .. "  (left click)", primary.desc, class.fire.colorA)
	local sig = Abilities.get(class.signature)
	feature(2, sig.icon, string.format("%s  (key 1, level %d)", sig.name, Game.SIGNATURE_LEVEL), sig.desc)
	local bonus = Abilities.get(class.bonus)
	feature(3, bonus.icon, string.format("%s  (extra skill at level %d)", bonus.name, Game.BONUS_LEVEL), bonus.desc, C.gold)
	local branches = {}
	for _, branch in ipairs(Talents[current]) do
		table.insert(branches, branch.icon .. " " .. branch.name)
	end
	feature(4, "🌟", "Its own skill tree", table.concat(branches, "   ") .. ". A little tougher and stronger than the free dragons, too.")
	refreshButton()
end

local function act()
	if busy or not current then
		return
	end
	local class = Classes.get(current)
	if not owns(current) then
		App.Store.buy("pass", class.pass)
		return
	end
	busy = true
	local ok, err = Remotes.func("Transform"):InvokeServer(current)
	busy = false
	if ok then
		App.Windows.close("DragonShowcase")
	elseif err then
		App.Windows.notify(err, C.bad, "🐉")
	end
end

function DragonShowcase.open(classId: string?)
	App.Windows.open("DragonShowcase", classId)
end

function DragonShowcase.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "💎 Legendary Dragons", Vector2.new(760, 520))
	close.Activated:Connect(function()
		App.Windows.close("DragonShowcase")
	end)

	-- tabs along the top
	local tabRow = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = content })
	Theme.list(tabRow, 8, true)
	for i, classId in ipairs(legendary()) do
		local class = Classes.get(classId)
		tabs[classId] = Theme.button(class.icon .. " " .. class.name, C.panel3, function()
			DragonShowcase.show(classId)
		end, { Size = UDim2.fromOffset(150, 32), TextSize = 15, LayoutOrder = i, Parent = tabRow })
	end

	-- left: the dragon, its name and stats
	viewport = Theme.make("ViewportFrame", {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.fromOffset(300, 220),
		BackgroundColor3 = Color3.fromRGB(35, 30, 50),
		Ambient = Color3.fromRGB(180, 175, 185),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-1, -1.5, -0.5),
		Parent = content,
	})
	Theme.corner(viewport, 10)
	camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	nameLabel = Theme.label({ Position = UDim2.fromOffset(0, 268), Size = UDim2.fromOffset(300, 30), Font = Theme.Fonts.title, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Text = "", Parent = content })
	roleLabel = Theme.label({ Position = UDim2.fromOffset(0, 298), Size = UDim2.fromOffset(300, 18), TextSize = 14, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Center, Text = "", Parent = content })
	taglineLabel = Theme.label({ Position = UDim2.fromOffset(10, 318), Size = UDim2.fromOffset(280, 32), TextSize = 12, Font = Enum.Font.GothamMedium, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Center, Text = "", Parent = content })
	statsFrame = Theme.make("Frame", { Position = UDim2.fromOffset(60, 356), Size = UDim2.fromOffset(180, 72), BackgroundTransparency = 1, Parent = content })

	-- right: what it does, and the one button
	featureList = Theme.scroll(content, { Position = UDim2.fromOffset(312, 42), Size = UDim2.new(1, -312, 1, -120) })
	Theme.list(featureList, 6)
	actionButton = Theme.button("", ROBUX_GREEN, act, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -24),
		Size = UDim2.new(1, -320, 0, 46),
		Font = Theme.Fonts.title,
		TextSize = 20,
		Parent = content,
	})
	noteLabel = Theme.label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, 0), Size = UDim2.new(1, -320, 0, 20), TextSize = 12, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Center, Text = "", Parent = content })

	App.Windows.register("DragonShowcase", window, function(classId)
		DragonShowcase.show(classId)
		if not spin then
			local t = 0
			spin = RunService.RenderStepped:Connect(function(dt)
				t += dt
				local model = current and models[current]
				if model then
					local cf, size = model:GetBoundingBox()
					local dist = math.max(size.X, size.Z, size.Y) * 1.05 + 4
					local a = t * 0.5 + 2.4
					camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(math.sin(a) * dist, dist * 0.3, math.cos(a) * dist), cf.Position)
				end
			end)
		end
	end, function()
		if spin then
			spin:Disconnect()
			spin = nil
		end
	end)
	App.State.changed:Connect(function()
		if window.Visible and current then
			refreshButton() -- (just bought it, or just became one)
		end
	end)
end

return DragonShowcase
