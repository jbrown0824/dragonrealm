-- Owns everything about a player's dragon: choosing a type, spawning, stats, XP and levels,
-- gold, inventory, equipment, skill points, buffs, regen, and pushing profile snapshots to
-- the client UI.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Classes = require(Shared.Config.Classes)
local Abilities = require(Shared.Config.Abilities)
local Zones = require(Shared.Config.Zones)
local Seeds = require(Shared.Config.Seeds)
local StatCalc = require(Shared.StatCalc)
local TalentUtil = require(Shared.TalentUtil)
local ItemUtil = require(Shared.ItemUtil)
local BonusUtil = require(Shared.BonusUtil)
local Tuning = require(Shared.Tuning)
local DragonBuilder = require(Shared.DragonBuilder)
local Remotes = require(Shared.Remotes)

local PlayerService = {}
local S -- all services

-- Runtime (not saved) state per player.
local state = {} -- [Player] = { stats, buffs, lastDamaged, cheatDeathReady, stealthUntil, ambushMult, zoneId, homeReadyAt, dirty, streak }
PlayerService.state = state

local function now()
	return os.clock()
end

---------------------------------------------------------------- helpers

function PlayerService.getProfile(player: Player)
	return S.DataService.get(player)
end

function PlayerService.getStats(player: Player)
	local st = state[player]
	return st and st.stats
end

-- Returns character, humanoid, root when the player's dragon is alive.
function PlayerService.getCharacter(player: Player)
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

function PlayerService.markDirty(player: Player)
	local st = state[player]
	if st then
		st.dirty = true
	end
end

function PlayerService.notify(player: Player, text: string, color: Color3?, icon: string?)
	Remotes.event("Notify"):FireClient(player, { text = text, color = color, icon = icon })
end

function PlayerService.findItem(profile, itemId: string)
	for i, item in ipairs(profile.inventory) do
		if item.id == itemId then
			return item, i
		end
	end
	return nil
end

local function equippedItems(profile)
	local result = {}
	for slot, itemId in pairs(profile.equipped) do
		local item = PlayerService.findItem(profile, itemId)
		if item then
			result[slot] = item
		else
			profile.equipped[slot] = nil
		end
	end
	return result
end

local function updateLeaderstats(player: Player)
	local profile = PlayerService.getProfile(player)
	local ls = player:FindFirstChild("leaderstats")
	if not profile or not ls then
		return
	end
	ls.Level.Value = profile.level
	ls.Gold.Value = profile.gold
	ls.Glory.Value = profile.glory
end

---------------------------------------------------------------- nametag

local function updateNametag(player: Player)
	local character = player.Character
	local profile = PlayerService.getProfile(player)
	if not character or not profile then
		return
	end
	local head = character:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("Nametag")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not tag or not humanoid then
		return
	end
	local class = Classes.get(profile.class)
	tag.Info.Text = string.format("Lv %d %s", profile.level, class and class.name or "")
	local pct = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
	tag.Bar.Fill.Size = UDim2.fromScale(pct, 1)
end

local function createNametag(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local scale = character:GetAttribute("DragonScale") or 1
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(200, 56)
	gui.StudsOffset = Vector3.new(0, 3.2 * scale, 0)
	gui.MaxDistance = 140
	gui.PlayerToHideFrom = player
	gui.LightInfluence = 0

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 22)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = player.DisplayName
	name.Parent = gui

	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(0, 22)
	info.Size = UDim2.new(1, 0, 0, 16)
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(255, 220, 140)
	info.TextStrokeTransparency = 0.5
	info.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 42)
	bar.Size = UDim2.fromOffset(110, 8)
	bar.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(1, 0)
	c1.Parent = bar
	local c2 = c1:Clone()
	c2.Parent = fill

	gui.Parent = head
end

---------------------------------------------------------------- stats

function PlayerService.refreshMovement(player: Player)
	local st = state[player]
	local character, humanoid = PlayerService.getCharacter(player)
	if not st or not st.stats or not humanoid then
		return
	end
	local mult = S.CombatService.speedMultiplier(character)
	humanoid.WalkSpeed = st.stats.speed * mult
	character:SetAttribute("SpeedMult", mult)
end

function PlayerService.recompute(player: Player)
	local profile = PlayerService.getProfile(player)
	local st = state[player]
	if not profile or not st or not profile.class then
		return
	end
	local buffStats = BonusUtil.entries(profile)
	for _, buff in pairs(st.buffs) do
		if buff.stats then
			table.insert(buffStats, { stats = buff.stats })
		end
	end
	st.stats = StatCalc.compute(profile.class, profile.level, equippedItems(profile), profile.talents, buffStats)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local ratio = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
		humanoid.MaxHealth = st.stats.maxHealth
		humanoid.Health = math.max(1, math.min(st.stats.maxHealth, st.stats.maxHealth * ratio))
		character:SetAttribute("MaxStamina", st.stats.stamina)
		character:SetAttribute("BaseSpeed", st.stats.speed)
		character:SetAttribute("FlightSpeedMult", math.max(0.3, 1 + st.stats.flightSpeedPct / 100))
		character:SetAttribute("Level", profile.level)
		PlayerService.refreshMovement(player)
		updateNametag(player)
	end
	PlayerService.markDirty(player)
end

---------------------------------------------------------------- snapshot for the client

function PlayerService.snapshot(player: Player)
	local profile = PlayerService.getProfile(player)
	local st = state[player]
	if not profile or not st then
		return nil
	end
	return {
		class = profile.class,
		level = profile.level,
		xp = profile.xp,
		xpToNext = Game.xpToNext(profile.level),
		gold = profile.gold,
		glory = profile.glory,
		talents = profile.talents,
		talentPoints = TalentUtil.available(profile.level, profile.talents),
		inventory = profile.inventory,
		equipped = profile.equipped,
		seeds = profile.seeds,
		quests = profile.quests,
		plotsUnlocked = profile.plotsUnlocked,
		stats = st.stats,
		power = st.stats and StatCalc.power(st.stats) or 0,
		bossKills = profile.bossKills,
		vikingKills = profile.vikingKills,
		baseIndex = st.baseIndex,
		saveFailed = S.DataService.didLoadFail(player),
		hunger = profile.hunger,
		food = profile.food,
		potions = profile.potions,
		eggs = profile.eggs,
		pets = profile.pets,
		treats = profile.treats,
		petsEquipped = profile.petsEquipped,
		petSlots = Game.petSlots(profile.level),
		robots = profile.robots,
		garden = S.FarmService.summary(player),
		tutorial = profile.tutorial,
		isAdmin = S.AdminService.isAdmin(player),
		settings = profile.settings,
	}
end

---------------------------------------------------------------- spawning

function PlayerService.getSpawnCFrame(player: Player): CFrame
	local arenaCF = S.BossService and S.BossService.getArenaSpawn(player)
	if arenaCF then
		return arenaCF
	end
	local offset = Vector3.new(math.random(-14, 14), 0, math.random(-6, 10))
	local pos = Zones.SPAWN + offset
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
end

function PlayerService.spawn(player: Player, atCFrame: CFrame?)
	local profile = PlayerService.getProfile(player)
	local st = state[player]
	if not profile or not st or not profile.class or not player.Parent then
		return
	end
	local old = player.Character
	if old then
		player.Character = nil
		old:Destroy()
	end

	st.buffs = {}
	st.stealthUntil = 0
	PlayerService.recompute(player)
	local stats = st.stats

	local model, hipHeight = DragonBuilder.build(profile.class, { name = player.Name })
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.AutomaticScalingEnabled = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 55
	humanoid.MaxHealth = stats.maxHealth
	humanoid.Health = stats.maxHealth
	humanoid.WalkSpeed = stats.speed
	humanoid.MaxSlopeAngle = 60
	humanoid.Parent = model

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Dragons"
		end
	end

	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("MaxStamina", stats.stamina)
	model:SetAttribute("BaseSpeed", stats.speed)
	model:SetAttribute("Level", profile.level)
	model:SetAttribute("SpeedMult", 1)
	model:SetAttribute("FlightSpeedMult", math.max(0.3, 1 + stats.flightSpeedPct / 100))
	createNametag(player, model)
	S.PetService.applyToCharacter(player, model)

	model:PivotTo(atCFrame or PlayerService.getSpawnCFrame(player))
	model.Parent = workspace
	player.Character = model
	CollectionService:AddTag(model, "Dragon")

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	pcall(function()
		root:SetNetworkOwner(player)
	end)

	updateNametag(player)
	humanoid.HealthChanged:Connect(function()
		updateNametag(player)
	end)

	humanoid.Died:Connect(function()
		S.BossService.onPlayerDied(player)
		S.SurvivalService.onDied(player)
		Remotes.event("Died"):FireClient(player, Game.RESPAWN_TIME)
		Remotes.event("VFX"):FireAllClients({ kind = "enemyDeath", pos = root.Position })
		task.delay(Game.RESPAWN_TIME, function()
			if player.Parent and player.Character == model then
				PlayerService.spawn(player)
			end
		end)
	end)
end

---------------------------------------------------------------- progression

function PlayerService.addXP(player: Player, amount: number, raw: boolean?)
	local profile = PlayerService.getProfile(player)
	local st = state[player]
	if not profile or not st or amount <= 0 then
		return
	end
	if profile.level >= Game.LEVEL_CAP then
		return
	end
	if not raw and st.stats then
		amount = amount * (1 + st.stats.xpPct / 100) * Tuning.global("xp")
	end
	profile.xp += math.floor(amount)

	local startLevel = profile.level
	while profile.level < Game.LEVEL_CAP and profile.xp >= Game.xpToNext(profile.level) do
		profile.xp -= Game.xpToNext(profile.level)
		profile.level += 1
	end
	if profile.level >= Game.LEVEL_CAP then
		profile.xp = 0
	end

	if profile.level > startLevel then
		PlayerService.recompute(player)
		local _, humanoid = PlayerService.getCharacter(player)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
		local gained = profile.level - startLevel
		Remotes.event("Announce"):FireClient(player, {
			title = "LEVEL UP!",
			text = string.format("You are now level %d  •  +%d skill point%s", profile.level, gained, gained > 1 and "s" or ""),
			color = Color3.fromRGB(255, 215, 80),
			duration = 4,
		})
		if player.Character then
			Remotes.event("VFX"):FireAllClients({ kind = "levelUp", character = player.Character })
		end
		S.QuestService.progress(player, "level", nil, profile.level, true)
		updateLeaderstats(player)
		local class = Classes.get(profile.class)
		if class and class.signature and startLevel < Game.SIGNATURE_LEVEL and profile.level >= Game.SIGNATURE_LEVEL then
			local a = Abilities.get(class.signature)
			PlayerService.notify(player, string.format("New ability: %s %s! Use it with key 1.", a.icon, a.name), Color3.fromRGB(255, 215, 80), "✨")
		end
	end
	PlayerService.markDirty(player)
end

function PlayerService.addGold(player: Player, amount: number, applyBonus: boolean?): number
	local profile = PlayerService.getProfile(player)
	local st = state[player]
	if not profile or amount <= 0 then
		return 0
	end
	if applyBonus and st and st.stats then
		amount = amount * (1 + st.stats.goldPct / 100) * Tuning.global("gold")
	end
	amount = math.floor(amount)
	profile.gold += amount
	updateLeaderstats(player)
	PlayerService.markDirty(player)
	return amount
end

function PlayerService.spendGold(player: Player, amount: number): boolean
	local profile = PlayerService.getProfile(player)
	if not profile or amount < 0 or profile.gold < amount then
		return false
	end
	profile.gold -= amount
	updateLeaderstats(player)
	PlayerService.markDirty(player)
	return true
end

function PlayerService.addGlory(player: Player, amount: number)
	local profile = PlayerService.getProfile(player)
	if not profile then
		return
	end
	profile.glory += amount
	updateLeaderstats(player)
	PlayerService.markDirty(player)
end

-- Adds an item to the bag. If the bag is full it is sold automatically.
function PlayerService.addItem(player: Player, item, silent: boolean?): boolean
	local profile = PlayerService.getProfile(player)
	if not profile then
		return false
	end
	if #profile.inventory >= Game.INVENTORY_LIMIT then
		local gold = ItemUtil.sellPrice(item)
		PlayerService.addGold(player, gold)
		PlayerService.notify(player, string.format("Bag full! Sold %s for %d gold.", ItemUtil.displayName(item), gold), Color3.fromRGB(255, 200, 80), "💰")
		return false
	end
	table.insert(profile.inventory, item)
	if not silent then
		PlayerService.notify(player, "Found: " .. ItemUtil.displayName(item), ItemUtil.rarityColor(item.rarity), "✨")
	end
	PlayerService.markDirty(player)
	return true
end

function PlayerService.removeItem(player: Player, itemId: string)
	local profile = PlayerService.getProfile(player)
	if not profile then
		return nil
	end
	local item, index = PlayerService.findItem(profile, itemId)
	if not item then
		return nil
	end
	table.remove(profile.inventory, index)
	local wasEquipped = profile.equipped[item.slot] == itemId
	if wasEquipped then
		profile.equipped[item.slot] = nil
		PlayerService.recompute(player)
	end
	PlayerService.markDirty(player)
	return item
end

function PlayerService.addSeeds(player: Player, seedId: string, count: number, silent: boolean?)
	local profile = PlayerService.getProfile(player)
	local seed = Seeds.get(seedId)
	if not profile or not seed or count <= 0 then
		return
	end
	profile.seeds[seedId] = (profile.seeds[seedId] or 0) + count
	if not silent then
		PlayerService.notify(player, string.format("Found %dx %s Seed!", count, seed.name), seed.bloom, "🌱")
	end
	PlayerService.markDirty(player)
end

-- Change a dragon's level directly (admin tools). Skill points above the new total are refunded.
function PlayerService.setLevel(player: Player, level: number)
	local profile = PlayerService.getProfile(player)
	if not profile then
		return
	end
	profile.level = math.clamp(math.floor(level), 1, Game.LEVEL_CAP)
	profile.xp = 0
	if TalentUtil.available(profile.level, profile.talents) < 0 then
		profile.talents = {}
	end
	PlayerService.recompute(player)
	local _, humanoid = PlayerService.getCharacter(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	S.QuestService.progress(player, "level", nil, profile.level, true)
	updateLeaderstats(player)
end

-- Switch dragon type in place (used by Transform and the admin panel).
function PlayerService.setClass(player: Player, classId: string)
	local profile = PlayerService.getProfile(player)
	if not profile or not Classes.get(classId) then
		return
	end
	profile.class = classId
	profile.talents = {}
	local _, _, root = PlayerService.getCharacter(player)
	local at = root and root.CFrame or nil
	PlayerService.recompute(player)
	PlayerService.spawn(player, at)
end

---------------------------------------------------------------- buffs

function PlayerService.addBuff(player: Player, id: string, duration: number, stats)
	local st = state[player]
	if not st then
		return
	end
	st.buffs[id] = { id = id, expires = now() + duration, stats = stats }
	PlayerService.recompute(player)
end

function PlayerService.heal(player: Player, amount: number)
	local _, humanoid = PlayerService.getCharacter(player)
	if humanoid and amount > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

function PlayerService.teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(cf)
	end
end

---------------------------------------------------------------- remotes

local function onChooseClass(player: Player, classId)
	local profile = PlayerService.getProfile(player)
	if not profile or profile.class ~= nil or type(classId) ~= "string" or not Classes.get(classId) then
		return false
	end
	profile.class = classId
	PlayerService.recompute(player)
	PlayerService.spawn(player)
	PlayerService.markDirty(player)
	return true
end

local function onTransform(player: Player, classId)
	local profile = PlayerService.getProfile(player)
	if not profile or not profile.class or type(classId) ~= "string" or not Classes.get(classId) then
		return false, "Invalid dragon type."
	end
	if classId == profile.class then
		return false, "You are already a " .. classId .. "."
	end
	local cost = Game.transformCost(profile.level)
	if not PlayerService.spendGold(player, cost) then
		return false, string.format("You need %d gold to transform.", cost)
	end
	PlayerService.setClass(player, classId)
	PlayerService.notify(player, "You transformed into a " .. Classes.get(classId).name .. "! Your skill points were refunded.", Color3.fromRGB(255, 215, 80), "🐉")
	return true
end

-- Learn `count` ranks of one skill (1 by default; "Max" in the UI sends the ranks left).
local function onSpendTalent(player: Player, talentId, count)
	local profile = PlayerService.getProfile(player)
	if not profile or not profile.class or type(talentId) ~= "string" then
		return false, "Invalid"
	end
	count = math.clamp(math.floor(tonumber(count) or 1), 1, 5)
	local learned = 0
	for _ = 1, count do
		local ok, reason = TalentUtil.canLearn(profile.class, profile.level, profile.talents, talentId)
		if not ok then
			if learned == 0 then
				return false, reason
			end
			break
		end
		profile.talents[talentId] = (profile.talents[talentId] or 0) + 1
		learned += 1
	end
	PlayerService.recompute(player)
	return true, learned
end

-- Spend every point you can down one branch.
local function onAutoSpend(player: Player, branchIndex)
	local profile = PlayerService.getProfile(player)
	if not profile or not profile.class or type(branchIndex) ~= "number" then
		return false, "Invalid"
	end
	if TalentUtil.available(profile.level, profile.talents) <= 0 then
		return false, "No skill points left. Level up to earn more!"
	end
	local learned = TalentUtil.autoFill(profile.class, profile.level, profile.talents, branchIndex)
	if learned == 0 then
		return false, "Nothing more to learn in that branch right now."
	end
	PlayerService.recompute(player)
	return true, learned
end

local function onResetTalents(player: Player)
	local profile = PlayerService.getProfile(player)
	if not profile or TalentUtil.spent(profile.talents) == 0 then
		return false, "You haven't spent any points."
	end
	local cost = TalentUtil.respecCost(profile.level)
	if not PlayerService.spendGold(player, cost) then
		return false, string.format("Resetting costs %d gold.", cost)
	end
	profile.talents = {}
	PlayerService.recompute(player)
	return true
end

local function onEquip(player: Player, itemId)
	local profile = PlayerService.getProfile(player)
	if not profile or type(itemId) ~= "string" then
		return false
	end
	local item = PlayerService.findItem(profile, itemId)
	if not item then
		return false
	end
	profile.equipped[item.slot] = item.id
	PlayerService.recompute(player)
	return true
end

-- Wear the best item you own in every slot.
local function onEquipBest(player: Player)
	local profile = PlayerService.getProfile(player)
	if not profile then
		return false
	end
	local changed = 0
	for slot, item in pairs(ItemUtil.bestPerSlot(profile.inventory)) do
		if profile.equipped[slot] ~= item.id then
			profile.equipped[slot] = item.id
			changed += 1
		end
	end
	PlayerService.recompute(player)
	return true, changed
end

local function onUnequip(player: Player, slot)
	local profile = PlayerService.getProfile(player)
	if not profile or type(slot) ~= "string" then
		return false
	end
	profile.equipped[slot] = nil
	PlayerService.recompute(player)
	return true
end

local function onTeleportHome(player: Player)
	local st = state[player]
	if not st or not PlayerService.getCharacter(player) then
		return false, "You can't do that right now."
	end
	if S.BossService.isInFight(player) then
		return false, "You can't leave a boss fight!"
	end
	if now() < st.homeReadyAt then
		return false, string.format("Wait %d more seconds.", math.ceil(st.homeReadyAt - now()))
	end
	if now() - st.lastDamaged < 4 then
		return false, "You can't fly home while in combat!"
	end
	local cf = S.FarmService.getHomeCFrame(player) or PlayerService.getSpawnCFrame(player)
	st.homeReadyAt = now() + Game.HOME_TELEPORT_COOLDOWN
	PlayerService.teleport(player, cf)
	return true
end

---------------------------------------------------------------- lifecycle

local function onPlayerAdded(player: Player)
	state[player] = {
		stats = nil,
		buffs = {},
		lastDamaged = 0,
		cheatDeathReady = 0,
		stealthUntil = 0,
		ambushMult = 0,
		homeReadyAt = 0,
		dirty = true,
		streak = 0,
	}

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in ipairs({ "Level", "Glory", "Gold" }) do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player

	local profile = S.DataService.load(player)
	if not profile or not player.Parent then
		return
	end
	PlayerService.recompute(player)
	updateLeaderstats(player)
	S.FarmService.assignBase(player)

	if profile.class then
		PlayerService.spawn(player)
	end
	PlayerService.markDirty(player)
	if S.DataService.didLoadFail(player) then
		PlayerService.notify(player, "We couldn't load your save. Progress this session won't be saved — try rejoining later.", Color3.fromRGB(255, 90, 90), "⚠️")
	end
end

local function onPlayerRemoving(player: Player)
	S.FarmService.releaseBase(player)
	S.DataService.release(player)
	state[player] = nil
	if player.Character then
		player.Character:Destroy()
	end
end

function PlayerService.init(services)
	S = services
end

function PlayerService.start()
	Players.CharacterAutoLoads = false

	Remotes.func("GetProfile").OnServerInvoke = function(player)
		local deadline = os.clock() + 15
		while not PlayerService.getProfile(player) and os.clock() < deadline and player.Parent do
			task.wait(0.1)
		end
		return PlayerService.snapshot(player)
	end
	Remotes.func("ChooseClass").OnServerInvoke = onChooseClass
	Remotes.func("Transform").OnServerInvoke = onTransform
	Remotes.func("SpendTalent").OnServerInvoke = onSpendTalent
	Remotes.func("AutoSpendBranch").OnServerInvoke = onAutoSpend
	Remotes.func("ResetTalents").OnServerInvoke = onResetTalents
	Remotes.func("EquipItem").OnServerInvoke = onEquip
	Remotes.func("UnequipItem").OnServerInvoke = onUnequip
	Remotes.func("EquipBest").OnServerInvoke = onEquipBest
	-- small per-player UI preferences (only known keys, only booleans)
	Remotes.event("SetSetting").OnServerEvent:Connect(function(player, key, value)
		local profile = PlayerService.getProfile(player)
		if profile and key == "minimap" and type(value) == "boolean" then
			profile.settings[key] = value
			PlayerService.markDirty(player)
		end
	end)
	Remotes.func("TeleportHome").OnServerInvoke = onTeleportHome
	Remotes.event("SetFlying").OnServerEvent:Connect(function(player, flying)
		local character = player.Character
		if character then
			character:SetAttribute("Flying", flying == true)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- Push changed profiles to their owners a few times per second.
	local pushAccum = 0
	RunService.Heartbeat:Connect(function(dt)
		pushAccum += dt
		if pushAccum < 0.15 then
			return
		end
		pushAccum = 0
		for player, st in pairs(state) do
			if st.dirty and player.Parent then
				local snap = PlayerService.snapshot(player)
				if snap then
					st.dirty = false
					Remotes.event("ProfileUpdated"):FireClient(player, snap)
				end
			end
		end
	end)

	-- Regen + buff expiry
	task.spawn(function()
		while true do
			local dt = 0.5
			task.wait(dt)
			local t = now()
			for player, st in pairs(state) do
				local changed = false
				for id, buff in pairs(st.buffs) do
					if t >= buff.expires then
						st.buffs[id] = nil
						changed = true
					end
				end
				if changed then
					PlayerService.recompute(player)
				end
				local _, humanoid = PlayerService.getCharacter(player)
				if humanoid and st.stats and humanoid.Health < humanoid.MaxHealth then
					local perSecond = humanoid.MaxHealth * st.stats.regen / 100
					if t - st.lastDamaged >= Game.OUT_OF_COMBAT_TIME then
						perSecond += humanoid.MaxHealth * Game.OUT_OF_COMBAT_REGEN
					end
					if perSecond > 0 then
						humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perSecond * dt)
					end
				end
			end
		end
	end)
end

return PlayerService
