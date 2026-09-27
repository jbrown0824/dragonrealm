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
UDim2 = { new = passthrough, fromOffset = passthrough, fromScale = passthrough }
UDim = { new = passthrough }
Vector2 = { new = function(x, y)
	return { X = x, Y = y }
end }
NumberSequence = { new = passthrough }
NumberSequenceKeypoint = { new = passthrough }
NumberRange = { new = passthrough }
ColorSequence = { new = passthrough }
ColorSequenceKeypoint = { new = passthrough }
Enum = setmetatable({}, {
	__index = function(_, typ)
		return setmetatable({}, {
			__index = function(_, name)
				return { EnumType = typ, Name = name, Value = 0 }
			end,
		})
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

---------------------------------------------------------------- Instances
local InstMT = {}
local M = {}
local PART_CLASSES = { Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true, TrussPart = true, SpawnLocation = true }
ALL_INSTANCES = {}

Instance = {}
function Instance.new(className)
	local o = setmetatable({ _class = className, _props = { Name = className }, _children = {}, _attrs = {}, _tags = {} }, InstMT)
	if PART_CLASSES[className] then
		o._props.Size = v3(4, 1, 2)
		o._props.CFrame = CFrame.new()
		o._props.Color = Color3.fromRGB(163, 162, 165)
		o._props.Transparency = 0
		o._props.CanCollide = true
		o._props.Material = Enum.Material.Plastic
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
		return o._parent.CFrame * o._props.CFrame
	elseif k == "WorldPosition" and o._class == "Attachment" then
		return (o._parent.CFrame * o._props.CFrame).p
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
		o._props.CFrame = o._parent.CFrame:Inverse() * CFrame.new(v)
		return
	end
	o._props[k] = v
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
	o._attrs[k] = v
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
local dummySignal = { Connect = function()
	return { Disconnect = function() end }
end }
function M.GetPropertyChangedSignal()
	return dummySignal
end
function M.GetAttributeChangedSignal()
	return dummySignal
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
-- Terrain no-ops
function M.FillBlock() end
function M.FillBall() end
function M.FillCylinder() end

---------------------------------------------------------------- services
workspace = Instance.new("Workspace")
workspace.Name = "Workspace"
local terrain = Instance.new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace

local services = {
	CollectionService = {
		AddTag = function(_, inst, tag)
			inst._tags[tag] = true
		end,
		GetTagged = function()
			return {}
		end,
	},
	Lighting = Instance.new("Lighting"),
	HttpService = {
		GenerateGUID = function()
			return tostring(math.random(1, 1e9))
		end,
	},
}
game = {
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return { WaitForChild = function(_, n)
				return __proxy(n)
			end }
		end
		return services[name] or Instance.new(name)
	end,
}

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
			table.insert(out, string.format(
				'{"tag":"%s","n":"%s","path":"%s","c":"%s","shape":"%s","mesh":"%s","size":[%s,%s,%s],"cf":[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s],"col":[%s,%s,%s],"t":%s,"mat":"%s","collide":%s}',
				tag or "", p.Name, fullName(d):gsub('"', ""), d._class, p.Shape and p.Shape.Name or "Block", mesh or "",
				jnum(p.Size.X), jnum(p.Size.Y), jnum(p.Size.Z),
				jnum(cf.p.X), jnum(cf.p.Y), jnum(cf.p.Z), jnum(r[1]), jnum(r[2]), jnum(r[3]), jnum(r[4]), jnum(r[5]), jnum(r[6]), jnum(r[7]), jnum(r[8]), jnum(r[9]),
				jnum(col.R), jnum(col.G), jnum(col.B), jnum(p.Transparency or 0), p.Material and p.Material.Name or "Plastic",
				tostring(p.CanCollide ~= false)
			))
		end
	end
	return out
end
