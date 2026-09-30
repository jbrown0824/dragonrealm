-- Dungeon check: carves every dungeon (DungeonBuilder) and walks it on the terrain.
--   * every marker (the entrance, the way out, each monster, the bosses, the hoard) stands on a
--     floor with room above it
--   * every walk in the monsters' map (DungeonNav.graph: tunnels, each room's middle to its tunnel
--     mouths, the spiral ramp, the extra `routes`, near neighbours) is walkable: the floor never
--     jumps more than STEP between samples 2 studs apart, and there's HEADROOM above it the whole way;
--     and every node of it can be reached from the entrance
--   * each monster, boss, the keeper, the provisions and the hoard stand out of the lava and can
--     walk to the map; monsters of different packs start Dungeons.PACK_SPACING apart
--   * every boss room has its doors, and every patrol route is walkable
-- Prints a line per dungeon and "N dungeon problems" at the end. With DUNGEON_MAP = "<id>" set
-- (prepend a line), it prints the floor map of that dungeon instead ("x z floorY material" rows,
-- for dungeon_map.py).
local Dungeons = require(__proxy("Shared/Config/Dungeons"))
local DungeonBuilder = require(__proxy("Server/World/DungeonBuilder"))
local DungeonNav = require(__proxy("Shared/DungeonNav"))

local HEADROOM = 9
local STEP = 2.6
local problems = 0
local folder = Instance.new("Folder")
folder.Parent = workspace

-- Solid intervals only (water is somewhere you can wade through).
local function solids(x: number, z: number)
	local list = {}
	for _, iv in ipairs(TERRAIN_COLUMN(x, z)) do
		if iv[3] ~= "Water" then
			table.insert(list, iv)
		end
	end
	return list
end

-- The floor at (x, z) closest to height y with at least HEADROOM of air above it.
local function floorNear(x: number, z: number, y: number)
	local list = solids(x, z)
	local best, bestMat = nil, nil
	for i, iv in ipairs(list) do
		local above = list[i + 1]
		local ceiling = above and above[1] or math.huge
		if ceiling - iv[2] >= HEADROOM and math.abs(iv[2] - y) <= 9 then
			if not best or math.abs(iv[2] - y) < math.abs(best - y) then
				best, bestMat = iv[2], iv[3]
			end
		end
	end
	return best, bestMat
end

local function walk(label: string, a: Vector3, b: Vector3): string?
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local steps = math.max(1, math.ceil(flat.Magnitude / 2))
	local y = a.Y
	for i = 0, steps do
		local p = a + flat * (i / steps)
		local expect = y
		if i == 0 then
			expect = a.Y
		end
		local floor = floorNear(p.X, p.Z, expect)
		if not floor then
			return string.format("%s: no floor or no headroom at (%.0f, %.0f, %.0f)", label, p.X, expect, p.Z)
		end
		if i > 0 and math.abs(floor - y) > STEP then
			return string.format("%s: a %.1f stud step at (%.0f, %.0f)", label, floor - y, p.X, p.Z)
		end
		y = floor
	end
	if math.abs(y - b.Y) > 4 then
		return string.format("%s: ends at height %.1f, expected %.1f", label, y, b.Y)
	end
	return nil
end

local function check(def)
	local origin = Dungeons.origin(def.id, 1)
	local built = DungeonBuilder.interior(def, origin, folder)
	TERRAIN_PREPARE()
	if DUNGEON_MAP == def.id then
		local b = built.bounds
		for z = math.floor(b.min.Z), math.ceil(b.max.Z), 2 do
			for x = math.floor(b.min.X), math.ceil(b.max.X), 2 do
				-- the lowest cave floor with headroom in this column
				local list = solids(x, z)
				for i, iv in ipairs(list) do
					local above = list[i + 1]
					if above and above[1] - iv[2] >= HEADROOM and iv[2] > b.min.Y + 2 then
						print(string.format("%d %d %.1f %s", x - origin.X, z - origin.Z, iv[2] - origin.Y, iv[3]))
						break
					end
				end
			end
		end
		-- markers: M kind x z
		print(string.format("M spawn %d %d", def.spawn.X, def.spawn.Z))
		print(string.format("M exit %d %d", def.exit.X, def.exit.Z))
		for _, pack in ipairs(def.packs) do
			for _, entry in ipairs(Dungeons.packMobs(pack)) do
				print(string.format("M mob %d %d", entry[2].X, entry[2].Z))
			end
		end
		print(string.format("M mini %d %d", def.miniBoss.at.X, def.miniBoss.at.Z))
		print(string.format("M boss %d %d", def.boss.at.X, def.boss.at.Z))
		if def.chest then
			print(string.format("M chest %d %d", def.chest.X, def.chest.Z))
		end
		return
	end
	local found = {}
	local function problem(msg: string?)
		if msg then
			table.insert(found, msg)
		end
	end
	local function marker(label: string, p: Vector3)
		local w = origin + p
		local floor = floorNear(w.X, w.Z, w.Y)
		if not floor or math.abs(floor - w.Y) > 3 then
			problem(string.format("%s: no floor near (%.0f, %.0f, %.0f)", label, p.X, p.Y, p.Z))
		end
	end
	marker("entrance", def.spawn)
	marker("way out", def.exit)
	if def.chest then
		marker("hoard", def.chest)
	end
	marker("mini-boss", def.miniBoss.at)
	marker("boss", def.boss.at)
	for _, spot in ipairs({ { "keeper", def.keeper and def.keeper.at }, { "provisions", def.keeper and def.keeper.food } }) do
		if spot[2] then
			marker(spot[1], spot[2])
		end
	end
	-- the monsters' map: every walk in it, and all of it reachable from the entrance
	local graph = DungeonNav.graph(def)
	for _, edge in ipairs(graph.edges) do
		local a, b = graph.nodes[edge[1]], graph.nodes[edge[2]]
		problem(walk(string.format("walk (%.0f, %.0f, %.0f) - (%.0f, %.0f, %.0f)", a.X, a.Y, a.Z, b.X, b.Y, b.Z), origin + a, origin + b))
	end
	local function nearest(p: Vector3): number
		local best, bestDist = 1, math.huge
		for i, q in ipairs(graph.nodes) do
			local d = (q - p).Magnitude
			if d < bestDist then
				best, bestDist = i, d
			end
		end
		return best
	end
	local seen, queue = { [nearest(def.spawn)] = true }, { nearest(def.spawn) }
	while #queue > 0 do
		local i = table.remove(queue)
		for _, j in ipairs(graph.adj[i]) do
			if not seen[j] then
				seen[j] = true
				table.insert(queue, j)
			end
		end
	end
	for i, q in ipairs(graph.nodes) do
		if not seen[i] then
			problem(string.format("(%.0f, %.0f, %.0f) can't be reached from the entrance", q.X, q.Y, q.Z))
		end
	end
	-- each monster (and the bosses, the hoard...): out of the lava, and a walk to the map
	local spots = {}
	for i, pack in ipairs(def.packs) do
		for j, entry in ipairs(Dungeons.packMobs(pack)) do
			table.insert(spots, { string.format("pack %d mob %d (%s)", i, j, entry[1]), entry[2], i })
		end
	end
	table.insert(spots, { "mini-boss", def.miniBoss.at })
	table.insert(spots, { "boss", def.boss.at })
	if def.chest then
		table.insert(spots, { "hoard", def.chest })
	end
	for _, spot in ipairs(spots) do
		local label, p = spot[1], spot[2]
		marker(label, p)
		if DungeonNav.inHazard(def, p) then
			problem(label .. " stands in lava")
		end
		local w = graph.nodes[nearest(p)]
		problem(walk(label .. " to the way", origin + p, origin + w))
		if not DungeonNav.route(def, def.spawn, p) then
			problem(label .. ": no way there from the entrance")
		end
	end
	-- packs spread out (so fighting one doesn't happen right under the next one's nose)
	for i = 1, #spots do
		for j = i + 1, #spots do
			local a, b = spots[i], spots[j]
			if a[3] and b[3] and a[3] ~= b[3] then
				local d = Vector3.new(b[2].X - a[2].X, 0, b[2].Z - a[2].Z).Magnitude
				if d < Dungeons.PACK_SPACING then
					problem(string.format("%s and %s are only %.0f apart", a[1], b[1], d))
				end
			end
		end
	end
	-- patrol routes: every leg walkable, and the whole pack's formation on the floor at each stop
	for i, pack in ipairs(def.packs) do
		if pack.patrol then
			for j = 2, #pack.patrol do
				problem(walk(string.format("pack %d patrol leg %d", i, j - 1), origin + pack.patrol[j - 1], origin + pack.patrol[j]))
			end
			for j, stop in ipairs(pack.patrol) do
				for k, entry in ipairs(Dungeons.packMobs(pack)) do
					local p = stop + (entry[2] - pack.at)
					marker(string.format("pack %d patrol stop %d mob %d", i, j, k), p)
					if DungeonNav.inHazard(def, p) then
						problem(string.format("pack %d patrol stop %d: in the lava", i, j))
					end
				end
			end
		end
	end
	-- the spiral, in finer steps than the map's samples
	for _, f in ipairs(def.features or {}) do
		if f.kind == "spiral" then
			local last = nil
			for _, p in ipairs(DungeonNav.spiralPoints(f, 0.05)) do
				if last then
					problem(walk("spiral", origin + last, origin + p))
				end
				last = p
			end
		end
	end
	-- the boss rooms' doors
	for _, spec in ipairs({ def.miniBoss, def.boss }) do
		local n = 0
		for _, door in ipairs(built.doors or {}) do
			if door.room == spec.room then
				n += 1
			end
		end
		if n == 0 then
			problem(spec.room .. " (a boss room) has no doors")
		end
	end
	problems += #found
	print(string.format("%s %-8s %d spaces, %d packs, %d map nodes, %d doors, %d problems", #found == 0 and "ok  " or "BAD ", def.id, #def.spaces, #def.packs, #DungeonNav.graph(def).nodes, #(built.doors or {}), #found))
	for _, msg in ipairs(found) do
		print("     " .. msg)
	end
end

for _, id in ipairs(Dungeons.Order) do
	if not DUNGEON_MAP or DUNGEON_MAP == id then
		check(Dungeons.List[id])
	end
end
if not DUNGEON_MAP then
	print(string.format("%d dungeon problems", problems))
end
