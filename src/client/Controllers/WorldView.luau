-- Per-player view tweaks of the shared world:
--   * hides farm prompts on other players' bases
--   * hides other players' loot orbs
--   * shows ❗ / ❓ quest markers over village dragons
--   * renders stealthed dragons as see-through (or almost invisible to others)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestUtil = require(Shared.QuestUtil)

local WorldView = {}
local App

local player = Players.LocalPlayer
local markers = {} -- [giverId] = TextLabel

---------------------------------------------------------------- prompts

local function enforcePrompt(prompt: ProximityPrompt)
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner ~= nil and owner ~= player.UserId and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function watchPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt:GetAttribute("OwnerUserId") == nil then
		return
	end
	enforcePrompt(prompt)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		enforcePrompt(prompt)
	end)
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		enforcePrompt(prompt)
	end)
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
	if not giverId or markers[giverId] then
		return
	end
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "QuestMarker"
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffset = Vector3.new(0, 11, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	markers[giverId] = label
end

local function refreshMarkers()
	local p = App.State.profile
	if not p then
		return
	end
	for giverId, label in pairs(markers) do
		local state = QuestUtil.giverState(giverId, p.quests, p.level)
		if state == "turnin" then
			label.Text = "?"
			label.TextColor3 = Color3.fromRGB(255, 215, 60)
		elseif state == "available" then
			label.Text = "!"
			label.TextColor3 = Color3.fromRGB(255, 225, 60)
		elseif state == "active" then
			label.Text = "?"
			label.TextColor3 = Color3.fromRGB(170, 170, 180)
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

	local map = workspace:WaitForChild("Map")
	for _, d in ipairs(map:GetDescendants()) do
		watchPrompt(d)
	end
	map.DescendantAdded:Connect(watchPrompt)

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

	for _, model in ipairs(CollectionService:GetTagged("QuestGiver")) do
		addMarker(model)
	end
	CollectionService:GetInstanceAddedSignal("QuestGiver"):Connect(function(model)
		addMarker(model)
		refreshMarkers()
	end)
	App.State.changed:Connect(refreshMarkers)
	refreshMarkers()
end

return WorldView
