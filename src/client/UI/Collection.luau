-- The 📖 Collection window (L): the pet book with its milestones, achievements, and the skins
-- and titles they unlock. Rewards arrive by themselves when you reach them (AchievementService);
-- this window shows progress and lets you pick a skin and a title.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Collections = require(Shared.Config.Collections)
local Skins = require(Shared.Config.Skins)
local PetInfo = require(Shared.Config.Pets)
local StatCalc = require(Shared.StatCalc)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Collection = {}
local App

local window, pages, tabButtons = nil, {}, {}
local tab = "Pets"
local busy = false
local TABS = { { id = "Pets", label = "📖 Pet Book" }, { id = "Achievements", label = "🏆 Achievements" }, { id = "Skins", label = "🎨 Skins & Titles" } }

local function statText(stats): string
	local parts = {}
	for stat, v in pairs(stats) do
		local info = StatCalc.STAT_INFO[stat]
		table.insert(parts, string.format("+%s%% %s", Util.fmt(v), info and info.label or stat))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

function Collection.rewardText(reward): string
	local parts = {}
	if reward.gold then
		table.insert(parts, Util.formatNumber(reward.gold) .. " gold")
	end
	if reward.treats then
		table.insert(parts, reward.treats .. " 🍬")
	end
	for eggId, n in pairs(reward.eggs or {}) do
		local egg = PetInfo.Eggs[eggId]
		table.insert(parts, (n > 1 and (n .. "x ") or "") .. egg.icon .. " " .. egg.name)
	end
	if reward.skin then
		table.insert(parts, "🎨 " .. Skins.get(reward.skin).name .. " skin")
	end
	if reward.title then
		table.insert(parts, "🏷️ \"" .. reward.title .. "\"")
	end
	return table.concat(parts, ", ")
end

local function invoke(remote: string, arg, okText: string?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, err = Remotes.func(remote):InvokeServer(arg)
		busy = false
		if ok and okText then
			App.Windows.notify(okText, C.good, "📖")
		elseif not ok and err then
			App.Windows.notify(err, C.bad, "📖")
		end
	end)
end

-- A thin progress bar.
local function progress(parent: Instance, pos: UDim2, size: UDim2, fraction: number, color: Color3)
	local back = Theme.make("Frame", { Position = pos, Size = size, BackgroundColor3 = C.bg, Parent = parent })
	Theme.corner(back, 4)
	local fill = Theme.make("Frame", { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1), BackgroundColor3 = color, Parent = back })
	Theme.corner(fill, 4)
end

---------------------------------------------------------------- pet book

-- The eggs a species can hatch from (eggs with species of their own, like the dungeon eggs, only
-- hatch those).
local function eggsFor(speciesId: string, rarity: string): string
	local names = {}
	for _, eggId in ipairs(PetInfo.EggOrder) do
		local egg = PetInfo.Eggs[eggId]
		if egg.weights[rarity] and table.find(PetInfo.speciesFor(eggId, rarity), speciesId) then
			table.insert(names, egg.name)
		end
	end
	return table.concat(names, ", ")
end

local function refreshPets(p)
	local page = pages.Pets
	Theme.clear(page.grid)
	Theme.clear(page.milestones)
	local book = p.petBook or {}
	local species, golden, total = 0, 0, 0
	local all = {}
	for id, s in pairs(PetInfo.Species) do
		table.insert(all, { id = id, s = s })
		total += 1
		if book[id] then
			species += 1
			if book[id] >= 2 then
				golden += 1
			end
		end
	end
	table.sort(all, function(a, b)
		local ra, rb = table.find(PetInfo.RarityOrder, a.s.rarity), table.find(PetInfo.RarityOrder, b.s.rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.s.name < b.s.name
	end)
	page.header.Text = string.format("Species found: <font color=\"#FFD24A\">%d / %d</font>   •   Made golden: <font color=\"#FFD24A\">%d / %d</font>", species, total, golden, total)
	for i, entry in ipairs(all) do
		local s = entry.s
		local state = book[entry.id] or 0
		local color = PetInfo.RarityColors[s.rarity]
		local cell = Theme.make("Frame", { BackgroundColor3 = state >= 2 and Color3.fromRGB(80, 64, 26) or (state > 0 and C.panel2 or C.bg), LayoutOrder = i, Parent = page.grid })
		Theme.corner(cell, 8)
		Theme.stroke(cell, color, state > 0 and 1.5 or 1, state > 0 and 0.2 or 0.7)
		Theme.label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 20), TextSize = 14, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = state > 0 and color or C.subtext, Text = (state >= 2 and "✨ " or "") .. (state > 0 and s.name or "???"), Parent = cell })
		Theme.label({ Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 16), TextSize = 11, TextColor3 = color, Text = s.rarity, Parent = cell })
		Theme.label({ Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 0, 30), TextSize = 10, Font = Theme.Fonts.body, TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = state > 0 and C.good or C.subtext, Text = state > 0 and statText(s.stats) or ("From: " .. eggsFor(entry.id, s.rarity)), Parent = cell })
	end
	for i, m in ipairs(Collections.PetMilestones) do
		local done = p.milestones and p.milestones["m" .. i]
		local have = m.kind == "golden" and golden or species
		local row = Theme.make("Frame", { Size = UDim2.new(1, -6, 0, 50), BackgroundColor3 = done and Color3.fromRGB(40, 70, 45) or C.panel2, LayoutOrder = i, Parent = page.milestones })
		Theme.corner(row, 8)
		Theme.label({ Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 18), TextSize = 13, TextColor3 = done and C.good or C.text,
			Text = (done and "✅ " or "") .. (m.kind == "golden" and string.format("Make %d pet%s golden", m.count, m.count == 1 and "" or "s") or string.format("Find %d species", m.count)), Parent = row })
		Theme.label({ Position = UDim2.fromOffset(8, 20), Size = UDim2.new(1, -16, 0, 16), TextSize = 10, Font = Theme.Fonts.body, TextColor3 = C.gold, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = Collection.rewardText(m.reward), Parent = row })
		progress(row, UDim2.fromOffset(8, 39), UDim2.new(1, -16, 0, 6), have / m.count, done and C.good or C.accent)
	end
end

---------------------------------------------------------------- achievements

local function statValue(p, stat: string): number
	return tonumber(p[stat]) or 0
end

local function refreshAchievements(p)
	local list = pages.Achievements.list
	Theme.clear(list)
	for i, a in ipairs(Collections.Achievements) do
		local reached = p.achievements and p.achievements[a.id] or 0
		local value = statValue(p, a.stat)
		local nextTier = a.tiers[reached + 1]
		local row = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 70), BackgroundColor3 = C.panel2, LayoutOrder = i, Parent = list })
		Theme.corner(row, 10)
		Theme.stroke(row, reached >= #a.tiers and C.gold or C.accentDark, 1.5, 0.3)
		Theme.label({ Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(52, 56), TextSize = 36, TextXAlignment = Enum.TextXAlignment.Center, Text = a.icon, Parent = row })
		Theme.label({ Position = UDim2.fromOffset(66, 6), Size = UDim2.fromOffset(260, 22), Font = Theme.Fonts.title, TextSize = 19, Text = a.name, Parent = row })
		-- tier medals: drawn circles, filled when reached
		for t = 1, #a.tiers do
			local medal = Theme.make("Frame", { Position = UDim2.fromOffset(300 + (t - 1) * 22, 9), Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = t <= reached and ({ Color3.fromRGB(205, 127, 50), Color3.fromRGB(200, 200, 210), C.gold })[t] or C.bg, Parent = row })
			Theme.corner(medal, 8)
			Theme.stroke(medal, C.accentDark, 1.5, t <= reached and 0 or 0.4)
		end
		if nextTier then
			Theme.label({ Position = UDim2.fromOffset(66, 30), Size = UDim2.new(1, -80, 0, 16), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext,
				Text = string.format("%s: %s / %s   •   <font color=\"#FFD24A\">Next: %s</font>", a.desc, Util.formatNumber(value), Util.formatNumber(nextTier.count), Collection.rewardText(nextTier.reward)), Parent = row })
			progress(row, UDim2.fromOffset(66, 52), UDim2.new(1, -80, 0, 8), value / nextTier.count, C.accent)
		else
			Theme.label({ Position = UDim2.fromOffset(66, 32), Size = UDim2.new(1, -80, 0, 30), TextSize = 13, TextColor3 = C.good, Text = "Complete! " .. a.desc .. ": " .. Util.formatNumber(value), Parent = row })
		end
	end
end

---------------------------------------------------------------- skins and titles

local function swatch(parent: Instance, colors, x: number)
	for k, key in ipairs({ "primary", "secondary", "belly", "accent" }) do
		local sq = Theme.make("Frame", { Position = UDim2.fromOffset(x + (k - 1) * 20, 30), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = colors[key], Parent = parent })
		Theme.corner(sq, 4)
	end
end

local function refreshSkins(p)
	local page = pages.Skins
	Theme.clear(page.grid)
	Theme.clear(page.titles)
	for i, id in ipairs(Skins.Order) do
		local skin = Skins.get(id)
		local have = id == "Classic" or (p.skins and p.skins[id])
		local equipped = (p.skin or "Classic") == id
		local cell = Theme.make("Frame", { BackgroundColor3 = equipped and Color3.fromRGB(40, 70, 45) or C.panel2, LayoutOrder = i, Parent = page.grid })
		Theme.corner(cell, 8)
		Theme.stroke(cell, equipped and C.good or C.accentDark, equipped and 2.5 or 1, have and 0.2 or 0.6)
		Theme.label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 22), Font = Theme.Fonts.title, TextSize = 17, TextColor3 = have and C.text or C.subtext, Text = (have and "" or "🔒 ") .. skin.name, Parent = cell })
		if skin.colors then
			swatch(cell, skin.colors, 8)
		else
			Theme.label({ Position = UDim2.fromOffset(8, 30), Size = UDim2.new(1, -16, 0, 18), TextSize = 12, TextColor3 = C.subtext, Text = "Your dragon's own colors", Parent = cell })
		end
		if have then
			local b = Theme.button(equipped and "Wearing" or "Wear", Color3.fromRGB(60, 140, 70), function()
				invoke("SetSkin", id, "Now wearing " .. skin.name .. "!")
			end, { Position = UDim2.new(0, 8, 1, -34), Size = UDim2.new(1, -16, 0, 28), TextSize = 14, Parent = cell })
			Theme.setButtonEnabled(b, not equipped)
		else
			Theme.label({ Position = UDim2.new(0, 8, 1, -38), Size = UDim2.new(1, -16, 0, 34), TextSize = 10, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextYAlignment = Enum.TextYAlignment.Top, Text = skin.unlock, Parent = cell })
		end
	end
	-- titles: "None" plus every title, earned ones selectable
	local titles = { "" }
	for _, t in ipairs(Collections.allTitles()) do
		table.insert(titles, t)
	end
	for i, t in ipairs(titles) do
		local have = t == "" or (p.titles and p.titles[t])
		local chosen = (p.title or "") == t
		local b = Theme.button((chosen and "✅ " or (have and "" or "🔒 ")) .. (t == "" and "No title" or t), chosen and Color3.fromRGB(60, 120, 70) or C.panel3, function()
			invoke("SetTitle", t, t == "" and "Title removed." or ("Your title is now \"" .. t .. "\"!"))
		end, { Size = UDim2.new(1, -6, 0, 30), TextSize = 13, LayoutOrder = i, Parent = page.titles })
		Theme.setButtonEnabled(b, have and not chosen)
	end
end

---------------------------------------------------------------- window

function Collection.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	for _, t in ipairs(TABS) do
		pages[t.id].frame.Visible = tab == t.id
		tabButtons[t.id].BackgroundColor3 = tab == t.id and C.accentDark or C.panel3
	end
	if tab == "Pets" then
		refreshPets(p)
	elseif tab == "Achievements" then
		refreshAchievements(p)
	else
		refreshSkins(p)
	end
end

function Collection.open(which: string?)
	tab = which or tab
	App.Windows.open("Collection")
end

function Collection.init(app)
	App = app
	local content, close
	window, content, close = Theme.window(App.Windows.guis.Windows, "📖 Collection", Vector2.new(880, 600))
	close.Activated:Connect(function()
		App.Windows.close("Collection")
	end)
	for i, t in ipairs(TABS) do
		tabButtons[t.id] = Theme.button(t.label, C.panel3, function()
			tab = t.id
			Collection.refresh()
		end, { Position = UDim2.fromOffset((i - 1) * 180, 0), Size = UDim2.fromOffset(170, 32), TextSize = 15, Parent = content })
	end
	local function page(id: string)
		local frame = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Visible = false, Parent = content })
		pages[id] = { frame = frame }
		return pages[id]
	end

	local pets = page("Pets")
	pets.header = Theme.label({ Size = UDim2.new(1, 0, 0, 22), TextSize = 15, Parent = pets.frame })
	pets.grid = Theme.scroll(pets.frame, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -250, 1, -28) })
	Theme.make("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 74), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pets.grid })
	Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 28), Size = UDim2.fromOffset(240, 20), TextSize = 14, TextColor3 = C.accent, Text = "Milestones", Parent = pets.frame })
	pets.milestones = Theme.scroll(pets.frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 50), Size = UDim2.new(0, 240, 1, -50) })
	Theme.list(pets.milestones, 6)

	local achievements = page("Achievements")
	achievements.list = Theme.scroll(achievements.frame, { Size = UDim2.fromScale(1, 1) })
	Theme.list(achievements.list, 8)

	local skins = page("Skins")
	Theme.label({ Size = UDim2.new(1, -260, 0, 22), TextSize = 14, TextColor3 = C.subtext, Text = "Skins change your dragon's colors. Earn them from achievements and the pet book.", Parent = skins.frame })
	skins.grid = Theme.scroll(skins.frame, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -260, 1, -28) })
	Theme.make("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 96), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = skins.grid })
	Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(250, 22), TextSize = 14, TextColor3 = C.accent, Text = "🏷️ Title (shown over your name)", Parent = skins.frame })
	skins.titles = Theme.scroll(skins.frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 28), Size = UDim2.new(0, 250, 1, -28) })
	Theme.list(skins.titles, 5)

	App.Windows.register("Collection", window, Collection.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Collection.refresh()
		end
	end)
end

return Collection
