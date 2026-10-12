#!/usr/bin/env python3
"""Measure what each PC key types on each model, for the PC keyboard layout (tools/fix_keymap.py).

Runs the Verilator sim (verilator/obj_dir_fast/Vtop, Sharp layout: the keys by position) on each model, types
every character key and keypad key unshifted and shifted at the monitor (MZ-80B: Disk BASIC, MZ-2000: BASIC
from tape), and reads back from video RAM what appeared. Each key is typed as X, an index letter, the key: the letter
names the field, so a key that types nothing, deletes or moves the cursor only spoils its own field. That gives, per model, the matrix position and SHIFT state
that types each character; tools/keymap_pc_chars.json is the result (bank -> character -> [position, shift]).
For the MZ-700/800 (and MZ-1500, MZ-700 bank) mz800emu's character table fills in characters that only keys
without a PC legend reach (@ is on F6 in the Sharp layout).

usage: keymap_measure.py [--jobs N] [--models mz80k,mz80a,...]   (run from the repo root, after make fast)
       keymap_measure.py --verify [...]   type every character in the PC layout and check what each model shows
                                          (after fix_keymap.py and make fast)
"""
import argparse, json, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, 'verilator')
SW = os.path.join(ROOT, 'software')
ROMS = os.path.join(ROOT, 'rtl/software/roms')

# PC keys with legends: scan code -> unshifted, shifted (keypad: one character, measured unshifted only).
LEGEND = [(0x0E, '`~'), (0x16, '1!'), (0x1E, '2@'), (0x26, '3#'), (0x25, '4$'), (0x2E, '5%'), (0x36, '6^'),
          (0x3D, '7&'), (0x3E, '8*'), (0x46, '9('), (0x45, '0)'), (0x4E, '-_'), (0x55, '=+'), (0x54, '[{'),
          (0x5B, ']}'), (0x5D, '\\|'), (0x4C, ';:'), (0x52, '\'"'), (0x41, ',<'), (0x49, '.>'), (0x4A, '/?'),
          (0x7C, '*'), (0x7B, '-'), (0x79, '+'), (0x71, '.'), (0x70, '0'), (0x69, '1'), (0x72, '2'),
          (0x7A, '3'), (0x6B, '4'), (0x73, '5'), (0x74, '6'), (0x6C, '7'), (0x75, '8'), (0x7D, '9')]
EXTRA = {'mz80k': [0x09, 0x78, 0x07]}          # F10-F12: MZ-80K keys no PC legend reaches

# Sharp keys that no PC key reaches in the Sharp layout: measured through F1-F10 put on them in a scratch copy
# of the keymap (the sim reads ./software/mif/*.hex from its working directory).
PROBE = {'mz80k': [0x65, 0x82, 0x94], 'mz80a': [0x61, 0x64, 0x71, 0x81, 0x91, 0x93, 0x94],
         'mz80b': [0x97, 0xA1, 0xA4, 0xA5, 0xA6, 0xA7, 0xB4, 0xB5, 0xB6, 0xB7],
         'mz2000': [0x97, 0xA1, 0xA4, 0xA5, 0xA6, 0xA7, 0xB4, 0xB5, 0xB6, 0xB7]}
PROBE_KEYS = [0x05, 0x06, 0x04, 0x0C, 0x03, 0x0B, 0x01, 0x09, 0x78, 0x07]     # F1-F6, F9-F12

BANK = {'mz80k': 0, 'mz80a': 3, 'mz700': 4, 'mz800': 5, 'mz80b': 6, 'mz2000': 7}
MONITOR = {'mz80k': ('SP1002.rom', 0xBC6), 'mz80a': ('monitor_SA1510.rom', 0xAB5),
           'mz700': ('monitor_1Z-013A.rom', 0xA92), 'mz800': ('monitor_1Z-013A.rom', 0xA92)}
PER_LINE = 12
IDX = 'ABCDEFGHIJKLMNOPQRSTUVWYZ'                 # field names (no X)


def boot(model, tmp):
    """Sim arguments and the first frame to type at."""
    if model == 'mz800':
        return ['--type', '150:M'], 300                       # IPL menu: M for the monitor
    if model == 'mz80b':
        return ['--fdd', os.path.join(SW, 'idealine/mz-80b/rb_DSK/DSK/DISK23.DSK'), '--fdd-readonly'], 1000
    if model == 'mz2000':                                     # MZ-1Z002 BASIC as a tape image
        b = open(os.path.join(SW, 'rom-candidates/emuz2000_tf/emuz2000/MZ-1Z002.dat'), 'rb').read()
        h = bytearray(128); h[0] = 1; n = b'MZ-1Z002\r'; h[1:1 + len(n)] = n
        for k in range(1 + len(n), 18):
            h[k] = 0x0D
        h[18:20] = len(b).to_bytes(2, 'little'); h[22:24] = (0).to_bytes(2, 'little')
        t = os.path.join(tmp, 'mz2000.mzt'); open(t, 'wb').write(bytes(h) + b)
        return ['--fast-tape', '6', '--tape-image', t], 1700
    return [], 120


def keys_for(model, shifted, probe=False):
    if probe:
        return PROBE_KEYS[:len(PROBE.get(model, []))]
    ks = [c for c, l in LEGEND if len(l) == 2] if shifted else [c for c, l in LEGEND]
    return ks + ([] if shifted else EXTRA.get(model, []))


def probe_dir(model, tmp, tag):
    """A working directory for the sim whose keymap has F1-F10 on the model's PROBE positions."""
    d = os.path.join(tmp, f'probe_{model}_{tag}')
    os.makedirs(os.path.join(d, 'software/mif'), exist_ok=True)
    src = os.path.join(SIM, 'software/mif')
    for f in os.listdir(src):
        if f != 'combined_keymap.mif.hex' and not os.path.exists(os.path.join(d, 'software/mif', f)):
            os.symlink(os.path.join(src, f), os.path.join(d, 'software/mif', f))
    lines = open(os.path.join(src, 'combined_keymap.mif.hex')).read().split()
    bank = BANK[model]
    for code, pos in zip(PROBE_KEYS, PROBE.get(model, [])):
        lines[bank * 256 + code] = '%02x' % pos
    open(os.path.join(d, 'software/mif/combined_keymap.mif.hex'), 'w').write('\n'.join(lines) + '\n')
    return d


def line(fields):
    """Typed text for [(index letter, key text)]: X, letter, key, ... X, Return."""
    return ''.join('X' + l + k for l, k in fields) + 'X{RETURN}'


def run(model, shifted, tmp, probe=False):
    args, f0 = boot(model, tmp)
    ks = keys_for(model, shifted, probe)
    text = ''
    for i in range(0, len(ks), PER_LINE):
        text += line([(IDX[(j) % len(IDX)], ('{SSC%02X}' if shifted else '{SC%02X}') % c)
                      for j, c in enumerate(ks[i:i + PER_LINE], i)])
    n = len(ks) * 3 + len(ks) // PER_LINE * 3 + 4
    out = os.path.join(tmp, f'{model}_{int(shifted)}{"p" if probe else ""}.bin')
    end = f0 + n * 16 + 150
    subprocess.run([os.path.join(SIM, 'obj_dir_fast/Vtop'), '--model', model, *args, '--type-rate', '6:6',
                    '--shift-lead', '4', '--type', f'{f0}:{text}', '--stop-at-frame', str(end), '--vram-dump', out,
                    '--quiet'], cwd=probe_dir(model, tmp, int(shifted)) if probe else SIM,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return ks, open(out, 'rb').read()[0::2]


VERIFY = '!"#$%&\'()*+,-./0123456789:;<=>?@[\\]^_`{|}~'


def verify(model, tmp):
    args, f0 = boot(model, tmp)
    text = ''
    for i in range(0, len(VERIFY), PER_LINE):
        text += line([(IDX[j % len(IDX)], '\\' + c if c in '{}\\' else c) for j, c in enumerate(VERIFY[i:i + PER_LINE], i)])
    n = len(VERIFY) * 3 + len(VERIFY) // PER_LINE * 3 + 4
    out = os.path.join(tmp, f'{model}_v.bin')
    subprocess.run(['./obj_dir_fast/Vtop', '--model', model, *args, '--key-layout', 'pc', '--type-rate', '6:6',
                    '--shift-lead', '4', '--type', f'{f0}:{text}', '--stop-at-frame', str(f0 + n * 16 + 150),
                    '--vram-dump', out, '--quiet'],
                   cwd=SIM, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return open(out, 'rb').read()[0::2]


def decoder(model):
    if model not in MONITOR:                                  # MZ-80B/2000: ASCII in video RAM
        return (lambda b: chr(b) if 32 <= b < 127 else None), ord('X'), {c: ord(c) for c in IDX + ' '}
    conv = {}
    for l in open(os.path.join(ROOT, 'rtl/software/mif/ascii_conv.mif')):
        m = re.match(r'([0-9a-f]{3,4}):((?: [0-9a-f]{2})+);', l.strip(), re.I)
        if m:
            for i, b in enumerate(m[2].split()):
                conv[int(m[1], 16) + i] = int(b, 16)
    name, t = MONITOR[model]
    rom = open(os.path.join(ROMS, name), 'rb').read()
    d2c = {}
    for c in range(0x20, 0x7F):                               # ASCII -> Sharp ASCII -> display code
        sh = c if c < 0x60 else conv.get(0x100 + c, 0)
        if sh:
            d2c.setdefault(rom[t + sh], chr(c))
    return (lambda b: d2c.get(b)), rom[t + ord('X')], {c: rom[t + ord(c)] for c in IDX + ' '}


def fields(vram, sep, enc, n, cols=40):
    """The output of each of n keys, by index letter, from the typed lines (None where a field is unreadable).
    enc: index letter -> its byte in video RAM."""
    got = {}
    for r in range(25):
        row = vram[r * cols:(r + 1) * cols]
        for part in row.split(bytes([sep]))[1:]:
            if part and part[0] in enc.values():
                letter = next(l for l, b in enc.items() if b == part[0])
                got.setdefault(letter, []).append(part[1:])
    out = []
    for i in range(n):
        g = got.get(IDX[i % len(IDX)], [])
        k = i // len(IDX)                                     # letters repeat after 25 keys
        out.append(g[k].rstrip(bytes([enc[' ']])) if k < len(g) else None)
    return out


def mz800emu_table():
    """mz800emu's autotype table: character -> (row, bit, shift) for the MZ-700/800."""
    p = os.path.join(ROOT, 'refs/mz800emu/src/emulator/hw-generic/pio8255/pio8255.c')
    if not os.path.exists(p):
        return {}
    t = {}
    for m in re.finditer(r"\{'(\\.|[^'])', (\d+), (\d+), (\d)\}", open(p).read()):
        ch = m[1].encode().decode('unicode_escape')
        if ch.isprintable() and ch not in t:
            t[ch] = ((int(m[2]) << 4) | int(m[3]), int(m[4]))
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=6)
    ap.add_argument('--models', default=','.join(BANK))
    ap.add_argument('--verify', action='store_true')
    ap.add_argument('--probe-only', action='store_true', help='only the PROBE positions, merged into the JSON')
    a = ap.parse_args()
    models = a.models.split(',')
    if a.verify:
        chars = json.load(open(os.path.join(ROOT, 'tools/keymap_pc_chars.json')))
        bad = 0
        with tempfile.TemporaryDirectory() as tmp, ThreadPoolExecutor(a.jobs) as ex:
            jobs = {m: ex.submit(verify, m, tmp) for m in models}
            for m in models:
                dec, sep, enc = decoder(m)
                toks = fields(jobs[m].result(), sep, enc, len(VERIFY))
                have = chars.get(str(BANK[m]), {})
                wrong = []
                for i, c in enumerate(VERIFY):
                    got = '(missing)' if toks[i] is None else ''.join(dec(b) or '?' for b in toks[i])
                    want = c if c in have else ''
                    if got != want:
                        wrong.append(f'{c}->{got or "-"}')
                print(m, 'ok' if not wrong else 'WRONG ' + ' '.join(wrong),
                      '| not on this model:', ''.join(c for c in VERIFY if c not in have) or '-')
                bad += bool(wrong)
        sys.exit(1 if bad else 0)
    sharp = open(os.path.join(ROMS, 'combined_keymap.rom'), 'rb').read()
    path = os.path.join(ROOT, 'tools/keymap_pc_chars.json')
    result = json.load(open(path)) if os.path.exists(path) else {}
    with tempfile.TemporaryDirectory() as tmp, ThreadPoolExecutor(a.jobs) as ex:
        passes = [True] if a.probe_only else [False, True]
        jobs = {(m, s, p): ex.submit(run, m, s, tmp, p) for m in models for s in (False, True) for p in passes
                if not p or m in PROBE}
        emu = mz800emu_table()
        measured = {}
        for m in models:
            bank = BANK[m]
            dec, sep, enc = decoder(m)
            chars = {}
            report = []
            if a.probe_only:
                chars = {k: v for k, v in result.get(str(bank), {}).items()}
            for s, p in [(s, p) for s in (False, True) for p in passes if (m, s, p) in jobs]:
                ks, vram = jobs[(m, s, p)].result()
                toks = fields(vram, sep, enc, len(ks))
                for code, tok in zip(ks, toks):
                    pos = PROBE[m][PROBE_KEYS.index(code)] if p else sharp[bank * 256 + code]
                    shown = '(lost)' if tok is None else ''.join(dec(b) or '?' for b in tok)
                    report.append(f'{"S+" if s else ""}{"@%02X" % pos if p else "%02X" % code}:{shown or "-"}')
                    if tok is None or pos == 0xFF or len(tok) != 1 or dec(tok[0]) is None:
                        continue
                    own = bank < 4 and pos & 0x08
                    ch = dec(tok[0])
                    if ch not in chars or (not s and chars[ch][1]):
                        chars[ch] = [pos & 0xF7, 1 if (s or own) else 0]
            if m in ('mz700', 'mz800'):
                for ch, (pos, s) in emu.items():
                    chars.setdefault(ch, [pos, s])
            print(m, ' '.join(report))
            print('   ', ''.join(sorted(chars)))
            measured[m] = chars
        # Models that share a keyboard: the MZ-80K/80C/1200, the MZ-700/800 (and MZ-1500), the MZ-80B/2000.
        for group, banks in ((['mz80k'], [0, 1, 2]), (['mz80a'], [3]), (['mz800', 'mz700'], [4, 5]),
                             (['mz80b', 'mz2000'], [6, 7])):
            merged = {}
            for m in group:
                for ch, v in measured.get(m, {}).items():
                    merged.setdefault(ch, v)
            # The MZ-700/800 have no | key: SHIFT ] shows a glyph the monitor's table also gives |, but it is }
            # (mz800emu; the MZ-700 font). Two characters on one key: keep the one mz800emu has there.
            if 'mz800' in group and merged.get('|') == merged.get('}'):
                merged.pop('|', None)
            if merged:
                for b in banks:
                    result[str(b)] = {k: merged[k] for k in sorted(merged)}
    json.dump(result, open(path, 'w'), indent=1, sort_keys=True)
    print('wrote', path)


if __name__ == '__main__':
    main()
