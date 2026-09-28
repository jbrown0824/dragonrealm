#!/bin/zsh
# Renders the real client's main screens at desktop and phone size (tools/sim/gui_shots.sh) and
# fails if the client errors, text overflows its box, or a panel sticks out of the screen.
# The PNGs land in tools/preview/_gui_desktop and _gui_phone: look at them after UI changes.
D=${0:A:h}
P=$D/../preview
result=0
for spec in "desktop 1280 720 false" "phone 844 390 true"; do
  set -- ${=spec}
  out=$P/_gui_$1
  $D/../sim/gui_shots.sh $2 $3 $4 $out > $out.log 2>&1
  problems=$(grep -c "^    " $out.log)
  errors=$(grep -c "ERROR" $out/errors.txt 2>/dev/null)
  echo "gui $1 (${2}x$3): $(ls $out/*.png 2>/dev/null | wc -l | tr -d ' ') screens, $problems layout problems, $errors script errors"
  if [[ $problems -gt 0 || $errors -gt 0 ]]; then
    grep "^    \|problems" $out.log | head -20
    cat $out/errors.txt | head -20
    result=1
  fi
done
exit $result
