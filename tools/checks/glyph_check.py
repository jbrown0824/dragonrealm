"""Flags characters that Roblox fonts can't draw: they show up as empty boxes in game.

* Emoji added in Unicode 12 or later (Roblox's emoji font is older): e.g. the rock 🪨 that
  showed as a box for the Stoneskin Draught.
* Symbol glyphs that Roblox's text fonts lack: ✕ ▲ ● ○ − ↺ ✔. Use emoji, plain ASCII, or draw
  the shape with Frames instead.
"""
import os, sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src')

NEW_EMOJI_RANGES = [
    (0x1FA70, 0x1FAFF),  # Symbols and Pictographs Extended-A: all Unicode 12+
    (0x1F90C, 0x1F90F), (0x1F93F, 0x1F93F), (0x1F971, 0x1F972), (0x1F977, 0x1F979), (0x1F97B, 0x1F97B),
    (0x1F9A3, 0x1F9AF), (0x1F9BA, 0x1F9BF), (0x1F9C3, 0x1F9CF),
]
BAD_SYMBOLS = {'✕', '▲', '●', '○', '−', '↺', '✔'}

def bad(ch):
    o = ord(ch)
    return ch in BAD_SYMBOLS or any(a <= o <= b for a, b in NEW_EMOJI_RANGES)

problems = 0
for root, _, files in os.walk(SRC):
    for f in sorted(files):
        if not f.endswith('.luau'):
            continue
        path = os.path.join(root, f)
        for n, line in enumerate(open(path, encoding='utf8'), 1):
            if line.lstrip().startswith('--'):
                continue
            for ch in line:
                if bad(ch):
                    problems += 1
                    print(f"{os.path.relpath(path, SRC)}:{n}: '{ch}' (U+{ord(ch):04X}) won't render in Roblox")
print(f"glyphs {'OK' if problems == 0 else 'FAILED'} ({problems} problems)")
sys.exit(1 if problems else 0)
