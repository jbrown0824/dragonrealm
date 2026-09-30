-- Quests from the village dragons. Talking to a quest giver opens a dialog on the client;
-- the client asks to accept or turn in, and this service checks the rules in QuestUtil.
-- Other services report progress with QuestService.progress(player, type, target, amount).
-- During a night raid the quest givers in town are busy fighting (RaidService) and don't talk
-- quests; the keepers at the dungeon entrances are far from it all and always do.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Raids = require(Shared.Config.Raids)
local Zones = require(Shared.Config.Zones)
local QuestUtil = require(Shared.QuestUtil)
local Remotes = require(Shared.Remotes)

local QuestService = {}
local S

local GIVER_RANGE = 40

local function nearGiver(player: Player, giverId: string): boolean
	local _, _, root = S.PlayerService.getCharacter(player)
	local spot = Zones.QuestGivers[giverId]
	return root ~= nil and spot ~= nil and (root.Position - spot.position).Magnitude <= GIVER_RANGE
end

-- Report progress. `set` = true replaces progress with `amount` (used for "reach level N").
function QuestService.progress(player: Player, objectiveType: string, target: string?, amount: number, set: boolean?)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	local active = profile.quests.active
	local changed = false
	for questId, progress in pairs(active) do
		local quest = Quests.byId[questId]
		if quest and quest.objective.type == objectiveType then
			local want = quest.objective.target
			if want == nil or want == "any" or want == target then
				local count = quest.objective.count
				if progress < count then
					local newProgress = set and amount or (progress + amount)
					newProgress = math.min(newProgress, count)
					if newProgress ~= progress then
						active[questId] = newProgress
						changed = true
						if newProgress >= count then
							local giver = Quests.Givers[quest.giver]
							S.PlayerService.notify(player, string.format("Quest complete: %s! Return to %s.", quest.name, giver.name), Color3.fromRGB(255, 220, 90), "📜")
						end
					end
				end
			end
		end
	end
	if changed then
		S.PlayerService.markDirty(player)
	end
end

local function onAccept(player: Player, questId)
	local profile = S.PlayerService.getProfile(player)
	local quest = type(questId) == "string" and Quests.byId[questId]
	if not profile or not quest then
		return false, "Unknown quest."
	end
	if S.RaidService.isActive() and not Quests.Givers[quest.giver].dungeon then
		return false, Raids.QUEST_BUSY
	end
	if not nearGiver(player, quest.giver) then
		return false, "Talk to " .. Quests.Givers[quest.giver].name .. " to accept this quest."
	end
	local state = profile.quests
	if not QuestUtil.isAvailable(quest, state, profile.level) then
		return false, "You can't take that quest right now."
	end
	local activeCount = 0
	for _ in pairs(state.active) do
		activeCount += 1
	end
	if activeCount >= Quests.MAX_ACTIVE then
		return false, string.format("You can only have %d quests at once.", Quests.MAX_ACTIVE)
	end
	local start = 0
	if quest.objective.type == "level" then
		start = math.min(profile.level, quest.objective.count)
	end
	state.active[questId] = start
	S.PlayerService.markDirty(player)
	-- Some objectives may already be satisfied (e.g. standing in the zone right now).
	if quest.objective.type == "visitZone" then
		local st = S.PlayerService.state[player]
		if st and st.zoneId == quest.objective.target then
			QuestService.progress(player, "visitZone", st.zoneId, 1)
		end
	end
	return true
end

local function onTurnIn(player: Player, questId)
	local profile = S.PlayerService.getProfile(player)
	local quest = type(questId) == "string" and Quests.byId[questId]
	if not profile or not quest then
		return false, "Unknown quest."
	end
	if S.RaidService.isActive() and not Quests.Givers[quest.giver].dungeon then
		return false, Raids.QUEST_BUSY
	end
	if not nearGiver(player, quest.giver) then
		return false, "Return to " .. Quests.Givers[quest.giver].name .. " to turn this in."
	end
	local state = profile.quests
	if not QuestUtil.isComplete(questId, state) then
		return false, "That quest isn't finished yet."
	end
	state.active[questId] = nil
	state.done[questId] = (state.done[questId] or 0) + 1
	S.LootService.grant(player, quest.rewards)
	S.PlayerService.notify(player, "Quest rewards: " .. QuestUtil.rewardText(quest), Color3.fromRGB(255, 220, 90), "🏆")
	S.PlayerService.markDirty(player)
	return true
end

local function onAbandon(player: Player, questId)
	local profile = S.PlayerService.getProfile(player)
	if not profile or type(questId) ~= "string" or profile.quests.active[questId] == nil then
		return false
	end
	profile.quests.active[questId] = nil
	S.PlayerService.markDirty(player)
	return true
end

function QuestService.init(services)
	S = services
end

function QuestService.start()
	Remotes.func("AcceptQuest").OnServerInvoke = onAccept
	Remotes.func("TurnInQuest").OnServerInvoke = onTurnIn
	Remotes.func("AbandonQuest").OnServerInvoke = onAbandon

	for _, prompt in ipairs(CollectionService:GetTagged("QuestPrompt")) do
		prompt.Triggered:Connect(function(player)
			local giver = Quests.Givers[prompt:GetAttribute("GiverId") or ""]
			if S.RaidService.isActive() and not (giver and giver.dungeon) then
				S.PlayerService.notify(player, Raids.QUEST_BUSY, Color3.fromRGB(255, 150, 110), "⚔️")
				return
			end
			Remotes.event("OpenQuestDialog"):FireClient(player, prompt:GetAttribute("GiverId"))
		end)
	end
end

return QuestService
