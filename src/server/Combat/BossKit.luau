-- Boss moves, and the fight loop that picks them, shared by the world bosses (BossService) and
-- the dungeon bosses (DungeonService). A "brain" drives one boss enemy record (EnemyService,
-- spawned with customAI):
--   BossKit.new(S, opts) -> brain       BossKit.think(brain, t) about 10 times a second
--   brain.moves can be swapped at any time (phases, a second life); brain.cdMult / dmgMult enrage it
-- opts:
--   boss            the EnemyService record
--   level, hit      damage level and a basic hit (each move multiplies it by its `mult`)
--   color           telegraph and slam colour
--   moves           { [name] = cfg } (below)
--   participants()  -> { { player, root, character } }: the dragons it may hit
--   over()          -> true once the fight is done (moves in flight stop hurting)
--   center, radius  the room: Leap and Charge stay inside it
--   ground(pos)     the floor under a point (default: EnemyService.groundAt from 10 studs up)
--   laneFrom        where Lane fire starts (the chained dragon's breath); default: the boss
--   grace           seconds before the first move (default 3)
--
-- Moves (cfg fields besides cooldown and mult):
--   Cleave { range }                        a swing in front
--   GroundSlam { radius, delay, slowPct? }  a telegraphed ring around the boss
--   RuneStrikes { radius, delay, count, style? }   telegraphed circles under the dragons
--   AxeVolley { count, style? }             thrown axes (or "hammer"s)
--   Leap { radius, delay, pick? }           crouch, then jump an inhuman distance onto a dragon
--                                           ("far": the farthest one, if anyone's over 30 studs
--                                           away) and slam down where it lands; any range
--   Charge { length, width, delay }         a telegraphed line, then a rush along it
--   Whirlwind { radius, duration, tick,     spins after the nearest dragon in a firestorm, hurting
--     cyclones?, cycloneRadius, cycloneMult }  everyone close; `cyclones` little ones spiral out
--                                           across the room (Dungeons.cyclonePos)
--   Harpoon { minHeight, far? }             a chain drags a dragon in: the highest one hovering
--                                           minHeight off the floor, or the farthest past `far`
--   Lane { width, delay }                   a row of fire across the room through a dragon
-- brain.hold = a floor point: the boss walks there and casts from it instead of chasing (a rune
-- shield phase).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Dungeons = require(ReplicatedStorage:WaitForChild("Shared").Config.Dungeons)
local WorldUtil = require(script.Parent.Parent.World.WorldUtil)

local BossKit = {}

BossKit.MOVES = { "Cleave", "GroundSlam", "RuneStrikes", "AxeVolley", "Leap", "Charge", "Whirlwind", "Harpoon", "Lane" }

local HARPOON_SPEED = 90

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function BossKit.new(S, opts)
	local brain = {
		S = S,
		boss = opts.boss,
		level = opts.level or 1,
		hit = opts.hit or 10,
		color = opts.color or Color3.fromRGB(255, 60, 40),
		moves = opts.moves or {},
		participants = opts.participants,
		over = opts.over or function()
			return false
		end,
		center = opts.center,
		radius = opts.radius,
		ground = opts.ground,
		laneFrom = opts.laneFrom,
		grace = opts.grace or 3,
		speed = opts.speed or opts.boss.baseSpeed,
		cdMult = 1,
		dmgMult = 1,
		nextMove = {},
		busyUntil = 0,
		target = nil,
		retargetAt = 0,
		startedAt = nil,
	}
	if not brain.ground then
		brain.ground = function(pos: Vector3): Vector3
			return S.EnemyService.groundAt(pos, 10)
		end
	end
	return brain
end

local function vfx(brain, data)
	brain.S.CombatService.broadcastVFX(data)
end

local function telegraph(brain, pos: Vector3, radius: number, delay: number, color: Color3?)
	vfx(brain, { kind = "telegraph", pos = pos, radius = radius, duration = delay, color = color or brain.color })
end

local function damage(brain, player: Player, amount: number)
	brain.boss.lastCombat = os.clock()
	-- (world bosses spawn above the group's level: no level gap in the arena)
	return brain.S.CombatService.damagePlayer(player, amount, { sourceLevel = brain.level, noLevelGap = brain.boss.arena or nil })
end

local function hitOf(brain, cfg): number
	return brain.hit * (cfg.mult or 1) * brain.dmgMult
end

local function hitInRadius(brain, center: Vector3, radius: number, amount: number, maxHeight: number, effects)
	for _, p in ipairs(brain.participants()) do
		local offset = p.root.Position - center
		if flat(offset).Magnitude <= radius + 3 and offset.Y <= maxHeight then
			damage(brain, p.player, amount)
			if effects and effects.slowPct then
				brain.S.CombatService.applySlow(p.character, effects.slowPct, 3)
			end
		end
	end
end

-- A point pulled back inside the room (with `margin` to spare).
local function inRoom(brain, pos: Vector3, margin: number): Vector3
	if not brain.center or not brain.radius then
		return pos
	end
	local d = flat(pos - brain.center)
	local max = math.max(0, brain.radius - margin)
	if d.Magnitude <= max then
		return pos
	end
	local p = brain.center + d.Unit * max
	return Vector3.new(p.X, pos.Y, p.Z)
end

local function face(brain, pos: Vector3)
	local root = brain.boss.root
	local p = root.Position
	if flat(pos - p).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(p, Vector3.new(pos.X, p.Y, pos.Z))
	end
end

-- Move the anchored boss along a path (a leap or a charge), `steps` frames over `time` seconds.
local function glide(brain, time: number, steps: number, at: (number) -> Vector3, look: Vector3, onStep)
	local boss = brain.boss
	local root = boss.root
	root.Anchored = true
	for i = 1, steps do
		task.wait(time / steps)
		if boss.dead or not root.Parent then
			break
		end
		local pos = at(i / steps)
		boss.model:PivotTo(CFrame.lookAt(pos, pos + look))
		if onStep then
			onStep(pos)
		end
	end
	if root.Parent then
		WorldUtil.release(root)
	end
end

---------------------------------------------------------------- moves

local MOVE = {}

MOVE.Cleave = function(brain, cfg)
	local boss = brain.boss
	local root = boss.root
	boss.model:SetAttribute("Swing", os.clock())
	local range = cfg.range * (boss.scale / 3)
	local amount = hitOf(brain, cfg)
	task.delay(0.55, function()
		if boss.dead or brain.over() then
			return
		end
		local look = root.CFrame.LookVector
		for _, p in ipairs(brain.participants()) do
			local offset = p.root.Position - root.Position
			local f = flat(offset)
			if f.Magnitude <= range + 4 and offset.Y < 20 then
				if f.Magnitude < 6 or look:Dot(f.Unit) > 0.2 then
					damage(brain, p.player, amount)
				end
			end
		end
	end)
	return 0.8
end

MOVE.GroundSlam = function(brain, cfg)
	local boss = brain.boss
	local center = brain.ground(boss.root.Position)
	telegraph(brain, center, cfg.radius, cfg.delay, Color3.fromRGB(255, 60, 40))
	boss.model:SetAttribute("Swing", os.clock() + cfg.delay - 0.3)
	local amount = hitOf(brain, cfg)
	task.delay(cfg.delay, function()
		if boss.dead or brain.over() then
			return
		end
		vfx(brain, { kind = "slam", pos = center, radius = cfg.radius, color = brain.color })
		hitInRadius(brain, center, cfg.radius, amount, 14, { slowPct = cfg.slowPct })
	end)
	return cfg.delay
end

MOVE.RuneStrikes = function(brain, cfg)
	local boss = brain.boss
	local players = brain.participants()
	local amount = hitOf(brain, cfg)
	for i = 1, cfg.count do
		local p = players[((i - 1) % math.max(1, #players)) + 1]
		if p then
			local jitter = i > #players and Vector3.new(math.random(-25, 25), 0, math.random(-25, 25)) or Vector3.new()
			local pos = brain.ground(inRoom(brain, p.root.Position + jitter, 6))
			telegraph(brain, pos, cfg.radius, cfg.delay, brain.color)
			task.delay(cfg.delay, function()
				if boss.dead or brain.over() then
					return
				end
				vfx(brain, { kind = "strike", pos = pos, radius = cfg.radius, delay = 0, style = cfg.style or "lightning", color = brain.color })
				hitInRadius(brain, pos, cfg.radius, amount, 25, nil)
			end)
		end
	end
	return 1
end

MOVE.AxeVolley = function(brain, cfg)
	local boss = brain.boss
	local players = brain.participants()
	local amount = hitOf(brain, cfg)
	for i = 1, math.min(cfg.count, #players * 2) do
		local p = players[((i - 1) % #players) + 1]
		task.delay((i - 1) * 0.2, function()
			if boss.dead or brain.over() or not p.root.Parent then
				return
			end
			brain.S.EnemyService.throwAt(boss, p.player, p.root, amount, cfg.style or "axe")
		end)
	end
	return 1
end

-- Crouch, then an arcing jump onto a dragon's spot (far away is no escape), slamming down.
MOVE.Leap = function(brain, cfg, target)
	local boss = brain.boss
	local root = boss.root
	local players = brain.participants()
	if cfg.pick == "far" then
		-- the farthest dragon, if anyone's hanging back; otherwise straight up and down on its target
		local best, far = -1, nil
		for _, p in ipairs(players) do
			local d = flat(p.root.Position - root.Position).Magnitude
			if d > best then
				best, far = d, p
			end
		end
		if far and best > 30 then
			target = far
		end
	end
	local land = brain.ground(inRoom(brain, target.root.Position, 8))
	telegraph(brain, land, cfg.radius, cfg.delay, brain.color)
	boss.model:SetAttribute("Swing", os.clock() + cfg.delay - 0.2)
	boss.model:SetAttribute("Leaping", true)
	brain.holdUntil = os.clock() + cfg.delay + 0.4
	local amount = hitOf(brain, cfg)
	local hip = boss.humanoid.HipHeight + root.Size.Y / 2
	task.spawn(function()
		boss.humanoid:MoveTo(root.Position)
		task.wait(0.35) -- crouch
		if boss.dead or brain.over() then
			boss.model:SetAttribute("Leaping", nil)
			return
		end
		local from = root.Position
		local to = land + Vector3.new(0, hip, 0)
		local look = flat(to - from)
		look = look.Magnitude > 0.5 and look.Unit or root.CFrame.LookVector
		local height = 18 + (to - from).Magnitude * 0.2
		local time = math.max(0.3, cfg.delay - 0.35)
		glide(brain, time, math.max(4, math.floor(time / 0.05)), function(k)
			return from:Lerp(to, k) + Vector3.new(0, 4 * height * k * (1 - k), 0)
		end, look)
		boss.model:SetAttribute("Leaping", nil)
		if boss.dead or brain.over() then
			return
		end
		vfx(brain, { kind = "slam", pos = land, radius = cfg.radius, color = brain.color })
		hitInRadius(brain, land, cfg.radius, amount, 16, { slowPct = 30 })
	end)
	return cfg.delay + 0.5
end

-- A telegraphed line, then a rush along it that hurts every dragon in the way.
MOVE.Charge = function(brain, cfg, target)
	local boss = brain.boss
	local root = boss.root
	local from = root.Position
	local dir = flat(target.root.Position - from)
	dir = dir.Magnitude > 1 and dir.Unit or flat(root.CFrame.LookVector).Unit
	local length = cfg.length
	while length > 10 and inRoom(brain, from + dir * length, 8) ~= from + dir * length do
		length -= 5
	end
	for d = 0, length, 10 do
		telegraph(brain, brain.ground(from + dir * d), cfg.width / 2 + 2, cfg.delay, brain.color)
	end
	boss.humanoid:MoveTo(root.Position)
	face(brain, from + dir * 10)
	brain.holdUntil = os.clock() + cfg.delay + 0.7
	local amount = hitOf(brain, cfg)
	task.spawn(function()
		task.wait(cfg.delay)
		if boss.dead or brain.over() then
			return
		end
		local hitAlready = {}
		glide(brain, 0.6, 12, function(k)
			return from + dir * (length * k)
		end, dir, function(pos)
			for _, p in ipairs(brain.participants()) do
				local offset = p.root.Position - pos
				if not hitAlready[p.player] and flat(offset).Magnitude <= cfg.width / 2 + 3 + boss.scale and offset.Y < 14 then
					hitAlready[p.player] = true
					damage(brain, p.player, amount)
					brain.S.CombatService.applySlow(p.character, 40, 2)
				end
			end
		end)
		vfx(brain, { kind = "slam", pos = brain.ground(root.Position), radius = cfg.width, color = brain.color })
	end)
	return cfg.delay + 0.8
end

MOVE.Whirlwind = function(brain, cfg)
	local boss = brain.boss
	brain.spin = { untilT = os.clock() + cfg.duration, nextTick = 0, cfg = cfg, amount = hitOf(brain, cfg) }
	boss.model:SetAttribute("Spinning", true)
	pcall(function()
		boss.humanoid.AutoRotate = false
	end)
	vfx(brain, { kind = "bossCyclone", model = boss.model, duration = cfg.duration, radius = cfg.radius, color = brain.color })
	if cfg.cyclones then
		local center = brain.ground(boss.root.Position)
		local maxR = brain.radius and math.max(10, brain.radius - 6) or 60
		brain.cyclones = {
			center = center,
			start = os.clock(),
			count = cfg.cyclones,
			radius = cfg.cycloneRadius or 7,
			amount = hitOf(brain, cfg) * (cfg.cycloneMult or 1),
			duration = cfg.duration,
			maxR = maxR,
			hit = {},
		}
		vfx(brain, { kind = "cyclones", center = center, count = cfg.cyclones, start = workspace:GetServerTimeNow(), duration = cfg.duration, radius = cfg.cycloneRadius or 7, maxR = maxR, color = brain.color })
	end
	return cfg.duration
end

-- A chain hooks the highest dragon flying out of reach and drags it down in front of the boss.
MOVE.Harpoon = function(brain, cfg, _, victim)
	local boss = brain.boss
	local root = boss.root
	local from = root.Position + Vector3.new(0, 2 * boss.scale, 0)
	local to = victim.root.Position
	local travel = (to - from).Magnitude / HARPOON_SPEED
	local reel = Dungeons.REEL_TIME
	face(brain, to)
	brain.holdUntil = os.clock() + travel + reel
	boss.model:SetAttribute("Throw", os.clock())
	vfx(brain, { kind = "throw", from = from, to = to, time = travel, style = "chain" })
	local amount = hitOf(brain, cfg)
	task.delay(travel, function()
		if boss.dead or brain.over() then
			return
		end
		local character, _, vroot = brain.S.PlayerService.getCharacter(victim.player)
		if not character then
			return
		end
		-- hooked: the chain goes taut and the dragon is dragged in (its own client moves it, so it
		-- slides the whole way; everyone sees the chain between them)
		local away = flat(vroot.Position - root.Position)
		away = away.Magnitude > 1 and away.Unit or root.CFrame.LookVector
		local spot = brain.ground(inRoom(brain, root.Position + away * (8 + 4 * boss.scale), 6))
		vfx(brain, { kind = "harpooned", userId = victim.player.UserId, model = boss.model, from = from, to = spot + Vector3.new(0, 4, 0), time = reel })
		task.delay(reel, function()
			if boss.dead or brain.over() then
				return
			end
			local c2, _, r2 = brain.S.PlayerService.getCharacter(victim.player)
			if not c2 then
				return
			end
			if flat(r2.Position - spot).Magnitude > 12 then
				-- (didn't get dragged all the way: lag, or a client that ignored it)
				brain.S.PlayerService.teleport(victim.player, CFrame.lookAt(spot + Vector3.new(0, 5, 0), Vector3.new(root.Position.X, spot.Y + 5, root.Position.Z)))
			end
			damage(brain, victim.player, amount)
			brain.S.CombatService.applySlow(c2, 40, 3)
		end)
	end)
	return travel + reel + 0.4
end

-- Fire along a line across the room, through one of the dragons: telegraphed, then it burns.
MOVE.Lane = function(brain, cfg, target)
	local boss = brain.boss
	local from = brain.laneFrom or brain.ground(boss.root.Position)
	local aim = brain.ground(target.root.Position)
	local dir = flat(aim - from)
	dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, -1)
	local length = brain.radius and brain.radius * 2 or 120
	while length > 20 and inRoom(brain, from + dir * length, 4) ~= from + dir * length do
		length -= 6
	end
	local points = {}
	for d = 6, length, 9 do
		local pos = brain.ground(from + dir * d)
		table.insert(points, pos)
		telegraph(brain, pos, cfg.width / 2, cfg.delay, Color3.fromRGB(255, 120, 30))
	end
	local amount = hitOf(brain, cfg)
	task.delay(cfg.delay, function()
		if boss.dead or brain.over() then
			return
		end
		for i, pos in ipairs(points) do
			if i % 2 == 1 then
				vfx(brain, { kind = "slam", pos = pos, radius = cfg.width / 2, color = Color3.fromRGB(255, 120, 30) })
			end
		end
		for _, p in ipairs(brain.participants()) do
			local rel = p.root.Position - from
			local along = math.clamp(rel:Dot(dir), 0, length)
			local off = flat(rel - dir * along)
			local floor = brain.ground(p.root.Position)
			if off.Magnitude <= cfg.width / 2 + 2 and p.root.Position.Y - floor.Y < 20 then
				damage(brain, p.player, amount)
				brain.S.CombatService.applyDot(p.character, "burn", amount * 0.3, 3)
			end
		end
		if brain.onLane then
			brain.onLane(from, dir, length)
		end
	end)
	return 0.6
end

-- Use a move now (its cooldown starts). `victim` is the Harpoon's flyer.
function BossKit.use(brain, name: string, target, victim)
	local cfg = brain.moves[name]
	local t = os.clock()
	brain.nextMove[name] = t + cfg.cooldown * brain.cdMult
	local busy = MOVE[name](brain, cfg, target, victim)
	brain.busyUntil = t + (busy or 1)
end

---------------------------------------------------------------- the fight loop

-- The highest dragon flying at least minHeight off the floor (by its own standing height).
local function highestFlyer(brain, players, minHeight: number)
	local boss = brain.boss
	local floorY = boss.root.Position.Y - (boss.humanoid.HipHeight + boss.root.Size.Y / 2)
	local best, bestUp = nil, minHeight
	for _, p in ipairs(players) do
		if p.character:GetAttribute("Flying") then
			local hum = p.character:FindFirstChildOfClass("Humanoid")
			local stand = hum and (hum.HipHeight + p.root.Size.Y / 2) or 4
			local up = p.root.Position.Y - floorY - stand
			if up >= bestUp then
				best, bestUp = p, up
			end
		end
	end
	return best
end

-- The farthest dragon past `far` studs (hanging back out of reach).
local function farthest(brain, players, far: number?)
	if not far then
		return nil
	end
	local best, bestD = nil, far
	for _, p in ipairs(players) do
		local d = flat(p.root.Position - brain.boss.root.Position).Magnitude
		if d > bestD then
			best, bestD = p, d
		end
	end
	return best
end

-- The whirlwind's little cyclones: each one hurts (and slows) a dragon it runs into, once.
local function cycloneTick(brain, players)
	local c = brain.cyclones
	local t = os.clock() - c.start
	if t > c.duration or brain.over() then
		brain.cyclones = nil
		return
	end
	for i = 1, c.count do
		local pos = Dungeons.cyclonePos(c.center, i, c.count, t, c.maxR)
		for _, p in ipairs(players) do
			local key = tostring(i) .. ":" .. p.player.UserId
			local off = p.root.Position - pos
			if not c.hit[key] and flat(off).Magnitude <= c.radius + 3 and off.Y < 16 then
				c.hit[key] = true
				damage(brain, p.player, c.amount)
				brain.S.CombatService.applySlow(p.character, 30, 2)
			end
		end
	end
end

local function spinTick(brain, t: number, players)
	local boss = brain.boss
	local spin = brain.spin
	local root = boss.root
	local nearest, best = nil, math.huge
	for _, p in ipairs(players) do
		local d = flat(p.root.Position - root.Position).Magnitude
		if d < best then
			nearest, best = p, d
		end
	end
	boss.humanoid.WalkSpeed = brain.speed * 1.3 * brain.S.CombatService.speedMultiplier(boss.model)
	if nearest then
		boss.humanoid:MoveTo(Vector3.new(nearest.root.Position.X, root.Position.Y, nearest.root.Position.Z))
	end
	root.CFrame = root.CFrame * CFrame.Angles(0, 1.1, 0)
	if t >= spin.nextTick then
		spin.nextTick = t + spin.cfg.tick
		local center = brain.ground(root.Position)
		vfx(brain, { kind = "slam", pos = center, radius = spin.cfg.radius, color = brain.color })
		hitInRadius(brain, center, spin.cfg.radius, spin.amount, 14, nil)
	end
end

local function endSpin(brain)
	brain.spin = nil
	brain.boss.model:SetAttribute("Spinning", nil)
	pcall(function()
		brain.boss.humanoid.AutoRotate = true
	end)
end

-- One decision: pick (or keep) a target, walk at it, and use the first ready move that fits.
function BossKit.think(brain, t: number)
	local boss = brain.boss
	if boss.dead or brain.over() then
		return
	end
	local players = brain.participants()
	if brain.cyclones then
		cycloneTick(brain, players)
	end
	if brain.spin then
		if t < brain.spin.untilT and #players > 0 then
			spinTick(brain, t, players)
			return
		end
		endSpin(brain)
	end
	local speedMult = brain.S.CombatService.speedMultiplier(boss.model)
	boss.humanoid.WalkSpeed = brain.speed * speedMult
	if speedMult == 0 then
		boss.humanoid:MoveTo(boss.root.Position)
		return
	end
	if #players == 0 then
		boss.humanoid:MoveTo(brain.home or brain.center or boss.spawnPos)
		return
	end
	if boss.root.Anchored then
		return -- mid-leap or mid-charge
	end
	if brain.holdUntil and t < brain.holdUntil then
		boss.humanoid:MoveTo(boss.root.Position) -- winding up a leap, a charge or a throw
		return
	end
	local stillThere = false
	if brain.target then
		for _, p in ipairs(players) do
			if p.player == brain.target.player then
				brain.target = p
				stillThere = true
			end
		end
	end
	if not stillThere or t >= brain.retargetAt then
		brain.retargetAt = t + 4 + math.random() * 3
		local best, bestDist = nil, math.huge
		for _, p in ipairs(players) do
			local d = (p.root.Position - boss.root.Position).Magnitude + math.random() * 25
			if d < bestDist then
				best, bestDist = p, d
			end
		end
		brain.target = best
	end
	local target = brain.target
	local offset = target.root.Position - boss.root.Position
	local dist = flat(offset).Magnitude
	local cleave = brain.moves.Cleave
	local cleaveRange = cleave and cleave.range * (boss.scale / 3) or 14

	if brain.hold then
		-- casting from its spot (a rune shield phase): walk there, then stand and face its target
		if flat(brain.hold - boss.root.Position).Magnitude > 4 then
			boss.humanoid:MoveTo(brain.hold)
		else
			boss.humanoid:MoveTo(boss.root.Position)
			face(brain, target.root.Position)
		end
	elseif dist > cleaveRange * 0.8 then
		boss.humanoid:MoveTo(Vector3.new(target.root.Position.X, boss.root.Position.Y, target.root.Position.Z))
	else
		boss.humanoid:MoveTo(boss.root.Position)
		face(brain, target.root.Position)
	end

	if not brain.startedAt then
		brain.startedAt = t + brain.grace -- a moment to get ready (and teleport in)
		return
	end
	if t < brain.startedAt or t < brain.busyUntil then
		return
	end

	local moves = brain.moves
	local function ready(name: string): boolean
		return moves[name] ~= nil and t >= (brain.nextMove[name] or brain.startedAt)
	end
	local function near(radius: number): boolean
		for _, p in ipairs(players) do
			if (p.root.Position - boss.root.Position).Magnitude < radius then
				return true
			end
		end
		return false
	end

	if ready("Harpoon") then
		local victim = highestFlyer(brain, players, moves.Harpoon.minHeight) or farthest(brain, players, moves.Harpoon.far)
		if victim then
			BossKit.use(brain, "Harpoon", target, victim)
			return
		end
	end
	if ready("Leap") then
		BossKit.use(brain, "Leap", target)
		return
	end
	if ready("Charge") and dist > 16 and dist < moves.Charge.length then
		BossKit.use(brain, "Charge", target)
		return
	end
	if ready("Whirlwind") and near(moves.Whirlwind.radius + 12) then
		BossKit.use(brain, "Whirlwind", target)
		return
	end
	if ready("Lane") then
		BossKit.use(brain, "Lane", target)
		return
	end
	if ready("GroundSlam") and near(moves.GroundSlam.radius) then
		BossKit.use(brain, "GroundSlam", target)
		return
	end
	if ready("RuneStrikes") then
		BossKit.use(brain, "RuneStrikes", target)
		return
	end
	if ready("AxeVolley") and (dist > cleaveRange or math.random() < 0.4) then
		BossKit.use(brain, "AxeVolley", target)
		return
	end
	if ready("Cleave") and dist <= cleaveRange + 4 and offset.Y < 20 then
		BossKit.use(brain, "Cleave", target)
		return
	end
	-- flyers staying out of reach get axes thrown at them
	if ready("AxeVolley") and offset.Y > 15 then
		BossKit.use(brain, "AxeVolley", target)
	end
end

-- Stop whatever it's doing (a second life, a wipe reset).
function BossKit.reset(brain)
	if brain.spin then
		endSpin(brain)
	end
	brain.cyclones = nil
	brain.busyUntil = 0
	brain.holdUntil = nil
	brain.target = nil
	brain.startedAt = nil
	table.clear(brain.nextMove)
	if brain.boss.root.Parent then
		WorldUtil.release(brain.boss.root)
	end
end

BossKit.inRoom = inRoom

return BossKit
