-- Permanent dragon upgrades sold at the Bubbling Cauldron in town. Each potion has several
-- ranks; every rank adds `stats` again (stat keys are the same ones talents use, see
-- StatCalc.STAT_INFO). Rank N costs `costs[N] * (costMult or 1)` gold.

local Potions = {}

Potions.Order = { "WingTonic", "GaleDraught", "SwiftclawBrew", "HeartbloodElixir", "IronBellyStew", "EmberheartTonic", "StoneskinDraught" }

Potions.COSTS = { 300, 750, 1500, 3000, 6000 }

Potions.WingTonic = {
	id = "WingTonic", name = "Wing Tonic", icon = "💨", color = Color3.fromRGB(120, 220, 255),
	stats = { staminaPct = 12 },
	desc = "Stronger wing muscles: fly longer before you tire.",
}
Potions.GaleDraught = {
	id = "GaleDraught", name = "Gale Draught", icon = "🌬️", color = Color3.fromRGB(170, 240, 230),
	stats = { flightSpeedPct = 6 },
	desc = "Catch the wind: fly faster.",
}
Potions.SwiftclawBrew = {
	id = "SwiftclawBrew", name = "Swiftclaw Brew", icon = "👟", color = Color3.fromRGB(255, 220, 120),
	stats = { speedPct = 4 },
	desc = "Quicker claws: walk and run faster.",
}
Potions.HeartbloodElixir = {
	id = "HeartbloodElixir", name = "Heartblood Elixir", icon = "❤️", color = Color3.fromRGB(255, 110, 120),
	stats = { healthPct = 5 },
	desc = "A thicker, hotter heart: more max health.",
}
Potions.IronBellyStew = {
	id = "IronBellyStew", name = "Iron Belly Stew", icon = "🍖", color = Color3.fromRGB(220, 160, 110),
	stats = { hungerPct = 10 }, costMult = 0.7,
	desc = "A stomach like a furnace: hunger drops slower, so you go longer between meals.",
}
Potions.EmberheartTonic = {
	id = "EmberheartTonic", name = "Emberheart Tonic", icon = "🔥", color = Color3.fromRGB(255, 140, 60),
	stats = { attackPct = 3 }, costMult = 1.2,
	desc = "Stoke your inner fire: hit harder with everything.",
}
Potions.StoneskinDraught = {
	id = "StoneskinDraught", name = "Stoneskin Draught", icon = "🛡️", color = Color3.fromRGB(180, 180, 190),
	stats = { defensePct = 5 },
	desc = "Scales like granite: more defense.",
}

function Potions.get(id: string)
	local p = Potions[id]
	if type(p) == "table" and p.id then
		return p
	end
	return nil
end

function Potions.maxRank(): number
	return #Potions.COSTS
end

-- Gold for the next rank (rank = ranks already owned), or nil when maxed.
function Potions.cost(id: string, rank: number): number?
	local p = Potions.get(id)
	local base = p and Potions.COSTS[rank + 1]
	if not base then
		return nil
	end
	return math.floor(base * (p.costMult or 1) / 10 + 0.5) * 10
end

return Potions
