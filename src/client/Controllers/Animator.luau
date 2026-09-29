-- Procedural animation, run on each client by setting Motor6D.Transform:
--   dragons: poses from Shared/DragonRig (folded wings at rest, hard wing beats when jumping,
--            gliding when falling, flapping in flight, jaw + frill when breathing fire, blinking,
--            walking with knees, a pulsing ember core, sprawled flat when knocked out or dead),
--            blended smoothly between states
--   vikings: walking, chopping, throwing, and raising the war horn (Hornblowers); raiders
--            riding a longship (tag VikingPassenger) cheer with their arms up, and tuck in to leap
--   animals: trotting legs, head bob and tail wag (AnimalBuilder rigs)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DragonRig = require(ReplicatedStorage:WaitForChild("Shared").DragonRig)

local Animator = {}
local App

local rigs = {} -- [Model] = { kind, motors, current, phase, root, info, coreLight, swingAt, throwAt }

local function register(model: Instance, kind: string)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local rig = { kind = kind, motors = {}, current = {}, phase = math.random() * 10, root = nil, swingAt = -10, throwAt = -10 }
	rigs[model] = rig
	-- Joints can replicate a moment after the model itself (especially while the game is still
	-- loading), so keep picking up any that arrive later; a joint we never saw would leave that
	-- limb frozen in its build pose (a wing stuck spread out, for example).
	local function track(d: Instance)
		if d:IsA("Motor6D") then
			rig.motors[d.Name] = d
		elseif d.Name == "CoreLight" and d:IsA("PointLight") then
			rig.coreLight = d
		end
	end
	model.DescendantAdded:Connect(track)
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 10)
		for _, d in ipairs(model:GetDescendants()) do
			track(d)
		end
		if kind == "dragon" then
			rig.info = DragonRig.info(model)
		end
		rig.root = root
	end)
	if kind == "viking" or kind == "animal" or kind == "passenger" then
		model:GetAttributeChangedSignal("Swing"):Connect(function()
			rig.swingAt = os.clock()
		end)
		model:GetAttributeChangedSignal("Throw"):Connect(function()
			rig.throwAt = os.clock()
		end)
	end
end

local function set(rig, name: string, cf: CFrame)
	local m = rig.motors[name]
	if m then
		m.Transform = cf
	end
end

local function animateDragon(model: Model, rig, now: number, dt: number)
	local root = rig.root
	local vel = root.AssemblyLinearVelocity
	local t = now + rig.phase
	local breathing = App ~= nil and App.VFX.isBreathing(model)
	local humanoid = rig.humanoid or model:FindFirstChildOfClass("Humanoid")
	rig.humanoid = humanoid
	local downed = model:GetAttribute("KnockedOut") == true or (humanoid ~= nil and humanoid.Health <= 0)
	local pose = DragonRig.pose(rig.info, {
		t = t,
		mode = DragonRig.modeFor(model:GetAttribute("Flying") == true, vel.Y, downed),
		vy = vel.Y,
		speed = Vector3.new(vel.X, 0, vel.Z).Magnitude,
		breathing = breathing,
		blink = (t % 4.7) < 0.14,
	})
	-- Blend toward the target pose so switching between folded / flapping / gliding is smooth.
	-- Jaw, eyelids and flapping wings react fast; everything else eases.
	local alpha = math.clamp(dt * 10, 0, 1)
	local fast = math.clamp(dt * 25, 0, 1)
	for name, target in pairs(pose) do
		local motor = rig.motors[name]
		if motor then
			local current = rig.current[name] or target
			local a = (name == "Jaw" or name == "LidL" or name == "LidR" or name == "WingR" or name == "WingL") and fast or alpha
			current = current:Lerp(target, a)
			rig.current[name] = current
			motor.Transform = current
		end
	end
	if rig.coreLight then
		rig.coreLight.Brightness = 0.8 + math.sin(t * 2.2) * 0.35 + (breathing and 1.8 or 0)
	end
end

local function animatePassenger(model: Model, rig, now: number)
	local t = now + rig.phase
	if model:GetAttribute("Leaping") then
		set(rig, "ArmR", CFrame.Angles(2.9, 0, 0))
		set(rig, "ArmL", CFrame.Angles(2.9, 0, 0))
		set(rig, "LegL", CFrame.Angles(0.9, 0, 0))
		set(rig, "LegR", CFrame.Angles(0.6, 0, 0))
		return
	end
	-- a battle cry on the way in: weapons pumping in the air
	set(rig, "ArmR", CFrame.Angles(2.5 + math.sin(t * 5) * 0.4, 0, 0))
	set(rig, "ArmL", CFrame.Angles(1.6 + math.sin(t * 5 + 1.3) * 0.5, 0, 0))
	set(rig, "LegL", CFrame.Angles(math.max(0, math.sin(t * 2.5)) * 0.15, 0, 0))
	set(rig, "LegR", CFrame.new())
end

local function animateViking(model: Model, rig, now: number)
	if rig.kind == "passenger" then
		animatePassenger(model, rig, now)
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return -- toppled over (EnemyService); keep the pose it fell in
	end
	local root = rig.root
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local t = now + rig.phase
	local walk = math.sin(t * 9) * math.clamp(speed / 12, 0, 1) * 0.8
	set(rig, "LegL", CFrame.Angles(walk, 0, 0))
	set(rig, "LegR", CFrame.Angles(-walk, 0, 0))
	set(rig, "ArmL", CFrame.Angles(-walk * 0.6, 0, 0))

	local sinceSwing = now - rig.swingAt
	local sinceThrow = now - rig.throwAt
	local arm
	if model:GetAttribute("Blowing") then
		-- horn raised to the lips, swaying as he blows
		arm = 2.3 + math.sin(t * 6) * 0.12
	elseif sinceSwing >= 0 and sinceSwing < 0.55 then
		if sinceSwing < 0.25 then
			arm = 2.6 * (sinceSwing / 0.25)
		else
			arm = 2.6 - 3.0 * math.min(1, (sinceSwing - 0.25) / 0.2)
		end
	elseif sinceThrow < 0.4 then
		if sinceThrow < 0.15 then
			arm = 2.8 * (sinceThrow / 0.15)
		else
			arm = 2.8 - 2.4 * math.min(1, (sinceThrow - 0.15) / 0.15)
		end
	else
		arm = walk * 0.6
	end
	set(rig, "ArmR", CFrame.Angles(arm, 0, 0))
end

local function animateAnimal(model: Model, rig, now: number)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return -- a carcass lies still
	end
	local root = rig.root
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local t = now + rig.phase
	local amt = math.clamp(speed / 14, 0, 1)
	local stride = math.sin(t * (6 + speed * 0.4)) * 0.6 * amt
	set(rig, "LegFL", CFrame.Angles(stride, 0, 0))
	set(rig, "LegBR", CFrame.Angles(stride, 0, 0))
	set(rig, "LegFR", CFrame.Angles(-stride, 0, 0))
	set(rig, "LegBL", CFrame.Angles(-stride, 0, 0))
	local sinceSwing = now - rig.swingAt
	local lunge = (sinceSwing >= 0 and sinceSwing < 0.4) and math.sin(sinceSwing / 0.4 * math.pi) * 0.5 or 0
	-- grazing when idle, bobbing when moving, lunging to bite
	local graze = amt < 0.1 and (math.sin(t * 0.4) > 0.3 and -0.5 or 0) or 0
	set(rig, "Head", CFrame.Angles(graze + math.sin(t * 7) * 0.08 * amt - lunge, 0, 0))
	set(rig, "Tail", CFrame.Angles(0, math.sin(t * 3) * 0.4, 0))
end

function Animator.init(app)
	App = app
	for _, model in ipairs(CollectionService:GetTagged("Dragon")) do
		register(model, "dragon")
	end
	for _, model in ipairs(CollectionService:GetTagged("Viking")) do
		register(model, "viking")
	end
	CollectionService:GetInstanceAddedSignal("Dragon"):Connect(function(m)
		register(m, "dragon")
	end)
	CollectionService:GetInstanceAddedSignal("Viking"):Connect(function(m)
		register(m, "viking")
	end)
	for _, model in ipairs(CollectionService:GetTagged("VikingPassenger")) do
		register(model, "passenger")
	end
	CollectionService:GetInstanceAddedSignal("VikingPassenger"):Connect(function(m)
		register(m, "passenger")
	end)
	-- the sparring golem swings its throwing arm like a viking
	local function maybeGolem(model)
		if model:GetAttribute("Kind") == "Golem" then
			register(model, "viking")
		end
	end
	for _, model in ipairs(CollectionService:GetTagged("TrainingDummy")) do
		maybeGolem(model)
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(maybeGolem)
	for _, model in ipairs(CollectionService:GetTagged("Animal")) do
		register(model, "animal")
	end
	CollectionService:GetInstanceAddedSignal("Animal"):Connect(function(m)
		register(m, "animal")
	end)
	CollectionService:GetInstanceRemovedSignal("Animal"):Connect(function(m)
		rigs[m] = nil
	end)
	CollectionService:GetInstanceRemovedSignal("Dragon"):Connect(function(m)
		rigs[m] = nil
	end)
	CollectionService:GetInstanceRemovedSignal("Viking"):Connect(function(m)
		rigs[m] = nil
	end)

	RunService.Stepped:Connect(function(_, dt)
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or Vector3.zero
		for model, rig in pairs(rigs) do
			if not model.Parent then
				rigs[model] = nil
			elseif rig.root and rig.root.Parent and (rig.root.Position - camPos).Magnitude < 320 then
				if rig.kind == "dragon" then
					animateDragon(model, rig, now, dt)
				elseif rig.kind == "animal" then
					animateAnimal(model, rig, now)
				else
					animateViking(model, rig, now)
				end
			end
		end
	end)
end

return Animator
