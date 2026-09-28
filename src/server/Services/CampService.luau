-- Viking camp extras: the treasure chest in the middle of each camp and the camp's mini-boss.
--
-- Chests (tag "CampChest", built by WorldBuilder): hold E to open. The moment you start, every
-- viking in the camp comes for you. When it opens, every dragon in the camp gets a prize. Then
-- the chest refills after Game.CHEST_RESPAWN seconds.
--
-- Mini-bosses (Enemies.MiniBosses): one per camp, standing guard near the chest. Skull on the
-- health bar, a telegraphed slam, great loot, and a few minutes before the next one shows up.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Enemies = require(Shared.Config.Enemies)
local Zones = require(Shared.Config.Zones)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local CampService = {}
local S

local chests = {} -- [campId] = { model, camp, prompt, lid, lidClosed, glow, label, readyAt, lastAlarm }
local bosses = {} -- [campId] = enemy info

---------------------------------------------------------------- chests

local function setChestReady(chest, ready: boolean)
	chest.prompt.Enabled = ready
	if chest.glow then
		chest.glow.Transparency = ready and 0.2 or 1
		local light = chest.glow:FindFirstChildWhichIsA("PointLight")
		if light then
			light.Enabled = ready
		end
	end
	if chest.lid then
		local goal = ready and chest.lidClosed or chest.lidClosed * chest.lidOpen
		TweenService:Create(chest.lid, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = goal }):Play()
	end
	chest.label.Text = ready and "💰 Treasure Chest" or ""
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
	if os.clock() < chest.readyAt then
		return
	end
	local _, _, root = S.PlayerService.getCharacter(player)
	if not root or (root.Position - chest.model:GetPivot().Position).Magnitude > 30 then
		return
	end
	chest.readyAt = os.clock() + Game.CHEST_RESPAWN
	setChestReady(chest, false)
	S.CombatService.broadcastVFX({ kind = "chest", pos = chest.model:GetPivot().Position })
	-- Everyone who helped (any dragon in the camp) gets their own prize.
	local camp = chest.camp
	for _, other in ipairs(Players:GetPlayers()) do
		local _, _, r = S.PlayerService.getCharacter(other)
		if r and (r.Position - camp.center).Magnitude <= camp.radius + 40 then
			chestRewards(camp, other)
		end
	end
end

local function setupChest(model: Model)
	local campId = model:GetAttribute("CampId")
	local camp = campId and Zones.getCamp(campId)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not camp or not prompt then
		return
	end
	local lid = model:FindFirstChild("Lid")
	local chest = {
		model = model,
		camp = camp,
		prompt = prompt,
		lid = lid,
		lidClosed = lid and lid.CFrame,
		-- hinge along the back edge
		lidOpen = lid and (CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2) * CFrame.Angles(math.rad(100), 0, 0) * CFrame.new(0, lid.Size.Y / 2, -lid.Size.Z / 2)),
		glow = model:FindFirstChild("Glow"),
		readyAt = 0,
		lastAlarm = 0,
	}
	local gui = Instance.new("BillboardGui")
	gui.Name = "ChestLabel"
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 215, 90)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = model.PrimaryPart
	chest.label = label

	prompt.ActionText = "Open Chest"
	prompt.ObjectText = camp.name .. " Treasure"
	prompt.HoldDuration = camp.chest.hold
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if os.clock() < chest.readyAt then
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
	setChestReady(chest, true)
end

function CampService.resetChests()
	for _, chest in pairs(chests) do
		chest.readyAt = 0
		setChestReady(chest, true)
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
	-- Countdown on empty chests.
	while true do
		task.wait(1)
		local t = os.clock()
		for _, chest in pairs(chests) do
			if chest.readyAt > 0 then
				if t >= chest.readyAt then
					chest.readyAt = 0
					setChestReady(chest, true)
				else
					chest.label.Text = "Refills in " .. Util.formatTime(chest.readyAt - t)
				end
			end
		end
	end
end

return CampService
