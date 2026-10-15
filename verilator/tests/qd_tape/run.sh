#!/bin/bash
# tests/qd_tape: a tape mounted as a Quick Disk gives the stream tools/mzf2qdf.py would write. Usage: run.sh TAPE.mzt
set -e
T=$(cd "$(dirname "${1:?tape}")" && pwd)/$(basename "$1")    # absolute, before the cd
cd "$(dirname "$0")"
mkdir -p out
python3 - "$T" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
open('out/img.hex', 'w').write(''.join(f'{b:02x}\n' for b in d))
open('out/size', 'w').write(str(len(d)))
PY
python3 ../../../tools/mzf2qdf.py out/expected.qdf "$T" > /dev/null
python3 - <<'PY'
d = open('out/expected.qdf', 'rb').read()[16:]
end = len(d.rstrip(b"\x00")) + 200                   # the used part and some of the zeros after it (the head goes home 255 zeros after the last file)
open('out/expected.hex', 'w').write(''.join(f'{b:02x}\n' for b in d[:end]))
open('out/bytes', 'w').write(str(end))
PY
if [ ! -x obj_dir/Vtb ] || [ ../../../rtl/mz_qdisk.sv -nt obj_dir/Vtb ] || [ tb.sv -nt obj_dir/Vtb ]; then
    verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE --top-module tb -Mdir obj_dir \
        tb.sv ../../../rtl/mz_qdisk.sv ../../../rtl/wd1793_mem.v > out/build.log 2>&1 || { tail -20 out/build.log; exit 1; }
fi
./obj_dir/Vtb +size=$(cat out/size) +bytes=$(cat out/bytes) | grep -v "^- "
if cmp -s out/expected.hex out/stream.hex; then echo "PASS $(basename "$T")"; else
    echo "FAIL $(basename "$T"): first difference at byte $(diff <(cat out/expected.hex) <(cat out/stream.hex) | head -1)"; exit 1; fi
