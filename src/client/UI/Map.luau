-- Minimap (top right) and the full world map (M). Both are drawn from the same data the world
-- is built from (Config/Zones), so they always match the terrain: town streets, lairs, the
-- winding river, lakes, camps, hunting grounds, shops and fishing spots.
-- The full map lets you pick a place (or click anywhere) to set a waypoint, or track a quest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Quests = require(Shared.Config.Quests)
local Util = require(Shared.Util)

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Map = {}
local App

local player = Players.LocalPlayer
local MIN_X, MIN_Z = Zones.WorldBounds.min.X, Zones.WorldBounds.min.Z
local MAX_X, MAX_Z = Zones.WorldBounds.max.X, Zones.WorldBounds.max.Z
local MINI_SIZE = 180
local MINI_SCALE = 0.55 -- pixels per stud on the minimap
local BIG_SCALE = 0.365

local mini = {} -- { frame, entry, arrow, zoneLabel, edgePin, arenaLabel }
local big = {} -- { window, entry, arrow, list }

---------------------------------------------------------------- canvas drawing

-- A map canvas at `scale` pixels per stud. Returns the canvas and a table of drawing helpers.
local function newCanvas(parent: Instance, scale: number, labels: boolean)
	local canvas = Theme.make("Frame", {
		Name = "Canvas",
		Size = UDim2.fromOffset((MAX_X - MIN_X) * scale, (MAX_Z - MIN_Z) * scale),
		BackgroundColor3 = Color3.fromRGB(86, 138, 64),
		BorderSizePixel = 0,
		Parent = parent,
	})
	local function px(x: number, z: number): (number, number)
		return (x - MIN_X) * scale, (z - MIN_Z) * scale
	end
	local draw = {}
	function draw.rect(x0: number, z0: number, x1: number, z1: number, color: Color3, transparency: number?, z: number?)
		local ax, az = px(math.min(x0, x1), math.min(z0, z1))
		local bx, bz = px(math.max(x0, x1), math.max(z0, z1))
		return Theme.make("Frame", {
			Position = UDim2.fromOffset(ax, az),
			Size = UDim2.fromOffset(bx - ax, bz - az),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			ZIndex = z or 1,
			Parent = canvas,
		})
	end
	function draw.circle(x: number, zz: number, r: number, color: Color3, transparency: number?, z: number?)
		local cx, cz = px(x, zz)
		local f = Theme.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cz),
			Size = UDim2.fromOffset(r * 2 * scale, r * 2 * scale),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			ZIndex = z or 1,
			Parent = canvas,
		})
		Theme.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
		return f
	end
	function draw.line(a: Vector3, b: Vector3, width: number, color: Color3, z: number?)
		local ax, az = px(a.X, a.Z)
		local bx, bz = px(b.X, b.Z)
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		return Theme.make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((ax + bx) / 2, (az + bz) / 2),
			Size = UDim2.fromOffset(length + width * scale, math.max(2, width * scale)),
			Rotation = math.deg(math.atan2(bz - az, bx - ax)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z or 2,
			Parent = canvas,
		})
	end
	function draw.text(x: number, zz: number, text: string, size: number, color: Color3?, z: number?)
		local cx, cz = px(x, zz)
		return Theme.label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cz),
			Size = UDim2.fromOffset(160, size + 6),
			TextSize = size,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = color or Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.3,
			TextWrapped = false,
			Text = text,
			ZIndex = z or 6,
			Parent = canvas,
		})
	end
	draw.px = px

	-- terrain and areas
	draw.rect(MIN_X, 248, MAX_X, MAX_Z, Color3.fromRGB(74, 112, 60))
	local tints = {
		ElkMeadows = Color3.fromRGB(125, 170, 85),
		Whisperwood = Color3.fromRGB(50, 100, 55),
		BearclawHollow = Color3.fromRGB(120, 110, 90),
		FrostfangRidge = Color3.fromRGB(215, 228, 238),
	}
	for id, color in pairs(tints) do
		local a = Zones.getArea(id)
		draw.rect(a.min.X, a.min.Z, a.max.X, a.max.Z, color, 0.15)
	end
	local town = Zones.getArea("Town")
	draw.rect(town.min.X, town.min.Z, town.max.X, town.max.Z, Color3.fromRGB(128, 165, 100))
	for _, road in ipairs(Zones.Roads) do
		draw.line(road.a, road.b, road.width, Color3.fromRGB(175, 170, 160))
	end
	for _, path in ipairs(Zones.Paths) do
		draw.line(path.a, path.b, path.width, Color3.fromRGB(135, 105, 72))
	end
	draw.circle(0, 0, 50, Color3.fromRGB(175, 170, 160), 0, 2)
	local bz = Zones.getArea("BattleZone")
	draw.rect(bz.min.X, bz.min.Z, bz.max.X, bz.max.Z, Color3.fromRGB(185, 75, 65), 0, 2)
	for _, base in ipairs(Zones.Bases) do
		local depth, width = Zones.BaseSize.X, Zones.BaseSize.Z
		local hx = math.abs(base.facing.X) > 0.5 and depth / 2 or width / 2
		local hz = math.abs(base.facing.X) > 0.5 and width / 2 or depth / 2
		local f = draw.rect(base.center.X - hx, base.center.Z - hz, base.center.X + hx, base.center.Z + hz, Color3.fromRGB(100, 150, 78), 0, 2)
		f.Name = "Base" .. base.index
		Theme.stroke(f, Color3.fromRGB(95, 70, 45), 1)
	end
	-- water
	for _, p in ipairs(Util.spline(Zones.River.points, 16)) do
		draw.circle(p.X, p.Z, Zones.River.width / 2, Color3.fromRGB(70, 130, 210), 0, 3)
	end
	for _, lake in ipairs(Zones.Lakes) do
		for _, lobe in ipairs(lake.lobes) do
			draw.circle(lake.center.X + lobe[1], lake.center.Z + lobe[2], lobe[3], lake.frozen and Color3.fromRGB(195, 228, 248) or Color3.fromRGB(70, 130, 210), 0, 3)
		end
	end
	-- camps
	for _, camp in ipairs(Zones.Camps) do
		draw.circle(camp.center.X, camp.center.Z, camp.radius, Color3.fromRGB(160, 60, 50), 0.45, 4)
		draw.text(camp.center.X, camp.center.Z, "⚔️", 16, nil, 5)
		if labels then
			draw.text(camp.center.X, camp.center.Z + camp.radius + 16, string.format("%s  Lv %d-%d", camp.name, camp.levels[1], camp.levels[2]), 12, Color3.fromRGB(255, 200, 190))
		end
	end
	-- points of interest
	local shopIcons = { Armory = "⚔️", Exchange = "💰", Forge = "🔨", Alchemist = "🧪", Hatchery = "🥚" }
	for _, shop in ipairs(Zones.Shops) do
		draw.text(shop.position.X, shop.position.Z, shopIcons[shop.id] or "🛒", 13, nil, 5)
	end
	for _, spot in pairs(Zones.QuestGivers) do
		draw.text(spot.position.X, spot.position.Z, "🐉", 12, nil, 5)
	end
	draw.text(Zones.WarHorn.X, Zones.WarHorn.Z, "📯", 13, nil, 5)
	draw.text(Zones.Training.dummies[2].X, Zones.Training.dummies[2].Z + 30, "🎯", 13, nil, 5)
	for _, spot in ipairs(Zones.FishingSpots) do
		draw.text(spot.pos.X, spot.pos.Z, "🎣", 11, nil, 5)
	end
	if labels then
		for _, id in ipairs({ "ElkMeadows", "Whisperwood", "BearclawHollow", "FrostfangRidge", "BattleZone" }) do
			local a = Zones.getArea(id)
			draw.text((a.min.X + a.max.X) / 2, (a.min.Z + a.max.Z) / 2 - (id == "BattleZone" and 0 or 60), a.name, 14, a.color)
		end
		draw.text(0, 80, "Dragon Town", 15, Color3.fromRGB(255, 230, 160))
		draw.text(0, 260, "~ River ~", 11, Color3.fromRGB(200, 230, 255))
	end

	-- dynamic layer: dots for dragons, the waypoint and quest pins
	local dynamic = Theme.make("Frame", { Name = "Dynamic", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10, Parent = canvas })
	return { canvas = canvas, draw = draw, scale = scale, dynamic = dynamic, dots = {}, pins = {} }
end

-- Your dragon: a gold dot with a nose pointing where you face (no font glyphs needed).
local function makeArrow(parent: Instance, size: number)
	local holder = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = 30, Parent = parent })
	local body = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.6, 0.6), BackgroundColor3 = Color3.fromRGB(255, 215, 80), ZIndex = 31, Parent = holder })
	Theme.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = body })
	Theme.stroke(body, Color3.fromRGB(40, 25, 10), 2)
	local nose = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.24, 0.45), BackgroundColor3 = Color3.fromRGB(255, 240, 180), ZIndex = 32, Parent = holder })
	Theme.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = nose })
	return holder
end

local function heading(root: BasePart): number
	local look = root.CFrame.LookVector
	-- map up = -Z (north)
	return math.deg(math.atan2(look.X, -look.Z))
end

local function pin(entry, key: string, text: string, color: Color3)
	local p = entry.pins[key]
	if not p then
		p = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = color, ZIndex = 20, Parent = entry.dynamic })
		Theme.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = p })
		Theme.stroke(p, Color3.new(1, 1, 1), 2)
		Theme.label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -1), Size = UDim2.fromOffset(24, 18), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Text = text, ZIndex = 21, Name = "Icon", Parent = p })
		entry.pins[key] = p
	end
	return p
end

-- Move dots and pins on one canvas.
local function updateDynamic(entry)
	local draw = entry.draw
	local seen = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and other ~= player then
			local dot = entry.dots[other]
			if not dot then
				dot = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.fromRGB(90, 180, 255), ZIndex = 15, Parent = entry.dynamic })
				Theme.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
				Theme.stroke(dot, Color3.new(1, 1, 1), 1)
				entry.dots[other] = dot
			end
			local x, z = draw.px(root.Position.X, root.Position.Z)
			dot.Position = UDim2.fromOffset(x, z)
			seen[other] = true
		end
	end
	for other, dot in pairs(entry.dots) do
		if not seen[other] then
			dot:Destroy()
			entry.dots[other] = nil
		end
	end
	-- waypoint
	local wp = App.Waypoint.get()
	local wpPin = pin(entry, "waypoint", "📍", Color3.fromRGB(235, 70, 60))
	wpPin.Visible = wp ~= nil
	if wp then
		local x, z = draw.px(wp.pos.X, wp.pos.Z)
		wpPin.Position = UDim2.fromOffset(x, z)
	end
	-- the lair
	local home = App.Waypoint.homePosition()
	local homePin = pin(entry, "home", "🏠", Color3.fromRGB(255, 205, 80))
	homePin.Visible = home ~= nil
	if home then
		local x, z = draw.px(home.X, home.Z)
		homePin.Position = UDim2.fromOffset(x, z)
	end
end

---------------------------------------------------------------- minimap

local function buildMini(root: Instance)
	local frame = Theme.make("Frame", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -86, 0, 10),
		Size = UDim2.fromOffset(MINI_SIZE, MINI_SIZE),
		BackgroundColor3 = Color3.fromRGB(30, 50, 30),
		ClipsDescendants = true,
		Parent = root,
	})
	Theme.stroke(frame, C.accentDark, 3)
	mini.frame = frame
	mini.entry = newCanvas(frame, MINI_SCALE, false)
	mini.arrow = makeArrow(frame, 18)
	mini.arrow.Position = UDim2.fromScale(0.5, 0.5)
	-- waypoint off the edge of the minimap: a pin stuck to the border pointing the way
	mini.edgePin = Theme.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(235, 70, 60), Visible = false, ZIndex = 40, Parent = frame })
	Theme.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = mini.edgePin })
	Theme.stroke(mini.edgePin, Color3.new(1, 1, 1), 2)
	mini.arenaLabel = Theme.label({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.3, BackgroundColor3 = Color3.fromRGB(60, 20, 20), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "⚔️ Boss Arena", Visible = false, ZIndex = 50, Parent = frame })
	local open = Theme.make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 60, Parent = frame })
	open.Activated:Connect(function()
		App.Windows.toggle("Map")
	end)
	mini.zoneLabel = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -86, 0, MINI_SIZE + 12),
		Size = UDim2.fromOffset(MINI_SIZE, 18),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Text = "",
		Parent = root,
	})
	Theme.label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -90, 0, MINI_SIZE + 6),
		Size = UDim2.fromOffset(60, 16),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.3,
		Text = "M = map",
		ZIndex = 70,
		Parent = root,
	})
end

local function updateMini()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local pos = root.Position
	local inWorld = Zones.inWorld(pos)
	mini.arenaLabel.Visible = not inWorld
	local entry = mini.entry
	local x, z = entry.draw.px(pos.X, pos.Z)
	entry.canvas.Position = UDim2.fromOffset(MINI_SIZE / 2 - x, MINI_SIZE / 2 - z)
	mini.arrow.Rotation = heading(root)
	local area = Zones.areaAt(pos)
	mini.zoneLabel.Text = area and area.name or "The Wilds"
	-- edge pin when the waypoint is off the minimap
	local wp = App.Waypoint.get()
	if wp then
		local dx, dz = (wp.pos.X - pos.X) * MINI_SCALE, (wp.pos.Z - pos.Z) * MINI_SCALE
		local half = MINI_SIZE / 2 - 9
		local outside = math.abs(dx) > half or math.abs(dz) > half
		mini.edgePin.Visible = outside
		if outside then
			local k = half / math.max(math.abs(dx), math.abs(dz))
			mini.edgePin.Position = UDim2.fromOffset(MINI_SIZE / 2 + dx * k, MINI_SIZE / 2 + dz * k)
		end
	else
		mini.edgePin.Visible = false
	end
end

---------------------------------------------------------------- full map

local function placesList()
	local list = {
		{ "🏠 Your lair", nil, "home" },
		{ "🐉 Town square", Vector3.new(0, 0, 0) },
		{ "🎯 Training grounds", Zones.Training.dummies[2] },
		{ "📯 War Horn (bosses)", Zones.WarHorn },
	}
	for _, shop in ipairs(Zones.Shops) do
		table.insert(list, { ({ Armory = "⚔️ ", Exchange = "💰 ", Forge = "🔨 ", Alchemist = "🧪 ", Hatchery = "🥚 " })[shop.id] .. shop.name, shop.position })
	end
	local bzArea = Zones.getArea("BattleZone")
	table.insert(list, { "🏟️ Battle Zone (PvP)", (bzArea.min + bzArea.max) / 2 })
	for _, area in ipairs(Zones.HuntingGrounds) do
		local a = Zones.getArea(area.id)
		table.insert(list, { string.format("🦌 %s (Lv %d-%d)", a.name, area.levels[1], area.levels[2]), (area.min + area.max) / 2 })
	end
	for _, camp in ipairs(Zones.Camps) do
		table.insert(list, { string.format("⚔️ %s (Lv %d-%d)", camp.name, camp.levels[1], camp.levels[2]), camp.center })
	end
	return list
end

function Map.refreshList()
	local p = App.State.profile
	if not p or not big.list then
		return
	end
	Theme.clear(big.list)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local wp = App.Waypoint.get()
	Theme.label({ Size = UDim2.new(1, -8, 0, 22), LayoutOrder = nextOrder(), Font = Theme.Fonts.title, TextSize = 17, TextColor3 = C.accent, Text = "📍 Waypoint: " .. (wp and wp.label or "none"), Parent = big.list })
	if wp then
		Theme.button("Clear waypoint", C.panel3, function()
			App.Waypoint.clear()
			Map.refreshList()
		end, { Size = UDim2.new(1, -8, 0, 28), LayoutOrder = nextOrder(), TextSize = 13, Parent = big.list })
	end
	Theme.label({ Size = UDim2.new(1, -8, 0, 22), LayoutOrder = nextOrder(), Font = Theme.Fonts.title, TextSize = 16, TextColor3 = C.accent, Text = "📜 Quests", Parent = big.list })
	local any = false
	local questIds = {}
	for questId in pairs(p.quests.active) do
		if Quests.byId[questId] then
			table.insert(questIds, questId)
		end
	end
	table.sort(questIds, function(a, b)
		return Quests.byId[a].order < Quests.byId[b].order
	end)
	for _, questId in ipairs(questIds) do
		local quest = Quests.byId[questId]
		local pos, label = App.Waypoint.questTarget(questId)
		if pos then
			any = true
			local tracked = App.Waypoint.trackedQuestId() == questId
			Theme.button((tracked and "📍 " or "") .. quest.name .. "  (" .. label .. ")", tracked and Color3.fromRGB(150, 70, 60) or C.panel3, function()
				App.Waypoint.trackQuest(questId)
				Map.refreshList()
			end, { Size = UDim2.new(1, -8, 0, 28), LayoutOrder = nextOrder(), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = big.list })
		end
	end
	if not any then
		Theme.label({ Size = UDim2.new(1, -8, 0, 20), LayoutOrder = nextOrder(), TextSize = 12, TextColor3 = C.subtext, Text = "No quests to track. Talk to a dragon with a ❗", Parent = big.list })
	end
	Theme.label({ Size = UDim2.new(1, -8, 0, 22), LayoutOrder = nextOrder(), Font = Theme.Fonts.title, TextSize = 16, TextColor3 = C.accent, Text = "🧭 Places", Parent = big.list })
	for _, place in ipairs(placesList()) do
		Theme.button(place[1], C.panel3, function()
			local pos = place[3] == "home" and App.Waypoint.homePosition() or place[2]
			if pos then
				App.Waypoint.setPlace(pos, (place[1]:gsub("^%S+%s", "")))
				Map.refreshList()
			end
		end, { Size = UDim2.new(1, -8, 0, 26), LayoutOrder = nextOrder(), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = big.list })
	end
end

local function buildBig()
	local window, content, close = Theme.window(App.Windows.guis.Windows, "🗺️ World Map", Vector2.new(760, 640))
	close.Activated:Connect(function()
		App.Windows.close("Map")
	end)
	big.window = window
	local holder = Theme.make("Frame", {
		Size = UDim2.fromOffset((MAX_X - MIN_X) * BIG_SCALE, (MAX_Z - MIN_Z) * BIG_SCALE),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})
	Theme.stroke(holder, C.accentDark, 2)
	big.entry = newCanvas(holder, BIG_SCALE, true)
	big.arrow = makeArrow(big.entry.dynamic, 16)
	-- click anywhere on the map to put a waypoint there
	local clicker = Theme.make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 60, Parent = holder })
	clicker.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local absPos, absSize = holder.AbsolutePosition, holder.AbsoluteSize
		if absSize.X <= 0 then
			return
		end
		-- mouse input positions sit below the top bar; AbsolutePosition does too
		local localX = (input.Position.X - absPos.X) / absSize.X
		local localZ = (input.Position.Y - absPos.Y) / absSize.Y
		if localX < 0 or localX > 1 or localZ < 0 or localZ > 1 then
			return
		end
		local pos = Vector3.new(MIN_X + localX * (MAX_X - MIN_X), 0, MIN_Z + localZ * (MAX_Z - MIN_Z))
		local area = Zones.areaAt(pos)
		App.Waypoint.setPlace(pos, area and area.name or "Marked spot")
		Map.refreshList()
	end)
	Theme.label({ Position = UDim2.new(0, 0, 1, -18), Size = UDim2.fromOffset(410, 18), TextSize = 12, TextColor3 = C.subtext, Text = "Click the map to set a waypoint. 🏠 = your lair, blue dots = other dragons.", Parent = content })
	big.list = Theme.scroll(content, { Position = UDim2.fromOffset((MAX_X - MIN_X) * BIG_SCALE + 12, 0), Size = UDim2.new(1, -((MAX_X - MIN_X) * BIG_SCALE + 12), 1, 0) })
	Theme.list(big.list, 4)
	App.Windows.register("Map", window, Map.refreshList)
end

local function updateBig()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		big.arrow.Visible = false
		return
	end
	big.arrow.Visible = Zones.inWorld(root.Position)
	local x, z = big.entry.draw.px(root.Position.X, root.Position.Z)
	big.arrow.Position = UDim2.fromOffset(x, z)
	big.arrow.Rotation = heading(root)
end

function Map.init(app)
	App = app
	buildMini(App.Windows.guis.HUD)
	buildBig()
	App.Waypoint.changed:Connect(function()
		if big.window.Visible then
			Map.refreshList()
		end
	end)
	local accum = 0
	RunService.RenderStepped:Connect(function(dt)
		updateMini()
		if big.window.Visible then
			updateBig()
		end
		accum += dt
		if accum >= 0.2 then
			accum = 0
			updateDynamic(mini.entry)
			if big.window.Visible then
				updateDynamic(big.entry)
			end
		end
	end)
	-- outline your own lair in gold
	App.State.changed:Connect(function(p)
		for _, entry in ipairs({ mini.entry, big.entry }) do
			for _, base in ipairs(Zones.Bases) do
				local f = entry.canvas:FindFirstChild("Base" .. base.index)
				local stroke = f and f:FindFirstChildOfClass("UIStroke")
				if stroke then
					local mine = p and p.baseIndex == base.index
					stroke.Color = mine and Color3.fromRGB(255, 215, 80) or Color3.fromRGB(95, 70, 45)
					stroke.Thickness = mine and 3 or 1
				end
			end
		end
	end)
end

return Map
