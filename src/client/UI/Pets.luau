-- Pets window: your nano dragons (equip, feed treats to level up, merge three into a golden
-- one, release) and eggs. Buying an egg at the Hatchery hatches it right away with a little
-- reveal; eggs you find wait here until you hatch them. Each egg shows its rarity odds on one
-- line, and "See every pet" lists each pet it can hatch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local PetInfo = require(Shared.Config.Pets)
local StoreInfo = require(Shared.Config.Store)
local DungeonInfo = require(Shared.Config.Dungeons)
local StatCalc = require(Shared.StatCalc)
local BonusUtil = require(Shared.BonusUtil)
local DragonBuilder = require(Shared.DragonBuilder)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Pets = {}
local App

local window, content
local tab = "Pets"
local tabButtons = {}
local petsPage, eggsPage
local header, grid, details = nil, nil, {}
local eggsList, eggsHeader, eggsRestock
local eggsBadge -- red count on the Eggs tab: eggs waiting to hatch
local expanded = {} -- [eggId] = true: that egg's card lists every pet it can hatch
local revealed = false -- the hatched pet's card is showing (a click outside it closes it)
local selected = nil
local releaseArmed = nil
local busy = false
local hatching = false -- the reveal is playing: no more hatching until it's closed
local overlay
local emptyLabel

local ROBUX_GREEN = Color3.fromRGB(40, 150, 70)
local PLAN_ICONS = { Shadowstalker = "🌑", Stormwing = "⚡", Behemoth = "🌋", Frostwyrm = "❄️", Venomspine = "🐍" }

local function statText(stats): string
	local parts = {}
	for stat, v in pairs(stats) do
		local info = StatCalc.STAT_INFO[stat]
		table.insert(parts, string.format("+%s%% %s", Util.fmt(v), info and info.label or stat))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- A spinning 3D nano dragon inside a ViewportFrame.
local function preview(parent: GuiObject, speciesId: string, golden: boolean?)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	local species = PetInfo.get(speciesId)
	if not species then
		return
	end
	local colors, fire = App.PetFollow.look(speciesId, golden == true)
	local model = DragonBuilder.build(species.plan, { anchored = true, noParticles = true, lite = true, colors = colors, fire = fire })
	model:PivotTo(CFrame.new())
	model.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = parent
	parent.CurrentCamera = camera
	local _, size = model:GetBoundingBox()
	local dist = math.max(size.X, size.Y, size.Z) * 1.3 + 3
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent or not parent.Parent then
			conn:Disconnect()
			return
		end
		local a = (os.clock() - start) * 0.8
		camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * dist, dist * 0.35, math.cos(a) * dist), Vector3.zero)
	end)
end

local function invoke(remote: string, arg, onOk)
	if busy or hatching then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = Remotes.func(remote):InvokeServer(arg)
		busy = false
		if ok then
			if onOk then
				onOk(result)
			end
		elseif result then
			App.Windows.notify(result, C.bad, "🐲")
		end
	end)
end

---------------------------------------------------------------- hatching

local function showHatch(pet)
	local species = PetInfo.get(pet.species)
	local color = PetInfo.RarityColors[species.rarity]
	hatching = true
	revealed = false
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.35 }):Play()
	local egg = overlay.Egg
	local card = overlay.Card
	card.Visible = false
	egg.Visible = true
	egg.Rotation = 0
	egg.Size = UDim2.fromOffset(160, 160)
	task.spawn(function()
		-- wobble harder and harder, then pop
		for i = 1, 10 do
			local amt = 6 + i * 2.5
			TweenService:Create(egg, TweenInfo.new(0.09), { Rotation = (i % 2 == 0) and amt or -amt }):Play()
			task.wait(0.1)
		end
		TweenService:Create(egg, TweenInfo.new(0.15), { Size = UDim2.fromOffset(240, 240), TextTransparency = 1 }):Play()
		task.wait(0.15)
		egg.Visible = false
		egg.TextTransparency = 0
		card.Visible = true
		card.Title.Text = species.name
		card.Title.TextColor3 = color
		local rare = species.rarity == "Epic" or species.rarity == "Legendary" or species.rarity == "Secret"
		card.Rarity.Text = (rare and "✨ " or "") .. species.rarity:upper() .. " NANO DRAGON" .. (rare and " ✨" or "")
		card.Rarity.TextColor3 = color
		card.Stats.Text = statText(species.stats)
		card.UIStroke.Color = color
		card.UIStroke.Thickness = rare and 5 or 3
		preview(card.View, pet.species)
		App.Sfx.play("LevelUp")
		revealed = true
	end)
end

local function closeHatch()
	overlay.Visible = false
	hatching = false
	revealed = false
	Pets.refresh()
end

---------------------------------------------------------------- pages

local function refreshPets(p)
	local slots = p.petSlots or 1
	local equipped = p.petsEquipped or {}
	local nextLevel = Game.PET_SLOT_LEVELS[slots + 1]
	header.Text = string.format("Following you: <font color=\"#FFD24A\">%d / %d</font>%s   •   Nest: %d / %d   •   🍬 %d",
		math.min(#equipped, slots), slots, nextLevel and string.format(" (slot at Lv %d)", nextLevel) or "", #(p.pets or {}), Game.PET_LIMIT, p.treats or 0)
	Theme.clear(grid)
	local list = table.clone(p.pets or {})
	local order = {}
	for i, r in ipairs(PetInfo.RarityOrder) do
		order[r] = i
	end
	table.sort(list, function(a, b)
		local ea, eb = table.find(equipped, a.uid) ~= nil, table.find(equipped, b.uid) ~= nil
		if ea ~= eb then
			return ea
		end
		local sa, sb = PetInfo.get(a.species), PetInfo.get(b.species)
		if sa.rarity ~= sb.rarity then
			return order[sa.rarity] > order[sb.rarity]
		end
		if sa.name ~= sb.name then
			return sa.name < sb.name
		end
		return BonusUtil.petScore(a) > BonusUtil.petScore(b)
	end)
	for i, pet in ipairs(list) do
		local species = PetInfo.get(pet.species)
		local color = PetInfo.RarityColors[species.rarity]
		local isEquipped = table.find(equipped, pet.uid) ~= nil
		local cardButton = Theme.make("TextButton", { BackgroundColor3 = pet.golden and Color3.fromRGB(90, 72, 30) or C.panel2, AutoButtonColor = false, Text = "", LayoutOrder = i, Parent = grid })
		Theme.corner(cardButton, 8)
		Theme.stroke(cardButton, color, selected == pet.uid and 3 or 1.5, selected == pet.uid and 0 or 0.3)
		Theme.label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 34), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Text = PLAN_ICONS[species.plan] or "🐲", Parent = cardButton })
		Theme.label({ Position = UDim2.fromOffset(4, 40), Size = UDim2.new(1, -8, 0, 28), TextSize = 11, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Text = PetInfo.displayName(pet), Parent = cardButton })
		Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(40, 16), TextSize = 12, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Right, Text = "Lv " .. (pet.level or 1), Parent = cardButton })
		if isEquipped then
			Theme.label({ Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(30, 16), TextSize = 12, TextColor3 = C.good, Text = "✅", Parent = cardButton })
		end
		cardButton.Activated:Connect(function()
			selected = pet.uid
			releaseArmed = nil
			Pets.refresh()
		end)
	end
	-- (outside the grid: a grid cell would squash the message into a 100-pixel box)
	emptyLabel.Visible = #list == 0

	local pet = nil
	for _, candidate in ipairs(p.pets or {}) do
		if candidate.uid == selected then
			pet = candidate
		end
	end
	details.frame.Visible = pet ~= nil
	if pet then
		local species = PetInfo.get(pet.species)
		local color = PetInfo.RarityColors[species.rarity]
		local isEquipped = table.find(equipped, pet.uid) ~= nil
		local level = pet.level or 1
		details.name.Text = PetInfo.displayName(pet)
		details.name.TextColor3 = pet.golden and PetInfo.GOLDEN_LOOK.accent or color
		details.info.Text = string.format("%s nano dragon  •  %s body", species.rarity, species.plan)
		details.stats.Text = "Boosts: " .. statText(BonusUtil.petBoosts(pet))
		local cost = PetInfo.LEVEL_COSTS[level]
		details.level.Text = string.format("Level %d / %d%s\n%s", level, PetInfo.MAX_LEVEL,
			cost and string.format("  •  next: %d 🍬 (you have %d)", cost, p.treats or 0) or "  •  MAX",
			pet.golden and "Golden: boosts x" .. PetInfo.GOLDEN_MULT or string.format("Merge %d for a Golden (x%s boosts): %s 💰", PetInfo.MERGE_COUNT, tostring(PetInfo.GOLDEN_MULT), Util.formatNumber(PetInfo.MergeGold[species.rarity] or 0)))
		details.feed.Text = cost and string.format("🍬 Feed (%d)", cost) or "Max level"
		Theme.setButtonEnabled(details.feed, cost ~= nil and (p.treats or 0) >= cost)
		local same = 0
		for _, other in ipairs(p.pets or {}) do
			if other.species == pet.species and not other.golden then
				same += 1
			end
		end
		if pet.golden then
			details.merge.Text = "✨ Golden!"
			Theme.setButtonEnabled(details.merge, false)
		else
			details.merge.Text = string.format("✨ Merge %d/%d", math.min(same, PetInfo.MERGE_COUNT), PetInfo.MERGE_COUNT)
			local mergeGold = PetInfo.MergeGold[species.rarity] or 0
			Theme.setButtonEnabled(details.merge, same >= PetInfo.MERGE_COUNT and p.gold >= mergeGold)
			Theme.onDisabledClick(details.merge, same >= PetInfo.MERGE_COUNT and function()
				App.Store.needGold(mergeGold)
			end or nil)
		end
		details.equip.Text = isEquipped and "Unequip" or "Equip"
		details.equip.BackgroundColor3 = isEquipped and Color3.fromRGB(120, 60, 60) or Color3.fromRGB(60, 140, 70)
		local releaseGold = PetInfo.releaseGold(pet)
		details.release.Text = releaseArmed == pet.uid and "Really release?" or string.format("Release (+%d 💰)", releaseGold)
		local shownKey = pet.uid .. (pet.golden and "g" or "")
		if details.shown ~= shownKey then
			details.shown = shownKey
			preview(details.view, pet.species, pet.golden)
		end
	end
end

-- Every pet an egg can hatch, with its chance and boosts.
local function eggContents(eggId: string)
	local egg = PetInfo.Eggs[eggId]
	local total = 0
	for _, w in pairs(egg.weights) do
		total += w
	end
	local list = {}
	for _, rarity in ipairs(PetInfo.RarityOrder) do
		local w = egg.weights[rarity]
		if w then
			local species = PetInfo.speciesFor(eggId, rarity)
			for _, id in ipairs(species) do
				table.insert(list, { id = id, chance = w / total / #species * 100 })
			end
		end
	end
	return list
end

-- The chance of each rarity on one color-coded line: "Common 62%   Uncommon 30%   ...".
local function oddsLine(egg): string
	local total = 0
	for _, w in pairs(egg.weights) do
		total += w
	end
	local parts = {}
	for _, rarity in ipairs(PetInfo.RarityOrder) do
		local w = egg.weights[rarity]
		if w then
			table.insert(parts, string.format("<font color=\"%s\">%s %s%%</font>", Theme.colorHex(PetInfo.RarityColors[rarity]), rarity, Util.fmt(math.floor(w / total * 1000 + 0.5) / 10)))
		end
	end
	return table.concat(parts, "   ")
end

local function refreshEggs(p)
	eggsRestock.Visible = App.Store.available("product", "Restock")
	Theme.clear(eggsList)
	local stock = p.shopStock and p.shopStock.eggs or {}
	local nestFull = #(p.pets or {}) >= Game.PET_LIMIT
	eggsHeader.Text = string.format("💰 %s gold   •   Nest: %s%d / %d</font>   •   <font color=\"#8CE678\">%s</font>",
		Util.formatNumber(p.gold), nestFull and "<font color=\"#F05A5A\">" or "<font color=\"#FFFFFF\">", #(p.pets or {}), Game.PET_LIMIT, App.Shop.restockText(p))
	for i, eggId in ipairs(PetInfo.EggOrder) do
		local egg = PetInfo.Eggs[eggId]
		local owned = (p.eggs and p.eggs[eggId]) or 0
		if egg.robux and owned == 0 then
			continue -- sold in the 💎 Store; shows here once you have one to hatch
		end
		local contents = eggContents(eggId)
		local open = expanded[eggId] == true
		local rows = open and math.ceil(#contents / 4) or 0
		local card = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 100 + (open and rows * 50 + 2 or 0)), BackgroundColor3 = C.panel2, LayoutOrder = i, Parent = eggsList })
		Theme.corner(card, 10)
		Theme.stroke(card, egg.color, 2, 0.3)
		-- the buy button takes the top right; the name and description get the rest. "Hatch yours"
		-- sits on the bottom row beside "See every pet".
		local sold = egg.price ~= nil or egg.store ~= nil
		local right = 250
		Theme.label({ Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(64, 70), TextSize = 48, TextXAlignment = Enum.TextXAlignment.Center, Text = egg.icon, Parent = card })
		Theme.label({ Position = UDim2.fromOffset(78, 6), Size = UDim2.new(1, -78 - right, 0, 26), Font = Theme.Fonts.title, TextSize = 22, TextColor3 = egg.color, Text = egg.name, Parent = card })
		Theme.label({ Position = UDim2.fromOffset(78, 33), Size = UDim2.new(1, -78 - right, 0, 32), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextYAlignment = Enum.TextYAlignment.Top, Text = egg.desc, Parent = card })
		-- the odds on one color-coded line, and a button for the full list of pets
		Theme.label({ Position = UDim2.fromOffset(78, 72), Size = UDim2.new(1, -78 - (owned > 0 and 320 or 160), 0, 20), TextSize = 13, RichText = true, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = oddsLine(egg), Parent = card })
		Theme.button(open and "Hide pets" or "🔍 See every pet", C.panel3, function()
			expanded[eggId] = not open or nil
			Pets.refresh()
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 70), Size = UDim2.fromOffset(140, 24), TextSize = 13, Parent = card })

		-- right side: buy & hatch (Hatchery eggs), and hatch the ones you found
		if egg.price then
			local left = stock[eggId] or 0
			local buy = Theme.button(left > 0 and string.format("🐣 Buy & Hatch  %s 💰", Util.formatNumber(egg.price)) or "Sold out", Color3.fromRGB(70, 150, 80), function()
				invoke("BuyEgg", eggId, function(pet)
					App.Sfx.play("Coin")
					selected = pet.uid
					showHatch(pet)
				end)
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(230, 38), TextSize = 16, Parent = card })
			Theme.setButtonEnabled(buy, left > 0 and not nestFull and p.gold >= egg.price)
			if left > 0 and not nestFull then
				Theme.onDisabledClick(buy, function()
					App.Store.needGold(egg.price)
				end)
			end
			Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 48), Size = UDim2.fromOffset(230, 16), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = left > 0 and C.good or C.bad, Text = nestFull and "Your nest is full!" or (left > 0 and string.format("%d in stock", left) or "Out of stock"), Parent = card })
		end
		if egg.store and not egg.price and not App.Store.available("product", egg.store) then
			-- paid random items are restricted here: no Robux button, just where to find one
			Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(230, 38), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
				TextColor3 = C.subtext, Text = egg.robux and "Not sold where you live" or "Find one free on champions, bosses and camp chests", Parent = card })
		elseif egg.store and not egg.price then
			-- sold for Robux (the Mythic Egg also drops in the wild, and says so)
			local product = StoreInfo.Products[egg.store]
			Theme.button(string.format("💎 Buy one  R$ %d", product.robux), ROBUX_GREEN, function()
				App.Store.buy("product", egg.store)
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(230, 38), TextSize = 16, Parent = card })
			Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 48), Size = UDim2.fromOffset(230, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = C.subtext, Text = egg.robux and "only in the 💎 Store" or "or find one free in the wild", Parent = card })
		end
		if owned > 0 then
			local hatch = Theme.button(string.format("🥚 Hatch yours (%d)", owned), Color3.fromRGB(200, 120, 60), function()
				invoke("HatchEgg", eggId, function(pet)
					selected = pet.uid
					showHatch(pet)
				end)
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -160, 0, 70), Size = UDim2.fromOffset(152, 24), TextSize = 13, Parent = card })
			Theme.setButtonEnabled(hatch, not nestFull)
		elseif not sold then
			local where = egg.dungeon and string.format("Only from the boss of %s (🏰 Dungeons)", DungeonInfo.get(egg.dungeon).name) or "Not sold anywhere: found on champions, bosses and chests"
			Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(230, 40), TextSize = 12, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Center, Text = where, Parent = card })
		end
		if not open then
			continue
		end

		-- what's inside
		local grid = Theme.make("Frame", { Position = UDim2.fromOffset(10, 100), Size = UDim2.new(1, -20, 0, rows * 50), BackgroundTransparency = 1, Parent = card })
		Theme.make("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 44), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for k, entry in ipairs(contents) do
			local species = PetInfo.get(entry.id)
			local color = PetInfo.RarityColors[species.rarity]
			local cell = Theme.make("Frame", { BackgroundColor3 = C.panel, LayoutOrder = k, Parent = grid })
			Theme.corner(cell, 6)
			Theme.stroke(cell, color, 1, 0.4)
			Theme.label({ Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -60, 0, 18), TextSize = 12, TextColor3 = color, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = species.name, Parent = cell })
			Theme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 2), Size = UDim2.fromOffset(54, 18), TextSize = 12, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Right, Text = Util.fmt(math.floor(entry.chance * 10 + 0.5) / 10) .. "%", Parent = cell })
			Theme.label({ Position = UDim2.fromOffset(6, 21), Size = UDim2.new(1, -12, 0, 20), TextSize = 10, Font = Theme.Fonts.body, TextColor3 = C.good, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = statText(species.stats), Parent = cell })
		end
	end
	Theme.label({ Size = UDim2.new(1, -10, 0, 30), LayoutOrder = 10, TextSize = 12, TextColor3 = C.subtext, Text = "Nestmother's Hatchery is east of the plaza. Its stock refills every few minutes.", Parent = eggsList })
end

function Pets.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	petsPage.Visible = tab == "Pets"
	eggsPage.Visible = tab == "Eggs"
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == tab and C.accentDark or C.panel3
	end
	Theme.setBadge(eggsBadge, App.HUD.eggsWaiting(p))
	if tab == "Pets" then
		refreshPets(p)
	else
		refreshEggs(p)
	end
end

function Pets.open(which: string?)
	tab = which or tab
	App.Windows.open("Pets")
end

function Pets.init(app)
	App = app
	local close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🐲 Nano Dragons", Vector2.new(840, 600))
	close.Activated:Connect(function()
		App.Windows.close("Pets")
	end)
	for i, name in ipairs({ "Pets", "Eggs" }) do
		tabButtons[name] = Theme.button(name == "Pets" and "🐲 My Pets" or "🥚 Eggs", C.panel3, function()
			tab = name
			Pets.refresh()
		end, { Position = UDim2.fromOffset((i - 1) * 130, 0), Size = UDim2.fromOffset(120, 32), TextSize = 15, Parent = content })
	end
	eggsBadge = Theme.badge(tabButtons.Eggs, { Size = UDim2.fromOffset(22, 22), TextSize = 13 })
	petsPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Parent = content })
	eggsPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Visible = false, Parent = content })

	header = Theme.label({ Size = UDim2.new(1, -290, 0, 22), TextSize = 14, TextWrapped = false, Parent = petsPage })
	Theme.button("⚡ Equip Best", Color3.fromRGB(60, 140, 70), function()
		invoke("EquipBestPets", nil, function()
			App.Sfx.play("Click")
			App.Windows.notify("Your best pets are following you!", C.good, "🐲")
		end)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4), Size = UDim2.fromOffset(280, 28), TextSize = 14, Parent = petsPage })
	grid = Theme.scroll(petsPage, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -290, 1, -26) })
	Theme.make("UIGridLayout", { CellSize = UDim2.fromOffset(100, 74), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	emptyLabel = Theme.label({
		Position = UDim2.fromOffset(10, 50),
		Size = UDim2.new(1, -310, 0, 90),
		TextSize = 17,
		TextColor3 = C.subtext,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "No pets yet!\nBuy an egg at Nestmother's Hatchery in town (the 🥚 Eggs tab shows what each one can hatch), or find one on a camp champion.",
		Visible = false,
		Parent = petsPage,
	})

	details.frame = Theme.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 26), Size = UDim2.new(0, 280, 1, -26), BackgroundColor3 = C.panel2, Visible = false, Parent = petsPage })
	Theme.corner(details.frame, 10)
	Theme.pad(details.frame, 10)
	details.view = Theme.make("ViewportFrame", { Size = UDim2.new(1, 0, 0, 160), BackgroundColor3 = Color3.fromRGB(35, 30, 50), Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.fromRGB(255, 245, 230), LightDirection = Vector3.new(-1, -1.5, -0.5), Parent = details.frame })
	Theme.corner(details.view, 10)
	details.name = Theme.label({ Position = UDim2.fromOffset(0, 164), Size = UDim2.new(1, 0, 0, 26), Font = Theme.Fonts.title, TextSize = 21, Parent = details.frame })
	details.info = Theme.label({ Position = UDim2.fromOffset(0, 190), Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = C.subtext, Parent = details.frame })
	details.stats = Theme.label({ Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 52), TextSize = 14, TextColor3 = C.good, TextYAlignment = Enum.TextYAlignment.Top, Parent = details.frame })
	details.level = Theme.label({ Position = UDim2.fromOffset(0, 264), Size = UDim2.new(1, 0, 0, 34), TextSize = 12, TextColor3 = C.gold, TextYAlignment = Enum.TextYAlignment.Top, Parent = details.frame })
	details.feed = Theme.button("🍬 Feed", Color3.fromRGB(200, 110, 160), function()
		if selected then
			invoke("FeedPet", selected, function(level)
				App.Sfx.play("LevelUp")
				App.Windows.notify(string.format("Yum! Your pet grew to level %d!", level or 0), C.good, "🍬")
			end)
		end
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -90), Size = UDim2.new(0.5, -4, 0, 38), TextSize = 15, Parent = details.frame })
	details.merge = Theme.button("✨ Merge", Color3.fromRGB(190, 150, 40), function()
		if selected then
			invoke("MergePets", selected, function()
				App.Sfx.play("LevelUp")
				App.Windows.notify("Three became one... a GOLDEN nano dragon!", PetInfo.GOLDEN_LOOK.accent, "✨")
			end)
		end
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -90), Size = UDim2.new(0.5, -4, 0, 38), TextSize = 15, Parent = details.frame })
	details.equip = Theme.button("Equip", Color3.fromRGB(60, 140, 70), function()
		local p = App.State.profile
		if not p or not selected then
			return
		end
		if table.find(p.petsEquipped or {}, selected) then
			invoke("UnequipPet", selected)
		else
			invoke("EquipPet", selected)
		end
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -46), Size = UDim2.new(1, 0, 0, 38), Parent = details.frame })
	details.release = Theme.button("Release", Color3.fromRGB(120, 60, 70), function()
		if not selected then
			return
		end
		if releaseArmed ~= selected then
			releaseArmed = selected
			Pets.refresh()
			return
		end
		local uid = selected
		releaseArmed = nil
		selected = nil
		invoke("ReleasePet", uid, function(gold)
			App.Windows.notify(string.format("Your pet flew off into the wild. +%d gold", gold or 0), C.gold, "🐲")
		end)
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 36), TextSize = 14, Parent = details.frame })

	eggsHeader = Theme.label({ Size = UDim2.new(1, -170, 0, 22), TextSize = 14, Parent = eggsPage })
	eggsRestock = Theme.button("🔄 Restock now (R$)", ROBUX_GREEN, function()
		App.Store.buy("product", "Restock")
	end, { Name = "Restock", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -3), Size = UDim2.fromOffset(160, 26), TextSize = 13, Parent = eggsPage })
	eggsList = Theme.scroll(eggsPage, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28) })
	Theme.list(eggsList, 8)
	-- keep the restock countdown ticking
	task.spawn(function()
		while true do
			task.wait(1)
			if window.Visible and tab == "Eggs" and App.State.profile then
				local p = App.State.profile
				eggsHeader.Text = string.gsub(eggsHeader.Text, "🔄 Restocks in [%d:]+", App.Shop.restockText(p))
			end
		end
	end)

	-- Hatch reveal overlay: a button, so clicks can't reach the windows underneath while it shows
	overlay = Theme.make("TextButton", { Name = "HatchOverlay", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, AutoButtonColor = false, Text = "", Active = true, Modal = true, Visible = false, ZIndex = 50, Parent = App.Windows.guis.Top })
	Theme.label({ Name = "Egg", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(160, 160), TextSize = 140, TextXAlignment = Enum.TextXAlignment.Center, Text = "🥚", ZIndex = 51, Parent = overlay })
	-- once the pet is revealed, a click outside its card closes it (the card itself is Active, so
	-- clicks on it don't)
	overlay.Activated:Connect(function()
		if revealed then
			closeHatch()
		end
	end)
	local card = Theme.make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(380, 400), BackgroundColor3 = C.panel, Active = true, Visible = false, ZIndex = 51, Parent = overlay })
	Theme.corner(card, 14)
	Theme.stroke(card, C.accent, 3)
	Theme.label({ Name = "Rarity", Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52, Parent = card })
	local view = Theme.make("ViewportFrame", { Name = "View", Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -40, 0, 210), BackgroundColor3 = Color3.fromRGB(35, 30, 50), Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.fromRGB(255, 245, 230), LightDirection = Vector3.new(-1, -1.5, -0.5), ZIndex = 52, Parent = card })
	Theme.corner(view, 10)
	Theme.label({ Name = "Title", Position = UDim2.fromOffset(0, 252), Size = UDim2.new(1, 0, 0, 34), Font = Theme.Fonts.title, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52, Parent = card })
	Theme.label({ Name = "Stats", Position = UDim2.fromOffset(20, 290), Size = UDim2.new(1, -40, 0, 44), TextSize = 15, TextColor3 = C.good, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52, Parent = card })
	Theme.button("Awesome!", Color3.fromRGB(60, 140, 70), closeHatch, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(180, 42), ZIndex = 52, Parent = card })

	App.Windows.register("Pets", window, Pets.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Pets.refresh()
		end
	end)
end

return Pets
