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
local skillBadge
local mobile = {}

local SLOT_KEYS = { "Mouse", "Q", "1", "2", "3", "4" }

local function abilityForSlot(i: number): string?
	local p = App.State.profile
	local list = p and p.stats and p.stats.abilities
	return list and list[i]
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
		{ id = "map", icon = "🗺️", label = "Map [M]", action = function() App.Windows.toggle("Map") end },
		{ id = "home", icon = "🏠", label = "Home [H]", action = function() HUD.goHome() end },
		{ id = "codes", icon = "🎁", label = "Codes", action = function() App.Windows.toggle("Codes") end },
		{ id = "help", icon = "❓", label = "Help", action = function() App.Windows.toggle("Help") end },
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
		if i == 1 then
			skillBadge = Theme.label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 4, 0, -4),
				Size = UDim2.fromOffset(24, 24),
				BackgroundTransparency = 0,
				BackgroundColor3 = C.bad,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "0",
				Visible = false,
				ZIndex = 3,
				Parent = b,
			})
			Theme.corner(skillBadge, 12)
		end
	end
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

local function buildMobile()
	if not UserInputService.TouchEnabled then
		return
	end
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

local function refresh()
	local p = App.State.profile
	if not p then
		return
	end
	local class = Classes.get(p.class)
	card.class.Text = class and string.format("Lv %d %s", p.level, class.name) or "Choose your dragon!"
	card.icon.Text = class and ({ Shadowstalker = "🌑", Stormwing = "⚡", Behemoth = "🌋", Frostwyrm = "❄️", Venomspine = "🐍" })[class.id] or "🐉"
	card.gold.Text = "💰 " .. Util.formatNumber(p.gold)
	card.glory.Text = "⚔️ " .. Util.formatNumber(p.glory)
	card.power.Text = "⚡ " .. Util.formatNumber(p.power or 0)

	if p.level >= Game.LEVEL_CAP then
		bars.xpFill.Size = UDim2.fromScale(1, 1)
		bars.xpText.Text = "MAX LEVEL"
	else
		bars.xpFill.Size = UDim2.fromScale(math.clamp(p.xp / p.xpToNext, 0, 1), 1)
		bars.xpText.Text = string.format("Level %d  —  %s / %s XP", p.level, Util.formatNumber(p.xp), Util.formatNumber(p.xpToNext))
	end

	skillBadge.Visible = p.talentPoints > 0
	skillBadge.Text = tostring(p.talentPoints)
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
			slot.icon.Text = ({ Shadowstalker = "💜", Stormwing = "⚡", Behemoth = "🔥", Frostwyrm = "❄️", Venomspine = "🧪" })[class.id] or "🔥"
		end
	end
	refreshTracker(p)
	root.Enabled = p.class ~= nil
end

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
	buildTracker()
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

		for i, slot in ipairs(slots) do
			local id = abilityForSlot(i)
			if id then
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
