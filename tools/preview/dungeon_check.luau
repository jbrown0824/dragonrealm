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
--   * a rune shield's guard spots (phases[].shield.spots) stand on the floor of the boss's room,
--     out of the lava and off any ledge, with a straight walk from the room's middle
--   * the "Way out" signs are up, flat on a wall; a shut boss door leaves no gap across its opening
--   * each cave mouth out in the viking lands is open: no hill or rock across the doorway, the
--     passage behind it, or the way up to it (the hill once buried it), and a hill behind it
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
	-- a rune shield's guards: fixed spots on the boss room's floor
	for _, spec in ipairs({ def.miniBoss, def.boss }) do
		local b = Dungeons.Bosses[spec.id]
		local room = nil
		for _, sp in ipairs(def.spaces) do
			if sp.id == spec.room then
				room = sp
			end
		end
		for _, ph in ipairs(b.phases or {}) do
			for k, spot in ipairs(ph.shield and ph.shield.spots or {}) do
				local label = string.format("%s's guard spot %d", spec.id, k)
				marker(label, spot)
				if DungeonNav.inHazard(def, spot) then
					problem(label .. " stands in lava")
				end
				for _, f in ipairs(def.features or {}) do
					if f.kind == "ledge" and spot.X >= f.min.X - 4 and spot.X <= f.max.X + 4 and spot.Z >= f.min.Z - 4 and spot.Z <= f.max.Z + 4 then
						problem(label .. " is on (or in) a ledge")
					end
				end
				if not room or not DungeonNav.spaceHas(room, spot) then
					problem(label .. " isn't in " .. spec.room)
				elseif not DungeonNav.direct(def, Vector3.new(room.at.X, spot.Y, room.at.Z), spot) then
					problem(label .. ": no straight walk from the middle of " .. spec.room)
				end
			end
		end
	end
	-- the way out signs: on a wall (rock right behind them, air in front), not hanging in a doorway
	local function solidAt(p: Vector3): boolean
		for _, iv in ipairs(solids(p.X, p.Z)) do
			if p.Y >= iv[1] and p.Y <= iv[2] then
				return true
			end
		end
		return false
	end
	local signs = 0
	for _, d in ipairs(built.model:GetDescendants()) do
		if d.Name == "WayOutSign" then
			signs += 1
			local look = d.CFrame.LookVector
			if not solidAt(d.Position - look * 2.5) or solidAt(d.Position + look * 3) then
				problem(string.format("a Way out sign at (%.0f, %.0f, %.0f) isn't on a wall", d.Position.X - origin.X, d.Position.Y - origin.Y, d.Position.Z - origin.Z))
			end
		end
	end
	if signs == 0 then
		problem("no Way out signs")
	end
	-- a shut boss door seals its whole opening: every point across the door's plane is rock, a
	-- leaf or a jamb (an angled tunnel's mouth is wider than the tunnel)
	local function inPart(model: Instance, p: Vector3): boolean
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				local rel = part.CFrame:PointToObjectSpace(p)
				local half = part.Size / 2
				if math.abs(rel.X) <= half.X + 0.6 and math.abs(rel.Y) <= half.Y + 0.6 and math.abs(rel.Z) <= half.Z + 0.6 then
					return true
				end
			end
		end
		return false
	end
	for i, door in ipairs(built.doors or {}) do
		local across = Vector3.new(-door.dir.Z, 0, door.dir.X)
		local gaps = 0
		for x = -(door.width / 2 + 10), door.width / 2 + 10, 1.5 do
			for y = 2, door.height - 2, 3 do
				local p = door.pos + across * x + Vector3.new(0, y, 0)
				if not solidAt(p) and not inPart(door.model, p) then
					gaps += 1
				end
			end
		end
		if gaps > 0 then
			problem(string.format("door %d (%s) has %d gaps a dragon could slip through", i, door.room, gaps))
		end
	end
	problems += #found
	print(string.format("%s %-8s %d spaces, %d packs, %d map nodes, %d doors, %d way out signs, %d problems", #found == 0 and "ok  " or "BAD ", def.id, #def.spaces, #def.packs, #DungeonNav.graph(def).nodes, #(built.doors or {}), signs, #found))
	for _, msg in ipairs(found) do
		print("     " .. msg)
	end
end

for _, id in ipairs(Dungeons.Order) do
	if not DUNGEON_MAP or DUNGEON_MAP == id then
		check(Dungeons.List[id])
	end
end

-- The cave mouths out in the viking lands (on a flat patch of the world's ground block).
local function checkEntrance(def)
	local found = {}
	local e = def.entrance
	workspace.Terrain:FillBlock(CFrame.new(e.X, -8, e.Z), Vector3.new(240, 16, 240), Enum.Material.Grass)
	local model = DungeonBuilder.entrance(folder, def)
	TERRAIN_PREPARE() -- (index the new terrain edits)
	local M = DungeonBuilder.MOUTH
	local top = M.leg + M.radius
	local face = def.entranceFacing.Unit
	local base = Vector3.new(e.X, 0, e.Z)
	local cf = CFrame.lookAt(base, base + face)
	-- solid terrain across the doorway's height at a spot (in the mouth's frame)
	local function blocked(dx: number, dz: number): boolean
		local p = (cf * CFrame.new(dx, 0, dz)).Position
		for _, iv in ipairs(solids(p.X, p.Z)) do
			if iv[2] > base.Y + 1 and iv[1] < base.Y + top - 1 then
				return true
			end
		end
		return false
	end
	for _, dx in ipairs({ -(M.half - 2), 0, M.half - 2 }) do
		for _, dz in ipairs({ -14, -8, -3, 2, 8, M.depth - 3 }) do
			if blocked(dx, dz) then
				table.insert(found, string.format("terrain in the %s at (%d, %d)", dz < 0 and "way up to the mouth" or "passage", dx, dz))
			end
		end
	end
	local behind = (cf * CFrame.new(0, 0, M.depth + 8)).Position
	local hill = 0
	for _, iv in ipairs(solids(behind.X, behind.Z)) do
		hill = math.max(hill, iv[2])
	end
	if hill < base.Y + top then
		table.insert(found, string.format("no hill behind the mouth (%.0f high)", hill - base.Y))
	end
	-- nothing solid standing in the way up to the doorway
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			local rel = cf:PointToObjectSpace(part.Position)
			if math.abs(rel.X) < M.half and rel.Z < -3 and rel.Z > -14 and rel.Y < top then
				table.insert(found, string.format("a part (%s) stands in front of the doorway", part.Name))
			end
		end
	end
	problems += #found
	print(string.format("%s %-8s cave mouth, %d problems", #found == 0 and "ok  " or "BAD ", def.id, #found))
	for _, msg in ipairs(found) do
		print("     " .. msg)
	end
end
if not DUNGEON_MAP then
	for _, id in ipairs(Dungeons.Order) do
		checkEntrance(Dungeons.List[id])
	end
end
if not DUNGEON_MAP then
	print(string.format("%d dungeon problems", problems))
end
