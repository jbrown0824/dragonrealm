"""Top-down map of the generated world: terrain colored by material (shaded by height) with
every part's footprint drawn on top. Usage: python3 terrain_map.py dump.txt out.png [scale]"""
import json, sys
import numpy as np
from PIL import Image, ImageDraw

COLORS = {
    'Grass': (96, 150, 70), 'LeafyGrass': (84, 128, 60), 'Snow': (235, 240, 248), 'Sand': (214, 196, 140),
    'Water': (60, 120, 200), 'Rock': (120, 118, 115), 'Mud': (110, 85, 60), 'Cobblestone': (150, 145, 140),
    'Ice': (175, 215, 240), 'CrackedLava': (140, 50, 30), 'Basalt': (60, 55, 55), 'Ground': (120, 95, 70),
    'Slate': (100, 100, 105), 'None': (0, 0, 0),
}

def main(path, out, scale=1.0):
    cells, parts = [], []
    for line in open(path):
        if line.startswith('T '):
            for chunk in line[2:].strip().split(' T '):
                x, z, y, m = chunk.split()
                cells.append((int(x), int(z), float(y), m))
        elif line.startswith('{'):
            parts.append(json.loads(line))
    xs = sorted({c[0] for c in cells}); zs = sorted({c[1] for c in cells})
    step = xs[1] - xs[0]
    W, H = len(xs), len(zs)
    img = np.zeros((H, W, 3), np.uint8)
    xi = {x: i for i, x in enumerate(xs)}; zi = {z: i for i, z in enumerate(zs)}
    for x, z, y, m in cells:
        base = np.array(COLORS.get(m, (255, 0, 255)), float)
        shade = np.clip(1 + y / 60, 0.55, 1.35)
        img[zi[z], xi[x]] = np.clip(base * shade, 0, 255)
    im = Image.fromarray(img).resize((int(W * step * scale), int(H * step * scale)), Image.NEAREST)
    d = ImageDraw.Draw(im, 'RGBA')
    x0, z0 = xs[0], zs[0]
    def px(x, z):
        return ((x - x0) * scale, (z - z0) * scale)
    for p in parts:
        if p['t'] >= 1:
            continue
        cf = p['cf']; c = np.array(cf[0:3]); R = np.array(cf[3:12]).reshape(3, 3)
        sx, sy, sz = p['size']
        corners = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            w = c + R @ np.array([a * sx / 2, 0, b * sz / 2])
            corners.append(px(w[0], w[2]))
        col = tuple(int(v * 255) for v in p['col'])
        d.polygon(corners, fill=col + (150,))
    im.save(out)
    print('wrote', out, im.size)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 1.0)
