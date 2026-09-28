-- The four viking camps in the Viking Lands. Each has a treasure chest in the middle (tag
-- "CampChest", opened through CampService) and room in front of its big building for the
-- camp's mini-boss (Zones.Camps[i].boss).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Config.Zones)

local Props = require(script.Parent.Props)
local WorldUtil = require(script.Parent.WorldUtil)

local Camps = {}

local rng = Random.new(90210)
local facingCF = WorldUtil.facingCF

local function chest(parent: Instance, camp)
	local c = camp.center
	local model = Props.chest(parent, facingCF(c, Vector3.new(0, 0, -1)), camp.id)
	CollectionService:AddTag(model, "CampChest")
end

local function angleDiff(a: number, b: number): number
	return math.abs(math.atan2(math.sin(a - b), math.cos(a - b)))
end

-- Calls fn(position, angle) around a ring, skipping any angle within 0.45 rad of `skip`.
local function scatterRing(center: Vector3, count: number, radius: number, jitter: number, skip: { number }?, fn)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-jitter, jitter)
		local ok = true
		for _, s in ipairs(skip or {}) do
			if angleDiff(a, s) < 0.45 then
				ok = false
			end
		end
		if ok then
			local p = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			fn(p, a)
		end
	end
end

-- A ring palisade with gate gaps at `gates` (radians, 0 = +X, pi/2 = +Z). The first gate gets
-- a watchtower on each side.
local function palisadeRing(parent: Instance, center: Vector3, radius: number, gates: { number }, height: number?)
	local segments = 16
	for i = 0, segments - 1 do
		local a1 = (i / segments) * math.pi * 2
		local a2 = ((i + 1) / segments) * math.pi * 2
		local mid = (a1 + a2) / 2
		local open = false
		for _, g in ipairs(gates) do
			if angleDiff(mid, g) < 0.35 then
				open = true
			end
		end
		if not open then
			Props.palisade(parent, center + Vector3.new(math.cos(a1) * radius, 0, math.sin(a1) * radius), center + Vector3.new(math.cos(a2) * radius, 0, math.sin(a2) * radius), height)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local a = gates[1] + side * 0.42
		Props.watchtower(parent, center + Vector3.new(math.cos(a) * (radius - 2), 0, math.sin(a) * (radius - 2)))
	end
end

-- Crates, barrels, firewood and weapon racks, kept out of `keepOut` circles ({ pos, radius }).
local function clutter(parent: Instance, center: Vector3, radius: number, count: number, keepOut)
	local placed, tries = 0, 0
	while placed < count and tries < count * 10 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(18, radius)
		local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local blocked = false
		for _, k in ipairs(keepOut or {}) do
			if (Vector3.new(p.X - k[1].X, 0, p.Z - k[1].Z)).Magnitude < k[2] + 4 then
				blocked = true
			end
		end
		if blocked then
			continue
		end
		placed += 1
		local roll = rng:NextNumber()
		if roll < 0.35 then
			Props.crate(parent, p)
		elseif roll < 0.65 then
			Props.barrel(parent, p)
		elseif roll < 0.85 then
			Props.firewood(parent, facingCF(p, center - p))
		else
			Props.weaponRack(parent, facingCF(p, center - p))
		end
	end
end

local function campSign(parent: Instance, pos: Vector3, facing: Vector3, text: string)
	Props.sign(parent, CFrame.lookAt(pos + Vector3.new(0, 5, 0), pos + Vector3.new(0, 5, 0) + facing), text, Vector2.new(11, 4.5))
end

local function raiderCamp(parent: Instance, camp)
	local f = WorldUtil.folder("RaiderCamp", parent)
	local c = camp.center
	-- gates: north toward town, then the roads to the other three camps
	local gates = { -math.pi / 2, math.pi / 2, math.atan2(170, 280), math.atan2(130, -280) }
	palisadeRing(f, c, 72, gates, 11)
	local colors = { Color3.fromRGB(170, 60, 50), Color3.fromRGB(200, 180, 140), Color3.fromRGB(120, 90, 60) }
	local tentSkips = table.clone(gates)
	table.insert(tentSkips, math.pi) -- the chieftain's tent
	local keepOut = { { c, 10 } }
	scatterRing(c, 10, 46, 0.1, tentSkips, function(p)
		Props.tent(f, facingCF(p, c - p), colors[rng:NextInteger(1, #colors)])
		table.insert(keepOut, { p, 6 })
	end)
	local bigTent = c + Vector3.new(-50, 0, -4)
	Props.bigTent(f, facingCF(bigTent, Vector3.new(1, 0, 0)), Color3.fromRGB(150, 40, 35))
	local fires = { c + Vector3.new(-18, 0, -26), c + Vector3.new(22, 0, -22) }
	for _, p in ipairs(fires) do
		Props.campfire(f, p)
	end
	table.insert(keepOut, { bigTent, 13 })
	table.insert(keepOut, { fires[1], 5 })
	table.insert(keepOut, { fires[2], 5 })
	clutter(f, c, 60, 14, keepOut)
	for _, x in ipairs({ -14, 14 }) do
		Props.banner(f, c + Vector3.new(x, 0, -66), Color3.fromRGB(170, 30, 30), Vector3.new(0, 0, -1))
	end
	chest(f, camp)
	campSign(f, c + Vector3.new(22, 0, -86), Vector3.new(0, 0, -1), "⚔️ Raider Camp\nLevel 1 - 4")
end

local function fishingVillage(parent: Instance, camp)
	local f = WorldUtil.folder("FishingVillage", parent)
	local c = camp.center
	for _, off in ipairs({ Vector3.new(-30, 0, -46), Vector3.new(12, 0, -54), Vector3.new(46, 0, -22), Vector3.new(40, 0, 32), Vector3.new(-8, 0, 50), Vector3.new(-44, 0, 36), Vector3.new(58, 0, 6) }) do
		local p = c + off
		Props.hut(f, facingCF(p, c - p))
	end
	-- boathouse on the shore
	Props.longhouse(f, facingCF(c + Vector3.new(-62, 0, -44), Vector3.new(1, 0, 0)), 24, 14)
	Props.campfire(f, c + Vector3.new(18, 0, 14))
	local villageKeepOut = { { c + Vector3.new(18, 0, 14), 5 }, { c, 10 }, { c + Vector3.new(-62, 0, -44), 16 }, { c + Vector3.new(28, 0, -34), 6 } }
	-- longships out on the lake and docks reaching toward them
	Props.longship(f, CFrame.new(-458, Zones.WATER_LEVEL + 1.5, 560) * CFrame.Angles(0, math.rad(10), 0))
	Props.longship(f, CFrame.new(-446, Zones.WATER_LEVEL + 1.5, 632) * CFrame.Angles(0, math.rad(-15), 0))
	for _, z in ipairs({ 580, 624 }) do
		Props.part(f, Vector3.new(44, 1, 6), CFrame.new(-408, 0.6, z), Color3.fromRGB(130, 95, 60), Enum.Material.WoodPlanks)
		for x = -428, -388, 10 do
			Props.column(f, Vector3.new(x, -12, z + 3), 13, 1, Props.DARK_WOOD, Enum.Material.Wood)
		end
	end
	-- fish drying racks
	for _, p in ipairs({ c + Vector3.new(-22, 0, 12), c + Vector3.new(22, 0, -12), c + Vector3.new(0, 0, 28) }) do
		Props.column(f, p + Vector3.new(-4, 0, 0), 6, 0.5, Props.DARK_WOOD, Enum.Material.Wood)
		Props.column(f, p + Vector3.new(4, 0, 0), 6, 0.5, Props.DARK_WOOD, Enum.Material.Wood)
		Props.beam(f, p + Vector3.new(-4, 5.5, 0), p + Vector3.new(4, 5.5, 0), 0.4, Props.DARK_WOOD, Enum.Material.Wood)
		for i = -3, 3 do
			Props.ellipsoid(f, Vector3.new(0.6, 1.8, 0.4), CFrame.new(p + Vector3.new(i, 4.4, 0)), Color3.fromRGB(170, 180, 190), Enum.Material.SmoothPlastic)
		end
	end
	-- stone well
	Props.column(f, c + Vector3.new(28, 0, -34), 3, 7, Color3.fromRGB(130, 130, 135), Enum.Material.Cobblestone)
	Props.roof(f, CFrame.new(c + Vector3.new(28, 6, -34)), 7, 7, 0, 3, Color3.fromRGB(120, 80, 50), Enum.Material.WoodPlanks)
	for _, off in ipairs({ Vector3.new(-30, 0, -46), Vector3.new(12, 0, -54), Vector3.new(46, 0, -22), Vector3.new(40, 0, 32), Vector3.new(-8, 0, 50), Vector3.new(-44, 0, 36), Vector3.new(58, 0, 6), Vector3.new(-22, 0, 12), Vector3.new(22, 0, -12), Vector3.new(0, 0, 28) }) do
		table.insert(villageKeepOut, { c + off, 8 })
	end
	clutter(f, c, 62, 12, villageKeepOut)
	chest(f, camp)
	campSign(f, c + Vector3.new(70, 0, -52), Vector3.new(1, 0, -1), "🎣 Fishing Village\nLevel 5 - 10")
end

local function longhouseHold(parent: Instance, camp)
	local f = WorldUtil.folder("LonghouseHold", parent)
	local c = camp.center
	local gate = math.atan2(-1, -1) -- toward town (north-west)
	palisadeRing(f, c, 84, { gate }, 12)
	Props.longhouse(f, facingCF(c + Vector3.new(0, 0, 58), Vector3.new(0, 0, -1)), 48, 22) -- the Thane's hall
	Props.longhouse(f, facingCF(c + Vector3.new(-50, 0, 12), Vector3.new(1, 0, 0)), 36)
	Props.longhouse(f, facingCF(c + Vector3.new(50, 0, 8), Vector3.new(-1, 0, 0)), 36)
	Props.watchtower(f, c + Vector3.new(-40, 0, 62))
	Props.watchtower(f, c + Vector3.new(44, 0, -48))
	Props.campfire(f, c + Vector3.new(-18, 0, -26))
	-- forge: stone hearth and anvil
	local forge = c + Vector3.new(24, 0, -34)
	Props.part(f, Vector3.new(6, 4, 5), CFrame.new(forge + Vector3.new(0, 2, 0)), Color3.fromRGB(90, 85, 85), Enum.Material.Slate)
	local glow = Props.part(f, Vector3.new(3.5, 0.6, 3), CFrame.new(forge + Vector3.new(0, 4.2, 0)), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
	Props.fire(glow, 4)
	Props.part(f, Vector3.new(3, 1.3, 1.5), CFrame.new(forge + Vector3.new(6, 2.2, 0)), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	for _, off in ipairs({ Vector3.new(-30, 0, -34), Vector3.new(30, 0, 44), Vector3.new(-14, 0, 40), Vector3.new(14, 0, 40) }) do
		Props.banner(f, c + off, Color3.fromRGB(40, 70, 150), Vector3.new(-1, 0, -1))
	end
	clutter(f, c, 66, 12, {
		{ c + Vector3.new(0, 0, 58), 26 }, { c + Vector3.new(-50, 0, 12), 20 }, { c + Vector3.new(50, 0, 8), 20 },
		{ c + Vector3.new(-18, 0, -26), 5 }, { forge, 8 }, { c, 10 }, { c + Vector3.new(-40, 0, 62), 7 }, { c + Vector3.new(44, 0, -48), 7 },
	})
	chest(f, camp)
	campSign(f, c + Vector3.new(-76, 0, -82), Vector3.new(-1, 0, -1), "🛡️ Longhouse Hold\nLevel 10 - 17")
end

local function jarlsFortress(parent: Instance, camp)
	local f = WorldUtil.folder("JarlsFortress", parent)
	local c = camp.center
	local hx, hz = 95, 85
	local nw, ne = c + Vector3.new(-hx, 0, -hz), c + Vector3.new(hx, 0, -hz)
	local sw, se = c + Vector3.new(-hx, 0, hz), c + Vector3.new(hx, 0, hz)
	Props.stoneWall(f, nw, c + Vector3.new(-16, 0, -hz), 16, 5)
	Props.stoneWall(f, c + Vector3.new(16, 0, -hz), ne, 16, 5)
	Props.stoneWall(f, nw, sw, 16, 5)
	Props.stoneWall(f, ne, se, 16, 5)
	Props.stoneWall(f, sw, se, 16, 5)
	for _, p in ipairs({ nw, ne, sw, se, c + Vector3.new(-20, 0, -hz), c + Vector3.new(20, 0, -hz) }) do
		Props.tower(f, p, 24, 11, Color3.fromRGB(110, 30, 30))
	end
	-- the Jarl's great hall and two barracks
	Props.longhouse(f, facingCF(c + Vector3.new(0, 0, 58), Vector3.new(0, 0, -1)), 60, 26)
	Props.longhouse(f, facingCF(c + Vector3.new(-62, 0, 16), Vector3.new(1, 0, 0)), 34)
	Props.longhouse(f, facingCF(c + Vector3.new(62, 0, 16), Vector3.new(-1, 0, 0)), 34)
	-- horn towers where the Hornblowers keep watch
	Props.hornTower(f, c + Vector3.new(-40, 0, -64))
	Props.hornTower(f, c + Vector3.new(40, 0, -64))
	for z = -70, 26, 16 do
		Props.torch(f, c + Vector3.new(-14, 0, z), Color3.fromRGB(255, 120, 50))
		Props.torch(f, c + Vector3.new(14, 0, z), Color3.fromRGB(255, 120, 50))
	end
	for _, off in ipairs({ Vector3.new(-40, 0, 10), Vector3.new(40, 0, 10), Vector3.new(-25, 0, -48), Vector3.new(25, 0, -48) }) do
		Props.banner(f, c + off, Color3.fromRGB(120, 40, 160), Vector3.new(0, 0, -1))
	end
	Props.campfire(f, c + Vector3.new(-46, 0, -26))
	Props.campfire(f, c + Vector3.new(46, 0, -26))
	for _, x in ipairs({ -70, -58, 58, 70 }) do
		Props.weaponRack(f, facingCF(c + Vector3.new(x, 0, -30), Vector3.new(0, 0, -1)))
	end
	clutter(f, c, 78, 10, {
		{ c + Vector3.new(0, 0, 58), 32 }, { c + Vector3.new(-62, 0, 16), 19 }, { c + Vector3.new(62, 0, 16), 19 },
		{ c + Vector3.new(-40, 0, -64), 7 }, { c + Vector3.new(40, 0, -64), 7 }, { c + Vector3.new(-46, 0, -26), 5 },
		{ c + Vector3.new(46, 0, -26), 5 }, { c, 10 }, { c + Vector3.new(0, 0, -30), 16 },
	})
	chest(f, camp)
	campSign(f, c + Vector3.new(30, 0, -hz - 14), Vector3.new(0, 0, -1), "🏰 Jarl's Fortress\nLevel 18 - 28")
end

function Camps.build(parent: Instance)
	local builders = {
		RaiderCamp = raiderCamp,
		FishingVillage = fishingVillage,
		LonghouseHold = longhouseHold,
		JarlsFortress = jarlsFortress,
	}
	for _, camp in ipairs(Zones.Camps) do
		local fn = builders[camp.id]
		if fn then
			fn(parent, camp)
		end
	end
end

return Camps
