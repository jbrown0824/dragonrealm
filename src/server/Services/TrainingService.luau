-- Training grounds in town. Straw dummies (tag "TrainingDummy") can be hit by anything and
-- never die; each dragon gets a live DPS meter for the dummy they're hitting. The sparring
-- golem inside the fenced pen also throws practice axes at any dragon standing in the pen:
-- they hurt (even in town) but can never take you below 1 health.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Remotes = require(Shared.Remotes)

local TrainingService = {}
local S

local sessions = {} -- [Player] = { [Model] = { start, last, total, sent } }
local golem = nil
local IDLE_RESET = 5
local GOLEM_INTERVAL = 1.8
local GOLEM_HIT = 0.08 -- fraction of the victim's max health (before defense)

local function sendStats(player: Player, dummy: Model, s, final: boolean?)
	local t = os.clock()
	local elapsed = math.max(1, (final and s.last or t) - s.start)
	Remotes.event("DummyStats"):FireClient(player, {
		dummy = dummy,
		dps = s.total / elapsed,
		total = s.total,
		time = elapsed,
		final = final == true,
	})
	s.sent = t
end

local function onHit(dummy: Model, player: Player, amount: number)
	local perPlayer = sessions[player]
	if not perPlayer then
		perPlayer = {}
		sessions[player] = perPlayer
	end
	local t = os.clock()
	local s = perPlayer[dummy]
	if not s or t - s.last > IDLE_RESET then
		s = { start = t, last = t, total = 0, sent = 0 }
		perPlayer[dummy] = s
	end
	s.total += amount
	s.last = t
	if t - s.sent >= 0.25 then
		sendStats(player, dummy, s)
	end
end

local function registerDummy(model: Model)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	local isGolem = model:GetAttribute("Kind") == "Golem"
	local info = S.EnemyService.register(model, humanoid, root, {
		kind = "dummy",
		dummy = true,
		displayName = isGolem and "🥊 Sparring Golem" or "🎯 Training Dummy",
		level = 1,
		scale = model:GetAttribute("Scale") or 1.4,
		radius = 2.4,
		height = model:GetAttribute("Height") or 7,
		tagOffset = 3,
		def = { name = model.Name, defense = 0 },
		onHit = function(player, amount)
			onHit(model, player, amount)
		end,
	})
	if isGolem then
		golem = info
	end
end

local function inPen(pos: Vector3): boolean
	local pen = Zones.Training.pen
	return pos.X >= pen.min.X and pos.X <= pen.max.X and pos.Z >= pen.min.Z and pos.Z <= pen.max.Z and pos.Y < 45
end

function TrainingService.init(services)
	S = services
end

function TrainingService.start()
	for _, model in ipairs(CollectionService:GetTagged("TrainingDummy")) do
		registerDummy(model)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)

	local nextThrow = 0
	while true do
		task.wait(0.25)
		local t = os.clock()
		-- Finish meters that have gone quiet so the client can show the final result.
		for player, perPlayer in pairs(sessions) do
			for dummy, s in pairs(perPlayer) do
				if t - s.last > IDLE_RESET then
					if player.Parent then
						sendStats(player, dummy, s, true)
					end
					perPlayer[dummy] = nil
				end
			end
		end
		-- Sparring golem
		if golem and t >= nextThrow then
			nextThrow = t + GOLEM_INTERVAL
			for _, player in ipairs(Players:GetPlayers()) do
				local character, humanoid, root = S.PlayerService.getCharacter(player)
				if character and inPen(root.Position) then
					S.EnemyService.throwAt(golem, player, root, humanoid.MaxHealth * GOLEM_HIT, "axe", { ignoreSafe = true, nonLethal = true })
				end
			end
		end
	end
end

return TrainingService
