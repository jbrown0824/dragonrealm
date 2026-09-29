-- Target practice range in town (Config/Range, Zones.Range). Stand on a lane's firing mat, open
-- the range window (PanelPrompt "Range") and start a level or AFK practice.
--
-- A session belongs to one dragon and one lane. Its targets are models tagged "PracticeTarget"
-- with an OwnerUserId and their motion as attributes (shared/RangeUtil): every client moves them
-- itself, and the server works out where they are from the same numbers when a fireball flies,
-- so nothing streams positions. CombatService asks RangeService.targetsFor(attacker) for the
-- owner's targets and calls RangeService.onHit when a blast reaches one.
--
-- While practicing the player attribute "RangeMode" ("level" / "afk") tells CombatService and the
-- client that only Fireball works, on a shorter cooldown (and left click fires it too). Walking
-- off the mat, dying, a raid coming ashore or leaving ends the session. AFK practice pays a
-- little XP per target knocked down (Range.afkXpPerHit), shown as a rising "+XP" number.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Range = require(Shared.Config.Range)
local Zones = require(Shared.Config.Zones)
local RangeUtil = require(Shared.RangeUtil)
local Remotes = require(Shared.Remotes)

local RangeService = {}
local S

local sessions = {} -- [Player] = session
local laneOwner = {} -- [lane] = Player
local folder: Folder

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function RangeService.matPos(lane: number): Vector3
	return Vector3.new(Zones.Range.matX, 0, Zones.Range.lanes[lane])
end

-- The lane whose mat the player is standing at, if any.
local function laneAt(pos: Vector3): number?
	for lane in ipairs(Zones.Range.lanes) do
		if flat(pos, RangeService.matPos(lane)) <= Range.MAT_RANGE then
			return lane
		end
	end
	return nil
end

function RangeService.mode(player: Player): string?
	local s = sessions[player]
	return s and s.mode or nil
end

---------------------------------------------------------------- targets

local function buildModel(t, owner: Player): Model
	local model = Instance.new("Model")
	model.Name = "PracticeTarget"
	local d = t.size
	local rings = t.gold and { Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 250, 230), Color3.fromRGB(255, 170, 30) }
		or { Color3.fromRGB(215, 50, 45), Color3.fromRGB(250, 245, 235), Color3.fromRGB(215, 50, 45) }
	local function disc(diameter: number, x: number, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder -- the round faces point along x, toward the mats
		p.Size = Vector3.new(0.4, diameter, diameter)
		p.CFrame = CFrame.new(t.x + x, t.y, t.z)
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = true -- the mouse aim lands on the target itself (it's outside Map, so no service raycast sees it)
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	local board = disc(d + 0.6, 0, Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	disc(d, 0.15, rings[1], Enum.Material.SmoothPlastic)
	disc(d * 0.66, 0.3, rings[2], Enum.Material.SmoothPlastic)
	disc(d * 0.33, 0.45, rings[3], t.gold and Enum.Material.Neon or Enum.Material.SmoothPlastic)
	model.PrimaryPart = board
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("Pattern", t.pattern)
	model:SetAttribute("X0", t.x)
	model:SetAttribute("Y0", t.y)
	model:SetAttribute("Z0", t.z)
	model:SetAttribute("Speed", t.speed)
	model:SetAttribute("Amp", t.amp)
	model:SetAttribute("Phase", t.phase)
	model:SetAttribute("Born", t.born)
	model:SetAttribute("Life", t.life)
	model:SetAttribute("Gold", t.gold)
	model:PivotTo(CFrame.new(RangeUtil.position(t, t.born)))
	CollectionService:AddTag(model, "PracticeTarget")
	model.Parent = folder
	return model
end

local function spawnTarget(s)
	local def = s.def
	local R = Zones.Range
	local pattern = def.patterns[math.random(1, #def.patterns)]
	local laneZ = R.lanes[s.lane]
	local size = def.size
	local moving = pattern ~= "still" and pattern ~= "popup"
	local amp = moving and R.laneHalf * (0.55 + math.random() * 0.45) or 1
	local margin = pattern == "zigzag" and amp * 0.5 or (pattern == "float" and 3 or 0)
	local t = {
		pattern = pattern,
		x = R.far + margin + math.random() * math.max(0, (R.near - R.far) - 2 * margin),
		y = (def.high and 16 or 5) + size / 2 + math.random() * 2,
		z = moving and laneZ or laneZ + (math.random() * 2 - 1) * (R.laneHalf - size / 2),
		speed = (def.speed or 0) * (0.85 + math.random() * 0.3),
		amp = amp,
		phase = math.random() * math.pi * 2,
		born = now(),
		life = pattern == "popup" and def.life or nil,
		size = size,
		gold = s.mode == "level" and math.random() < Range.GOLD_CHANCE,
	}
	s.nextId += 1
	t.id = s.nextId
	t.model = buildModel(t, s.player)
	s.targets[t.id] = t
end

local function removeTarget(s, id: number)
	local t = s.targets[id]
	if t then
		s.targets[id] = nil
		t.model:Destroy()
	end
end

local function clearTargets(s)
	for id in pairs(s.targets) do
		removeTarget(s, id)
	end
end

-- The player's own targets, the way CombatService lists things to hit.
function RangeService.targetsFor(player: Player)
	local s = sessions[player]
	local list = {}
	if not s then
		return list
	end
	local t0 = now()
	for id, t in pairs(s.targets) do
		if not RangeUtil.expired(t, t0) then
			table.insert(list, { model = t.model, root = { Position = RangeUtil.position(t, t0) }, radius = t.size / 2, practice = id })
		end
	end
	return list
end

---------------------------------------------------------------- sessions

local function sendState(s, result)
	if not s.player.Parent then
		return
	end
	Remotes.event("RangeState"):FireClient(s.player, {
		mode = s.mode,
		level = s.level,
		name = s.def.name,
		hits = s.hits,
		needed = s.needed,
		endsAt = s.endsAt,
		lane = s.lane,
		result = result,
	})
end

local function xpUnit(profile): number
	return profile.level >= Game.LEVEL_CAP and Game.paragonXp(profile.paragon or 0) or Game.xpToNext(profile.level)
end

local function finish(s, cleared: boolean?, reason: string?)
	if sessions[s.player] ~= s then
		return
	end
	sessions[s.player] = nil
	if laneOwner[s.lane] == s.player then
		laneOwner[s.lane] = nil
	end
	clearTargets(s)
	s.player:SetAttribute("RangeMode", nil)
	local result = { cleared = cleared == true, reason = reason, hits = s.hits, needed = s.needed }
	local profile = S.PlayerService.getProfile(s.player)
	if cleared and profile then
		local first = s.level > (profile.rangeLevel or 0)
		if first then
			profile.rangeLevel = s.level
		end
		local xp = S.PlayerService.addXP(s.player, xpUnit(profile) * s.def.xp * (first and 1 or Range.REPLAY_XP))
		S.PlayerService.markDirty(s.player)
		local _, _, root = S.PlayerService.getCharacter(s.player)
		if root then
			S.CombatService.queueNumber(s.player, root.Position + Vector3.new(0, 8, 0), xp, "xp")
		end
		result.xp = xp
		result.first = first
	end
	sendState(s, result)
end

function RangeService.stop(player: Player, reason: string?)
	local s = sessions[player]
	if s then
		finish(s, false, reason or "stopped")
	end
end

local function begin(player: Player, mode: string, level: number?): (boolean, string?)
	local profile = S.PlayerService.getProfile(player)
	local character, humanoid, root = S.PlayerService.getCharacter(player)
	if not profile or not profile.class or not character or humanoid.Health <= 0 then
		return false, "You need a dragon to practice."
	end
	if S.RaidService.isActive() and workspace:GetAttribute("RaidPhase") == "fighting" then
		return false, "Vikings are in town! Practice after the raid."
	end
	if S.BossService.isInFight(player) then
		return false, "Finish your boss fight first."
	end
	local lane = laneAt(root.Position)
	if not lane then
		return false, "Stand on one of the firing mats at the range."
	end
	local owner = laneOwner[lane]
	if owner and owner ~= player and sessions[owner] then
		return false, owner.DisplayName .. " is using this lane. Try another one."
	end
	local def
	if mode == "afk" then
		def = { name = "AFK practice", patterns = Range.AFK.patterns, speed = Range.AFK.speed, size = Range.AFK.size, count = Range.AFK.count }
	else
		mode = "level"
		level = math.floor(tonumber(level) or 1)
		def = Range.Levels[level]
		if not def then
			return false, "There's no such level."
		end
		if level > (profile.rangeLevel or 0) + 1 then
			return false, "Clear level " .. (level - 1) .. " first."
		end
	end
	RangeService.stop(player, "restart")
	local t = now()
	local s = {
		player = player,
		lane = lane,
		mode = mode,
		level = mode == "level" and level or 0,
		def = def,
		hits = 0,
		needed = def.needed or 0,
		endsAt = def.time and (t + def.time) or nil,
		nextPaidHit = 0,
		targets = {},
		nextId = 0,
	}
	sessions[player] = s
	laneOwner[lane] = player
	player:SetAttribute("RangeMode", mode)
	for _ = 1, def.count do
		spawnTarget(s)
	end
	sendState(s)
	return true, nil
end

-- A practice blast reached one of the player's targets (CombatService).
function RangeService.onHit(player: Player, id: number)
	local s = sessions[player]
	local t = s and s.targets[id]
	if not t then
		return
	end
	local pos = RangeUtil.position(t, now())
	removeTarget(s, id)
	local points = t.gold and 2 or 1
	s.hits += points
	S.CombatService.broadcastVFX({ kind = "pop", pos = pos, big = t.gold, color = t.gold and Color3.fromRGB(255, 205, 60) or Color3.fromRGB(255, 120, 90) })
	if s.mode == "afk" then
		-- AFK pays per target, no faster than the auto-fire could (so mashing Q isn't a shortcut)
		local clock = now()
		local profile = S.PlayerService.getProfile(player)
		if profile and clock >= s.nextPaidHit then
			s.nextPaidHit = clock + Range.AFK.fireEvery * 0.8
			local gained = S.PlayerService.addXP(player, Range.afkXpPerHit(xpUnit(profile)))
			S.CombatService.queueNumber(player, pos + Vector3.new(0, t.size / 2 + 1, 0), gained, "xp")
		end
	else
		S.CombatService.queueNumber(player, pos + Vector3.new(0, t.size / 2 + 1, 0), points, "target")
	end
	if s.mode == "level" and s.hits >= s.needed then
		finish(s, true)
		return
	end
	sendState(s)
	task.delay(Range.RESPAWN, function()
		if sessions[player] == s then
			spawnTarget(s)
		end
	end)
end

local function onAction(player: Player, action, level)
	if action == "start" then
		return begin(player, "level", level)
	elseif action == "afk" then
		return begin(player, "afk")
	elseif action == "stop" then
		RangeService.stop(player, "stopped")
		return true
	end
	return false, "Unknown action."
end

local function tick()
	local t = now()
	local raiding = workspace:GetAttribute("RaidPhase") == "fighting"
	for player, s in pairs(sessions) do
		local character, humanoid, root = S.PlayerService.getCharacter(player)
		if not player.Parent then
			finish(s, false, "left")
		elseif not character or humanoid.Health <= 0 then
			finish(s, false, "died")
		elseif flat(root.Position, RangeService.matPos(s.lane)) > Range.LEAVE_DISTANCE or root.Position.Y > 60 then
			finish(s, false, "walked")
		elseif raiding then
			finish(s, false, "raid")
		elseif s.endsAt and t >= s.endsAt then
			finish(s, false, "time")
		else
			-- popups that timed out make way for new ones
			for id, target in pairs(s.targets) do
				if RangeUtil.expired(target, t) then
					removeTarget(s, id)
					spawnTarget(s)
				end
			end
		end
	end
end

function RangeService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "PracticeTargets"
	folder.Parent = workspace
end

function RangeService.start()
	Remotes.func("RangeAction").OnServerInvoke = onAction
	Players.PlayerRemoving:Connect(function(player)
		local s = sessions[player]
		if s then
			finish(s, false, "left")
		end
	end)
	while true do
		task.wait(0.25)
		local ok, err = pcall(tick)
		if not ok then
			warn("[RangeService]", err)
		end
	end
end

return RangeService
