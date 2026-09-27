#!/bin/zsh
# Syntax/lint, cross-reference and logic tests, then a place build. Run from anywhere.
set -e
D=${0:A:h}
$D/lint.sh
python3 $D/xref.py
python3 $D/bundle_tests.py $D/logic_test.luau $D/_tests.luau
luau $D/_tests.luau | grep -E "FAIL|PASSED|FAILURES"
rm -f $D/_tests.luau
cd $D/../.. && rojo build default.project.json -o DragonRealm.rbxlx
