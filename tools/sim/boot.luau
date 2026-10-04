-- Shared by the sim scenarios: boots every server service like init.server.luau does and
-- defines small helpers (check, invoke, fire, addPlayer, tp...).
local Remotes = require(__proxy("Shared/Remotes"))
local Zones = require(__proxy("Shared/Config/Zones"))
local Game = require(__proxy("Shared/Config/Game"))
local Tuning = require(__proxy("Shared/Tuning"))
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

Remotes.init()
-- The sims' fake players aren't the game's owner: open admin mode to them, with whatever the
-- admin code is set to (AdminConfig is the real, server-only file).
local AdminConfig = require(__proxy("Server/Config/AdminConfig"))
local OWNER_IDS = AdminConfig.ALLOWED_USER_IDS
AdminConfig.ALLOWED_USER_IDS = {}
local ADMIN_CODE = AdminConfig.CODE
local WorldBuilder = require(__proxy("Server/World/WorldBuilder"))
WorldBuilder.build()

local S = {}
for _, name in ipairs(SIM_ORDER) do
	S[name] = require(__proxy("Server/Services/" .. name))
end
for _, name in ipairs(SIM_ORDER) do
	if S[name].init then
		S[name].init(S)
	end
end
for _, name in ipairs(SIM_ORDER) do
	if S[name].start then
		task.spawn(S[name].start)
	end
end

local failures = {}
local function check(cond, msg)
	if not cond then
		table.insert(failures, msg)
		print("CHECK FAILED: " .. msg)
	end
	return cond
end
local function invoke(name, player, ...)
	local fn = Remotes.func(name).OnServerInvoke
	assert(fn, "no handler for " .. name)
	return fn(player, ...)
end
local function fire(name, player, ...)
	Remotes.event(name).OnServerEvent:Fire(player, ...)
end
local function addPlayer(userId: number, name: string)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = userId
	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	return p
end
local function remoteCount(name: string, player)
	local n = 0
	for _, entry in ipairs(REMOTE_LOG) do
		if entry.remote == name and (player == nil or entry.player == player or entry.all) then
			n += 1
		end
	end
	return n
end
local function tp(player, pos: Vector3)
	S.PlayerService.teleport(player, CFrame.new(pos))
end
local function rootOf(player)
	local _, _, root = S.PlayerService.getCharacter(player)
	return root
end
local function findEnemy(pred)
	for _, e in ipairs(S.EnemyService.alive()) do
		if pred(e) then
			return e
		end
	end
	return nil
end
local function step(label: string)
	print(string.format("[%6.1fs] %s", SIM.now, label))
end

