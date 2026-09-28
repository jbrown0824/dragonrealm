-- WotLK-style skill tree window: three branches, five tiers each.
-- Made for young players too:
--   * click a skill to see it; click it again (or the Learn button that pops up beside it) to learn
--   * every skill shows filled bars for the ranks you have (like 2 of 3) and a big "2/3"
--   * "Max" learns all remaining ranks at once when you have the points
--   * each branch has an "Auto" button that spends your points down that path
--   * the "Keys 2-5" strip picks which learned abilities go on your action bar (Paragon points
--     let you learn more abilities than there are keys)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Talents = require(Shared.Config.Talents)
local Abilities = require(Shared.Config.Abilities)
local Game = require(Shared.Config.Game)
local TalentUtil = require(Shared.TalentUtil)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local SkillTree = {}
local App

local window, content
local pointsLabel, resetButton
local columns = {}
local details = {}
local popup = {}
local selectedId = nil
local bar = { slots = {} } -- the keys 2-5 strip and its picker
local builtFor = nil
local autoArmed = nil
local busy = false

local STAT_ICONS = {
	attackPct = "⚔️", healthPct = "❤️", defensePct = "🛡️", critChance = "🎯", critDamage = "💥",
	speedPct = "👟", staminaPct = "💨", dodge = "🌀", lifesteal = "🦇", regen = "💚",
	cooldownPct = "⏱️", breathPct = "🔥", fireballPct = "☄️", abilityPct = "✨", poisonPct = "☠️",
	burnPct = "🌋", slowPct = "🐌", executePct = "🗡️", bossPct = "👑", pvpPct = "🏆",
	thorns = "🌵", goldPct = "💰", xpPct = "📘", lootPct = "🍀", cheatDeath = "💀",
}

local COL_X = { [1] = 70, [1.5] = 125, [2] = 180 }
local ROW_Y0, ROW_H = 58, 60
local TILE = 50
local GOLD = Color3.fromRGB(255, 205, 70)

local function talentIcon(talent): string
	if talent.ability then
		local a = Abilities.get(talent.ability)
		return a and a.icon or "✨"
	end
	if talent.mods then
		for abilityId in pairs(talent.mods) do
			local a = Abilities.get(abilityId)
			return a and a.icon or "⬆️"
		end
	end
	local keys = {}
	for k in pairs(talent.effects) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return STAT_ICONS[keys[1]] or "⭐"
end

-- Ask the server to learn `count` ranks of a skill.
local function learn(talentId: string, count: number?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, err = Remotes.func("SpendTalent"):InvokeServer(talentId, count or 1)
		busy = false
		if not ok and err then
			App.Windows.notify(err, C.bad, "🌟")
		else
			App.Sfx.play("LevelUp", 0.4)
		end
	end)
end

local function autoFill(branchIndex: number)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = Remotes.func("AutoSpendBranch"):InvokeServer(branchIndex)
		busy = false
		if ok then
			App.Sfx.play("LevelUp", 0.4)
			App.Windows.notify(string.format("Learned %d skill rank%s!", result, result == 1 and "" or "s"), C.good, "🌟")
		elseif result then
			App.Windows.notify(result, C.bad, "🌟")
		end
	end)
end

-- How many more ranks of this skill you could learn right now (0 if none).
local function learnableRanks(p, talent): number
	if not TalentUtil.canLearn(p.class, p.level, p.talents, talent.id, p.paragon) then
		return 0
	end
	local rank = p.talents[talent.id] or 0
	return math.min(talent.maxRank - rank, p.talentPoints)
end

local function showDetails()
	local p = App.State.profile
	local talent = selectedId and Talents.byId[selectedId]
	if not p or not talent then
		details.name.Text = "Pick a skill"
		details.body.Text = "Click any skill above to see what it does, then click it again to learn it. You can't learn everything, so pick a branch to specialize in!"
		details.req.Text = ""
		details.learn.Visible = false
		details.max.Visible = false
		return
	end
	local rank = p.talents[talent.id] or 0
	details.name.Text = string.format("%s %s  <font color=\"#FFD24A\">%d/%d</font>", talentIcon(talent), talent.name, rank, talent.maxRank)
	local lines = {}
	if rank > 0 then
		table.insert(lines, "<b>Now:</b> " .. TalentUtil.describe(talent, rank):gsub("\n", ", "))
	end
	if rank < talent.maxRank then
		table.insert(lines, "<b>" .. (rank > 0 and "Next rank" or "Learn") .. ":</b> " .. TalentUtil.describe(talent, rank + 1):gsub("\n", ", "))
	end
	details.body.Text = table.concat(lines, "\n")
	local ok, reason = TalentUtil.canLearn(p.class, p.level, p.talents, talent.id, p.paragon)
	if rank >= talent.maxRank then
		details.req.Text = "✅ Fully learned!"
		details.req.TextColor3 = C.good
	elseif ok then
		details.req.Text = "Ready! Click the skill again to learn it."
		details.req.TextColor3 = C.good
	else
		details.req.Text = reason or ""
		details.req.TextColor3 = C.bad
	end
	local canCount = learnableRanks(p, talent)
	local remaining = talent.maxRank - rank
	details.learn.Visible = rank < talent.maxRank
	details.learn.Text = string.format("Learn %d/%d", rank + 1, talent.maxRank)
	Theme.setButtonEnabled(details.learn, canCount > 0)
	details.max.Visible = remaining > 1
	details.max.Text = string.format("Max (+%d)", remaining)
	Theme.setButtonEnabled(details.max, canCount >= remaining and remaining > 1)
end

-- The little Learn / Max bubble next to the selected skill.
local function showPopup(p)
	local talent = selectedId and Talents.byId[selectedId]
	local col = talent and columns[talent.branch]
	local canCount = talent and learnableRanks(p, talent) or 0
	if not talent or not col or canCount <= 0 then
		popup.frame.Visible = false
		return
	end
	local rank = p.talents[talent.id] or 0
	local remaining = talent.maxRank - rank
	local x = COL_X[talent.col] or COL_X[1]
	local y = ROW_Y0 + (talent.tier - 1) * ROW_H
	popup.frame.Parent = col.frame
	popup.frame.Position = talent.col == 2 and UDim2.fromOffset(x - TILE / 2 - 122, y - 4) or UDim2.fromOffset(x + TILE / 2 + 6, y - 4)
	popup.learn.Text = string.format("Learn %d/%d", rank + 1, talent.maxRank)
	popup.max.Visible = remaining > 1
	popup.max.Text = string.format("Max (+%d)", remaining)
	Theme.setButtonEnabled(popup.max, canCount >= remaining)
	popup.frame.Size = UDim2.fromOffset(116, remaining > 1 and 60 or 32)
	popup.frame.Visible = true
end

local function setPips(b, rank: number, maxRank: number, color: Color3)
	for i, pip in ipairs(b.pips) do
		pip.BackgroundColor3 = i <= rank and color or Color3.fromRGB(40, 34, 55)
	end
	b.rank.Text = string.format("%d/%d", rank, maxRank)
	b.rank.TextColor3 = rank >= maxRank and GOLD or (rank > 0 and C.text or C.subtext)
end

-- Put `abilityId` on key slot `index` (1-4 = keys 2-5), swapping if it's already on another key.
local function assignKey(index: number, abilityId: string)
	local p = App.State.profile
	local current = {}
	for i = 1, TalentUtil.LOADOUT_SLOTS do
		current[i] = App.HUD.abilityForSlot(i + 3) or false
	end
	local from = table.find(current, abilityId)
	if from then
		current[from] = current[index]
	end
	current[index] = abilityId
	bar.picker.Visible = false
	task.spawn(function()
		Remotes.func("SetLoadout"):InvokeServer(current)
	end)
	if p then
		App.Sfx.play("Click")
	end
end

local function refreshBar(p)
	local class = Classes.get(p.class)
	local learned = TalentUtil.treeAbilities(p.stats and p.stats.abilities, class and class.signature)
	for i, slot in ipairs(bar.slots) do
		local id = App.HUD.abilityForSlot(i + 3)
		local a = id and Abilities.get(id)
		slot.Text = a and a.icon or ""
		slot.BackgroundTransparency = a and 0 or 0.5
	end
	local extra = #learned - TalentUtil.LOADOUT_SLOTS
	bar.hint.Text = extra > 0 and string.format("<font color=\"#FFD24A\">+%d more</font>: click a key to swap", extra) or "click a key to choose"
end

local function openPicker(index: number)
	local p = App.State.profile
	if not p then
		return
	end
	local class = Classes.get(p.class)
	local learned = TalentUtil.treeAbilities(p.stats and p.stats.abilities, class and class.signature)
	Theme.clear(bar.pickerList)
	if #learned == 0 then
		Theme.label({ Size = UDim2.new(1, 0, 0, 36), TextSize = 13, TextColor3 = C.subtext, ZIndex = 32, Text = "Learn abilities (the big icons in each branch) to put them on your keys.", Parent = bar.pickerList })
	end
	for i, id in ipairs(learned) do
		local a = Abilities.get(id)
		local b = Theme.button(string.format("%s  %s", a.icon, a.name), a.ultimate and Color3.fromRGB(120, 60, 40) or C.panel3, function()
			assignKey(index, id)
		end, { Size = UDim2.new(1, 0, 0, 30), TextSize = 14, LayoutOrder = i, ZIndex = 32, TextXAlignment = Enum.TextXAlignment.Left, Parent = bar.pickerList })
		Theme.pad(b, 8)
	end
	bar.pickerTitle.Text = "Put on key " .. (index + 1) .. ":"
	bar.picker.Visible = true
end

local function refresh()
	local p = App.State.profile
	if not p or not p.class then
		return
	end
	local branches = Talents[p.class]
	if builtFor ~= p.class then
		SkillTree.build(p.class)
	end
	pointsLabel.Text = string.format("Skill points: <font color=\"#FFD24A\">%d</font>  •  Lv %d%s", p.talentPoints, p.level,
		(p.paragon or 0) > 0 and string.format("  •  💫 %d", p.paragon) or "")
	refreshBar(p)
	local spent = TalentUtil.spent(p.talents)
	resetButton.Text = string.format("Reset (%d gold)", TalentUtil.respecCost(p.level))
	Theme.setButtonEnabled(resetButton, spent > 0)

	for branchIndex, branch in ipairs(branches) do
		local col = columns[branchIndex]
		local inBranch = TalentUtil.spentInBranch(p.talents, p.class, branchIndex)
		col.header.Text = string.format("%s %s  <font color=\"#FFD24A\">(%d)</font>", branch.icon, branch.name, inBranch)
		local anyLearnable = false
		for tier = 1, 5 do
			local unlocked = inBranch >= TalentUtil.tierRequirement(tier)
			col.tierLabels[tier].TextColor3 = unlocked and C.good or C.subtext
		end
		for _, talent in ipairs(branch.talents) do
			local b = col.buttons[talent.id]
			local rank = p.talents[talent.id] or 0
			local canLearn = TalentUtil.canLearn(p.class, p.level, p.talents, talent.id, p.paragon)
			anyLearnable = anyLearnable or canLearn
			local tierOk = inBranch >= TalentUtil.tierRequirement(talent.tier)
			setPips(b, rank, talent.maxRank, rank >= talent.maxRank and GOLD or C.good)
			if rank >= talent.maxRank then
				b.stroke.Color = GOLD
				b.button.BackgroundColor3 = Color3.fromRGB(90, 70, 40)
				b.button.BackgroundTransparency = 0
				b.icon.TextTransparency = 0
			elseif canLearn then
				b.stroke.Color = C.good
				b.button.BackgroundColor3 = C.panel3
				b.button.BackgroundTransparency = 0
				b.icon.TextTransparency = 0
			elseif rank > 0 or tierOk then
				b.stroke.Color = C.blue
				b.button.BackgroundColor3 = C.panel2
				b.button.BackgroundTransparency = 0
				b.icon.TextTransparency = rank > 0 and 0 or 0.35
			else
				b.stroke.Color = Color3.fromRGB(70, 65, 80)
				b.button.BackgroundColor3 = C.panel2
				b.button.BackgroundTransparency = 0.4
				b.icon.TextTransparency = 0.6
			end
			b.stroke.Thickness = selectedId == talent.id and 4 or 2
		end
		col.auto.Visible = p.talentPoints > 0 and anyLearnable
		col.auto.Text = autoArmed == branchIndex and "Sure?" or "⚡ Auto"
	end
	showDetails()
	showPopup(p)
end

function SkillTree.build(classId: string)
	builtFor = classId
	selectedId = nil
	for _, col in ipairs(columns) do
		col.frame:Destroy()
	end
	columns = {}
	local branches = Talents[classId]
	local class = Classes.get(classId)
	window.TitleBar_.Title.Text = "🌟 Skill Tree: " .. class.name
	for branchIndex, branch in ipairs(branches) do
		local frame = Theme.make("Frame", {
			Position = UDim2.fromOffset((branchIndex - 1) * 278, 40),
			Size = UDim2.fromOffset(268, 362),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = 0.2,
			Parent = content,
		})
		Theme.corner(frame, 10)
		local header = Theme.label({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -96, 0, 24),
			Font = Theme.Fonts.title,
			TextSize = 20,
			TextColor3 = class.colors.accent,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = branch.name,
			Parent = frame,
		})
		local auto = Theme.button("⚡ Auto", Color3.fromRGB(70, 120, 180), function()
			if autoArmed ~= branchIndex then
				-- ask once before spending every point
				autoArmed = branchIndex
				refresh()
				task.delay(4, function()
					if autoArmed == branchIndex then
						autoArmed = nil
						refresh()
					end
				end)
				return
			end
			autoArmed = nil
			autoFill(branchIndex)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 7), Size = UDim2.fromOffset(78, 24), TextSize = 13, Visible = false, Parent = frame })
		Theme.label({
			Position = UDim2.fromOffset(10, 30),
			Size = UDim2.new(1, -20, 0, 18),
			TextSize = 12,
			Font = Theme.Fonts.body,
			TextColor3 = C.subtext,
			Text = branch.desc,
			Parent = frame,
		})
		local col = { frame = frame, header = header, auto = auto, buttons = {}, tierLabels = {} }
		for tier = 1, 5 do
			col.tierLabels[tier] = Theme.label({
				Position = UDim2.fromOffset(8, ROW_Y0 + (tier - 1) * ROW_H + 16),
				Size = UDim2.fromOffset(30, 18),
				TextSize = 12,
				TextColor3 = C.subtext,
				Text = tostring(TalentUtil.tierRequirement(tier)),
				Parent = frame,
			})
		end
		for _, talent in ipairs(branch.talents) do
			local x = COL_X[talent.col] or COL_X[1]
			local y = ROW_Y0 + (talent.tier - 1) * ROW_H
			local button = Theme.make("TextButton", {
				Position = UDim2.fromOffset(x - TILE / 2, y),
				Size = UDim2.fromOffset(TILE, TILE),
				BackgroundColor3 = C.panel2,
				AutoButtonColor = false,
				Text = "",
				Parent = frame,
			})
			Theme.corner(button, talent.ability and 25 or 10)
			local stroke = Theme.stroke(button, C.subtext, 2)
			local icon = Theme.label({
				Size = UDim2.new(1, 0, 0, 36),
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = talentIcon(talent),
				Parent = button,
			})
			-- one bar per rank, filled as you learn them
			local pips = {}
			local gap = 2
			local width = (TILE - 12 - gap * (talent.maxRank - 1)) / talent.maxRank
			for i = 1, talent.maxRank do
				local pip = Theme.make("Frame", {
					Position = UDim2.fromOffset(6 + (i - 1) * (width + gap), 38),
					Size = UDim2.fromOffset(width, 7),
					BackgroundColor3 = Color3.fromRGB(40, 34, 55),
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = button,
				})
				Theme.corner(pip, 3)
				pips[i] = pip
			end
			local rank = Theme.label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 8, 0, -8),
				Size = UDim2.fromOffset(30, 18),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(15, 12, 22),
				Font = Theme.Fonts.title,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "0/" .. talent.maxRank,
				ZIndex = 3,
				Parent = button,
			})
			Theme.corner(rank, 6)
			if talent.mods then
				Theme.label({
					Position = UDim2.fromOffset(-4, -6),
					Size = UDim2.fromOffset(18, 18),
					TextSize = 16,
					TextColor3 = C.good,
					Text = "+",
					ZIndex = 2,
					Parent = button,
				})
			end
			button.Activated:Connect(function()
				local p = App.State.profile
				-- second click on the selected skill learns a rank
				if selectedId == talent.id and p and learnableRanks(p, talent) > 0 then
					learn(talent.id, 1)
				end
				selectedId = talent.id
				refresh()
			end)
			col.buttons[talent.id] = { button = button, stroke = stroke, icon = icon, rank = rank, pips = pips }
		end
		columns[branchIndex] = col
	end
end

function SkillTree.init(app)
	App = app
	local close, titleBar
	window, content, close, titleBar = Theme.window(App.Windows.guis.Windows, "🌟 Skill Tree", Vector2.new(858, 592))
	titleBar.Name = "TitleBar_"
	close.Activated:Connect(function()
		App.Windows.close("SkillTree")
	end)

	pointsLabel = Theme.label({
		Size = UDim2.fromOffset(300, 30),
		TextSize = 17,
		TextWrapped = false,
		Text = "",
		Parent = content,
	})

	-- Keys 2-5: which learned abilities are on the action bar
	local strip = Theme.make("Frame", { Position = UDim2.fromOffset(305, -2), Size = UDim2.fromOffset(350, 34), BackgroundTransparency = 1, Parent = content })
	Theme.label({ Size = UDim2.fromOffset(74, 34), TextSize = 13, TextColor3 = C.accent, Text = "Keys 2-5", Parent = strip })
	for i = 1, TalentUtil.LOADOUT_SLOTS do
		local slot = Theme.button("", C.panel2, function()
			if bar.picker.Visible and bar.pickerIndex == i then
				bar.picker.Visible = false
			else
				bar.pickerIndex = i
				openPicker(i)
			end
		end, { Name = "KeySlot" .. i, Position = UDim2.fromOffset(74 + (i - 1) * 38, 0), Size = UDim2.fromOffset(34, 34), TextSize = 20, Parent = strip })
		Theme.stroke(slot, C.accentDark, 1.5)
		Theme.label({ Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(12, 12), TextSize = 10, TextColor3 = C.accent, Text = tostring(i + 1), ZIndex = 3, Parent = slot })
		bar.slots[i] = slot
	end
	bar.hint = Theme.label({ Position = UDim2.fromOffset(228, 0), Size = UDim2.fromOffset(122, 34), TextSize = 11, TextColor3 = C.subtext, Text = "", Parent = strip })
	bar.picker = Theme.make("Frame", { Position = UDim2.fromOffset(379, 36), Size = UDim2.fromOffset(260, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel, Visible = false, ZIndex = 30, Parent = content })
	Theme.corner(bar.picker, 8)
	Theme.stroke(bar.picker, C.accent, 2)
	Theme.pad(bar.picker, 8)
	Theme.list(bar.picker, 6)
	bar.pickerTitle = Theme.label({ Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = C.accent, LayoutOrder = 0, ZIndex = 31, Parent = bar.picker })
	bar.pickerList = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 31, Parent = bar.picker })
	Theme.list(bar.pickerList, 4)
	resetButton = Theme.button("Reset", Color3.fromRGB(120, 50, 60), function()
		task.spawn(function()
			local ok, err = Remotes.func("ResetTalents"):InvokeServer()
			if not ok and err then
				App.Windows.notify(err, C.bad, "🌟")
			elseif ok then
				App.Windows.notify("Skill points refunded!", C.good, "🌟")
			end
		end)
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(170, 32),
		TextSize = 14,
		Parent = content,
	})

	local panel = Theme.make("Frame", {
		Position = UDim2.fromOffset(0, 410),
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundColor3 = C.panel2,
		Parent = content,
	})
	Theme.corner(panel, 10)
	Theme.pad(panel, 10)
	details.name = Theme.label({ Size = UDim2.new(1, -190, 0, 22), TextSize = 18, TextColor3 = C.accent, Parent = panel })
	details.body = Theme.label({ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -190, 0, 40), TextSize = 13, Font = Theme.Fonts.body, Parent = panel })
	details.req = Theme.label({ Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, -190, 0, 16), TextSize = 13, Parent = panel })
	details.learn = Theme.button("Learn", Color3.fromRGB(60, 140, 70), function()
		if selectedId then
			learn(selectedId, 1)
		end
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(170, 40),
		TextSize = 19,
		Parent = panel,
	})
	details.max = Theme.button("Max", Color3.fromRGB(150, 110, 40), function()
		local talent = selectedId and Talents.byId[selectedId]
		local p = App.State.profile
		if talent and p then
			learn(talent.id, talent.maxRank - (p.talents[talent.id] or 0))
		end
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(170, 30),
		TextSize = 15,
		Parent = panel,
	})

	-- Learn / Max bubble that appears right beside the selected skill
	popup.frame = Theme.make("Frame", {
		Size = UDim2.fromOffset(116, 60),
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 20,
		Parent = content,
	})
	Theme.corner(popup.frame, 8)
	Theme.stroke(popup.frame, C.good, 2)
	popup.learn = Theme.button("Learn", Color3.fromRGB(60, 140, 70), function()
		if selectedId then
			learn(selectedId, 1)
		end
	end, { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 24), TextSize = 14, ZIndex = 21, Parent = popup.frame })
	popup.max = Theme.button("Max", Color3.fromRGB(150, 110, 40), function()
		local talent = selectedId and Talents.byId[selectedId]
		local p = App.State.profile
		if talent and p then
			learn(talent.id, talent.maxRank - (p.talents[talent.id] or 0))
		end
	end, { Position = UDim2.fromOffset(4, 32), Size = UDim2.new(1, -8, 0, 24), TextSize = 13, ZIndex = 21, Parent = popup.frame })

	App.Windows.register("SkillTree", window, refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			refresh()
		end
	end)
end

return SkillTree
