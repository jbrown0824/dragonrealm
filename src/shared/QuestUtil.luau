-- Quest availability rules shared by server and client.
-- Saved quest state: { active = { [questId] = progress }, done = { [questId] = timesCompleted } }

local Quests = require(script.Parent.Config.Quests)
local Pets = require(script.Parent.Config.Pets)

local QuestUtil = {}

function QuestUtil.isComplete(questId: string, state): boolean
	local quest = Quests.byId[questId]
	local progress = state.active[questId]
	return quest ~= nil and progress ~= nil and progress >= quest.objective.count
end

function QuestUtil.isAvailable(quest, state, level: number): boolean
	if state.active[quest.id] ~= nil then
		return false
	end
	if (state.done[quest.id] or 0) > 0 and not quest.repeatable then
		return false
	end
	if quest.after and (state.done[quest.after] or 0) == 0 then
		return false
	end
	return level >= (quest.minLevel or 1)
end

-- The next quest this giver would offer, or nil.
function QuestUtil.nextOffer(giverId: string, state, level: number)
	for _, quest in ipairs(Quests.List) do
		if quest.giver == giverId and QuestUtil.isAvailable(quest, state, level) then
			return quest
		end
	end
	return nil
end

-- A finished quest waiting to be handed in to this giver, or nil.
function QuestUtil.readyToTurnIn(giverId: string, state)
	for _, quest in ipairs(Quests.List) do
		if quest.giver == giverId and QuestUtil.isComplete(quest.id, state) then
			return quest
		end
	end
	return nil
end

-- For the marker over a giver's head: "turnin" (?), "available" (!), "active" (…), or "none".
function QuestUtil.giverState(giverId: string, state, level: number): string
	if QuestUtil.readyToTurnIn(giverId, state) then
		return "turnin"
	end
	if QuestUtil.nextOffer(giverId, state, level) then
		return "available"
	end
	for questId in pairs(state.active) do
		local quest = Quests.byId[questId]
		if quest and quest.giver == giverId then
			return "active"
		end
	end
	return "none"
end

-- Returns true when this quest has no offer yet only because the player is too low level.
function QuestUtil.lockedByLevel(giverId: string, state, level: number)
	for _, quest in ipairs(Quests.List) do
		if quest.giver == giverId and QuestUtil.isAvailable(quest, state, 999) and level < (quest.minLevel or 1) then
			return quest
		end
	end
	return nil
end

function QuestUtil.objectiveText(quest, progress: number?): string
	local o = quest.objective
	local p = math.min(progress or 0, o.count)
	return string.format("%s  (%d/%d)", quest.name, p, o.count)
end

function QuestUtil.rewardText(quest): string
	local r = quest.rewards
	local parts = {}
	if r.xp then
		table.insert(parts, r.xp .. " XP")
	end
	if r.gold then
		table.insert(parts, r.gold .. " Gold")
	end
	if r.gear then
		table.insert(parts, r.gear.rarity .. " Gear")
	end
	if r.seeds then
		for seedId, n in pairs(r.seeds) do
			table.insert(parts, n .. "x " .. seedId .. " Seed")
		end
	end
	if r.eggs then
		for eggId, n in pairs(r.eggs) do
			local egg = Pets.Eggs[eggId]
			table.insert(parts, n .. "x " .. (egg and egg.name or eggId))
		end
	end
	return table.concat(parts, "  •  ")
end

return QuestUtil
