"""Checks the village dragons' walks (walk_dump.luau) against the world's solid parts.

Usage: python3 walk_check.py world.jsonl walks.jsonl [radius]
Every walk is sampled every half stud; a sample fails if a collidable part in the Map overlaps a
villager-sized column (radius, from the floor + 0.7 to + 5 studs) at that spot. Walks up a house
ramp (floor -1) are only checked above the ramp."""
import json, sys
import numpy as np

def load(path, key):
    return [json.loads(l) for l in open(path) if l.startswith('{') and key in l]

def main(world, walks, radius=2.0):
    parts = []
    for p in load(world, '"cf"'):
        if not p.get('collide') or not p['path'].startswith('Workspace.Map'):
            continue
        cf = p['cf']
        parts.append((np.array(cf[0:3]), np.array(cf[3:12]).reshape(3, 3), np.array(p['size']) / 2, p))
    centers = np.array([c for c, _, _, _ in parts])
    reach = np.array([np.linalg.norm(h) for _, _, h, _ in parts]) + radius
    bad = 0
    for w in load(walks, '"walk"'):
        ax, az, bx, bz = w['walk']
        floor = w['floor']
        lo, hi = (3.2, 7) if floor < 0 else (floor + 0.7, floor + 5)
        a, b = np.array([ax, az]), np.array([bx, bz])
        n = max(2, int(np.linalg.norm(b - a) / 0.5))
        ts = np.linspace(0, 1, n)
        xz = a + (b - a) * ts[:, None]
        ys = np.arange(lo, hi + 0.01, 0.75)
        pts = np.array([[x, y, z] for x, z in xz for y in ys])
        # only parts whose bounding sphere can reach the walk
        seg = b - a
        L2 = max(seg @ seg, 1e-9)
        rel = centers[:, [0, 2]] - a
        t = np.clip(rel @ seg / L2, 0, 1)
        d = np.linalg.norm(rel - t[:, None] * seg, axis=1)
        hits = {}
        for i in np.nonzero(d < reach)[0]:
            c, R, half, p = parts[i]
            loc = (pts - c) @ R  # rows: R.T @ (pt - c)
            # grow the part sideways by the villager's radius (along each local axis, as much as
            # that axis points sideways in the world), never up or down
            grow = radius * np.sqrt(R[0, :] ** 2 + R[2, :] ** 2)
            if p['c'] == 'WedgePart':
                # solid under the slope that rises toward +Z (the ramps up to house doors)
                top = -half[1] + 2 * half[1] * (loc[:, 2] + half[2]) / (2 * half[2])
                inside = (np.abs(loc[:, 0]) < half[0] + grow[0]) & (np.abs(loc[:, 2]) < half[2] + grow[2]) & (loc[:, 1] > -half[1]) & (loc[:, 1] < np.minimum(top, half[1]))
            else:
                inside = np.all(np.abs(loc) < half + grow, axis=1)
            if inside.any():
                k = np.nonzero(inside)[0][0]
                hits[p['path']] = (round(pts[k][0], 1), round(pts[k][2], 1))
        if hits:
            bad += 1
            print(f"BLOCKED {w['label']}:")
            for path, at in list(hits.items())[:4]:
                print(f"    {path} near {at}")
    print(f"{bad} blocked walks")
    return bad

if __name__ == '__main__':
    sys.exit(1 if main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 2.0) else 0)
