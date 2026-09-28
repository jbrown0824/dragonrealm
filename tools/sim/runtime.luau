-- Virtual-time scheduler for the server simulation: task.wait / spawn / delay / defer run on a
-- fake clock (os.clock is replaced) that SIM.step advances. Errors inside any coroutine are
-- collected in SIM.errors with a traceback instead of stopping the run.

SIM = { now = 0, queue = {}, errors = {}, seq = 0 }
local realOs = os
os = setmetatable({ clock = function()
	return SIM.now
end }, { __index = realOs })

local function report(err, co)
	local msg = tostring(err)
	for _, e in ipairs(SIM.errors) do
		if e.msg == msg then
			e.count += 1
			return
		end
	end
	table.insert(SIM.errors, { msg = msg, trace = debug.traceback(co), count = 1 })
	print("SIM ERROR: " .. msg)
end

local cancelled = {}
local function resume(co, ...)
	if cancelled[co] or coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(err, co)
	end
end

local function schedule(at: number, co, ...)
	SIM.seq += 1
	table.insert(SIM.queue, { at = at, seq = SIM.seq, co = co, args = table.pack(...) })
end

task = {}
function task.wait(t)
	local co = coroutine.running()
	local start = SIM.now
	schedule(SIM.now + math.max(t or 0, 0.001), co)
	coroutine.yield()
	return SIM.now - start
end
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.delay(t, fn, ...)
	local co = coroutine.create(fn)
	schedule(SIM.now + (t or 0), co, ...)
	return co
end
function task.defer(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	schedule(SIM.now, co, ...)
	return co
end
function task.cancel(co)
	cancelled[co] = true
end
wait = task.wait
warn = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	print("WARN: " .. table.concat(parts, " "))
end

-- Advance the clock by dt: fire Heartbeat/Stepped, then run everything that's due.
function SIM.step(dt: number)
	SIM.now += dt
	local run = game:GetService("RunService")
	run.Stepped:Fire(SIM.now, dt)
	run.Heartbeat:Fire(dt)
	run.RenderStepped:Fire(dt)
	local guard = 0
	while true do
		guard += 1
		if guard > 100000 then
			print("SIM: too many wakeups in one step")
			break
		end
		table.sort(SIM.queue, function(a, b)
			if a.at ~= b.at then
				return a.at < b.at
			end
			return a.seq < b.seq
		end)
		local item = SIM.queue[1]
		if not item or item.at > SIM.now then
			break
		end
		table.remove(SIM.queue, 1)
		resume(item.co, table.unpack(item.args, 1, item.args.n))
	end
end

function SIM.run(seconds: number, dt: number?)
	local steps = math.floor(seconds / (dt or 0.1) + 0.5)
	for _ = 1, steps do
		SIM.step(dt or 0.1)
	end
end

-- typeof() the way Roblox answers it for the mock's value types.
local realTypeof = typeof
typeof = function(v)
	if type(v) == "table" then
		if rawget(v, "_class") then
			return "Instance"
		elseif rawget(v, "X") ~= nil and rawget(v, "Y") ~= nil and rawget(v, "Z") ~= nil then
			return "Vector3"
		elseif rawget(v, "p") ~= nil and rawget(v, "r") ~= nil then
			return "CFrame"
		elseif rawget(v, "R") ~= nil and rawget(v, "G") ~= nil then
			return "Color3"
		elseif rawget(v, "Width") ~= nil then
			return "UDim2"
		elseif rawget(v, "Scale") ~= nil then
			return "UDim"
		elseif rawget(v, "X") ~= nil and rawget(v, "Y") ~= nil then
			return "Vector2"
		end
	end
	return realTypeof(v)
end
