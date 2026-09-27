#!/bin/zsh
# Dump every dragon type in one pose.
# usage: ./pose.sh MODE BREATHING T SPEED VY out.jsonl
#   MODE: ground | jump | fall | fly     BREATHING: true | false
SIM=${0:A:h}
printf 'POSE_MODE=%s\nPOSE_BREATH=%s\nPOSE_T=%s\nPOSE_SPEED=%s\nPOSE_VY=%s\n' "\"$1\"" "$2" "$3" "$4" "$5" > $SIM/_pose_hdr.luau
cat $SIM/_pose_hdr.luau $SIM/dragons_dump.luau > $SIM/_dd.luau
cd $SIM && python3 bundle.py _dd.luau _dd_bundle.luau && luau _dd_bundle.luau > $6
rm -f $SIM/_pose_hdr.luau $SIM/_dd.luau $SIM/_dd_bundle.luau
