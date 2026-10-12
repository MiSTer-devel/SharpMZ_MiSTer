#!/usr/bin/env python3
"""Triage a folder of MZ-700 / MZ-800 programs: run each in the core's simulation and in mz800emu, side by side.

Usage: triage.py MODEL DIR [--jobs N] [--frames N] [--limit N] [--only N,N] [--direct-start] [--out DIR]
       MODEL is mz700 or mz800; DIR is searched for folders named MZ-700 / MZ-800 (as in the year-based collection)
       holding .mzf files, or with --any-folder every .mzf under DIR is taken.

Each single-file program is loaded straight into RAM and started with the monitor's J command (MZ-800: M, then J),
in the half-clock Verilator sim (verilator/obj_dir_fast/Vtop, `make fast`) and in mz800emu's headless mode
(refs/mz800emu/build/build-mz700emu-pal or build-mz800emu). A screenshot of each is taken FRAMES frames after the
start. The results go to OUT/<model>/: <n>_core.png, <n>_emu.png, results.csv (file, exec, fb hashes, whether the core
picture is blank or unchanged from the monitor) and contact sheets sheet_NN.png (core left, emulator right) for a
person to look through. Programs split into several files (Loader/Program/Part) and BASIC programs (types 02, 05) are listed as skipped:
they need the tape path or the BASIC interpreter. Run it with a Python that has Pillow for the contact sheets.
"""
import argparse, csv, hashlib, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, 'verilator/obj_dir_fast/Vtop')         # make fast: half clk_sys, same 320-wide pictures
EMU = {'mz700': os.path.join(ROOT, 'refs/mz800emu/build/build-mz700emu-pal/mz700emu-pal'),
       'mz800': os.path.join(ROOT, 'refs/mz800emu/build/build-mz800emu/mz800emu')}


def header(path):
    d = open(path, 'rb').read(128)
    return d[0], d[18] | d[19] << 8, d[20] | d[21] << 8, d[22] | d[23] << 8


def run_one(model, i, path, frames, out, direct_start=False):
    path, out = os.path.abspath(path), os.path.abspath(out)
    t, size, load, exe = header(path)
    core_png = os.path.join(out, f'{i:04d}_core.png')
    emu_png = os.path.join(out, f'{i:04d}_emu.png')
    jtype = f'J{exe:04X}\\n'
    # Core: direct load at frame 20 (warm reset into the monitor), then J at the prompt (MZ-800: M first).
    start = 200 if model == 'mz800' else 100
    types = ['--type', '200:M', '--type', f'280:{jtype}'] if model == 'mz800' else ['--type', f'100:{jtype}']
    shot = start + 80 + frames
    if direct_start:                     # the core starts the program itself, about 75 frames after the load
        types, shot = [], 100 + frames
    sdir = os.path.join(out, f'c{i:04d}')
    subprocess.run([SIM, '--model', model, '--mzf', path, '--mzf-direct', '--mzf-direct-frame', '20', *types,
                    *(['--direct-start'] if direct_start else []),
                    '--stop-at-frame', str(shot + 1), '--screenshot', str(shot), '--out', sdir, '--quiet'],
                   cwd=os.path.dirname(os.path.dirname(SIM)),          # the sim reads its ROMs from software/mif there
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=7200)
    src = os.path.join(sdir, f'frame_{shot:06d}.png')
    if os.path.exists(src):
        os.replace(src, core_png)
    # Emulator: its direct load sets PC to the exec address itself.
    edir = os.path.join(out, f'e{i:04d}')
    eshot = 100 + frames
    subprocess.run([EMU[model], '--headless', '--model', model, '--mzf', path, '--mzf-direct', '--mzf-direct-frame', '100',
                    '--stop-at-frame', str(eshot + 1), '--screenshot', str(eshot), '--out', edir],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    esrc = os.path.join(edir, f'frame_{eshot:06d}.png')
    if os.path.exists(esrc):
        os.replace(esrc, emu_png)
    h = lambda p: hashlib.md5(open(p, 'rb').read()).hexdigest()[:8] if os.path.exists(p) else ''
    return [i, os.path.basename(path), f'{t:02x}', f'{load:04x}', f'{exe:04x}', h(core_png), h(emu_png)]


def sheets(out, rows):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print('no Pillow: no contact sheets')
        return
    per = 12
    for s in range(0, len(rows), per):
        chunk = rows[s:s + per]
        sheet = Image.new('RGB', (2 * 320 + 10, len(chunk) * 214), 'gray')
        d = ImageDraw.Draw(sheet)
        for k, r in enumerate(chunk):
            y = k * 214
            d.text((2, y + 1), f'{r[0]:04d} {r[1][:70]}', fill='white')
            for x, name in ((0, 'core'), (330, 'emu')):
                p = os.path.join(out, f'{r[0]:04d}_{name}.png')
                if os.path.exists(p):
                    sheet.paste(Image.open(p).convert('RGB').resize((320, 200)), (x, y + 14))
        sheet.save(os.path.join(out, f'sheet_{s // per:02d}.png'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('model', choices=['mz700', 'mz800'])
    ap.add_argument('dir')
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--frames', type=int, default=500)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--any-folder', action='store_true', help='take every .mzf, not only those in MZ-700 / MZ-800 folders')
    ap.add_argument('--direct-start', action='store_true',
                    help='the core starts the program after the load (OSD Load Direct: Start Program) instead of J typed')
    ap.add_argument('--only', default='', help='comma-separated title numbers to run (from an earlier results.csv)')
    ap.add_argument('--out', default=os.path.join(ROOT, 'verilator/out/triage'))
    a = ap.parse_args()
    out = os.path.join(a.out, a.model)
    os.makedirs(out, exist_ok=True)
    files, skipped = [], []
    folder = {'mz700': 'MZ-700', 'mz800': 'MZ-800'}[a.model]
    for root, _, fs in os.walk(a.dir):
        if os.path.basename(root) != folder and not a.any_folder:   # the collection sorts titles by machine
            continue
        for f in sorted(fs):
            if not f.lower().endswith('.mzf'):
                continue
            p = os.path.join(root, f)
            multi = any(w in f for w in ('(Loader', '(Program', '(Part', 'Part ', '(Opening'))
            if multi or header(p)[0] != 1:            # multi-file, or not machine code (05/02: BASIC programs)
                skipped.append(p)
            else:
                files.append(p)
    files.sort()
    if a.limit:
        files = files[:a.limit]
    only = {int(n) for n in a.only.split(',') if n}
    print(f'{len(files)} single-file machine-code programs, {len(skipped)} skipped (multi-file or BASIC)', flush=True)
    rows = []
    with ThreadPoolExecutor(a.jobs) as ex:
        futs = [ex.submit(run_one, a.model, i, p, a.frames, out, a.direct_start)
                for i, p in enumerate(files) if not only or i in only]
        for f in futs:
            r = f.result()
            rows.append(r)
            print(' '.join(map(str, r)), flush=True)
    rows.sort()
    with open(os.path.join(out, 'results.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['n', 'file', 'type', 'load', 'exec', 'core_png_md5', 'emu_png_md5'])
        w.writerows(rows)
        for p in skipped:
            w.writerow(['skip', os.path.basename(p), f'{header(p)[0]:02x}', '', '', '', ''])
    sheets(out, rows)
    return 0


if __name__ == '__main__':
    sys.exit(main())
