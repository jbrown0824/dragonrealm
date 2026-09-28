#!/bin/zsh
# Run the offline server + client simulations (boot.luau is prepended to each scenario).
D=${0:A:h}
result=0
for scenario in smoke client_smoke; do
  echo "=== $scenario"
  cat $D/boot.luau $D/$scenario.luau > $D/_driver.luau
  python3 $D/bundle_server.py $D/_driver.luau $D/_bundle.luau && luau $D/_bundle.luau > $D/_out.txt 2>&1
  grep -E "SIM ERROR|CHECK FAILED|^ERROR|script errors|^\\[" $D/_out.txt | grep -v "^\\[Admin\\]" | tail -40
  grep -q "0 script errors, 0 failed checks" $D/_out.txt || result=1
done
rm -f $D/_driver.luau $D/_bundle.luau
exit $result
