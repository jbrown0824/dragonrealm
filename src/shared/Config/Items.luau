-- Gear definitions. Items are stored as tiny records { id, slot, ilvl, rarity, up, uniq }
-- and everything else (name, stats, value) is derived in ItemUtil, so balancing changes here
-- apply to items players already own.

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Items = {}

Items.Slots = { "Head", "Body", "Claws", "Tail", "Charm" }

Items.SlotInfo = {
	Head = { name = "Horn Crown", icon = "👑" },
	Body = { name = "Scale Plating", icon = "🛡️" },
	Claws = { name = "Claw Blades", icon = "🗡️" },
	Tail = { name = "Tail Spike", icon = "🦂" },
	Charm = { name = "Amulet", icon = "📿" },
}

-- How much of each stat an item of a slot gets per point of item power.
Items.SlotStats = {
	Head = { health = 2.2, defense = 0.22 },
	Body = { health = 3.0, defense = 0.35 },
	Claws = { attack = 0.35, crit = 0.05 },
	Tail = { attack = 0.2, health = 1.0, speed = 0.08 },
	Charm = { attack = 0.15, health = 1.0, crit = 0.04 },
}

Items.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

Items.Rarities = {
	Common = { mult = 1.0, color = rgb(205, 205, 205), weight = 62, rank = 1 },
	Uncommon = { mult = 1.25, color = rgb(90, 225, 90), weight = 24, rank = 2 },
	Rare = { mult = 1.6, color = rgb(80, 160, 255), weight = 10, rank = 3 },
	Epic = { mult = 2.1, color = rgb(195, 95, 255), weight = 3.4, rank = 4 },
	Legendary = { mult = 2.8, color = rgb(255, 165, 40), weight = 0.6, rank = 5 },
}

-- Name material by item level.
Items.Tiers = {
	{ maxLevel = 7, name = "Bronze" },
	{ maxLevel = 15, name = "Iron" },
	{ maxLevel = 23, name = "Runed" },
	{ maxLevel = 30, name = "Dragonbone" },
	{ maxLevel = math.huge, name = "Starforged" },
}

Items.RarityNames = {
	Common = "%s %s",
	Uncommon = "Fine %s %s",
	Rare = "%s %s of Embers",
	Epic = "%s %s of Fury",
	Legendary = "Ancient %s %s",
}

-- Boss-only legendaries with a fixed name and a bonus stat on top of normal stats.
Items.Uniques = {
	FrostbeardCrown = { name = "Frostbeard's Crown", slot = "Head", bonus = { defense = 0.3 } },
	RagnarsIcebreaker = { name = "Ragnar's Icebreaker", slot = "Claws", bonus = { attack = 0.2 } },
	StormcallerCharm = { name = "Stormcaller's Rune", slot = "Charm", bonus = { crit = 0.08 } },
	GrimhildasVeil = { name = "Grimhilda's Veil", slot = "Body", bonus = { health = 2.0 } },
	DragonslayerBane = { name = "Dragonslayer's Bane", slot = "Tail", bonus = { attack = 0.25 } },
	HrothgarsHeart = { name = "Heart of Hrothgar", slot = "Body", bonus = { defense = 0.3, health = 1.0 } },
}

Items.StatLabels = {
	attack = "Attack",
	health = "Health",
	defense = "Defense",
	crit = "% Crit Chance",
	speed = "% Speed",
}

return Items
