-- The always-on HUD: player card, health / stamina / hunger / XP bars, ability bar with
-- cooldowns, menu buttons, quest tracker, garden reminder, and touch controls on mobile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Abilities = require(Shared.Config.Abilities)
local Quests = require(Shared.Config.Quests)
local Game = require(Shared.Config.Game)
local QuestUtil = require(Shared.QuestUtil)
local TalentUtil = require(Shared.TalentUtil)
local StoreInfo = require(Shared.Config.Store)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local HUD = {}
local App

local root
local card = {}
local menuButtons = {}
local gardenLabel
local bars = {}
local slots = {}
local tooltip
local tracker
local skillBadge, petBadge
local mobile = {}
local starterAd

-- Mouse = breath, Q = fireball, 1 = your dragon's own ability, 2-5 = your skill tree loadout.
local SLOT_KEYS = { "Mouse", "Q", "1", "2", "3", "4", "5" }

local function abilityForSlot(i: number): string?
	local p = App.State.profile
	local list = p and p.stats and p.stats.abilities
	if not list then
		return nil
	end
	local class = Classes.get(p.class)
	local signature = class and class.signature
	if i == 1 then
		return table.find(list, "Breath") and "Breath" or nil
	elseif i == 2 then
		return table.find(list, "Fireball") and "Fireball" or nil
	elseif i == 3 then
		return signature and table.find(list, signature) and signature or nil
	end
	return TalentUtil.resolveLoadout(list, p.loadout, signature)[i - 3]
end
HUD.abilityForSlot = abilityForSlot

-- Eggs you found (or bought in the Store) that are waiting to hatch: the Pets menu badge and the
-- Eggs tab both show this.
function HUD.eggsWaiting(p): number
	local count = 0
	for _, n in pairs(p and p.eggs or {}) do
		count += n
	end
	return count
end

local function buildCard()
	local frame = Theme.make("Frame", {
		Name = "Card",
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(270, 92),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Parent = root,
	})
	Theme.corner(frame, 12)
	Theme.stroke(frame, C.accentDark, 2, 0.3)
	card.icon = Theme.label({
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(52, 52),
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "🐉",
		Parent = frame,
	})
	card.name = Theme.label({
		Position = UDim2.fromOffset(66, 6),
		Size = UDim2.fromOffset(196, 24),
		Font = Theme.Fonts.title,
		TextSize = 20,
		Text = Players.LocalPlayer.DisplayName,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	card.class = Theme.label({
		Position = UDim2.fromOffset(66, 30),
		Size = UDim2.fromOffset(196, 20),
		TextSize = 15,
		TextColor3 = C.accent,
		Text = "",
		Parent = frame,
	})
	card.gold = Theme.label({
		Position = UDim2.fromOffset(10, 64),
		Size = UDim2.fromOffset(120, 22),
		TextSize = 16,
		TextColor3 = C.gold,
		Text = "💰 0",
		Parent = frame,
	})
	card.glory = Theme.label({
		Position = UDim2.fromOffset(120, 64),
		Size = UDim2.fromOffset(70, 22),
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 130, 120),
		Text = "⚔️ 0",
		Parent = frame,
	})
	card.power = Theme.label({
		Position = UDim2.fromOffset(186, 64),
		Size = UDim2.fromOffset(84, 22),
		TextSize = 16,
		TextColor3 = C.blue,
		Text = "⚡ 0",
		Parent = frame,
	})
	card.gold.Size = UDim2.fromOffset(108, 22) -- (it overlapped Glory, which confused the hover tips)
	-- a Gold Rush (💎 Store) counting down, in the gap under the class line
	card.rush = Theme.label({
		Position = UDim2.fromOffset(66, 49),
		Size = UDim2.fromOffset(196, 14),
		TextSize = 11,
		TextColor3 = C.gold,
		TextWrapped = false,
		Text = "",
		Visible = false,
		Parent = frame,
	})

	-- What the three numbers mean: hover them (tap on phones) for a tip under the card.
	local tip = Theme.make("Frame", {
		Name = "CardTip",
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.fromOffset(270, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 12,
		Parent = root,
	})
	Theme.corner(tip, 10)
	Theme.stroke(tip, C.accentDark, 1.5)
	Theme.pad(tip, 8)
	Theme.label({ Name = "Title", Size = UDim2.new(1, 0, 0, 20), TextSize = 16, TextColor3 = C.accent, ZIndex = 13, Parent = tip })
	Theme.label({ Name = "Body", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, Font = Theme.Fonts.body, TextColor3 = C.subtext, ZIndex = 13, Parent = tip })
	card.tip = tip
	local showing = nil
	local function hint(target: GuiObject, title: string, body: string)
		local function show()
			showing = target
			tip.Title.Text = title
			tip.Body.Text = body
			tip.Visible = true
		end
		target.MouseEnter:Connect(show)
		target.MouseLeave:Connect(function()
			if showing == target then
				showing = nil
				tip.Visible = false
			end
		end)
		target.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				show()
				task.delay(4, function()
					if showing == target then
						showing = nil
						tip.Visible = false
					end
				end)
			end
		end)
	end
	hint(card.gold, "💰 Gold", "Earned from fights, quests, chests and crops. Spend it at the town shops and the Hatchery.")
	hint(card.glory, "⚔️ Glory", "Your PvP score. Win a fight against another player's dragon in the Battle Zone (north end of town) for +1, or +3 for ending a streak of 3+. Only PvP wins count, so it stays at 0 until then.")
	hint(card.power, "⚡ Power", "Your dragon's overall strength: attack, crits, health and defense from gear, skills, pets and potions, in one number. Higher is stronger.")
end

local function buildBars()
	local width = 470
	local holder = Theme.make("Frame", {
		Name = "Bars",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.fromOffset(width, 56),
		BackgroundTransparency = 1,
		Parent = root,
	})
	bars.hp, bars.hpFill, bars.hpText = Theme.bar(holder, C.hp, UDim2.fromOffset(width, 22))
	bars.hpText.TextSize = 14
	bars.stamina, bars.staminaFill, bars.staminaText = Theme.bar(holder, C.stamina, UDim2.fromOffset(width, 10), UDim2.fromOffset(0, 26))
	bars.staminaText.TextSize = 9
	-- Hunger: click it (or press G) to eat something from your food bag.
	bars.hunger, bars.hungerFill, bars.hungerText = Theme.bar(holder, Color3.fromRGB(230, 150, 70), UDim2.fromOffset(width, 14), UDim2.fromOffset(0, 40))
	bars.hungerText.TextSize = 11
	local eatButton = Theme.make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 4,
		Parent = bars.hunger,
	})
	eatButton.Activated:Connect(function()
		HUD.eat()
	end)

	bars.xp, bars.xpFill, bars.xpText = Theme.bar(root, C.xp, UDim2.new(0, width, 0, 14), UDim2.new(0.5, -width / 2, 1, -18))
	bars.xpText.TextSize = 11
end

local function buildAbilityBar()
	local size, gap = 70, 8
	local count = #SLOT_KEYS
	local total = count * size + (count - 1) * gap
	local holder = Theme.make("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(total, size),
		BackgroundTransparency = 1,
		Parent = root,
	})
	for i = 1, count do
		local button = Theme.make("TextButton", {
			Name = "Slot" .. i,
			Position = UDim2.fromOffset((i - 1) * (size + gap), 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = C.panel2,
			AutoButtonColor = false,
			Text = "",
			Parent = holder,
		})
		Theme.corner(button, 12)
		local stroke = Theme.stroke(button, C.accentDark, 2)
		local icon = Theme.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 34,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "",
			Parent = button,
		})
		local cd = Theme.make("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 2,
			Parent = button,
		})
		Theme.corner(cd, 12)
		local cdText = Theme.label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			ZIndex = 3,
			Text = "",
			Parent = button,
		})
		local key = Theme.label({
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.fromOffset(40, 16),
			TextSize = 12,
			TextColor3 = C.accent,
			TextStrokeTransparency = 0.3,
			Text = SLOT_KEYS[i],
			ZIndex = 4,
			Parent = button,
		})
		local note = Theme.label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.new(1, -4, 0, 16),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			Text = "",
			ZIndex = 4,
			Parent = button,
		})
		local slot = { button = button, icon = icon, cd = cd, cdText = cdText, key = key, note = note, stroke = stroke, index = i }
		slots[i] = slot

		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local id = abilityForSlot(i)
				if id then
					if id == "Breath" then
						App.Combat.setBreathHeld(true, input)
					else
						App.Combat.cast(id)
					end
				end
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if abilityForSlot(i) == "Breath" then
					App.Combat.setBreathHeld(false)
				end
			end
		end)
		button.MouseEnter:Connect(function()
			local id = abilityForSlot(i)
			local a = id and Abilities.get(id)
			if not a then
				-- explain empty slots
				local p = App.State.profile
				local class = p and Classes.get(p.class)
				if i == 3 and class and p.level < Game.SIGNATURE_LEVEL then
					local sig = Abilities.get(class.signature)
					tooltip.Title.Text = "🔒 " .. sig.icon .. " " .. sig.name .. " (level " .. Game.SIGNATURE_LEVEL .. ")"
					tooltip.Body.Text = sig.desc
				else
					tooltip.Title.Text = "🌟 Empty slot"
					tooltip.Body.Text = "Learn new abilities in your skill tree (press K). Look for the big icons in each branch."
				end
				tooltip.Visible = true
			elseif a then
				local p = App.State.profile
				local fire = id == "Breath" and p and Classes.get(p.class)
				tooltip.Title.Text = (a.icon or "") .. " " .. (fire and fire.fire.name or a.name)
				tooltip.Body.Text = a.desc
				tooltip.Visible = true
			end
		end)
		button.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
	end

	tooltip = Theme.make("Frame", {
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(360, 74),
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	Theme.corner(tooltip, 10)
	Theme.stroke(tooltip, C.accentDark, 1.5)
	Theme.pad(tooltip, 8)
	Theme.label({ Name = "Title", Size = UDim2.new(1, 0, 0, 20), TextSize = 17, TextColor3 = C.accent, ZIndex = 11, Parent = tooltip })
	Theme.label({ Name = "Body", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 36), TextSize = 13, Font = Theme.Fonts.body, TextColor3 = C.subtext, ZIndex = 11, Parent = tooltip })
end

local function buildMenu()
	local holder = Theme.make("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(64, 600),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Theme.list(holder, 6)
	local entries = {
		{ id = "skills", icon = "🌟", label = "Skills [K]", action = function() App.Windows.toggle("SkillTree") end },
		{ id = "bag", icon = "🎒", label = "Bag [B]", action = function() App.Windows.toggle("Inventory") end },
		{ id = "pets", icon = "🐲", label = "Pets [P]", action = function() App.Windows.toggle("Pets") end },
		{ id = "quests", icon = "📜", label = "Quests [J]", action = function() App.Windows.toggle("QuestLog") end },
		{ id = "collection", icon = "📖", label = "Collection [L]", action = function() App.Windows.toggle("Collection") end },
		{ id = "home", icon = "🏠", label = "Home [H]", action = function() HUD.goHome() end },
		{ id = "admin", icon = "🛠️", label = "Admin", action = function() App.Windows.toggle("Admin") end },
	}
	for i, e in ipairs(entries) do
		local b = Theme.button(e.icon, C.panel2, e.action, {
			Size = UDim2.fromOffset(58, 58),
			TextSize = 28,
			LayoutOrder = i,
			Parent = holder,
		})
		menuButtons[e.id] = b
		if e.id == "admin" then
			b.Visible = false
		end
		Theme.stroke(b, C.accentDark, 2, 0.2)
		Theme.label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, -6, 0.5, 0),
			Size = UDim2.fromOffset(90, 18),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0.4,
			Text = e.label,
			Parent = b,
		})
		if e.id == "skills" then
			skillBadge = Theme.badge(b) -- unspent skill points
		elseif e.id == "pets" then
			petBadge = Theme.badge(b) -- eggs waiting to hatch
		end
	end
end

-- Round buttons at the top right, in the same row as Roblox's own top bar buttons: the Robux
-- store, codes and help. They're sized from the top bar inset, so they line up with Roblox's.
local function buildTopBar()
	local gui = App.Windows.guis.TopBar
	local inset = 58
	local ok, topLeft = pcall(function()
		return game:GetService("GuiService"):GetGuiInset()
	end)
	if ok and typeof(topLeft) == "Vector2" and topLeft.Y > 0 then
		inset = topLeft.Y
	end
	local size = math.clamp(inset - 14, 30, 44)
	local holder = Theme.make("Frame", {
		Name = "TopButtons",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, math.floor((inset - size) / 2)),
		Size = UDim2.fromOffset(3 * (size + 8), size),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local buttons = {
		{ id = "store", icon = "💎", color = Color3.fromRGB(40, 150, 70), transparency = 0, action = function() App.Windows.toggle("Store") end },
		{ id = "codes", icon = "🎁", action = function() App.Windows.toggle("Codes") end },
		{ id = "help", icon = "❓", action = function() App.Windows.toggle("Help") end },
	}
	for i, entry in ipairs(buttons) do
		local b = Theme.roundButton(entry.icon, entry.action, {
			Name = entry.id,
			Position = UDim2.fromOffset((i - 1) * (size + 8), 0),
			Size = UDim2.fromOffset(size, size),
			TextSize = math.floor(size * 0.5),
			BackgroundColor3 = entry.color or Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = entry.transparency or 0.35,
			Parent = holder,
		})
		if entry.color then
			Theme.stroke(b, Color3.fromRGB(255, 230, 120), 2, 0.1)
		end
		menuButtons[entry.id] = b
	end
end

-- A "Starter Pack" button under the player card until you buy it or reach Store.STARTER_MAX_LEVEL.
-- Its green price tag says up front that it costs Robux.
local function buildStarterAd()
	starterAd = Theme.button("🎁 Starter Pack", Color3.fromRGB(200, 90, 40), function()
		App.Store.open("StarterPack")
	end, {
		Name = "StarterAd",
		Position = UDim2.fromOffset(12, 132),
		Size = UDim2.fromOffset(230, 40),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		Visible = false,
		Parent = root,
	})
	Theme.make("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = starterAd })
	Theme.stroke(starterAd, Color3.fromRGB(255, 230, 120), 2.5, 0)
	local tag = Theme.label({
		Name = "Price",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(64, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(40, 150, 70),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "R$ " .. StoreInfo.Products.StarterPack.robux,
		ZIndex = 2,
		Parent = starterAd,
	})
	Theme.corner(tag, 8)
	-- a gentle pulse so it gets noticed
	task.spawn(function()
		local t = 0
		while true do
			task.wait(0.05)
			t += 0.05
			if starterAd.Visible then
				starterAd.UIStroke.Transparency = 0.5 + math.sin(t * 4) * 0.5
			end
		end
	end)
end

local function buildTracker()
	tracker = Theme.make("Frame", {
		Name = "QuestTracker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -86, 0, 236), -- under the minimap
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	})
	Theme.list(tracker, 4)
end

-- Phones and tablets: the ability buttons move into a thumb cluster around Roblox's jump button
-- (in the unscaled Touch gui, so positions are in screen points like Roblox's own controls),
-- the bars go to the top center, and the rest of the HUD tightens up.
local function mobileLayout()
	local touch = App.Windows.guis.Touch
	local vp = workspace.CurrentCamera.ViewportSize
	local small = math.min(vp.X, vp.Y) <= 500
	local f = small and 1 or 1.6 -- tablets get Roblox's big jump button, so everything grows
	-- Roblox's jump button: 70 points, 95 from the right and 90 from the bottom (small screens)
	local cluster = Theme.make("Frame", { Name = "AbilityCluster", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(330 * f, 220 * f), BackgroundTransparency = 1, Parent = touch })
	local spots = {
		{ 72, 330 - 177, 220 - 86 }, -- breath, left of the jump button
		{ 58, 330 - 243, 220 - 78 }, -- Q
		{ 58, 330 - 309, 220 - 78 }, -- 1
		{ 54, 330 - 265, 220 - 154 }, -- 2
		{ 54, 330 - 203, 220 - 154 }, -- 3
		{ 54, 330 - 141, 220 - 154 }, -- 4
		{ 54, 330 - 79, 220 - 154 }, -- 5
	}
	for i, slot in ipairs(slots) do
		local spot = spots[i]
		slot.button.Parent = cluster
		slot.button.Position = UDim2.fromOffset(spot[2] * f, spot[3] * f)
		slot.button.Size = UDim2.fromOffset(spot[1] * f, spot[1] * f)
		slot.button:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
		slot.icon.TextSize = math.floor(spot[1] * f * 0.5)
		slot.cdText.TextSize = math.floor(spot[1] * f * 0.34)
		slot.key.Visible = false
	end
	root:FindFirstChild("Abilities").Visible = false
	-- bars and XP along the top, between the player card and the minimap
	local barsHolder = root:FindFirstChild("Bars")
	barsHolder.AnchorPoint = Vector2.new(0.5, 0)
	barsHolder.Position = UDim2.new(0.5, 0, 0, 6)
	bars.xp.Position = UDim2.new(0.5, -235, 0, 64)
	gardenLabel.AnchorPoint = Vector2.new(0.5, 0)
	gardenLabel.Position = UDim2.new(0.5, 0, 0, 82)
	gardenLabel.TextXAlignment = Enum.TextXAlignment.Center
	-- the menu becomes a 2-column grid on the left, under the player card (Roblox's jump button
	-- and your thumb live on the right), without the key labels (there's no keyboard)
	local menu = root:FindFirstChild("Menu")
	menu:FindFirstChildOfClass("UIListLayout"):Destroy()
	Theme.make("UIGridLayout", { CellSize = UDim2.fromOffset(50, 50), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
	menu.AnchorPoint = Vector2.new(0, 0)
	menu.Position = UDim2.fromOffset(12, 196)
	menu.Size = UDim2.fromOffset(106, 220)
	for _, b in pairs(menuButtons) do
		if b.Parent == menu then
			b.TextSize = 24
			for _, child in ipairs(b:GetChildren()) do
				if child:IsA("TextLabel") and child.Name ~= "Badge" then
					child.Visible = false
				end
			end
		end
	end
	-- quests: under the player card, above the menu (two at most)
	tracker.AnchorPoint = Vector2.new(0, 0)
	tracker.Position = UDim2.fromOffset(12, 104)
	tracker.Size = UDim2.fromOffset(270, 0)
	starterAd.Position = UDim2.fromOffset(128, 196)
	tooltip.Visible = false
end

local function buildMobile()
	if not UserInputService.TouchEnabled then
		return
	end
	local cluster = App.Windows.guis.Touch and App.Windows.guis.Touch:FindFirstChild("AbilityCluster")
	if cluster then
		-- phones: Fly above the jump button, Up / Down beside it while flying
		local f = cluster.Size.X.Offset / 330
		local function place(button, x, y)
			button.Position = UDim2.fromOffset(x * f, y * f)
			button.Size = UDim2.fromOffset(62 * f, 44 * f)
			button.TextSize = math.floor(15 * f)
			button.Parent = cluster
		end
		mobile.fly = Theme.button("🦅 Fly", C.blue, function()
			App.Movement.toggleFlight()
		end, {})
		mobile.up = Theme.button("⬆️ Up", C.panel3, nil, { Visible = false })
		mobile.down = Theme.button("⬇️ Down", C.panel3, nil, { Visible = false })
		place(mobile.fly, 251, 12)
		place(mobile.up, 183, 12)
		place(mobile.down, 115, 12)
	else
		local holder = Theme.make("Frame", {
			Name = "Touch",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -170, 1, -120),
			Size = UDim2.fromOffset(80, 200),
			BackgroundTransparency = 1,
			Parent = root,
		})
		mobile.fly = Theme.button("🦅 Fly", C.blue, function()
			App.Movement.toggleFlight()
		end, { Size = UDim2.fromOffset(76, 50), Position = UDim2.fromOffset(0, 140), Parent = holder })
		mobile.up = Theme.button("⬆️ Up", C.panel3, nil, { Size = UDim2.fromOffset(76, 50), Position = UDim2.fromOffset(0, 20), Parent = holder, Visible = false })
		mobile.down = Theme.button("⬇️ Down", C.panel3, nil, { Size = UDim2.fromOffset(76, 50), Position = UDim2.fromOffset(0, 80), Parent = holder, Visible = false })
	end
	for button, dir in pairs({ [mobile.up] = 1, [mobile.down] = -1 }) do
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				App.Movement.setVertical(dir)
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				App.Movement.setVertical(0)
			end
		end)
	end
end

function HUD.eat()
	task.spawn(function()
		local ok, err = Remotes.func("EatFood"):InvokeServer(nil)
		if not ok and err then
			App.Notifications.toast(err, Color3.fromRGB(255, 190, 110), "🍖")
		end
	end)
end

function HUD.setAdmin(isAdmin: boolean)
	if menuButtons.admin then
		menuButtons.admin.Visible = isAdmin
	end
end

-- The quest tracker sits under the minimap; it moves up when the minimap is hidden.
function HUD.setTrackerTop(y: number)
	if App.Windows.mobile then
		return -- phones keep quests on the left
	end
	tracker.Position = UDim2.new(1, -86, 0, y)
end

function HUD.goHome()
	task.spawn(function()
		local ok, err = Remotes.func("TeleportHome"):InvokeServer()
		if not ok and err then
			App.Notifications.toast(err, C.bad, "🏠")
		end
	end)
end

local function refreshTracker(p)
	Theme.clear(tracker)
	local order = {}
	for questId, progress in pairs(p.quests.active) do
		local quest = Quests.byId[questId]
		if quest then
			table.insert(order, { quest = quest, progress = progress })
		end
	end
	table.sort(order, function(a, b)
		return a.quest.order < b.quest.order
	end)
	local tracked = App.Waypoint.trackedQuestId()
	if App.Windows.mobile then
		-- phones have room for two, starting with the tracked one
		table.sort(order, function(a, b)
			local ta, tb = a.quest.id == tracked, b.quest.id == tracked
			if ta ~= tb then
				return ta
			end
			return a.quest.order < b.quest.order
		end)
		while #order > 2 do
			table.remove(order)
		end
	end
	for i, entry in ipairs(order) do
		local done = entry.progress >= entry.quest.objective.count
		local isTracked = tracked == entry.quest.id
		-- click a quest to put a waypoint on it
		local row = Theme.make("TextButton", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = isTracked and Color3.fromRGB(70, 35, 40) or C.panel,
			BackgroundTransparency = 0.3,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			Parent = tracker,
		})
		Theme.corner(row, 8)
		Theme.pad(row, 6)
		if isTracked then
			Theme.stroke(row, Color3.fromRGB(235, 90, 80), 1.5)
		end
		local giver = Quests.Givers[entry.quest.giver]
		Theme.label({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			TextColor3 = done and C.good or C.text,
			Text = (isTracked and "📍 " or "") .. (done and string.format("✅ %s: return to %s", entry.quest.name, giver.name) or QuestUtil.objectiveText(entry.quest, entry.progress)),
			Parent = row,
		})
		local questId = entry.quest.id
		row.Activated:Connect(function()
			App.Waypoint.trackQuest(questId)
		end)
	end
end

-- The Gold Rush countdown in the card (every second while one is running).
function HUD.updateRush()
	local p = App.State.profile
	local left = p and p.goldRushEnds and p.goldRushEnds - workspace:GetServerTimeNow() or 0
	card.rush.Visible = left > 0
	if left > 0 then
		card.rush.Text = "💸 Gold Rush: +100% gold  •  " .. Util.formatTime(left)
	end
end

local function refresh()
	local p = App.State.profile
	if not p then
		return
	end
	local class = Classes.get(p.class)
	card.class.Text = class and string.format("Lv %d%s %s", p.level, (p.paragon or 0) > 0 and (" 💫" .. p.paragon) or "", class.name) or "Choose your dragon!"
	starterAd.Visible = class ~= nil and not p.starterPack and p.level < StoreInfo.STARTER_MAX_LEVEL
	card.icon.Text = class and ({ Shadowstalker = "🌑", Stormwing = "⚡", Behemoth = "🌋", Frostwyrm = "❄️", Venomspine = "🐍" })[class.id] or "🐉"
	card.gold.Text = "💰 " .. Util.formatNumber(p.gold)
	card.glory.Text = "⚔️ " .. Util.formatNumber(p.glory)
	card.power.Text = "⚡ " .. Util.formatNumber(p.power or 0)
	HUD.updateRush()

	if p.level >= Game.LEVEL_CAP then
		-- Paragon levels past the cap
		local need = p.paragonXpToNext or 1
		bars.xpFill.Size = UDim2.fromScale(math.clamp(p.xp / need, 0, 1), 1)
		bars.xpText.Text = string.format("💫 Paragon %d  —  %s / %s XP", p.paragon or 0, Util.formatNumber(p.xp), Util.formatNumber(need))
	else
		bars.xpFill.Size = UDim2.fromScale(math.clamp(p.xp / p.xpToNext, 0, 1), 1)
		bars.xpText.Text = string.format("Level %d  —  %s / %s XP", p.level, Util.formatNumber(p.xp), Util.formatNumber(p.xpToNext))
	end

	Theme.setBadge(skillBadge, p.talentPoints)
	Theme.setBadge(petBadge, HUD.eggsWaiting(p))
	HUD.setAdmin(p.isAdmin == true)

	-- Remind gardeners about thirsty plants.
	local thirsty = 0
	for _, plant in ipairs(p.garden or {}) do
		if plant.thirsty then
			thirsty += 1
		end
	end
	gardenLabel.Visible = thirsty > 0 and not (p.robots and p.robots.water)
	gardenLabel.Text = string.format("💧 %d plant%s thirsty at your lair!", thirsty, thirsty == 1 and " is" or "s are")

	for i, slot in ipairs(slots) do
		local id = abilityForSlot(i)
		local a = id and Abilities.get(id)
		slot.icon.Text = a and a.icon or ""
		slot.icon.TextTransparency = 0
		slot.note.Text = ""
		slot.button.BackgroundTransparency = a and 0 or 0.6
		if not a and App.Windows.mobile and i > 3 then
			-- phones: hide empty skill keys instead of showing a row of empty buttons
			slot.button.Visible = false
		elseif App.Windows.mobile then
			slot.button.Visible = true
		end
		if not a then
			-- A locked signature slot shows its level; other empty slots hint at the skill tree.
			if i == 3 and class and p.level < Game.SIGNATURE_LEVEL then
				slot.icon.Text = "🔒"
				slot.note.Text = "Lv " .. Game.SIGNATURE_LEVEL
			else
				slot.icon.Text = "🌟"
				slot.icon.TextTransparency = 0.75
			end
		end
		slot.stroke.Color = (a and a.ultimate) and Color3.fromRGB(255, 120, 60) or C.accentDark
		if id == "Breath" and class then
			slot.icon.Text = ({ Shadowstalker = "💜", Stormwing = "🌬️", Behemoth = "🔥", Frostwyrm = "❄️", Venomspine = "🧪" })[class.id] or "🔥"
		end
		-- practice range: the mouse button fires Fireball too, and the rest sit out
		if Players.LocalPlayer:GetAttribute("RangeMode") then
			if i == 1 then
				slot.icon.Text = Abilities.get("Fireball").icon
			elseif i > 2 and a then
				slot.icon.TextTransparency = 0.7
			end
		end
	end
	refreshTracker(p)
	root.Enabled = p.class ~= nil
end

HUD.refresh = refresh

function HUD.init(app)
	App = app
	root = App.Windows.guis.HUD
	buildCard()
	gardenLabel = Theme.label({
		Position = UDim2.fromOffset(14, 106),
		Size = UDim2.fromOffset(300, 20),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(130, 200, 255),
		TextStrokeTransparency = 0.4,
		Visible = false,
		Parent = root,
	})
	buildBars()
	buildAbilityBar()
	buildMenu()
	buildTopBar()
	buildTracker()
	buildStarterAd()
	if App.Windows.mobile then
		mobileLayout()
	end
	buildMobile()
	root.Enabled = false
	App.State.changed:Connect(refresh)
	App.Waypoint.changed:Connect(function()
		local p = App.State.profile
		if p then
			refreshTracker(p)
		end
	end)
	refresh()
	task.spawn(function()
		while true do
			task.wait(1)
			if card.rush.Visible then
				HUD.updateRush()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local pct = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
			bars.hpFill.Size = UDim2.fromScale(pct, 1)
			bars.hpText.Text = string.format("❤️ %d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
		end
		local hunger = Players.LocalPlayer:GetAttribute("Hunger")
		if hunger then
			local lvl = Game.hungerLevel(hunger)
			bars.hungerFill.Size = UDim2.fromScale(math.clamp(hunger / Game.HUNGER_MAX, 0, 1), 1)
			bars.hungerFill.BackgroundColor3 = lvl and lvl.color or Color3.fromRGB(230, 150, 70)
			bars.hungerText.Text = string.format("🍖 Hunger %d%%%s", math.floor(hunger + 0.5), lvl and ("  —  " .. lvl.icon .. " " .. lvl.id .. "! Press G to eat") or "")
		end
		local stamina, maxStamina = App.Movement.getStamina()
		bars.staminaFill.Size = UDim2.fromScale(maxStamina > 0 and math.clamp(stamina / maxStamina, 0, 1) or 0, 1)
		bars.staminaFill.BackgroundColor3 = App.Movement.isFlying() and Color3.fromRGB(120, 230, 255) or C.stamina

		local practicing = Players.LocalPlayer:GetAttribute("RangeMode") ~= nil
		for i, slot in ipairs(slots) do
			local id = abilityForSlot(i)
			if practicing and i == 1 then
				id = "Fireball"
			end
			if practicing and i > 2 then
				-- resting while you practice
				slot.cd.Size = UDim2.fromScale(1, id and 1 or 0)
				slot.cdText.Text = ""
			elseif id then
				local remaining, total = App.Combat.getCooldown(id)
				if remaining > 0.05 and total > 0 then
					slot.cd.Size = UDim2.fromScale(1, math.clamp(remaining / total, 0, 1))
					slot.cdText.Text = remaining >= 1 and tostring(math.ceil(remaining)) or ""
				else
					slot.cd.Size = UDim2.fromScale(1, 0)
					slot.cdText.Text = ""
				end
			else
				slot.cd.Size = UDim2.fromScale(1, 0)
				slot.cdText.Text = ""
			end
		end

		if mobile.fly then
			local flying = App.Movement.isFlying()
			mobile.fly.Text = flying and "🛬 Land" or "🦅 Fly"
			mobile.up.Visible = flying
			mobile.down.Visible = flying
		end
	end)
end

return HUD
