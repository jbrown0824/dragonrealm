-- Player bases and farming. Each player gets a base in town with 6 planting spots (more can
-- be unlocked). Plants grow Seed -> Seedling -> Sprout -> Flower. A few times per stage a plant
-- gets thirsty (shown above the plot with a countdown) and growth pauses until you water it.
-- Miss the window and it keeps growing anyway, but its quality drops, and quality scales the
-- harvest value. Garden robots bought at the Bot Dock can water and harvest for you.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Seeds = require(Shared.Config.Seeds)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local FarmService = {}
local S

local bases = {} -- [index] = { model, owner, plots = { [i] = plotRuntime }, sign, home, dock, bots = {} }
local playerBase = {} -- [Player] = index

local DIRT = Color3.fromRGB(96, 66, 42)
local WATER_COLOR = Color3.fromRGB(70, 160, 255)
local BLOOM_COLOR = Color3.fromRGB(255, 150, 220)
local OUTLINE_IDLE = Color3.fromRGB(205, 170, 105)
local OUTLINE_LOCKED = Color3.fromRGB(110, 110, 120)
local CARE_RANGE = 40
local WORKSHOP_RANGE = 70

---------------------------------------------------------------- plant state

local function nextNeedAt(seed, needsDone: number): number
	local k = needsDone + 1
	local base = seed.stageTime * k / (seed.needsPerStage + 1)
	return base * (0.85 + math.random() * 0.3)
end

local function newPlant(seedId: string)
	local seed = Seeds.get(seedId)
	return {
		seed = seedId,
		stage = 1,
		progress = 0,
		quality = 100,
		need = false,
		needLeft = 0,
		needsDone = 0,
		nextNeedAt = nextNeedAt(seed, 0),
	}
end

-- Saves from before the water-only update had sun needs, health and withering.
local function migratePlant(plant)
	if type(plant) ~= "table" then
		return
	end
	if plant.need == "sun" then
		plant.need = "water"
	end
	if plant.health then
		plant.quality = math.max(Seeds.MIN_QUALITY, plant.health)
		plant.health = nil
	end
	if plant.withered then
		plant.withered = nil
		plant.quality = Seeds.MIN_QUALITY
	end
	plant.quality = plant.quality or 100
	-- timestamps from another server's clock mean nothing here
	plant.thirstyAt = nil
	plant.bloomAt = nil
end

-- Advance a plant by dt seconds. Returns true when it got thirsty or reached a new stage.
local function growPlant(plant, dt: number): boolean
	local seed = Seeds.get(plant.seed)
	if not seed or plant.stage >= 4 then
		return false
	end
	if plant.need then
		plant.needLeft -= dt
		if plant.needLeft <= 0 then
			-- Missed it: the plant gets over it and grows on, but it won't be worth as much.
			plant.quality = math.max(Seeds.MIN_QUALITY, plant.quality - Seeds.MISSED_WATER_LOSS)
			plant.need = false
			plant.missed = (plant.missed or 0) + 1
			plant.needsDone += 1
			plant.nextNeedAt = nextNeedAt(seed, plant.needsDone)
			return true
		end
		return false
	end
	plant.progress += dt
	if plant.needsDone < seed.needsPerStage and plant.progress >= plant.nextNeedAt then
		plant.need = "water"
		plant.needLeft = seed.needWindow
		plant.thirstyAt = os.clock()
		return true
	end
	if plant.progress >= seed.stageTime and plant.needsDone >= seed.needsPerStage then
		plant.stage += 1
		plant.progress = 0
		plant.needsDone = 0
		plant.nextNeedAt = nextNeedAt(seed, 0)
		if plant.stage >= 4 then
			plant.bloomAt = os.clock()
		end
		return true
	end
	return false
end

local function harvestValue(plant): number
	local seed = Seeds.get(plant.seed)
	if not seed then
		return 0
	end
	return math.floor(seed.value * Seeds.StageValue[plant.stage] * plant.quality / 100)
end

---------------------------------------------------------------- visuals

local function makePart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, sphere: boolean?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if sphere then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end

local function buildPlant(plant, base: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Plant"
	local seed = Seeds.get(plant.seed)
	-- Neglected plants look a little droopy and faded.
	local tired = plant.quality < 70
	local leaf = tired and seed.leaf:Lerp(Color3.fromRGB(150, 130, 70), 0.45) or seed.leaf
	local bloom = seed.bloom
	local stage = plant.stage

	makePart(model, Vector3.new(3, 0.8, 3), base * CFrame.new(0, 0.2, 0), Color3.fromRGB(80, 55, 35), Enum.Material.Ground, true)
	if stage == 1 then
		makePart(model, Vector3.new(0.9, 0.7, 0.9), base * CFrame.new(0, 0.55, 0), Color3.fromRGB(150, 100, 50), nil, true)
		return model
	end

	local height = ({ 0, 1.6, 3.2, 4.6 })[stage]
	local droop = tired and CFrame.Angles(math.rad(14), 0, 0) or CFrame.new()
	local stemCF = base * droop * CFrame.new(0, height / 2 + 0.4, 0)
	makePart(model, Vector3.new(0.35, height, 0.35), stemCF, leaf, nil, false)

	local leafCount = stage == 2 and 2 or 4
	for i = 1, leafCount do
		local angle = (i / leafCount) * math.pi * 2
		local y = 0.6 + (i % 2) * height * 0.3
		local leafCF = base * droop * CFrame.new(0, y, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.9) * CFrame.Angles(math.rad(-25), 0, 0)
		makePart(model, Vector3.new(0.9, 0.2, 1.7), leafCF, leaf, nil, true)
	end

	local top = base * droop * CFrame.new(0, height + 0.4, 0)
	if stage == 3 then
		makePart(model, Vector3.new(0.8, 1.1, 0.8), top, bloom, nil, true)
	elseif stage == 4 then
		makePart(model, Vector3.new(0.9, 0.9, 0.9), top, Color3.fromRGB(255, 240, 150), Enum.Material.Neon, true)
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local petalCF = top * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.95) * CFrame.Angles(math.rad(20), 0, 0)
			makePart(model, Vector3.new(0.9, 0.2, 1.6), petalCF, bloom, nil, true)
		end
		if plant.seed == "Dragonfruit" then
			for i = 1, 3 do
				local angle = (i / 3) * math.pi * 2
				makePart(model, Vector3.new(0.9, 1.1, 0.9), base * CFrame.new(math.cos(angle) * 1.2, height * 0.6, math.sin(angle) * 1.2), Color3.fromRGB(255, 60, 130), nil, true)
			end
		end
		local light = Instance.new("PointLight")
		light.Color = bloom
		light.Range = 8
		light.Brightness = 1
		light.Parent = model:FindFirstChildWhichIsA("BasePart")
	end
	return model
end

local function makeBillboard(plotPart: BasePart)
	-- Sized in studs (scale units) so the signs shrink with distance instead of piling on top of
	-- each other when you look at a whole garden from far away.
	local gui = Instance.new("BillboardGui")
	gui.Name = "PlotInfo"
	gui.Size = UDim2.fromScale(8.5, 3.9)
	gui.StudsOffset = Vector3.new(0, 7.5, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
	frame.BackgroundTransparency = 0.35
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame

	local function label(name: string, y: number, h: number, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.6
		l.Parent = frame
		return l
	end
	label("Title", 0.03, 0.23, Enum.Font.FredokaOne)
	label("Stage", 0.28, 0.19, Enum.Font.GothamBold)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0.07, 0.5)
	bar.Size = UDim2.fromScale(0.86, 0.08)
	bar.BackgroundColor3 = Color3.fromRGB(50, 45, 60)
	bar.BorderSizePixel = 0
	bar.Parent = frame
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	label("Need", 0.61, 0.2, Enum.Font.GothamBold)
	label("Health", 0.82, 0.15, Enum.Font.Gotham)

	gui.Parent = plotPart
	return gui
end

-- A raised wooden frame around each planting spot so it's clear where one ends and the next
-- begins. The frame glows blue when the plant is thirsty and pink when it's ready to harvest.
local function makeOutline(plotPart: BasePart)
	local folder = Instance.new("Model")
	folder.Name = "Outline"
	local size = plotPart.Size
	local top = plotPart.CFrame * CFrame.new(0, size.Y / 2 + 0.25, 0)
	local t = 0.5
	local parts = {}
	for _, spec in ipairs({
		{ Vector3.new(size.X + t, 0.5, t), CFrame.new(0, 0, -size.Z / 2) },
		{ Vector3.new(size.X + t, 0.5, t), CFrame.new(0, 0, size.Z / 2) },
		{ Vector3.new(t, 0.5, size.Z - t), CFrame.new(-size.X / 2, 0, 0) },
		{ Vector3.new(t, 0.5, size.Z - t), CFrame.new(size.X / 2, 0, 0) },
	}) do
		local p = makePart(folder, spec[1], top * spec[2], OUTLINE_IDLE, Enum.Material.Wood)
		table.insert(parts, p)
	end
	folder.Parent = plotPart
	return parts
end

local function setOutline(plot, color: Color3, glow: boolean)
	if plot.outlineColor == color and plot.outlineGlow == glow then
		return
	end
	plot.outlineColor = color
	plot.outlineGlow = glow
	for _, p in ipairs(plot.outline) do
		p.Color = color
		p.Material = glow and Enum.Material.Neon or Enum.Material.Wood
	end
end

---------------------------------------------------------------- robots

local function botPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = makePart(parent, size, cf, color, material)
	if shape then
		p.Shape = shape
	end
	return p
end

-- A little hovering garden drone. kind: "Water" or "Harvest".
local function buildBot(kind: string, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = kind .. "Bot"
	local main = kind == "Water" and Color3.fromRGB(80, 170, 255) or Color3.fromRGB(120, 200, 90)
	local trim = kind == "Water" and Color3.fromRGB(230, 245, 255) or Color3.fromRGB(255, 210, 80)
	local body = botPart(model, Vector3.new(2.6, 2.6, 2.6), at, main, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	body.Name = "Body"
	model.PrimaryPart = body
	local parts = {}
	-- trim band around the middle
	table.insert(parts, botPart(model, Vector3.new(0.5, 3, 3), at * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), trim, Enum.Material.Metal, Enum.PartType.Cylinder))
	table.insert(parts, botPart(model, Vector3.new(1.2, 0.8, 0.3), at * CFrame.new(0, 0.4, -1.2), Color3.fromRGB(20, 30, 40), Enum.Material.Glass))
	for _, x in ipairs({ -0.3, 0.3 }) do
		table.insert(parts, botPart(model, Vector3.new(0.25, 0.25, 0.2), at * CFrame.new(x, 0.45, -1.35), trim, Enum.Material.Neon))
	end
	-- rotor on top
	table.insert(parts, botPart(model, Vector3.new(0.3, 1.2, 0.3), at * CFrame.new(0, 1.6, 0), Color3.fromRGB(60, 60, 70), Enum.Material.Metal))
	table.insert(parts, botPart(model, Vector3.new(3.6, 0.12, 0.5), at * CFrame.new(0, 2.2, 0), Color3.fromRGB(70, 70, 80), Enum.Material.Metal))
	table.insert(parts, botPart(model, Vector3.new(0.5, 0.12, 3.6), at * CFrame.new(0, 2.2, 0), Color3.fromRGB(70, 70, 80), Enum.Material.Metal))
	if kind == "Water" then
		-- watering-can spout
		table.insert(parts, botPart(model, Vector3.new(0.5, 0.5, 1.8), at * CFrame.new(0, -0.5, -1.6) * CFrame.Angles(math.rad(-30), 0, 0), trim, Enum.Material.Metal))
		table.insert(parts, botPart(model, Vector3.new(0.3, 0.9, 0.9), at * CFrame.new(0, -1.0, -2.4) * CFrame.Angles(0, math.rad(90), 0), trim, Enum.Material.Metal, Enum.PartType.Cylinder))
	else
		-- two little scythe arms
		for _, x in ipairs({ -1.4, 1.4 }) do
			table.insert(parts, botPart(model, Vector3.new(0.3, 0.3, 1.6), at * CFrame.new(x, -0.4, -0.6), Color3.fromRGB(90, 90, 100), Enum.Material.Metal))
			table.insert(parts, botPart(model, Vector3.new(0.15, 1.1, 0.9), at * CFrame.new(x, -0.8, -1.4) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(210, 215, 225), Enum.Material.Metal))
		end
	end
	local light = Instance.new("PointLight")
	light.Color = trim
	light.Range = 8
	light.Brightness = 1
	light.Parent = body
	for _, p in ipairs(parts) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = p
		w.Parent = p
		p.Anchored = false
	end
	return model
end

local function dockCFrame(base, kind: string): CFrame
	local dock = base.dock
	local side = kind == "Water" and -3 or 3
	return dock.CFrame * CFrame.new(side, 6.5, 0)
end

local function removeBots(base)
	for kind, bot in pairs(base.bots) do
		bot.model:Destroy()
		base.bots[kind] = nil
	end
end

local function syncBots(baseIndex: number)
	local base = bases[baseIndex]
	local profile = base.owner and S.PlayerService.getProfile(base.owner)
	if not profile or not base.dock then
		removeBots(base)
		return
	end
	local wants = { Water = profile.robots.water == true, Harvest = (profile.robots.harvest or 0) > 0 }
	for kind, want in pairs(wants) do
		if want and not base.bots[kind] then
			local model = buildBot(kind, dockCFrame(base, kind))
			model.Parent = base.model
			base.bots[kind] = { model = model, busy = false }
		elseif not want and base.bots[kind] then
			base.bots[kind].model:Destroy()
			base.bots[kind] = nil
		end
	end
end

-- Fly a bot to a spot above a plot. Calls done() when it arrives.
local function flyBot(bot, target: CFrame, time: number, done)
	local body = bot.model.PrimaryPart
	local tween = TweenService:Create(body, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = target })
	tween.Completed:Once(function()
		if bot.model.Parent and done then
			done()
		end
	end)
	tween:Play()
end

---------------------------------------------------------------- per-plot refresh

local function setPrompt(prompt: ProximityPrompt, enabled: boolean, action: string?, object: string?, hold: number?)
	prompt.Enabled = enabled
	-- Clients show only the prompts of the plot they're facing; they read this to know which
	-- ones the server allows.
	prompt:SetAttribute("On", enabled)
	if action then
		prompt.ActionText = action
	end
	if object then
		prompt.ObjectText = object
	end
	if hold then
		prompt.HoldDuration = hold
	end
end

local function clearVisual(plot)
	if plot.visual then
		plot.visual:Destroy()
		plot.visual = nil
		plot.visualKey = nil
	end
end

local function refreshPlot(baseIndex: number, plotIndex: number)
	local base = bases[baseIndex]
	local plot = base.plots[plotIndex]
	local owner = base.owner
	local profile = owner and S.PlayerService.getProfile(owner)
	local gui = plot.gui.Frame

	if not profile then
		plot.part.Color = DIRT
		setOutline(plot, OUTLINE_IDLE, false)
		clearVisual(plot)
		plot.gui.Enabled = false
		setPrompt(plot.main, false)
		setPrompt(plot.water, false)
		return
	end
	plot.gui.Enabled = true

	-- Locked plot
	if plotIndex > profile.plotsUnlocked then
		clearVisual(plot)
		plot.part.Color = Color3.fromRGB(70, 70, 75)
		setOutline(plot, OUTLINE_LOCKED, false)
		local isNext = plotIndex == profile.plotsUnlocked + 1
		local cost = Game.PLOT_COSTS[profile.plotsUnlocked - Game.START_PLOTS + 1]
		gui.Title.Text = "🔒 Locked Plot"
		gui.Title.TextColor3 = Color3.fromRGB(180, 180, 190)
		gui.Stage.Text = isNext and cost and string.format("Unlock for %s gold", Util.formatNumber(cost)) or "Unlock earlier plots first"
		gui.Need.Text = ""
		gui.Health.Text = ""
		gui.Bar.Visible = false
		plot.gui.Enabled = isNext
		setPrompt(plot.main, isNext and cost ~= nil, "Unlock Plot", cost and (Util.formatNumber(cost) .. " gold") or "", 0.5)
		setPrompt(plot.water, false)
		return
	end
	plot.part.Color = DIRT

	local plant = profile.plots[plotIndex]
	if not plant then
		clearVisual(plot)
		setOutline(plot, OUTLINE_IDLE, false)
		gui.Title.Text = "Empty Plot " .. plotIndex
		gui.Title.TextColor3 = Color3.fromRGB(220, 200, 160)
		gui.Stage.Text = "Plant a seed here"
		gui.Need.Text = ""
		gui.Health.Text = ""
		gui.Bar.Visible = false
		setPrompt(plot.main, true, "Plant Seed", "Planting Spot " .. plotIndex, 0)
		setPrompt(plot.water, false)
		return
	end

	local seed = Seeds.get(plant.seed)
	local key = plant.seed .. plant.stage .. tostring(plant.quality < 70)
	if plot.visualKey ~= key then
		if plot.visual then
			plot.visual:Destroy()
		end
		plot.visual = buildPlant(plant, plot.part.CFrame * CFrame.new(0, plot.part.Size.Y / 2, 0))
		plot.visual.Parent = plot.part
		plot.visualKey = key
	end

	gui.Title.Text = seed.name
	gui.Title.TextColor3 = seed.bloom
	gui.Bar.Visible = plant.stage < 4
	gui.Stage.Text = string.format("%s %s  (%d/4)", Seeds.StageIcons[plant.stage], Seeds.Stages[plant.stage], plant.stage)
	gui.Bar.Fill.Size = UDim2.fromScale(math.clamp(plant.progress / seed.stageTime, 0, 1), 1)
	local qualityIcon = plant.quality >= 85 and "⭐" or (plant.quality >= 60 and "🙂" or "🥀")
	gui.Health.Text = string.format("%s Quality %d%%   💰 %d", qualityIcon, plant.quality, harvestValue(plant))

	if plant.need == "water" then
		gui.Need.Text = string.format("💧 Thirsty! Water within %s", Util.formatTime(plant.needLeft))
		gui.Need.TextColor3 = WATER_COLOR
		setOutline(plot, WATER_COLOR, true)
	elseif plant.stage >= 4 then
		gui.Need.Text = "🌸 Fully grown! Harvest for seeds"
		gui.Need.TextColor3 = BLOOM_COLOR
		setOutline(plot, BLOOM_COLOR, true)
	else
		gui.Need.Text = "✅ Growing happily"
		gui.Need.TextColor3 = Color3.fromRGB(140, 230, 120)
		setOutline(plot, OUTLINE_IDLE, false)
	end

	local growing = plant.stage < 4
	setPrompt(plot.main, true, plant.stage >= 4 and "Harvest" or string.format("Harvest early (%dg)", harvestValue(plant)), seed.name, plant.stage >= 4 and 0.4 or 1.2)
	setPrompt(plot.water, growing and plant.need == "water", "💧 Water", seed.name, 0)
end

local function refreshBase(baseIndex: number)
	for i = 1, #bases[baseIndex].plots do
		refreshPlot(baseIndex, i)
	end
end

---------------------------------------------------------------- actions

local function ownerCheck(player: Player, baseIndex: number, plotIndex: number, needNear: boolean)
	local base = bases[baseIndex]
	if not base or base.owner ~= player then
		return nil
	end
	local plot = base.plots[plotIndex]
	if not plot then
		return nil
	end
	if needNear then
		local _, _, root = S.PlayerService.getCharacter(player)
		if not root or (root.Position - plot.part.Position).Magnitude > CARE_RANGE then
			return nil
		end
	end
	return S.PlayerService.getProfile(player), plot
end

-- Give a thirsty plant its water. `byBot` skips the range check and the quest credit.
local function waterPlant(player: Player, baseIndex: number, plotIndex: number, byBot: boolean?): boolean
	local profile = ownerCheck(player, baseIndex, plotIndex, not byBot)
	local plant = profile and profile.plots[plotIndex]
	if not plant or plant.stage >= 4 then
		return false
	end
	local seed = Seeds.get(plant.seed)
	if plant.need ~= "water" then
		if not byBot then
			S.PlayerService.notify(player, seed.name .. " isn't thirsty right now. Wait for the 💧!", Color3.fromRGB(170, 210, 255), "💧")
		end
		return false
	end
	plant.need = false
	plant.needsDone += 1
	plant.nextNeedAt = nextNeedAt(seed, plant.needsDone)
	S.CombatService.broadcastVFX({ kind = "water", pos = bases[baseIndex].plots[plotIndex].part.Position })
	if not byBot then
		S.QuestService.progress(player, "care", nil, 1)
	end
	S.PlayerService.markDirty(player)
	refreshPlot(baseIndex, plotIndex)
	return true
end

-- Harvest a plot. Returns the harvested seed id (for replanting) when a full flower was picked.
local function harvest(player: Player, baseIndex: number, plotIndex: number, byBot: boolean?): string?
	local profile = ownerCheck(player, baseIndex, plotIndex, not byBot)
	local plant = profile and profile.plots[plotIndex]
	if not plant then
		return nil
	end
	local seed = Seeds.get(plant.seed)
	profile.plots[plotIndex] = false

	local gold = harvestValue(plant)
	S.PlayerService.addGold(player, gold)
	local parts = { string.format("+%d gold", gold) }
	local flower = plant.stage >= 4
	if flower then
		local seedsBack = 1
		if plant.quality >= Seeds.BONUS_SEED_QUALITY and math.random() < 0.5 then
			seedsBack += 1
		end
		S.PlayerService.addSeeds(player, plant.seed, seedsBack, true)
		table.insert(parts, string.format("%dx %s Seed", seedsBack, seed.name))
		if math.random() < Seeds.MUTATION_CHANCE then
			local idx = table.find(Seeds.Order, plant.seed)
			local better = idx and Seeds.Order[math.min(idx + 1, #Seeds.Order)]
			if better then
				S.PlayerService.addSeeds(player, better, 1, true)
				table.insert(parts, "MUTATION: 1x " .. Seeds[better].name .. " Seed!")
			end
		end
		profile.flowersHarvested += 1
	end
	local who = byBot and "Reap-Bot harvested" or "Harvested"
	S.PlayerService.notify(player, string.format("%s %s (%s, %d%% quality): %s", who, seed.name, Seeds.Stages[plant.stage], plant.quality, table.concat(parts, ", ")), seed.bloom, Seeds.StageIcons[plant.stage])
	S.QuestService.progress(player, "harvest", flower and "Flower" or Seeds.Stages[plant.stage], 1)
	S.CombatService.broadcastVFX({ kind = "harvest", pos = bases[baseIndex].plots[plotIndex].part.Position, color = seed.bloom })
	S.PlayerService.markDirty(player)
	refreshPlot(baseIndex, plotIndex)
	return flower and plant.seed or nil
end

local function plant(player: Player, baseIndex: number, plotIndex: number, seedId: string): boolean
	local profile = S.PlayerService.getProfile(player)
	if not profile or plotIndex > profile.plotsUnlocked or profile.plots[plotIndex] then
		return false
	end
	if not Seeds.get(seedId) or (profile.seeds[seedId] or 0) <= 0 then
		return false
	end
	profile.seeds[seedId] -= 1
	if profile.seeds[seedId] <= 0 then
		profile.seeds[seedId] = nil
	end
	profile.plots[plotIndex] = newPlant(seedId)
	S.PlayerService.markDirty(player)
	refreshPlot(baseIndex, plotIndex)
	return true
end

local function unlockPlot(player: Player, baseIndex: number, plotIndex: number)
	local profile = ownerCheck(player, baseIndex, plotIndex, true)
	if not profile or plotIndex ~= profile.plotsUnlocked + 1 then
		return
	end
	local cost = Game.PLOT_COSTS[profile.plotsUnlocked - Game.START_PLOTS + 1]
	if not cost then
		return
	end
	if not S.PlayerService.spendGold(player, cost) then
		S.PlayerService.notify(player, string.format("You need %s gold to unlock this plot.", Util.formatNumber(cost)), Color3.fromRGB(255, 120, 100), "🔒")
		return
	end
	profile.plotsUnlocked += 1
	S.PlayerService.notify(player, "New planting spot unlocked!", Color3.fromRGB(140, 230, 120), "🌱")
	S.PlayerService.markDirty(player)
	refreshBase(baseIndex)
end

local function onMain(player: Player, baseIndex: number, plotIndex: number)
	local profile = ownerCheck(player, baseIndex, plotIndex, true)
	if not profile then
		return
	end
	if plotIndex > profile.plotsUnlocked then
		unlockPlot(player, baseIndex, plotIndex)
	elseif profile.plots[plotIndex] then
		harvest(player, baseIndex, plotIndex)
	else
		local hasSeeds = false
		for _, n in pairs(profile.seeds) do
			if n > 0 then
				hasSeeds = true
				break
			end
		end
		if hasSeeds then
			Remotes.event("OpenSeedPicker"):FireClient(player, plotIndex)
		else
			S.PlayerService.notify(player, "You have no seeds! Vikings sometimes drop them, and fully grown flowers give seeds back.", Color3.fromRGB(255, 200, 120), "🌰")
		end
	end
end

local function onPlantSeed(player: Player, plotIndex, seedId)
	if type(plotIndex) ~= "number" or type(seedId) ~= "string" then
		return false
	end
	local baseIndex = playerBase[player]
	if not baseIndex or not ownerCheck(player, baseIndex, plotIndex, true) then
		return false, "You can't plant there."
	end
	if not plant(player, baseIndex, plotIndex, seedId) then
		return false, "You can't plant that there."
	end
	S.QuestService.progress(player, "plant", nil, 1)
	return true
end

---------------------------------------------------------------- robot jobs

local function botJobs(baseIndex: number, profile)
	local base = bases[baseIndex]
	local owner = base.owner
	local now = os.clock()
	local waterBot = base.bots.Water
	if waterBot and not waterBot.busy then
		for i = 1, profile.plotsUnlocked do
			local p = profile.plots[i]
			if p and p.need == "water" and now - (p.thirstyAt or 0) >= Game.ROBOTS.Water.delay then
				waterBot.busy = true
				local plotPart = base.plots[i].part
				flyBot(waterBot, CFrame.new(plotPart.Position + Vector3.new(0, 7, 0)) * plotPart.CFrame.Rotation, 1.4, function()
					if base.owner == owner then
						waterPlant(owner, baseIndex, i, true)
					end
					task.delay(0.8, function()
						flyBot(waterBot, dockCFrame(base, "Water"), 1.4, nil)
						waterBot.busy = false
					end)
				end)
				break
			end
		end
	end

	local reapBot = base.bots.Harvest
	if reapBot and not reapBot.busy then
		for i = 1, profile.plotsUnlocked do
			local p = profile.plots[i]
			if p and p.stage >= 4 and now - (p.bloomAt or 0) >= Game.ROBOTS.Harvest.delay then
				reapBot.busy = true
				local plotPart = base.plots[i].part
				flyBot(reapBot, CFrame.new(plotPart.Position + Vector3.new(0, 6, 0)) * plotPart.CFrame.Rotation, 1.4, function()
					if base.owner == owner then
						local seedId = harvest(owner, baseIndex, i, true)
						local prof = S.PlayerService.getProfile(owner)
						if seedId and prof and (prof.robots.harvest or 0) >= 2 and plant(owner, baseIndex, i, seedId) then
							S.PlayerService.notify(owner, "Reap-Bot replanted a " .. Seeds[seedId].name .. " seed.", Seeds[seedId].bloom, "🌱")
						end
					end
					task.delay(0.8, function()
						flyBot(reapBot, dockCFrame(base, "Harvest"), 1.4, nil)
						reapBot.busy = false
					end)
				end)
				break
			end
		end
	end
end

local function onBuyRobot(player: Player, kind)
	local profile = S.PlayerService.getProfile(player)
	local baseIndex = playerBase[player]
	local base = baseIndex and bases[baseIndex]
	if not profile or not base or type(kind) ~= "string" then
		return false, "You need a lair first."
	end
	local _, _, root = S.PlayerService.getCharacter(player)
	if not root or (root.Position - base.dock.Position).Magnitude > WORKSHOP_RANGE then
		return false, "Visit the Bot Dock in your lair to buy robots."
	end
	local cost, onBought
	if kind == "Water" then
		if profile.robots.water then
			return false, "You already have a Drizzle-Bot."
		end
		cost = Game.ROBOTS.Water.cost
		onBought = function()
			profile.robots.water = true
		end
	elseif kind == "Harvest" then
		local level = profile.robots.harvest or 0
		local info = Game.ROBOTS.Harvest.levels[level + 1]
		if not info then
			return false, "Your Reap-Bot is fully upgraded."
		end
		cost = info.cost
		onBought = function()
			profile.robots.harvest = level + 1
		end
	else
		return false, "Unknown robot."
	end
	if not S.PlayerService.spendGold(player, cost) then
		return false, string.format("You need %s gold.", Util.formatNumber(cost))
	end
	onBought()
	S.PlayerService.markDirty(player)
	syncBots(baseIndex)
	return true
end

---------------------------------------------------------------- ownership

function FarmService.assignBase(player: Player)
	if playerBase[player] then
		return playerBase[player]
	end
	local profile = S.PlayerService.getProfile(player)
	if profile then
		for i = 1, Game.MAX_PLOTS do
			if profile.plots[i] == nil then
				profile.plots[i] = false
			else
				migratePlant(profile.plots[i])
			end
		end
	end
	for index, base in ipairs(bases) do
		if not base.owner then
			base.owner = player
			playerBase[player] = index
			base.model:SetAttribute("OwnerUserId", player.UserId)
			base.sign.Text = string.format("🏠 %s's Lair", player.DisplayName)
			for _, prompt in ipairs(base.prompts) do
				prompt:SetAttribute("OwnerUserId", player.UserId)
			end
			local st = S.PlayerService.state[player]
			if st then
				st.baseIndex = index
			end
			refreshBase(index)
			syncBots(index)
			S.PlayerService.markDirty(player)
			return index
		end
	end
	warn("[FarmService] No free base for", player.Name)
	return nil
end

function FarmService.releaseBase(player: Player)
	local index = playerBase[player]
	if not index then
		return
	end
	playerBase[player] = nil
	local base = bases[index]
	base.owner = nil
	base.model:SetAttribute("OwnerUserId", 0)
	base.sign.Text = "🏠 Empty Lair"
	for _, prompt in ipairs(base.prompts) do
		prompt:SetAttribute("OwnerUserId", 0)
	end
	removeBots(base)
	refreshBase(index)
end

function FarmService.getHomeCFrame(player: Player): CFrame?
	local index = playerBase[player]
	local base = index and bases[index]
	if not base then
		return nil
	end
	return base.home.CFrame + Vector3.new(0, 5, 0)
end

-- Redraw a player's plots and robots after their profile was changed from outside (admin tools).
function FarmService.refreshPlayer(player: Player)
	local index = playerBase[player]
	if index then
		refreshBase(index)
		syncBots(index)
	end
end

-- Small garden summary for the client (tutorial, HUD reminders).
function FarmService.summary(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return nil
	end
	local list = {}
	for i = 1, profile.plotsUnlocked do
		local p = profile.plots[i]
		if p then
			table.insert(list, { plot = i, seed = p.seed, stage = p.stage, thirsty = p.need == "water", quality = p.quality })
		end
	end
	return list
end

---------------------------------------------------------------- setup

local function makePrompt(parent: Instance, key: Enum.KeyCode, pad: Enum.KeyCode, action: string, offset: Vector2)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	-- Generous reach: only the plot you're facing shows its prompts (WorldView), so a long reach
	-- can't grab the wrong plot, and big dragons stand farther from what they face.
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.UIOffset = offset
	prompt:SetAttribute("OwnerUserId", 0)
	prompt:SetAttribute("On", false)
	prompt.Parent = parent
	return prompt
end

function FarmService.init(services)
	S = services
	local baseModels = CollectionService:GetTagged("PlayerBase")
	table.sort(baseModels, function(a, b)
		return a:GetAttribute("BaseIndex") < b:GetAttribute("BaseIndex")
	end)
	for _, model in ipairs(baseModels) do
		local index = model:GetAttribute("BaseIndex")
		local base = {
			model = model,
			owner = nil,
			plots = {},
			prompts = {},
			bots = {},
			sign = model:FindFirstChild("Sign"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Title"),
			home = model:FindFirstChild("HomeSpawn"),
			dock = model:FindFirstChild("BotDock"),
		}
		for i = 1, Game.MAX_PLOTS do
			local part = model.Plots:FindFirstChild("Plot" .. i)
			local plot = {
				part = part,
				outline = makeOutline(part),
				gui = makeBillboard(part),
				main = makePrompt(part, Enum.KeyCode.E, Enum.KeyCode.ButtonX, "Plant Seed", Vector2.new(0, 0)),
				water = makePrompt(part, Enum.KeyCode.R, Enum.KeyCode.ButtonY, "💧 Water", Vector2.new(0, 70)),
				visual = nil,
				visualKey = nil,
			}
			table.insert(base.prompts, plot.main)
			table.insert(base.prompts, plot.water)
			plot.main.Triggered:Connect(function(player)
				onMain(player, index, i)
			end)
			plot.water.Triggered:Connect(function(player)
				waterPlant(player, index, i)
			end)
			base.plots[i] = plot
		end
		if base.dock then
			local prompt = base.dock:FindFirstChildWhichIsA("ProximityPrompt")
			if prompt then
				prompt:SetAttribute("OwnerUserId", 0)
				table.insert(base.prompts, prompt)
				prompt.Triggered:Connect(function(player)
					if base.owner == player then
						Remotes.event("OpenPanel"):FireClient(player, "Robots")
					end
				end)
			end
		end
		bases[index] = base
		base.sign.Text = "🏠 Empty Lair"
		refreshBase(index)
	end
end

function FarmService.start()
	Remotes.func("PlantSeed").OnServerInvoke = onPlantSeed
	Remotes.func("BuyRobot").OnServerInvoke = onBuyRobot

	while true do
		task.wait(1)
		for index, base in pairs(bases) do
			local owner = base.owner
			local profile = owner and S.PlayerService.getProfile(owner)
			if profile then
				local changed = false
				for i = 1, profile.plotsUnlocked do
					local p = profile.plots[i]
					if p then
						changed = growPlant(p, 1) or changed
						refreshPlot(index, i)
					end
				end
				if changed then
					S.PlayerService.markDirty(owner)
				end
				local ok, err = pcall(botJobs, index, profile)
				if not ok then
					warn("[FarmService] robot error:", err)
				end
			end
		end
	end
end

return FarmService
