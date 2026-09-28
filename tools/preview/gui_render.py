"""Renders a GUI dump (GUI_DUMP in mock.luau, written by tools/sim/gui_shots.sh) to PNGs, one per
tag, at the given screen size. It lays out the tree the way Roblox does closely enough to check
layouts: UDim2 position/size with anchor points, UIScale on ScreenGuis, the top bar inset,
UIPadding, UIListLayout, UIGridLayout, automatic sizes, scrolling frames (clipped) and ZIndex.
Text uses Arial / Arial Rounded with Apple's emoji font, so it's close but not pixel-exact.

It also reports text that overflows its box ("text overflow") and elements that stick out of
the screen, which is how it catches clipped labels and off-screen windows on small screens.

Usage: python3 gui_render.py gui.jsonl outdir width height [inset]
"""
import json, os, re, sys
from collections import defaultdict
from PIL import Image, ImageDraw, ImageFont

FONT_FILES = {
    'title': '/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf',
    'bold': '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    'body': '/System/Library/Fonts/Supplemental/Arial.ttf',
}
EMOJI_FILE = '/System/Library/Fonts/Apple Color Emoji.ttc'
_fonts, _emoji_cache = {}, {}

def font(kind, size):
    size = max(4, int(round(size)))
    key = (kind, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_FILES[kind], size)
    return _fonts[key]

def font_kind(name):
    if name in ('FredokaOne', 'LuckiestGuy', 'Bangers'):
        return 'title'
    if name in ('Gotham', 'SourceSans', 'Arial'):
        return 'body'
    return 'bold'

def is_emoji(ch):
    o = ord(ch)
    return (o >= 0x1F000 or 0x2600 <= o <= 0x27BF or 0x2B00 <= o <= 0x2BFF or 0x2190 <= o <= 0x21FF
            or 0x2300 <= o <= 0x23FF or 0x25A0 <= o <= 0x25FF or o in (0x203C, 0x2049, 0x2122, 0x2139, 0x3030, 0x24C2))

def emoji_image(ch, size):
    key = (ch, int(size))
    if key not in _emoji_cache:
        try:
            f = ImageFont.truetype(EMOJI_FILE, 64)
            im = Image.new('RGBA', (80, 80), (0, 0, 0, 0))
            ImageDraw.Draw(im).text((0, 0), ch, font=f, embedded_color=True)
            bbox = im.getbbox() or (0, 0, 64, 64)
            im = im.crop((0, 0, max(64, bbox[2]), max(64, bbox[3])))
            s = max(1, int(size))
            _emoji_cache[key] = im.resize((s, s), Image.LANCZOS)
        except Exception:
            _emoji_cache[key] = None
    return _emoji_cache[key]

TAG_RE = re.compile(r'<[^>]+>')
def plain(text):
    text = TAG_RE.sub('', text or '')
    return text.replace('&lt;', '<').replace('&gt;', '>').replace('&amp;', '&').replace('️', '').replace('‍', '')

def text_width(s, f, size):
    w = 0
    for ch in s:
        if is_emoji(ch):
            w += size * 1.05
        else:
            w += f.getlength(ch)
    return w

def wrap(text, f, size, width, wrapped):
    lines = []
    for para in text.split('\n'):
        if not wrapped or width <= 0:
            lines.append(para)
            continue
        words, cur = para.split(' '), ''
        for word in words:
            trial = word if not cur else cur + ' ' + word
            if text_width(trial, f, size) <= width or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines

def col(c, default=(163, 162, 165)):
    if not c:
        return default
    return tuple(int(round(v * 255)) for v in c)

class Node:
    def __init__(self, d):
        self.d = d
        self.children = []
        self.helpers = defaultdict(list)
        self.rect = None

def build(records):
    nodes = {r['id']: Node(r) for r in records}
    roots = []
    for r in records:
        n = nodes[r['id']]
        parent = nodes.get(r['parent'])
        if r['class'].startswith('UI'):
            if parent:
                parent.helpers[r['class']].append(r)
            continue
        if parent and not r['class'] == 'ScreenGui':
            parent.children.append(n)
        elif r['class'] == 'ScreenGui':
            roots.append(n)
    return roots

def udim2(v, pw, ph, k=1.0):
    """k: the scale from UIScales on ancestors below the ScreenGui (offsets grow with it)."""
    if not v:
        return 0.0, 0.0
    return v[0] * pw + v[1] * k, v[2] * ph + v[3] * k

def text_height(d, width, k=1.0):
    size = d['textSize'] * k
    f = font(font_kind(d['font']), size)
    lines = wrap(plain(d['text']), f, size, width, d['wrapped'])
    return len(lines) * size * 1.2

def padding_of(node):
    p = node.helpers.get('UIPadding')
    if not p:
        return 0, 0, 0, 0
    p = p[0]
    w, h = node.rect[2], node.rect[3]
    k = getattr(node, 'k', 1.0)
    def pv(v, total):
        return (v[0] * total + v[1] * k) if v else 0
    return pv(p['padL'], w), pv(p['padR'], w), pv(p['padT'], h), pv(p['padB'], h)

def place(node, x, y, w, h, k=1.0):
    """Lay out node at rect (x, y, w, h) (already resolved), then its children. Returns final rect.
    k is the accumulated UIScale below the ScreenGui."""
    d = node.d
    ui = node.helpers.get('UIScale')
    if ui and d['class'] != 'ScreenGui' and abs(ui[0]['scale'] - 1) > 1e-6:
        f = ui[0]['scale']
        ax, ay = d['anchor'] or [0, 0]
        x, y = x + ax * w * (1 - f), y + ay * h * (1 - f)
        w, h = w * f, h * f
        k *= f
    node.k = k
    node.rect = [x, y, w, h]
    pl, pr, pt, pb = padding_of(node)
    cx, cy, cw, ch = x + pl, y + pt, max(0, w - pl - pr), max(0, h - pt - pb)
    if d['class'] == 'ScrollingFrame':
        cp = d.get('canvasPos') or [0, 0]
        cy -= cp[1]
    kids = [kid for kid in node.children if kid.d['visible']]
    lst = node.helpers.get('UIListLayout')
    grid = node.helpers.get('UIGridLayout')
    if lst:
        L = lst[0]
        horizontal = L['fill'] == 'Horizontal'
        gap = (L['padding'] or [0, 0])[1] * k + (L['padding'] or [0, 0])[0] * (cw if horizontal else ch)
        kids.sort(key=lambda kid: kid.d['order'])
        cur = 0
        for kid in kids:
            kw, kh = udim2(kid.d['size'], cw, ch, k)
            if horizontal:
                ky = cy
                if L['vAlign'] == 'Center':
                    ky = cy + (ch - kh) / 2
                elif L['vAlign'] == 'Bottom':
                    ky = cy + ch - kh
                r = place(kid, cx + cur, ky, kw, kh, k)
                cur += r[2] + gap
            else:
                kx = cx
                if L['hAlign'] == 'Center':
                    kx = cx + (cw - kw) / 2
                elif L['hAlign'] == 'Right':
                    kx = cx + cw - kw
                r = place(kid, kx, cy + cur, kw, kh, k)
                cur += r[3] + gap
    elif grid:
        G = grid[0]
        cs = G['cellSize'] or [0, 100, 0, 100]
        cpd = G['cellPadding'] or [0, 5, 0, 5]
        cellw, cellh = udim2(cs, cw, ch, k)
        padx, pady = udim2(cpd, cw, ch, k)
        per_row = max(1, int((cw + padx) // max(1, cellw + padx)))
        kids.sort(key=lambda kid: kid.d['order'])
        for i, kid in enumerate(kids):
            row, c = divmod(i, per_row)
            place(kid, cx + c * (cellw + padx), cy + row * (cellh + pady), cellw, cellh, k)
    else:
        for kid in kids:
            kw, kh = udim2(kid.d['size'], cw, ch, k)
            px, py = udim2(kid.d['pos'], cw, ch, k)
            ax, ay = kid.d['anchor'] or [0, 0]
            place(kid, cx + px - ax * kw, cy + py - ay * kh, kw, kh, k)
    # automatic size grows the box to fit its content
    auto = d.get('auto') or 'None'
    if auto in ('Y', 'XY') or auto in ('X', 'XY'):
        bottom, right = y + h, x + w
        for kid in kids:
            if kid.rect:
                bottom = max(bottom, kid.rect[1] + kid.rect[3] + pb)
                right = max(right, kid.rect[0] + kid.rect[2] + pr)
        if d.get('text') and d['class'] in ('TextLabel', 'TextButton') and not d['scaled']:
            bottom = max(bottom, y + pt + text_height(d, w - pl - pr, k) + pb)
        if auto in ('Y', 'XY'):
            node.rect[3] = bottom - y
        if auto in ('X', 'XY'):
            node.rect[2] = right - x
    return node.rect

def rounded(draw, box, radius, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = box
    if x1 - x0 < 1 or y1 - y0 < 1:
        return
    radius = max(0, min(radius, (x1 - x0) / 2, (y1 - y0) / 2))
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)

class Renderer:
    def __init__(self, width, height, inset):
        self.W, self.H, self.inset = width, height, inset
        self.problems = []

    def render(self, roots, out):
        img = Image.new('RGBA', (self.W, self.H), (70, 120, 70, 255))
        # a hint of the world and of Roblox's top bar
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, self.W, self.inset), fill=(40, 60, 40, 255))
        for i in range(3):
            d.ellipse((12 + i * 52, (self.inset - 44) / 2, 56 + i * 52, (self.inset + 44) / 2), fill=(20, 20, 20, 255))
        roots = [r for r in roots if r.d['enabled']]
        roots.sort(key=lambda r: r.d['displayOrder'])
        for root in roots:
            scale = 1.0
            ui = root.helpers.get('UIScale')
            if ui:
                scale = ui[0]['scale']
            top = 0 if root.d['ignoreInset'] else self.inset
            vw, vh = self.W / scale, (self.H - top) / scale
            place(root, 0, 0, vw, vh)
            self.scale, self.top = scale, top
            self.draw_tree(img, root, (0, 0, self.W, self.H))
        img.convert('RGB').save(out)

    def to_screen(self, rect):
        x, y, w, h = rect
        s = self.scale
        return (x * s, self.top + y * s, (x + w) * s, self.top + (y + h) * s)

    def draw_tree(self, img, node, clip):
        kids = sorted([k for k in node.children if k.d['visible']], key=lambda k: k.d['z'])
        for k in kids:
            self.draw_node(img, k, clip)
            kclip = clip
            if k.d['class'] == 'ScrollingFrame' or k.d['clips']:
                box = self.to_screen(k.rect)
                kclip = (max(clip[0], box[0]), max(clip[1], box[1]), min(clip[2], box[2]), min(clip[3], box[3]))
            self.draw_tree(img, k, kclip)

    def draw_node(self, img, node, clip):
        d, s = node.d, self.scale
        box = self.to_screen(node.rect)
        x0, y0, x1, y1 = box
        if x1 <= clip[0] or y1 <= clip[1] or x0 >= clip[2] or y0 >= clip[3]:
            return
        unclipped = clip == (0, 0, self.W, self.H)
        if unclipped and (x1 > self.W + 1 or y1 > self.H + 1 or x0 < -1 or y0 < -1) and d['class'] in ('Frame', 'TextButton', 'ScrollingFrame') and node.rect[2] > 20:
            self.problems.append(f"off screen: {d['class']} {d['name']!r} at {tuple(round(v) for v in box)}")
        lx0, ly0 = int(max(0, x0 - 4)), int(max(0, y0 - 4))
        lx1, ly1 = int(min(self.W, x1 + 4)), int(min(self.H, y1 + 4))
        if lx1 <= lx0 or ly1 <= ly0:
            return
        layer = Image.new('RGBA', (lx1 - lx0, ly1 - ly0), (0, 0, 0, 0))
        dr = ImageDraw.Draw(layer)
        rel = (x0 - lx0, y0 - ly0, x1 - lx0, y1 - ly0)
        radius = 0
        corner = node.helpers.get('UICorner')
        if corner:
            cr = corner[0]['radius'] or [0, 8]
            radius = (cr[0] * min(x1 - x0, y1 - y0) + cr[1] * s * node.k)
        alpha = int(255 * (1 - d['bgt']))
        if alpha > 0 and d['class'] not in ('ScreenGui',):
            rounded(dr, rel, radius, fill=col(d['bg']) + (alpha,))
        stroke = node.helpers.get('UIStroke')
        if stroke and d['class'] != 'TextLabel':
            st = stroke[0]
            sa = int(255 * (1 - st['transparency']))
            t = max(1, int(round(st['thickness'] * s * node.k)))
            if sa > 0:
                rounded(dr, (rel[0] - t / 2, rel[1] - t / 2, rel[2] + t / 2, rel[3] + t / 2), radius + t / 2, outline=col(st['color']) + (sa,), width=t)
        if d.get('text') and d['class'] in ('TextLabel', 'TextButton', 'TextBox'):
            self.draw_text(dr, layer, d, rel, s, node)
        # clip to the parent chain
        cx0, cy0 = int(max(clip[0], lx0)) - lx0, int(max(clip[1], ly0)) - ly0
        cx1, cy1 = int(min(clip[2], lx1)) - lx0, int(min(clip[3], ly1)) - ly0
        if cx1 <= cx0 or cy1 <= cy0:
            return
        part = layer.crop((cx0, cy0, cx1, cy1))
        img.alpha_composite(part, (lx0 + cx0, ly0 + cy0))

    def draw_text(self, dr, layer, d, rel, s, node):
        text = plain(d['text'])
        if not text.strip():
            return
        pl, pr, pt, pb = [v * s for v in padding_of(node)]
        s = s * node.k
        x0, y0, x1, y1 = rel[0] + pl, rel[1] + pt, rel[2] - pr, rel[3] - pb
        w, h = x1 - x0, y1 - y0
        kind = font_kind(d['font'])
        size = d['textSize'] * s
        if d['scaled']:
            size = max(6, min(h * 0.9, 100 * s))
            while size > 6:
                f = font(kind, size)
                lines = wrap(text, f, size, w, True)
                if len(lines) * size * 1.15 <= h and max(text_width(l, f, size) for l in lines) <= w:
                    break
                size -= 1
        f = font(kind, size)
        lines = wrap(text, f, size, w, d['wrapped'])
        lh = size * 1.18
        total = lh * len(lines)
        widest = max(text_width(l, f, size) for l in lines)
        if (total > h + 2 * s or widest > w + 2 * s) and d.get('auto', 'None') == 'None' and w > 0:
            self.problems.append(f"text overflow: {d['name']!r} {text[:40]!r} needs {widest / s:.0f}x{total / s:.0f}, box {w / s:.0f}x{h / s:.0f}")
        ya = d.get('yAlign') or 'Center'
        y = y0 if ya == 'Top' else (y1 - total if ya == 'Bottom' else y0 + (h - total) / 2)
        color = col(d['textColor'], (27, 42, 53)) + (int(255 * (1 - d['textT'])),)
        for line in lines:
            lw = text_width(line, f, size)
            xa = d.get('xAlign') or 'Center'
            x = x0 if xa == 'Left' else (x1 - lw if xa == 'Right' else x0 + (w - lw) / 2)
            for ch in line:
                if is_emoji(ch):
                    em = emoji_image(ch, size)
                    if em:
                        layer.alpha_composite(em, (int(max(0, x)), int(max(0, y + (lh - size) / 2))))
                    x += size * 1.05
                else:
                    dr.text((x, y + (lh - size) / 2), ch, font=f, fill=color)
                    x += f.getlength(ch)
            y += lh

def main(path, outdir, width, height, inset=58):
    by_tag = defaultdict(list)
    for line in open(path, encoding='utf8'):
        if line.startswith('{"tag"'):
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            by_tag[r['tag']].append(r)
    os.makedirs(outdir, exist_ok=True)
    for tag, records in by_tag.items():
        roots = build(records)
        r = Renderer(width, height, inset)
        out = os.path.join(outdir, tag + '.png')
        r.render(roots, out)
        print(f"wrote {out}" + (f"  ({len(r.problems)} layout problems)" if r.problems else ""))
        for p in r.problems[:25]:
            print("   ", p)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]) if len(sys.argv) > 5 else 58)
