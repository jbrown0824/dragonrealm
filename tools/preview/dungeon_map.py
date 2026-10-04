"""Top-down floor map of a dungeon from dungeon_check.luau's DUNGEON_MAP output.
Usage: python3 dungeon_map.py rows.txt out.png [pixels per stud]
Floors are shaded by height (light = high), water blue, lava orange; markers: green = entrance,
white = way out, red = monsters, orange = mini-boss, purple = boss, gold = the hoard."""
import sys
from PIL import Image, ImageDraw

rows, marks = [], []
for line in open(sys.argv[1]):
    parts = line.split()
    if not parts:
        continue
    if parts[0] == "M":
        marks.append((parts[1], float(parts[2]), float(parts[3])))
    elif len(parts) == 4:
        rows.append((float(parts[0]), float(parts[1]), float(parts[2]), parts[3]))
scale = float(sys.argv[3]) if len(sys.argv) > 3 else 2
xs = [r[0] for r in rows] + [m[1] for m in marks]
zs = [r[1] for r in rows] + [m[2] for m in marks]
x0, x1, z0, z1 = min(xs) - 10, max(xs) + 10, min(zs) - 10, max(zs) + 10
ys = [r[2] for r in rows]
y0, y1 = min(ys), max(ys)
W, H = int((x1 - x0) * scale), int((z1 - z0) * scale)
img = Image.new("RGB", (W, H), (12, 10, 14))
d = ImageDraw.Draw(img)
def px(x, z):
    return (x - x0) * scale, (z1 - z) * scale  # north (+z) up
for x, z, y, mat in rows:
    k = (y - y0) / max(1, y1 - y0)
    base = int(60 + 150 * k)
    color = (base, base, int(base * 0.95))
    if mat == "CrackedLava":
        color = (230, 110, 30)
    elif mat == "Mud":
        color = (70, 110, 170)  # (the Barrow's pool: water over mud)
    elif mat == "Cobblestone":
        color = (base + 20, base + 10, base - 10)
    a, b = px(x - 1, z + 1)
    c, e = px(x + 1, z - 1)
    d.rectangle([a, b, c, e], fill=color)
colors = {"spawn": (60, 220, 90), "exit": (255, 255, 255), "mob": (230, 50, 50), "mini": (255, 150, 40), "boss": (190, 80, 255), "chest": (255, 215, 60)}
for kind, x, z in marks:
    cx, cz = px(x, z)
    r = 7 if kind in ("mini", "boss") else 4
    d.ellipse([cx - r, cz - r, cx + r, cz + r], fill=colors.get(kind, (255, 0, 255)), outline=(0, 0, 0))
img.save(sys.argv[2])
print(f"{sys.argv[2]}: {W}x{H}, floors {y0:.0f}..{y1:.0f}")
