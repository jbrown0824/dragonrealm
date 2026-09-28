-- Fishing. Fishing spots (tagged "FishingSpot", built by WorldBuilder from Zones.FishingSpots)
-- have a 🎣 prompt. Using it casts a line; after a few seconds a fish bites and the client runs
-- a quick reel minigame (stop the needle in the green zone). Land it and the fish goes into your
-- food bag. Moving away or getting hit makes you lose your line.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Food = require(Shared.Config.Food)
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local FishingService = {}
local S

local sessions = {} -- [Player] = { spot, token, state = "waiting" | "bite", biteAt, startHealth }
local MAX_DISTANCE = 24
local REEL_WINDOW = 6 -- seconds after the bite to finish the minigame
local counter = 0

local spots = {}
for _, spot in ipairs(Zones.FishingSpots) do
	spots[spot.id] = spot
end

local function send(player: Player, data)
	Remotes.event("Fishing"):FireClient(player, data)
end

local function stop(player: Player, reason: string?)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	player:SetAttribute("Fishing", nil)
	send(player, { phase = "stop", reason = reason })
end

local function start(player: Player, spotId: string)
	local spot = spots[spotId]
	local _, humanoid, root = S.PlayerService.getCharacter(player)
	if not spot or not root then
		return
	end
	if sessions[player] then
		stop(player, nil)
	end
	local flat = Vector3.new(root.Position.X - spot.pos.X, 0, root.Position.Z - spot.pos.Z)
	if flat.Magnitude > MAX_DISTANCE + 6 then
		S.PlayerService.notify(player, "Get closer to the fishing spot!", Color3.fromRGB(170, 210, 255), "🎣")
		return
	end
	counter += 1
	local token = counter
	local session = { spot = spot, token = token, state = "waiting", startHealth = humanoid.Health }
	sessions[player] = session
	player:SetAttribute("Fishing", spot.id)
	send(player, { phase = "cast", pos = spot.pos, kind = spot.kind })
	S.CombatService.broadcastVFX({ kind = "splash", pos = spot.pos })
	task.delay(2.5 + math.random() * 4, function()
		if sessions[player] ~= session then
			return
		end
		session.state = "bite"
		session.biteAt = os.clock()
		session.fish = Util.weightedPick(Food.FishTables[spot.kind] or Food.FishTables.River)
		local difficulty = Food.FishingDifficulty[spot.kind] or Food.FishingDifficulty.River
		send(player, { phase = "bite", token = token, zone = difficulty.zone, speed = difficulty.speed, window = REEL_WINDOW - 1 })
		S.CombatService.broadcastVFX({ kind = "splash", pos = spot.pos, big = true })
		task.delay(REEL_WINDOW, function()
			if sessions[player] == session then
				stop(player, "The fish got away!")
			end
		end)
	end)
end

local function onAction(player: Player, action, token, success)
	local session = sessions[player]
	if not session then
		return
	end
	if action == "cancel" then
		stop(player, nil)
		return
	end
	if action ~= "reel" or session.state ~= "bite" or token ~= session.token then
		return
	end
	if os.clock() - session.biteAt > REEL_WINDOW + 0.5 then
		stop(player, "Too slow! The fish got away.")
		return
	end
	local fishId = session.fish
	sessions[player] = nil
	player:SetAttribute("Fishing", nil)
	if success ~= true then
		send(player, { phase = "stop", reason = "It slipped off the hook!" })
		return
	end
	local fish = Food.get(fishId)
	local profile = S.PlayerService.getProfile(player)
	if profile then
		profile.fishCaught += 1
	end
	local kept = S.SurvivalService.addFood(player, fishId, 1)
	send(player, { phase = "caught", fish = fishId })
	if kept then
		S.PlayerService.notify(player, string.format("You caught a %s %s! (in your food bag: G to eat, or sell it)", fish.icon, fish.name), fish.color, "🎣")
	end
	S.PlayerService.addXP(player, 10 + fish.sell * 0.4)
	S.QuestService.progress(player, "fish", fishId, 1)
	S.CombatService.broadcastVFX({ kind = "splash", pos = session.spot.pos, big = true })
end

function FishingService.init(services)
	S = services
end

function FishingService.start()
	Remotes.event("FishingAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)

	local function hook(part: Instance)
		local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
		local spotId = part:GetAttribute("SpotId")
		if prompt and spotId then
			prompt.Triggered:Connect(function(player)
				start(player, spotId)
			end)
		end
	end
	for _, part in ipairs(CollectionService:GetTagged("FishingSpot")) do
		hook(part)
	end

	-- Lose your line if you wander off, fly away or get hurt.
	while true do
		task.wait(0.3)
		for player, session in pairs(sessions) do
			local character, humanoid, root = S.PlayerService.getCharacter(player)
			if not character then
				stop(player, nil)
			else
				local flat = Vector3.new(root.Position.X - session.spot.pos.X, 0, root.Position.Z - session.spot.pos.Z)
				if flat.Magnitude > MAX_DISTANCE + 10 or character:GetAttribute("Flying") then
					stop(player, "You reeled in your line.")
				elseif humanoid.Health < session.startHealth - 1 then
					stop(player, "Ouch! You dropped your line.")
				end
			end
		end
	end
end

return FishingService
