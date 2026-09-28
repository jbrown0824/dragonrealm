-- Draws every dragon's nano dragon pets on this client. The server only sets the "Pets"
-- attribute on each character (comma-separated species ids); each client builds small local
-- copies that hover beside their owner, flap their wings and bob along.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local DragonBuilder = require(Shared.DragonBuilder)
local DragonRig = require(Shared.DragonRig)

local PetFollow = {}

local PET_SCALE = 0.26
local SHOW_DISTANCE = 220
local folder: Folder
local owners = {} -- [Model] = { key, pets = { { model, root, motors, info, pos, phase } } }

-- Spots around the owner (right, left, above-behind), scaled by the owner's size.
local OFFSETS = { Vector3.new(4.5, 3.5, 1), Vector3.new(-4.5, 3.8, 1.5), Vector3.new(0, 6, 5) }

local function clearPets(entry)
	for _, pet in ipairs(entry.pets) do
		pet.model:Destroy()
	end
	entry.pets = {}
end

local function buildPet(speciesId: string)
	local species = Pets.get(speciesId)
	if not species then
		return nil
	end
	local model = DragonBuilder.build(species.plan, {
		scale = PET_SCALE,
		anchored = true,
		noParticles = true,
		lite = true,
		colors = species.look.colors,
		fire = species.look.fire,
		name = species.name,
	})
	local motors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
		elseif d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	model.Parent = folder
	return { model = model, root = model.PrimaryPart, motors = motors, info = DragonRig.info(model), phase = math.random() * 10 }
end

local function sync(character: Model)
	local key = character:GetAttribute("Pets") or ""
	local entry = owners[character]
	if not entry then
		entry = { key = nil, pets = {} }
		owners[character] = entry
	end
	if entry.key == key then
		return
	end
	entry.key = key
	clearPets(entry)
	for speciesId in string.gmatch(key, "[^,]+") do
		local pet = buildPet(speciesId)
		if pet then
			table.insert(entry.pets, pet)
		end
	end
end

local watched = {} -- [Model] = true once we listen for its "Pets" attribute

local function watch(character: Instance)
	if not character:IsA("Model") or not character:GetAttribute("OwnerUserId") or watched[character] then
		return
	end
	watched[character] = true
	sync(character)
	character:GetAttributeChangedSignal("Pets"):Connect(function()
		sync(character)
	end)
end

local function updateOwner(character: Model, entry, now: number, dt: number, camPos: Vector3)
	local root = character:FindFirstChild("HumanoidRootPart")
	-- Your own pets always show; other dragons' pets only when they're near the camera.
	local mine = character == Players.LocalPlayer.Character
	local far = not mine and (root.Position - camPos).Magnitude > SHOW_DISTANCE
	local scale = character:GetAttribute("DragonScale") or 1
	local ownerCF = root.CFrame
	for i, pet in ipairs(entry.pets) do
		if far then
			pet.model.Parent = nil
			continue
		end
		if pet.model.Parent ~= folder then
			pet.model.Parent = folder
		end
		local t = now + pet.phase
		local offset = OFFSETS[(i - 1) % #OFFSETS + 1] * scale
		local target = ownerCF * offset + Vector3.new(0, math.sin(t * 2.2) * 0.6, 0)
		-- Glide after the owner, but jump straight to them after a teleport (boss arena, fly home...).
		if not pet.pos or pet.pos ~= pet.pos or (pet.pos - target).Magnitude > 80 then
			pet.pos = target
		else
			pet.pos = pet.pos:Lerp(target, math.clamp(dt * 6, 0, 1))
		end
		local moveDir = target - pet.pos
		local look = Vector3.new(moveDir.X, 0, moveDir.Z).Magnitude > 0.5 and moveDir or ownerCF.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		pet.root.CFrame = CFrame.lookAt(pet.pos, pet.pos + look.Unit)
		local pose = DragonRig.pose(pet.info, { t = t, mode = "fly", vy = 0, speed = 0 })
		for name, cf in pairs(pose) do
			local m = pet.motors[name]
			if m then
				m.Transform = cf
			end
		end
	end
end

local warned = false
local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	for character, entry in pairs(owners) do
		if not character.Parent or not character:FindFirstChild("HumanoidRootPart") then
			clearPets(entry)
			owners[character] = nil
			watched[character] = nil
			continue
		end
		-- A pet model that got removed from under us is rebuilt on the next sync.
		for _, pet in ipairs(entry.pets) do
			if pet.model.Parent == nil and not pet.root.Parent then
				entry.key = nil
			end
		end
		local ok, err = pcall(updateOwner, character, entry, now, dt, camPos)
		if not ok and not warned then
			warned = true
			warn("[PetFollow]", err)
		end
	end
end

function PetFollow.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = workspace
	for _, model in ipairs(CollectionService:GetTagged("Dragon")) do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal("Dragon"):Connect(watch)
	RunService.RenderStepped:Connect(step)
	-- Safety net: pick up any player's current dragon we somehow missed, and re-sync pets.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character and character.Parent then
					watch(character)
					if owners[character] and owners[character].key ~= (character:GetAttribute("Pets") or "") then
						sync(character)
					end
				end
			end
		end
	end)
end

return PetFollow
