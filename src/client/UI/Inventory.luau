-- The Bag: equipped gear, your stats, every item you carry, your seeds and your food.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Seeds = require(Shared.Config.Seeds)
local Food = require(Shared.Config.Food)
local Game = require(Shared.Config.Game)
local ItemUtil = require(Shared.ItemUtil)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Inventory = {}
local App

local window, content
local tab = "Gear"
local gearPage, seedsPage, foodPage
local foodList, foodHeader
local tabButtons = {}
local equippedRows = {}
local statsLabel
local bagHeader, bagGrid
local details = {}
local seedsList
local selectedId = nil

local function sortedInventory(p)
	local list = table.clone(p.inventory)
	local slotOrder = {}
	for i, slot in ipairs(Items.Slots) do
		slotOrder[slot] = i
	end
	table.sort(list, function(a, b)
		if a.slot ~= b.slot then
			return slotOrder[a.slot] < slotOrder[b.slot]
		end
		return ItemUtil.score(a) > ItemUtil.score(b)
	end)
	return list
end

local function statLine(label: string, value: string, color: Color3?)
	return string.format("<font color=\"%s\">%s</font>  %s", Theme.colorHex(color or C.subtext), label, value)
end

local function refreshStats(p)
	local s = p.stats
	if not s then
		statsLabel.Text = ""
		return
	end
	local lines = {
		statLine("⚔️ Attack", Util.fmt(s.attack), Color3.fromRGB(255, 170, 60)),
		statLine("❤️ Max Health", Util.formatNumber(s.maxHealth), Color3.fromRGB(240, 100, 100)),
		statLine("🛡️ Defense", Util.fmt(s.defense), Color3.fromRGB(170, 170, 200)),
		statLine("🎯 Crit Chance", Util.fmt(s.critChance) .. "%", Color3.fromRGB(255, 220, 90)),
		statLine("💥 Crit Damage", Util.fmt(s.critDamage) .. "%", Color3.fromRGB(255, 200, 120)),
		statLine("👟 Speed", Util.fmt(s.speed), Color3.fromRGB(110, 210, 255)),
		statLine("💨 Flight Stamina", Util.fmt(s.stamina), Color3.fromRGB(120, 230, 255)),
	}
	if s.dodge > 0 then
		table.insert(lines, statLine("🌀 Dodge", Util.fmt(s.dodge) .. "%"))
	end
	if s.lifesteal > 0 then
		table.insert(lines, statLine("🦇 Lifesteal", Util.fmt(s.lifesteal) .. "%"))
	end
	table.insert(lines, statLine("⚡ Power", Util.formatNumber(p.power or 0), C.blue))
	statsLabel.Text = table.concat(lines, "\n")
end

local function showDetails()
	local p = App.State.profile
	local item = selectedId and App.State.findItem(selectedId)
	if not p or not item then
		details.frame.Visible = false
		return
	end
	details.frame.Visible = true
	details.name.Text = ItemUtil.displayName(item)
	details.name.TextColor3 = ItemUtil.rarityColor(item.rarity)
	details.info.Text = string.format("%s %s  •  %s  •  Item Level %d  •  Sells for %s gold", Items.SlotInfo[item.slot].icon, Items.SlotInfo[item.slot].name, item.rarity, item.ilvl, Util.formatNumber(ItemUtil.sellPrice(item)))

	local stats = ItemUtil.getStats(item)
	local lines = ItemUtil.describeStats(stats)
	local equippedId = p.equipped[item.slot]
	local equipped = equippedId and equippedId ~= item.id and App.State.findItem(equippedId)
	if equipped then
		local other = ItemUtil.getStats(equipped)
		local diffs = {}
		for _, stat in ipairs({ "attack", "health", "defense", "crit", "speed" }) do
			local d = (stats[stat] or 0) - (other[stat] or 0)
			if math.abs(d) >= 0.05 then
				local color = d > 0 and "#6EDC6E" or "#F05A5A"
				table.insert(diffs, string.format("<font color=\"%s\">%s%s %s</font>", color, d > 0 and "+" or "", Util.fmt(d), Items.StatLabels[stat]))
			end
		end
		if #diffs > 0 then
			table.insert(lines, "vs equipped: " .. table.concat(diffs, ", "))
		end
	end
	details.stats.Text = table.concat(lines, "\n")

	local isEquipped = p.equipped[item.slot] == item.id
	details.equip.Text = isEquipped and "Unequip" or "Equip"
	details.equip.BackgroundColor3 = isEquipped and Color3.fromRGB(120, 60, 60) or Color3.fromRGB(60, 140, 70)
end

local UPGRADE_GREEN = Color3.fromRGB(110, 230, 110)

local function itemCard(parent: Instance, item, order: number)
	local color = ItemUtil.rarityColor(item.rarity)
	local p = App.State.profile
	local isEquipped = p.equipped[item.slot] == item.id
	local worn = p.equipped[item.slot] and App.State.findItem(p.equipped[item.slot])
	local better = not isEquipped and ItemUtil.isUpgrade(item, worn)
	local card = Theme.make("TextButton", {
		BackgroundColor3 = better and Color3.fromRGB(40, 70, 45) or C.panel2,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.corner(card, 8)
	Theme.stroke(card, better and UPGRADE_GREEN or color, selectedId == item.id and 3 or (better and 2.5 or 1.5), selectedId == item.id and 0 or (better and 0 or 0.3))
	if better then
		-- better than what you're wearing in this slot
		Theme.label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -6),
			Size = UDim2.fromOffset(22, 22),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "⬆️",
			ZIndex = 3,
			Parent = card,
		})
	end
	Theme.label({
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 32),
		TextSize = 12,
		TextColor3 = color,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = ItemUtil.displayName(item),
		Parent = card,
	})
	Theme.label({
		Position = UDim2.fromOffset(6, 40),
		Size = UDim2.new(1, -12, 0, 18),
		TextSize = 12,
		TextColor3 = C.subtext,
		Text = string.format("%s iLvl %d%s", Items.SlotInfo[item.slot].icon, item.ilvl, isEquipped and "  <font color=\"#6EDC6E\">✅ worn</font>" or ""),
		Parent = card,
	})
	card.Activated:Connect(function()
		selectedId = item.id
		Inventory.refresh()
	end)
end

function Inventory.refresh()
	local p = App.State.profile
	if not p then
		return
	end
	gearPage.Visible = tab == "Gear"
	seedsPage.Visible = tab == "Seeds"
	foodPage.Visible = tab == "Food"
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == tab and C.accentDark or C.panel3
	end

	if tab == "Food" then
		local total = 0
		for _, n in pairs(p.food or {}) do
			total += n
		end
		foodHeader.Text = string.format("🍖 Hunger: <font color=\"#FFB464\">%d / %d</font>   •   Food bag: %d / %d   •   Press <b>G</b> to eat the best snack", math.floor(p.hunger or 0), Game.HUNGER_MAX, total, Game.FOOD_BAG_LIMIT)
		Theme.clear(foodList)
		local any = false
		for i, foodId in ipairs(Food.Order) do
			local count = p.food and p.food[foodId] or 0
			if count > 0 then
				any = true
				local item = Food.get(foodId)
				local row = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 52), BackgroundColor3 = C.panel2, LayoutOrder = i, Parent = foodList })
				Theme.corner(row, 8)
				Theme.label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -140, 0, 24), Font = Theme.Fonts.title, TextSize = 19, TextColor3 = item.color, Text = string.format("%s %s  x%d", item.icon, item.name, count), Parent = row })
				Theme.label({ Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -140, 0, 18), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext, Text = string.format("+%d hunger  •  sells for %d gold at the Hoard Exchange", item.food, item.sell), Parent = row })
				Theme.button("Eat", Color3.fromRGB(200, 120, 60), function()
					task.spawn(function()
						local ok, err = Remotes.func("EatFood"):InvokeServer(foodId)
						if not ok and err then
							App.Notifications.toast(err, Color3.fromRGB(255, 190, 110), "🍖")
						end
					end)
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(100, 36), Parent = row })
			end
		end
		if not any then
			Theme.label({ Size = UDim2.new(1, 0, 0, 60), TextSize = 15, TextColor3 = C.subtext, Text = "No food! Hunt animals in Elk Meadows (west of town) or Whisperwood (east), or catch fish at the 🎣 spots on the river and lakes.", Parent = foodList })
		end
		return
	end

	if tab == "Gear" then
		for _, slot in ipairs(Items.Slots) do
			local row = equippedRows[slot]
			local item = p.equipped[slot] and App.State.findItem(p.equipped[slot])
			if item then
				row.name.Text = ItemUtil.displayName(item)
				row.name.TextColor3 = ItemUtil.rarityColor(item.rarity)
				row.stats.Text = table.concat(ItemUtil.describeStats(ItemUtil.getStats(item)), "  ")
			else
				row.name.Text = "Empty " .. Items.SlotInfo[slot].name
				row.name.TextColor3 = C.subtext
				row.stats.Text = ""
			end
			row.itemId = item and item.id or nil
		end
		refreshStats(p)
		bagHeader.Text = string.format("🎒 Bag  (%d / %d)   <font size=\"13\" color=\"#6EE66E\">⬆️ = better than what you wear</font>", #p.inventory, Game.INVENTORY_LIMIT)
		Theme.clear(bagGrid)
		for i, item in ipairs(sortedInventory(p)) do
			itemCard(bagGrid, item, i)
		end
		if #p.inventory == 0 then
			Theme.label({
				Size = UDim2.new(1, 0, 0, 60),
				TextSize = 15,
				TextColor3 = C.subtext,
				Text = "Your bag is empty. Defeat vikings for loot, or visit the Emberforge Armory!",
				Parent = bagGrid,
			})
		end
		showDetails()
	else
		Theme.clear(seedsList)
		local any = false
		for i, seedId in ipairs(Seeds.Order) do
			local count = p.seeds[seedId] or 0
			if count > 0 then
				any = true
				local seed = Seeds[seedId]
				local row = Theme.make("Frame", {
					Size = UDim2.new(1, -10, 0, 64),
					BackgroundColor3 = C.panel2,
					LayoutOrder = i,
					Parent = seedsList,
				})
				Theme.corner(row, 8)
				Theme.pad(row, 8)
				Theme.label({
					Size = UDim2.new(0.6, 0, 0, 22),
					Font = Theme.Fonts.title,
					TextSize = 20,
					TextColor3 = seed.bloom,
					Text = string.format("🌱 %s  x%d", seed.name, count),
					Parent = row,
				})
				Theme.label({
					Position = UDim2.fromOffset(0, 24),
					Size = UDim2.new(1, 0, 0, 30),
					TextSize = 13,
					Font = Theme.Fonts.body,
					TextColor3 = C.subtext,
					Text = string.format("%s — %s. Grows in about %s. Full bloom worth ~%d gold.", seed.rarity, seed.desc, Util.formatTime(seed.stageTime * 3), seed.value),
					Parent = row,
				})
			end
		end
		if not any then
			Theme.label({
				Size = UDim2.new(1, 0, 0, 60),
				TextSize = 15,
				TextColor3 = C.subtext,
				Text = "No seeds yet. Vikings very rarely drop seeds — and fully grown flowers give seeds back!",
				Parent = seedsList,
			})
		end
	end
end

function Inventory.init(app)
	App = app
	local close
	window, content, close = Theme.window(App.Windows.guis.Windows, "🎒 Bag", Vector2.new(840, 580))
	close.Activated:Connect(function()
		App.Windows.close("Inventory")
	end)

	local tabLabels = { Gear = "⚔️ Gear", Seeds = "🌱 Seeds", Food = "🍖 Food" }
	for i, name in ipairs({ "Gear", "Seeds", "Food" }) do
		tabButtons[name] = Theme.button(tabLabels[name], C.panel3, function()
			tab = name
			Inventory.refresh()
		end, { Position = UDim2.fromOffset((i - 1) * 130, 0), Size = UDim2.fromOffset(120, 32), TextSize = 15, Parent = content })
	end

	gearPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Parent = content })
	seedsPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Visible = false, Parent = content })
	foodPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Visible = false, Parent = content })
	foodHeader = Theme.label({ Size = UDim2.new(1, 0, 0, 22), TextSize = 14, Parent = foodPage })
	foodList = Theme.scroll(foodPage, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	Theme.list(foodList, 6)

	-- Equipped column
	local left = Theme.make("Frame", { Size = UDim2.new(0, 280, 1, 0), BackgroundColor3 = C.panel2, BackgroundTransparency = 0.2, Parent = gearPage })
	Theme.corner(left, 10)
	Theme.pad(left, 8)
	Theme.label({ Size = UDim2.new(1, 0, 0, 22), Font = Theme.Fonts.title, TextSize = 19, TextColor3 = C.accent, Text = "Equipped", Parent = left })
	for i, slot in ipairs(Items.Slots) do
		local row = Theme.make("TextButton", {
			Position = UDim2.fromOffset(0, 26 + (i - 1) * 46),
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundColor3 = C.panel,
			AutoButtonColor = false,
			Text = "",
			Parent = left,
		})
		Theme.corner(row, 8)
		Theme.label({ Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(34, 42), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Text = Items.SlotInfo[slot].icon, Parent = row })
		local entry = {
			name = Theme.label({ Position = UDim2.fromOffset(40, 3), Size = UDim2.new(1, -44, 0, 18), TextSize = 13, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = row }),
			stats = Theme.label({ Position = UDim2.fromOffset(40, 21), Size = UDim2.new(1, -44, 0, 16), TextSize = 11, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", Parent = row }),
		}
		equippedRows[slot] = entry
		row.Activated:Connect(function()
			if entry.itemId then
				selectedId = entry.itemId
				Inventory.refresh()
			end
		end)
	end
	Theme.label({ Position = UDim2.fromOffset(0, 262), Size = UDim2.new(1, 0, 0, 22), Font = Theme.Fonts.title, TextSize = 19, TextColor3 = C.accent, Text = "Your Stats", Parent = left })
	statsLabel = Theme.label({ Position = UDim2.fromOffset(0, 286), Size = UDim2.new(1, 0, 1, -286), TextSize = 14, TextYAlignment = Enum.TextYAlignment.Top, Text = "", Parent = left })

	-- Bag column
	local right = Theme.make("Frame", { Position = UDim2.fromOffset(292, 0), Size = UDim2.new(1, -292, 1, 0), BackgroundTransparency = 1, Parent = gearPage })
	bagHeader = Theme.label({ Size = UDim2.new(1, -150, 0, 22), Font = Theme.Fonts.title, TextSize = 19, TextColor3 = C.accent, Text = "Bag", Parent = right })
	Theme.button("⚡ Equip Best", Color3.fromRGB(60, 140, 70), function()
		task.spawn(function()
			local ok, changed = Remotes.func("EquipBest"):InvokeServer()
			if ok then
				App.Sfx.play("Click")
				App.Notifications.toast(changed and changed > 0 and string.format("Equipped %d better item%s!", changed, changed == 1 and "" or "s") or "You're already wearing your best gear.", C.good, "⚔️")
			end
		end)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, -4), Size = UDim2.fromOffset(140, 28), TextSize = 14, Parent = right })
	bagGrid = Theme.scroll(right, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -166) })
	Theme.make("UIGridLayout", { CellSize = UDim2.fromOffset(122, 64), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bagGrid })

	details.frame = Theme.make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 132), BackgroundColor3 = C.panel2, Visible = false, Parent = right })
	Theme.corner(details.frame, 10)
	Theme.pad(details.frame, 10)
	details.name = Theme.label({ Size = UDim2.new(1, -130, 0, 22), Font = Theme.Fonts.title, TextSize = 19, Parent = details.frame })
	details.info = Theme.label({ Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext, Parent = details.frame })
	details.stats = Theme.label({ Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, -130, 0, 64), TextSize = 14, TextYAlignment = Enum.TextYAlignment.Top, Parent = details.frame })
	details.equip = Theme.button("Equip", Color3.fromRGB(60, 140, 70), function()
		local p = App.State.profile
		local item = selectedId and App.State.findItem(selectedId)
		if not p or not item then
			return
		end
		task.spawn(function()
			if p.equipped[item.slot] == item.id then
				Remotes.func("UnequipItem"):InvokeServer(item.slot)
			else
				Remotes.func("EquipItem"):InvokeServer(item.id)
				App.Sfx.play("Click")
			end
		end)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(120, 40), Parent = details.frame })

	-- Seeds page
	Theme.label({ Size = UDim2.new(1, 0, 0, 22), TextSize = 14, TextColor3 = C.subtext, Text = "Plant seeds at the planting spots in your lair (🏠 button). Water them when they get thirsty (💧)!", Parent = seedsPage })
	seedsList = Theme.scroll(seedsPage, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	Theme.list(seedsList, 6)

	App.Windows.register("Inventory", window, Inventory.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Inventory.refresh()
		end
	end)
end

return Inventory
