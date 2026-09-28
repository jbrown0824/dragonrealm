-- Quest giver dialogs and the quest log.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local QuestUtil = require(Shared.QuestUtil)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local QuestUI = {}
local App

local dialog, dialogContent, dialogTitle
local giverLabel, speechLabel, questBox, questName, questDesc, questRewards
local primaryButton, secondaryButton, transformButton
local currentGiver = nil
local logWindow, logList

local function invoke(remote: string, questId: string, successText: string?)
	task.spawn(function()
		local ok, err = Remotes.func(remote):InvokeServer(questId)
		if not ok then
			App.Windows.notify(err or "Couldn't do that.", C.bad, "📜")
		else
			if successText then
				App.Windows.notify(successText, C.accent, "📜")
			end
			App.Sfx.play("Quest")
			-- show what this giver has next
			task.wait(0.3)
			if currentGiver and dialog.Visible then
				QuestUI.showDialog(currentGiver)
			end
		end
	end)
end

local function setButton(button: TextButton, text: string?, handler)
	if not text then
		button.Visible = false
		return
	end
	button.Visible = true
	button.Text = text
	QuestUI.handlers[button] = handler
end

QuestUI.handlers = {}

function QuestUI.showDialog(giverId: string)
	local p = App.State.profile
	local giver = Quests.Givers[giverId]
	if not p or not giver then
		return
	end
	currentGiver = giverId
	dialogTitle.Text = "💬 " .. giver.name
	giverLabel.Text = giver.title
	transformButton.Visible = giverId == "Elder"

	local state = p.quests
	local turnIn = QuestUtil.readyToTurnIn(giverId, state)
	local offer = QuestUtil.nextOffer(giverId, state, p.level)

	if turnIn then
		speechLabel.Text = "Wonderful work! You've done it. Here is your reward."
		questBox.Visible = true
		questName.Text = "✅ " .. turnIn.name
		questDesc.Text = turnIn.desc
		questRewards.Text = "🏆 Rewards: " .. QuestUtil.rewardText(turnIn)
		setButton(primaryButton, "Claim Rewards", function()
			invoke("TurnInQuest", turnIn.id)
		end)
		setButton(secondaryButton, "Later", function()
			App.Windows.close("QuestDialog")
		end)
	elseif offer then
		speechLabel.Text = giver.greeting
		questBox.Visible = true
		questName.Text = "❗ " .. offer.name .. (offer.repeatable and "  (repeatable)" or "")
		questDesc.Text = offer.desc
		questRewards.Text = "🏆 Rewards: " .. QuestUtil.rewardText(offer)
		setButton(primaryButton, "Accept", function()
			invoke("AcceptQuest", offer.id, "Quest accepted: " .. offer.name)
		end)
		setButton(secondaryButton, "Not now", function()
			App.Windows.close("QuestDialog")
		end)
	else
		local activeQuest = nil
		for questId, progress in pairs(state.active) do
			local q = Quests.byId[questId]
			if q and q.giver == giverId then
				activeQuest = { quest = q, progress = progress }
			end
		end
		local locked = QuestUtil.lockedByLevel(giverId, state, p.level)
		if activeQuest then
			speechLabel.Text = "How is it going? Come back when you're done."
			questBox.Visible = true
			questName.Text = "⏳ " .. QuestUtil.objectiveText(activeQuest.quest, activeQuest.progress)
			questDesc.Text = activeQuest.quest.desc
			questRewards.Text = "🏆 Rewards: " .. QuestUtil.rewardText(activeQuest.quest)
		elseif locked then
			speechLabel.Text = string.format("I'll have more for you when you reach level %d. Keep training!", locked.minLevel)
			questBox.Visible = false
		else
			speechLabel.Text = giver.idle
			questBox.Visible = false
		end
		setButton(primaryButton, "Goodbye", function()
			App.Windows.close("QuestDialog")
		end)
		setButton(secondaryButton, nil)
	end
end

function QuestUI.refreshLog()
	local p = App.State.profile
	if not p then
		return
	end
	Theme.clear(logList)
	local entries = {}
	for questId, progress in pairs(p.quests.active) do
		local q = Quests.byId[questId]
		if q then
			table.insert(entries, { quest = q, progress = progress })
		end
	end
	table.sort(entries, function(a, b)
		return a.quest.order < b.quest.order
	end)
	for i, e in ipairs(entries) do
		local q = e.quest
		local done = e.progress >= q.objective.count
		local frame = Theme.make("Frame", {
			Size = UDim2.new(1, -10, 0, 104),
			BackgroundColor3 = C.panel2,
			LayoutOrder = i,
			Parent = logList,
		})
		Theme.corner(frame, 8)
		Theme.pad(frame, 8)
		Theme.label({ Size = UDim2.new(1, -110, 0, 22), Font = Theme.Fonts.title, TextSize = 18, TextColor3 = done and C.good or C.accent, Text = (done and "✅ " or "📜 ") .. q.name, Parent = frame })
		Theme.label({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -110, 0, 32), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.text, Text = q.desc, Parent = frame })
		local _, fill, text = Theme.bar(frame, done and C.good or C.xp, UDim2.new(1, -110, 0, 16), UDim2.fromOffset(0, 58))
		fill.Size = UDim2.fromScale(math.clamp(e.progress / q.objective.count, 0, 1), 1)
		text.Text = string.format("%d / %d", math.min(e.progress, q.objective.count), q.objective.count)
		Theme.label({ Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, -110, 0, 16), TextSize = 12, TextColor3 = C.subtext, Text = (done and ("Return to " .. Quests.Givers[q.giver].name .. "  •  ") or "") .. "Rewards: " .. QuestUtil.rewardText(q), Parent = frame })
		Theme.button("Abandon", Color3.fromRGB(120, 50, 60), function()
			task.spawn(function()
				Remotes.func("AbandonQuest"):InvokeServer(q.id)
			end)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(96, 32), TextSize = 13, Parent = frame })
	end
	if #entries == 0 then
		Theme.label({
			Size = UDim2.new(1, 0, 0, 80),
			TextSize = 15,
			TextColor3 = C.subtext,
			Text = "No active quests. Look for dragons with a yellow ❗ above their heads in Dragon Town!",
			Parent = logList,
		})
	end
end

function QuestUI.init(app)
	App = app
	local close, titleBar
	dialog, dialogContent, close, titleBar = Theme.window(App.Windows.guis.Windows, "Quest", Vector2.new(560, 380))
	dialogTitle = titleBar.Title
	close.Activated:Connect(function()
		App.Windows.close("QuestDialog")
	end)
	giverLabel = Theme.label({ Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = C.subtext, Parent = dialogContent })
	speechLabel = Theme.label({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 44), TextSize = 15, Font = Enum.Font.GothamMedium, Text = "", Parent = dialogContent })
	questBox = Theme.make("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 170), BackgroundColor3 = C.panel2, Parent = dialogContent })
	Theme.corner(questBox, 10)
	Theme.pad(questBox, 10)
	questName = Theme.label({ Size = UDim2.new(1, 0, 0, 24), Font = Theme.Fonts.title, TextSize = 21, TextColor3 = C.accent, Parent = questBox })
	questDesc = Theme.label({ Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 70), TextSize = 14, Font = Theme.Fonts.body, TextYAlignment = Enum.TextYAlignment.Top, Parent = questBox })
	questRewards = Theme.label({ Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 44), TextSize = 14, TextColor3 = C.gold, TextYAlignment = Enum.TextYAlignment.Top, Parent = questBox })

	local function dispatch(button)
		local handler = QuestUI.handlers[button]
		if handler then
			handler()
		end
	end
	primaryButton = Theme.button("Accept", Color3.fromRGB(60, 140, 70), nil, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(150, 40), Parent = dialogContent })
	secondaryButton = Theme.button("Not now", C.panel3, nil, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -160, 1, 0), Size = UDim2.fromOffset(120, 40), Parent = dialogContent })
	primaryButton.Activated:Connect(function()
		dispatch(primaryButton)
	end)
	secondaryButton.Activated:Connect(function()
		dispatch(secondaryButton)
	end)
	transformButton = Theme.button("🐉 Transform", Color3.fromRGB(110, 60, 150), function()
		App.Windows.close("QuestDialog")
		App.ClassSelect.show("transform")
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(150, 40), Parent = dialogContent })

	App.Windows.register("QuestDialog", dialog, function(giverId)
		QuestUI.showDialog(giverId)
	end, function()
		currentGiver = nil
	end)

	local logContent, logClose
	logWindow, logContent, logClose = Theme.window(App.Windows.guis.Windows, "📜 Quest Log", Vector2.new(640, 520))
	logClose.Activated:Connect(function()
		App.Windows.close("QuestLog")
	end)
	logList = Theme.scroll(logContent, { Size = UDim2.fromScale(1, 1) })
	Theme.list(logList, 8)
	App.Windows.register("QuestLog", logWindow, QuestUI.refreshLog)

	App.State.changed:Connect(function()
		if logWindow.Visible then
			QuestUI.refreshLog()
		end
		if dialog.Visible and currentGiver then
			QuestUI.showDialog(currentGiver)
		end
	end)

	Remotes.event("OpenQuestDialog").OnClientEvent:Connect(function(giverId)
		App.Windows.open("QuestDialog", giverId)
	end)
end

return QuestUI
