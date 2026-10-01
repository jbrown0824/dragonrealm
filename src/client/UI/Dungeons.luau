-- The 🏰 Dungeons window (from level Dungeons.UNLOCK_LEVEL; I, the menu button, or a cave mouth
-- in the viking lands). Left: every dungeon (locked ones too, so you know what's coming), with
-- its boss, what it can drop, your clears, how many dragons are looking, and Enter now / Find
-- group. Right: your group: its dragons, invites waiting for you, and inviting others in the server.
-- The queue, ready checks and your run show on the small dungeon pill (DungeonHUD).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DungeonInfo = require(Shared.Config.Dungeons)
local Classes = require(Shared.Config.Classes)
local PetInfo = require(Shared.Config.Pets)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Dungeons = {}
local App

local window, list, groupPanel
local picked = nil -- the dungeon the window was opened on (a cave mouth)
local inviting = false -- the invite list is showing
local busy = false
local lastKey = ""
local friends = {} -- [userId] = true / false (asked once)

local player = Players.LocalPlayer

function Dungeons.send(action: string, args, okText: string?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, msg = Remotes.func("DungeonAction"):InvokeServer(action, args or {})
		busy = false
		if ok and (msg or okText) then
			App.Windows.notify(msg or okText, C.good, "🏰")
		elseif not ok and msg then
			App.Windows.notify(msg, C.bad, "🏰")
		end
	end)
end

local function levelOf(p: Player): number
	local stats = p:FindFirstChild("leaderstats")
	local level = stats and stats:FindFirstChild("Level")
	return level and level.Value or 1
end

local function isFriend(userId: number): boolean
	if friends[userId] == nil then
		friends[userId] = false
		task.spawn(function()
			local ok, yes = pcall(function()
				return player:IsFriendsWith(userId)
			end)
			friends[userId] = ok and yes == true
			if ok and yes and window.Visible then
				lastKey = ""
				Dungeons.refresh()
			end
		end)
	end
	return friends[userId]
end

---------------------------------------------------------------- dungeon cards

local function rewardLine(def): string
	local egg = PetInfo.Eggs[def.loot.egg]
	return string.format("🎁 Epic+ gear (Lv %d)  •  ✨ rare relics with lifesteal or regen\n%s %s: pets found nowhere else", def.ilvl, egg.icon, egg.name)
end

local function card(order: number, def, p, state)
	local locked = p.level < def.minLevel
	local clears = p.dungeons and p.dungeons.clears and p.dungeons.clears[def.id] or 0
	local looking = state and state.looking and state.looking[def.id] or 0
	local group = state and state.group
	local queued = state and state.queue and state.queue.dungeonId == def.id
	local leader = not group or group.leader == player.UserId
	local frame = Theme.make("Frame", { Name = def.id, Size = UDim2.new(1, -12, 0, 194), BackgroundColor3 = C.panel2, LayoutOrder = order, Parent = list })
	Theme.corner(frame, 10)
	Theme.stroke(frame, def.color, picked == def.id and 3 or 1.5, picked == def.id and 0 or 0.4)
	local boss = DungeonInfo.Bosses[def.boss.id]
	Theme.label({ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(56, 56), TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Text = locked and "🔒" or def.icon, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -170, 0, 26), Font = Theme.Fonts.title, TextSize = 22, TextColor3 = locked and C.subtext or def.color, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = def.name, Parent = frame })
	local tag = Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(84, 24), BackgroundTransparency = 0, BackgroundColor3 = locked and C.panel or def.color:Lerp(Color3.new(0, 0, 0), 0.55), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = "Lv " .. def.minLevel .. "+", Parent = frame })
	Theme.corner(tag, 6)
	Theme.label({ Position = UDim2.fromOffset(72, 36), Size = UDim2.new(1, -84, 0, 34), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextYAlignment = Enum.TextYAlignment.Top, Text = def.story, Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(12, 74), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.format("💀 Boss: %s   •   monsters Lv %d-%d   •   1-%d dragons", boss.name, def.level - 1, def.level + 1, DungeonInfo.MAX_GROUP), Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(12, 94), Size = UDim2.new(1, -24, 0, 32), TextSize = 12, TextColor3 = C.good, TextYAlignment = Enum.TextYAlignment.Top, Text = rewardLine(def), Parent = frame })
	Theme.label({ Position = UDim2.fromOffset(12, 128), Size = UDim2.new(1, -24, 0, 18), TextSize = 12, TextColor3 = C.subtext, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.format("%s  •  👀 %d looking", clears > 0 and string.format("✅ cleared %d time%s", clears, clears == 1 and "" or "s") or "not cleared yet", looking), Parent = frame })

	if locked then
		Theme.label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.fromOffset(260, 32), TextSize = 15, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Right, Text = "🔒 Unlocks at level " .. def.minLevel, Parent = frame })
		return
	end
	local busyElsewhere = (state and state.run) or (state and state.check)
	if queued then
		Theme.button("Leave queue", Color3.fromRGB(120, 60, 60), function()
			Dungeons.send("unqueue")
		end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.fromOffset(140, 34), TextSize = 14, Parent = frame })
		Theme.label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -160, 1, -10), Size = UDim2.fromOffset(150, 34), TextSize = 13, TextColor3 = def.color, TextXAlignment = Enum.TextXAlignment.Right, Text = "Looking for dragons...", Parent = frame })
		return
	end
	local size = group and #group.members or 1
	local enter = Theme.button(size > 1 and string.format("⚔️ Enter now (%d)", size) or "⚔️ Enter alone", Color3.fromRGB(70, 150, 80), function()
		Dungeons.send("enter", { dungeonId = def.id })
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.fromOffset(140, 34), TextSize = 14, Parent = frame })
	local find = Theme.button("🔍 Find group", Color3.fromRGB(70, 110, 170), function()
		Dungeons.send("queue", { dungeonId = def.id })
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -160, 1, -10), Size = UDim2.fromOffset(140, 34), TextSize = 14, Parent = frame })
	local canLead = leader and not busyElsewhere and not (state and state.queue)
	Theme.setButtonEnabled(enter, canLead)
	Theme.setButtonEnabled(find, canLead and size < DungeonInfo.MAX_GROUP)
	if not leader then
		Theme.onDisabledClick(enter, function()
			App.Windows.notify("Your group leader decides where the group goes.", C.subtext, "👑")
		end)
		Theme.onDisabledClick(find, function()
			App.Windows.notify("Your group leader decides where the group goes.", C.subtext, "👑")
		end)
	end
end

---------------------------------------------------------------- group panel

local function groupRow(parent: Instance, order: number, member, isLeader: boolean, canKick: boolean)
	local row = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.panel, LayoutOrder = order, Parent = parent })
	Theme.corner(row, 8)
	local class = member.class and Classes.get(member.class)
	Theme.label({ Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -60, 0, 20), TextSize = 15, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = (isLeader and "👑 " or "") .. member.name .. (member.userId == player.UserId and " (you)" or ""), Parent = row })
	Theme.label({ Position = UDim2.fromOffset(8, 23), Size = UDim2.new(1, -60, 0, 16), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext,
		Text = string.format("Lv %d %s", member.level, class and class.name or ""), Parent = row })
	if canKick then
		Theme.button("X", Color3.fromRGB(120, 60, 60), function()
			Dungeons.send("kick", { userId = member.userId })
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(32, 30), TextSize = 14, Parent = row })
	end
end

local function refreshGroup(state)
	Theme.clear(groupPanel)
	local holder = Theme.scroll(groupPanel, { Size = UDim2.fromScale(1, 1) })
	Theme.list(holder, 6)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	Theme.label({ Size = UDim2.new(1, -10, 0, 24), LayoutOrder = nextOrder(), Font = Theme.Fonts.title, TextSize = 19, TextColor3 = C.accent, Text = "👥 Your group", Parent = holder })
	for _, inv in ipairs(state and state.invites or {}) do
		local box = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 64), BackgroundColor3 = Color3.fromRGB(40, 70, 50), LayoutOrder = nextOrder(), Parent = holder })
		Theme.corner(box, 8)
		Theme.label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 22), TextSize = 14, Text = "🤝 " .. inv.from .. " invited you!", Parent = box })
		Theme.button("Join", C.good, function()
			Dungeons.send("accept", { groupId = inv.groupId })
		end, { Position = UDim2.fromOffset(8, 30), Size = UDim2.new(0.5, -12, 0, 28), TextSize = 14, Parent = box })
		Theme.button("No thanks", C.panel3, function()
			Dungeons.send("decline", { groupId = inv.groupId })
		end, { Position = UDim2.new(0.5, 4, 0, 30), Size = UDim2.new(0.5, -12, 0, 28), TextSize = 14, Parent = box })
	end
	local group = state and state.group
	local members = group and group.members or { { userId = player.UserId, name = player.DisplayName, level = App.State.profile and App.State.profile.level or 1, class = App.State.profile and App.State.profile.class } }
	local leaderId = group and group.leader or player.UserId
	local iLead = leaderId == player.UserId
	for _, m in ipairs(members) do
		groupRow(holder, nextOrder(), m, m.userId == leaderId, iLead and m.userId ~= player.UserId)
	end
	for _ = #members + 1, DungeonInfo.MAX_GROUP do
		local empty = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 30), BackgroundColor3 = C.panel, BackgroundTransparency = 0.5, LayoutOrder = nextOrder(), Parent = holder })
		Theme.corner(empty, 8)
		Theme.label({ Size = UDim2.fromScale(1, 1), TextSize = 12, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Center, Text = "empty spot", Parent = empty })
	end
	local buttons = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 32), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = holder })
	local invite = Theme.button(inviting and "Hide list" or "➕ Invite", Color3.fromRGB(70, 110, 170), function()
		inviting = not inviting
		lastKey = ""
		Dungeons.refresh()
	end, { Size = UDim2.new(0.5, -3, 1, 0), TextSize = 14, Parent = buttons })
	Theme.setButtonEnabled(invite, iLead and #members < DungeonInfo.MAX_GROUP and not (state and (state.queue or state.run)))
	local leave = Theme.button("Leave group", Color3.fromRGB(120, 60, 60), function()
		Dungeons.send("leaveGroup")
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, -3, 1, 0), TextSize = 14, Parent = buttons })
	Theme.setButtonEnabled(leave, group ~= nil and #members > 1)

	if inviting then
		local others = {}
		local inGroup = {}
		for _, m in ipairs(members) do
			inGroup[m.userId] = true
		end
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and not inGroup[other.UserId] then
				table.insert(others, other)
			end
		end
		table.sort(others, function(a, b)
			local fa, fb = isFriend(a.UserId), isFriend(b.UserId)
			if fa ~= fb then
				return fa
			end
			return levelOf(a) > levelOf(b)
		end)
		if #others == 0 then
			Theme.label({ Size = UDim2.new(1, -10, 0, 40), LayoutOrder = nextOrder(), TextSize = 12, TextColor3 = C.subtext, Text = "Nobody else is in this server right now.", Parent = holder })
		end
		for _, other in ipairs(others) do
			local row = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 36), BackgroundColor3 = C.panel, LayoutOrder = nextOrder(), Parent = holder })
			Theme.corner(row, 8)
			local level = levelOf(other)
			Theme.label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -96, 1, 0), TextSize = 13, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("%s%s  <font color=\"#B9AFD2\">Lv %d</font>", isFriend(other.UserId) and "⭐ " or "", other.DisplayName, level), Parent = row })
			local b = Theme.button("Invite", C.good, function()
				Dungeons.send("invite", { userId = other.UserId })
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(80, 28), TextSize = 13, Parent = row })
			Theme.setButtonEnabled(b, level >= DungeonInfo.UNLOCK_LEVEL)
			if level < DungeonInfo.UNLOCK_LEVEL then
				Theme.onDisabledClick(b, function()
					App.Windows.notify(string.format("%s needs to be level %d for dungeons.", other.DisplayName, DungeonInfo.UNLOCK_LEVEL), C.subtext, "🏰")
				end)
			end
		end
	end
	Theme.label({ Size = UDim2.new(1, -10, 0, 44), LayoutOrder = nextOrder(), TextSize = 11, Font = Theme.Fonts.body, TextColor3 = C.subtext,
		Text = "⭐ = your Roblox friends. Friend in another server? Join them from your friends list, then invite them here.", Parent = holder })
end

---------------------------------------------------------------- refresh

-- Everything the window shows, as one string: it's only rebuilt when this changes (the state
-- arrives every second for the pill's timers).
local function stateKey(p, state): string
	local parts = { tostring(p.level), tostring(inviting), tostring(picked) }
	for _, id in ipairs(DungeonInfo.Order) do
		table.insert(parts, tostring(p.dungeons and p.dungeons.clears and p.dungeons.clears[id] or 0))
		table.insert(parts, tostring(state and state.looking and state.looking[id] or 0))
	end
	if state then
		if state.group then
			table.insert(parts, "g" .. state.group.leader)
			for _, m in ipairs(state.group.members) do
				table.insert(parts, m.userId .. ":" .. m.level)
			end
		end
		table.insert(parts, state.queue and ("q" .. state.queue.dungeonId) or "-")
		table.insert(parts, state.check and "c" or "-")
		table.insert(parts, state.run and "r" or "-")
		for _, inv in ipairs(state.invites or {}) do
			table.insert(parts, "i" .. inv.groupId)
		end
	end
	if inviting then
		for _, other in ipairs(Players:GetPlayers()) do
			table.insert(parts, other.UserId .. ":" .. levelOf(other) .. tostring(friends[other.UserId]))
		end
	end
	return table.concat(parts, ",")
end

function Dungeons.refresh()
	local p = App.State.profile
	if not p or not window.Visible then
		return
	end
	local state = App.State.dungeon
	local key = stateKey(p, state)
	if key == lastKey then
		return
	end
	lastKey = key
	Theme.clear(list)
	for i, id in ipairs(DungeonInfo.Order) do
		card(i, DungeonInfo.List[id], p, state)
	end
	refreshGroup(state)
end

function Dungeons.open(dungeonId: string?)
	App.Windows.open("Dungeons", dungeonId)
end

local function onOpen(dungeonId)
	picked = type(dungeonId) == "string" and dungeonId or nil
	lastKey = ""
	Dungeons.refresh()
	-- the 🏰 badge clears once you've seen the window
	local p = App.State.profile
	if p then
		local best = 0
		for _, id in ipairs(DungeonInfo.unlocked(p.level)) do
			best = math.max(best, DungeonInfo.List[id].minLevel)
		end
		if best > ((p.dungeons and p.dungeons.seen) or 0) then
			task.spawn(function()
				Remotes.func("DungeonAction"):InvokeServer("seen", {})
			end)
		end
	end
end

function Dungeons.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🏰 Dungeons", Vector2.new(800, 540))
	close.Activated:Connect(function()
		App.Windows.close("Dungeons")
	end)
	Theme.label({ Size = UDim2.new(1, -290, 0, 22), TextSize = 13, TextColor3 = C.subtext,
		Text = "Groups of up to " .. DungeonInfo.MAX_GROUP .. " dragons. Everyone gets their own loot.", Parent = content })
	list = Theme.scroll(content, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -290, 1, -26) })
	Theme.list(list, 8)
	groupPanel = Theme.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 280, 1, 0), BackgroundColor3 = C.panel2, Parent = content })
	Theme.corner(groupPanel, 10)
	Theme.pad(groupPanel, 6)
	App.Windows.register("Dungeons", window, onOpen)
	App.State.changed:Connect(Dungeons.refresh)
	App.State.dungeonChanged:Connect(Dungeons.refresh)
end

return Dungeons
