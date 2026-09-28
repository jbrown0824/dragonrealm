-- Remembers how far each dragon got in the tutorial (the client runs the steps; see
-- client/UI/Tutorial) and pays out a one-time reward for finishing it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local TutorialService = {}
local S

TutorialService.REWARD = { gold = 150, eggs = { EmberEgg = 1 } }
local MAX_STEP = 50

local function onStep(player: Player, step)
	local profile = S.PlayerService.getProfile(player)
	if not profile or type(step) ~= "number" then
		return
	end
	step = math.floor(step)
	if step == -1 or step == -2 then
		-- -1 = finished, -2 = skipped
		local finished = step == -1
		profile.tutorial = -1
		if finished and not profile.tutorialRewarded then
			profile.tutorialRewarded = true
			S.LootService.grant(player, TutorialService.REWARD)
			S.PlayerService.notify(player, "Tutorial complete! Here's 150 gold and a dragon egg. Open Pets (P), Eggs, to hatch it!", Color3.fromRGB(255, 215, 80), "🎓")
		end
	elseif step >= 0 and step <= MAX_STEP then
		profile.tutorial = step
	end
	S.PlayerService.markDirty(player)
end

function TutorialService.init(services)
	S = services
end

function TutorialService.start()
	Remotes.event("TutorialStep").OnServerEvent:Connect(onStep)
end

return TutorialService
