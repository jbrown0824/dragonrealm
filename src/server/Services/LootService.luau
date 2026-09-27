-- Loot rolls and drops. Vikings drop gold (collected instantly) and sometimes gear or seeds,
-- which pop out as glowing orbs that only their owner can see and that fly to the owner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Seeds = require(Shared.Config.Seeds)
local ItemUtil = require(Shared.ItemUtil)
local Util = require(Shared.Util)

local LootService = {}
local S

local folder: Folder
local orbs = {} -- [Part] = { owner, kind, payload, spawnedAt }
local ORB_LIFETIME = 60
local MAGNET_RADIUS = 18

---------------------------------------------------------------- rolls

-- luck: percent bonus that shifts weight toward rarer tiers. minRarity: floor.
function LootService.rollRarity(luck: number?, minRarity: string?): string
	luck = luck or 0
	local minRank = minRarity and Items.Rarities[minRarity].rank or 1
	local weights = {}
	for name, r in pairs(Items.Rarities) do
		if r.rank >= minRank then
			local w = r.weight
			if r.rank >= 3 then
				w *= 1 + luck / 100
			end
			weights[name] = w
		end
	end
	return Util.weightedPick(weights) or "Common"
end

function LootService.rollGear(ilvl: number, luck: number?, minRarity: string?, forcedRarity: string?)
	local slot = Items.Slots[math.random(1, #Items.Slots)]
	local rarity = forcedRarity or LootService.rollRarity(luck, minRarity)
	return ItemUtil.new(slot, math.max(1, ilvl), rarity)
end

function LootService.rollUnique(uniqueId: string, ilvl: number)
	local unique = Items.Uniques[uniqueId]
	if not unique then
		return nil
	end
	return ItemUtil.new(unique.slot, ilvl, "Legendary", uniqueId)
end

-- bonus > 0 makes rarer seeds more likely.
function LootService.rollSeed(bonus: number?): string
	bonus = bonus or 0
	local weights = {}
	for i, id in ipairs(Seeds.Order) do
		local seed = Seeds[id]
		weights[id] = seed.dropWeight * (1 + bonus * (i - 1))
	end
	return Util.weightedPick(weights) or "Emberbloom"
end

---------------------------------------------------------------- orbs

local function orbColor(kind: string, payload): Color3
	if kind == "gear" then
		return ItemUtil.rarityColor(payload.rarity)
	elseif kind == "seed" then
		local seed = Seeds.get(payload)
		return seed and seed.bloom or Color3.new(0.4, 1, 0.4)
	end
	return Color3.fromRGB(255, 210, 60)
end

local function orbLabel(kind: string, payload): string
	if kind == "gear" then
		return ItemUtil.displayName(payload)
	elseif kind == "seed" then
		local seed = Seeds.get(payload)
		return "🌱 " .. (seed and seed.name or payload) .. " Seed"
	end
	return "Gold"
end

local function collect(orb: BasePart)
	local data = orbs[orb]
	if not data then
		return
	end
	orbs[orb] = nil
	local player = data.owner
	if player.Parent then
		if data.kind == "gear" then
			S.PlayerService.addItem(player, data.payload)
		elseif data.kind == "seed" then
			S.PlayerService.addSeeds(player, data.payload, 1)
		end
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local tween = TweenService:Create(orb, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = root.Position, Size = Vector3.new(0.2, 0.2, 0.2) })
		tween:Play()
		tween.Completed:Connect(function()
			orb:Destroy()
		end)
	else
		orb:Destroy()
	end
end

function LootService.spawnOrb(player: Player, position: Vector3, kind: string, payload)
	local color = orbColor(kind, payload)
	local orb = Instance.new("Part")
	orb.Name = "LootOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.6, 1.6, 1.6)
	orb.Material = Enum.Material.Neon
	orb.Color = color
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CollisionGroup = "Loot"
	orb:SetAttribute("OwnerUserId", player.UserId)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 2
	light.Parent = orb

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(color)
	sparkle.LightEmission = 1
	sparkle.Rate = 8
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = orb

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 24)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = orbLabel(kind, payload)
	label.Parent = gui
	gui.Parent = orb

	-- Pop up out of the body, then settle.
	local start = position + Vector3.new(0, 2, 0)
	local offset = Vector3.new(math.random(-40, 40) / 10, 0, math.random(-40, 40) / 10)
	local ground = S.EnemyService.groundAt(start + offset, 6)
	orb.Position = start
	orb.Parent = folder
	TweenService:Create(orb, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), { Position = ground + Vector3.new(0, 1.5, 0) }):Play()

	orbs[orb] = { owner = player, kind = kind, payload = payload, spawnedAt = os.clock() }
end

---------------------------------------------------------------- enemy drops

function LootService.dropForEnemy(player: Player, e, position: Vector3)
	local stats = S.PlayerService.getStats(player)
	local luck = stats and stats.lootPct or 0
	local def = e.def

	local gold = math.random(4, 8) * (1 + 0.3 * (e.level - 1)) * (def.goldMult or 1)
	local got = S.PlayerService.addGold(player, gold, true)
	S.CombatService.queueNumber(player, position + Vector3.new(0, 5, 0), got, "gold")

	if math.random() < (def.gearChance or 0) * (1 + luck / 100) then
		local ilvl = math.clamp(e.level + math.random(-1, 1), 1, 32)
		LootService.spawnOrb(player, position, "gear", LootService.rollGear(ilvl, luck, def.minRarity))
	end
	if math.random() < (def.seedChance or 0) * (1 + luck / 100) then
		LootService.spawnOrb(player, position, "seed", LootService.rollSeed(e.level / 30))
	end
end

-- Direct rewards (quests, bosses). rewards: { xp, gold, gear = { rarity }, seeds = { id = n }, items = { item... } }
function LootService.grant(player: Player, rewards)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	if rewards.gold then
		S.PlayerService.addGold(player, rewards.gold)
	end
	if rewards.xp then
		S.PlayerService.addXP(player, rewards.xp)
	end
	if rewards.gear then
		S.PlayerService.addItem(player, LootService.rollGear(profile.level, 0, nil, rewards.gear.rarity))
	end
	if rewards.items then
		for _, item in ipairs(rewards.items) do
			S.PlayerService.addItem(player, item)
		end
	end
	if rewards.seeds then
		for seedId, n in pairs(rewards.seeds) do
			S.PlayerService.addSeeds(player, seedId, n)
		end
	end
end

function LootService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = workspace
end

function LootService.start()
	Players.PlayerRemoving:Connect(function(player)
		for orb, data in pairs(orbs) do
			if data.owner == player then
				orbs[orb] = nil
				orb:Destroy()
			end
		end
	end)

	while true do
		task.wait(0.25)
		local t = os.clock()
		for orb, data in pairs(orbs) do
			if t - data.spawnedAt < 0.7 then
				continue
			end
			local character = data.owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if t - data.spawnedAt > ORB_LIFETIME then
				collect(orb)
			elseif root and (root.Position - orb.Position).Magnitude <= MAGNET_RADIUS then
				collect(orb)
			end
		end
	end
end

return LootService
