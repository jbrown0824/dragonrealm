-- How monsters find their way around a dungeon, and what the dungeon check walks. Everything is
-- in the dungeon's own coordinates (Config/Dungeons, relative to its origin); y is floor height.
--
--   DungeonNav.graph(def)          nodes (tunnel points, room middles, routes, spiral samples) and
--                                  the walks between them (tools/preview/dungeon_check walks every one)
--   DungeonNav.route(def, a, b)    the node positions to go through from a to b (A*), or nil
--   DungeonNav.direct(def, a, b)   true when you can just walk straight from a to b: both in the
--                                  same hub room (climbing no more than a step) or the same stretch
--                                  of tunnel, with no lava in between
--   DungeonNav.inHazard(def, p)    standing in lava (a bridge's deck is safe)
--   DungeonNav.spaceHas(sp, p)     whether a floor point is inside a space
--
-- Rooms with `hub = false` (a lava channel, a pit) are never walked straight across: monsters go
-- over their bridges and down their ramps (the dungeon's `routes` and spirals).

local DungeonNav = {}

DungeonNav.LINK = 36 -- nodes this close, in the same space and with no lava between, are linked
DungeonNav.CLIMB = 4 -- the most a straight walk may climb (a ledge needs its ramp)

local cache = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Flat distance from p to the segment a-b, and how far along it (0-1) the closest point is.
local function segment(p: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab = flat(b - a)
	local ap = flat(p - a)
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
	return (ap - ab * t).Magnitude, t
end

-- Whether a floor point is inside a space (for tunnels, also which stretch of it).
function DungeonNav.spaceHas(sp, p: Vector3): (boolean, number?)
	if sp.kind == "box" then
		local d = p - sp.at
		return math.abs(d.X) <= sp.size.X / 2 and math.abs(d.Z) <= sp.size.Y / 2 and d.Y > -8 and d.Y < sp.height
	elseif sp.kind == "round" then
		local d = p - sp.at
		return flat(d).Magnitude <= sp.radius and d.Y > -8 and d.Y < sp.height
	end
	for i = 1, #sp.points - 1 do
		local a, b = sp.points[i], sp.points[i + 1]
		local dist, t = segment(p, a, b)
		if dist <= sp.width / 2 and math.abs(p.Y - (a.Y + (b.Y - a.Y) * t)) < 8 then
			return true, i
		end
	end
	return false, nil
end

-- On a bridge's deck (over the lava, but safe).
function DungeonNav.onBridge(def, p: Vector3): boolean
	for _, f in ipairs(def.features or {}) do
		if f.kind == "bridge" then
			local dist = segment(p, f.from, f.to)
			if dist <= f.width / 2 and p.Y >= math.min(f.from.Y, f.to.Y) - 1 then
				return true
			end
		end
	end
	return false
end

function DungeonNav.inHazard(def, p: Vector3): boolean
	if DungeonNav.onBridge(def, p) then
		return false
	end
	for _, h in ipairs(def.hazards or {}) do
		if h.min then
			if p.X >= h.min.X and p.X <= h.max.X and p.Z >= h.min.Z and p.Z <= h.max.Z and p.Y >= h.min.Y - 2 and p.Y <= h.max.Y + 3 then
				return true
			end
		elseif flat(p - h.center).Magnitude <= h.radius and p.Y <= h.top + 3 then
			return true
		end
	end
	return false
end

-- Does a straight walk from a to b go through lava?
function DungeonNav.crossesHazard(def, a: Vector3, b: Vector3): boolean
	if not def.hazards or #def.hazards == 0 then
		return false
	end
	local steps = math.max(1, math.ceil(flat(b - a).Magnitude / 2))
	for i = 0, steps do
		if DungeonNav.inHazard(def, a:Lerp(b, i / steps)) then
			return true
		end
	end
	return false
end

function DungeonNav.direct(def, a: Vector3, b: Vector3): boolean
	if flat(b - a).Magnitude < 3 and math.abs(b.Y - a.Y) < DungeonNav.CLIMB then
		return true
	end
	if DungeonNav.crossesHazard(def, a, b) then
		return false
	end
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "path" then
			local inA, ia = DungeonNav.spaceHas(sp, a)
			if inA then
				local inB, ib = DungeonNav.spaceHas(sp, b)
				if inB and ia == ib then
					return true
				end
			end
		elseif sp.hub ~= false and b.Y - a.Y <= DungeonNav.CLIMB and DungeonNav.spaceHas(sp, a) and DungeonNav.spaceHas(sp, b) then
			return true
		end
	end
	return false
end

local function shareSpace(def, a: Vector3, b: Vector3): boolean
	for _, sp in ipairs(def.spaces) do
		if DungeonNav.spaceHas(sp, a) and DungeonNav.spaceHas(sp, b) then
			return true
		end
	end
	return false
end

-- The spiral ramp's middle line, sampled every tenth of the way down.
function DungeonNav.spiralPoints(f, step: number?): { Vector3 }
	local list = {}
	local mid = (f.inner + f.outer) / 2
	local n = math.floor(1 / (step or 0.1) + 0.5)
	for i = 0, n do
		local k = i / n
		local a = math.rad(f.from + (f.to - f.from) * k)
		table.insert(list, f.center + Vector3.new(math.cos(a) * mid, f.topY + (f.bottomY - f.topY) * k - f.center.Y, math.sin(a) * mid))
	end
	return list
end

function DungeonNav.graph(def)
	if cache[def.id] then
		return cache[def.id]
	end
	local g = { nodes = {}, adj = {}, edges = {} }
	local function node(p: Vector3): number
		for i, q in ipairs(g.nodes) do
			if (q - p).Magnitude < 1 then
				return i
			end
		end
		table.insert(g.nodes, p)
		g.adj[#g.nodes] = {}
		return #g.nodes
	end
	local function link(i: number, j: number)
		if i ~= j and not table.find(g.adj[i], j) then
			table.insert(g.adj[i], j)
			table.insert(g.adj[j], i)
			table.insert(g.edges, { i, j })
		end
	end
	local function chain(points)
		local prev = nil
		for _, p in ipairs(points) do
			local i = node(p)
			if prev then
				link(prev, i)
			end
			prev = i
		end
	end
	-- tunnels, the extra routes, the spiral
	for _, sp in ipairs(def.spaces) do
		if sp.kind == "path" then
			chain(sp.points)
		end
	end
	for _, route in ipairs(def.routes or {}) do
		chain(route)
	end
	for _, f in ipairs(def.features or {}) do
		if f.kind == "spiral" then
			chain(DungeonNav.spiralPoints(f))
		end
	end
	-- each walkable room a tunnel opens into: its middle to those tunnel mouths
	for _, room in ipairs(def.spaces) do
		if room.kind ~= "path" and room.hub ~= false then
			local c = nil
			for _, sp in ipairs(def.spaces) do
				if sp.kind == "path" then
					for _, p in ipairs({ sp.points[1], sp.points[#sp.points] }) do
						if DungeonNav.spaceHas(room, p) then
							c = c or node(room.at)
							link(c, node(p))
						end
					end
				end
			end
		end
	end
	-- near neighbours sharing a space (a route's end and the tunnel it leads into...)
	local count = #g.nodes
	for i = 1, count do
		for j = i + 1, count do
			local a, b = g.nodes[i], g.nodes[j]
			if not table.find(g.adj[i], j) and flat(b - a).Magnitude <= DungeonNav.LINK and math.abs(b.Y - a.Y) <= 6
				and not DungeonNav.crossesHazard(def, a, b) and shareSpace(def, a, b) then
				link(i, j)
			end
		end
	end
	cache[def.id] = g
	return g
end

-- The node to start from (or finish at) for a point: the nearest one it can walk straight to, or
-- failing that the nearest one without lava in between.
local function anchor(def, g, p: Vector3): number?
	local best, bestDist = nil, math.huge
	for i, q in ipairs(g.nodes) do
		local d = (q - p).Magnitude
		if d < bestDist and DungeonNav.direct(def, p, q) then
			best, bestDist = i, d
		end
	end
	if best then
		return best
	end
	for i, q in ipairs(g.nodes) do
		local d = (q - p).Magnitude
		if d < bestDist and d < 24 and not DungeonNav.crossesHazard(def, p, q) then
			best, bestDist = i, d
		end
	end
	return best
end

-- The nodes to walk through from a to b (nil: no way found). The first entries the walker can skip
-- straight past are dropped, so it never doubles back to a node behind it.
function DungeonNav.route(def, a: Vector3, b: Vector3): { Vector3 }?
	local g = DungeonNav.graph(def)
	local s, e = anchor(def, g, a), anchor(def, g, b)
	if not s or not e then
		return nil
	end
	-- A*
	local open, came, cost = { s }, {}, { [s] = 0 }
	local score = { [s] = (g.nodes[s] - g.nodes[e]).Magnitude }
	local closed = {}
	while #open > 0 do
		local bi = 1
		for i = 2, #open do
			if score[open[i]] < score[open[bi]] then
				bi = i
			end
		end
		local cur = table.remove(open, bi)
		if cur == e then
			local path = { g.nodes[e] }
			while came[cur] do
				cur = came[cur]
				table.insert(path, 1, g.nodes[cur])
			end
			while #path >= 2 and DungeonNav.direct(def, a, path[2]) do
				table.remove(path, 1)
			end
			return path
		end
		closed[cur] = true
		for _, nxt in ipairs(g.adj[cur]) do
			if not closed[nxt] then
				local c = cost[cur] + (g.nodes[nxt] - g.nodes[cur]).Magnitude
				if not cost[nxt] or c < cost[nxt] then
					cost[nxt] = c
					came[nxt] = cur
					score[nxt] = c + (g.nodes[nxt] - g.nodes[e]).Magnitude
					if not table.find(open, nxt) then
						table.insert(open, nxt)
					end
				end
			end
		end
	end
	return nil
end

return DungeonNav
