import sys
from PIL import Image, ImageDraw
from render import load, render
src, out = sys.argv[1], sys.argv[2]
views = sys.argv[3].split(',') if len(sys.argv) > 3 else ['q34', 'side']
# every type in Classes.Order (dragons_dump.luau lines them up 24 studs apart in that order);
# an optional 4th argument picks some of them: Tidecaller,Solaris
order = ['Shadowstalker', 'Stormwing', 'Behemoth', 'Frostwyrm', 'Venomspine', 'Tidecaller', 'Solaris']
classes = sys.argv[4].split(',') if len(sys.argv) > 4 else order
cells = []
for c in classes:
    i = order.index(c)
    parts = load(src, c)
    x = (i - 2) * 24
    row = []
    for v in views:
        if v == 'q34':
            eye, tgt = (x - 15, 9, -19), (x, 4, 2)
        elif v == 'side':
            eye, tgt = (x + 30, 6, 2), (x, 4, 2)
        elif v == 'top':
            eye, tgt = (x + 0.1, 36, 4), (x, 3, 3)
        elif v == 'back':
            eye, tgt = (x + 14, 10, 26), (x, 4, 0)
        elif v == 'front':
            eye, tgt = (x - 6, 9, -24), (x, 5, 0)
        elif v == 'high':
            eye, tgt = (x - 16, 22, -14), (x, 3, 2)
        im = render(parts, eye, tgt, f'_cell_{c}_{v}.png', size=(420, 300), floor_y=0, supersample=2)
        row.append(im)
    cells.append(row)
W, H = 420, 300
sheet = Image.new('RGB', (W * len(views), H * len(classes)), 'white')
d = ImageDraw.Draw(sheet)
for r, row in enumerate(cells):
    for cidx, im in enumerate(row):
        sheet.paste(im, (cidx * W, r * H))
    d.text((6, r * H + 4), classes[r], fill=(0, 0, 0))
sheet.save(out)
print('saved', out, sheet.size)
