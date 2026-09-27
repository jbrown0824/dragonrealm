# Bundle mock runtime + game modules + a driver into one Luau script for the `luau` CLI.
import glob, os, sys
SIM=os.path.dirname(os.path.abspath(__file__))
SRC=os.path.normpath(os.path.join(SIM, '..', '..', 'src'))
driver=open(sys.argv[1]).read()
out=[r'''
local __modules, __cache = {}, {}
function __proxy(path) return setmetatable({__path=path}, {__index=function(t,k) if k=="Parent" then local p=string.match(t.__path, "^(.*)/[^/]+$") or ""; return __proxy(p) end; return __proxy(t.__path.."/"..k) end}) end
function require(p)
  local path = type(p)=="table" and rawget(p,"__path") or p
  if __cache[path] == nil then
    local f = __modules[path]; assert(f, "no module "..tostring(path))
    __cache[path] = f(__proxy(path))
  end
  return __cache[path]
end
''', open(os.path.join(SIM,'mock.luau')).read()]
for base, prefix in ((SRC+'/shared','Shared'), (SRC+'/server/World','Server/World')):
    for p in sorted(glob.glob(base+'/**/*.luau', recursive=True)):
        rel=os.path.relpath(p, base).replace('.luau','')
        out.append(f'__modules["{prefix}/{rel}"] = function(script)\n'+open(p).read()+'\nend\n')
out.append(driver)
open(sys.argv[2],'w').write('\n'.join(out))
