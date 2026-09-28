-- Hunger and food. Every dragon's hunger drains over time (faster while flying, slower in
-- town, slower with Iron Belly Stew and some pets). Below the thresholds in Game.HUNGER_LEVELS
-- you fly slower and shorter and hit softer. Eat hunted meat or caught fish to fill up.
-- The current value is mirrored to the player attribute "Hunger" for the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Food = require(Shared.Config.Food)
local Zones = require(Shared.Config.Zones)
local Remotes = require(Shared.Remotes)

local SurvivalService = {}
local S

local lastLevel = {} -- [Player] = hunger level id ("Hungry" / "Starving" / "")

local function levelId(hunger: number): string
	local lvl = Game.hungerLevel(hunger)
	return lvl and lvl.id or ""
end

local function publish(player: Player, profile)
	player:SetAttribute("Hunger", math.floor(profile.hunger * 10 + 0.5) / 10)
	local id = levelId(profile.hunger)
	if lastLevel[player] ~= id then
		local before = lastLevel[player]
		lastLevel[player] = id
		S.PlayerService.recompute(player)
		if before ~= nil then
			if id == "Starving" then
				S.PlayerService.notify(player, "You're STARVING! Your wings and fire are much weaker. Hunt an animal or catch a fish!", Color3.fromRGB(255, 90, 90), "😵")
			elseif id == "Hungry" and before == "" then
				S.PlayerService.notify(player, "You're getting hungry. Your flight and fire are weaker until you eat. (G to eat from your bag)", Color3.fromRGB(255, 190, 80), "😋")
			elseif id == "" then
				S.PlayerService.notify(player, "You feel full and strong again!", Color3.fromRGB(140, 230, 120), "🍖")
			end
		end
	end
end

-- Fill up by `amount` hunger points (also heals a little).
function SurvivalService.feed(player: Player, amount: number)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	profile.hunger = math.clamp(profile.hunger + amount, 0, Game.HUNGER_MAX)
	local _, humanoid = S.PlayerService.getCharacter(player)
	if humanoid then
		S.PlayerService.heal(player, humanoid.MaxHealth * Game.EAT_HEAL_PCT / 100)
	end
	publish(player, profile)
	S.PlayerService.markDirty(player)
	S.QuestService.progress(player, "eat", nil, 1)
	local character = player.Character
	if character then
		S.CombatService.broadcastVFX({ kind = "eat", character = character })
	end
end

function SurvivalService.setHunger(player: Player, value: number)
	local profile = S.PlayerService.getProfile(player)
	if profile then
		profile.hunger = math.clamp(value, 0, Game.HUNGER_MAX)
		publish(player, profile)
		S.PlayerService.markDirty(player)
	end
end

local function foodCount(profile): number
	local n = 0
	for _, c in pairs(profile.food) do
		n += c
	end
	return n
end

-- Put food in the bag. Returns false (and sells it) when the bag is full.
function SurvivalService.addFood(player: Player, foodId: string, count: number?): boolean
	local profile = S.PlayerService.getProfile(player)
	local item = Food.get(foodId)
	if not profile or not item then
		return false
	end
	count = count or 1
	if foodCount(profile) + count > Game.FOOD_BAG_LIMIT then
		local gold = S.PlayerService.addGold(player, item.sell * count)
		S.PlayerService.notify(player, string.format("Food bag full! Sold %s for %d gold.", item.name, gold), Color3.fromRGB(255, 200, 80), "💰")
		return false
	end
	profile.food[foodId] = (profile.food[foodId] or 0) + count
	S.PlayerService.markDirty(player)
	return true
end

-- Eat one of something from the bag. With no id, eats whatever fills you up best without
-- wasting much.
local function onEat(player: Player, foodId)
	local profile = S.PlayerService.getProfile(player)
	if not profile or not S.PlayerService.getCharacter(player) then
		return false, "You can't eat right now."
	end
	if profile.hunger >= Game.HUNGER_MAX - 1 then
		return false, "You're already full!"
	end
	if type(foodId) ~= "string" then
		local missing = Game.HUNGER_MAX - profile.hunger
		local best, bestScore = nil, math.huge
		for id, count in pairs(profile.food) do
			local item = Food.get(id)
			if item and count > 0 then
				-- prefer the snack that best matches how hungry you are, then the cheapest
				local score = math.abs(missing - item.food) + item.sell * 0.05
				if score < bestScore then
					best, bestScore = id, score
				end
			end
		end
		foodId = best
	end
	local item = foodId and Food.get(foodId)
	if not item or (profile.food[foodId] or 0) <= 0 then
		return false, "You have no food! Hunt animals or go fishing."
	end
	profile.food[foodId] -= 1
	if profile.food[foodId] <= 0 then
		profile.food[foodId] = nil
	end
	SurvivalService.feed(player, item.food)
	S.PlayerService.notify(player, string.format("You ate %s %s. (+%d hunger)", item.icon, item.name, item.food), item.color, "😋")
	return true
end

local function onSellFood(player: Player, foodId, count)
	local profile = S.PlayerService.getProfile(player)
	local item = type(foodId) == "string" and Food.get(foodId)
	if not profile or not item then
		return false, "Unknown food."
	end
	if not S.ShopService.isNear(player, { "Exchange" }) then
		return false, "Sell food at the Hoard Exchange in town."
	end
	local have = profile.food[foodId] or 0
	count = math.clamp(math.floor(tonumber(count) or 1), 1, have)
	if have <= 0 then
		return false, "You don't have any."
	end
	profile.food[foodId] = have - count
	if profile.food[foodId] <= 0 then
		profile.food[foodId] = nil
	end
	local gold = S.PlayerService.addGold(player, item.sell * count)
	S.PlayerService.markDirty(player)
	return true, gold
end

function SurvivalService.onDied(player: Player)
	local profile = S.PlayerService.getProfile(player)
	if profile and profile.hunger < Game.HUNGER_AFTER_DEATH then
		profile.hunger = Game.HUNGER_AFTER_DEATH
		publish(player, profile)
	end
end

function SurvivalService.init(services)
	S = services
end

function SurvivalService.start()
	Remotes.func("EatFood").OnServerInvoke = onEat
	Remotes.func("SellFood").OnServerInvoke = onSellFood
	Players.PlayerRemoving:Connect(function(player)
		lastLevel[player] = nil
	end)

	local dirtyTick = 0
	while true do
		task.wait(1)
		dirtyTick += 1
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = S.PlayerService.getProfile(player)
			local character, _, root = S.PlayerService.getCharacter(player)
			if profile and profile.class then
				if character and not S.BossService.isInFight(player) then
					local stats = S.PlayerService.getStats(player)
					local rate = Game.HUNGER_DRAIN * (1 - (stats and stats.hungerPct or 0) / 100)
					if character:GetAttribute("Flying") then
						rate *= Game.HUNGER_FLYING_MULT
					end
					local area = Zones.areaAt(root.Position)
					if area and area.safe then
						rate *= Game.HUNGER_TOWN_MULT
					end
					profile.hunger = math.max(0, profile.hunger - rate)
				end
				publish(player, profile)
				if dirtyTick % 10 == 0 then
					S.PlayerService.markDirty(player)
				end
			end
		end
	end
end

return SurvivalService
