-- Wild animals in the hunting grounds (Zones.HuntingGrounds). EnemyService runs their AI;
-- this service keeps each area stocked and turns kills into carcasses. A carcass has two
-- prompts: Eat (refills hunger now) and Pack Meat (puts the meat in your food bag). For the
-- first few seconds only the dragon that made the kill can use it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Food = require(Shared.Config.Food)
local Zones = require(Shared.Config.Zones)

local AnimalBuilder = require(script.Parent.Parent.World.AnimalBuilder)

local WildlifeService = {}
local S

local CARCASS_TIME = 50
local KILLER_ONLY_TIME = 12

local spawnAnimal

local function randomSpot(area): Vector3?
	for _ = 1, 20 do
		local pos = Vector3.new(
			area.min.X + math.random() * (area.max.X - area.min.X),
			0,
			area.min.Z + math.random() * (area.max.Z - area.min.Z)
		)
		local ok = S.EnemyService.isGoodSpawn(pos)
		if ok then
			return pos
		end
	end
	return nil
end

local function makeCarcass(e, killer: Player?)
	local def = e.def
	local meat = Food.get(def.meat)
	local model = e.model
	-- Lay the body on its side where it fell.
	local root = e.root
	local ground = S.EnemyService.terrainGround(root.Position)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			if p.Transparency < 1 then
				p.Color = p.Color:Lerp(Color3.fromRGB(60, 40, 35), 0.25)
			end
		end
	end
	local yaw = root.CFrame.Rotation
	model:PivotTo(CFrame.new(ground + Vector3.new(0, e.scale * 0.9, 0)) * yaw * CFrame.Angles(0, 0, math.rad(88)))

	local used = false
	local prompts = {}
	local function makePrompt(action: string, key: Enum.KeyCode, offset: number)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = action
		prompt.ObjectText = def.name
		prompt.KeyboardKeyCode = key
		prompt.HoldDuration = 0.8
		prompt.MaxActivationDistance = 14 + e.scale * 2
		prompt.RequiresLineOfSight = false
		prompt.UIOffset = Vector2.new(0, offset)
		if killer then
			prompt:SetAttribute("OwnerUserId", killer.UserId)
		end
		prompt.Parent = root
		table.insert(prompts, prompt)
		return prompt
	end
	local eat = makePrompt(string.format("🍖 Eat (+%d hunger)", meat.food), Enum.KeyCode.E, 0)
	local pack = makePrompt("🎒 Pack " .. meat.name, Enum.KeyCode.R, 70)

	local function finish()
		if used then
			return
		end
		used = true
		for _, p in ipairs(prompts) do
			p:Destroy()
		end
		S.CombatService.broadcastVFX({ kind = "enemyDeath", pos = root.Position })
		S.EnemyService.forget(e)
	end
	local function allowed(player: Player): boolean
		local owner = eat:GetAttribute("OwnerUserId")
		return not used and (owner == nil or owner == player.UserId)
	end
	eat.Triggered:Connect(function(player)
		if allowed(player) then
			local profile = S.PlayerService.getProfile(player)
			if profile and profile.hunger >= Game.HUNGER_MAX - 1 then
				S.PlayerService.notify(player, "You're full! Pack the meat for later instead [R].", Color3.fromRGB(255, 220, 140), "🍖")
				return
			end
			S.SurvivalService.feed(player, meat.food)
			S.PlayerService.notify(player, string.format("You ate the %s. (+%d hunger)", def.name, meat.food), meat.color, "😋")
			finish()
		end
	end)
	pack.Triggered:Connect(function(player)
		if allowed(player) then
			if S.SurvivalService.addFood(player, def.meat, 1) then
				S.PlayerService.notify(player, string.format("Packed %s %s for later. Eat it with G.", meat.icon, meat.name), meat.color, "🎒")
			end
			finish()
		end
	end)
	task.delay(KILLER_ONLY_TIME, function()
		for _, p in ipairs(prompts) do
			if p.Parent then
				p:SetAttribute("OwnerUserId", nil)
			end
		end
	end)
	task.delay(CARCASS_TIME, finish)
	if killer then
		S.PlayerService.notify(killer, string.format("You hunted a %s! Hold E to eat it, or R to pack the meat.", def.name), Color3.fromRGB(200, 240, 170), "🏹")
	end
end

spawnAnimal = function(area, typeId: string)
	local def = Animals.get(typeId)
	local pos = randomSpot(area)
	if not def or not pos then
		task.delay(10, function()
			spawnAnimal(area, typeId)
		end)
		return
	end
	local level = math.random(area.levels[1], area.levels[2])
	S.EnemyService.spawn(typeId, level, pos, {
		def = def,
		kind = "animal",
		tag = "Animal",
		builder = AnimalBuilder.build,
		area = area,
		keepBody = true,
		leash = 140,
		aggroRange = def.aggroRange,
		tagOffset = (def.look.bodyH + 1.4) * def.scale,
		radius = math.max(def.look.bodyW, def.look.bodyL * 0.5) * 0.7 * def.scale,
		height = (def.look.legLen + def.look.bodyH) * def.scale,
		onDeath = function(e, killer)
			makeCarcass(e, killer)
			task.delay(Game.ANIMAL_RESPAWN + math.random() * 20, function()
				spawnAnimal(area, typeId)
			end)
		end,
	})
end

function WildlifeService.init(services)
	S = services
end

function WildlifeService.start()
	task.wait(2) -- let the map settle so ground raycasts see the terrain
	for _, area in ipairs(Zones.HuntingGrounds) do
		for typeId, count in pairs(area.spawns) do
			for _ = 1, count do
				spawnAnimal(area, typeId)
			end
		end
	end
end

return WildlifeService
