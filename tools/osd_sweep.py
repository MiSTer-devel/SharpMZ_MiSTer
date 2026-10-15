#!/usr/bin/env python3
"""Run the simulation once for every value of every OSD option (from SharpMZ.sv's CONF_STR), on a model the option
affects, and report which runs fail and which change the picture.

The sim sets options by name (sim_headless --osd), through sharpmz_top.sv, the same module the MiSTer top level uses,
so a value that breaks the machine here breaks it on the hardware.

    python3 tools/osd_sweep.py                       # all options; report in verilator/out/osd_sweep/report.md
    python3 tools/osd_sweep.py --only "Fast Tape" --frames 300 -j 4

Each run boots the model (--frames, default 200) and takes a screenshot of the last frame. A run "differs" when its
last frame is not the same as the model's run with the defaults; for options that only act on tape, disk or printer
use, "same" is the expected answer and the point of the run is that the machine still starts.
"""
import argparse
import concurrent.futures
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sharpmz_osd import ROOT, options

SIM_DIR = os.path.join(ROOT, 'verilator')

# Options video_mixer applies (outside sharpmz_top), so not in the simulation.
HARDWARE_ONLY = {'Scandoubler Fx', 'Aspect ratio'}

# The model each option is swept on (default MZ-700); Model itself is swept on its own values.
MODEL_FOR = {
    'MZ-80B/2000 Boot Reset': 'MZ-80B',
    'MZ-800 Mode': 'MZ-800',
    'MZ-800 RAM Disk': 'MZ-800',
    'MZ-800 Border': 'MZ-800',
    'Display Type': 'MZ-80A',
}

# The sim's own defaults differ from the core's in a few places (sim_headless write_config); set the core's here so
# the baseline is the machine a user gets.
CORE_DEFAULTS = 'Keyboard Layout=PC, Fast Tape=Fastest, Load Direct Start=Program, Tape Messages=On, MZ-800 Mode=MZ-700'


def run(binary, out, tag, assignments, frames):
    d = os.path.join(out, tag)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, 'frames.csv')
    cmd = [binary, '--osd', CORE_DEFAULTS, '--osd', assignments, '--stop-at-frame', str(frames + 1),
           '--frame-log', log, '--screenshot', str(frames), '--out', d, '--quiet']
    p = subprocess.run(cmd, cwd=SIM_DIR, capture_output=True, text=True)
    last = None
    if os.path.exists(log):
        for line in open(log):
            f = line.split(',')
            if f[0] == str(frames):
                last = f[1].strip()
    return p.returncode, last, p.stderr.strip().splitlines()[-1:] if p.returncode else []


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--bin', default=os.path.join(SIM_DIR, 'obj_dir_headless/Vtop'))
    ap.add_argument('--out', default=os.path.join(SIM_DIR, 'out/osd_sweep'))
    ap.add_argument('--frames', type=int, default=200)
    ap.add_argument('--only', action='append', help='option name (repeatable)')
    ap.add_argument('-j', type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()

    jobs = []           # (option, value, model, assignments)
    table = options()
    for name, (lo, width, values) in table.items():
        if a.only and name not in a.only:
            continue
        for v in values:
            if name == 'Model':
                jobs.append((name, v, v, f'Model={v}'))
            elif name not in HARDWARE_ONLY:
                m = MODEL_FOR.get(name, 'MZ-700')
                jobs.append((name, v, m, f'Model={m}, {name}={v}'))
    models = sorted({j[2] for j in jobs})

    def tag(*parts):
        return '_'.join(''.join(c if c.isalnum() else '-' for c in p) for p in parts)

    results = {}
    with concurrent.futures.ThreadPoolExecutor(a.j) as ex:
        base = {m: ex.submit(run, a.bin, a.out, tag('base', m), f'Model={m}', a.frames) for m in models}
        futs = {j: ex.submit(run, a.bin, a.out, tag(j[0], j[1]), j[3], a.frames) for j in jobs}
        for j, f in futs.items():
            results[j] = f.result()
            rc, h, err = results[j]
            print(f'{j[0]:26s} {j[1]:22s} {j[2]:8s} {"FAIL " + str(err) if rc else "ok"}', flush=True)
        base = {m: f.result() for m, f in base.items()}

    lines = ['# OSD option sweep', '',
             f'Each run: {a.frames} frames from power-on with the core\'s defaults plus the one option. '
             '"differs" compares the last frame with the same model\'s run with the defaults.', '',
             '| Option | Value | Model | Run | Picture | Screenshot |', '|---|---|---|---|---|---|']
    fails = 0
    for j, (rc, h, err) in results.items():
        bh = base[j[2]][1]
        fails += rc != 0 or h is None
        run_s = 'ok' if rc == 0 and h else f'**FAIL** {" ".join(err)}'
        pic = '' if h is None else ('same' if h == bh else 'differs')
        shot = os.path.join(tag(j[0], j[1]), f'frame_{a.frames:06d}.png')
        lines.append(f'| {j[0]} | {j[1]} | {j[2]} | {run_s} | {pic} | [png]({shot}) |')
    for name in table:
        if name in HARDWARE_ONLY and (not a.only or name in a.only):
            lines.append(f'| {name} | (all) | | hardware only (video_mixer) | | |')
    os.makedirs(a.out, exist_ok=True)
    open(os.path.join(a.out, 'report.md'), 'w').write('\n'.join(lines) + '\n')
    print(f'{len(results)} runs, {fails} failed; report: {os.path.join(a.out, "report.md")}')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
