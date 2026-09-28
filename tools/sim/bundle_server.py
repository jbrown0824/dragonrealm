"""Bundle the mock runtime, the virtual-time scheduler, every shared + server module and a driver
into one Luau script. Usage: python3 bundle_server.py driver.luau out.luau"""
import glob, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = os.path.join(HERE, '..', 'preview')
SRC = os.path.normpath(os.path.join(HERE, '..', '..', 'src'))
driver = open(sys.argv[1]).read()
out = [r'''
local __modules, __cache = {}, {}
function __proxy(path) return setmetatable({__path=path}, {__index=function(t,k)
  if k=="Parent" then local p=string.match(t.__path, "^(.*)/[^/]+$") or ""; return __proxy(p) end
  if k=="WaitForChild" or k=="FindFirstChild" then return function(self, name) return __proxy(rawget(self, "__path").."/"..name) end end
  return __proxy(t.__path.."/"..k) end}) end
function require(p)
  local path = type(p)=="table" and rawget(p,"__path") or p
  if __cache[path] == nil then
    local f = __modules[path]; assert(f, "no module "..tostring(path))
    __cache[path] = f(__proxy(path))
  end
  return __cache[path]
end
''', open(os.path.join(PREVIEW, 'mock.luau')).read(), open(os.path.join(HERE, 'runtime.luau')).read()]
for base, prefix in ((SRC + '/shared', 'Shared'), (SRC + '/server', 'Server'), (SRC + '/client', 'Client')):
    for p in sorted(glob.glob(base + '/**/*.luau', recursive=True)):
        if p.endswith('init.server.luau'):
            continue
        rel = os.path.relpath(p, base).replace('.luau', '')
        key = prefix if rel == 'init.client' else f'{prefix}/{rel}'  # the client entry script is "Client" itself
        out.append(f'__modules["{key}"] = function(script)\n' + open(p).read() + '\nend\n')
import re
init = open(SRC + '/server/init.server.luau').read()
order = re.search(r'local ORDER = \{(.*?)\}', init, re.S).group(1)
out.append('SIM_ORDER = {' + order + '}')
out.append(driver)
open(sys.argv[2], 'w').write('\n'.join(out))
