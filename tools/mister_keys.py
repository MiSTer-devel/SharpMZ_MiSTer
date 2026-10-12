#!/usr/bin/env python3
"""Virtual keyboard for a MiSTer: type into the running core from ssh, without mrext. Needs python3 and
/dev/uinput (both on the stock MiSTer Linux). Lives on the SD card as /media/fat/tools/mister_keys.py.

  mister_keys.py start              start the keyboard daemon in the background (if it isn't running)
  mister_keys.py stop               stop it
  mister_keys.py status             running or not
  mister_keys.py type TEXT          type TEXT (US layout; \\n = Return; {F12} {ESC} {UP} ... = named keys)
  mister_keys.py key CODE [CODE..]  Linux key codes; a negative code is typed with SHIFT held; w500 waits 500 ms;
                                    A+B+C holds the keys together (29+56+100 = LCtrl+LAlt+RAlt, Main's reset)
  mister_keys.py serve [FIFO]       run the daemon in the foreground (what start runs)
  mister_keys.py joy STATE..        virtual gamepad (an Xbox 360 pad to Main, so it is mapped without setup): hold
                                    up/down/left/right/a/b/x/y/start/select until the next joy line; "joy" alone releases
  mister_keys.py watch [DIR]        autotype: when Main loads a core or MGL whose name (/tmp/CORENAME, an MGL's
                                    setname) has DIR/<name>.steps, play it (default DIR /media/fat/tools/autotype)
  mister_keys.py watch-start|watch-stop   run the watcher in the background / stop it

A .steps file has one step per line: "wait SECONDS", "type TEXT" (as above), "key CODES", "shot LABEL"
(Main's screenshot, saved as <name>_<LABEL>.png). tools/mister_test.py --menu writes them for its tests, so a test
picked from the MiSTer menu types its own keys while watch is running.

The daemon creates one uinput keyboard ("mister-keys") and types what is written to the FIFO /tmp/mister_keys,
one line of codes at a time, so Main sees a single keyboard for the whole session. Examples:
  ssh root@mister "python3 /media/fat/tools/mister_keys.py type 'LOAD\\n'"
  ssh root@mister "python3 /media/fat/tools/mister_keys.py key 88"       # F12: OSD menu
Copy with: scp tools/mister_keys.py root@mister:/media/fat/tools/
"""
import fcntl, os, signal, struct, subprocess, sys, time

FIFO = '/tmp/mister_keys'
PIDFILE = '/tmp/mister_keys.pid'
WATCH_PID = '/tmp/mister_keys_watch.pid'
STEPS_DIR = '/media/fat/tools/autotype'
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE = 0x40045564, 0x40045565, 0x5501
EV_SYN, EV_KEY, SYN_REPORT, KEY_LEFTSHIFT = 0, 1, 0, 42
PRESS, GAP = 0.12, 0.08          # seconds a key is held (the MZ-1500 IPL debounce misses 60 ms presses), and between keys

# US layout: character -> key code (negative: with SHIFT).
CHARS = {'\n': 28, '\t': 15, ' ': 57, '-': 12, '=': 13, '[': 26, ']': 27, '\\': 43, ';': 39, "'": 40, '`': 41,
         ',': 51, '.': 52, '/': 53, '_': -12, '+': -13, '{': -26, '}': -27, '|': -43, ':': -39, '"': -40,
         '~': -41, '<': -51, '>': -52, '?': -53, '!': -2, '@': -3, '#': -4, '$': -5, '%': -6, '^': -7, '&': -8,
         '*': -9, '(': -10, ')': -11}
CHARS.update({c: k for c, k in zip('1234567890', range(2, 12))})
for row, start in (('qwertyuiop', 16), ('asdfghjkl', 30), ('zxcvbnm', 44)):
    for i, c in enumerate(row):
        CHARS[c] = start + i
        CHARS[c.upper()] = -(start + i)
NAMED = {'ESC': 1, 'BS': 14, 'TAB': 15, 'ENTER': 28, 'RETURN': 28, 'CTRL': 29, 'SHIFT': 42, 'ALT': 56, 'SPACE': 57,
         'CAPS': 58, 'F1': 59, 'F2': 60, 'F3': 61, 'F4': 62, 'F5': 63, 'F6': 64, 'F7': 65, 'F8': 66, 'F9': 67,
         'F10': 68, 'F11': 87, 'F12': 88, 'HOME': 102, 'UP': 103, 'PGUP': 104, 'LEFT': 105, 'RIGHT': 106,
         'END': 107, 'DOWN': 108, 'PGDN': 109, 'INS': 110, 'DEL': 111, 'BREAK': 119, 'PAUSE': 119}


def open_kbd():
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for k in range(1, 249):
        fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    # struct uinput_user_dev: name[80], input_id (bustype, vendor, product, version), ff_effects_max, 4 x abs[64]
    os.write(fd, struct.pack('80sHHHHi', b'mister-keys', 0x03, 0x1209, 0x4d4b, 1, 0) + b'\0' * (4 * 64 * 4))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(1.0)               # let Main pick up the new device
    return fd


def emit(fd, typ, code, val):
    t = time.time()
    os.write(fd, struct.pack('llHHi', int(t), int((t % 1) * 1e6), typ, code, val))


def press(fd, code, down):
    emit(fd, EV_KEY, code, 1 if down else 0)
    emit(fd, EV_SYN, SYN_REPORT, 0)


def tap(fd, code):
    shift, code = code < 0, abs(code)
    if shift:
        press(fd, KEY_LEFTSHIFT, True)
        time.sleep(0.02)
    press(fd, code, True)
    time.sleep(PRESS)
    press(fd, code, False)
    if shift:
        time.sleep(0.02)
        press(fd, KEY_LEFTSHIFT, False)
    time.sleep(GAP)


def serve(path):
    if not os.path.exists(path):
        os.mkfifo(path)
    with open(PIDFILE, 'w') as f:
        f.write(str(os.getpid()))
    fd = open_kbd()
    while True:
        with open(path) as f:
            for line in f:
                for item in line.split():
                    if item.startswith('w'):
                        time.sleep(int(item[1:]) / 1000)
                    elif '+' in item:                     # chord: press all, hold, release (29+56+100 = MiSTer reset)
                        codes = [int(c) for c in item.split('+')]
                        for c in codes:
                            press(fd, c, True)
                            time.sleep(0.03)
                        time.sleep(0.3)
                        for c in reversed(codes):
                            press(fd, c, False)
                        time.sleep(GAP)
                    else:
                        tap(fd, int(item))


def run_steps(name, path):
    log = open('/tmp/mister_keys_watch.log', 'a')
    log.write(f'{time.ctime()}: {name}\n')
    log.flush()
    for line in open(path):
        op, _, arg = line.rstrip('\n').partition(' ')
        if op == 'wait':
            time.sleep(float(arg))
        elif op == 'type':
            send(text_codes(arg))
            time.sleep(0.15 * len(arg) + 0.3)
        elif op == 'key':
            send(arg.split())
            time.sleep(0.15 * len(arg.split()) + 0.3)
        elif op == 'shot':
            with open('/dev/MiSTer_cmd', 'w') as f:
                f.write(f'screenshot {name}_{arg}.png\n')
            time.sleep(1.5)
    log.write(f'{time.ctime()}: {name} done\n')


def watch(d):
    with open(WATCH_PID, 'w') as f:
        f.write(str(os.getpid()))
    last = None
    while True:
        try:
            st = os.stat('/tmp/CORENAME')
            cur = (open('/tmp/CORENAME').read().strip(), st.st_mtime)
        except OSError:
            cur = None
        if cur and cur != last:
            last = cur
            path = os.path.join(d, cur[0] + '.steps')
            if os.path.exists(path):
                try:
                    run_steps(cur[0], path)
                except Exception as e:                       # keep watching
                    open('/tmp/mister_keys_watch.log', 'a').write(f'{cur[0]}: {e}\n')
                try:                                         # a step that reloads the same core doesn't retrigger it;
                    st = os.stat('/tmp/CORENAME')                # another test loaded meanwhile still runs
                    now = (open('/tmp/CORENAME').read().strip(), st.st_mtime)
                    if now[0] == cur[0]:
                        last = now
                except OSError:
                    pass
        time.sleep(0.5)


def bg_pid(pidfile):
    try:
        pid = int(open(pidfile).read())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return 0


# Virtual gamepad: an Xbox 360 controller (045e:028e) for Main's gamecontrollerdb mapping. D-pad as hat axes, A/B/X/Y,
# start, select. The daemon behind 'joy' keeps the device so Main sees one pad for the session.
JOY_FIFO = '/tmp/mister_joy'
JOY_PID = '/tmp/mister_joy.pid'
EV_ABS, ABS_HAT0X, ABS_HAT0Y = 3, 0x10, 0x11
UI_SET_ABSBIT = 0x40045567
JOY_BTN = {'a': 304, 'b': 305, 'x': 307, 'y': 308, 'select': 314, 'start': 315}


def open_joy():
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
    for b in JOY_BTN.values():
        fcntl.ioctl(fd, UI_SET_KEYBIT, b)
    for ax in (ABS_HAT0X, ABS_HAT0Y):
        fcntl.ioctl(fd, UI_SET_ABSBIT, ax)
    absmax, absmin = [0] * 64, [0] * 64
    for ax in (ABS_HAT0X, ABS_HAT0Y):
        absmax[ax], absmin[ax] = 1, -1
    os.write(fd, struct.pack('80sHHHHi', b'Microsoft X-Box 360 pad', 0x03, 0x045e, 0x028e, 0x0114, 0) +
             struct.pack('64i', *absmax) + struct.pack('64i', *absmin) + struct.pack('64i', *[0] * 64) +
             struct.pack('64i', *[0] * 64))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(1.0)
    return fd


def joy_serve(path):
    if not os.path.exists(path):
        os.mkfifo(path)
    with open(JOY_PID, 'w') as f:
        f.write(str(os.getpid()))
    fd = open_joy()
    held = set()
    while True:
        with open(path) as f:
            for line in f:
                want = set(line.split())
                for b, code in JOY_BTN.items():
                    if (b in want) != (b in held):
                        emit(fd, EV_KEY, code, 1 if b in want else 0)
                hx = (1 if 'right' in want else 0) - (1 if 'left' in want else 0)
                hy = (1 if 'down' in want else 0) - (1 if 'up' in want else 0)
                emit(fd, EV_ABS, ABS_HAT0X, hx)
                emit(fd, EV_ABS, ABS_HAT0Y, hy)
                emit(fd, EV_SYN, SYN_REPORT, 0)
                held = want


def joy_send(states):
    if not bg_pid(JOY_PID):
        subprocess.Popen([sys.executable, os.path.abspath(__file__), 'joy-serve'], stdout=subprocess.DEVNULL,
                         stderr=open('/tmp/mister_joy.log', 'w'), start_new_session=True)
        for _ in range(30):
            if bg_pid(JOY_PID) and os.path.exists(JOY_FIFO):
                time.sleep(1.5)
                break
            time.sleep(0.1)
    with open(JOY_FIFO, 'w') as f:
        f.write(' '.join(states) + '\n')


def running():
    try:
        pid = int(open(PIDFILE).read())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return 0


def start():
    if running():
        return
    subprocess.Popen([sys.executable, os.path.abspath(__file__), 'serve', FIFO], stdout=subprocess.DEVNULL,
                     stderr=open('/tmp/mister_keys.log', 'w'), start_new_session=True)
    for _ in range(30):
        if running() and os.path.exists(FIFO):
            time.sleep(1.2)       # device creation
            return
        time.sleep(0.1)
    sys.exit('mister_keys: daemon did not start (see /tmp/mister_keys.log)')


def send(items):
    start()
    with open(FIFO, 'w') as f:
        f.write(' '.join(items) + '\n')


def text_codes(text):
    out, i = [], 0
    text = text.replace('\\n', '\n')
    while i < len(text):
        if text[i] == '{' and '}' in text[i:]:
            j = text.index('}', i)
            out.append(str(NAMED[text[i + 1:j].upper()]))
            i = j + 1
            continue
        out.append(str(CHARS[text[i]]))
        i += 1
    return out


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == 'serve':
        serve(a[1] if len(a) > 1 else FIFO)
    elif a[0] == 'start':
        start()
    elif a[0] == 'stop':
        pid = running()
        if pid:
            os.kill(pid, signal.SIGTERM)
    elif a[0] == 'status':
        print('keys: ' + ('running' if running() else 'stopped') + ', watch: ' + ('running' if bg_pid(WATCH_PID) else 'stopped'))
    elif a[0] == 'watch':
        watch(a[1] if len(a) > 1 else STEPS_DIR)
    elif a[0] == 'watch-start':
        if not bg_pid(WATCH_PID):
            start()
            subprocess.Popen([sys.executable, os.path.abspath(__file__), 'watch'] + a[1:2], stdout=subprocess.DEVNULL,
                             stderr=open('/tmp/mister_keys_watch.err', 'w'), start_new_session=True)
    elif a[0] == 'watch-stop':
        pid = bg_pid(WATCH_PID)
        if pid:
            os.kill(pid, signal.SIGTERM)
    elif a[0] == 'joy':
        joy_send(a[1:])
    elif a[0] == 'joy-serve':
        joy_serve(JOY_FIFO)
    elif a[0] == 'type':
        send(text_codes(' '.join(a[1:])))
    elif a[0] == 'key':
        send(a[1:])
    else:
        sys.exit(__doc__)
