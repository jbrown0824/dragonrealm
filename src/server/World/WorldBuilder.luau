-- Generates the whole map at server start: terrain, Dragon Town (plaza, shops, quest givers,
-- player bases, Battle Zone), the Viking Lands camps, and the Boss Arena.
-- Positions come from Config/Zones so gameplay and scenery always line up.
--
-- Want to hand-build the map in Studio instead? Keep the tags/attributes this file sets
-- (PlayerBase, ShopPrompt, QuestPrompt, WarHornPrompt, Plots/Plot1..12, HomeSpawn, Sign)
-- and the services will keep working.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Quests = require(Shared.Config.Quests)
local Game = require(Shared.Config.Game)
local DragonBuilder = require(Shared.DragonBuilder)

local Props = require(script.Parent.Props)

local WorldBuilder = {}

local terrain = workspace.Terrain
local rng = Random.new(20260926)

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function facingCF(pos: Vector3, facing: Vector3): CFrame
	local dir = Vector3.new(facing.X, 0, facing.Z)
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(pos, pos + dir.Unit)
end

local function terrainPath(a: Vector3, b: Vector3, width: number, material: Enum.Material)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(Vector3.new(mid.X, -2, mid.Z), Vector3.new(b.X, -2, b.Z))
	terrain:FillBlock(cf, Vector3.new(width, 4, len + width), material)
end

local function invisibleWall(parent: Instance, size: Vector3, cf: CFrame)
	local p = Props.part(parent, size, cf, Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- A decorative / NPC dragon standing on the ground at `pos`.
local function placeDragon(parent: Instance, classId: string, pos: Vector3, facing: Vector3, options)
	options = options or {}
	options.anchored = true
	local model, hipHeight = DragonBuilder.build(classId, options)
	local root = model.PrimaryPart
	local height = hipHeight + root.Size.Y / 2
	model:PivotTo(facingCF(pos + Vector3.new(0, height, 0), facing))
	model.Parent = parent
	if not options.tint then
		CollectionService:AddTag(model, "Dragon") -- clients animate wings/tail (statues stay still)
	end
	return model
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

	-- River between town and the viking lands, with sandy banks.
	terrain:FillBlock(CFrame.new(0, -4, 276), Vector3.new(1320, 16, 48), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(0, -10, 276), Vector3.new(1320, 12, 48), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -3, 248), Vector3.new(1320, 6, 8), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -3, 304), Vector3.new(1320, 6, 8), Enum.Material.Sand)

	-- Town roads and plaza
	terrain:FillCylinder(CFrame.new(0, -2, 0), 4, 50, Enum.Material.Cobblestone)
	terrainPath(Vector3.new(0, 0, 40), Vector3.new(0, 0, 244), 18, Enum.Material.Cobblestone)
	terrainPath(Vector3.new(0, 0, -40), Vector3.new(0, 0, -196), 16, Enum.Material.Cobblestone)
	terrainPath(Vector3.new(-140, 0, 0), Vector3.new(140, 0, 0), 14, Enum.Material.Cobblestone)
	terrainPath(Vector3.new(-140, 0, -225), Vector3.new(-140, 0, 225), 12, Enum.Material.Cobblestone)
	terrainPath(Vector3.new(140, 0, -225), Vector3.new(140, 0, 225), 12, Enum.Material.Cobblestone)

	-- Battle Zone floor
	terrain:FillBlock(CFrame.new(0, -2, -265), Vector3.new(190, 4, 140), Enum.Material.Sand)

	-- Viking lands: colder, muddier ground
	terrain:FillBlock(CFrame.new(0, -2, 710), Vector3.new(1320, 4, 800), Enum.Material.LeafyGrass)
	terrainPath(Vector3.new(0, 0, 305), Vector3.new(0, 0, 400), 14, Enum.Material.Mud)
	terrainPath(Vector3.new(0, 0, 440), Vector3.new(-280, 0, 570), 12, Enum.Material.Mud)
	terrainPath(Vector3.new(0, 0, 440), Vector3.new(280, 0, 610), 12, Enum.Material.Mud)
	terrainPath(Vector3.new(0, 0, 440), Vector3.new(0, 0, 840), 14, Enum.Material.Mud)
	for _ = 1, 60 do
		local p = Vector3.new(rng:NextNumber(-540, 540), -7, rng:NextNumber(320, 1100))
		local clear = math.abs(p.X) > 26
		for _, camp in ipairs(Zones.Camps) do
			if (Vector3.new(p.X, 0, p.Z) - camp.center).Magnitude < camp.radius + 30 then
				clear = false
			end
		end
		if clear then
			terrain:FillBall(p, rng:NextNumber(9, 18), Enum.Material.Snow)
		end
	end

	-- Fishing village pond
	terrain:FillBlock(CFrame.new(-440, -4, 590), Vector3.new(110, 16, 190), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(-440, -10, 590), Vector3.new(110, 12, 190), Enum.Material.Water)

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

local function buildStall(parent: Instance, shop, keeperClass: string, awningColor: Color3)
	local model = Instance.new("Model")
	model.Name = shop.id
	local cf = facingCF(shop.position, shop.facing)

	Props.part(model, Vector3.new(22, 0.8, 16), cf * CFrame.new(0, 0.4, 2), Color3.fromRGB(150, 130, 110), Enum.Material.WoodPlanks)
	local counter = Props.part(model, Vector3.new(16, 3.6, 2.6), cf * CFrame.new(0, 2.2, -3), Props.WOOD, Enum.Material.WoodPlanks)
	Props.part(model, Vector3.new(16.6, 0.5, 3.2), cf * CFrame.new(0, 4.2, -3), Props.DARK_WOOD, Enum.Material.Wood)
	Props.part(model, Vector3.new(20, 12, 1), cf * CFrame.new(0, 6.4, 9.5), Color3.fromRGB(110, 80, 55), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -10, 10 }) do
		for _, z in ipairs({ -5, 9 }) do
			Props.column(model, (cf * CFrame.new(x, 0, z)).Position, 13, 1, Props.DARK_WOOD, Enum.Material.Wood)
		end
	end
	-- striped awning
	for i = 0, 7 do
		local color = i % 2 == 0 and awningColor or Color3.fromRGB(245, 235, 215)
		Props.part(model, Vector3.new(2.75, 0.4, 16), cf * CFrame.new(-9.6 + i * 2.75, 13.4, 2) * CFrame.Angles(math.rad(-12), 0, 0), color, Enum.Material.Fabric)
	end
	-- shelves with goods
	for row = 0, 1 do
		Props.part(model, Vector3.new(16, 0.4, 2), cf * CFrame.new(0, 5 + row * 3, 8.5), Props.DARK_WOOD, Enum.Material.Wood)
		for i = -3, 3 do
			local color = ({ Color3.fromRGB(200, 60, 60), Color3.fromRGB(80, 160, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(180, 90, 255) })[(i + row) % 4 + 1]
			Props.ellipsoid(model, Vector3.new(1.2, 1.4, 1.2), cf * CFrame.new(i * 2, 5.9 + row * 3, 8.5), color, Enum.Material.Glass)
		end
	end

	-- name board hanging from the front of the awning
	local board = Props.part(model, Vector3.new(18, 3.4, 0.5), cf * CFrame.new(0, 16.2, -5.2), Color3.fromRGB(95, 65, 40), Enum.Material.Wood)
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
	prompt.ActionText = shop.tab == "Buy" and "Browse Gear" or (shop.tab == "Sell" and "Sell Gear" or "Upgrade Gear")
	prompt.ObjectText = shop.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopTab", shop.tab)
	prompt:SetAttribute("ShopName", shop.name)
	prompt.Parent = counter
	CollectionService:AddTag(prompt, "ShopPrompt")

	if shop.id == "Forge" then
		Props.part(model, Vector3.new(5, 4, 4), cf * CFrame.new(7, 2, 5), Color3.fromRGB(90, 85, 85), Enum.Material.Slate)
		local glow = Props.part(model, Vector3.new(3, 0.6, 2.6), cf * CFrame.new(7, 4.2, 5), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		Props.fire(glow, 4)
		Props.light(glow, Color3.fromRGB(255, 140, 60), 20, 2)
		Props.part(model, Vector3.new(3, 1.2, 1.4), cf * CFrame.new(-6, 4.9, -3), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	end

	model.Parent = parent
	placeDragon(parent, keeperClass, (cf * CFrame.new(0, 0.8, 3.5)).Position, shop.facing, { scale = 0.6, name = shop.name .. " Keeper" })
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
	Props.sign(model, CFrame.lookAt(pos + Vector3.new(0, 3.2, -7.5), pos + Vector3.new(0, 3.2, -20)), "📯 WAR HORN\nJoin boss fights here!", Vector2.new(11, 4))

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
	Props.sign(town, CFrame.lookAt(Vector3.new(-24, 3.5, 54), Vector3.new(0, 3.5, 32)), "🐉 Welcome to Dragon Town!", Vector2.new(16, 3.5))

	-- Shops
	local keepers = { Armory = "Stormwing", Exchange = "Shadowstalker", Forge = "Behemoth" }
	local awnings = { Armory = Color3.fromRGB(190, 50, 50), Exchange = Color3.fromRGB(200, 160, 40), Forge = Color3.fromRGB(60, 90, 170) }
	for _, shop in ipairs(Zones.Shops) do
		buildStall(town, shop, keepers[shop.id], awnings[shop.id])
	end

	buildQuestGivers(town)
	buildWarHorn(town)

	-- Houses
	local houseSpots = {
		{ Vector3.new(-42, 0, 100), Vector3.new(1, 0, 0) },
		{ Vector3.new(-42, 0, 150), Vector3.new(1, 0, 0) },
		{ Vector3.new(-42, 0, 200), Vector3.new(1, 0, 0) },
		{ Vector3.new(42, 0, 100), Vector3.new(-1, 0, 0) },
		{ Vector3.new(42, 0, 150), Vector3.new(-1, 0, 0) },
		{ Vector3.new(42, 0, 200), Vector3.new(-1, 0, 0) },
		{ Vector3.new(-70, 0, -150), Vector3.new(1, 0, 0) },
		{ Vector3.new(105, 0, -130), Vector3.new(-1, 0, 0) },
		{ Vector3.new(-95, 0, 100), Vector3.new(0, 0, -1) },
		{ Vector3.new(95, 0, 100), Vector3.new(0, 0, -1) },
	}
	local walls = { Color3.fromRGB(235, 220, 190), Color3.fromRGB(215, 200, 230), Color3.fromRGB(200, 225, 210) }
	local roofs = { Color3.fromRGB(170, 70, 50), Color3.fromRGB(70, 90, 150), Color3.fromRGB(90, 130, 80) }
	for i, spot in ipairs(houseSpots) do
		Props.house(town, facingCF(spot[1], spot[2]), 20, 16, 10, walls[i % 3 + 1], roofs[i % 3 + 1])
	end

	-- Lamps along the main road
	for z = 60, 230, 34 do
		Props.lamp(town, Vector3.new(-12, 0, z))
		Props.lamp(town, Vector3.new(12, 0, z))
	end
	for z = -70, -180, -36 do
		Props.lamp(town, Vector3.new(-11, 0, z))
		Props.lamp(town, Vector3.new(11, 0, z))
	end

	-- Trees around the edges of town
	for x = -265, 265, 24 do
		if math.abs(x) > 22 then
			Props.tree(town, Vector3.new(x + rng:NextNumber(-4, 4), 0, 236 + rng:NextNumber(-3, 3)), rng:NextNumber(0.8, 1.2), "oak")
		end
		if math.abs(x) > 110 then
			Props.tree(town, Vector3.new(x + rng:NextNumber(-4, 4), 0, -345 + rng:NextNumber(-4, 4)), rng:NextNumber(0.8, 1.3), "pine")
		end
	end
	for z = -330, 220, 26 do
		Props.tree(town, Vector3.new(-268 + rng:NextNumber(-4, 4), 0, z), rng:NextNumber(0.8, 1.2), z % 2 == 0 and "pine" or "oak")
		Props.tree(town, Vector3.new(268 + rng:NextNumber(-4, 4), 0, z), rng:NextNumber(0.8, 1.2), z % 2 == 0 and "oak" or "pine")
	end
	for _, p in ipairs({ Vector3.new(-80, 0, 60), Vector3.new(80, 0, 60), Vector3.new(-100, 0, -80), Vector3.new(100, 0, -80), Vector3.new(-60, 0, 140), Vector3.new(70, 0, 200) }) do
		Props.tree(town, p, 1.1, "oak")
		Props.bush(town, p + Vector3.new(6, 0, 4))
	end

	-- Bridge over the river
	local bridge = folder("Bridge", town)
	Props.part(bridge, Vector3.new(18, 1.2, 80), CFrame.new(0, 0.4, 276), Color3.fromRGB(130, 95, 60), Enum.Material.WoodPlanks)
	for z = 244, 308, 16 do
		for _, x in ipairs({ -8, 8 }) do
			Props.column(bridge, Vector3.new(x, -10, z), 14, 1.6, Props.DARK_WOOD, Enum.Material.Wood)
		end
	end
	Props.fence(bridge, Vector3.new(-8.5, 1, 238), Vector3.new(-8.5, 1, 314))
	Props.fence(bridge, Vector3.new(8.5, 1, 238), Vector3.new(8.5, 1, 314))
	Props.sign(town, CFrame.lookAt(Vector3.new(16, 3.5, 236), Vector3.new(16, 3.5, 200)), "⚠️ Viking Lands ahead!\nRaider Camp: Lv 1-4", Vector2.new(12, 4.5))
	Props.sign(town, CFrame.lookAt(Vector3.new(-16, 3.5, 318), Vector3.new(-16, 3.5, 360)), "🐉 Dragon Town\n(safe from vikings)", Vector2.new(12, 4.5))
end

---------------------------------------------------------------- player bases

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
		local width, depth = 92, 76

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

		-- nest with eggs
		local nest = L(0, 25)
		Props.column(model, nest - Vector3.new(0, 0.2, 0), 1.2, 16, Color3.fromRGB(200, 170, 100), Enum.Material.Fabric)
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			Props.rock(model, nest + Vector3.new(math.cos(a) * 8, 0.8, math.sin(a) * 8), 2.6, Color3.fromRGB(140, 130, 120))
		end
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			Props.ellipsoid(model, Vector3.new(2, 2.8, 2), CFrame.new(nest + Vector3.new(math.cos(a) * 2, 2.1, math.sin(a) * 2)), eggColors[(info.index + i) % 4 + 1], Enum.Material.SmoothPlastic)
		end

		-- planting spots
		local plots = folder("Plots", model)
		local index = 0
		for _, z in ipairs({ -14, 0, 14 }) do
			for _, x in ipairs({ -21, -7, 7, 21 }) do
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

		local home = invisibleWall(model, Vector3.new(2, 1, 2), CFrame.lookAt(L(0, -27) + Vector3.new(0, 1, 0), nest + Vector3.new(0, 1, 0)))
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

	for _, p in ipairs({ Vector3.new(min.X + 4, 0, min.Z + 4), Vector3.new(max.X - 4, 0, min.Z + 4), Vector3.new(min.X + 4, 0, max.Z - 4), Vector3.new(max.X - 4, 0, max.Z - 4), Vector3.new(-20, 0, max.Z + 2), Vector3.new(20, 0, max.Z + 2) }) do
		Props.banner(bz, p, red, Vector3.new(0, 0, 1))
		Props.torch(bz, p + Vector3.new(0, 0, -3), Color3.fromRGB(255, 90, 60))
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

	Props.sign(bz, CFrame.lookAt(Vector3.new(-26, 4, max.Z + 6), Vector3.new(-26, 4, max.Z + 40)), "⚔️ BATTLE ZONE ⚔️\nPvP: dragons can fight here!", Vector2.new(16, 5), Color3.fromRGB(255, 200, 190), Color3.fromRGB(90, 30, 30))
end

---------------------------------------------------------------- viking lands

local function scatterCamp(parent: Instance, center: Vector3, count: number, radius: number, fn)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = radius * rng:NextNumber(0.85, 1.1)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		fn(p, a)
	end
end

local function buildVikingLands(map: Folder)
	local vl = folder("VikingLands", map)
	local camps = {}
	for _, camp in ipairs(Zones.Camps) do
		camps[camp.id] = camp
	end

	-- Raider Camp
	do
		local f = folder("RaiderCamp", vl)
		local c = camps.RaiderCamp.center
		local colors = { Color3.fromRGB(170, 60, 50), Color3.fromRGB(200, 180, 140), Color3.fromRGB(120, 90, 60) }
		scatterCamp(f, c, 7, 38, function(p, a)
			Props.tent(f, facingCF(p, c - p), colors[rng:NextInteger(1, #colors)])
		end)
		Props.campfire(f, c + Vector3.new(-8, 0, 4))
		Props.campfire(f, c + Vector3.new(14, 0, -10))
		for _ = 1, 8 do
			local p = c + Vector3.new(rng:NextNumber(-45, 45), 0, rng:NextNumber(-45, 45))
			if rng:NextNumber() < 0.5 then
				Props.crate(f, p)
			else
				Props.barrel(f, p)
			end
		end
		Props.banner(f, c + Vector3.new(0, 0, -30), Color3.fromRGB(170, 30, 30), Vector3.new(0, 0, -1))
		Props.palisade(f, c + Vector3.new(-60, 0, 20), c + Vector3.new(-30, 0, 55))
		Props.palisade(f, c + Vector3.new(30, 0, 55), c + Vector3.new(60, 0, 20))
		Props.palisade(f, c + Vector3.new(-30, 0, 55), c + Vector3.new(30, 0, 55))
		Props.sign(f, CFrame.lookAt(c + Vector3.new(18, 3.5, -72), c + Vector3.new(18, 3.5, -120)), "Raider Camp\nLevel 1 - 4", Vector2.new(10, 4))
	end

	-- Fishing Village
	do
		local f = folder("FishingVillage", vl)
		local c = camps.FishingVillage.center
		for _, off in ipairs({ Vector3.new(-30, 0, -40), Vector3.new(10, 0, -50), Vector3.new(40, 0, -20), Vector3.new(35, 0, 30), Vector3.new(-10, 0, 45), Vector3.new(-45, 0, 25) }) do
			local p = c + off
			Props.hut(f, facingCF(p, c - p))
		end
		Props.campfire(f, c)
		Props.longship(f, CFrame.new(-445, -1.5, 560) * CFrame.Angles(0, math.rad(10), 0))
		Props.longship(f, CFrame.new(-430, -1.5, 640) * CFrame.Angles(0, math.rad(-15), 0))
		-- docks
		for _, z in ipairs({ 545, 615 }) do
			Props.part(f, Vector3.new(40, 1, 6), CFrame.new(-395, 0.6, z), Color3.fromRGB(130, 95, 60), Enum.Material.WoodPlanks)
			for x = -410, -380, 10 do
				Props.column(f, Vector3.new(x, -8, z + 3), 9, 1, Props.DARK_WOOD, Enum.Material.Wood)
			end
		end
		-- fish drying racks
		for _, p in ipairs({ c + Vector3.new(-20, 0, 10), c + Vector3.new(20, 0, 5) }) do
			Props.column(f, p + Vector3.new(-4, 0, 0), 6, 0.5, Props.DARK_WOOD, Enum.Material.Wood)
			Props.column(f, p + Vector3.new(4, 0, 0), 6, 0.5, Props.DARK_WOOD, Enum.Material.Wood)
			Props.beam(f, p + Vector3.new(-4, 5.5, 0), p + Vector3.new(4, 5.5, 0), 0.4, Props.DARK_WOOD, Enum.Material.Wood)
			for i = -3, 3 do
				Props.ellipsoid(f, Vector3.new(0.6, 1.8, 0.4), CFrame.new(p + Vector3.new(i, 4.4, 0)), Color3.fromRGB(170, 180, 190), Enum.Material.SmoothPlastic)
			end
		end
		for _ = 1, 6 do
			Props.barrel(f, c + Vector3.new(rng:NextNumber(-50, 50), 0, rng:NextNumber(-50, 50)))
		end
		Props.sign(f, CFrame.lookAt(c + Vector3.new(60, 3.5, -40), c + Vector3.new(120, 3.5, -80)), "Fishing Village\nLevel 5 - 10", Vector2.new(10, 4))
	end

	-- Longhouse Hold
	do
		local f = folder("LonghouseHold", vl)
		local c = camps.LonghouseHold.center
		Props.longhouse(f, facingCF(c + Vector3.new(-18, 0, 10), Vector3.new(-1, 0, -1)), 42)
		Props.longhouse(f, facingCF(c + Vector3.new(24, 0, 26), Vector3.new(-1, 0, -1)), 36)
		Props.campfire(f, c + Vector3.new(0, 0, -20))
		Props.watchtower(f, c + Vector3.new(-50, 0, 40))
		Props.watchtower(f, c + Vector3.new(50, 0, -40))
		-- palisade ring with a gap facing town (north-west)
		local segments = 14
		for i = 0, segments - 1 do
			local a1 = (i / segments) * math.pi * 2
			local a2 = ((i + 1) / segments) * math.pi * 2
			local mid = (a1 + a2) / 2
			local toTown = math.atan2(-1, -1)
			local diff = math.abs(math.atan2(math.sin(mid - toTown), math.cos(mid - toTown)))
			if diff > 0.5 then
				Props.palisade(f, c + Vector3.new(math.cos(a1) * 82, 0, math.sin(a1) * 82), c + Vector3.new(math.cos(a2) * 82, 0, math.sin(a2) * 82), 12)
			end
		end
		for _, off in ipairs({ Vector3.new(-30, 0, -30), Vector3.new(30, 0, 50), Vector3.new(0, 0, 55) }) do
			Props.banner(f, c + off, Color3.fromRGB(40, 70, 150), Vector3.new(-1, 0, -1))
		end
		for _ = 1, 8 do
			Props.crate(f, c + Vector3.new(rng:NextNumber(-55, 55), 0, rng:NextNumber(-55, 55)))
		end
		Props.sign(f, CFrame.lookAt(c + Vector3.new(-70, 3.5, -75), c + Vector3.new(-120, 3.5, -120)), "Longhouse Hold\nLevel 10 - 17", Vector2.new(10, 4))
	end

	-- Jarl's Fortress
	do
		local f = folder("JarlsFortress", vl)
		local c = camps.JarlsFortress.center
		local hx, hz = 95, 85
		local nw, ne = c + Vector3.new(-hx, 0, -hz), c + Vector3.new(hx, 0, -hz)
		local sw, se = c + Vector3.new(-hx, 0, hz), c + Vector3.new(hx, 0, hz)
		Props.stoneWall(f, nw, c + Vector3.new(-16, 0, -hz), 16, 5)
		Props.stoneWall(f, c + Vector3.new(16, 0, -hz), ne, 16, 5)
		Props.stoneWall(f, nw, sw, 16, 5)
		Props.stoneWall(f, ne, se, 16, 5)
		Props.stoneWall(f, sw, se, 16, 5)
		for _, p in ipairs({ nw, ne, sw, se, c + Vector3.new(-20, 0, -hz), c + Vector3.new(20, 0, -hz) }) do
			Props.tower(f, p, 24, 11, Color3.fromRGB(110, 30, 30))
		end
		Props.longhouse(f, facingCF(c + Vector3.new(0, 0, 50), Vector3.new(0, 0, -1)), 60, 26)
		for z = -70, 30, 20 do
			Props.torch(f, c + Vector3.new(-12, 0, z), Color3.fromRGB(255, 120, 50))
			Props.torch(f, c + Vector3.new(12, 0, z), Color3.fromRGB(255, 120, 50))
		end
		for _, off in ipairs({ Vector3.new(-40, 0, 10), Vector3.new(40, 0, 10), Vector3.new(-25, 0, -60), Vector3.new(25, 0, -60) }) do
			Props.banner(f, c + off, Color3.fromRGB(120, 40, 160), Vector3.new(0, 0, -1))
		end
		Props.campfire(f, c + Vector3.new(-45, 0, -25))
		Props.campfire(f, c + Vector3.new(45, 0, -25))
		Props.sign(f, CFrame.lookAt(c + Vector3.new(26, 3.5, -hz - 12), c + Vector3.new(26, 3.5, -hz - 60)), "Jarl's Fortress\nLevel 18 - 28", Vector2.new(10, 4))
	end

	-- Scattered pines and rocks
	local function nearCamp(p: Vector3): boolean
		for _, camp in ipairs(Zones.Camps) do
			if (Vector3.new(p.X, 0, p.Z) - camp.center).Magnitude < camp.radius + 45 then
				return true
			end
		end
		if math.abs(p.X) < 22 and p.Z < 850 then
			return true -- main path
		end
		if p.X < -380 and p.Z > 480 and p.Z < 700 then
			return true -- pond
		end
		return false
	end
	local scenery = folder("Scenery", vl)
	local placed = 0
	for _ = 1, 400 do
		if placed >= 170 then
			break
		end
		local p = Vector3.new(rng:NextNumber(-530, 530), 0, rng:NextNumber(330, 1090))
		if not nearCamp(p) then
			placed += 1
			if rng:NextNumber() < 0.75 then
				Props.tree(scenery, p, rng:NextNumber(0.9, 1.6), rng:NextNumber() < 0.6 and "snowpine" or "pine")
			else
				Props.rock(scenery, p + Vector3.new(0, 1, 0), rng:NextNumber(4, 11))
			end
		end
	end
end

---------------------------------------------------------------- boss arena

local function buildBossArena(map: Folder)
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
		local wall = Props.part(arena, Vector3.new(2 * math.pi * (r + 2) / segments + 2, h, 2), CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)), Color3.fromRGB(255, 70, 50), Enum.Material.ForceField)
		wall.Transparency = 0.6
		wall.CanQuery = false
		wall.CastShadow = false
	end
	invisibleWall(arena, Vector3.new(r * 2 + 40, 2, r * 2 + 40), CFrame.new(c + Vector3.new(0, h + 1, 0)))
	for _, off in ipairs({ Vector3.new(-40, 0, -85), Vector3.new(40, 0, -85), Vector3.new(-40, 0, 85), Vector3.new(40, 0, 85) }) do
		Props.banner(arena, c + off, Color3.fromRGB(150, 20, 20), Vector3.new(0, 0, -off.Z))
	end
end

---------------------------------------------------------------- world bounds

local function buildBounds(map: Folder)
	local bounds = folder("Bounds", map)
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
	buildBossArena(map)
	buildBounds(map)
	map.Parent = workspace
end

return WorldBuilder
