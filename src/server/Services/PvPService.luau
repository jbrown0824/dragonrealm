-- Battle Zone PvP rewards: Glory, gold, kill streaks and server announcements.
-- Who can hit whom is decided in CombatService.canPvP (both players inside the Battle Zone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local PvPService = {}
local S

local STREAK_NAMES = {
	[3] = "is on a rampage",
	[5] = "is DOMINATING",
	[8] = "is UNSTOPPABLE",
	[12] = "is LEGENDARY",
}

function PvPService.onKill(killer: Player, victim: Player)
	if killer == victim then
		return
	end
	local killerSt = S.PlayerService.state[killer]
	local victimSt = S.PlayerService.state[victim]
	local victimProfile = S.PlayerService.getProfile(victim)
	if not killerSt or not victimProfile then
		return
	end

	local endedStreak = victimSt and victimSt.streak or 0
	if victimSt then
		victimSt.streak = 0
	end
	killerSt.streak += 1

	local glory = 1 + (endedStreak >= 3 and 2 or 0)
	S.PlayerService.addGlory(killer, glory)
	local gold = S.PlayerService.addGold(killer, 20 + 5 * victimProfile.level)
	S.QuestService.progress(killer, "pvpKill", nil, 1)

	S.PlayerService.notify(killer, string.format("You defeated %s! +%d Glory, +%d gold", victim.DisplayName, glory, gold), Color3.fromRGB(255, 120, 100), "⚔️")
	S.PlayerService.notify(victim, string.format("%s defeated you in the Battle Zone.", killer.DisplayName), Color3.fromRGB(255, 160, 160), "💀")

	local announce = Remotes.event("Announce")
	local streakText = STREAK_NAMES[killerSt.streak]
	if streakText then
		announce:FireAllClients({
			title = "⚔️ BATTLE ZONE",
			text = string.format("%s %s! (%d wins in a row)", killer.DisplayName, streakText, killerSt.streak),
			color = Color3.fromRGB(255, 90, 90),
			duration = 4,
		})
	elseif endedStreak >= 3 then
		announce:FireAllClients({
			title = "⚔️ BATTLE ZONE",
			text = string.format("%s ended %s's %d-win streak!", killer.DisplayName, victim.DisplayName, endedStreak),
			color = Color3.fromRGB(255, 90, 90),
			duration = 4,
		})
	end
end

function PvPService.init(services)
	S = services
end

return PvPService
