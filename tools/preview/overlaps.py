"""Find parts that clip into signs (and other chosen parts) using oriented-bounding-box tests."""
import json, sys, math
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from render import load

def obb(p):
    cf = p['cf']
    c = np.array(cf[0:3]); R = np.array(cf[3:12]).reshape(3, 3)
    sx, sy, sz = p['size']
    if p['shape'] == 'Ball':
        r = min(sx, sy, sz); sx = sy = sz = r
    if p['shape'] == 'Cylinder':
        r = min(sy, sz); sy = sz = r
    half = np.array([sx, sy, sz]) / 2
    if p['mesh'] in ('Sphere', 'Head') or p['shape'] in ('Ball', 'Cylinder'):
        half = half * 0.8  # round shapes: shrink a bit so corners don't count
    return c, R, half

def penetration(a, b):
    """Smallest overlap along the separating axes (0 or negative = no overlap)."""
    ca, Ra, ha = a; cb, Rb, hb = b
    axes = [Ra[:, i] for i in range(3)] + [Rb[:, i] for i in range(3)]
    for i in range(3):
        for j in range(3):
            ax = np.cross(Ra[:, i], Rb[:, j])
            if np.linalg.norm(ax) > 1e-6:
                axes.append(ax / np.linalg.norm(ax))
    d = cb - ca
    best = math.inf
    for ax in axes:
        ra = sum(ha[k] * abs(np.dot(Ra[:, k], ax)) for k in range(3))
        rb = sum(hb[k] * abs(np.dot(Rb[:, k], ax)) for k in range(3))
        dist = abs(np.dot(d, ax))
        pen = ra + rb - dist
        if pen <= 0:
            return 0
        best = min(best, pen)
    return best

def check(parts, is_subject, min_pen=0.3, ignore=lambda a, b: False):
    boxes = [obb(p) for p in parts]
    centers = np.array([b[0] for b in boxes])
    radii = np.array([np.linalg.norm(b[2]) for b in boxes])
    hits = []
    for i, p in enumerate(parts):
        if not is_subject(p):
            continue
        near = np.where(np.linalg.norm(centers - centers[i], axis=1) < radii + radii[i])[0]
        for j in near:
            if j == i or ignore(p, parts[j]):
                continue
            pen = penetration(boxes[i], boxes[j])
            if pen > min_pen:
                hits.append((pen, p, parts[j]))
    return hits

if __name__ == '__main__':
    parts = [p for p in load(sys.argv[1]) if p['t'] < 1]
    def is_sign(p):
        return p['n'] == 'Sign'
    hits = check(parts, is_sign, 0.3)
    seen = set()
    for pen, a, b in sorted(hits, key=lambda h: -h[0]):
        key = (a['path'], b['path'])
        if key in seen:
            continue
        seen.add(key)
        print(f"{pen:5.2f}  {a['path']} @ {[round(x,1) for x in a['cf'][:3]]}  <->  {b['path']} ({b['c']},{b['shape']}{','+b['mesh'] if b['mesh'] else ''}) @ {[round(x,1) for x in b['cf'][:3]]}")
    print(len(seen), 'sign overlaps')
