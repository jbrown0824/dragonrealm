-- WotLK-style skill tree window: three branches, five tiers each. Click a skill to see what
-- it does, then Learn it with a skill point.

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
local selectedId = nil
local builtFor = nil

local STAT_ICONS = {
	attackPct = "⚔️", healthPct = "❤️", defensePct = "🛡️", critChance = "🎯", critDamage = "💥",
	speedPct = "👟", staminaPct = "💨", dodge = "🌀", lifesteal = "🦇", regen = "💚",
	cooldownPct = "⏱️", breathPct = "🔥", fireballPct = "☄️", abilityPct = "✨", poisonPct = "☠️",
	burnPct = "🌋", slowPct = "🐌", executePct = "🗡️", bossPct = "👑", pvpPct = "🏆",
	thorns = "🌵", goldPct = "💰", xpPct = "📘", lootPct = "🍀", cheatDeath = "💀",
}

local COL_X = { [1] = 70, [1.5] = 125, [2] = 180 }
local ROW_Y0, ROW_H = 58, 60

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

local function learn(talentId: string)
	task.spawn(function()
		local ok, err = Remotes.func("SpendTalent"):InvokeServer(talentId)
		if not ok and err then
			App.Notifications.toast(err, C.bad, "🌟")
		else
			App.Sfx.play("Click")
		end
	end)
end

local function showDetails()
	local p = App.State.profile
	local talent = selectedId and Talents.byId[selectedId]
	if not p or not talent then
		details.name.Text = "Select a skill"
		details.body.Text = "Click any skill above to see what it does. Tip: you can't learn everything — pick a branch to specialize in, like a real hero!"
		details.req.Text = ""
		Theme.setButtonEnabled(details.learn, false)
		return
	end
	local rank = p.talents[talent.id] or 0
	details.name.Text = string.format("%s %s  <font color=\"#B9AFD2\">(%d/%d)</font>", talentIcon(talent), talent.name, rank, talent.maxRank)
	local lines = {}
	if rank > 0 then
		table.insert(lines, "<b>Now:</b> " .. TalentUtil.describe(talent, rank):gsub("\n", ", "))
	end
	if rank < talent.maxRank then
		table.insert(lines, "<b>" .. (rank > 0 and "Next rank" or "Learn") .. ":</b> " .. TalentUtil.describe(talent, rank + 1):gsub("\n", ", "))
	end
	details.body.Text = table.concat(lines, "\n")
	local ok, reason = TalentUtil.canLearn(p.class, p.level, p.talents, talent.id)
	if rank >= talent.maxRank then
		details.req.Text = "✅ Mastered"
		details.req.TextColor3 = C.good
	elseif ok then
		details.req.Text = "Ready to learn!"
		details.req.TextColor3 = C.good
	else
		details.req.Text = reason or ""
		details.req.TextColor3 = C.bad
	end
	Theme.setButtonEnabled(details.learn, ok == true)
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
	pointsLabel.Text = string.format("Skill points: <font color=\"#FFD24A\">%d</font>   •   Level %d / %d", p.talentPoints, p.level, Game.LEVEL_CAP)
	local spent = TalentUtil.spent(p.talents)
	resetButton.Text = string.format("Reset (%d gold)", TalentUtil.respecCost(p.level))
	Theme.setButtonEnabled(resetButton, spent > 0)

	for branchIndex, branch in ipairs(branches) do
		local col = columns[branchIndex]
		local inBranch = TalentUtil.spentInBranch(p.talents, p.class, branchIndex)
		col.header.Text = string.format("%s %s  <font color=\"#FFD24A\">(%d)</font>", branch.icon, branch.name, inBranch)
		for tier = 1, 5 do
			local unlocked = inBranch >= TalentUtil.tierRequirement(tier)
			col.tierLabels[tier].TextColor3 = unlocked and C.good or C.subtext
		end
		for _, talent in ipairs(branch.talents) do
			local b = col.buttons[talent.id]
			local rank = p.talents[talent.id] or 0
			local canLearn = TalentUtil.canLearn(p.class, p.level, p.talents, talent.id)
			local tierOk = inBranch >= TalentUtil.tierRequirement(talent.tier)
			b.rank.Text = string.format("%d/%d", rank, talent.maxRank)
			if rank >= talent.maxRank then
				b.stroke.Color = C.accent
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
	end
	showDetails()
end

function SkillTree.build(classId: string)
	builtFor = classId
	for _, col in ipairs(columns) do
		col.frame:Destroy()
	end
	columns = {}
	local branches = Talents[classId]
	local class = Classes.get(classId)
	window.TitleBar_.Title.Text = "🌟 Skill Tree — " .. class.name
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
			Size = UDim2.new(1, -20, 0, 24),
			Font = Theme.Fonts.title,
			TextSize = 20,
			TextColor3 = class.colors.accent,
			Text = branch.name,
			Parent = frame,
		})
		Theme.label({
			Position = UDim2.fromOffset(10, 30),
			Size = UDim2.new(1, -20, 0, 18),
			TextSize = 12,
			Font = Theme.Fonts.body,
			TextColor3 = C.subtext,
			Text = branch.desc,
			Parent = frame,
		})
		local col = { frame = frame, header = header, buttons = {}, tierLabels = {} }
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
				Position = UDim2.fromOffset(x - 25, y),
				Size = UDim2.fromOffset(50, 50),
				BackgroundColor3 = C.panel2,
				AutoButtonColor = false,
				Text = "",
				Parent = frame,
			})
			Theme.corner(button, talent.ability and 25 or 10)
			local stroke = Theme.stroke(button, C.subtext, 2)
			local icon = Theme.label({
				Size = UDim2.fromScale(1, 1),
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = talentIcon(talent),
				Parent = button,
			})
			local rank = Theme.label({
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 6, 1, 4),
				Size = UDim2.fromOffset(30, 16),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(15, 12, 22),
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "0/" .. talent.maxRank,
				ZIndex = 2,
				Parent = button,
			})
			Theme.corner(rank, 5)
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
				selectedId = talent.id
				refresh()
			end)
			col.buttons[talent.id] = { button = button, stroke = stroke, icon = icon, rank = rank }
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
		Size = UDim2.fromOffset(500, 30),
		TextSize = 18,
		Text = "",
		Parent = content,
	})
	resetButton = Theme.button("Reset", Color3.fromRGB(120, 50, 60), function()
		task.spawn(function()
			local ok, err = Remotes.func("ResetTalents"):InvokeServer()
			if not ok and err then
				App.Notifications.toast(err, C.bad, "🌟")
			elseif ok then
				App.Notifications.toast("Skill points refunded!", C.good, "🌟")
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
	details.name = Theme.label({ Size = UDim2.new(1, -150, 0, 22), TextSize = 18, TextColor3 = C.accent, Parent = panel })
	details.body = Theme.label({ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -150, 0, 40), TextSize = 13, Font = Theme.Fonts.body, Parent = panel })
	details.req = Theme.label({ Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, -150, 0, 16), TextSize = 13, Parent = panel })
	details.learn = Theme.button("Learn", Color3.fromRGB(60, 140, 70), function()
		if selectedId then
			learn(selectedId)
		end
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(130, 46),
		TextSize = 20,
		Parent = panel,
	})

	App.Windows.register("SkillTree", window, refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			refresh()
		end
	end)
end

return SkillTree
