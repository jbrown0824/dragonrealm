#!/bin/zsh
# Syntax/lint, cross-reference and logic tests, then a place build. Run from anywhere.
set -e
D=${0:A:h}
$D/lint.sh
python3 $D/xref.py
python3 $D/glyph_check.py
python3 $D/bundle_tests.py $D/logic_test.luau $D/_tests.luau
luau $D/_tests.luau | grep -E "FAIL|PASSED|FAILURES"
rm -f $D/_tests.luau
# Village dragons' walking routes must stay clear of solid parts.
P=$D/../preview
python3 $P/bundle.py $P/world_dump.luau $P/_world.luau && luau $P/_world.luau > $P/world.jsonl
python3 $P/bundle.py $P/walk_dump.luau $P/_wd.luau && luau $P/_wd.luau > $P/walks.jsonl
python3 $P/walk_check.py $P/world.jsonl $P/walks.jsonl > $P/_walks.txt || { cat $P/_walks.txt; exit 1 }
tail -1 $P/_walks.txt
# Lakes and the river: deep enough, never over the void, boats afloat.
python3 $P/bundle.py $P/water_check.luau $P/_wc.luau && luau $P/_wc.luau > $P/_water.txt
grep -q "^0 water problems" $P/_water.txt || { cat $P/_water.txt; exit 1 }
tail -1 $P/_water.txt
# The client's screens rendered at desktop and phone size.
$D/gui_check.sh
cd $D/../.. && rojo build default.project.json -o DragonRealm.rbxlx
