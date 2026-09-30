-- Admin panel (unlocked by typing the admin code in 🎁 Codes). Every button asks the server
-- (AdminService), which checks you're really an admin.
--   Dragon:  level 1-30 and Paragon, dragon type, gold, gear, eggs, pets (any species, golden,
--            levelled), treats, the pet book, skins, titles, achievements, Robux passes and
--            products (test grants), potions, hunger, god mode, teleports...
--            for yourself or any player you pick at the top
--   World:   start a boss, respawn camps, refill chests, restock or close the shops, set the
--            time of day, start or end a night raid, burn and rebuild houses, jump into a dungeon
--   Balance: live multipliers for ability damage/cooldowns, skill values, global rates, the
--            lifesteal / regen caps and each dungeon, plus "Print changes" to copy the new
--            numbers into the Config files

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Classes = require(Shared.Config.Classes)
local Abilities = require(Shared.Config.Abilities)
local Talents = require(Shared.Config.Talents)
local Items = require(Shared.Config.Items)
local Pets = require(Shared.Config.Pets)
local Skins = require(Shared.Config.Skins)
local Collections = require(Shared.Config.Collections)
local StoreInfo = require(Shared.Config.Store)
local Dungeons = require(Shared.Config.Dungeons)
local Zones = require(Shared.Config.Zones)
local Tuning = require(Shared.Tuning)
local TalentUtil = require(Shared.TalentUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Admin = {}
local App

local window, content
local tab = "Dragon"
local tabButtons = {}
local pages = {}
local targetButton, statusLabel
local targetId = nil
local balanceList, reportBox
local levelBox, paragonBox
local petGolden, petLevel = false, 1

local function target(): Player
	return (targetId and Players:GetPlayerByUserId(targetId)) or Players.LocalPlayer
end

local function act(action: string, args, quiet: boolean?)
	args = args or {}
	args.userId = target().UserId
	statusLabel.Text = "…"
	task.spawn(function()
		local ok, message = Remotes.func("AdminAction"):InvokeServer(action, args)
		statusLabel.Text = message or (ok and "Done." or "Failed.")
		statusLabel.TextColor3 = ok and C.good or C.bad
		if action == "printTuning" and ok then
			reportBox.Text = message
			statusLabel.Text = "Report printed to the server Output too."
		end
		if not quiet and ok then
			App.Sfx.play("Click")
		end
	end)
end

---------------------------------------------------------------- layout helpers

local function section(parent: Instance, order: number, title: string)
	local frame = Theme.make("Frame", { Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel2, LayoutOrder = order, Parent = parent })
	Theme.corner(frame, 8)
	Theme.pad(frame, 8)
	Theme.list(frame, 6)
	Theme.label({ Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = C.accent, Text = title, LayoutOrder = 0, Parent = frame })
	local row = Theme.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = frame })
	Theme.make("UIGridLayout", { CellSize = UDim2.fromOffset(118, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	return row, frame
end

local function button(parent: Instance, text: string, color: Color3?, fn)
	return Theme.button(text, color or C.panel3, fn, { TextSize = 13, TextWrapped = true, Parent = parent })
end

---------------------------------------------------------------- Dragon page

local function buildDragonPage(page: Instance)
	local scroll = Theme.scroll(page, { Size = UDim2.fromScale(1, 1) })
	Theme.list(scroll, 8)

	local levelRow = section(scroll, 1, "⭐ Level (skill points above the new total are refunded)")
	levelBox = Theme.make("TextBox", { BackgroundColor3 = C.panel, TextColor3 = C.text, Font = Theme.Fonts.bold, TextSize = 16, Text = "30", PlaceholderText = "1-30", Parent = levelRow })
	Theme.corner(levelBox, 6)
	button(levelRow, "Set level", Color3.fromRGB(70, 120, 180), function()
		act("setLevel", { level = tonumber(levelBox.Text) or 1 })
	end)
	for _, lvl in ipairs({ 1, 5, 10, 15, 20, 25, 30 }) do
		button(levelRow, "Lv " .. lvl, nil, function()
			levelBox.Text = tostring(lvl)
			act("setLevel", { level = lvl })
		end)
	end
	button(levelRow, "Refund skills", nil, function()
		act("resetTalents")
	end)

	local paragonRow = section(scroll, 2, "💫 Paragon (sets level 30; a skill point every " .. Game.PARAGON_POINT_EVERY .. ")")
	paragonBox = Theme.make("TextBox", { BackgroundColor3 = C.panel, TextColor3 = C.text, Font = Theme.Fonts.bold, TextSize = 16, Text = "10", PlaceholderText = "0+", Parent = paragonRow })
	Theme.corner(paragonBox, 6)
	button(paragonRow, "Set Paragon", Color3.fromRGB(120, 80, 170), function()
		act("setParagon", { value = tonumber(paragonBox.Text) or 0 })
	end)
	for _, amount in ipairs({ 1, 5, 25 }) do
		button(paragonRow, "+" .. amount .. " Paragon", nil, function()
			act("addParagon", { amount = amount })
		end)
	end
	for _, value in ipairs({ 0, 100 }) do
		button(paragonRow, "Paragon " .. value, nil, function()
			act("setParagon", { value = value })
		end)
	end

	local classRow = section(scroll, 3, "🐉 Dragon type (free, instant)")
	for _, classId in ipairs(Classes.Order) do
		button(classRow, classId, Classes.get(classId).colors.accent:Lerp(Color3.new(0, 0, 0), 0.45), function()
			act("setClass", { classId = classId })
		end)
	end

	local giveRow = section(scroll, 4, "🎁 Give")
	for _, amount in ipairs({ 1000, 10000, 100000 }) do
		button(giveRow, "+" .. Util.formatNumber(amount) .. " 💰", Color3.fromRGB(150, 120, 40), function()
			act("gold", { amount = amount })
		end)
	end
	for _, rarity in ipairs(Items.RarityOrder) do
		button(giveRow, rarity .. " gear", Items.Rarities[rarity].color:Lerp(Color3.new(0, 0, 0), 0.5), function()
			act("item", { rarity = rarity })
		end)
	end
	for _, eggId in ipairs(Pets.EggOrder) do
		button(giveRow, Pets.Eggs[eggId].icon .. " " .. Pets.Eggs[eggId].name, nil, function()
			act("egg", { eggId = eggId })
		end)
	end
	button(giveRow, "🌱 All seeds x3", nil, function()
		act("seeds")
	end)
	button(giveRow, "🍖 Food", nil, function()
		act("food")
	end)
	button(giveRow, "🧪 Max potions", nil, function()
		act("potions", { rank = 5 })
	end)
	button(giveRow, "🧪 Clear potions", nil, function()
		act("potions", { rank = 0 })
	end)
	button(giveRow, "🤖 All robots", nil, function()
		act("robots")
	end)
	button(giveRow, "🌱 Unlock plots", nil, function()
		act("unlockPlots")
	end)

	-- pets: pick golden / level first, then a species
	local petRow = section(scroll, 5, "🐲 Pets (choose golden and level, then a species) and treats")
	local goldenButton, levelButton
	goldenButton = button(petRow, "Golden: no", Color3.fromRGB(150, 120, 40), function()
		petGolden = not petGolden
		goldenButton.Text = petGolden and "Golden: YES" or "Golden: no"
	end)
	levelButton = button(petRow, "Level: 1", Color3.fromRGB(150, 120, 40), function()
		petLevel = petLevel % Pets.MAX_LEVEL + 1
		levelButton.Text = "Level: " .. petLevel
	end)
	local species = {}
	for id, s in pairs(Pets.Species) do
		table.insert(species, { id = id, s = s })
	end
	table.sort(species, function(a, b)
		local ra, rb = table.find(Pets.RarityOrder, a.s.rarity), table.find(Pets.RarityOrder, b.s.rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.s.name < b.s.name
	end)
	for _, entry in ipairs(species) do
		button(petRow, entry.s.name, Pets.RarityColors[entry.s.rarity]:Lerp(Color3.new(0, 0, 0), 0.55), function()
			act("pet", { species = entry.id, golden = petGolden, level = petLevel })
		end)
	end
	for _, amount in ipairs({ 20, 200 }) do
		button(petRow, "+" .. amount .. " 🍬 treats", nil, function()
			act("treats", { amount = amount })
		end)
	end
	button(petRow, "Release all pets", Color3.fromRGB(120, 50, 60), function()
		act("clearPets")
	end)

	local bookRow = section(scroll, 6, "📖 Collection: pet book, achievements, skins, titles")
	button(bookRow, "Book: all found", nil, function()
		act("petBook", { mode = "found" })
	end)
	button(bookRow, "Book: all golden", nil, function()
		act("petBook", { mode = "golden" })
	end)
	button(bookRow, "Book: clear", Color3.fromRGB(120, 50, 60), function()
		act("petBook", { mode = "clear" })
	end)
	button(bookRow, "Max achievements", Color3.fromRGB(150, 120, 40), function()
		act("achievements", { mode = "reach" })
	end)
	button(bookRow, "Reset achievements", Color3.fromRGB(120, 50, 60), function()
		act("achievements", { mode = "reset" })
	end)
	button(bookRow, "Unlock all skins", Color3.fromRGB(150, 120, 40), function()
		act("skins", { mode = "unlockAll" })
	end)
	button(bookRow, "Lock all skins", Color3.fromRGB(120, 50, 60), function()
		act("skins", { mode = "lockAll" })
	end)
	button(bookRow, "Unlock all titles", Color3.fromRGB(150, 120, 40), function()
		act("titles", { mode = "unlockAll" })
	end)
	button(bookRow, "Clear titles", Color3.fromRGB(120, 50, 60), function()
		act("titles", { mode = "clear" })
	end)
	local skinRow = section(scroll, 7, "🎨 Wear a skin (unlocks it)")
	for _, id in ipairs(Skins.Order) do
		local skin = Skins.get(id)
		-- tint the button with the skin's main color, darker for pale skins so white text still reads
		local tint = nil
		if skin.colors then
			local c = skin.colors.primary
			tint = c:Lerp(Color3.new(0, 0, 0), (c.R + c.G + c.B) > 1.8 and 0.6 or 0.35)
		end
		button(skinRow, skin.name, tint, function()
			act("skins", { mode = "wear", skin = id })
		end)
	end
	local titleRow = section(scroll, 8, "🏷️ Set a title (unlocks it)")
	button(titleRow, "No title", nil, function()
		act("titles", { mode = "set", title = "" })
	end)
	for _, title in ipairs(Collections.allTitles()) do
		button(titleRow, title, nil, function()
			act("titles", { mode = "set", title = title })
		end)
	end

	local storeRow = section(scroll, 9, "💎 Store (test grants: no Robux involved)")
	for _, passId in ipairs(StoreInfo.PassOrder) do
		local pass = StoreInfo.Passes[passId]
		button(storeRow, pass.name .. " on", Color3.fromRGB(40, 130, 70), function()
			act("pass", { pass = passId, on = true })
		end)
		button(storeRow, pass.name .. " off", nil, function()
			act("pass", { pass = passId, on = false })
		end)
	end
	for _, key in ipairs(StoreInfo.ProductOrder) do
		local product = StoreInfo.Products[key]
		button(storeRow, product.icon .. " " .. product.name, Color3.fromRGB(40, 110, 70), function()
			act("product", { product = key })
		end)
	end
	button(storeRow, "Reset Starter Pack", nil, function()
		act("starterReset")
	end)
	button(storeRow, "Restock their shops", nil, function()
		act("restockMine")
	end)

	local stateRow = section(scroll, 10, "❤️ State")
	button(stateRow, "Heal", nil, function()
		act("heal")
	end)
	button(stateRow, "Fill hunger", nil, function()
		act("hunger", { value = Game.HUNGER_MAX })
	end)
	button(stateRow, "Hungry (25)", nil, function()
		act("hunger", { value = 25 })
	end)
	button(stateRow, "Starving (5)", nil, function()
		act("hunger", { value = 5 })
	end)
	button(stateRow, "God mode on", Color3.fromRGB(150, 120, 40), function()
		act("god", { on = true })
	end)
	button(stateRow, "God mode off", nil, function()
		act("god", { on = false })
	end)
	button(stateRow, "No cooldowns on", Color3.fromRGB(150, 120, 40), function()
		act("noCooldowns", { on = true })
	end)
	button(stateRow, "No cooldowns off", nil, function()
		act("noCooldowns", { on = false })
	end)
	button(stateRow, "Restart tutorial", nil, function()
		act("tutorial")
	end)

	local tpRow = section(scroll, 11, "🧭 Teleport")
	local places = { "Town", "Training" }
	for _, camp in ipairs(Zones.Camps) do
		table.insert(places, camp.id)
	end
	for _, area in ipairs(Zones.HuntingGrounds) do
		table.insert(places, area.id)
	end
	for _, place in ipairs(places) do
		button(tpRow, place, nil, function()
			act("teleport", { place = place })
		end)
	end
end

---------------------------------------------------------------- World page

local function buildWorldPage(page: Instance)
	local scroll = Theme.scroll(page, { Size = UDim2.fromScale(1, 1) })
	Theme.list(scroll, 8)
	local bossRow = section(scroll, 1, "👑 World boss")
	for _, seconds in ipairs({ 10, 30, 60 }) do
		button(bossRow, "Boss in " .. seconds .. "s", Color3.fromRGB(160, 60, 50), function()
			act("bossNow", { seconds = seconds })
		end)
	end
	local campRow = section(scroll, 2, "⛺ Viking camps")
	button(campRow, "Respawn vikings", nil, function()
		act("respawnCamps")
	end)
	button(campRow, "Refill chests", nil, function()
		act("resetChests")
	end)
	button(campRow, "Respawn champions", nil, function()
		act("miniBosses")
	end)
	local shopRow = section(scroll, 3, "🛒 Shops")
	button(shopRow, "Restock shops", nil, function()
		act("restockShops")
	end)
	button(shopRow, "Close shops 60s", nil, function()
		act("shops", { seconds = 60 })
	end)
	button(shopRow, "Reopen shops", nil, function()
		act("shops", { open = true })
	end)
	local timeRow = section(scroll, 4, "🌗 Time of day (night falls at 18:00)")
	for _, entry in ipairs({ { "🌅 Dawn", 6 }, { "☀️ Noon", 12 }, { "🌇 Dusk soon", 17.8 }, { "🌙 Midnight", 0 } }) do
		button(timeRow, entry[1], nil, function()
			act("setHour", { hour = entry[2] })
		end)
	end
	local raidRow = section(scroll, 5, "⚔️ Night raids")
	button(raidRow, "Raid now", Color3.fromRGB(160, 60, 50), function()
		act("raidNow")
	end)
	button(raidRow, "End: repelled", nil, function()
		act("raidEnd", { won = true })
	end)
	button(raidRow, "End: lost", nil, function()
		act("raidEnd", { won = false })
	end)
	button(raidRow, "Set a house on fire", nil, function()
		act("burnHouse")
	end)
	button(raidRow, "Rebuild houses", nil, function()
		act("rebuildHouses")
	end)
	local dungeonRow = section(scroll, 6, "🏰 Dungeons (for the dragon picked at the top: alone, any level)")
	for _, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		button(dungeonRow, "Enter " .. def.name:gsub("^The ", ""), def.color:Lerp(Color3.new(0, 0, 0), 0.55), function()
			act("enterDungeon", { dungeonId = id })
		end)
	end
	button(dungeonRow, "Reset clears & pity", Color3.fromRGB(120, 50, 60), function()
		act("dungeonReset")
	end)
end

---------------------------------------------------------------- Balance page

local function stepper(parent: Instance, order: number, label: string, value: number, detail: string, onChange)
	local row = Theme.make("Frame", { Size = UDim2.new(1, -12, 0, 34), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.3, LayoutOrder = order, Parent = parent })
	Theme.corner(row, 6)
	Theme.label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0.34, 0, 1, 0), TextSize = 13, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = label, Parent = row })
	Theme.label({ Position = UDim2.new(0.34, 8, 0, 0), Size = UDim2.new(0.66, -190, 1, 0), TextSize = 11, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = detail, Parent = row })
	local changed = value ~= 1
	Theme.label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 0), Size = UDim2.fromOffset(60, 26), TextSize = 14, TextColor3 = changed and C.accent or C.text, TextXAlignment = Enum.TextXAlignment.Center, Text = "x" .. Util.fmt(value), Parent = row })
	Theme.button("-", C.panel3, function()
		onChange(math.max(0, Util.round(value - 0.1, 2)))
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -124, 0.5, 0), Size = UDim2.fromOffset(28, 26), Parent = row })
	Theme.button("+", C.panel3, function()
		onChange(Util.round(value + 0.1, 2))
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -32, 0.5, 0), Size = UDim2.fromOffset(28, 26), Parent = row })
	Theme.button("1x", C.panel3, function()
		onChange(1)
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0), Size = UDim2.fromOffset(28, 26), Parent = row })
end

local function header(parent: Instance, order: number, text: string)
	Theme.label({ Size = UDim2.new(1, -12, 0, 24), LayoutOrder = order, Font = Theme.Fonts.title, TextSize = 17, TextColor3 = C.accent, Text = text, Parent = parent })
end

function Admin.refreshBalance()
	if not balanceList then
		return
	end
	Theme.clear(balanceList)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	header(balanceList, nextOrder(), "🌍 Global (everyone on the server)")
	for _, key in ipairs(Tuning.GLOBAL_KEYS) do
		stepper(balanceList, nextOrder(), Tuning.GLOBAL_LABELS[key], Tuning.global(key), "", function(v)
			act("tuneGlobal", { key = key, value = v }, true)
		end)
	end

	header(balanceList, nextOrder(), "❤️ Lifesteal & regen caps")
	local capBase = { lifestealCap = Game.LIFESTEAL_CAP, regenCap = Game.REGEN_CAP, extraLifestealCap = Game.EXTRA_LIFESTEAL_CAP, extraRegenCap = Game.EXTRA_REGEN_CAP }
	for _, key in ipairs(Tuning.CAP_KEYS) do
		local v = Tuning.global(key)
		stepper(balanceList, nextOrder(), Tuning.GLOBAL_LABELS[key], v, string.format("%s%% → %s%%%s", Util.fmt(capBase[key]), Util.fmt(Util.round(capBase[key] * v, 2)), key:find("egen") and " of max health /s" or ""), function(x)
			act("tuneGlobal", { key = key, value = x }, true)
		end)
	end

	header(balanceList, nextOrder(), "🏰 Dungeons (new runs use these)")
	local scaling = Tuning.global("groupScaling")
	local parts = {}
	for n = 1, 3 do
		table.insert(parts, string.format("%d: x%s", n, Util.fmt(Util.round(math.max(0.1, 1 - (1 - Dungeons.GROUP_HEALTH[n]) * scaling), 2))))
	end
	stepper(balanceList, nextOrder(), Tuning.GLOBAL_LABELS.groupScaling, scaling, "health for groups of " .. table.concat(parts, ", "), function(x)
		act("tuneGlobal", { key = "groupScaling", value = x }, true)
	end)
	for _, id in ipairs(Dungeons.Order) do
		local def = Dungeons.List[id]
		for _, key in ipairs(Tuning.DUNGEON_KEYS) do
			local detail = ""
			if key == "bossHp" then
				detail = string.format("%s %s HP (for 4)", def.icon, Util.formatNumber(Dungeons.Bosses[def.boss.id].health * Tuning.dungeon(id, key)))
			elseif key == "loot" then
				detail = string.format("relic %s%%, egg %s%%", Util.fmt(Dungeons.UNIQUE_CHANCE * 100 * Tuning.dungeon(id, key)), Util.fmt(Dungeons.EGG_CHANCE * 100 * Tuning.dungeon(id, key)))
			end
			stepper(balanceList, nextOrder(), def.icon .. " " .. def.name:gsub("^The ", "") .. ": " .. Tuning.DUNGEON_LABELS[key], Tuning.dungeon(id, key), detail, function(x)
				act("tuneDungeon", { dungeonId = id, key = key, value = x }, true)
			end)
		end
	end

	local p = App.State.profile
	local classId = (target() == Players.LocalPlayer and p and p.class) or target().Character and target().Character:GetAttribute("DragonClass") or (p and p.class) or "Shadowstalker"
	header(balanceList, nextOrder(), "✨ Abilities (" .. classId .. ")")
	local abilityIds = { "Breath", "Fireball" }
	for _, branch in ipairs(Talents[classId]) do
		for _, t in ipairs(branch.talents) do
			if t.ability then
				table.insert(abilityIds, t.ability)
			end
		end
	end
	for _, id in ipairs(abilityIds) do
		local a = Abilities.get(id)
		local dmg, cd = Tuning.ability(id)
		local baseMult = id == "Breath" and Classes.get(classId).breath.mult or a.mult
		local baseCd = id == "Breath" and Classes.get(classId).breath.cooldown or a.cooldown
		stepper(balanceList, nextOrder(), a.icon .. " " .. a.name .. " damage", dmg, baseMult and string.format("x%s attack → x%s", Util.fmt(baseMult), Util.fmt(baseMult * dmg)) or "no damage", function(v)
			act("tuneAbility", { abilityId = id, field = "dmg", value = v }, true)
		end)
		if baseCd then
			stepper(balanceList, nextOrder(), a.icon .. " " .. a.name .. " cooldown", cd, string.format("%ss → %ss", Util.fmt(baseCd), Util.fmt(baseCd * cd)), function(v)
				act("tuneAbility", { abilityId = id, field = "cd", value = v }, true)
			end)
		end
	end

	header(balanceList, nextOrder(), "🌟 Skills (" .. classId .. ", stat skills only)")
	for _, branch in ipairs(Talents[classId]) do
		for _, t in ipairs(branch.talents) do
			if next(t.effects) then
				stepper(balanceList, nextOrder(), string.format("%s %s (T%d)", branch.icon, t.name, t.tier), Tuning.talent(t.id), TalentUtil.describe(t, 1):gsub("\n", ", ") .. " per rank", function(v)
					act("tuneTalent", { talentId = t.id, value = v }, true)
				end)
			end
		end
	end
end

local function buildBalancePage(page: Instance)
	balanceList = Theme.scroll(page, { Size = UDim2.new(1, -300, 1, 0) })
	Theme.list(balanceList, 4)
	local side = Theme.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 290, 1, 0), BackgroundColor3 = C.panel2, Parent = page })
	Theme.corner(side, 8)
	Theme.pad(side, 8)
	Theme.label({ Size = UDim2.new(1, 0, 0, 60), TextSize = 12, TextColor3 = C.subtext, Text = "Changes apply live to everyone on this server and reset when the server restarts. Print them to copy the new numbers into src/shared/Config.", Parent = side })
	Theme.button("🖨️ Print changes", Color3.fromRGB(70, 120, 180), function()
		act("printTuning")
	end, { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(0.5, -4, 0, 34), TextSize = 13, Parent = side })
	Theme.button("🔄 Reset all", Color3.fromRGB(130, 60, 60), function()
		act("resetTuning")
	end, { Position = UDim2.new(0.5, 4, 0, 66), Size = UDim2.new(0.5, -4, 0, 34), TextSize = 13, Parent = side })
	reportBox = Theme.make("TextBox", {
		Position = UDim2.fromOffset(0, 108),
		Size = UDim2.new(1, 0, 1, -108),
		BackgroundColor3 = C.panel,
		TextColor3 = C.text,
		Font = Enum.Font.Code,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextEditable = false,
		Text = "",
		Parent = side,
	})
	Theme.corner(reportBox, 6)
	Theme.pad(reportBox, 6)
end

---------------------------------------------------------------- window

local function refreshTarget()
	local t = target()
	targetButton.Text = "🎯 " .. t.DisplayName .. (t == Players.LocalPlayer and " (you)" or "") .. "  (change)"
end

function Admin.refresh()
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == tab and C.accentDark or C.panel3
		pages[name].Visible = name == tab
	end
	refreshTarget()
	if tab == "Balance" then
		Admin.refreshBalance()
	end
end

function Admin.init(app)
	App = app
	local close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🛠️ Admin", Vector2.new(940, 600))
	close.Activated:Connect(function()
		App.Windows.close("Admin")
	end)
	for i, name in ipairs({ "Dragon", "World", "Balance" }) do
		tabButtons[name] = Theme.button(name, C.panel3, function()
			tab = name
			Admin.refresh()
		end, { Position = UDim2.fromOffset((i - 1) * 110, 0), Size = UDim2.fromOffset(100, 32), Parent = content })
		pages[name] = Theme.make("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 1, -70), BackgroundTransparency = 1, Visible = false, Parent = content })
	end
	targetButton = Theme.button("🎯 You", Color3.fromRGB(90, 70, 130), function()
		-- cycle through everyone in the server
		local list = Players:GetPlayers()
		local index = 0
		for i, pl in ipairs(list) do
			if pl == target() then
				index = i
			end
		end
		local nextPlayer = list[index % #list + 1]
		targetId = nextPlayer.UserId
		Admin.refresh()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(260, 32), TextSize = 13, Parent = content })
	statusLabel = Theme.label({ Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 26), TextSize = 13, TextColor3 = C.subtext, Text = "Pick who to change with the 🎯 button (top right). Everything else applies to that dragon.", Parent = content })
	buildDragonPage(pages.Dragon)
	buildWorldPage(pages.World)
	buildBalancePage(pages.Balance)
	App.Windows.register("Admin", window, Admin.refresh)

	-- Keep the local copy of the live balance overrides in sync with the server.
	task.spawn(function()
		local values = Remotes.func("GetTuning"):InvokeServer()
		Tuning.apply(values)
	end)
	Remotes.event("TuningChanged").OnClientEvent:Connect(function(values)
		Tuning.apply(values)
		if window.Visible and tab == "Balance" then
			Admin.refreshBalance()
		end
		App.State.changed:Fire(App.State.profile)
	end)
end

return Admin
