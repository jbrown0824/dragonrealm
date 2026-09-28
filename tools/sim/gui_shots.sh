#!/bin/zsh
# GUI screenshots of the real client at a screen size: gui_shots.sh <width> <height> <touch true|false> <outdir>
# e.g.  tools/sim/gui_shots.sh 1280 720 false /tmp/desktop   and   tools/sim/gui_shots.sh 844 390 true /tmp/phone
D=${0:A:h}
W=${1:-1280}; H=${2:-720}; TOUCH=${3:-false}; OUT=${4:-$D/_shots}
mkdir -p $OUT
printf 'GUI_W = %s\nGUI_H = %s\nGUI_TOUCH = %s\n' $W $H $TOUCH > $D/_gui_hdr.luau
cat $D/boot.luau $D/_gui_hdr.luau $D/gui_shots.luau > $D/_gui_driver.luau
python3 $D/bundle_server.py $D/_gui_driver.luau $D/_gui_bundle.luau && luau $D/_gui_bundle.luau > $OUT/gui.jsonl 2> $OUT/errors.txt
python3 $D/../preview/gui_render.py $OUT/gui.jsonl $OUT $W $H
cat $OUT/errors.txt | head -20
rm -f $D/_gui_hdr.luau $D/_gui_driver.luau $D/_gui_bundle.luau
