-- Player bases and farming. Each player gets a base in town with 6 planting spots (more can
-- be unlocked). Plants grow Seed -> Seedling -> Sprout -> Flower, but only while you give them
-- what they ask for: water or sun, shown above each plot with a countdown.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Seeds = require(Shared.Config.Seeds)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local FarmService = {}
local S

local bases = {} -- [index] = { model, owner, plots = { [i] = plotRuntime }, sign, home }
local playerBase = {} -- [Player] = index

local DIRT = Color3.fromRGB(96, 66, 42)
local WATER_COLOR = Color3.fromRGB(70, 160, 255)
local SUN_COLOR = Color3.fromRGB(255, 215, 60)
local CARE_RANGE = 40

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
		health = 100,
		need = false,
		needLeft = 0,
		needsDone = 0,
		nextNeedAt = nextNeedAt(seed, 0),
		withered = false,
	}
end

-- Advance a plant by dt seconds. Returns true if it changed in a way that matters.
local function growPlant(plant, dt: number): boolean
	local seed = Seeds.get(plant.seed)
	if not seed or plant.withered or plant.stage >= 4 then
		return false
	end
	if plant.need then
		plant.needLeft -= dt
		if plant.needLeft <= 0 then
			plant.health -= Seeds.NEED_PENALTY
			plant.need = false
			plant.needsDone += 1
			plant.nextNeedAt = nextNeedAt(seed, plant.needsDone)
			if plant.health <= 0 then
				plant.health = 0
				plant.withered = true
			end
		end
		return true
	end
	plant.progress += dt
	if plant.needsDone < seed.needsPerStage and plant.progress >= plant.nextNeedAt then
		plant.need = math.random() < seed.sunBias and "sun" or "water"
		plant.needLeft = seed.needWindow
		return true
	end
	if plant.progress >= seed.stageTime and plant.needsDone >= seed.needsPerStage then
		plant.stage += 1
		plant.progress = 0
		plant.needsDone = 0
		plant.nextNeedAt = nextNeedAt(seed, 0)
	end
	return true
end

local function harvestValue(plant): number
	local seed = Seeds.get(plant.seed)
	if not seed or plant.withered then
		return 0
	end
	return math.floor(seed.value * Seeds.StageValue[plant.stage] * (0.4 + 0.6 * plant.health / 100))
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
	local leaf = plant.withered and Color3.fromRGB(110, 85, 50) or seed.leaf
	local bloom = plant.withered and Color3.fromRGB(90, 70, 50) or seed.bloom
	local stage = plant.stage

	makePart(model, Vector3.new(3, 0.8, 3), base * CFrame.new(0, 0.2, 0), Color3.fromRGB(80, 55, 35), Enum.Material.Ground, true)
	if stage == 1 then
		makePart(model, Vector3.new(0.9, 0.7, 0.9), base * CFrame.new(0, 0.55, 0), Color3.fromRGB(150, 100, 50), nil, true)
		return model
	end

	local height = ({ 0, 1.6, 3.2, 4.6 })[stage]
	local droop = plant.withered and CFrame.Angles(math.rad(35), 0, 0) or CFrame.new()
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
		makePart(model, Vector3.new(0.9, 0.9, 0.9), top, Color3.fromRGB(255, 240, 150), if plant.withered then nil else Enum.Material.Neon, true)
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local petalCF = top * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.95) * CFrame.Angles(math.rad(20), 0, 0)
			makePart(model, Vector3.new(0.9, 0.2, 1.6), petalCF, bloom, nil, true)
		end
		if plant.seed == "Dragonfruit" and not plant.withered then
			for i = 1, 3 do
				local angle = (i / 3) * math.pi * 2
				makePart(model, Vector3.new(0.9, 1.1, 0.9), base * CFrame.new(math.cos(angle) * 1.2, height * 0.6, math.sin(angle) * 1.2), Color3.fromRGB(255, 60, 130), nil, true)
			end
		end
		if not plant.withered then
			local light = Instance.new("PointLight")
			light.Color = bloom
			light.Range = 8
			light.Brightness = 1
			light.Parent = model:FindFirstChildWhichIsA("BasePart")
		end
	end
	return model
end

local function makeBillboard(plotPart: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PlotInfo"
	gui.Size = UDim2.fromOffset(170, 78)
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
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local function label(name: string, y: number, h: number, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(6, y)
		l.Size = UDim2.new(1, -12, 0, h)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.6
		l.Parent = frame
		return l
	end
	label("Title", 3, 18, Enum.Font.FredokaOne)
	label("Stage", 22, 15, Enum.Font.GothamBold)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(10, 39)
	bar.Size = UDim2.new(1, -20, 0, 6)
	bar.BackgroundColor3 = Color3.fromRGB(50, 45, 60)
	bar.BorderSizePixel = 0
	bar.Parent = frame
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	label("Need", 48, 16, Enum.Font.GothamBold)
	label("Health", 64, 12, Enum.Font.Gotham)

	gui.Parent = plotPart
	return gui
end

---------------------------------------------------------------- per-plot refresh

local function setPrompt(prompt: ProximityPrompt, enabled: boolean, action: string?, object: string?, hold: number?)
	prompt.Enabled = enabled
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

local function refreshPlot(baseIndex: number, plotIndex: number)
	local base = bases[baseIndex]
	local plot = base.plots[plotIndex]
	local owner = base.owner
	local profile = owner and S.PlayerService.getProfile(owner)
	local gui = plot.gui.Frame

	if not profile then
		plot.part.Color = DIRT
		plot.ring.Transparency = 1
		if plot.visual then
			plot.visual:Destroy()
			plot.visual = nil
			plot.visualKey = nil
		end
		plot.gui.Enabled = false
		setPrompt(plot.main, false)
		setPrompt(plot.water, false)
		setPrompt(plot.sun, false)
		return
	end
	plot.gui.Enabled = true

	-- Locked plot
	if plotIndex > profile.plotsUnlocked then
		if plot.visual then
			plot.visual:Destroy()
			plot.visual = nil
			plot.visualKey = nil
		end
		plot.part.Color = Color3.fromRGB(70, 70, 75)
		plot.ring.Transparency = 1
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
		setPrompt(plot.sun, false)
		return
	end
	plot.part.Color = DIRT

	local plant = profile.plots[plotIndex]
	if not plant then
		if plot.visual then
			plot.visual:Destroy()
			plot.visual = nil
			plot.visualKey = nil
		end
		plot.ring.Transparency = 1
		gui.Title.Text = "Empty Plot"
		gui.Title.TextColor3 = Color3.fromRGB(220, 200, 160)
		gui.Stage.Text = "Plant a seed here"
		gui.Need.Text = ""
		gui.Health.Text = ""
		gui.Bar.Visible = false
		setPrompt(plot.main, true, "Plant Seed", "Planting Spot " .. plotIndex, 0)
		setPrompt(plot.water, false)
		setPrompt(plot.sun, false)
		return
	end

	local seed = Seeds.get(plant.seed)
	local key = plant.seed .. plant.stage .. tostring(plant.withered)
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
	gui.Bar.Visible = plant.stage < 4 and not plant.withered
	gui.Stage.Text = string.format("%s %s  (%d/4)", Seeds.StageIcons[plant.stage], Seeds.Stages[plant.stage], plant.stage)
	gui.Bar.Fill.Size = UDim2.fromScale(math.clamp(plant.progress / seed.stageTime, 0, 1), 1)
	gui.Health.Text = string.format("❤️ Health %d%%   💰 %d", plant.health, harvestValue(plant))

	if plant.withered then
		gui.Need.Text = "🥀 Withered..."
		gui.Need.TextColor3 = Color3.fromRGB(190, 140, 100)
		plot.ring.Transparency = 1
		setPrompt(plot.main, true, "Clear Plant", seed.name, 0.5)
		setPrompt(plot.water, false)
		setPrompt(plot.sun, false)
		return
	end

	if plant.need == "water" then
		gui.Need.Text = string.format("💧 Needs WATER! %s", Util.formatTime(plant.needLeft))
		gui.Need.TextColor3 = WATER_COLOR
		plot.ring.Color = WATER_COLOR
		plot.ring.Transparency = 0.2
	elseif plant.need == "sun" then
		gui.Need.Text = string.format("☀️ Needs SUN! %s", Util.formatTime(plant.needLeft))
		gui.Need.TextColor3 = SUN_COLOR
		plot.ring.Color = SUN_COLOR
		plot.ring.Transparency = 0.2
	elseif plant.stage >= 4 then
		gui.Need.Text = "🌸 Fully grown! Harvest for seeds"
		gui.Need.TextColor3 = Color3.fromRGB(255, 150, 220)
		plot.ring.Color = Color3.fromRGB(255, 150, 220)
		plot.ring.Transparency = 0.5
	else
		gui.Need.Text = "✅ Growing happily"
		gui.Need.TextColor3 = Color3.fromRGB(140, 230, 120)
		plot.ring.Transparency = 1
	end

	local growing = plant.stage < 4
	setPrompt(plot.main, true, plant.stage >= 4 and "Harvest" or string.format("Harvest early (%dg)", harvestValue(plant)), seed.name, plant.stage >= 4 and 0.4 or 1.2)
	setPrompt(plot.water, growing, "💧 Water", seed.name, 0)
	setPrompt(plot.sun, growing, "☀️ Give Sun", seed.name, 0)
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

local function care(player: Player, baseIndex: number, plotIndex: number, action: string)
	local profile = ownerCheck(player, baseIndex, plotIndex, true)
	local plant = profile and profile.plots[plotIndex]
	if not plant or plant.withered or plant.stage >= 4 then
		return
	end
	local seed = Seeds.get(plant.seed)
	if plant.need == action then
		plant.need = false
		plant.needsDone += 1
		plant.nextNeedAt = nextNeedAt(seed, plant.needsDone)
		plant.health = math.min(100, plant.health + Seeds.GOOD_CARE_BONUS)
		S.CombatService.broadcastVFX({ kind = action == "water" and "water" or "sun", pos = bases[baseIndex].plots[plotIndex].part.Position })
		S.QuestService.progress(player, "care", nil, 1)
	elseif plant.need then
		plant.health -= Seeds.WRONG_CARE_PENALTY
		S.PlayerService.notify(player, string.format("Oops! %s wanted %s, not %s.", seed.name, plant.need == "sun" and "sun" or "water", action), Color3.fromRGB(255, 140, 90), "⚠️")
	else
		plant.health -= 5
		S.PlayerService.notify(player, string.format("Too much %s! Wait until %s asks for it.", action == "sun" and "sun" or "water", seed.name), Color3.fromRGB(255, 180, 90), "⚠️")
	end
	if plant.health <= 0 then
		plant.health = 0
		plant.withered = true
	end
	refreshPlot(baseIndex, plotIndex)
end

local function harvest(player: Player, baseIndex: number, plotIndex: number)
	local profile = ownerCheck(player, baseIndex, plotIndex, true)
	local plant = profile and profile.plots[plotIndex]
	if not plant then
		return
	end
	local seed = Seeds.get(plant.seed)
	profile.plots[plotIndex] = false

	if plant.withered then
		S.PlayerService.notify(player, "You cleared the withered plant.", Color3.fromRGB(190, 160, 120), "🥀")
	else
		local gold = harvestValue(plant)
		S.PlayerService.addGold(player, gold)
		local parts = { string.format("+%d gold", gold) }
		if plant.stage >= 4 then
			local seedsBack = 1
			if plant.health >= 75 and math.random() < 0.5 then
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
		S.PlayerService.notify(player, string.format("Harvested %s (%s): %s", seed.name, Seeds.Stages[plant.stage], table.concat(parts, ", ")), seed.bloom, Seeds.StageIcons[plant.stage])
		S.QuestService.progress(player, "harvest", plant.stage >= 4 and "Flower" or Seeds.Stages[plant.stage], 1)
		S.CombatService.broadcastVFX({ kind = "harvest", pos = bases[baseIndex].plots[plotIndex].part.Position, color = seed.bloom })
	end
	S.PlayerService.markDirty(player)
	refreshPlot(baseIndex, plotIndex)
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
	if not baseIndex then
		return false
	end
	local profile = ownerCheck(player, baseIndex, plotIndex, true)
	if not profile or plotIndex > profile.plotsUnlocked or profile.plots[plotIndex] then
		return false, "You can't plant there."
	end
	if not Seeds.get(seedId) or (profile.seeds[seedId] or 0) <= 0 then
		return false, "You don't have that seed."
	end
	profile.seeds[seedId] -= 1
	if profile.seeds[seedId] <= 0 then
		profile.seeds[seedId] = nil
	end
	profile.plots[plotIndex] = newPlant(seedId)
	S.PlayerService.markDirty(player)
	S.QuestService.progress(player, "plant", nil, 1)
	refreshPlot(baseIndex, plotIndex)
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
			end
		end
	end
	for index, base in ipairs(bases) do
		if not base.owner then
			base.owner = player
			playerBase[player] = index
			base.model:SetAttribute("OwnerUserId", player.UserId)
			base.sign.Text = string.format("🏠 %s's Lair", player.DisplayName)
			for _, plot in ipairs(base.plots) do
				for _, prompt in ipairs({ plot.main, plot.water, plot.sun }) do
					prompt:SetAttribute("OwnerUserId", player.UserId)
				end
			end
			local st = S.PlayerService.state[player]
			if st then
				st.baseIndex = index
			end
			refreshBase(index)
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
	for _, plot in ipairs(base.plots) do
		for _, prompt in ipairs({ plot.main, plot.water, plot.sun }) do
			prompt:SetAttribute("OwnerUserId", 0)
		end
	end
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

---------------------------------------------------------------- setup

local function makePrompt(parent: Instance, key: Enum.KeyCode, pad: Enum.KeyCode, action: string, offset: Vector2)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.UIOffset = offset
	prompt:SetAttribute("OwnerUserId", 0)
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
			sign = model:FindFirstChild("Sign"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Title"),
			home = model:FindFirstChild("HomeSpawn"),
		}
		for i = 1, Game.MAX_PLOTS do
			local part = model.Plots:FindFirstChild("Plot" .. i)
			local ring = Instance.new("Part")
			ring.Name = "NeedRing"
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.Material = Enum.Material.Neon
			ring.Size = Vector3.new(part.Size.X + 1.2, part.Size.Y - 0.1, part.Size.Z + 1.2)
			ring.CFrame = part.CFrame
			ring.Transparency = 1
			ring.Parent = part

			local plot = {
				part = part,
				ring = ring,
				gui = makeBillboard(part),
				main = makePrompt(part, Enum.KeyCode.E, Enum.KeyCode.ButtonX, "Plant Seed", Vector2.new(0, 0)),
				water = makePrompt(part, Enum.KeyCode.R, Enum.KeyCode.ButtonY, "💧 Water", Vector2.new(0, 70)),
				sun = makePrompt(part, Enum.KeyCode.T, Enum.KeyCode.ButtonB, "☀️ Give Sun", Vector2.new(0, 140)),
				visual = nil,
				visualKey = nil,
			}
			plot.main.Triggered:Connect(function(player)
				onMain(player, index, i)
			end)
			plot.water.Triggered:Connect(function(player)
				care(player, index, i, "water")
			end)
			plot.sun.Triggered:Connect(function(player)
				care(player, index, i, "sun")
			end)
			base.plots[i] = plot
		end
		bases[index] = base
		base.sign.Text = "🏠 Empty Lair"
		refreshBase(index)
	end
end

function FarmService.start()
	Remotes.func("PlantSeed").OnServerInvoke = onPlantSeed

	while true do
		task.wait(1)
		for index, base in pairs(bases) do
			local owner = base.owner
			local profile = owner and S.PlayerService.getProfile(owner)
			if profile then
				for i = 1, profile.plotsUnlocked do
					local plant = profile.plots[i]
					if plant then
						growPlant(plant, 1)
						refreshPlot(index, i)
					end
				end
			end
		end
	end
end

return FarmService
