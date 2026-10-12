#!/bin/bash
# Run the MZ-800 graphics tests in the simulation and in mz800emu and compare the pictures
# (640x200 canvas). Run from verilator/. Needs refs/mz800emu built with the headless CLI.
cd "$(dirname "$0")/../.."
E=../refs/mz800emu/build/build-mz800emu/mz800emu
OUT=out/modes
TESTS=${TESTS:-gfx640 gfx640h gfx320h gfx320b gfx320x gfxwm gfxwm640 gfxrw gfxrw16 gfxscr gfxscr640 gfxscr640b}
for t in $TESTS; do
    mkdir -p $OUT/emu_$t $OUT/sim_$t
    $E --headless --model mz800 --type 160:M --mzf tests/mz800/$t.mzf --mzf-direct --mzf-direct-frame 200 \
       --stop-at-frame 321 --screenshot 320 --crop canvas --out $OUT/emu_$t --quiet > $OUT/emu_$t/log 2>&1
    ( ./obj_dir_headless/Vtop --model mz800 --mzf tests/mz800/$t.mzf --mzf-direct --mzf-direct-frame 20 --type 200:M \
          --type '280:J2000\n' --stop-at-frame 401 --screenshot 400 --out $OUT/sim_$t --quiet > /dev/null 2>&1 ) &
done
wait
fail=0
for t in $TESTS; do
    printf "%-10s " $t
    python3 tests/mz800/cmp_emu.py $OUT/sim_$t/frame_000400.png $OUT/emu_$t/frame_000320.png || fail=1
done
exit $fail
