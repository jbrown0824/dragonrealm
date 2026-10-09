-- Player input for combat: aiming, casting abilities, local cooldowns, and instant local
-- effects (the server decides what actually gets hit).
-- On the practice range (player attribute "RangeMode", RangeService) only Fireball works, on
-- Range.FIREBALL_COOLDOWN, and holding the left mouse button (or the breath button) fires it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatCalc = require(Shared.StatCalc)
local Range = require(Shared.Config.Range)
local DungeonInfo = require(Shared.Config.Dungeons)
local Remotes = require(Shared.Remotes)

local Combat = {}
local App

local player = Players.LocalPlayer
local cooldowns = {} -- [abilityId] = { readyAt, total }
local mouseHeld = false
local breathHeld = false
local breathInput = nil -- the touch/click that is holding the on-screen breath button
local projectileCounter = 0
local lastTouch = false
local lastRangeHint = 0
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
local mapParams = RaycastParams.new() -- the map and terrain only, like the server's (beams, waves)
mapParams.FilterType = Enum.RaycastFilterType.Include
mapParams.IgnoreWater = true

-- Keys for the action bar slots (HUD.abilityForSlot says what's in each).
local KEY_SLOTS = {
	[Enum.KeyCode.Q] = 2,
	[Enum.KeyCode.One] = 3,
	[Enum.KeyCode.Two] = 4,
	[Enum.KeyCode.Three] = 5,
	[Enum.KeyCode.Four] = 6,
	[Enum.KeyCode.Five] = 7,
}

function Combat.getCooldown(abilityId: string)
	local cd = cooldowns[abilityId]
	if not cd then
		return 0, 0
	end
	return math.max(0, cd.readyAt - os.clock()), cd.total
end

function Combat.setBreathHeld(held: boolean, input: InputObject?)
	breathHeld = held
	breathInput = held and input or nil
end

-- Touch screens have no mouse to aim with, so lock onto the enemy nearest to where the camera
-- is looking (within range and roughly in front), if there is one.
local AUTO_AIM_RANGE = 140
local function touchTarget(): Vector3?
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then
		return nil
	end
	local look = camera.CFrame.LookVector
	local best, bestScore = nil, -math.huge
	for _, tag in ipairs({ "Viking", "Animal", "TrainingDummy", "PracticeTarget" }) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local target = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			local owner = model:GetAttribute("OwnerUserId")
			if target and (not humanoid or humanoid.Health > 0) and (owner == nil or owner == player.UserId) then
				local offset = target.Position - root.Position
				local dist = offset.Magnitude
				if dist <= AUTO_AIM_RANGE and dist > 0.1 then
					local facing = look:Dot(offset.Unit)
					if facing > 0.35 then
						-- mostly "how centered", a little "how close"
						local score = facing * 2 - dist / AUTO_AIM_RANGE
						if score > bestScore then
							best, bestScore = target.Position, score
						end
					end
				end
			end
		end
	end
	return best
end

function Combat.aimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local screen
	if lastTouch then
		local target = touchTarget()
		if target then
			return target
		end
		screen = camera.ViewportSize / 2
	else
		screen = UserInputService:GetMouseLocation()
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local ignore = { workspace:FindFirstChild("ClientEffects"), workspace:FindFirstChild("Loot"), workspace:FindFirstChild("Barriers") }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	aimParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, aimParams)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * 250
end

local function castMap(from: Vector3, dir: Vector3)
	mapParams.FilterDescendantsInstances = { workspace:FindFirstChild("Map") or workspace.Terrain, workspace.Terrain }
	return workspace:Raycast(from, dir, mapParams)
end

local function mouthPosition(character: Model): Vector3
	local head = character:FindFirstChild("Head")
	local mouth = head and head:FindFirstChild("Mouth")
	if mouth then
		return mouth.WorldPosition
	end
	return character:GetPivot().Position
end

-- `aimAt` overrides the mouse / auto-aim (AFK practice aims for you).
function Combat.cast(abilityId: string?, aimAt: Vector3?)
	if not abilityId then
		return
	end
	local practicing = player:GetAttribute("RangeMode") ~= nil
	if practicing then
		if abilityId == "Breath" then
			abilityId = "Fireball" -- left click fires Fireball on the range
		elseif abilityId ~= "Fireball" then
			if os.clock() - lastRangeHint > 3 then
				lastRangeHint = os.clock()
				App.Notifications.toast("Only Fireball works on the practice range (left click or Q).", Color3.fromRGB(255, 200, 110), "🎯")
			end
			return
		end
	end
	local p = App.State.profile
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not p or not p.stats or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if character:GetAttribute("Stunned") then
		return
	end
	if not table.find(p.stats.abilities, abilityId) then
		return
	end
	local ability = StatCalc.resolveAbility(abilityId, p.class, p.stats)
	if not ability then
		return
	end
	local now = os.clock()
	local cd = cooldowns[abilityId]
	if cd and now < cd.readyAt then
		return
	end
	local cooldown = practicing and math.min(ability.cooldown, Range.FIREBALL_COOLDOWN) or ability.cooldown
	local cdTime = player:GetAttribute("NoCooldowns") and math.min(cooldown, 0.2) or cooldown
	cooldowns[abilityId] = { readyAt = now + cdTime, total = cdTime }

	local aim = aimAt or Combat.aimPoint()
	local projectileId = nil
	if ability.kind == "projectile" then
		projectileCounter += 1
		projectileId = player.UserId .. "_" .. projectileCounter
	end
	Remotes.event("CastAbility"):FireServer(abilityId, aim, projectileId)
	App.Movement.faceToward(aim, abilityId == "Breath" and 0.5 or 0.35)

	local origin = mouthPosition(character)
	if ability.kind == "breath" then
		local dir = aim - origin
		if dir.Magnitude < 1 then
			dir = root.CFrame.LookVector
		end
		App.VFX.breath(character, dir.Unit, p.class, ability.cooldown + 0.15)
		App.Sfx.play("Breath", 0.35)
	elseif ability.kind == "beam" then
		-- (the server's ray: to its range, or the first wall it meets)
		local dir = aim - origin
		if dir.Magnitude < 1 then
			dir = root.CFrame.LookVector
		end
		dir = dir.Unit
		local hit = castMap(origin, dir * ability.range)
		App.LegendFX.beam(character, hit and hit.Position or origin + dir * ability.range, p.class, ability.cooldown + 0.15)
		App.Sfx.play("Breath", 0.35)
	elseif ability.kind == "projectile" then
		if ability.ground then
			-- a wave rolls along the ground ahead of you (CombatService does the same)
			local down = castMap(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -200, 0))
			origin = (down and down.Position or Vector3.new(root.Position.X, 0, root.Position.Z)) + Vector3.new(0, 3, 0)
			aim = Vector3.new(aim.X, origin.Y, aim.Z)
		end
		local baseDir = aim - origin
		if baseDir.Magnitude < 1 then
			baseDir = root.CFrame.LookVector
		end
		baseDir = baseDir.Unit
		local count = ability.count or 1
		local spread = ability.spread or 0
		local list = {}
		for i = 1, count do
			local angle = 0
			if count > 1 then
				angle = -spread / 2 + spread * (i - 1) / (count - 1)
			end
			table.insert(list, { id = projectileId .. "_" .. i, dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(angle)) * baseDir })
		end
		App.VFX.projectiles({ origin = origin, list = list, speed = ability.speed, range = ability.range, size = ability.size, width = ability.width, classId = p.class, abilityId = abilityId, character = character })
		App.Sfx.play("Fireball", abilityId == "Breath" and 0.25 or 0.5)
	elseif ability.kind == "dash" then
		local d = aim - root.Position
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude < 0.5 then
			d = root.CFrame.LookVector
		end
		App.Movement.dash(d.Unit, ability.distance)
		App.VFX.dash({ character = character, from = root.Position, to = root.Position + d.Unit * ability.distance, classId = p.class })
	end
end

local function slotAbility(slot: number): string?
	return App.HUD.abilityForSlot(slot)
end

function Combat.init(app)
	App = app

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		lastTouch = inputType == Enum.UserInputType.Touch
	end)
	lastTouch = App.Windows.mobile or UserInputService:GetLastInputType() == Enum.UserInputType.Touch

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = true
			return
		end
		local slot = KEY_SLOTS[input.KeyCode]
		if slot then
			Combat.cast(slotAbility(slot))
		elseif input.KeyCode == Enum.KeyCode.K then
			App.Windows.toggle("SkillTree")
		elseif input.KeyCode == Enum.KeyCode.B then
			App.Windows.toggle("Inventory")
		elseif input.KeyCode == Enum.KeyCode.J then
			App.Windows.toggle("QuestLog")
		elseif input.KeyCode == Enum.KeyCode.H then
			App.HUD.goHome()
		elseif input.KeyCode == Enum.KeyCode.P then
			App.Windows.toggle("Pets")
		elseif input.KeyCode == Enum.KeyCode.L then
			App.Windows.toggle("Collection")
		elseif input.KeyCode == Enum.KeyCode.M then
			App.Windows.toggle("Map")
		elseif input.KeyCode == Enum.KeyCode.N then
			App.Map.toggleMini()
		elseif input.KeyCode == Enum.KeyCode.G then
			App.HUD.eat()
		elseif input.KeyCode == Enum.KeyCode.I then
			local p = App.State.profile
			if p and p.level >= DungeonInfo.UNLOCK_LEVEL then
				App.Windows.toggle("Dungeons")
			end
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
			App.Windows.close()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = false
			if breathInput and breathInput.UserInputType == Enum.UserInputType.MouseButton1 then
				breathHeld = false
			end
		elseif breathInput and input == breathInput then
			breathHeld = false
			breathInput = nil
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		mouseHeld = false
		breathHeld = false
	end)

	RunService.RenderStepped:Connect(function()
		if mouseHeld or breathHeld then
			Combat.cast("Breath")
		end
	end)

	player.CharacterAdded:Connect(function()
		cooldowns = {}
	end)
end

return Combat
