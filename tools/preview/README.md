# Offline preview tools

Checks and renders the world and dragons **without Roblox Studio**. `mock.luau` is a small stand-in
for the Roblox API (Vector3, CFrame, Instances, Motor6D posing), which is enough to run
`WorldBuilder` and `DragonBuilder` with the `luau` CLI and dump every part. The Python scripts
render those parts to PNGs and look for parts clipping into each other. The renders are simple
(shapes and colors, no Roblox materials or lighting).

Needs: `brew install luau`, plus Python 3 with numpy and Pillow.

```
cd tools/preview

# Every dragon type in a pose -> contact sheet
./pose.sh ground false 0.3 0 0 dragons.jsonl
python3 dragon_sheet.py dragons.jsonl dragons.png q34,side      # views: q34, side, top, back

# Whole map -> check signs for clipping
python3 bundle.py world_dump.luau _world.luau && luau _world.luau > world.jsonl
python3 overlaps.py world.jsonl

# Map with village dragons posed the way clients animate them
python3 bundle.py world_posed.luau _wp.luau && luau _wp.luau > world_posed.jsonl
```

Render any spot from Python:

```python
from render import load, render
parts = load("world.jsonl")
render(parts, eye=(-50, 14, -10), target=(-78, 8, -38), out="stall.png", floor_y=0, radius=90)
```
