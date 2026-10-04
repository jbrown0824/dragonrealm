-- Draws every dragon's nano dragon pets on this client. The server only sets the "Pets"
-- attribute on each character ("species:level:golden", comma-separated); each client builds
-- small local copies that hover beside their owner, flap their wings and bob along, with a
-- nametag (name, then rarity and level) so other players can see what you've got. To keep a
-- crowd readable: other dragons' pet nametags only show up close, other dragons' pets (and every
-- nametag) hide while you're in a boss fight (player attribute InBossFight), and a knocked-out
-- dragon's pets settle on the ground beside it instead of flapping over the body.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pets = require(Shared.Config.Pets)
local DragonBuilder = require(Shared.DragonBuilder)
local DragonRig = require(Shared.DragonRig)

local PetFollow = {}

local PET_SCALE = 0.22
local SHOW_DISTANCE = 220
local TAG_DISTANCE = 70 -- your own pets' nametags show within this range of the camera
local OTHER_TAG_DISTANCE = 28 -- other dragons' pets' nametags only this close
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

-- Species colors, with gold horns, trim and eyes for golden pets.
function PetFollow.look(speciesId: string, golden: boolean)
	local species = Pets.get(speciesId)
	if not golden then
		return species.look.colors, species.look.fire
	end
	local g = Pets.GOLDEN_LOOK
	local colors = table.clone(species.look.colors)
	colors.accent, colors.horn, colors.eyes = g.accent, g.horn, g.eyes
	colors.wing = colors.wing:Lerp(g.accent, 0.35)
	return colors, { colorA = g.fireA, colorB = g.fireB }
end

local function nametag(root: BasePart, speciesId: string, level: number, golden: boolean)
	local species = Pets.get(speciesId)
	local tag = Instance.new("BillboardGui")
	tag.Name = "PetTag"
	tag.Size = UDim2.fromOffset(160, 36)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = TAG_DISTANCE
	tag.LightInfluence = 0
	tag.Adornee = root
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 15
	name.TextStrokeTransparency = 0.3
	name.TextColor3 = golden and Pets.GOLDEN_LOOK.accent or Color3.new(1, 1, 1)
	name.Text = (golden and "✨ Golden " or "") .. species.name
	name.Parent = tag
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 18)
	sub.Size = UDim2.new(1, 0, 0, 16)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 12
	sub.TextStrokeTransparency = 0.4
	sub.TextColor3 = Pets.RarityColors[species.rarity]
	sub.Text = string.format("%s  •  Lv %d", species.rarity, level)
	sub.Parent = tag
	tag.Parent = root
	return tag
end

-- Golden pets sparkle gold; Secret pets always trail their own `aura` color.
local function sparkle(root: BasePart, color: Color3, name: string)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Rate = 10
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = root
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6
	light.Brightness = 1.2
	light.Parent = root
end

local function buildPet(entryText: string)
	local speciesId, level, golden = string.match(entryText, "^([^:]+):?(%d*):?(%d*)$")
	local species = speciesId and Pets.get(speciesId)
	if not species then
		return nil
	end
	local isGolden = golden == "1"
	local colors, fire = PetFollow.look(speciesId, isGolden)
	local model = DragonBuilder.build(species.plan, {
		scale = PET_SCALE,
		anchored = true,
		noParticles = true,
		lite = true,
		colors = colors,
		fire = fire,
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
	local tag = nametag(model.PrimaryPart, speciesId, tonumber(level) or 1, isGolden)
	if isGolden then
		sparkle(model.PrimaryPart, Color3.fromRGB(255, 225, 90), "GoldenSparkle")
	end
	if species.aura then
		sparkle(model.PrimaryPart, species.aura, "SecretAura")
	end
	model.Parent = folder
	local stand = (model:GetAttribute("HipHeight") or 1) + model.PrimaryPart.Size.Y / 2
	return { model = model, root = model.PrimaryPart, motors = motors, info = DragonRig.info(model), phase = math.random() * 10, tag = tag, stand = stand }
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
	for entryText in string.gmatch(key, "[^,]+") do
		local pet = buildPet(entryText)
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

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- The floor under a point (for pets settling beside a fallen owner).
local function groundY(pos: Vector3, character: Model): number?
	groundParams.FilterDescendantsInstances = { folder, character }
	local ray = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), groundParams)
	return ray and ray.Position.Y or nil
end

local function updateOwner(character: Model, entry, now: number, dt: number, camPos: Vector3)
	local root = character:FindFirstChild("HumanoidRootPart")
	-- Your own pets always show; other dragons' pets only when they're near the camera, and not
	-- at all while you're fighting a boss.
	local mine = character == Players.LocalPlayer.Character
	local bossFight = Players.LocalPlayer:GetAttribute("InBossFight") == true
	local far = not mine and (bossFight or (root.Position - camPos).Magnitude > SHOW_DISTANCE)
	local scale = character:GetAttribute("DragonScale") or 1
	local ownerCF = root.CFrame
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local downed = character:GetAttribute("KnockedOut") == true or (humanoid ~= nil and humanoid.Health <= 0)
	for i, pet in ipairs(entry.pets) do
		if far then
			pet.model.Parent = nil
			continue
		end
		if pet.model.Parent ~= folder then
			pet.model.Parent = folder
		end
		if pet.tag then
			pet.tag.Enabled = not bossFight
			pet.tag.MaxDistance = mine and TAG_DISTANCE or OTHER_TAG_DISTANCE
		end
		local t = now + pet.phase
		local offset = OFFSETS[(i - 1) % #OFFSETS + 1] * scale
		local target = ownerCF * offset + Vector3.new(0, math.sin(t * 2.2) * 0.6, 0)
		if downed then
			-- down on the ground beside it, wings folded (not flapping over the body)
			local side = ownerCF:VectorToWorldSpace(Vector3.new(offset.X, 0, offset.Z))
			local spot = root.Position + side * 1.3
			local floor = groundY(spot, character)
			target = Vector3.new(spot.X, (floor or (root.Position.Y - 3 * scale)) + pet.stand, spot.Z)
		end
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
		local pose = DragonRig.pose(pet.info, { t = t, mode = downed and "ground" or "fly", vy = 0, speed = 0 })
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
