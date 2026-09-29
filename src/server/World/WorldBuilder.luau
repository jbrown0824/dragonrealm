-- Generates the whole map at server start: terrain, Dragon Town (plaza, shops, quest givers,
-- training grounds, player bases, Battle Zone), the wilds around it (river, lakes, hunting
-- grounds: see Wilds), the viking camps (see Camps), and the Boss Arena.
-- Positions come from Config/Zones so gameplay and scenery always line up.
--
-- Want to hand-build the map in Studio instead? Keep the tags/attributes these files set
-- (PlayerBase, ShopPrompt, PanelPrompt, QuestPrompt, WarHornPrompt, Plots/Plot1..12, HomeSpawn,
-- BotDock, Sign, CampChest, TrainingDummy, FishingSpot) and the services will keep working.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Quests = require(Shared.Config.Quests)
local Game = require(Shared.Config.Game)

local Props = require(script.Parent.Props)
local WorldUtil = require(script.Parent.WorldUtil)
local Wilds = require(script.Parent.Wilds)
local Camps = require(script.Parent.Camps)

local WorldBuilder = {}

local terrain = WorldUtil.terrain
local rng = WorldUtil.rng
local folder = WorldUtil.folder
local facingCF = WorldUtil.facingCF
local terrainPath = WorldUtil.terrainPath
local invisibleWall = WorldUtil.invisibleWall
local placeDragon = WorldUtil.placeDragon


local function nearCamp(p: Vector3, extra: number): boolean
	for _, camp in ipairs(Zones.Camps) do
		if (Vector3.new(p.X, 0, p.Z) - camp.center).Magnitude < camp.radius + extra then
			return true
		end
	end
	return false
end

local function nearPath(p: Vector3, margin: number): boolean
	for _, path in ipairs(Zones.Paths) do
		if WorldUtil.flatDistToSegment(p, path.a, path.b) < path.width / 2 + margin then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- lighting

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 30
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(205, 205, 220)
	atmosphere.Decay = Color3.fromRGB(110, 115, 135)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.12
	cc.Contrast = 0.06
	cc.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.04
	rays.Parent = Lighting
end

---------------------------------------------------------------- terrain

local function buildTerrain()
	-- Ground for the whole map (top surface at y = 0).
	terrain:FillBlock(CFrame.new(0, -8, 350), Vector3.new(1320, 16, 1720), Enum.Material.Grass)

	-- Town roads and plaza
	terrain:FillCylinder(CFrame.new(0, -2, 0), 4, 50, Enum.Material.Cobblestone)
	for _, road in ipairs(Zones.Roads) do
		terrainPath(road.a, road.b, road.width, Enum.Material[road.material])
	end

	-- Battle Zone floor and the training yard
	terrain:FillBlock(CFrame.new(0, -2, -265), Vector3.new(190, 4, 140), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(100, -2, 176), Vector3.new(70, 4, 104), Enum.Material.Sand)
	local range = Zones.Range
	local rz0, rz1 = range.lanes[1] - range.laneHalf - 4, range.lanes[#range.lanes] + range.laneHalf + 4
	terrain:FillBlock(CFrame.new((range.backstop + range.matX + 8) / 2, -2, (rz0 + rz1) / 2), Vector3.new(range.matX + 8 - range.backstop, 4, rz1 - rz0), Enum.Material.Sand)

	-- Viking lands: colder, muddier ground
	terrain:FillBlock(CFrame.new(0, -2, 710), Vector3.new(1320, 4, 800), Enum.Material.LeafyGrass)
	for _, path in ipairs(Zones.Paths) do
		terrainPath(path.a, path.b, path.width, Enum.Material[path.material])
	end

	-- The river and lakes (curvy basins filled with water)
	Wilds.buildWater()

	-- Snowy mounds in the viking lands, kept off the paths, camps and water
	for _ = 1, 70 do
		local p = Vector3.new(rng:NextNumber(-540, 540), -7, rng:NextNumber(330, 1100))
		local r = rng:NextNumber(9, 18)
		if not nearCamp(p, 30) and not nearPath(p, r + 4) and not Wilds.inAnyLake(p, r + 6) and not Wilds.inRiver(p, r + 10) then
			terrain:FillBall(p, r, Enum.Material.Snow)
		end
	end

	-- Mountains around the edge of the world
	for i = 0, 13 do
		local z = -440 + i * 125
		terrain:FillBall(Vector3.new(-640, -30, z), rng:NextNumber(70, 105), i % 3 == 0 and Enum.Material.Snow or Enum.Material.Rock)
		terrain:FillBall(Vector3.new(640, -30, z), rng:NextNumber(70, 105), i % 3 == 1 and Enum.Material.Snow or Enum.Material.Rock)
	end
	for i = 0, 10 do
		local x = -600 + i * 120
		terrain:FillBall(Vector3.new(x, -30, -500), rng:NextNumber(70, 100), Enum.Material.Rock)
		terrain:FillBall(Vector3.new(x, -25, 1180), rng:NextNumber(80, 110), Enum.Material.Snow)
	end

	-- Boss arena island in a lava sea (off the main map)
	local c = Zones.BossArena.center
	terrain:FillBlock(CFrame.new(c + Vector3.new(0, -12, 0)), Vector3.new(700, 8, 700), Enum.Material.CrackedLava)
	terrain:FillCylinder(CFrame.new(c + Vector3.new(0, -8, 0)), 16, Zones.BossArena.radius + 15, Enum.Material.Basalt)
end

---------------------------------------------------------------- town

local SHOP_STYLE = {
	Armory = { keeper = "Stormwing", awning = Color3.fromRGB(190, 50, 50) },
	Exchange = { keeper = "Shadowstalker", awning = Color3.fromRGB(200, 160, 40) },
	Forge = { keeper = "Behemoth", awning = Color3.fromRGB(60, 90, 170) },
	Alchemist = { keeper = "Venomspine", awning = Color3.fromRGB(90, 170, 80) },
	Hatchery = { keeper = "Frostwyrm", awning = Color3.fromRGB(240, 150, 190) },
}

local function stallGoods(model: Model, cf: CFrame, shopId: string)
	for row = 0, 1 do
		Props.part(model, Vector3.new(16, 0.4, 2), cf * CFrame.new(0, 5 + row * 3, 8.5), Props.DARK_WOOD, Enum.Material.Wood)
		for i = -3, 3 do
			if shopId == "Alchemist" then
				-- potion bottles
				local color = ({ Color3.fromRGB(255, 90, 110), Color3.fromRGB(110, 220, 255), Color3.fromRGB(255, 200, 70), Color3.fromRGB(150, 255, 110), Color3.fromRGB(200, 120, 255) })[(i + row * 2) % 5 + 1]
				local bottle = Props.part(model, Vector3.new(1.6, 1, 1), cf * CFrame.new(i * 2, 6 + row * 3, 8.5) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon)
				bottle.Shape = Enum.PartType.Cylinder
				Props.part(model, Vector3.new(0.4, 0.6, 0.4), cf * CFrame.new(i * 2, 7.1 + row * 3, 8.5), Color3.fromRGB(140, 100, 60), Enum.Material.Wood)
			elseif shopId == "Hatchery" then
				local color = ({ Color3.fromRGB(255, 150, 90), Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 220, 110), Color3.fromRGB(200, 140, 255) })[(i + row) % 4 + 1]
				Props.ellipsoid(model, Vector3.new(1.3, 1.8, 1.3), cf * CFrame.new(i * 2, 6.1 + row * 3, 8.5), color, Enum.Material.SmoothPlastic)
			else
				local color = ({ Color3.fromRGB(200, 60, 60), Color3.fromRGB(80, 160, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(180, 90, 255) })[(i + row) % 4 + 1]
				Props.ellipsoid(model, Vector3.new(1.2, 1.4, 1.2), cf * CFrame.new(i * 2, 5.9 + row * 3, 8.5), color, Enum.Material.Glass)
			end
		end
	end
	if shopId == "Forge" then
		Props.part(model, Vector3.new(5, 4, 4), cf * CFrame.new(7, 2, 5), Color3.fromRGB(90, 85, 85), Enum.Material.Slate)
		local glow = Props.part(model, Vector3.new(3, 0.6, 2.6), cf * CFrame.new(7, 4.2, 5), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		Props.fire(glow, 4)
		Props.light(glow, Color3.fromRGB(255, 140, 60), 20, 2)
		Props.part(model, Vector3.new(3, 1.2, 1.4), cf * CFrame.new(-6, 4.9, -3), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	elseif shopId == "Alchemist" then
		-- a big bubbling cauldron in front of the counter
		local pot = Props.part(model, Vector3.new(5, 4, 5), cf * CFrame.new(-8.5, 2.4, -9), Color3.fromRGB(45, 45, 50), Enum.Material.Metal, "Part")
		pot.Shape = Enum.PartType.Ball
		local brew = Props.part(model, Vector3.new(0.4, 4.2, 4.2), cf * CFrame.new(-8.5, 3.7, -9) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 255, 90), Enum.Material.Neon)
		brew.Shape = Enum.PartType.Cylinder
		brew.CastShadow = false
		Props.fire(brew, 3, Color3.fromRGB(110, 255, 90))
		Props.light(brew, Color3.fromRGB(120, 255, 100), 18, 1.6)
		for i = 0, 3 do
			local a = i / 4 * math.pi * 2
			Props.rock(model, (cf * CFrame.new(-8.5 + math.cos(a) * 3, 0.4, -9 + math.sin(a) * 3)).Position, 1.2, Color3.fromRGB(90, 90, 95))
		end
	elseif shopId == "Hatchery" then
		-- a warm straw nest of eggs on the counter, under heat lamps
		local nest = cf * CFrame.new(-5, 4.6, -3)
		local straw = Props.part(model, Vector3.new(0.8, 4.6, 4.6), nest * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(215, 185, 110), Enum.Material.Fabric)
		straw.Shape = Enum.PartType.Cylinder
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			Props.ellipsoid(model, Vector3.new(1.3, 1.8, 1.3), nest * CFrame.new(math.cos(a) * 1.1, 1.1, math.sin(a) * 1.1), ({ Color3.fromRGB(255, 150, 90), Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 220, 110) })[i], Enum.Material.SmoothPlastic)
		end
		local lamp = Props.part(model, Vector3.new(1.6, 0.8, 1.6), cf * CFrame.new(-5, 10.2, -3), Color3.fromRGB(255, 170, 90), Enum.Material.Neon)
		Props.light(lamp, Color3.fromRGB(255, 170, 100), 16, 1.5)
	end
end

local function buildStall(parent: Instance, shop)
	local style = SHOP_STYLE[shop.id]
	local model = Instance.new("Model")
	model.Name = shop.id
	local cf = facingCF(shop.position, shop.facing)

	Props.part(model, Vector3.new(22, 0.8, 16), cf * CFrame.new(0, 0.4, 2), Color3.fromRGB(150, 130, 110), Enum.Material.WoodPlanks)
	local counter = Props.part(model, Vector3.new(16, 3.6, 2.6), cf * CFrame.new(0, 2.2, -3), Props.WOOD, Enum.Material.WoodPlanks)
	Props.part(model, Vector3.new(16.6, 0.5, 3.2), cf * CFrame.new(0, 4.2, -3), Props.DARK_WOOD, Enum.Material.Wood)
	Props.part(model, Vector3.new(20, 15, 1), cf * CFrame.new(0, 7.5, 9.5), Color3.fromRGB(110, 80, 55), Enum.Material.WoodPlanks)
	-- Striped awning sloping from 12 studs high at the front (z = -6.5) to 15.4 at the back (z = 10).
	local frontZ, backZ, frontY, backY = -6.5, 10, 12.2, 15.4
	local slope = math.atan((backY - frontY) / (backZ - frontZ))
	local length = math.sqrt((backZ - frontZ) ^ 2 + (backY - frontY) ^ 2)
	local function awningUnderside(z)
		return frontY - 0.2 + (z - frontZ) / (backZ - frontZ) * (backY - frontY)
	end
	for i = 0, 7 do
		local color = i % 2 == 0 and style.awning or Color3.fromRGB(245, 235, 215)
		Props.part(model, Vector3.new(2.75, 0.4, length), cf * CFrame.new(-9.625 + i * 2.75, (frontY + backY) / 2, (frontZ + backZ) / 2) * CFrame.Angles(-slope, 0, 0), color, Enum.Material.Fabric)
	end
	for _, x in ipairs({ -10, 10 }) do
		for _, z in ipairs({ -5, 9 }) do
			Props.column(model, (cf * CFrame.new(x, 0, z)).Position, awningUnderside(z), 1, Props.DARK_WOOD, Enum.Material.Wood)
		end
	end
	stallGoods(model, cf, shop.id)

	-- name board hanging in front of the awning's lower edge
	local board = Props.part(model, Vector3.new(18, 2.6, 0.4), cf * CFrame.new(0, 13.3, -6.95), Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
	board.Name = "Sign"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 150)
	label.TextStrokeTransparency = 0.4
	label.Text = shop.name
	label.Parent = gui
	gui.Parent = board

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = shop.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	if shop.tab then
		prompt.ActionText = shop.tab == "Buy" and "Browse Gear" or (shop.tab == "Sell" and "Sell Gear & Food" or "Upgrade Gear")
		prompt:SetAttribute("ShopTab", shop.tab)
		prompt:SetAttribute("ShopName", shop.name)
		CollectionService:AddTag(prompt, "ShopPrompt")
	else
		prompt.ActionText = shop.panel == "Potions" and "Browse Potions" or "Buy Dragon Eggs"
		prompt:SetAttribute("Panel", shop.panel)
		CollectionService:AddTag(prompt, "PanelPrompt")
	end
	prompt.Parent = counter

	model.Parent = parent
	-- raised step behind the counter so the shopkeeper can see over it
	Props.part(model, Vector3.new(16, 1.6, 7), cf * CFrame.new(0, 1.6, 4.6), Color3.fromRGB(125, 95, 65), Enum.Material.WoodPlanks)
	-- turned a little to one side so the tail fits inside the stall
	local keeperFacing = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(28)) * shop.facing
	placeDragon(parent, style.keeper, (cf * CFrame.new(-1.5, 2.4, 1.6)).Position, keeperFacing, { scale = 0.42, name = shop.name .. " Keeper" })
end

local function buildQuestGivers(parent: Instance)
	for _, giverId in ipairs(Quests.GiverOrder) do
		local giver = Quests.Givers[giverId]
		local spot = Zones.QuestGivers[giverId]
		-- little platform
		Props.column(parent, spot.position - Vector3.new(0, 0.5, 0), 1.2, 22, Color3.fromRGB(170, 160, 150), Enum.Material.Cobblestone)
		local model = placeDragon(parent, giver.look, spot.position + Vector3.new(0, 0.7, 0), spot.facing, { scale = 1.05, name = giver.name })
		model:SetAttribute("GiverId", giverId)
		CollectionService:AddTag(model, "QuestGiver")

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"
		prompt.ObjectText = giver.name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 18
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("GiverId", giverId)
		prompt.Parent = model.PrimaryPart
		CollectionService:AddTag(prompt, "QuestPrompt")

		local gui = Instance.new("BillboardGui")
		gui.Name = "GiverName"
		gui.Size = UDim2.fromOffset(220, 44)
		gui.StudsOffset = Vector3.new(0, 7, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0.6, 0)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = Color3.fromRGB(255, 225, 120)
		name.TextStrokeTransparency = 0.3
		name.Text = giver.name
		name.Parent = gui
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromScale(0, 0.6)
		title.Size = UDim2.new(1, 0, 0.4, 0)
		title.Font = Enum.Font.GothamBold
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(220, 220, 230)
		title.TextStrokeTransparency = 0.5
		title.Text = "<" .. giver.title .. ">"
		title.Parent = gui
		gui.Parent = model:FindFirstChild("Head") or model.PrimaryPart
	end
end

local function buildWarHorn(parent: Instance)
	local pos = Zones.WarHorn
	local model = Instance.new("Model")
	model.Name = "WarHorn"
	Props.column(model, pos - Vector3.new(0, 0.5, 0), 1.5, 16, Color3.fromRGB(150, 140, 130), Enum.Material.Cobblestone)
	for _, x in ipairs({ -5, 5 }) do
		Props.column(model, pos + Vector3.new(x, 0.9, 0), 10, 1.2, Props.DARK_WOOD, Enum.Material.Wood)
	end
	Props.beam(model, pos + Vector3.new(-5.5, 10, 0), pos + Vector3.new(5.5, 10, 0), 1, Props.DARK_WOOD, Enum.Material.Wood)
	local ivory = Color3.fromRGB(240, 230, 200)
	local a, b, c, d = pos + Vector3.new(-4, 8, 0), pos + Vector3.new(-1, 6.2, 0), pos + Vector3.new(2.5, 6.6, 0), pos + Vector3.new(4.6, 8.8, 0)
	Props.beam(model, a, b, 0.7, ivory)
	Props.beam(model, b, c, 1.2, ivory)
	local bell = Props.beam(model, c, d, 2, ivory)
	Props.ellipsoid(model, Vector3.new(0.5, 2.4, 2.4), CFrame.new(d) * CFrame.Angles(0, 0, math.rad(40)), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	Props.banner(model, pos + Vector3.new(-8, 0.9, 2), Color3.fromRGB(190, 40, 40), Vector3.new(0, 0, 1))
	Props.banner(model, pos + Vector3.new(8, 0.9, 2), Color3.fromRGB(190, 40, 40), Vector3.new(0, 0, 1))
	Props.sign(model, CFrame.lookAt(pos + Vector3.new(0, 5.5, -11), pos + Vector3.new(0, 5.5, -30)), "📯 WAR HORN\nJoin boss fights here!", Vector2.new(10, 3.4))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WarHornPrompt"
	prompt.ActionText = "Join / Leave Boss Queue"
	prompt.ObjectText = "War Horn"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = bell
	model.Parent = parent
end

local function buildTraining(parent: Instance)
	local f = folder("Training", parent)
	local tr = Zones.Training
	for _, pos in ipairs(tr.dummies) do
		local dummy = Props.dummy(f, pos, Vector3.new(0, 0, -1))
		CollectionService:AddTag(dummy, "TrainingDummy")
	end
	Props.sign(f, CFrame.lookAt(Vector3.new(66, 5, 130), Vector3.new(0, 5, 130)), "🎯 TRAINING DUMMIES\nHit one to see your DPS!", Vector2.new(13, 4))

	-- Sparring pen: a fence with a red danger line inside. The golem throws at anyone in it.
	local pen = tr.pen
	local x0, x1, z0, z1 = pen.min.X, pen.max.X, pen.min.Z, pen.max.Z
	local gateHalf = 7
	local mx = (x0 + x1) / 2
	Props.fence(f, Vector3.new(x0, 0, z0), Vector3.new(mx - gateHalf, 0, z0), Color3.fromRGB(150, 60, 50))
	Props.fence(f, Vector3.new(mx + gateHalf, 0, z0), Vector3.new(x1, 0, z0), Color3.fromRGB(150, 60, 50))
	Props.fence(f, Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1), Color3.fromRGB(150, 60, 50))
	Props.fence(f, Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1), Color3.fromRGB(150, 60, 50))
	Props.fence(f, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1), Color3.fromRGB(150, 60, 50))
	for _, edge in ipairs({
		{ Vector3.new(mx, 0.1, z0 + 1.5), Vector3.new(x1 - x0 - 3, 0.2, 0.6) },
		{ Vector3.new(mx, 0.1, z1 - 1.5), Vector3.new(x1 - x0 - 3, 0.2, 0.6) },
		{ Vector3.new(x0 + 1.5, 0.1, (z0 + z1) / 2), Vector3.new(0.6, 0.2, z1 - z0 - 3) },
		{ Vector3.new(x1 - 1.5, 0.1, (z0 + z1) / 2), Vector3.new(0.6, 0.2, z1 - z0 - 3) },
	}) do
		local line = Props.part(f, edge[2], CFrame.new(edge[1]), Color3.fromRGB(255, 70, 50), Enum.Material.Neon)
		line.CanCollide = false
		line.Transparency = 0.3
		line.CastShadow = false
	end
	for _, x in ipairs({ mx - gateHalf - 1, mx + gateHalf + 1 }) do
		Props.torch(f, Vector3.new(x, 0, z0 - 1.5), Color3.fromRGB(255, 90, 60))
	end
	local golem = Props.golem(f, tr.golem, Vector3.new(0, 0, -1))
	CollectionService:AddTag(golem, "TrainingDummy")
	Props.sign(f, CFrame.lookAt(Vector3.new(66, 5, 176), Vector3.new(0, 5, 176)), "🥊 SPARRING PEN\nThe golem throws back!", Vector2.new(11, 4), Color3.fromRGB(255, 200, 190), Color3.fromRGB(90, 30, 30))
end

-- Target practice range (Zones.Range, RangeService): a sandy field behind the houses on the
-- west side of the main road, split into lanes by rope fences, with a firing mat at the east end
-- of each lane (a "Range" PanelPrompt opens the practice window) and hay bales at the far end.
local function buildRange(parent: Instance)
	local f = folder("Range", parent)
	local R = Zones.Range
	local z0, z1 = R.lanes[1] - R.laneHalf - 4, R.lanes[#R.lanes] + R.laneHalf + 4
	local xBack, xFront = R.backstop, R.matX + 8
	local rope = Color3.fromRGB(150, 110, 70)
	-- fences round the field and between the lanes (the mats' end stays open)
	for _, z in ipairs({ z0, z1 }) do
		Props.fence(f, Vector3.new(xFront, 0, z), Vector3.new(xBack, 0, z), rope)
	end
	for i = 1, #R.lanes - 1 do
		local z = (R.lanes[i] + R.lanes[i + 1]) / 2
		Props.fence(f, Vector3.new(R.matX - 7, 0, z), Vector3.new(xBack + 2, 0, z), rope)
	end
	-- hay bales in front of a tall plank wall catch stray fireballs
	Props.part(f, Vector3.new(1, 12, z1 - z0), CFrame.new(xBack - 1.5, 6, (z0 + z1) / 2), Props.DARK_WOOD, Enum.Material.WoodPlanks)
	for z = z0 + 3, z1 - 3, 6 do
		for row = 0, 1 do
			local bale = Props.part(f, Vector3.new(3.6, 3, 5.6), CFrame.new(xBack + 1, 1.5 + row * 3, z + row * 3 - 1.5) * CFrame.Angles(0, math.rad(row * 4 - 2), 0), Color3.fromRGB(220, 190, 110), Enum.Material.Fabric)
			bale.Name = "HayBale"
		end
	end
	for lane, z in ipairs(R.lanes) do
		-- the firing mat, with a glowing line along its front edge
		local mat = Props.part(f, Vector3.new(11, 0.6, 12), CFrame.new(R.matX, 0.3, z), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
		mat.Name = "FiringMat"
		local line = Props.part(f, Vector3.new(0.4, 0.2, 12), CFrame.new(R.matX - 5.3, 0.7, z), Color3.fromRGB(255, 200, 80), Enum.Material.Neon)
		line.CanCollide = false
		line.CastShadow = false
		-- lane number on a post beside the mat
		Props.column(f, Vector3.new(R.matX + 3, 0, z - 7), 7, 0.6, Props.DARK_WOOD, Enum.Material.Wood)
		local board = Props.part(f, Vector3.new(3.4, 2.6, 0.3), CFrame.lookAt(Vector3.new(R.matX + 3, 7.4, z - 7), Vector3.new(R.matX + 13, 7.4, z - 7)), Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 225, 150)
		label.Text = "Lane " .. lane
		label.Parent = gui
		gui.Parent = board
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Target Practice"
		prompt.ObjectText = "Lane " .. lane
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Panel", "Range")
		prompt:SetAttribute("Lane", lane)
		CollectionService:AddTag(prompt, "PanelPrompt")
		prompt.Parent = mat
	end
	-- a high sign behind the mats, readable from the main road through the gap between houses 2
	-- and 3 (z 178-196); dragons walk under it on their way over
	local signZ = 187
	Props.sign(f, CFrame.lookAt(Vector3.new(R.matX + 12, 14, signZ), Vector3.new(0, 14, signZ)), "🏹 TARGET PRACTICE\nFireball the moving targets!", Vector2.new(14, 4.4))
end

local function buildTown(map: Folder)
	local town = folder("Town", map)

	-- Plaza statue
	Props.column(town, Vector3.new(0, -0.5, 0), 5, 18, Color3.fromRGB(165, 160, 150), Enum.Material.Slate)
	Props.column(town, Vector3.new(0, 4.5, 0), 1, 14, Color3.fromRGB(140, 135, 125), Enum.Material.Slate)
	placeDragon(town, "Stormwing", Vector3.new(0, 5.5, 0), Vector3.new(0, 0, 1), {
		scale = 1.7, tint = Color3.fromRGB(175, 172, 165), material = Enum.Material.Slate, noParticles = true, name = "Founder Statue",
	})
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + math.pi / 8
		Props.lamp(town, Vector3.new(math.cos(a) * 44, 0, math.sin(a) * 44))
	end
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		Props.flowers(town, Vector3.new(math.cos(a) * 12, 0, math.sin(a) * 12), ({ Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 220, 90), Color3.fromRGB(170, 120, 255) })[i % 3 + 1])
	end

	for _, shop in ipairs(Zones.Shops) do
		buildStall(town, shop)
	end
	buildQuestGivers(town)
	buildWarHorn(town)
	buildTraining(town)
	buildRange(town)

	-- Dragon-sized houses (wide arched doors, tall walls, perch beams on the roofs)
	local walls = { Color3.fromRGB(235, 220, 190), Color3.fromRGB(215, 200, 230), Color3.fromRGB(200, 225, 210) }
	local roofs = { Color3.fromRGB(170, 70, 50), Color3.fromRGB(70, 90, 150), Color3.fromRGB(90, 130, 80) }
	local size = Zones.HouseSize
	for i, house in ipairs(Zones.Houses) do
		local model = Props.dragonHouse(town, facingCF(house.pos, house.facing), size.X, size.Z, size.Y, walls[i % 3 + 1], roofs[i % 3 + 1])
		model.Name = "House" .. i
	end

	-- Lamps along the main road
	for z = 60, 200, 35 do
		Props.lamp(town, Vector3.new(-12, 0, z))
		Props.lamp(town, Vector3.new(12, 0, z))
	end
	for z = -70, -180, -36 do
		Props.lamp(town, Vector3.new(-11, 0, z))
		Props.lamp(town, Vector3.new(11, 0, z))
	end

	-- Trees around the edges of town, leaving gaps for the paths out to the hunting grounds
	for x = -265, 265, 24 do
		if math.abs(x) > 64 then
			Props.tree(town, Vector3.new(x + rng:NextNumber(-4, 4), 0, 236 + rng:NextNumber(-3, 3)), rng:NextNumber(0.8, 1.2), "oak")
		end
		if math.abs(x) > 110 then
			Props.tree(town, Vector3.new(x + rng:NextNumber(-4, 4), 0, -345 + rng:NextNumber(-4, 4)), rng:NextNumber(0.8, 1.3), "pine")
		end
	end
	for z = -330, 220, 26 do
		if math.abs(z) > 16 then
			Props.tree(town, Vector3.new(-268 + rng:NextNumber(-4, 4), 0, z), rng:NextNumber(0.8, 1.2), z % 2 == 0 and "pine" or "oak")
			Props.tree(town, Vector3.new(268 + rng:NextNumber(-4, 4), 0, z), rng:NextNumber(0.8, 1.2), z % 2 == 0 and "oak" or "pine")
		end
	end
	for _, p in ipairs({ Vector3.new(-80, 0, 60), Vector3.new(-100, 0, -80), Vector3.new(100, 0, -80), Vector3.new(118, 0, 60) }) do
		Props.tree(town, p, 1.1, "oak")
		Props.bush(town, p + Vector3.new(6, 0, 4))
	end

	-- Bridge over the river
	local bridge = folder("Bridge", town)
	Props.part(bridge, Vector3.new(18, 1.2, 80), CFrame.new(0, 0.4, 276), Color3.fromRGB(130, 95, 60), Enum.Material.WoodPlanks)
	for z = 244, 308, 16 do
		for _, x in ipairs({ -8, 8 }) do
			Props.column(bridge, Vector3.new(x, -12, z), 16, 1.6, Props.DARK_WOOD, Enum.Material.Wood)
		end
	end
	Props.fence(bridge, Vector3.new(-8.5, 1, 238), Vector3.new(-8.5, 1, 314))
	Props.fence(bridge, Vector3.new(8.5, 1, 238), Vector3.new(8.5, 1, 314))
	-- Welcome arch where the road meets the bridge. Each face has its own text.
	local archZ = 234
	for _, x in ipairs({ -14, 14 }) do
		Props.column(town, Vector3.new(x, 0, archZ), 13, 3.2, Color3.fromRGB(150, 145, 140), Enum.Material.Slate)
		local flame = Props.part(town, Vector3.new(1.4, 1.4, 1.4), CFrame.new(x, 17.3, archZ), Color3.fromRGB(255, 160, 60), Enum.Material.Neon)
		Props.fire(flame, 3)
		Props.light(flame, Color3.fromRGB(255, 170, 90), 20, 1.5)
	end
	local arch = Props.part(town, Vector3.new(31.5, 3.6, 1.2), CFrame.new(0, 14.8, archZ), Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
	arch.Name = "Sign"
	for face, text in pairs({
		[Enum.NormalId.Front] = "⚠️ Viking Lands ahead  •  Raider Camp Lv 1-4",
		[Enum.NormalId.Back] = "🐉 Welcome to Dragon Town  •  safe from vikings",
	}) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 225, 150)
		label.TextStrokeTransparency = 0.4
		label.Text = text
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.PaddingLeft = UDim.new(0.03, 0)
		pad.PaddingRight = UDim.new(0.03, 0)
		pad.Parent = label
		label.Parent = gui
		gui.Parent = arch
	end
end

---------------------------------------------------------------- player bases

local function buildBotDock(model: Model, cf: CFrame)
	local dock = Props.part(model, Vector3.new(10, 1, 8), cf * CFrame.new(0, 0.5, 0), Color3.fromRGB(120, 125, 135), Enum.Material.DiamondPlate)
	dock.Name = "BotDock"
	for _, x in ipairs({ -3, 3 }) do
		local pad = Props.part(model, Vector3.new(0.3, 3.4, 3.4), cf * CFrame.new(x, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 200, 255), Enum.Material.Neon)
		pad.Shape = Enum.PartType.Cylinder
		pad.CastShadow = false
	end
	Props.part(model, Vector3.new(0.6, 5, 0.6), cf * CFrame.new(-4.6, 3, 3.6), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
	Props.part(model, Vector3.new(0.6, 5, 0.6), cf * CFrame.new(4.6, 3, 3.6), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
	local board = Props.part(model, Vector3.new(10, 2.2, 0.4), cf * CFrame.new(0, 5.2, 3.6), Color3.fromRGB(60, 65, 80), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- toward the road and the village
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(150, 230, 255)
	label.Text = "🤖 Bot Dock"
	label.Parent = gui
	gui.Parent = board
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Robot Workshop"
	prompt.ObjectText = "Bot Dock"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = dock
end

local function buildBases(map: Folder)
	local basesFolder = folder("Bases", map)
	local eggColors = { Color3.fromRGB(255, 120, 80), Color3.fromRGB(120, 200, 255), Color3.fromRGB(190, 120, 255), Color3.fromRGB(140, 230, 120) }
	for _, info in ipairs(Zones.Bases) do
		local model = Instance.new("Model")
		model.Name = "Base" .. info.index
		model:SetAttribute("BaseIndex", info.index)
		model:SetAttribute("OwnerUserId", 0)
		CollectionService:AddTag(model, "PlayerBase")
		local cf = facingCF(info.center, info.facing)
		local depth, width = Zones.BaseSize.X, Zones.BaseSize.Z

		Props.part(model, Vector3.new(width, 1, depth), cf * CFrame.new(0, -0.3, 0), Color3.fromRGB(100, 155, 75), Enum.Material.Grass)
		-- fence with an opening at the front
		local hw, hd = width / 2, depth / 2
		local function L(x, z)
			return (cf * CFrame.new(x, 0.2, z)).Position
		end
		Props.fence(model, L(-hw, -hd), L(-hw, hd))
		Props.fence(model, L(hw, -hd), L(hw, hd))
		Props.fence(model, L(-hw, hd), L(hw, hd))
		Props.fence(model, L(-hw, -hd), L(-10, -hd))
		Props.fence(model, L(10, -hd), L(hw, -hd))

		-- nest with eggs at the back
		local nest = L(0, hd - 11)
		Props.column(model, nest - Vector3.new(0, 0.2, 0), 1.2, 16, Color3.fromRGB(200, 170, 100), Enum.Material.Fabric)
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			Props.rock(model, nest + Vector3.new(math.cos(a) * 8, 0.8, math.sin(a) * 8), 2.6, Color3.fromRGB(140, 130, 120))
		end
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			Props.ellipsoid(model, Vector3.new(2, 2.8, 2), CFrame.new(nest + Vector3.new(math.cos(a) * 2, 2.1, math.sin(a) * 2)), eggColors[(info.index + i) % 4 + 1], Enum.Material.SmoothPlastic)
		end

		-- planting spots, spaced out so it's always clear which one you're standing at
		local plots = folder("Plots", model)
		local index = 0
		for _, z in ipairs({ -20, -2, 16 }) do
			for _, x in ipairs({ -27, -9, 9, 27 }) do
				index += 1
				if index <= Game.MAX_PLOTS then
					local plot = Props.part(plots, Vector3.new(8, 1, 8), cf * CFrame.new(x, 0.2, z), Color3.fromRGB(96, 66, 42), Enum.Material.Ground)
					plot.Name = "Plot" .. index
					plot:SetAttribute("PlotIndex", index)
				end
			end
		end

		local sign = Props.sign(model, cf * CFrame.new(0, 5, -hd - 1), "🏠 Empty Lair", Vector2.new(14, 3.6))
		sign.Name = "Sign"

		buildBotDock(model, cf * CFrame.new(-hw + 11, 0, -hd + 11))

		local home = invisibleWall(model, Vector3.new(2, 1, 2), CFrame.lookAt(L(0, -hd + 10) + Vector3.new(0, 1, 0), nest + Vector3.new(0, 1, 0)))
		home.Name = "HomeSpawn"
		home.CanCollide = false

		Props.lamp(model, L(-12, -hd + 2))
		Props.lamp(model, L(12, -hd + 2))
		Props.tree(model, L(-hw + 7, hd - 7), 1, "oak")
		Props.tree(model, L(hw - 7, hd - 7), 1, "oak")
		model.Parent = basesFolder
	end
end

---------------------------------------------------------------- battle zone

local function buildBattleZone(map: Folder)
	local bz = folder("BattleZone", map)
	local area = Zones.getArea("BattleZone")
	local min, max = area.min, area.max
	local cx, cz = (min.X + max.X) / 2, (min.Z + max.Z) / 2
	local red = Color3.fromRGB(190, 40, 40)

	Props.stoneWall(bz, Vector3.new(min.X, 0, min.Z), Vector3.new(max.X, 0, min.Z), 6, 3)
	Props.stoneWall(bz, Vector3.new(min.X, 0, min.Z), Vector3.new(min.X, 0, max.Z), 6, 3)
	Props.stoneWall(bz, Vector3.new(max.X, 0, min.Z), Vector3.new(max.X, 0, max.Z), 6, 3)
	Props.stoneWall(bz, Vector3.new(min.X, 0, max.Z), Vector3.new(-16, 0, max.Z), 6, 3)
	Props.stoneWall(bz, Vector3.new(16, 0, max.Z), Vector3.new(max.X, 0, max.Z), 6, 3)
	local line = Props.part(bz, Vector3.new(32, 0.2, 1.2), CFrame.new(0, 0.15, max.Z), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	line.CanCollide = false

	-- corner banners stand well inside the walls, with a torch toward the middle
	for _, spot in ipairs({
		{ Vector3.new(min.X + 9, 0, min.Z + 9), Vector3.new(1, 0, 1) },
		{ Vector3.new(max.X - 9, 0, min.Z + 9), Vector3.new(-1, 0, 1) },
		{ Vector3.new(min.X + 9, 0, max.Z - 9), Vector3.new(1, 0, -1) },
		{ Vector3.new(max.X - 9, 0, max.Z - 9), Vector3.new(-1, 0, -1) },
	}) do
		Props.banner(bz, spot[1], red, spot[2])
		Props.torch(bz, spot[1] + spot[2].Unit * 4, Color3.fromRGB(255, 90, 60))
	end
	-- the entrance gap (x = -16..16) gets torches and banners just outside the wall
	for _, x in ipairs({ -1, 1 }) do
		Props.torch(bz, Vector3.new(19 * x, 0, max.Z + 4), Color3.fromRGB(255, 90, 60))
		Props.banner(bz, Vector3.new(26 * x, 0, max.Z + 4), red, Vector3.new(0, 0, 1))
	end

	-- cover to fight around
	for _, p in ipairs({ Vector3.new(cx - 45, 0, cz - 25), Vector3.new(cx + 45, 0, cz - 25), Vector3.new(cx - 45, 0, cz + 25), Vector3.new(cx + 45, 0, cz + 25), Vector3.new(cx, 0, cz - 45) }) do
		Props.column(bz, p, 14, 7, Color3.fromRGB(150, 140, 130), Enum.Material.Slate)
		Props.column(bz, p + Vector3.new(0, 14, 0), 1.2, 9, Color3.fromRGB(120, 110, 105), Enum.Material.Slate)
	end
	for _ = 1, 8 do
		Props.rock(bz, Vector3.new(rng:NextNumber(min.X + 15, max.X - 15), 1, rng:NextNumber(min.Z + 15, max.Z - 15)), rng:NextNumber(4, 8), Color3.fromRGB(150, 130, 110))
	end
	-- center emblem
	local emblem = Props.column(bz, Vector3.new(cx, 0.05, cz), 0.2, 26, Color3.fromRGB(200, 60, 50), Enum.Material.Neon)
	emblem.CanCollide = false
	emblem.Transparency = 0.5

	Props.sign(bz, CFrame.lookAt(Vector3.new(-44, 5, max.Z + 7), Vector3.new(-44, 5, max.Z + 40)), "⚔️ BATTLE ZONE ⚔️\nPvP: dragons can fight here!", Vector2.new(16, 5), Color3.fromRGB(255, 200, 190), Color3.fromRGB(90, 30, 30))
end

---------------------------------------------------------------- viking lands scenery

local function buildVikingLands(map: Folder)
	local vl = folder("VikingLands", map)
	Camps.build(vl)

	-- Scattered pines and rocks between the camps
	local scenery = folder("Scenery", vl)
	local placed = 0
	for _ = 1, 500 do
		if placed >= 170 then
			break
		end
		local p = Vector3.new(rng:NextNumber(-530, 530), 0, rng:NextNumber(330, 1090))
		if not nearCamp(p, 45) and not nearPath(p, 6) and not Wilds.inAnyLake(p, 10) and not Wilds.inRiver(p, 10) then
			placed += 1
			local ground = Vector3.new(p.X, Props.groundY(p.X, p.Z), p.Z)
			if rng:NextNumber() < 0.75 then
				Props.tree(scenery, ground, rng:NextNumber(0.9, 1.6), rng:NextNumber() < 0.6 and "snowpine" or "pine")
			else
				Props.rock(scenery, ground + Vector3.new(0, 1, 0), rng:NextNumber(4, 11))
			end
		end
	end
end

---------------------------------------------------------------- boss arena

local function buildBossArena(map: Folder, barriers: Folder)
	local arena = folder("BossArena", map)
	local c = Zones.BossArena.center
	local r = Zones.BossArena.radius
	local h = Zones.BossArena.wallHeight

	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * (r - 6), 0, math.sin(a) * (r - 6))
		Props.column(arena, p, 28, 6, Color3.fromRGB(70, 65, 70), Enum.Material.Basalt)
		local top = Props.part(arena, Vector3.new(3, 1.5, 3), CFrame.new(p + Vector3.new(0, 29, 0)), Color3.fromRGB(255, 110, 40), Enum.Material.Neon)
		Props.fire(top, 7)
		Props.light(top, Color3.fromRGB(255, 130, 60), 40, 2)
	end
	for i = 1, 32 do
		local a = (i / 32) * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 60, 0.1, math.sin(a) * 60)
		local rune = Props.part(arena, Vector3.new(4, 0.2, 1.2), CFrame.lookAt(p, c) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 80, 60), Enum.Material.Neon)
		rune.CanCollide = false
		rune.Transparency = 0.3
	end
	-- Invisible walls and ceiling that keep the fight inside the arena.
	local segments = 32
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * (r + 2), h / 2, math.sin(a) * (r + 2))
		local wall = Props.part(barriers, Vector3.new(2 * math.pi * (r + 2) / segments + 2, h, 2), CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)), Color3.fromRGB(255, 70, 50), Enum.Material.ForceField)
		wall.Transparency = 0.6
		wall.CanQuery = false
		wall.CastShadow = false
	end
	invisibleWall(barriers, Vector3.new(r * 2 + 40, 2, r * 2 + 40), CFrame.new(c + Vector3.new(0, h + 1, 0)))
	for _, off in ipairs({ Vector3.new(-40, 0, -85), Vector3.new(40, 0, -85), Vector3.new(-40, 0, 85), Vector3.new(40, 0, 85) }) do
		Props.banner(arena, c + off, Color3.fromRGB(150, 20, 20), Vector3.new(0, 0, -off.Z))
	end
end

---------------------------------------------------------------- world bounds

local function buildBounds(barriers: Folder)
	local bounds = folder("Bounds", barriers)
	local b = Zones.WorldBounds
	local cx, cz = (b.min.X + b.max.X) / 2, (b.min.Z + b.max.Z) / 2
	local w, d = b.max.X - b.min.X, b.max.Z - b.min.Z
	local h = 400
	invisibleWall(bounds, Vector3.new(4, h, d), CFrame.new(b.min.X, h / 2 - 50, cz))
	invisibleWall(bounds, Vector3.new(4, h, d), CFrame.new(b.max.X, h / 2 - 50, cz))
	invisibleWall(bounds, Vector3.new(w, h, 4), CFrame.new(cx, h / 2 - 50, b.min.Z))
	invisibleWall(bounds, Vector3.new(w, h, 4), CFrame.new(cx, h / 2 - 50, b.max.Z))
end

function WorldBuilder.build()
	local map = Instance.new("Folder")
	map.Name = "Map"
	setupLighting()
	buildTerrain()
	buildTown(map)
	buildBases(map)
	buildBattleZone(map)
	buildVikingLands(map)
	Wilds.build(map)
	local barriers = Instance.new("Folder")
	barriers.Name = "Barriers"
	buildBossArena(map, barriers)
	buildBounds(barriers)
	barriers.Parent = workspace
	map.Parent = workspace
end

return WorldBuilder
