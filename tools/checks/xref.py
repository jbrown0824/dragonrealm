import re, os, sys, glob
ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src'))
files={p:open(p).read() for p in glob.glob(ROOT+'/**/*.luau', recursive=True)}
def modname(p): return os.path.basename(p).replace('.luau','')

def defined_members(src, name):
    mem=set()
    for m in re.finditer(r'function\s+%s[.:](\w+)\s*\('%name, src): mem.add(m.group(1))
    for m in re.finditer(r'^\s*%s\.(\w+)\s*='%name, src, re.M): mem.add(m.group(1))
    # table constructor: local Name = { a = ..., }
    m=re.search(r'local\s+%s\s*=\s*\{'%name, src)
    if m:
        depth=0; i=m.end()-1; start=i
        while i < len(src):
            if src[i]=='{': depth+=1
            elif src[i]=='}':
                depth-=1
                if depth==0: break
            i+=1
        body=src[start+1:i]
        # top-level keys only (depth 0 within body)
        d=0; buf=''
        for ch in body:
            if ch in '{(': d+=1
            elif ch in '})': d-=1
            if d==0: buf+=ch
            else: buf+=' '
        for k in re.finditer(r'(?:^|[,\n])\s*(\w+)\s*=', buf): mem.add(k.group(1))
    return mem

problems=[]
# 1. Server services
services={modname(p):(p,s) for p,s in files.items() if '/server/Services/' in p}
for p,s in files.items():
    if '/server/' not in p: continue
    for m in re.finditer(r'\bS\.(\w+)\.(\w+)', s):
        svc, mem = m.group(1), m.group(2)
        if svc not in services: problems.append(f'{p}: unknown service S.{svc}'); continue
        if mem not in defined_members(services[svc][1], svc):
            problems.append(f'{os.path.relpath(p,ROOT)}: S.{svc}.{mem} not defined')
# 2. Client App modules
init=files[ROOT+'/client/init.client.luau']
appmods={}
for m in re.finditer(r'App\.(\w+)\s*=\s*require\((Controllers|UI)\.(\w+)\)', init):
    appmods[m.group(1)]=ROOT+f'/client/{m.group(2)}/{m.group(3)}.luau'
for p,s in files.items():
    if '/client/' not in p: continue
    for m in re.finditer(r'\bApp\.(\w+)\.(\w+)', s):
        mod, mem = m.group(1), m.group(2)
        if mod not in appmods: problems.append(f'{os.path.relpath(p,ROOT)}: unknown App.{mod}'); continue
        mp=appmods[mod]; msrc=files[mp]; mname=modname(mp)
        if mem not in defined_members(msrc, mname):
            problems.append(f'{os.path.relpath(p,ROOT)}: App.{mod}.{mem} not defined in {mname}')
# 3. Shared util modules usage via local alias
shared={modname(p):(p,s) for p,s in files.items() if '/shared/' in p and '/Config/' not in p}
for p,s in files.items():
    for m in re.finditer(r'local\s+(\w+)\s*=\s*require\([^)]*?\.(\w+)\)', s):
        alias, target = m.group(1), m.group(2)
        if target in shared and target not in ('Signal',):
            mem_def=defined_members(shared[target][1], target)
            for u in re.finditer(r'\b%s\.(\w+)'%alias, s):
                if u.group(1) not in mem_def:
                    problems.append(f'{os.path.relpath(p,ROOT)}: {alias}.{u.group(1)} not defined in {target}')
# 4. Config module direct function usages (Classes.get, Zones.areaAt...)
configs={modname(p):(p,s) for p,s in files.items() if '/Config/' in p}
for p,s in files.items():
    for m in re.finditer(r'local\s+(\w+)\s*=\s*require\([^)]*?Config\.(\w+)\)', s):
        alias,target=m.group(1),m.group(2)
        if target not in configs: problems.append(f'{p}: missing config {target}'); continue
        csrc=configs[target][1]
        for u in re.finditer(r'\b%s\.(\w+)\s*\('%alias, s):
            fn=u.group(1)
            if not re.search(r'function\s+%s\.%s\s*\('%(target,fn), csrc):
                problems.append(f'{os.path.relpath(p,ROOT)}: {alias}.{fn}() not a function in Config.{target}')
# 5. Remote names
rsrc=shared['Remotes'][1]
names=set(re.findall(r'^\s*"(\w+)",', rsrc, re.M))
for p,s in files.items():
    for m in re.finditer(r'Remotes\.(event|func)\("(\w+)"\)', s):
        if m.group(2) not in names: problems.append(f'{os.path.relpath(p,ROOT)}: unknown remote {m.group(2)}')
# 6. requires of script.Parent.X exist
for p,s in files.items():
    d=os.path.dirname(p)
    for m in re.finditer(r'require\(script\.Parent\.(\w+)\)', s):
        if not os.path.exists(os.path.join(d, m.group(1)+'.luau')): problems.append(f'{p}: require script.Parent.{m.group(1)} missing')
    for m in re.finditer(r'require\(script\.Parent\.Parent\.(\w+)\.(\w+)\)', s):
        if not os.path.exists(os.path.join(os.path.dirname(d), m.group(1), m.group(2)+'.luau')): problems.append(f'{p}: require ..{m.group(1)}.{m.group(2)} missing')
    for m in re.finditer(r'require\(Shared\.(\w+)\)', s):
        if not os.path.exists(ROOT+'/shared/'+m.group(1)+'.luau'): problems.append(f'{p}: Shared.{m.group(1)} missing')
    for m in re.finditer(r'require\(Shared\.Config\.(\w+)\)', s):
        if not os.path.exists(ROOT+'/shared/Config/'+m.group(1)+'.luau'): problems.append(f'{p}: Config.{m.group(1)} missing')
print('\n'.join(sorted(set(problems))) or 'xref OK')
