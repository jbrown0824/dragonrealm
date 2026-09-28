-- Everything about an item is derived from its small saved record:
--   { id = "guid", slot = "Claws", ilvl = 12, rarity = "Rare", up = 3, uniq = "RagnarsIcebreaker"? }

local HttpService = game:GetService("HttpService")

local Items = require(script.Parent.Config.Items)
local Util = require(script.Parent.Util)

local ItemUtil = {}

local STAT_ORDER = { "attack", "health", "defense", "crit", "speed" }

function ItemUtil.new(slot: string, ilvl: number, rarity: string, uniq: string?)
	return {
		id = HttpService:GenerateGUID(false),
		slot = slot,
		ilvl = math.max(1, math.floor(ilvl)),
		rarity = rarity,
		up = 0,
		uniq = uniq,
	}
end

function ItemUtil.power(item): number
	local rarity = Items.Rarities[item.rarity] or Items.Rarities.Common
	local p = (4 + item.ilvl * 1.6) * rarity.mult * (1 + 0.1 * (item.up or 0))
	if item.uniq then
		p *= 1.15
	end
	return p
end

function ItemUtil.getStats(item)
	local p = ItemUtil.power(item)
	local stats = {}
	for stat, weight in pairs(Items.SlotStats[item.slot] or {}) do
		stats[stat] = (stats[stat] or 0) + p * weight
	end
	local unique = item.uniq and Items.Uniques[item.uniq]
	if unique then
		for stat, weight in pairs(unique.bonus) do
			stats[stat] = (stats[stat] or 0) + p * weight
		end
	end
	for stat, v in pairs(stats) do
		if stat == "crit" or stat == "speed" then
			stats[stat] = Util.round(v, 1)
		else
			stats[stat] = math.floor(v + 0.5)
		end
	end
	return stats
end

function ItemUtil.describeStats(stats): { string }
	local lines = {}
	for _, stat in ipairs(STAT_ORDER) do
		local v = stats[stat]
		if v and v ~= 0 then
			if stat == "crit" or stat == "speed" then
				table.insert(lines, string.format("+%s%s", Util.fmt(v), Items.StatLabels[stat]))
			else
				table.insert(lines, string.format("+%d %s", v, Items.StatLabels[stat]))
			end
		end
	end
	return lines
end

function ItemUtil.tierName(ilvl: number): string
	for _, tier in ipairs(Items.Tiers) do
		if ilvl <= tier.maxLevel then
			return tier.name
		end
	end
	return Items.Tiers[#Items.Tiers].name
end

function ItemUtil.baseName(item): string
	local unique = item.uniq and Items.Uniques[item.uniq]
	if unique then
		return unique.name
	end
	local pattern = Items.RarityNames[item.rarity] or "%s %s"
	local slotName = Items.SlotInfo[item.slot] and Items.SlotInfo[item.slot].name or item.slot
	return string.format(pattern, ItemUtil.tierName(item.ilvl), slotName)
end

function ItemUtil.displayName(item): string
	local name = ItemUtil.baseName(item)
	if (item.up or 0) > 0 then
		name ..= " +" .. item.up
	end
	return name
end

function ItemUtil.rarityColor(rarity: string): Color3
	local r = Items.Rarities[rarity]
	return r and r.color or Color3.new(1, 1, 1)
end

function ItemUtil.value(item): number
	local rarity = Items.Rarities[item.rarity] or Items.Rarities.Common
	local v = 6 * (4 + item.ilvl * 1.6) * rarity.mult ^ 1.6
	if item.uniq then
		v *= 1.5
	end
	return math.floor(v)
end

function ItemUtil.sellPrice(item): number
	return math.floor(ItemUtil.value(item) * (1 + 0.3 * (item.up or 0)))
end

function ItemUtil.buyPrice(item): number
	return ItemUtil.value(item) * 3
end

function ItemUtil.upgradeCost(item): number
	return math.floor(ItemUtil.value(item) * 0.35 * ((item.up or 0) + 1) ^ 1.35)
end

-- Rough single number for sorting / comparing gear.
function ItemUtil.score(item): number
	local s = ItemUtil.getStats(item)
	return (s.attack or 0) * 3 + (s.health or 0) * 0.35 + (s.defense or 0) * 2 + (s.crit or 0) * 6 + (s.speed or 0) * 4
end

-- Is `item` an upgrade over what's in its slot? (`equipped` = the worn item or nil)
function ItemUtil.isUpgrade(item, equipped): boolean
	if equipped == nil then
		return true
	end
	return item.id ~= equipped.id and ItemUtil.score(item) > ItemUtil.score(equipped) + 0.01
end

-- The best item for every slot from a list of items: { [slot] = item }
function ItemUtil.bestPerSlot(items)
	local best = {}
	for _, item in ipairs(items) do
		local current = best[item.slot]
		if not current or ItemUtil.score(item) > ItemUtil.score(current) then
			best[item.slot] = item
		end
	end
	return best
end

return ItemUtil
