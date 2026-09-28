-- Minimal Roblox runtime stand-in, enough to run the map/dragon builders offline and dump parts.

---------------------------------------------------------------- Vector3
local V3mt = {}
local V3 = {}
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3mt)
end
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	return V3[k]
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(v)
	return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z)
end
Vector3 = {
	new = function(x, y, z)
		return v3(x or 0, y or 0, z or 0)
	end,
}
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

---------------------------------------------------------------- CFrame
local CFmt = {}
local CFm = {}
local function mk(p, r)
	return setmetatable({ p = p, r = r }, CFmt)
end
local IDR = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function mulR(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function mulRV(r, v)
	return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function fromCols(x, y, z)
	return { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z }
end
CFmt.__index = function(c, k)
	if k == "Position" then
		return c.p
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	elseif k == "LookVector" then
		return v3(-c.r[3], -c.r[6], -c.r[9])
	elseif k == "RightVector" then
		return v3(c.r[1], c.r[4], c.r[7])
	elseif k == "UpVector" then
		return v3(c.r[2], c.r[5], c.r[8])
	elseif k == "Rotation" then
		return mk(v3(0, 0, 0), c.r)
	end
	return CFm[k]
end
function CFm.Inverse(c)
	local r = c.r
	local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	return mk(-mulRV(t, c.p), t)
end
function CFm.Lerp(a, b, t)
	return mk(a.p:Lerp(b.p, t), t < 0.5 and a.r or b.r)
end
function CFm.PointToObjectSpace(c, v)
	return c:Inverse() * v
end
function CFm.ToObjectSpace(c, o)
	return c:Inverse() * o
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == CFmt then
		return mk(a.p + mulRV(a.r, b.p), mulR(a.r, b.r))
	end
	return a.p + mulRV(a.r, b)
end
CFmt.__add = function(a, v)
	return mk(a.p + v, a.r)
end
CFmt.__sub = function(a, v)
	return mk(a.p - v, a.r)
end
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local f = (target - at).Unit
	local right = f:Cross(up).Unit
	if right.Magnitude < 1e-6 then
		right = f:Cross(v3(0, 0, 1)).Unit
	end
	local up2 = right:Cross(f)
	return mk(at, fromCols(right, up2, -f))
end
local function angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return mk(v3(0, 0, 0), mulR(mulR(Rx, Ry), Rz))
end
CFrame = {}
CFrame.new = function(a, b, c, ...)
	if a == nil then
		return mk(v3(0, 0, 0), IDR)
	elseif type(a) == "number" then
		local rest = { ... }
		if #rest == 9 then
			return mk(v3(a, b, c), rest)
		end
		return mk(v3(a, b, c), IDR)
	elseif b ~= nil then
		return lookAt(a, b)
	end
	return mk(a, IDR)
end
CFrame.lookAt = lookAt
CFrame.Angles = angles
CFrame.fromEulerAnglesXYZ = angles
CFrame.fromMatrix = function(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return mk(pos, fromCols(vx, vy, vz))
end
CFrame.fromAxisAngle = function(axis, a)
	local u = axis.Unit
	local c, s, t = math.cos(a), math.sin(a), 1 - math.cos(a)
	local x, y, z = u.X, u.Y, u.Z
	return mk(v3(0, 0, 0), {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	})
end
CFrame.identity = mk(v3(0, 0, 0), IDR)
IS_CFRAME = function(v)
	return getmetatable(v) == CFmt
end

---------------------------------------------------------------- misc value types
local C3mt = {}
C3mt.__index = {
	Lerp = function(a, b, t)
		return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, C3mt)
	end,
}
Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, C3mt)
	end,
}
local function passthrough(...)
	return { ... }
end
-- UDim / UDim2 / Vector2 behave like Roblox's (the GUI dump needs scale vs offset).
local UDmt = {}
local function udim(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDmt)
end
UDmt.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDmt.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDmt.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
local U2mt = {}
local function udim2(xs, xo, ys, yo)
	if type(xs) == "table" then -- UDim2.new(UDim, UDim)
		return setmetatable({ X = xs, Y = xo, Width = xs, Height = xo }, U2mt)
	end
	local x, y = udim(xs, xo), udim(ys, yo)
	return setmetatable({ X = x, Y = y, Width = x, Height = y }, U2mt)
end
U2mt.__add = function(a, b)
	return udim2(a.X + b.X, a.Y + b.Y)
end
U2mt.__sub = function(a, b)
	return udim2(a.X - b.X, a.Y - b.Y)
end
U2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UDim2 = {
	new = udim2,
	fromOffset = function(x, y)
		return udim2(0, x or 0, 0, y or 0)
	end,
	fromScale = function(x, y)
		return udim2(x or 0, 0, y or 0, 0)
	end,
}
UDim = { new = udim }
local V2mt = {}
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2mt)
end
V2mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return nil
end
V2mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }
NumberSequence = { new = passthrough }
NumberSequenceKeypoint = { new = passthrough }
NumberRange = { new = passthrough }
ColorSequence = { new = passthrough }
ColorSequenceKeypoint = { new = passthrough }
-- Enum items are cached so `a == Enum.Material.Water` comparisons work like in Roblox.
Enum = setmetatable({}, {
	__index = function(enums, typ)
		local items = setmetatable({}, {
			__index = function(t, name)
				local item = { EnumType = typ, Name = name, Value = 0 }
				rawset(t, name, item)
				return item
			end,
		})
		rawset(enums, typ, items)
		return items
	end,
})
Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local r = {}
		local function nxt()
			state = (state * 16807) % 2147483647
			return state / 2147483647
		end
		function r:NextNumber(a, b)
			if a == nil then
				return nxt()
			end
			return a + (b - a) * nxt()
		end
		function r:NextInteger(a, b)
			return math.floor(a + (b - a + 1) * nxt())
		end
		return r
	end,
}
math.randomseed(7)

---------------------------------------------------------------- signals
-- Handlers run through `task.spawn` when a scheduler exists (server sim), else immediately.
local SignalMT = {}
SignalMT.__index = SignalMT
function NewSignal()
	return setmetatable({ handlers = {}, waiting = {} }, SignalMT)
end
function SignalMT.Connect(self, fn)
	local h = { fn = fn, connected = true }
	table.insert(self.handlers, h)
	return { Connected = true, Disconnect = function()
		h.connected = false
	end }
end
function SignalMT.Once(self, fn)
	local h
	h = { fn = function(...)
		h.connected = false
		fn(...)
	end, connected = true }
	table.insert(self.handlers, h)
	return { Disconnect = function()
		h.connected = false
	end }
end
function SignalMT.Wait(self)
	local co = coroutine.running()
	table.insert(self.waiting, co)
	return coroutine.yield()
end
function SignalMT.Fire(self, ...)
	for _, h in ipairs(table.clone(self.handlers)) do
		if h.connected then
			if task and task.spawn then
				task.spawn(h.fn, ...)
			else
				h.fn(...)
			end
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, co in ipairs(waiting) do
		task.spawn(co, ...)
	end
end
local EVENT_NAMES = {
	Triggered = true, PromptButtonHoldBegan = true, PromptButtonHoldEnded = true, TriggerEnded = true,
	HealthChanged = true, Died = true, OnServerEvent = true, OnClientEvent = true, Completed = true,
	Changed = true, ChildAdded = true, DescendantAdded = true, Destroying = true, PlayerAdded = true,
	PlayerRemoving = true, Heartbeat = true, Stepped = true, RenderStepped = true, Touched = true,
	CharacterAdded = true, CharacterRemoving = true, AncestryChanged = true, MouseEnter = true, MouseLeave = true, Activated = true,
	MouseButton1Click = true, MouseButton1Down = true, FocusLost = true, Focused = true, InputBegan = true,
	InputEnded = true, InputChanged = true, PromptGamePassPurchaseFinished = true, PromptProductPurchaseFinished = true,
}
SIM_LOCAL_PLAYER = nil -- set by the client sim: remotes then loop back between server and client
REMOTE_LOG = {}

---------------------------------------------------------------- Instances
local InstMT = {}
local M = {}
local PART_CLASSES = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true, TrussPart = true, SpawnLocation = true }
ALL_INSTANCES = {}

Instance = {}
function Instance.new(className)
	local o = setmetatable({ _class = className, _props = { Name = className }, _children = {}, _attrs = {}, _tags = {}, _id = #ALL_INSTANCES + 1 }, InstMT)
	if PART_CLASSES[className] then
		o._props.Size = v3(4, 1, 2)
		o._props.CFrame = CFrame.new()
		o._props.Color = Color3.fromRGB(163, 162, 165)
		o._props.Transparency = 0
		o._props.CanCollide = true
		o._props.Material = Enum.Material.Plastic
		o._props.AssemblyLinearVelocity = v3(0, 0, 0)
		o._props.Anchored = false
	elseif className == "Humanoid" then
		o._props.Health = 100
		o._props.MaxHealth = 100
		o._props.WalkSpeed = 16
		o._props.HipHeight = 0
	elseif className == "ProximityPrompt" then
		o._props.Enabled = true
		o._props.HoldDuration = 0
	elseif className == "TextButton" or className == "ImageButton" or className == "TextBox" then
		o._props.Active = true
		o._props.Visible = true
		o._props.Text = ""
	elseif className == "Frame" or className == "TextLabel" or className == "ScrollingFrame" or className == "ImageLabel" or className == "ViewportFrame" then
		o._props.Visible = true
	elseif className == "ScreenGui" or className == "BillboardGui" or className == "SurfaceGui" or className == "Highlight" or className == "Beam" or className == "PointLight" or className == "ParticleEmitter" then
		o._props.Enabled = true
	elseif className == "Attachment" then
		o._props.CFrame = CFrame.new()
	elseif className == "Motor6D" then
		o._props.C0 = CFrame.new()
		o._props.C1 = CFrame.new()
		o._props.Transform = CFrame.new()
	end
	table.insert(ALL_INSTANCES, o)
	return o
end

local function isA(o, cls)
	if o._class == cls or cls == "Instance" then
		return true
	end
	if cls == "BasePart" then
		return PART_CLASSES[o._class] == true
	end
	if cls == "GuiObject" then
		return o._class == "Frame" or o._class == "TextLabel" or o._class == "TextButton"
	end
	return false
end

InstMT.__index = function(o, k)
	if k == "ClassName" then
		return o._class
	elseif k == "Parent" then
		return o._parent
	end
	if EVENT_NAMES[k] then
		o._signals = o._signals or {}
		o._signals[k] = o._signals[k] or NewSignal()
		return o._signals[k]
	end
	local m = M[k]
	if m then
		return m
	end
	local v = o._props[k]
	if v ~= nil then
		return v
	end
	if k == "Position" and o._props.CFrame then
		return o._props.CFrame.p
	elseif k == "WorldCFrame" and o._class == "Attachment" then
		local parentCF = o._parent and o._parent._props.CFrame or CFrame.new()
		return parentCF * o._props.CFrame
	elseif k == "WorldPosition" and o._class == "Attachment" then
		local parentCF = o._parent and o._parent._props.CFrame or CFrame.new()
		return (parentCF * o._props.CFrame).p
	elseif k == "AbsoluteSize" or k == "AbsolutePosition" then
		return Vector2.new(0, 0)
	elseif k == "Orientation" then
		return v3(0, 0, 0)
	end
	for _, c in ipairs(o._children) do
		if c._props.Name == k then
			return c
		end
	end
	return nil
end

InstMT.__newindex = function(o, k, v)
	if k == "Parent" then
		if o._parent then
			local list = o._parent._children
			for i, c in ipairs(list) do
				if c == o then
					table.remove(list, i)
					break
				end
			end
		end
		o._parent = v
		if v then
			table.insert(v._children, o)
		end
		return
	elseif k == "Position" and o._props.CFrame then
		o._props.CFrame = mk(v, o._props.CFrame.r)
		return
	elseif k == "WorldPosition" and o._class == "Attachment" then
		local parentCF = o._parent and o._parent._props.CFrame
		o._props.CFrame = parentCF and (parentCF:Inverse() * CFrame.new(v)) or CFrame.new(v)
		return
	end
	if o._class == "Player" and k == "Character" and v ~= nil then
		o._props.Character = v
		o.CharacterAdded:Fire(v)
		return
	end
	if o._class == "Humanoid" and k == "Health" then
		local before = o._props.Health or 0
		v = math.clamp(v, 0, o._props.MaxHealth or 100)
		o._props.Health = v
		if v ~= before then
			o.HealthChanged:Fire(v)
		end
		if v <= 0 and before > 0 then
			o.Died:Fire()
		end
		return
	end
	local old = o._props[k]
	o._props[k] = v
	if old ~= v and o._propSignals and o._propSignals[k] then
		o._propSignals[k]:Fire()
	end
	if o._class == "WeldConstraint" and (k == "Part0" or k == "Part1") then
		local p0, p1 = o._props.Part0, o._props.Part1
		if p0 and p1 then
			o._rel = p0._props.CFrame:Inverse() * p1._props.CFrame
		end
	end
end

InstMT.__tostring = function(o)
	return o._props.Name
end

function M.GetChildren(o)
	return table.clone(o._children)
end
function M.GetDescendants(o)
	local out = {}
	local function walk(x)
		for _, c in ipairs(x._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(o)
	return out
end
function M.FindFirstChild(o, name, recursive)
	for _, c in ipairs(o._children) do
		if c._props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(o._children) do
			local f = M.FindFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
M.WaitForChild = function(o, name)
	if o._props.Name == "ReplicatedStorage" and name == "Shared" then
		return __proxy("Shared")
	end
	return M.FindFirstChild(o, name)
end
function M.FindFirstChildWhichIsA(o, cls, recursive)
	for _, c in ipairs(o._children) do
		if isA(c, cls) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(o._children) do
			local f = M.FindFirstChildWhichIsA(c, cls, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function M.FindFirstChildOfClass(o, cls)
	for _, c in ipairs(o._children) do
		if c._class == cls then
			return c
		end
	end
	return nil
end
function M.IsA(o, cls)
	return isA(o, cls)
end
function M.SetAttribute(o, k, v)
	local old = o._attrs[k]
	o._attrs[k] = v
	if old ~= v and o._attrSignals and o._attrSignals[k] then
		o._attrSignals[k]:Fire()
	end
end
function M.GetAttributes(o)
	return table.clone(o._attrs)
end
function M.GetAttribute(o, k)
	return o._attrs[k]
end
function M.Destroy(o)
	o.Parent = nil
	o._destroyed = true
end
function M.ClearAllChildren(o)
	for _, c in ipairs(table.clone(o._children)) do
		c.Parent = nil
	end
end
function M.GetPropertyChangedSignal(o, k)
	o._propSignals = o._propSignals or {}
	o._propSignals[k] = o._propSignals[k] or NewSignal()
	return o._propSignals[k]
end
function M.GetAttributeChangedSignal(o, k)
	o._attrSignals = o._attrSignals or {}
	o._attrSignals[k] = o._attrSignals[k] or NewSignal()
	return o._attrSignals[k]
end
function M.Clone(o)
	local c = Instance.new(o._class)
	for k, v in pairs(o._props) do
		c._props[k] = v
	end
	for k, v in pairs(o._attrs) do
		c._attrs[k] = v
	end
	for _, child in ipairs(o._children) do
		M.Clone(child).Parent = c
	end
	return c
end
-- Humanoid
function M.MoveTo(o, pos)
	o._moveTo = pos
end
function M.SetStateEnabled() end
function M.ChangeState() end
function M.GetState()
	return Enum.HumanoidStateType.Running
end
-- BasePart
function M.SetNetworkOwner() end
function M.GetMass()
	return 1
end
-- Remotes
function M.FireClient(o, player, ...)
	table.insert(REMOTE_LOG, { remote = o._props.Name, player = player, args = table.pack(...) })
	if SIM_LOCAL_PLAYER and player == SIM_LOCAL_PLAYER then
		o.OnClientEvent:Fire(...)
	end
end
function M.FireAllClients(o, ...)
	table.insert(REMOTE_LOG, { remote = o._props.Name, all = true, args = table.pack(...) })
	if SIM_LOCAL_PLAYER then
		o.OnClientEvent:Fire(...)
	end
end
function M.FireServer(o, ...)
	if SIM_LOCAL_PLAYER then
		o.OnServerEvent:Fire(SIM_LOCAL_PLAYER, ...)
	end
end
function M.InvokeServer(o, ...)
	local fn = o._props.OnServerInvoke
	assert(fn, "InvokeServer: no server handler for " .. o._props.Name)
	return fn(SIM_LOCAL_PLAYER, ...)
end
-- misc client-side methods
function M.Emit() end
function M.Play() end
function M.Stop() end
function M.PlayLocalSound() end
function M.SetCoreGuiEnabled() end
function M.ViewportPointToRay(o)
	local cf = o._props.CFrame or CFrame.new()
	return { Origin = cf.p, Direction = cf.LookVector }
end
function M.CaptureFocus() end
function M.ReleaseFocus() end
-- Players service
function M.GetPlayers(o)
	local list = {}
	for _, c in ipairs(o._children) do
		if c._class == "Player" then
			table.insert(list, c)
		end
	end
	return list
end
function M.GetPlayerFromCharacter(o, model)
	for _, c in ipairs(o._children) do
		if c._class == "Player" and c._props.Character == model and model ~= nil then
			return c
		end
	end
	return nil
end
function M.GetPlayerByUserId(o, id)
	for _, c in ipairs(o._children) do
		if c._class == "Player" and c._props.UserId == id then
			return c
		end
	end
	return nil
end
-- Workspace
-- Lighting
function M.GetSunDirection()
	return Vector3.new(0.3, 0.85, 0.4).Unit
end
function M.GetPartBoundsInBox()
	return {}
end
function M.GetServerTimeNow()
	return os.clock()
end
function M.GetPivot(o)
	if o._props.PrimaryPart then
		return o._props.PrimaryPart._props.CFrame
	end
	if o._props.CFrame then
		return o._props.CFrame
	end
	return CFrame.new()
end
function M.PivotTo(o, target)
	if o._props.CFrame then
		o._props.CFrame = target
		return
	end
	local offset = target * M.GetPivot(o):Inverse()
	for _, d in ipairs(M.GetDescendants(o)) do
		if PART_CLASSES[d._class] then
			d._props.CFrame = offset * d._props.CFrame
		end
	end
end
function M.GetBoundingBox(o)
	local mn, mx = v3(1e9, 1e9, 1e9), v3(-1e9, -1e9, -1e9)
	for _, d in ipairs(M.GetDescendants(o)) do
		if PART_CLASSES[d._class] then
			local p, s = d._props.CFrame.p, d._props.Size
			local r = math.max(s.X, s.Y, s.Z) / 2
			mn = v3(math.min(mn.X, p.X - r), math.min(mn.Y, p.Y - r), math.min(mn.Z, p.Z - r))
			mx = v3(math.max(mx.X, p.X + r), math.max(mx.Y, p.Y + r), math.max(mx.Z, p.Z + r))
		end
	end
	return CFrame.new((mn + mx) / 2), mx - mn
end
---------------------------------------------------------------- terrain
-- Terrain edits are recorded in order and evaluated per column (x, z) as a list of vertical
-- intervals, which is enough for straight-down raycasts and top-down terrain maps.
TERRAIN_OPS = {}
local function matName(m)
	return type(m) == "table" and m.Name or tostring(m)
end
function M.FillBlock(_, cf, size, mat)
	table.insert(TERRAIN_OPS, { kind = "block", inv = cf:Inverse(), cy = cf.p.Y, size = size, mat = matName(mat),
		r = math.sqrt(size.X * size.X + size.Z * size.Z) / 2, cx = cf.p.X, cz = cf.p.Z })
end
function M.FillBall(_, c, radius, mat)
	table.insert(TERRAIN_OPS, { kind = "ball", cx = c.X, cy = c.Y, cz = c.Z, r = radius, mat = matName(mat) })
end
function M.FillCylinder(_, cf, height, radius, mat)
	table.insert(TERRAIN_OPS, { kind = "cyl", cx = cf.p.X, cy = cf.p.Y, cz = cf.p.Z, h = height, r = radius, mat = matName(mat) })
end
function M.ReplaceMaterial(_, region, _res, from, to)
	table.insert(TERRAIN_OPS, { kind = "replace", min = region.min, max = region.max, from = matName(from), to = matName(to),
		cx = (region.min.X + region.max.X) / 2, cz = (region.min.Z + region.max.Z) / 2,
		r = math.sqrt((region.max.X - region.min.X) ^ 2 + (region.max.Z - region.min.Z) ^ 2) / 2 })
end
Region3 = {
	new = function(a, b)
		local r = { min = a, max = b }
		function r:ExpandToGrid()
			return r
		end
		return r
	end,
}

-- intervals: sorted list of { lo, hi, mat } (no overlaps); gaps are air
local function setInterval(list, lo, hi, mat)
	local out = {}
	for _, iv in ipairs(list) do
		if iv[2] <= lo or iv[1] >= hi then
			table.insert(out, iv)
		else
			if iv[1] < lo then
				table.insert(out, { iv[1], lo, iv[3] })
			end
			if iv[2] > hi then
				table.insert(out, { hi, iv[2], iv[3] })
			end
		end
	end
	if mat ~= "Air" then
		table.insert(out, { lo, hi, mat })
	end
	table.sort(out, function(a, b)
		return a[1] < b[1]
	end)
	return out
end

-- Optional speed-up for big maps: bucket ops by grid cell (keeps their order).
local BUCKETS, BUCKET_SIZE = nil, 32
function TERRAIN_PREPARE()
	BUCKETS = {}
	for index, op in ipairs(TERRAIN_OPS) do
		local x0, x1 = math.floor((op.cx - op.r) / BUCKET_SIZE), math.floor((op.cx + op.r) / BUCKET_SIZE)
		local z0, z1 = math.floor((op.cz - op.r) / BUCKET_SIZE), math.floor((op.cz + op.r) / BUCKET_SIZE)
		for bx = x0, x1 do
			for bz = z0, z1 do
				local key = bx .. "," .. bz
				BUCKETS[key] = BUCKETS[key] or {}
				table.insert(BUCKETS[key], index)
			end
		end
	end
end

function TERRAIN_COLUMN(x, z)
	local list = {}
	local ops = TERRAIN_OPS
	if BUCKETS then
		local bucket = BUCKETS[math.floor(x / BUCKET_SIZE) .. "," .. math.floor(z / BUCKET_SIZE)] or {}
		ops = {}
		for _, index in ipairs(bucket) do
			table.insert(ops, TERRAIN_OPS[index])
		end
	end
	for _, op in ipairs(ops) do
		local dx, dz = x - op.cx, z - op.cz
		if dx * dx + dz * dz <= op.r * op.r + 1e-6 then
			if op.kind == "ball" then
				local half = math.sqrt(op.r * op.r - dx * dx - dz * dz)
				list = setInterval(list, op.cy - half, op.cy + half, op.mat)
			elseif op.kind == "cyl" then
				list = setInterval(list, op.cy - op.h / 2, op.cy + op.h / 2, op.mat)
			elseif op.kind == "block" then
				local l = op.inv * v3(x, op.cy, z)
				if math.abs(l.X) <= op.size.X / 2 and math.abs(l.Z) <= op.size.Z / 2 then
					list = setInterval(list, op.cy - op.size.Y / 2, op.cy + op.size.Y / 2, op.mat)
				end
			elseif op.kind == "replace" then
				if x >= op.min.X and x <= op.max.X and z >= op.min.Z and z <= op.max.Z then
					if op.from == "Air" then
						-- fill the gaps inside [min.Y, max.Y]
						local y = op.min.Y
						local gaps = {}
						for _, iv in ipairs(list) do
							if iv[1] > y and iv[1] > op.min.Y then
								table.insert(gaps, { math.max(y, op.min.Y), math.min(iv[1], op.max.Y) })
							end
							y = math.max(y, iv[2])
						end
						if y < op.max.Y then
							table.insert(gaps, { y, op.max.Y })
						end
						for _, g in ipairs(gaps) do
							if g[2] > g[1] then
								list = setInterval(list, g[1], g[2], op.to)
							end
						end
					else
						local changed = {}
						for _, iv in ipairs(list) do
							if iv[3] == op.from and iv[2] > op.min.Y and iv[1] < op.max.Y then
								table.insert(changed, { math.max(iv[1], op.min.Y), math.min(iv[2], op.max.Y) })
							end
						end
						for _, g in ipairs(changed) do
							list = setInterval(list, g[1], g[2], op.to)
						end
					end
				end
			end
		end
	end
	return list
end

-- Highest surface at or below `fromY`: returns y, material (water counts unless ignoreWater).
function TERRAIN_TOP(x, z, fromY, ignoreWater)
	local list = TERRAIN_COLUMN(x, z)
	for i = #list, 1, -1 do
		local iv = list[i]
		if iv[1] <= fromY and not (ignoreWater and iv[3] == "Water") then
			return math.min(iv[2], fromY), iv[3]
		end
	end
	return nil
end

RaycastParams = { new = function()
	return { FilterDescendantsInstances = {}, IgnoreWater = false }
end }
function M.Raycast(_, origin, dir, params)
	-- Only straight-down rays against terrain are simulated (parts are ignored).
	if math.abs(dir.X) > 1e-3 or math.abs(dir.Z) > 1e-3 or dir.Y >= 0 then
		return nil
	end
	local y, mat = TERRAIN_TOP(origin.X, origin.Z, origin.Y, params and params.IgnoreWater)
	if not y or y < origin.Y + dir.Y then
		return nil
	end
	return { Position = v3(origin.X, y, origin.Z), Material = Enum.Material[mat], Instance = workspace and workspace.Terrain }
end

---------------------------------------------------------------- services
workspace = Instance.new("Workspace")
workspace.Name = "Workspace"
local terrain = Instance.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace

local tagged = {} -- [tag] = { instances }
local tagSignals = {}
local function tagSignal(tag)
	tagSignals[tag] = tagSignals[tag] or NewSignal()
	return tagSignals[tag]
end
local replicatedStorage = Instance.new("ReplicatedStorage")
replicatedStorage.Name = "ReplicatedStorage"
local playersService = Instance.new("Players")
playersService.Name = "Players"
local guid = 0
local services = {
	CollectionService = {
		AddTag = function(_, inst, tag)
			if not inst._tags[tag] then
				inst._tags[tag] = true
				tagged[tag] = tagged[tag] or {}
				table.insert(tagged[tag], inst)
				tagSignal(tag):Fire(inst)
			end
		end,
		HasTag = function(_, inst, tag)
			return inst._tags[tag] == true
		end,
		GetTagged = function(_, tag)
			local out = {}
			for _, inst in ipairs(tagged[tag] or {}) do
				if not inst._destroyed then
					table.insert(out, inst)
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(_, tag)
			return tagSignal(tag)
		end,
		GetInstanceRemovedSignal = function()
			return NewSignal()
		end,
	},
	Lighting = Instance.new("Lighting"),
	HttpService = {
		GenerateGUID = function()
			guid += 1
			return string.format("%08x-guid-%d", math.random(1, 1e8), guid)
		end,
	},
	ReplicatedStorage = replicatedStorage,
	Players = playersService,
	RunService = {
		Heartbeat = NewSignal(),
		Stepped = NewSignal(),
		RenderStepped = NewSignal(),
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
	},
	TweenService = {
		Create = function(_, inst, _info, goal)
			local tween = { Completed = NewSignal() }
			function tween.Play()
				for k, v in pairs(goal) do
					inst[k] = v
				end
				tween.Completed:Fire(Enum.PlaybackState.Completed)
			end
			function tween.Cancel() end
			return tween
		end,
	},
	DataStoreService = {
		GetDataStore = function()
			return {
				GetAsync = function(_, key)
					return SIM_SAVES and SIM_SAVES[key] or nil
				end,
				UpdateAsync = function() end,
				SetAsync = function() end,
			}
		end,
	},
	Debris = {
		AddItem = function(_, item, lifetime)
			if task and task.delay then -- only the sim has a scheduler
				task.delay(lifetime or 10, function()
					item:Destroy()
				end)
			end
		end,
	},
	PhysicsService = { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end },
	ProximityPromptService = { PromptShown = NewSignal(), PromptHidden = NewSignal() },
	UserInputService = {
		InputBegan = NewSignal(),
		InputEnded = NewSignal(),
		InputChanged = NewSignal(),
		LastInputTypeChanged = NewSignal(),
		WindowFocusReleased = NewSignal(),
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GetMouseLocation = function()
			return Vector2.new(640, 360)
		end,
		IsKeyDown = function()
			return false
		end,
		GetFocusedTextBox = function()
			return nil
		end,
		GetLastInputType = function()
			return Enum.UserInputType.MouseMovement
		end,
	},
}
-- Roblox's Lighting defaults for the properties the game tweens
services.Lighting.ExposureCompensation = 0
services.Lighting.Brightness = 2
services.Lighting.ClockTime = 14
services.GuiService = Instance.new("GuiService")
function services.GuiService.GetGuiInset()
	return Vector2.new(0, 58), Vector2.new(0, 0) -- Roblox's top bar
end
services.MarketplaceService = Instance.new("MarketplaceService")
function services.MarketplaceService.UserOwnsGamePassAsync()
	return false
end
function services.MarketplaceService.PromptProductPurchase() end
function services.MarketplaceService.PromptGamePassPurchase() end
services.RunService.BindToRenderStep = function(_, _name, _priority, fn)
	services.RunService.RenderStepped:Connect(fn)
end
services.RunService.UnbindFromRenderStep = function() end
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.new(0, 50, 50)
camera.ViewportSize = Vector2.new(1280, 720)
camera.FieldOfView = 70
camera.Parent = workspace
workspace.CurrentCamera = camera
game = {
	GetService = function(_, name)
		if not services[name] then
			services[name] = Instance.new(name)
		end
		return services[name]
	end,
	BindToClose = function() end,
}
OverlapParams = { new = function()
	return {}
end }
TweenInfo = { new = function(...)
	return { ... }
end }

---------------------------------------------------------------- joints: pose a model from its Motor6D.Transform values
function SOLVE(model)
	local root = model._props.PrimaryPart
	local edges = {}
	local function add(a, b, kind, j)
		edges[a] = edges[a] or {}
		table.insert(edges[a], { other = b, kind = kind, j = j })
	end
	for _, d in ipairs(M.GetDescendants(model)) do
		if d._class == "Motor6D" and d._props.Part0 and d._props.Part1 then
			add(d._props.Part0, d._props.Part1, "m0", d)
			add(d._props.Part1, d._props.Part0, "m1", d)
		elseif d._class == "WeldConstraint" and d._rel then
			add(d._props.Part0, d._props.Part1, "w0", d)
			add(d._props.Part1, d._props.Part0, "w1", d)
		end
	end
	local done = { [root] = true }
	local queue = { root }
	while #queue > 0 do
		local a = table.remove(queue, 1)
		local acf = a._props.CFrame
		for _, e in ipairs(edges[a] or {}) do
			if not done[e.other] then
				local j = e.j
				local cf
				if e.kind == "m0" then
					cf = acf * j._props.C0 * j._props.Transform * j._props.C1:Inverse()
				elseif e.kind == "m1" then
					cf = acf * j._props.C1 * j._props.Transform:Inverse() * j._props.C0:Inverse()
				elseif e.kind == "w0" then
					cf = acf * j._rel
				else
					cf = acf * j._rel:Inverse()
				end
				e.other._props.CFrame = cf
				done[e.other] = true
				table.insert(queue, e.other)
			end
		end
	end
end

---------------------------------------------------------------- dump parts as JSON lines
local function fullName(o)
	local names = {}
	local x = o
	while x do
		table.insert(names, 1, x._props.Name)
		x = x._parent
	end
	return table.concat(names, ".")
end
local function jnum(n)
	return string.format("%.4f", n)
end
-- GUI dump for tools/preview/gui_render.py: every ScreenGui / GuiObject / UI layout helper under
-- `root` as one JSON line, with its parent's id so the renderer can rebuild the tree.
local GUI_CLASSES = {
	ScreenGui = true, Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true,
	ImageButton = true, ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true,
	UIListLayout = true, UIGridLayout = true, UIPadding = true, UICorner = true, UIStroke = true, UIScale = true,
}
local function jstr(v)
	v = tostring(v or "")
	v = v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", ""):gsub("\t", " ")
	return '"' .. v .. '"'
end
local function ju2(v)
	if type(v) ~= "table" or not v.X then
		return "null"
	end
	return string.format("[%s,%s,%s,%s]", jnum(v.X.Scale), jnum(v.X.Offset), jnum(v.Y.Scale), jnum(v.Y.Offset))
end
local function jud(v)
	if type(v) ~= "table" or v.Scale == nil then
		return "null"
	end
	return string.format("[%s,%s]", jnum(v.Scale), jnum(v.Offset))
end
local function jcol(c)
	if type(c) ~= "table" or c.R == nil then
		return "null"
	end
	return string.format("[%s,%s,%s]", jnum(c.R), jnum(c.G), jnum(c.B))
end
local function jv2(v)
	if type(v) ~= "table" or v.X == nil then
		return "null"
	end
	return string.format("[%s,%s]", jnum(v.X), jnum(v.Y))
end
local function jenum(e)
	return e and jstr(e.Name) or "null"
end
function GUI_DUMP(root, tag)
	local out = {}
	local list = { root }
	for _, d in ipairs(M.GetDescendants(root)) do
		table.insert(list, d)
	end
	for _, d in ipairs(list) do
		if GUI_CLASSES[d._class] then
			local p = d._props
			local fields = {
				'"tag":' .. jstr(tag),
				'"id":' .. d._id,
				'"parent":' .. (d._parent and d._parent._id or 0),
				'"class":' .. jstr(d._class),
				'"name":' .. jstr(p.Name),
				'"visible":' .. tostring(p.Visible ~= false),
				'"enabled":' .. tostring(p.Enabled ~= false),
				'"pos":' .. ju2(p.Position),
				'"size":' .. ju2(p.Size),
				'"anchor":' .. jv2(p.AnchorPoint),
				'"bg":' .. jcol(p.BackgroundColor3),
				'"bgt":' .. jnum(p.BackgroundTransparency or 0),
				'"z":' .. (p.ZIndex or 1),
				'"order":' .. (p.LayoutOrder or 0),
				'"text":' .. (p.Text ~= nil and jstr(p.Text) or "null"),
				'"textSize":' .. (p.TextSize or 14),
				'"textColor":' .. jcol(p.TextColor3),
				'"textT":' .. jnum(p.TextTransparency or 0),
				'"xAlign":' .. jenum(p.TextXAlignment),
				'"yAlign":' .. jenum(p.TextYAlignment),
				'"wrapped":' .. tostring(p.TextWrapped == true),
				'"scaled":' .. tostring(p.TextScaled == true),
				'"font":' .. jenum(p.Font),
				'"auto":' .. jenum(p.AutomaticSize),
				'"clips":' .. tostring(p.ClipsDescendants == true),
				'"canvasPos":' .. jv2(p.CanvasPosition),
				'"displayOrder":' .. (p.DisplayOrder or 0),
				'"ignoreInset":' .. tostring(p.IgnoreGuiInset == true),
				'"fill":' .. jenum(p.FillDirection),
				'"padding":' .. jud(p.Padding),
				'"hAlign":' .. jenum(p.HorizontalAlignment),
				'"vAlign":' .. jenum(p.VerticalAlignment),
				'"cellSize":' .. ju2(p.CellSize),
				'"cellPadding":' .. ju2(p.CellPadding),
				'"padL":' .. jud(p.PaddingLeft),
				'"padR":' .. jud(p.PaddingRight),
				'"padT":' .. jud(p.PaddingTop),
				'"padB":' .. jud(p.PaddingBottom),
				'"radius":' .. jud(p.CornerRadius),
				'"color":' .. jcol(p.Color),
				'"thickness":' .. (p.Thickness or 1),
				'"transparency":' .. jnum(p.Transparency or 0),
				'"scale":' .. jnum(p.Scale or 1),
			}
			table.insert(out, "{" .. table.concat(fields, ",") .. "}")
		end
	end
	return out
end

function DUMP(root, tag)
	local out = {}
	for _, d in ipairs(M.GetDescendants(root)) do
		if PART_CLASSES[d._class] then
			local p = d._props
			local mesh = nil
			for _, c in ipairs(d._children) do
				if c._class == "SpecialMesh" then
					mesh = c._props.MeshType and c._props.MeshType.Name or "Head"
				end
			end
			local cf = p.CFrame
			local r = cf.r
			local col = p.Color
			-- id of the closest Model ancestor (so tools can tell separate buildings apart)
			local mid = 0
			local a = d._parent
			while a do
				if a._class == "Model" then
					mid = a._id
					break
				end
				a = a._parent
			end
			table.insert(out, string.format(
				'{"tag":"%s","n":"%s","mid":%d,"path":"%s","c":"%s","shape":"%s","mesh":"%s","size":[%s,%s,%s],"cf":[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s],"col":[%s,%s,%s],"t":%s,"mat":"%s","collide":%s}',
				tag or "", p.Name, mid, fullName(d):gsub('"', ""), d._class, p.Shape and p.Shape.Name or "Block", mesh or "",
				jnum(p.Size.X), jnum(p.Size.Y), jnum(p.Size.Z),
				jnum(cf.p.X), jnum(cf.p.Y), jnum(cf.p.Z), jnum(r[1]), jnum(r[2]), jnum(r[3]), jnum(r[4]), jnum(r[5]), jnum(r[6]), jnum(r[7]), jnum(r[8]), jnum(r[9]),
				jnum(col.R), jnum(col.G), jnum(col.B), jnum(p.Transparency or 0), p.Material and p.Material.Name or "Plastic",
				tostring(p.CanCollide ~= false)
			))
		end
	end
	return out
end
