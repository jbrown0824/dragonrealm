-- Flight, dashing and turning to face your aim. The client owns its dragon's physics, so all
-- of this runs locally with LinearVelocity / AlignOrientation on the HumanoidRootPart.
-- In a dungeon (player attribute InDungeon) wings only lift you Dungeons.HOVER_HEIGHT off the floor
-- until its boss is down (DungeonCleared): no flying over the monsters or hiding by the ceiling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Dungeons = require(Shared.Config.Dungeons)
local Remotes = require(Shared.Remotes)

local Movement = {}
local App

local player = Players.LocalPlayer
local controls = nil
local character, humanoid, root
local attachment, linear, align
local flying = false
local stamina, maxStamina = 100, 100
local touchVertical = 0
local faceTarget: Vector3? = nil
local faceUntil = 0
local dashUntil = 0
local dashVelocity = Vector3.zero
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function alive(): boolean
	return character ~= nil and humanoid ~= nil and root ~= nil and humanoid.Health > 0 and character.Parent ~= nil
end

local function lowCeiling(): boolean
	return player:GetAttribute("InDungeon") ~= nil and not player:GetAttribute("DungeonCleared")
end
local hoverToldRun = nil -- (the "wings only lift you a little" hint, once per run)

function Movement.getStamina()
	return stamina, maxStamina
end

function Movement.isFlying(): boolean
	return flying
end

function Movement.setVertical(v: number)
	touchVertical = v
end

function Movement.faceToward(pos: Vector3, duration: number)
	faceTarget = pos
	faceUntil = os.clock() + duration
end

function Movement.dash(direction: Vector3, distance: number)
	if not alive() then
		return
	end
	local duration = 0.22
	dashVelocity = direction.Unit * (distance / duration)
	dashUntil = os.clock() + duration
end

local function startFlight()
	if not alive() or flying or stamina < 8 then
		return
	end
	if character:GetAttribute("Stunned") then
		return
	end
	flying = true
	humanoid.PlatformStand = true
	linear.Enabled = true
	align.Enabled = true
	root.AssemblyLinearVelocity += Vector3.new(0, 20, 0)
	Remotes.event("SetFlying"):FireServer(true)
	if lowCeiling() and hoverToldRun ~= player:GetAttribute("DungeonRun") then
		hoverToldRun = player:GetAttribute("DungeonRun")
		App.Notifications.toast("The cave is too tight to fly: your wings only lift you a little until its boss is down.", Color3.fromRGB(120, 200, 255), "💨")
	end
end

local function stopFlight()
	if not flying then
		return
	end
	flying = false
	if alive() then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if linear then
		linear.Enabled = false
	end
	if align then
		align.Enabled = false
	end
	Remotes.event("SetFlying"):FireServer(false)
end

-- Stop flying (a dungeon boss's harpoon dragged you down).
function Movement.land()
	stopFlight()
end

function Movement.toggleFlight()
	if flying then
		stopFlight()
	else
		startFlight()
	end
end

-- Dragons are far bigger than Roblox avatars, so the default camera starts inside the tail.
-- Push the camera about a body length back for the first dragon of the session (raising the
-- minimum zoom pushes the camera out to it; then the player may zoom back in). Respawns and
-- new dragon types keep whatever zoom the player picked.
local framed = false
function Movement.frameDragon(newCharacter: Model)
	player.CameraMaxZoomDistance = Game.CAMERA_MAX_ZOOM
	if framed then
		player.CameraMinZoomDistance = Game.CAMERA_MIN_ZOOM
		return
	end
	framed = true
	local _, size = newCharacter:GetBoundingBox() -- built facing -Z, so Z is nose to tail
	local start = math.clamp(size.Z * Game.CAMERA_START_ZOOM + 6, Game.CAMERA_MIN_ZOOM, Game.CAMERA_MAX_ZOOM)
	player.CameraMinZoomDistance = start
	task.delay(0.5, function()
		player.CameraMinZoomDistance = Game.CAMERA_MIN_ZOOM
	end)
end

local function setupCharacter(newCharacter: Model)
	flying = false
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	root = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	groundParams.FilterDescendantsInstances = { newCharacter }
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	attachment = Instance.new("Attachment")
	attachment.Name = "MoveAttachment"
	attachment.Parent = root

	linear = Instance.new("LinearVelocity")
	linear.Attachment0 = attachment
	linear.MaxForce = math.huge
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.Enabled = false
	linear.Parent = root

	align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 22
	align.Enabled = false
	align.Parent = root

	maxStamina = newCharacter:GetAttribute("MaxStamina") or 100
	stamina = maxStamina
	newCharacter:GetAttributeChangedSignal("MaxStamina"):Connect(function()
		maxStamina = newCharacter:GetAttribute("MaxStamina") or maxStamina
	end)
	humanoid.Died:Connect(function()
		flying = false
	end)
	-- Make sure the camera follows the new dragon.
	workspace.CurrentCamera.CameraSubject = humanoid
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	Movement.frameDragon(newCharacter)
end

local function flatLook(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function step(dt: number)
	if not alive() or not linear then
		return
	end
	local now = os.clock()
	local camera = workspace.CurrentCamera

	-- Stamina
	if flying then
		stamina -= Game.FLIGHT_DRAIN * dt
		if stamina <= 0 then
			stamina = 0
			stopFlight()
			App.Notifications.toast("Your wings are tired! Land to rest them.", Color3.fromRGB(120, 200, 255), "💨")
		end
	else
		stamina = math.min(maxStamina, stamina + Game.FLIGHT_REGEN * dt)
	end

	-- Dash overrides everything for a moment.
	if now < dashUntil then
		linear.Enabled = true
		linear.VectorVelocity = dashVelocity
		align.Enabled = true
		align.CFrame = CFrame.lookAt(Vector3.zero, flatLook(dashVelocity, root.CFrame.LookVector))
		humanoid.AutoRotate = false
		return
	end

	if flying then
		local move = controls and controls:GetMoveVector() or Vector3.zero
		local camCF = camera.CFrame
		local dir = camCF.LookVector * -move.Z + camCF.RightVector * move.X
		local vertical = touchVertical
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				vertical += 1
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
				vertical -= 1
			end
		end
		dir += Vector3.new(0, math.clamp(vertical, -1, 1), 0)
		local ws = humanoid.WalkSpeed
		local flightMult = character:GetAttribute("FlightSpeedMult") or 1
		local speed = ws > 0 and (ws * Game.FLIGHT_SPEED_MULT + Game.FLIGHT_SPEED_BONUS) * flightMult or 0
		local velocity = dir.Magnitude > 0.05 and dir.Unit * speed or Vector3.new(0, math.sin(now * 2) * 1.2, 0)
		if root.Position.Y > Game.MAX_FLIGHT_HEIGHT and velocity.Y > 0 then
			velocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
		if lowCeiling() then
			-- a low hover only: no climbing past HOVER_HEIGHT, and eased back down if above it
			local hip = humanoid.HipHeight + root.Size.Y / 2
			local floor = workspace:Raycast(root.Position, Vector3.new(0, -(hip + Dungeons.HOVER_HEIGHT + 40), 0), groundParams)
			if floor then
				local over = root.Position.Y - floor.Position.Y - hip - Dungeons.HOVER_HEIGHT
				if over > 0 and velocity.Y > 0 then
					velocity = Vector3.new(velocity.X, 0, velocity.Z)
				end
				if over > 1 then
					velocity = Vector3.new(velocity.X, math.min(velocity.Y, -over * 4), velocity.Z)
				end
			end
		end
		linear.VectorVelocity = velocity

		-- Land automatically when descending onto the ground.
		if velocity.Y < -1 then
			local hip = humanoid.HipHeight + root.Size.Y / 2
			local ray = workspace:Raycast(root.Position, Vector3.new(0, -(hip + 1.5), 0), groundParams)
			if ray then
				stopFlight()
				return
			end
		end

		local lookDir = (now < faceUntil and faceTarget) and flatLook(faceTarget - root.Position, camCF.LookVector) or flatLook(camCF.LookVector, root.CFrame.LookVector)
		local pitch = speed > 0 and math.clamp(velocity.Y / speed, -0.8, 0.8) * 0.45 or 0
		local roll = -move.X * 0.35
		align.CFrame = CFrame.lookAt(Vector3.zero, lookDir) * CFrame.Angles(pitch, 0, roll)
		align.Enabled = true
		return
	end

	-- On the ground
	linear.Enabled = false
	if now < faceUntil and faceTarget then
		align.Enabled = true
		align.CFrame = CFrame.lookAt(Vector3.zero, flatLook(faceTarget - root.Position, root.CFrame.LookVector))
		humanoid.AutoRotate = false
	else
		align.Enabled = false
		humanoid.AutoRotate = true
	end
end

function Movement.init(app)
	App = app
	task.spawn(function()
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		end)
		if ok and module then
			controls = module:GetControls()
		end
	end)

	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			Movement.toggleFlight()
		elseif input.KeyCode == Enum.KeyCode.Space and not flying and alive() then
			local state = humanoid:GetState()
			if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
				startFlight()
			end
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return Movement
