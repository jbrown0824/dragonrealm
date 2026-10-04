-- Tracks which area each dragon is in: shows zone names, flags the Battle Zone for PvP,
-- keeps flyers inside the map, and keeps non-participants out of the Boss Arena. Dragons in a
-- dungeon run are off the map on purpose (DungeonService keeps them inside their cave).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)
local Remotes = require(Shared.Remotes)

local ZoneService = {}
local S

local function inArena(pos: Vector3): boolean
	local c = Zones.BossArena.center
	local dx, dz = pos.X - c.X, pos.Z - c.Z
	return dx * dx + dz * dz <= (Zones.BossArena.radius + 30) ^ 2 and pos.Y < c.Y + Zones.BossArena.wallHeight + 40 and pos.Y > c.Y - 60
end

local function check(player: Player)
	local st = S.PlayerService.state[player]
	local character, _, root = S.PlayerService.getCharacter(player)
	if not st or not character then
		return
	end
	local pos = root.Position
	local fighting = S.BossService.isInFight(player)
	local dungeon = player:GetAttribute("InDungeon")
	if dungeon then
		local id = "Dungeon:" .. dungeon
		if st.zoneId ~= id then
			st.zoneId = id
			player:SetAttribute("InBattleZone", false)
			character:SetAttribute("InBattleZone", false)
			Remotes.event("ZoneChanged"):FireClient(player, id)
		end
		return
	end

	if fighting then
		if not inArena(pos) then
			S.PlayerService.teleport(player, S.BossService.getArenaSpawn(player))
		end
	elseif inArena(pos) then
		S.PlayerService.teleport(player, S.PlayerService.getSpawnCFrame(player))
		S.PlayerService.notify(player, "Only dragons who joined the boss queue can enter the arena.", Color3.fromRGB(255, 150, 120), "⛔")
		return
	elseif not Zones.inWorld(pos) then
		S.PlayerService.teleport(player, S.PlayerService.getSpawnCFrame(player))
		S.PlayerService.notify(player, "You flew too far and got lost! Back to town.", Color3.fromRGB(255, 200, 120), "🧭")
		return
	end

	local area = Zones.areaAt(pos)
	local id = area and area.id or "Wilds"
	local pvp = area ~= nil and area.pvp == true and not fighting
	if player:GetAttribute("InBattleZone") ~= pvp then
		player:SetAttribute("InBattleZone", pvp)
		character:SetAttribute("InBattleZone", pvp)
	end
	if st.zoneId ~= id then
		st.zoneId = id
		Remotes.event("ZoneChanged"):FireClient(player, id)
		S.QuestService.progress(player, "visitZone", id, 1)
	end
end

function ZoneService.init(services)
	S = services
end

function ZoneService.start()
	while true do
		task.wait(0.4)
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(check, player)
			if not ok then
				warn("[ZoneService]", err)
			end
		end
	end
end

return ZoneService
