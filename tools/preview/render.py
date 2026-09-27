"""Tiny software renderer for dumped Roblox parts (blocks, wedges, balls, cylinders, sphere meshes).

Usage as a module:
    parts = load("world.jsonl")
    render(parts, eye=(x,y,z), target=(x,y,z), out="view.png", size=(800,500), floor_y=0)
"""
import json, math
import numpy as np
from PIL import Image, ImageDraw

def load(path, tag=None):
    parts = []
    for line in open(path):
        if line.startswith('{'):
            p = json.loads(line)
            if tag is None or p.get('tag') == tag:
                parts.append(p)
    return parts

_sphere_cache = {}
def _unit_sphere(nu=14, nv=9):
    key = (nu, nv)
    if key in _sphere_cache:
        return _sphere_cache[key]
    verts = []
    for i in range(nv + 1):
        th = math.pi * i / nv
        for j in range(nu):
            ph = 2 * math.pi * j / nu
            verts.append((math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)))
    faces = []
    for i in range(nv):
        for j in range(nu):
            a = i * nu + j
            b = i * nu + (j + 1) % nu
            c = (i + 1) * nu + j
            d = (i + 1) * nu + (j + 1) % nu
            faces.append((a, c, b))
            faces.append((b, c, d))
    _sphere_cache[key] = (np.array(verts, float), np.array(faces, int))
    return _sphere_cache[key]

def _box(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    v = np.array([(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)], float)
    f = [(0,1,2),(0,2,3),(4,6,5),(4,7,6),(0,4,5),(0,5,1),(3,2,6),(3,6,7),(0,3,7),(0,7,4),(1,5,6),(1,6,2)]
    return v, np.array(f, int)

def _wedge(sx, sy, sz):
    x, y, z = sx / 2, sy / 2, sz / 2
    # bottom full, back (+Z) full height, slope from top-back to bottom-front
    v = np.array([(-x,-y,-z),(x,-y,-z),(x,-y,z),(-x,-y,z),(-x,y,z),(x,y,z)], float)
    f = [(0,1,2),(0,2,3),(3,2,5),(3,5,4),(0,4,5),(0,5,1),(0,3,4),(1,5,2)]
    return v, np.array(f, int)

def _cylinder_x(length, radius, n=16):
    verts = []
    for side in (-1, 1):
        for j in range(n):
            a = 2 * math.pi * j / n
            verts.append((side * length / 2, radius * math.cos(a), radius * math.sin(a)))
    verts.append((-length / 2, 0, 0)); verts.append((length / 2, 0, 0))
    faces = []
    for j in range(n):
        a, b = j, (j + 1) % n
        faces.append((a, b, n + b)); faces.append((a, n + b, n + a))
        faces.append((2 * n, b, a)); faces.append((2 * n + 1, n + a, n + b))
    return np.array(verts, float), np.array(faces, int)

def part_mesh(p):
    sx, sy, sz = p['size']
    if p['mesh'] == 'Sphere':
        v, f = _unit_sphere()
        return v * np.array([sx / 2, sy / 2, sz / 2]), f
    if p['mesh'] == 'Head':
        v, f = _unit_sphere()
        return v * np.array([sx / 2, sy / 2, sz / 2]), f
    if p['shape'] == 'Ball':
        r = min(sx, sy, sz) / 2
        v, f = _unit_sphere()
        return v * r, f
    if p['shape'] == 'Cylinder':
        return _cylinder_x(sx, min(sy, sz) / 2)
    if p['c'] == 'WedgePart':
        return _wedge(sx, sy, sz)
    return _box(sx, sy, sz)

def world_tris(p):
    v, f = part_mesh(p)
    cf = p['cf']
    pos = np.array(cf[0:3])
    R = np.array(cf[3:12]).reshape(3, 3)
    wv = v @ R.T + pos
    return wv[f]  # (M,3,3)

def render(parts, eye, target, out, size=(800, 500), fov=50, floor_y=None, floor_color=(0.45, 0.62, 0.35),
           sky=((0.55, 0.72, 0.95), (0.85, 0.9, 1.0)), radius=None, supersample=2, labels=None):
    W, H = size[0] * supersample, size[1] * supersample
    eye = np.array(eye, float); target = np.array(target, float)
    fwd = target - eye; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = 1 / math.tan(math.radians(fov) / 2)
    aspect = W / H
    light = np.array([-0.45, 0.8, 0.35]); light /= np.linalg.norm(light)

    img = np.zeros((H, W, 3))
    grad = np.linspace(0, 1, H)[:, None]
    img[:] = (np.array(sky[0]) * (1 - grad) + np.array(sky[1]) * grad)[:, None, :]
    zbuf = np.full((H, W), np.inf)

    tris_all = []
    if floor_y is not None and abs(eye[1] - floor_y) > 1e-6:
        # analytic ground plane: intersect every pixel's view ray with y = floor_y
        xs = ((np.arange(W) + 0.5) / W - 0.5) * 2 * aspect / f
        ys = (0.5 - (np.arange(H) + 0.5) / H) * 2 / f
        X, Y = np.meshgrid(xs, ys)
        dirs = fwd[None, None, :] + X[..., None] * right[None, None, :] + Y[..., None] * up[None, None, :]
        t = (floor_y - eye[1]) / np.where(np.abs(dirs[..., 1]) < 1e-9, 1e-9, dirs[..., 1])
        hit = t > 0
        img[hit] = np.array(floor_color) * 0.95
        zbuf[hit] = t[hit]  # view-space depth along fwd equals t because dirs has unit fwd component
    for p in parts:
        if p['t'] >= 0.95 or p['mat'] == 'ForceField':
            continue
        pos = np.array(p['cf'][0:3])
        if radius is not None and np.linalg.norm(pos - target) > radius + max(p['size']):
            continue
        t = p['t']
        if p['mat'] in ('Glass', 'Ice'):
            t = max(t, 0.25)
        col = tuple(p['col'])
        for tri in world_tris(p):
            tris_all.append((tri, col, t, p['mat']))

    def draw(tri, col, t, mat, zwrite):
        rel = tri - eye
        z = rel @ fwd
        if np.any(z < 0.3):
            return
        x = rel @ right; y = rel @ up
        sx = (x / z * f / aspect * 0.5 + 0.5) * W
        sy = (0.5 - y / z * f * 0.5) * H
        minx = max(int(math.floor(sx.min())), 0); maxx = min(int(math.ceil(sx.max())), W - 1)
        miny = max(int(math.floor(sy.min())), 0); maxy = min(int(math.ceil(sy.max())), H - 1)
        if minx > maxx or miny > maxy:
            return
        n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
        nl = np.linalg.norm(n)
        if nl < 1e-9:
            return
        n /= nl
        if np.dot(n, eye - tri[0]) < 0:
            n = -n
        if mat == 'Neon':
            shade = np.array(col) * 1.05 + 0.08
        else:
            d = max(0.0, float(np.dot(n, light)))
            shade = np.array(col) * (0.45 + 0.65 * d)
        shade = np.clip(shade, 0, 1)
        xs = np.arange(minx, maxx + 1) + 0.5
        ys = np.arange(miny, maxy + 1) + 0.5
        X, Y = np.meshgrid(xs, ys)
        x0, x1, x2 = sx; y0, y1, y2 = sy
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-12:
            return
        w0 = ((y1 - y2) * (X - x2) + (x2 - x1) * (Y - y2)) / den
        w1 = ((y2 - y0) * (X - x2) + (x0 - x2) * (Y - y2)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            return
        depth = w0 * z[0] + w1 * z[1] + w2 * z[2]
        region = zbuf[miny:maxy + 1, minx:maxx + 1]
        m = inside & (depth < region)
        if not m.any():
            return
        sub = img[miny:maxy + 1, minx:maxx + 1]
        if t > 0:
            sub[m] = sub[m] * t + shade * (1 - t)
        else:
            sub[m] = shade
        if zwrite:
            region[m] = depth[m]

    opaque = [x for x in tris_all if x[2] <= 0]
    trans = [x for x in tris_all if x[2] > 0]
    for tri, col, t, mat in opaque:
        draw(tri, col, 0, mat, True)
    trans.sort(key=lambda x: -np.dot(x[0].mean(axis=0) - eye, fwd))
    for tri, col, t, mat in trans:
        draw(tri, col, t, mat, False)

    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    if supersample > 1:
        im = im.resize(size, Image.LANCZOS)
    if labels:
        d = ImageDraw.Draw(im)
        for (xy, text) in labels:
            d.text(xy, text, fill=(20, 20, 20))
    im.save(out)
    return im
