# Offline preview tools

Checks and renders the world and dragons **without Roblox Studio**. `mock.luau` is a small stand-in
for the Roblox API (Vector3, CFrame, Instances, Motor6D posing), which is enough to run
`WorldBuilder` and `DragonBuilder` with the `luau` CLI and dump every part. Terrain edits (FillBlock,
FillBall, FillCylinder, ReplaceMaterial) are recorded and evaluated per column, which supports
straight-down raycasts (so `Props.groundY` works offline) and top-down terrain maps. The same mock
also backs the server/client simulation in `tools/sim`. The Python scripts
render those parts to PNGs and look for parts clipping into each other. The renders are simple
(shapes and colors, no Roblox materials or lighting).

Needs: `brew install luau`, plus Python 3 with numpy and Pillow.

```
cd tools/preview

# Every dragon type in a pose -> contact sheet
./pose.sh ground false 0.3 0 0 dragons.jsonl
python3 dragon_sheet.py dragons.jsonl dragons.png q34,side      # views: q34, side, top, back

# Whole map -> check signs for clipping, and buildings clipping into anything else
python3 bundle.py world_dump.luau _world.luau && luau _world.luau > world.jsonl
python3 overlaps.py world.jsonl
python3 overlaps.py world.jsonl buildings

# Signs: how far each board's bottom edge is above the terrain under it (should be >= 3.5)
python3 bundle.py sign_check.luau _sc.luau && luau _sc.luau

# Top-down terrain map (materials shaded by height, with every part's footprint on top).
# Optional header: TERRAIN_STEP, TERRAIN_MIN_X / MAX_X / MIN_Z / MAX_Z to zoom in.
printf 'TERRAIN_STEP=4\n' > _hdr.luau && cat _hdr.luau terrain_dump.luau > _td.luau
python3 bundle.py _td.luau _tdb.luau && luau _tdb.luau > terrain.txt
python3 terrain_map.py terrain.txt map.png 0.6

# Lake and river depths: no water over the void, not too much shallow water, longships afloat
# (also run by tools/checks/run_all.sh)
python3 bundle.py water_check.luau _wc.luau && luau _wc.luau

# Village dragons' walking routes vs solid parts (also run by tools/checks/run_all.sh)
python3 bundle.py walk_dump.luau _wd.luau && luau _wd.luau > walks.jsonl
python3 walk_check.py world.jsonl walks.jsonl        # optional 3rd arg: villager radius (default 2)

# Map with village dragons posed the way clients animate them
python3 bundle.py world_posed.luau _wp.luau && luau _wp.luau > world_posed.jsonl
```

Render any spot from Python:

```python
from render import load, render
parts = load("world.jsonl")
render(parts, eye=(-50, 14, -10), target=(-78, 8, -38), out="stall.png", floor_y=0, radius=90)
```
