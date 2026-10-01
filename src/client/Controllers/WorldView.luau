-- Per-player view tweaks of the shared world:
--   * hides prompts owned by someone else (other lairs, someone else's fresh kill)
--   * in your lair, only the planting spot you're facing shows its prompts, with a glowing
--     outline, so you never water or harvest the plot next to the one you meant
--   * hides other players' loot orbs
--   * shows ❗ / ❓ quest markers over every quest giver (a dungeon keeper stands outside and
--     inside its dungeon: each gets its own), a grey ! for a quest you're not high enough level
--     for yet, and ⚔️ while the village's givers fight a raid
--   * renders stealthed dragons as see-through (or almost invisible to others)
--   * camp chests: each dragon has their own chest timer, so the lid, the treasure inside and
--     the "refills in" countdown are drawn per player from the ChestReady_<campId> attribute (a
--     dungeon's hidden hoard, tag DungeonChest, the same way: open and "Looted" once you've had it)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestUtil = require(Shared.QuestUtil)
local Quests = require(Shared.Config.Quests)
local Util = require(Shared.Util)

local WorldView = {}
local App

local player = Players.LocalPlayer
local markers = {} -- [giver Model] = { giverId, label, gui }
local watched = {} -- [ProximityPrompt] = true
local focusedPlot: BasePart? = nil
local highlight: Highlight? = nil

---------------------------------------------------------------- prompts

-- Should this prompt show for me right now?
--   "On" (farm prompts): what the server wants; prompts without it are meant to be on
--   "OwnerUserId": only its owner sees it (no attribute = everyone)
--   plot prompts: only on the plot I'm facing
local function wanted(prompt: ProximityPrompt): boolean
	local on = prompt:GetAttribute("On")
	if on == false then
		return false
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner ~= nil and owner ~= player.UserId then
		return false
	end
	local parent = prompt.Parent
	if parent and parent:GetAttribute("PlotIndex") ~= nil then
		return parent == focusedPlot
	end
	return true
end

local function enforcePrompt(prompt: ProximityPrompt)
	local want = wanted(prompt)
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or watched[prompt] then
		return
	end
	if prompt:GetAttribute("OwnerUserId") == nil and prompt:GetAttribute("On") == nil then
		-- Plain prompts (shops, chests, quest givers...) aren't filtered.
		return
	end
	watched[prompt] = true
	enforcePrompt(prompt)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		enforcePrompt(prompt)
	end)
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		enforcePrompt(prompt)
	end)
	prompt:GetAttributeChangedSignal("On"):Connect(function()
		enforcePrompt(prompt)
	end)
	prompt.Destroying:Connect(function()
		watched[prompt] = nil
	end)
end

---------------------------------------------------------------- camp chests

local chestViews = {} -- list of { model, campId, prompt, lid, lidClosed, treasure, label, open }

local function hinge(lid: Model, angle: number): CFrame
	local size = lid.PrimaryPart.Size
	return CFrame.new(0, -size.Y / 2, size.Z / 2) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, size.Y / 2, -size.Z / 2)
end

local function swingLid(view, open: boolean)
	local lid = view.lid
	if not lid or not lid.PrimaryPart then
		return
	end
	task.spawn(function()
		local from = open and 0 or math.rad(105)
		local to = open and math.rad(105) or 0
		for i = 1, 12 do
			if view.open ~= open then
				return -- changed again mid-swing
			end
			local t = i / 12
			local eased = 1 - (1 - t) ^ 3
			lid:PivotTo(view.lidClosed * hinge(lid, from + (to - from) * eased))
			task.wait(0.04)
		end
	end)
end

local function updateChest(view)
	local readyAt = player:GetAttribute("ChestReady_" .. view.campId) or 0
	local left = readyAt - workspace:GetServerTimeNow()
	local open = left > 0
	if view.open ~= open then
		view.open = open
		swingLid(view, open)
		if view.treasure then
			view.treasure.Parent = if open then nil else view.model
		end
		if view.prompt.Enabled == open then
			view.prompt.Enabled = not open
		end
	end
	if view.oneTime then
		-- a dungeon's hidden hoard: once per run
		view.label.Text = open and "Looted" or "💰 Hidden hoard"
	else
		view.label.Text = open and ("Empty for you  •  refills in " .. Util.formatTime(left)) or "💰 Treasure Chest"
	end
	view.label.TextColor3 = open and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(255, 215, 90)
end

local function addChest(model: Instance)
	local campId = model:GetAttribute("CampId")
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	local base = model:FindFirstChild("Base")
	if not campId or not prompt or not base then
		return
	end
	local lid = model:FindFirstChild("Lid")
	local gui = Instance.new("BillboardGui")
	gui.Name = "ChestLabel"
	gui.ResetOnSpawn = false -- lives in PlayerGui: keep it when the dragon respawns
	gui.Adornee = base
	gui.Size = UDim2.fromOffset(260, 30)
	gui.StudsOffset = Vector3.new(0, 6.5, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 20
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	local view = {
		model = model,
		campId = campId,
		prompt = prompt,
		lid = lid and lid:IsA("Model") and lid or nil,
		lidClosed = lid and lid:IsA("Model") and lid:GetPivot(),
		treasure = model:FindFirstChild("Treasure"),
		label = label,
		open = false,
		oneTime = model:GetAttribute("OneTime") == true,
	}
	table.insert(chestViews, view)
	updateChest(view)
end

---------------------------------------------------------------- planting spot focus

local function myBase(): Model?
	local p = App.State.profile
	local index = p and p.baseIndex
	if not index then
		return nil
	end
	local bases = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Bases")
	return bases and bases:FindFirstChild("Base" .. index)
end

-- The plot closest to a point just in front of my dragon's chest (within reach).
local function findFocus(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local base = myBase()
	local plots = base and base:FindFirstChild("Plots")
	if not root or not plots then
		return nil
	end
	local scale = character:GetAttribute("DragonScale") or 1
	local probe = root.Position + root.CFrame.LookVector * 3 * scale
	local best, bestDist = nil, 9 + 2 * scale
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("BasePart") then
			local d = Vector3.new(plot.Position.X - probe.X, 0, plot.Position.Z - probe.Z).Magnitude
			if d < bestDist and math.abs(plot.Position.Y - root.Position.Y) < 20 then
				best, bestDist = plot, d
			end
		end
	end
	return best
end

local function updateFocus()
	local focus = findFocus()
	if focus == focusedPlot then
		return
	end
	local old = focusedPlot
	focusedPlot = focus
	for _, plot in ipairs({ old, focus }) do
		if plot then
			for _, prompt in ipairs(plot:GetChildren()) do
				if prompt:IsA("ProximityPrompt") then
					enforcePrompt(prompt)
				end
			end
		end
	end
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "PlotFocus"
		highlight.FillColor = Color3.fromRGB(255, 240, 170)
		highlight.FillTransparency = 0.85
		highlight.OutlineColor = Color3.fromRGB(255, 225, 120)
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = workspace -- created on this client, so only you see it
	end
	highlight.Adornee = focus
	highlight.Enabled = focus ~= nil
end

---------------------------------------------------------------- loot

local function filterLoot(orb: Instance)
	if not orb:IsA("BasePart") then
		return
	end
	local owner = orb:GetAttribute("OwnerUserId")
	if owner and owner ~= player.UserId then
		orb.LocalTransparencyModifier = 1
		for _, d in ipairs(orb:GetDescendants()) do
			if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("PointLight") then
				d.Enabled = false
			end
		end
	end
end

---------------------------------------------------------------- stealth

local function applyStealth(model: Model)
	local stealthed = model:GetAttribute("Stealthed") == true
	local mine = model == player.Character
	local amount = stealthed and (mine and 0.6 or 0.93) or 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.LocalTransparencyModifier = amount
		elseif d:IsA("BillboardGui") then
			d.Enabled = not (stealthed and not mine)
		elseif d:IsA("ParticleEmitter") and d.Name == "Aura" then
			d.Enabled = not stealthed
		end
	end
end

local function watchDragon(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("Stealthed"):Connect(function()
		applyStealth(model)
	end)
	if model:GetAttribute("Stealthed") then
		applyStealth(model)
	end
end

---------------------------------------------------------------- quest markers

local function addMarker(model: Instance)
	local giverId = model:GetAttribute("GiverId")
	if not giverId or markers[model] then
		return
	end
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "QuestMarker"
	gui.ResetOnSpawn = false -- lives in PlayerGui: without this a respawn wiped every marker
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffset = Vector3.new(0, 11, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	gui.Adornee = head
	if not head then
		-- (a giver built while you play, like a keeper inside a dungeon, can reach this client
		-- before its parts do: hang the marker on its head once that arrives)
		task.spawn(function()
			for _ = 1, 120 do
				task.wait(0.25)
				local h = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChild("Head", true)
				if h then
					gui.Adornee = h
					return
				end
				if not model.Parent then
					return
				end
			end
		end)
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	markers[model] = { giverId = giverId, label = label, gui = gui }
end

local function refreshMarkers()
	local p = App.State.profile
	if not p then
		return
	end
	local raiding = workspace:GetAttribute("RaidPhase") ~= nil
	for model, marker in pairs(markers) do
		if not model.Parent then
			-- (a dungeon copy that was taken down)
			marker.gui:Destroy()
			markers[model] = nil
			continue
		end
		local giverId, label = marker.giverId, marker.label
		local state = QuestUtil.giverState(giverId, p.quests, p.level)
		local giver = Quests.Givers[giverId]
		if raiding and not (giver and giver.dungeon) then
			-- busy fighting the raiders: no quests until it's over
			label.Text = "⚔️"
			label.TextColor3 = Color3.new(1, 1, 1)
			continue
		end
		if state == "turnin" then
			label.Text = "?"
			label.TextColor3 = Color3.fromRGB(255, 215, 60)
		elseif state == "available" then
			label.Text = "!"
			label.TextColor3 = Color3.fromRGB(255, 225, 60)
		elseif state == "active" then
			label.Text = "?"
			label.TextColor3 = Color3.fromRGB(170, 170, 180)
		elseif QuestUtil.lockedByLevel(giverId, p.quests, p.level) then
			-- a quest waiting for you to level up (talking to them says which level)
			label.Text = "!"
			label.TextColor3 = Color3.fromRGB(150, 150, 160)
		else
			label.Text = ""
		end
		if giverId == "Elder" and label.Text == "" then
			label.Text = "🐉"
			label.TextColor3 = Color3.new(1, 1, 1)
		end
	end
end

function WorldView.init(app)
	App = app

	for _, d in ipairs(workspace:GetDescendants()) do
		watchPrompt(d)
	end
	workspace.DescendantAdded:Connect(watchPrompt)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(updateFocus)
			if not ok then
				warn("[WorldView]", err)
			end
		end
	end)

	local loot = workspace:WaitForChild("Loot")
	for _, orb in ipairs(loot:GetChildren()) do
		filterLoot(orb)
	end
	loot.ChildAdded:Connect(function(orb)
		task.wait()
		filterLoot(orb)
	end)

	for _, model in ipairs(CollectionService:GetTagged("Dragon")) do
		watchDragon(model)
	end
	CollectionService:GetInstanceAddedSignal("Dragon"):Connect(watchDragon)

	for _, model in ipairs(CollectionService:GetTagged("DungeonChest")) do
		addChest(model)
	end
	CollectionService:GetInstanceAddedSignal("DungeonChest"):Connect(addChest)
	for _, model in ipairs(CollectionService:GetTagged("CampChest")) do
		addChest(model)
	end
	CollectionService:GetInstanceAddedSignal("CampChest"):Connect(addChest)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, view in ipairs(chestViews) do
				local ok, err = pcall(updateChest, view)
				if not ok then
					warn("[WorldView] chest", err)
				end
			end
		end
	end)

	for _, model in ipairs(CollectionService:GetTagged("QuestGiver")) do
		addMarker(model)
	end
	CollectionService:GetInstanceAddedSignal("QuestGiver"):Connect(function(model)
		addMarker(model)
		refreshMarkers()
	end)
	App.State.changed:Connect(refreshMarkers)
	workspace:GetAttributeChangedSignal("RaidPhase"):Connect(refreshMarkers)
	refreshMarkers()
end

return WorldView
