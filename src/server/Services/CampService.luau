-- Viking camp extras: the treasure chest in the middle of each camp and the camp's mini-boss.
--
-- Chests (tag "CampChest", built by WorldBuilder): hold E to open. The moment you start, every
-- viking in the camp comes for you. Every dragon has their own chest timer: when you open it
-- you get a prize and the chest is empty *for you* for Game.CHEST_RESPAWN seconds (a
-- "ChestReady_<campId>" attribute on the player, in server time). Each client draws the lid,
-- treasure and countdown from that attribute (WorldView), so friends can each loot it.
--
-- Mini-bosses (Enemies.MiniBosses): one per camp, standing guard near the chest. Skull on the
-- health bar, a telegraphed slam, great loot, and a few minutes before the next one shows up.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Enemies = require(Shared.Config.Enemies)
local Zones = require(Shared.Config.Zones)
local Remotes = require(Shared.Remotes)

local CampService = {}
local S

local chests = {} -- [campId] = { model, camp, prompt, lastAlarm }
local bosses = {} -- [campId] = enemy info

---------------------------------------------------------------- chests

local function readyAttr(campId: string): string
	return "ChestReady_" .. campId
end

function CampService.chestReadyFor(player: Player, campId: string): boolean
	return workspace:GetServerTimeNow() >= (player:GetAttribute(readyAttr(campId)) or 0)
end

local function chestRewards(camp, player: Player)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	local top = camp.levels[2]
	local stats = S.PlayerService.getStats(player)
	local luck = stats and stats.lootPct or 0
	local gold = math.floor((60 + 30 * top) * (0.9 + math.random() * 0.3))
	local minRarity = top >= 17 and "Rare" or "Uncommon"
	local items = { S.LootService.rollGear(math.max(profile.level, top), luck, minRarity) }
	local seeds, eggs = nil, nil
	if math.random() < 0.4 then
		seeds = { [S.LootService.rollSeed(top / 20)] = 1 }
	end
	if math.random() < 0.15 then
		eggs = { [S.LootService.rollEgg(top / 30)] = 1 }
	end
	S.LootService.grant(player, { gold = gold, xp = 60 + 25 * top, items = items, seeds = seeds, eggs = eggs })
	profile.chestsOpened += 1
	S.QuestService.progress(player, "openChest", camp.id, 1)
	S.PlayerService.notify(player, string.format("You looted the %s chest! +%d gold", camp.name, gold), Color3.fromRGB(255, 215, 80), "💰")
end

local function openChest(chest, player: Player)
	if not CampService.chestReadyFor(player, chest.camp.id) then
		return
	end
	local _, _, root = S.PlayerService.getCharacter(player)
	if not root or (root.Position - chest.model:GetPivot().Position).Magnitude > 30 then
		return
	end
	player:SetAttribute(readyAttr(chest.camp.id), workspace:GetServerTimeNow() + Game.CHEST_RESPAWN)
	S.CombatService.broadcastVFX({ kind = "chest", pos = chest.model:GetPivot().Position })
	chestRewards(chest.camp, player)
end

local function setupChest(model: Model)
	local campId = model:GetAttribute("CampId")
	local camp = campId and Zones.getCamp(campId)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not camp or not prompt then
		return
	end
	local chest = { model = model, camp = camp, prompt = prompt, lastAlarm = 0 }
	prompt.ActionText = "Open Chest"
	prompt.ObjectText = camp.name .. " Treasure"
	prompt.HoldDuration = camp.chest.hold
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if not CampService.chestReadyFor(player, camp.id) then
			return
		end
		if os.clock() - chest.lastAlarm > 8 then
			chest.lastAlarm = os.clock()
			S.EnemyService.alarmCamp(camp, player)
			S.PlayerService.notify(player, "The vikings heard the lock creak... here they come!", Color3.fromRGB(255, 150, 80), "⚔️")
		end
	end)
	prompt.Triggered:Connect(function(player)
		openChest(chest, player)
	end)
	chests[camp.id] = chest
end

function CampService.resetChests()
	for _, player in ipairs(Players:GetPlayers()) do
		for campId in pairs(chests) do
			player:SetAttribute(readyAttr(campId), nil)
		end
	end
end

---------------------------------------------------------------- mini-bosses

local spawnMiniBoss

spawnMiniBoss = function(camp)
	local cfg = Enemies.MiniBosses[camp.id]
	local base = cfg and Enemies.Vikings[cfg.base]
	if not base then
		return
	end
	-- A copy of the base viking with the champion's look, bigger reach and no auto-respawn.
	local def = table.clone(base)
	def.id = cfg.id
	def.name = cfg.name
	def.look = cfg.look
	def.attackRange = (base.attackRange or 7) + 2
	def.elite = true
	def.xpMult = (base.xpMult or 1) * Enemies.MINI_BOSS_LOOT.xpMult
	local e = S.EnemyService.spawn(cfg.base, cfg.level, camp.center + camp.boss, {
		def = def,
		camp = camp,
		miniBoss = true,
		displayName = cfg.name,
		scale = cfg.scale,
		healthMult = cfg.healthMult,
		damageMult = cfg.damageMult,
		slam = cfg.slam,
		aggroRange = 40,
		leash = 90,
		onDeath = function(_, killer)
			bosses[camp.id] = nil
			for _, player in ipairs(Players:GetPlayers()) do
				local _, _, root = S.PlayerService.getCharacter(player)
				if root and (root.Position - camp.center).Magnitude < camp.radius + 150 then
					Remotes.event("Announce"):FireClient(player, {
						title = "💀 CHAMPION DEFEATED",
						text = string.format("%s has fallen%s!", cfg.name, killer and (" to " .. killer.DisplayName) or ""),
						color = Color3.fromRGB(255, 150, 60),
						duration = 4,
					})
				end
			end
			task.delay(cfg.respawn, function()
				spawnMiniBoss(camp)
			end)
		end,
	})
	bosses[camp.id] = e
end

function CampService.respawnMiniBosses()
	for _, camp in ipairs(Zones.Camps) do
		local e = bosses[camp.id]
		if e and not e.dead then
			S.EnemyService.despawn(e)
		end
		bosses[camp.id] = nil
		spawnMiniBoss(camp)
	end
end

function CampService.init(services)
	S = services
end

function CampService.start()
	for _, model in ipairs(CollectionService:GetTagged("CampChest")) do
		setupChest(model)
	end
	task.wait(1)
	for _, camp in ipairs(Zones.Camps) do
		spawnMiniBoss(camp)
	end
end

return CampService
