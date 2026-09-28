-- The Bubbling Cauldron: permanent potion upgrades (Config/Potions). Each purchase adds one
-- rank; the bonus shows up in your stats through BonusUtil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Potions = require(Shared.Config.Potions)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local PotionService = {}
local S

local function onBuy(player: Player, potionId)
	local potion = type(potionId) == "string" and Potions.get(potionId)
	local profile = S.PlayerService.getProfile(player)
	if not potion or not profile then
		return false, "Unknown potion."
	end
	if not S.ShopService.isNear(player, { "Alchemist" }) then
		return false, "Visit the Bubbling Cauldron in town to buy potions."
	end
	local rank = profile.potions[potionId] or 0
	local cost = Potions.cost(potionId, rank)
	if not cost then
		return false, potion.name .. " is already at max rank."
	end
	if not S.PlayerService.spendGold(player, cost) then
		return false, string.format("You need %s gold.", Util.formatNumber(cost))
	end
	profile.potions[potionId] = rank + 1
	S.PlayerService.recompute(player)
	S.QuestService.progress(player, "potion", potionId, 1)
	local character = player.Character
	if character then
		S.CombatService.broadcastVFX({ kind = "potion", character = character, color = potion.color })
	end
	return true, rank + 1
end

-- Admin panel: set every potion to a rank.
function PotionService.setAll(player: Player, rank: number)
	local profile = S.PlayerService.getProfile(player)
	if not profile then
		return
	end
	for _, id in ipairs(Potions.Order) do
		profile.potions[id] = math.clamp(rank, 0, Potions.maxRank())
	end
	S.PlayerService.recompute(player)
end

function PotionService.init(services)
	S = services
end

function PotionService.start()
	Remotes.func("BuyPotion").OnServerInvoke = onBuy
end

return PotionService
