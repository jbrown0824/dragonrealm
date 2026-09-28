-- Pets window: your nano dragons (equip, release) and your eggs (buy at the Hatchery, hatch
-- anywhere with a little reveal animation).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local PetInfo = require(Shared.Config.Pets)
local StatCalc = require(Shared.StatCalc)
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
local eggsList
local selected = nil
local releaseArmed = nil
local busy = false
local overlay

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
local function preview(parent: GuiObject, speciesId: string)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	local species = PetInfo.get(speciesId)
	if not species then
		return
	end
	local model = DragonBuilder.build(species.plan, { anchored = true, noParticles = true, lite = true, colors = species.look.colors, fire = species.look.fire })
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
	if busy then
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
			App.Notifications.toast(result, C.bad, "🐲")
		end
	end)
end

---------------------------------------------------------------- hatching

local function showHatch(pet)
	local species = PetInfo.get(pet.species)
	local color = PetInfo.RarityColors[species.rarity]
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
		card.Rarity.Text = species.rarity:upper() .. " NANO DRAGON"
		card.Rarity.TextColor3 = color
		card.Stats.Text = statText(species.stats)
		card.UIStroke.Color = color
		preview(card.View, pet.species)
		App.Sfx.play("LevelUp")
	end)
end

---------------------------------------------------------------- pages

local function refreshPets(p)
	local slots = p.petSlots or 1
	local equipped = p.petsEquipped or {}
	local nextLevel = Game.PET_SLOT_LEVELS[slots + 1]
	header.Text = string.format("Following you: <font color=\"#FFD24A\">%d / %d</font>%s   •   Nest: %d / %d",
		math.min(#equipped, slots), slots, nextLevel and string.format(" (another slot at level %d)", nextLevel) or "", #(p.pets or {}), Game.PET_LIMIT)
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
		return sa.name < sb.name
	end)
	for i, pet in ipairs(list) do
		local species = PetInfo.get(pet.species)
		local color = PetInfo.RarityColors[species.rarity]
		local isEquipped = table.find(equipped, pet.uid) ~= nil
		local cardButton = Theme.make("TextButton", { BackgroundColor3 = C.panel2, AutoButtonColor = false, Text = "", LayoutOrder = i, Parent = grid })
		Theme.corner(cardButton, 8)
		Theme.stroke(cardButton, color, selected == pet.uid and 3 or 1.5, selected == pet.uid and 0 or 0.3)
		Theme.label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 34), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Text = PLAN_ICONS[species.plan] or "🐲", Parent = cardButton })
		Theme.label({ Position = UDim2.fromOffset(4, 40), Size = UDim2.new(1, -8, 0, 28), TextSize = 11, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Text = species.name, Parent = cardButton })
		if isEquipped then
			Theme.label({ Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(30, 16), TextSize = 12, TextColor3 = C.good, Text = "✅", Parent = cardButton })
		end
		cardButton.Activated:Connect(function()
			selected = pet.uid
			releaseArmed = nil
			Pets.refresh()
		end)
	end
	if #list == 0 then
		Theme.label({ Size = UDim2.new(1, 0, 0, 60), TextSize = 15, TextColor3 = C.subtext, Text = "No pets yet! Buy an egg at Nestmother's Hatchery in town, or find one on a camp champion.", Parent = grid })
	end

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
		details.name.Text = species.name
		details.name.TextColor3 = color
		details.info.Text = string.format("%s nano dragon  •  %s body", species.rarity, species.plan)
		details.stats.Text = "Boosts: " .. statText(species.stats)
		details.equip.Text = isEquipped and "Unequip" or "Equip"
		details.equip.BackgroundColor3 = isEquipped and Color3.fromRGB(120, 60, 60) or Color3.fromRGB(60, 140, 70)
		details.release.Text = releaseArmed == pet.uid and "Really release?" or string.format("Release (+%d 💰)", PetInfo.ReleaseGold[species.rarity] or 0)
		if details.shown ~= pet.uid then
			details.shown = pet.uid
			preview(details.view, pet.species)
		end
	end
end

local function refreshEggs(p)
	Theme.clear(eggsList)
	for i, eggId in ipairs(PetInfo.EggOrder) do
		local egg = PetInfo.Eggs[eggId]
		local count = (p.eggs and p.eggs[eggId]) or 0
		local row = Theme.make("Frame", { Size = UDim2.new(1, -10, 0, 86), BackgroundColor3 = C.panel2, LayoutOrder = i, Parent = eggsList })
		Theme.corner(row, 8)
		Theme.stroke(row, egg.color, 1.5, 0.4)
		Theme.label({ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(60, 70), TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Text = egg.icon, Parent = row })
		Theme.label({ Position = UDim2.fromOffset(74, 6), Size = UDim2.new(1, -330, 0, 24), Font = Theme.Fonts.title, TextSize = 20, TextColor3 = egg.color, Text = string.format("%s  <font color=\"#FFFFFF\">x%d</font>", egg.name, count), Parent = row })
		local odds = {}
		for _, r in ipairs(PetInfo.RarityOrder) do
			if egg.weights[r] then
				table.insert(odds, string.format("<font color=\"%s\">%s %d%%</font>", Theme.colorHex(PetInfo.RarityColors[r]), r, egg.weights[r]))
			end
		end
		Theme.label({ Position = UDim2.fromOffset(74, 32), Size = UDim2.new(1, -330, 0, 48), TextSize = 12, Font = Theme.Fonts.body, TextColor3 = C.subtext, TextYAlignment = Enum.TextYAlignment.Top, Text = egg.desc .. "\n" .. table.concat(odds, "  "), Parent = row })
		local hatch = Theme.button("🐣 Hatch", Color3.fromRGB(200, 120, 60), function()
			invoke("HatchEgg", eggId, function(pet)
				selected = pet.uid
				showHatch(pet)
			end)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 40), Parent = row })
		Theme.setButtonEnabled(hatch, count > 0)
		if egg.price then
			local buy = Theme.button(Util.formatNumber(egg.price) .. " 💰", Color3.fromRGB(70, 140, 80), function()
				invoke("BuyEgg", eggId, function()
					App.Sfx.play("Coin")
					App.Notifications.toast("Bought a " .. egg.name .. "! Hatch it whenever you like.", egg.color, "🥚")
				end)
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -126, 0.5, 0), Size = UDim2.fromOffset(110, 40), Parent = row })
			Theme.setButtonEnabled(buy, p.gold >= egg.price)
		else
			Theme.label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -126, 0.5, 0), Size = UDim2.fromOffset(110, 40), TextSize = 11, TextColor3 = C.subtext, TextXAlignment = Enum.TextXAlignment.Center, Text = "Drops from champions, bosses & chests", Parent = row })
		end
	end
	Theme.label({ Size = UDim2.new(1, -10, 0, 30), LayoutOrder = 10, TextSize = 12, TextColor3 = C.subtext, Text = "Buy eggs at Nestmother's Hatchery in town (east of the plaza). You can hatch them anywhere.", Parent = eggsList })
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
	window, content, close = Theme.window(App.Windows.guis.Windows, "🐲 Nano Dragons", Vector2.new(820, 560))
	close.Activated:Connect(function()
		App.Windows.close("Pets")
	end)
	for i, name in ipairs({ "Pets", "Eggs" }) do
		tabButtons[name] = Theme.button(name == "Pets" and "🐲 My Pets" or "🥚 Eggs", C.panel3, function()
			tab = name
			Pets.refresh()
		end, { Position = UDim2.fromOffset((i - 1) * 130, 0), Size = UDim2.fromOffset(120, 32), TextSize = 15, Parent = content })
	end
	petsPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Parent = content })
	eggsPage = Theme.make("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), BackgroundTransparency = 1, Visible = false, Parent = content })

	header = Theme.label({ Size = UDim2.new(1, -300, 0, 22), TextSize = 14, Parent = petsPage })
	Theme.button("⚡ Equip Best", Color3.fromRGB(60, 140, 70), function()
		invoke("EquipBestPets", nil, function()
			App.Sfx.play("Click")
			App.Notifications.toast("Your best pets are following you!", C.good, "🐲")
		end)
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -290, 0, -4), Size = UDim2.fromOffset(140, 28), TextSize = 14, Parent = petsPage })
	grid = Theme.scroll(petsPage, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -290, 1, -26) })
	Theme.make("UIGridLayout", { CellSize = UDim2.fromOffset(100, 74), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	Theme.make("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3), Parent = grid })

	details.frame = Theme.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 26), Size = UDim2.new(0, 280, 1, -26), BackgroundColor3 = C.panel2, Visible = false, Parent = petsPage })
	Theme.corner(details.frame, 10)
	Theme.pad(details.frame, 10)
	details.view = Theme.make("ViewportFrame", { Size = UDim2.new(1, 0, 0, 170), BackgroundColor3 = Color3.fromRGB(35, 30, 50), Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.fromRGB(255, 245, 230), LightDirection = Vector3.new(-1, -1.5, -0.5), Parent = details.frame })
	Theme.corner(details.view, 10)
	details.name = Theme.label({ Position = UDim2.fromOffset(0, 176), Size = UDim2.new(1, 0, 0, 26), Font = Theme.Fonts.title, TextSize = 22, Parent = details.frame })
	details.info = Theme.label({ Position = UDim2.fromOffset(0, 202), Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = C.subtext, Parent = details.frame })
	details.stats = Theme.label({ Position = UDim2.fromOffset(0, 224), Size = UDim2.new(1, 0, 0, 50), TextSize = 14, TextColor3 = C.good, TextYAlignment = Enum.TextYAlignment.Top, Parent = details.frame })
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
			App.Notifications.toast(string.format("Your pet flew off into the wild. +%d gold", gold or 0), C.gold, "🐲")
		end)
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 36), TextSize = 14, Parent = details.frame })

	eggsList = Theme.scroll(eggsPage, { Size = UDim2.fromScale(1, 1) })
	Theme.list(eggsList, 8)

	-- Hatch reveal overlay
	overlay = Theme.make("Frame", { Name = "HatchOverlay", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Visible = false, ZIndex = 50, Parent = App.Windows.guis.Top })
	Theme.label({ Name = "Egg", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(160, 160), TextSize = 140, TextXAlignment = Enum.TextXAlignment.Center, Text = "🥚", ZIndex = 51, Parent = overlay })
	local card = Theme.make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(380, 400), BackgroundColor3 = C.panel, Visible = false, ZIndex = 51, Parent = overlay })
	Theme.corner(card, 14)
	Theme.stroke(card, C.accent, 3)
	Theme.label({ Name = "Rarity", Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52, Parent = card })
	local view = Theme.make("ViewportFrame", { Name = "View", Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -40, 0, 210), BackgroundColor3 = Color3.fromRGB(35, 30, 50), Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.fromRGB(255, 245, 230), LightDirection = Vector3.new(-1, -1.5, -0.5), ZIndex = 52, Parent = card })
	Theme.corner(view, 10)
	Theme.label({ Name = "Title", Position = UDim2.fromOffset(0, 252), Size = UDim2.new(1, 0, 0, 34), Font = Theme.Fonts.title, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52, Parent = card })
	Theme.label({ Name = "Stats", Position = UDim2.fromOffset(20, 290), Size = UDim2.new(1, -40, 0, 44), TextSize = 15, TextColor3 = C.good, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52, Parent = card })
	Theme.button("Awesome!", Color3.fromRGB(60, 140, 70), function()
		overlay.Visible = false
	end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(180, 42), ZIndex = 52, Parent = card })

	App.Windows.register("Pets", window, Pets.refresh)
	App.State.changed:Connect(function()
		if window.Visible then
			Pets.refresh()
		end
	end)
end

return Pets
