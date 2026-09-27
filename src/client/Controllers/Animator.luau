-- Procedural animation: flapping wings, swaying tails, walking legs for dragons, and walking /
-- chopping / throwing for vikings. Runs on each client by setting Motor6D.Transform.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Animator = {}

local rigs = {} -- [Model] = { kind, motors, phase, root, swingAt, throwAt }

local function register(model: Instance, kind: string)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local rig = { kind = kind, motors = {}, phase = math.random() * 10, root = nil, swingAt = -10, throwAt = -10 }
	rigs[model] = rig
	task.spawn(function()
		rig.root = model:WaitForChild("HumanoidRootPart", 10)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Motor6D") then
				rig.motors[d.Name] = d
			end
		end
	end)
	if kind == "viking" then
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

local function animateDragon(model: Model, rig, now: number)
	local root = rig.root
	local flying = model:GetAttribute("Flying") == true
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local t = now + rig.phase

	local flap, sweep
	if flying then
		flap = math.sin(t * 6.5) * 0.8 + 0.1
		sweep = 0.05
	else
		flap = 0.3 + math.sin(t * 1.4) * 0.05
		sweep = 0.85
	end
	set(rig, "WingR", CFrame.Angles(0, -sweep, 0) * CFrame.Angles(0, 0, flap))
	set(rig, "WingL", CFrame.Angles(0, sweep, 0) * CFrame.Angles(0, 0, -flap))

	for i = 1, 4 do
		local sway = math.sin(t * 2 - i * 0.8) * (flying and 0.08 or 0.14)
		set(rig, "Tail" .. i, CFrame.Angles(flying and 0.04 or 0, sway, 0))
	end

	if flying then
		set(rig, "LegFL", CFrame.Angles(-0.5, 0, 0))
		set(rig, "LegFR", CFrame.Angles(-0.5, 0, 0))
		set(rig, "LegBL", CFrame.Angles(-0.9, 0, 0))
		set(rig, "LegBR", CFrame.Angles(-0.9, 0, 0))
	else
		local amount = math.clamp(speed / 14, 0, 1)
		local swing = math.sin(t * (4 + speed * 0.25)) * 0.55 * amount
		set(rig, "LegFL", CFrame.Angles(swing, 0, 0))
		set(rig, "LegBR", CFrame.Angles(swing, 0, 0))
		set(rig, "LegFR", CFrame.Angles(-swing, 0, 0))
		set(rig, "LegBL", CFrame.Angles(-swing, 0, 0))
	end
end

local function animateViking(model: Model, rig, now: number)
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
	if sinceSwing >= 0 and sinceSwing < 0.55 then
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

function Animator.init()
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
	CollectionService:GetInstanceRemovedSignal("Dragon"):Connect(function(m)
		rigs[m] = nil
	end)
	CollectionService:GetInstanceRemovedSignal("Viking"):Connect(function(m)
		rigs[m] = nil
	end)

	RunService.Stepped:Connect(function()
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local camPos = camera and camera.CFrame.Position or Vector3.zero
		for model, rig in pairs(rigs) do
			if not model.Parent then
				rigs[model] = nil
			elseif rig.root and rig.root.Parent and (rig.root.Position - camPos).Magnitude < 320 then
				if rig.kind == "dragon" then
					animateDragon(model, rig, now)
				else
					animateViking(model, rig, now)
				end
			end
		end
	end)
end

return Animator
