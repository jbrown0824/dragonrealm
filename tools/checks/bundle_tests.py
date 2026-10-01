# Bundles the shared Luau modules + a test file into one script runnable by the `luau` CLI,
# with tiny stand-ins for the few Roblox APIs the shared code touches.
import glob, os, sys
ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src', 'shared'))
test=open(sys.argv[1]).read()
out=[]
out.append(r'''
local __modules, __cache = {}, {}
local function __proxy(path) return setmetatable({__path=path}, {__index=function(t,k) if k=="Parent" then local p=string.match(t.__path, "^(.*)/[^/]+$") or ""; return __proxy(p) end; return __proxy(t.__path.."/"..k) end}) end
local function require(p)
  local path = type(p)=="table" and rawget(p,"__path") or p
  if __cache[path] == nil then
    local f = __modules[path]; assert(f, "no module "..tostring(path))
    __cache[path] = f(__proxy(path))
  end
  return __cache[path]
end
-- Roblox stand-ins
local V3mt = {}
V3mt.__index = function(v,k)
  if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
  if k=="Unit" then local m=math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z); return Vector3.new(v.X/m,v.Y/m,v.Z/m) end
  if k=="Dot" then return function(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end end
  if k=="Lerp" then return function(a,b,t) return Vector3.new(a.X+(b.X-a.X)*t,a.Y+(b.Y-a.Y)*t,a.Z+(b.Z-a.Z)*t) end end
  if k=="Cross" then return function(a,b) return Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X) end end
  return nil
end
V3mt.__add=function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V3mt.__sub=function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V3mt.__mul=function(a,b) if type(a)=="number" then return Vector3.new(b.X*a,b.Y*a,b.Z*a) end; if type(b)=="number" then return Vector3.new(a.X*b,a.Y*b,a.Z*b) end; return Vector3.new(a.X*b.X,a.Y*b.Y,a.Z*b.Z) end
V3mt.__div=function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
V3mt.__unm=function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
V3mt.__eq=function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
V3mt.__tostring=function(v) return string.format("(%g,%g,%g)",v.X,v.Y,v.Z) end
Vector3 = { new=function(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0}, V3mt) end }
Vector3.zero = Vector3.new(0,0,0); Vector3.yAxis = Vector3.new(0,1,0)
Vector2 = { new=function(x,y) return {X=x or 0,Y=y or 0} end }
Color3 = { fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end, new=function(r,g,b) return {R=r,G=g,B=b} end }
local __guid = 0
game = { GetService=function(_, name) return { GenerateGUID=function() __guid += 1; return "guid-"..__guid end } end }
''')
for p in sorted(glob.glob(ROOT+'/**/*.luau', recursive=True)):
    rel = os.path.relpath(p, ROOT).replace('.luau','')
    key = 'Shared/' + rel
    out.append(f'__modules["{key}"] = function(script)\n' + open(p).read() + '\nend\n')
out.append('local Shared = __proxy("Shared")\n')
out.append(test)
open(sys.argv[2],'w').write('\n'.join(out))
