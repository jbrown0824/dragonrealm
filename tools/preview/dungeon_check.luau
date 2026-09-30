-- Dungeon check: carves every dungeon (DungeonBuilder) and walks it on the terrain.
--   * every marker (the entrance, the way out, each monster, the bosses, the hoard) stands on a
--     floor with room above it
--   * every tunnel, each room's way from its middle to its tunnel mouths and monsters, the spiral
--     ramp and the dungeon's extra `routes` are walkable: the floor never jumps more than STEP
--     between samples 2 studs apart, and there's HEADROOM above it the whole way
-- Prints a line per dungeon and "N dungeon problems" at the end. With DUNGEON_MAP = "<id>" set
-- (prepend a line), it prints the floor map of that dungeon instead ("x z floorY material" rows,
-- for dungeon_map.py).
local Dungeons = require(__proxy("Shared/Config/Dungeons"))
local DungeonBuilder = require(__proxy("Server/World/DungeonBuilder"))

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

local function inside(sp, p: Vector3): boolean
	local d = p - sp.at
	if sp.kind == "box" then
		return math.abs(d.X) <= sp.size.X / 2 + 1 and math.abs(d.Z) <= sp.size.Y / 2 + 1
	elseif sp.kind == "round" then
		return Vector3.new(d.X, 0, d.Z).Magnitude <= sp.radius + 1
	end
	return false
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
	local waypoints = {}
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "path" then
			for i, p in ipairs(sp.points) do
				table.insert(waypoints, p)
				if i > 1 then
					problem(walk(sp.id .. " " .. (i - 1), origin + sp.points[i - 1], origin + p))
				end
			end
		elseif sp.hub ~= false then
			table.insert(waypoints, sp.at)
		end
	end
	for _, route in ipairs(def.routes or {}) do
		for _, p in ipairs(route) do
			table.insert(waypoints, p)
		end
	end
	for _, f in ipairs(def.features or {}) do
		if f.kind == "spiral" then
			local mid = (f.inner + f.outer) / 2
			for k = 0, 1.0001, 0.1 do
				local a = math.rad(f.from + (f.to - f.from) * k)
				table.insert(waypoints, f.center + Vector3.new(math.cos(a) * mid, f.topY + (f.bottomY - f.topY) * k - f.center.Y, math.sin(a) * mid))
			end
		end
	end
	-- each room: from its middle to the tunnel mouths inside it
	for _, room in ipairs(def.spaces) do
		if room.kind ~= "path" and room.hub ~= false then
			for _, sp in ipairs(def.spaces) do
				if sp.kind == "path" then
					for _, p in ipairs({ sp.points[1], sp.points[#sp.points] }) do
						if inside(room, p) then
							problem(walk(room.id .. " to " .. sp.id, origin + room.at, origin + p))
						end
					end
				end
			end
		end
	end
	-- each monster: stands on a floor, and can walk to the nearest waypoint
	for i, pack in ipairs(def.packs) do
		for j, entry in ipairs(Dungeons.packMobs(pack)) do
			local label = string.format("pack %d mob %d (%s)", i, j, entry[1])
			marker(label, entry[2])
			local best, bestDist = nil, math.huge
			for _, w in ipairs(waypoints) do
				local d = (w - entry[2]).Magnitude
				if d < bestDist then
					best, bestDist = w, d
				end
			end
			problem(walk(label .. " to the way", origin + entry[2], origin + best))
		end
	end
	for _, f in ipairs(def.features or {}) do
		if f.kind == "spiral" then
			local mid = (f.inner + f.outer) / 2
			local last = nil
			for k = 0, 1.0001, 0.05 do
				local a = math.rad(f.from + (f.to - f.from) * k)
				local p = origin + f.center + Vector3.new(math.cos(a) * mid, f.topY + (f.bottomY - f.topY) * k - f.center.Y, math.sin(a) * mid)
				if last then
					problem(walk("spiral", last, p))
				end
				last = p
			end
		end
	end
	for i, route in ipairs(def.routes or {}) do
		for j = 2, #route do
			problem(walk("route " .. i, origin + route[j - 1], origin + route[j]))
		end
	end
	problems += #found
	print(string.format("%s %-8s %d spaces, %d packs, %d problems", #found == 0 and "ok  " or "BAD ", def.id, #def.spaces, #def.packs, #found))
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
