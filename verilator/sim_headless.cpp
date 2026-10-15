// Headless SharpMZ simulation: boot, type, load tapes, capture frames.
//
// The command line follows refs/mz800emu's headless CLI (HEADLESS_CLI.md) so a
// run on the core and on the reference emulator can be compared directly:
//
//   ./obj_dir_headless/Vtop --model mz700 --stop-at-frame 150 --ascii-end
//   ./obj_dir_headless/Vtop --mzf ../rtl/software/mzf/ramtest.mzf --type '100:L\n' \
//       --stop-at-frame 900 --screenshot 900 --frame-log out/frames.csv
//
// Run from this directory: the RAM init files are ./software/mif/*.hex.

#include "Vtop.h"
#include "verilated.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "ps2_keys.h"
#include "sharp_vcode.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <deque>
#include <map>
#include <fstream>
#include <memory>
#include <set>
#include <string>
#include <sys/stat.h>
#include <vector>

#ifndef SIM_CLK_DIV
#define SIM_CLK_DIV 1
#endif
static const double CLK_HZ = 70937600.0 / SIM_CLK_DIV;      // clk_sys; `make fast` builds at half rate

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------
struct MemDump { uint32_t addr, len; std::string path; };
struct TypeCmd { uint32_t frame; std::string text; };

struct Options {
    std::string model = "mz700";
    std::string vmode = "native";
    bool mz800_700 = true;
    int      turbo = 0;
    int      fast_tape = 1;           // Menu step 1 = off (real speed), as the reference emulator runs.
    uint32_t stop_frame = 0;
    bool     stop_set = false;
    std::string mzf;
    bool     mzf_direct = false;
    uint32_t mzf_direct_frame = 0;
    uint32_t mzf_frame = 0;                  // --mzf-frame N: Load Tape to CMT at frame N (as an MGL does, after boot)
    std::vector<TypeCmd> types;
    uint32_t type_press = 3, type_release = 3;
    uint32_t shift_lead = 0;                 // --shift-lead N: a shifted character presses SHIFT N frames before its key
    bool     tape_direct = false;            // --tape-direct: OSD Tape Image Start: Direct
    bool     tape_msgs = false;              // --tape-msgs: OSD Tape Messages: On (the core's default; off here for the tests)
    bool     key_sharp = true;               // --key-layout pc|sharp (the core's default is PC; the tests type by position)
    std::set<uint32_t> screenshots;
    bool     dump_range = false;
    uint32_t dump_from = 0, dump_to = 0, dump_every = 0;
    std::string out_dir = "out";
    std::string frame_log;
    bool     ascii_end = false;
    std::string vram_dump;                   // --vram-dump FILE: raw video RAM (4 KB) at exit
    int      ascii_cols = 40;
    std::vector<MemDump> memdumps;
    std::string printer;                     // --printer FILE: bytes the printer port sends out of the UART
    uint32_t    printer_baud = 9600;
    bool        printer_ascii = false;       // --printer-ascii: OSD Printer Charset: ASCII
    std::map<uint32_t, std::string> qd_swaps;   // frame -> Quick Disk image to mount then (side B etc.)
    std::string trace_file;
    std::string wav_file;
    std::string wav_out_file;
    bool        trace_cxxx = false;                // --wav-out: the core's final stereo output (sharpmz_top audio_l/r)
    std::string io_file;
    uint32_t trace_from = 0, trace_to = UINT32_MAX;
    bool     quiet = false;
    bool     verbose = false;
    std::string tape_image;
    std::string fdd;
    uint32_t    fdd_frame = 0;
    std::vector<std::string> osd;            // --osd "Name=Value, ...": OSD options by name (SharpMZ.sv CONF_STR)
    bool        osd_list = false;            // --osd-list: print the OSD options and their values, then exit
    std::string conf_str_file = "../SharpMZ.sv";
    bool        boot_reset = false;          // --boot-reset: OSD MZ-80B/2000 Boot Reset (a reset goes back to the IPL)               // --fdd-frame N: mount --fdd at frame N (after the boot), as from the OSD
    std::string qd;
    bool        qd_readonly = false;
    bool        ramdisk = false;
    uint32_t    joy0 = 0;                // joystick 1, MiSTer bits (5 fire 2, 4 fire 1, 3 up, 2 down, 1 left, 0 right)
    std::set<uint32_t> warm_resets;
    std::map<uint32_t, int> fast_tape_at;   // --fast-tape-at FRAME:STEP
    std::multimap<uint32_t, std::pair<std::string, uint32_t>> rom_loads;   // --load-rom FRAME:FILE[@ADDR]
    bool        fdd_readonly = false;
    std::string fdd_b;                       // --fdd-b: drive B image
    bool        fdd_b_hd = false;
    bool        direct_start = false;        // --direct-start: Load Direct starts the program (OSD default)            // --fdd-b-hd: drive B is unit 2 (OSD Drive B Unit: 3rd)
    int         fdc_mode = 0;
    bool     tape_readonly = false;
    std::set<uint32_t> tape_rewinds;
};

static void usage()
{
    fprintf(stderr,
"SharpMZ core simulation (headless)\n"
"\n"
"Machine and run:\n"
"  --model M              mz80k|mz80c|mz1200|mz80a|mz700|mz800|mz80b|mz2000 (default mz700)\n"
"  --vmode native|vga60   video timing (default native)\n"
"  --mz800-mode 700|800   MZ-800 rear mode switch (default 700, as mz800emu)\n"
"  --turbo N              CPU speed menu step 0..7 (default 0 = machine speed)\n"
"  --fast-tape N          tape speed menu step 0..7 (default 1 = off, real speed)\n"
"  --stop-at-frame N      exit after frame N (frames count vsyncs from reset)\n"
"  --quiet                no progress on stderr\n"
"  --verbose              also print internal state every 10M clocks\n"
"Tapes:\n"
"  --mzf FILE             put an MZF in the tape buffer (Load Tape to CMT)\n"
"  --mzf-direct           load it straight to RAM instead (Load Direct to RAM)\n"
"  --mzf-direct-frame N   frame to do the direct load at (default 0)\n"
"  --mzf-frame N          frame for Load Tape to CMT (default 0, before the boot)\n"
"  --direct-start         after a direct load, boot, restore 10F0-11FF and jump to the exec address\n"
"                         (OSD Load Direct: Start Program; off here so the tests that type J still work)\n"
"Tape image (the OSD Tape Image slot):\n"
"  --tape-image FILE      mount an MZT/MZF image; saves are written back into it\n"
"  --warm-reset N        OSD Reset (warm reset) at frame N (repeatable)\n"
"  --fast-tape-at F:N     change the Fast Tape step to N at frame F (repeatable)\n"
"  --load-rom F:FILE[@A]  OSD Load System ROM at frame F: FILE to system ROM offset A (hex, default 0 =\n"
"                         MZ-80K 40-column monitor); no reset, add --warm-reset (repeatable)\n"
"  --ramdisk              MZ-800 64 KB RAM disk board (OSD MZ-800 RAM Disk)\n"
"  --joy0 BITS            joystick 1 held all run (MiSTer bits: 0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2)\n"
"  --qd FILE              Quick Disk image (.mzq or .qdf; MZ-1500, MZ-800), written back; --qd-readonly\n"
"  --osd \"NAME=VALUE, ...\"  set OSD options by their names and values in SharpMZ.sv (e.g. \"Model=MZ-80B,\n"
"                         Fast Tape=Off\"); repeatable; applied after the options below. --osd-list lists them\n"
"  --boot-reset           OSD MZ-80B/2000 Boot Reset: a reset goes back to the IPL\n"
"  --fdd-frame N          mount the --fdd image at frame N instead of at the start (as from the OSD, later)\n"
"  --qd-swap FRAME:FILE   mount another Quick Disk image at FRAME (side B); repeatable\n"
"  --printer FILE         printer connected (OSD Printer: UART); the UART line is decoded into FILE\n"
"  --printer-baud N       UART speed (default 9600)\n"
"  --printer-ascii        OSD Printer Charset: ASCII (Sharp codes converted, CR followed by LF)\n"
"  --fdd FILE             Extended DSK image in floppy drive A (MZ-700/800); --fdd-readonly\n"
"  --fdd-b FILE           image in floppy drive B; --fdd-b-hd makes it unit 2 (CP/M 4.1 HD drive C:)\n"
"  --fdc-mode auto|on|off  floppy interface (default auto: present while a disk is mounted)\n"
"  --tape-readonly        mount it read-only\n"
"  --tape-rewind N        pulse Rewind Tape Image at frame N (repeatable)\n"
"Typing:\n"
"  --type FRAME:TEXT      type TEXT from FRAME; \\n or {RETURN}, {BREAK}, {DEL}, {INS},\n"
"                         {HOME}, {CLR}, {UP}, {DOWN}, {LEFT}, {RIGHT}, {WAIT n}\n"
"  --type-rate P:R        frames per key press:release (default 3:3)\n"
"Images and logs:\n"
"  --screenshot N         PNG of frame N (repeatable)\n"
"  --tape-msgs            OSD Tape Messages: On (the tape position over the picture; off in the sim by default)\n"
"  --tape-direct          OSD Tape Image Start: Direct (the tape image's first record to RAM and started)\n"
"  --key-layout pc|sharp  OSD Keyboard Layout (default sharp, by position; the core defaults to pc)\n"
"  --shift-lead N         --type presses SHIFT N frames before a shifted character's key (default 0)\n"
"  --dump-frames A:B      PNG of every frame A..B\n"
"  --dump-every K         PNG of every Kth frame\n"
"  --out DIR              output directory (default ./out)\n"
"  --frame-log FILE       frame,fb_hash,cpu_cycles,pc per frame\n"
"  --ascii-end            print the text screen (display codes -> ASCII) at exit\n"
"  --vram-dump FILE       write the raw video RAM (4 KB) at exit\n"
"  --ascii-cols 40|80     text width for --ascii-end (default 40)\n"
"  --dump-mem A:L:FILE    write main RAM A..A+L-1 at exit (physical RAM, not the\n"
"                         CPU's banked view; A and L in hex, e.g. 1200:100:ram.bin)\n"
"  --trace-cpu FILE       PC of each instruction fetch\n"
"  --trace-io FILE        each I/O write: frame,pc,port,data,MZ-800 DMD\n"
"  --wav FILE             audio at 48 kHz, 16-bit mono (sound/tape bit + MZ-800 PSG, as SharpMZ.sv)\n"
"  --wav-out FILE         the core's final audio output (sharpmz_top audio_l/r), 48 kHz 16-bit stereo\n"
"  --trace-from N         start tracing at frame N; --trace-to N stops after frame N\n"
"\n"
"fb_hash is FNV-1a 32 over the RGB888 bytes of the active (unblanked) picture,\n"
"the same bytes written to the PNG. cpu_cycles counts CPU clock enables (T-states).\n"
"Exit codes: 0 ok, 2 bad arguments or files, 3 runtime failure.\n");
}

static uint32_t parse_num(const std::string &s)
{
    return (uint32_t)strtoul(s.c_str(), nullptr, 0);
}

static bool parse_args(int argc, char **argv, Options &o)
{
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&](void) -> std::string {
            if (i + 1 >= argc) { fprintf(stderr, "%s needs a value\n", a.c_str()); exit(2); }
            return argv[++i];
        };
        if (a == "--help" || a == "-h") { usage(); exit(0); }
        else if (a == "--headless") {}
        else if (a == "--model") o.model = next();
        else if (a == "--vmode") o.vmode = next();
        else if (a == "--mz800-mode") o.mz800_700 = next() == "700";
        else if (a == "--turbo") o.turbo = (int)parse_num(next());
        else if (a == "--fast-tape") o.fast_tape = (int)parse_num(next());
        else if (a == "--load-rom") {
            std::string v = next(); size_t c = v.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--load-rom wants FRAME:FILE[@ADDR]\n"); exit(2); }
            std::string f = v.substr(c + 1); uint32_t addr = 0; size_t at = f.rfind('@');
            if (at != std::string::npos) { addr = (uint32_t)std::stoul(f.substr(at + 1), nullptr, 16); f = f.substr(0, at); }
            o.rom_loads.insert({(uint32_t)std::stoul(v.substr(0, c)), {f, addr}});
        }
        else if (a == "--fast-tape-at") {
            std::string v = next(); size_t c = v.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--fast-tape-at wants FRAME:STEP\n"); exit(2); }
            o.fast_tape_at[(uint32_t)std::stoul(v.substr(0, c))] = std::stoi(v.substr(c + 1));
        }
        else if (a == "--stop-at-frame") { o.stop_frame = parse_num(next()); o.stop_set = true; }
        else if (a == "--quiet") o.quiet = true;
        else if (a == "--verbose") o.verbose = true;
        else if (a == "--mzf") o.mzf = next();
        else if (a == "--mzf-direct") o.mzf_direct = true;
        else if (a == "--mzf-direct-frame") o.mzf_direct_frame = parse_num(next());
        else if (a == "--mzf-frame") o.mzf_frame = parse_num(next());
        else if (a == "--run-mzf") { o.mzf = next(); o.mzf_direct = true; }
        else if (a == "--type") {
            std::string v = next();
            size_t c = v.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--type wants FRAME:TEXT\n"); return false; }
            o.types.push_back({parse_num(v.substr(0, c)), v.substr(c + 1)});
        }
        else if (a == "--type-rate") {
            std::string v = next();
            size_t c = v.find(':');
            o.type_press = parse_num(v.substr(0, c));
            o.type_release = c == std::string::npos ? o.type_press : parse_num(v.substr(c + 1));
        }
        else if (a == "--screenshot") o.screenshots.insert(parse_num(next()));
        else if (a == "--shift-lead") o.shift_lead = parse_num(next());
        else if (a == "--key-layout") o.key_sharp = next() != "pc";
        else if (a == "--tape-direct") o.tape_direct = true;
        else if (a == "--tape-msgs") o.tape_msgs = true;
        else if (a == "--dump-frames") {
            std::string v = next();
            size_t c = v.find(':');
            o.dump_range = true;
            o.dump_from = parse_num(v.substr(0, c));
            o.dump_to = c == std::string::npos ? o.dump_from : parse_num(v.substr(c + 1));
        }
        else if (a == "--dump-every") o.dump_every = parse_num(next());
        else if (a == "--out") o.out_dir = next();
        else if (a == "--frame-log") o.frame_log = next();
        else if (a == "--ascii-end") o.ascii_end = true;
        else if (a == "--vram-dump") o.vram_dump = next();
        else if (a == "--ascii-cols") o.ascii_cols = (int)parse_num(next());
        else if (a == "--dump-mem") {
            std::string v = next();
            size_t c1 = v.find(':'), c2 = v.find(':', c1 + 1);
            if (c1 == std::string::npos || c2 == std::string::npos) { fprintf(stderr, "--dump-mem wants ADDR:LEN:FILE\n"); return false; }
            // Hex, as memory addresses are written everywhere else ("1200" is 0x1200, not 1200 decimal).
            auto hex = [](const std::string &t) { return (uint32_t)strtoul(t.c_str(), nullptr, 16); };
            o.memdumps.push_back({hex(v.substr(0, c1)), hex(v.substr(c1 + 1, c2 - c1 - 1)), v.substr(c2 + 1)});
        }
        else if (a == "--tape-image") o.tape_image = next();
        else if (a == "--fdd") o.fdd = next();
        else if (a == "--fdd-frame") o.fdd_frame = parse_num(next());
        else if (a == "--boot-reset") o.boot_reset = true;
        else if (a == "--osd") o.osd.push_back(next());
        else if (a == "--osd-list") o.osd_list = true;
        else if (a == "--conf-str") o.conf_str_file = next();
        else if (a == "--qd") o.qd = next();
        else if (a == "--qd-readonly") o.qd_readonly = true;
        else if (a == "--printer") o.printer = next();
        else if (a == "--printer-baud") o.printer_baud = parse_num(next());
        else if (a == "--printer-ascii") o.printer_ascii = true;
        else if (a == "--qd-swap") {
            std::string v = next();
            size_t c = v.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--qd-swap wants FRAME:FILE\n"); return false; }
            o.qd_swaps[parse_num(v.substr(0, c))] = v.substr(c + 1);
        }
        else if (a == "--ramdisk") o.ramdisk = true;
        else if (a == "--joy0") o.joy0 = parse_num(next());
        else if (a == "--warm-reset") o.warm_resets.insert((uint32_t)std::stoul(next()));
        else if (a == "--fdd-readonly") o.fdd_readonly = true;
        else if (a == "--fdd-b") o.fdd_b = next();
        else if (a == "--fdd-b-hd") o.fdd_b_hd = true;
        else if (a == "--direct-start") o.direct_start = true;
        else if (a == "--fdc-mode") { std::string m = next(); o.fdc_mode = m == "on" ? 1 : m == "off" ? 2 : 0; }
        else if (a == "--tape-readonly") o.tape_readonly = true;
        else if (a == "--tape-rewind") o.tape_rewinds.insert(parse_num(next()));
        else if (a == "--trace-cpu") o.trace_file = next();
        else if (a == "--wav") o.wav_file = next();
        else if (a == "--wav-out") o.wav_out_file = next();
        else if (a == "--trace-io") o.io_file = next();
        else if (a == "--trace-cxxx") o.trace_cxxx = true;
        else if (a == "--trace-from") o.trace_from = parse_num(next());
        else if (a == "--trace-to") o.trace_to = parse_num(next());
        else { fprintf(stderr, "unknown option %s (try --help)\n", a.c_str()); return false; }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Machine configuration, as SharpMZ.sv derives it from the OSD status bits.
// ---------------------------------------------------------------------------
struct ModelInfo { const char *name; uint8_t code; uint8_t display; uint8_t mz1500; };
static const ModelInfo MODELS[] = {
    {"mz80k", 0, 0, 0}, {"mz80c", 1, 0, 0}, {"mz1200", 2, 0, 0}, {"mz80a", 3, 0, 0},
    {"mz700", 4, 2, 0}, {"mz800", 5, 2, 0}, {"mz80b", 6, 1, 0}, {"mz2000", 7, 1, 0},
    {"mz1500", 4, 2, 1},                                    // an MZ-700 plus the MZ-1500 flag (display3 bit 3)
};

// ---------------------------------------------------------------------------
// OSD options: decoded from SharpMZ.sv's CONF_STR, so --osd NAME=VALUE sets the same status bits Main does.
// ---------------------------------------------------------------------------
struct OsdOption { std::string name; int lo, width; std::vector<std::string> values; };

static std::string lower_trim(std::string s)
{
    size_t a = s.find_first_not_of(" \t"), b = s.find_last_not_of(" \t");
    s = a == std::string::npos ? "" : s.substr(a, b - a + 1);
    for (auto &c : s) c = (char)tolower((unsigned char)c);
    return s;
}

// Entries like "P2O[23:21],Fast Tape,Fastest,Off,2x,4x,8x,16x;" or "O[122:121],Aspect ratio,...".
static std::vector<OsdOption> read_osd_options(const std::string &path)
{
    std::vector<OsdOption> out;
    std::ifstream f(path);
    std::string line;
    while (std::getline(f, line)) {
        size_t q = line.find('"');
        if (q == std::string::npos) continue;
        size_t e = line.find(';', q);
        if (e == std::string::npos) continue;
        std::string ent = line.substr(q + 1, e - q - 1);
        size_t i = 0;
        if (ent.size() > 1 && ent[0] == 'P' && isdigit((unsigned char)ent[1])) i = 2;
        if (ent.compare(i, 2, "O[") != 0) continue;
        size_t rb = ent.find(']', i);
        std::string range = ent.substr(i + 2, rb - i - 2);
        int hi, lo;
        size_t colon = range.find(':');
        if (colon == std::string::npos) hi = lo = atoi(range.c_str());
        else { hi = atoi(range.substr(0, colon).c_str()); lo = atoi(range.substr(colon + 1).c_str()); }
        std::vector<std::string> parts;
        std::string rest = ent.substr(rb + 2), cur;
        for (char c : rest) { if (c == ',') { parts.push_back(cur); cur.clear(); } else cur += c; }
        parts.push_back(cur);
        if (parts.empty()) continue;
        OsdOption o{parts[0], lo, hi - lo + 1, {}};
        for (size_t k = 1; k < parts.size(); k++) o.values.push_back(parts[k]);
        out.push_back(o);
    }
    return out;
}

// SharpMZ.sv mz_fast_tape(): menu step -> register value.
static uint8_t fast_tape_code(int step)
{
    static const uint8_t t[8] = {5, 0, 1, 2, 3, 4, 5, 5};   // 0 Fastest, 1 Off, 2x .. 16x, 6/7 Fastest
    return t[step & 7];
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------
class Sim {
public:
    explicit Sim(const Options &o) : opt(o), top(new Vtop) {}

    int run();

private:
    const Options &opt;
    std::unique_ptr<Vtop> top;

    uint64_t cycle = 0;
    FILE    *fprn = nullptr;                 // --printer
    int      prn_state = -1, prn_byte = 0;
    uint64_t prn_next = 0;
    bool     prev_prn_rx = true;
    unsigned prn_errors = 0;
    uint64_t cpu_cycles = 0;
    uint32_t frame = 0;
    bool     prev_vs = false, prev_hb = false, prev_m1 = true;
    int      exit_code = 0;

    // Video capture for the current frame.
    std::vector<uint8_t> line, fb;
    int fb_w = 0, fb_h = 0;

    // Keyboard.
    struct Ps2Event { uint16_t code; bool ext, press; };
    std::deque<Ps2Event> ps2_queue;
    std::multimap<uint32_t, Ps2Event> ps2_schedule;   // frame -> event
    uint64_t ps2_next_ok = 0;
    bool     ps2_toggle = false;

    FILE *flog = nullptr, *ftrace = nullptr;

    // Audio capture (--wav): 48 kHz samples of AUDIO_L as SharpMZ.sv mixes it.
    FILE    *fwav = nullptr;
    FILE    *fwav2 = nullptr;                // --wav-out
    uint64_t wav2_acc = 0, wav2_samples = 0;
    FILE    *fio = nullptr;
    bool     prev_io_wr = false;
    uint64_t wav_acc = 0, wav_samples = 0;
    void wav_header();
    void wav_out_header();

    // Tape image slot, emulating Main_MiSTer's side of hps_io's sd_* handshake.
    // Image slots: 0 = tape (S0), 1 = floppy drive A (S1). The buffer bus is shared.
    FILE    *img = nullptr;
    uint64_t img_size = 0;
    FILE    *fdd = nullptr;
    uint64_t fdd_size = 0;
    FILE    *fdd2 = nullptr;                 // --fdd-b: floppy drive B
    uint64_t fdd2_size = 0;
    void mount_fdd2();
    FILE    *qd = nullptr;
    uint64_t qd_size = 0;
    void mount_qd();
    std::string qd_path;                         // the Quick Disk image mounted now (opt.qd, then --qd-swap)
    int      sd_slot = 0;
    void mount_fdd();
    uint32_t status_bits[4] = {0, 0, 0, 0};      // the OSD status word, as Main sets it
    void set_status(int lo, int width, uint32_t v);
    void apply_status();
    bool apply_osd(const std::string &assignments);
    enum { SD_IDLE, SD_READ, SD_READ_END, SD_WRITE } sd_state = SD_IDLE;
    int      sd_idx = 0;
    uint32_t sd_cur_lba = 0;
    uint8_t  sd_data[512];
    uint32_t tape_rewind_frames = 0;
    uint16_t cmt_last = 0xFFFF;
    void sd_step();
    void mount_tape();

    void clock();
    void on_frame_end();
    void write_config();
    void ioctl_write(uint32_t addr, uint8_t data);
    bool load_mzf(bool direct);
    void load_rom(const std::string &path, uint32_t addr);
    void schedule_typing();
    void print_ascii();
    void dump_memory();
    bool want_png(uint32_t f) const;
    void write_png(uint32_t f);
};

void Sim::sd_step()
{
    // Slot accessors: the tape (S0) and floppy drive A (S1) share sd_buff_*.
    // Slot 2 is the Quick Disk (S3).
    // Slot 3 is floppy drive B (S2).
    auto req_rd = [&](int k) -> bool { return k == 3 ? top->fdd2_rd : k == 2 ? top->qd_rd : k ? top->fdd_rd : top->sd_rd; };
    auto req_wr = [&](int k) -> bool { return k == 3 ? top->fdd2_wr : k == 2 ? top->qd_wr : k ? top->fdd_wr : top->sd_wr; };
    auto lba    = [&](int k) -> uint32_t { return k == 3 ? top->fdd2_lba : k == 2 ? top->qd_lba : k ? top->fdd_lba : top->sd_lba; };
    auto ack    = [&](int k, int v) { if (k == 3) top->fdd2_ack = v; else if (k == 2) top->qd_ack = v; else if (k) top->fdd_ack = v; else top->sd_ack = v; };
    auto file   = [&](int k) -> FILE * { return k == 3 ? fdd2 : k == 2 ? qd : k ? fdd : img; };
    auto size   = [&](int k) -> uint64_t { return k == 3 ? fdd2_size : k == 2 ? qd_size : k ? fdd_size : img_size; };

    top->sd_buff_wr = 0;
    switch (sd_state) {
    case SD_IDLE:
        for (int k = 0; k < 4; k++) {
            if (!file(k) || !(req_rd(k) || req_wr(k))) continue;
            sd_slot = k;
            sd_cur_lba = lba(k);
            sd_idx = 0;
            ack(k, 1);
            if (req_rd(k)) {
                memset(sd_data, 0, sizeof(sd_data));
                uint64_t off = (uint64_t)sd_cur_lba * 512;
                if (off < size(k)) {
                    fseeko(file(k), (off_t)off, SEEK_SET);
                    fread(sd_data, 1, (size_t)std::min<uint64_t>(512, size(k) - off), file(k));
                }
                sd_state = SD_READ;
            } else {
                sd_state = SD_WRITE;
            }
            break;
        }
        break;
    case SD_READ:
        top->sd_buff_addr = sd_idx;
        top->sd_buff_dout = sd_data[sd_idx];
        top->sd_buff_wr = 1;
        if (++sd_idx == 512) sd_state = SD_READ_END;
        break;
    case SD_READ_END:
        ack(sd_slot, 0);
        sd_state = SD_IDLE;
        break;
    case SD_WRITE:
        // sd_buff_din is registered: it holds the byte addressed on the previous clock.
        if (sd_idx > 0) sd_data[sd_idx - 1] = sd_slot == 3 ? top->fdd2_buff_din : sd_slot == 2 ? top->qd_buff_din : sd_slot ? top->fdd_buff_din : top->sd_buff_din;
        if (sd_idx < 512) {
            top->sd_buff_addr = sd_idx++;
        } else {
            // Like Main, never grow the image: write only what fits.
            uint64_t off = (uint64_t)sd_cur_lba * 512;
            if (off < size(sd_slot)) {
                fseeko(file(sd_slot), (off_t)off, SEEK_SET);
                fwrite(sd_data, 1, (size_t)std::min<uint64_t>(512, size(sd_slot) - off), file(sd_slot));
                fflush(file(sd_slot));
            }
            ack(sd_slot, 0);
            sd_state = SD_IDLE;
        }
        break;
    }
}

void Sim::mount_qd()
{
    if (qd_path.empty()) qd_path = opt.qd;
    qd = fopen(qd_path.c_str(), opt.qd_readonly ? "rb" : "r+b");
    if (!qd) { fprintf(stderr, "cannot open Quick Disk image %s\n", qd_path.c_str()); exit_code = 2; return; }
    fseeko(qd, 0, SEEK_END);
    qd_size = (uint64_t)ftello(qd);
    top->qd_size = qd_size;
    top->qd_readonly = opt.qd_readonly;
    top->qd_mounted = 1;
    clock();
    top->qd_mounted = 0;
    if (!opt.quiet) fprintf(stderr, "[sim] Quick Disk image '%s' mounted at frame %u, %llu bytes\n", qd_path.c_str(), frame, (unsigned long long)qd_size);
}

void Sim::mount_fdd()
{
    fdd = fopen(opt.fdd.c_str(), opt.fdd_readonly ? "rb" : "r+b");
    if (!fdd) { fprintf(stderr, "cannot open disk image %s\n", opt.fdd.c_str()); exit_code = 2; return; }
    fseeko(fdd, 0, SEEK_END);
    fdd_size = (uint64_t)ftello(fdd);
    top->fdd_size = fdd_size;
    top->fdd_readonly = opt.fdd_readonly;
    top->fdd_mounted = 1;
    clock();
    top->fdd_mounted = 0;
    if (!opt.quiet) fprintf(stderr, "[sim] disk image '%s' mounted, %llu bytes\n", opt.fdd.c_str(), (unsigned long long)fdd_size);
}

void Sim::mount_fdd2()
{
    fdd2 = fopen(opt.fdd_b.c_str(), opt.fdd_readonly ? "rb" : "r+b");
    if (!fdd2) { fprintf(stderr, "cannot open disk image %s\n", opt.fdd_b.c_str()); exit_code = 2; return; }
    fseeko(fdd2, 0, SEEK_END);
    fdd2_size = (uint64_t)ftello(fdd2);
    top->fdd_size = fdd2_size;                 // one size/readonly bus for both drives, as hps_io's img_size
    top->fdd_readonly = opt.fdd_readonly;
    top->fdd2_mounted = 1;
    clock();
    top->fdd2_mounted = 0;
    for (int i = 0; i < 4; i++) clock();      // the size is taken when the strobe falls
    top->fdd_size = fdd_size;
    if (!opt.quiet) fprintf(stderr, "[sim] drive B image '%s' mounted, %llu bytes\n", opt.fdd_b.c_str(), (unsigned long long)fdd2_size);
}

void Sim::mount_tape()
{
    img = fopen(opt.tape_image.c_str(), opt.tape_readonly ? "rb" : "r+b");
    if (!img) { fprintf(stderr, "cannot open tape image %s\n", opt.tape_image.c_str()); exit_code = 2; return; }
    fseeko(img, 0, SEEK_END);
    img_size = (uint64_t)ftello(img);
    top->img_size = img_size;
    top->img_readonly = opt.tape_readonly;
    top->img_mounted = 1;
    clock();
    top->img_mounted = 0;
    if (!opt.quiet) fprintf(stderr, "[sim] tape image '%s' mounted, %llu bytes\n", opt.tape_image.c_str(), (unsigned long long)img_size);
}

void Sim::clock()
{
    sd_step();

    // Sample what the video pipeline sees at this rising edge: MiSTer's
    // video_mixer latches RGB on the clk_sys edge where CE_PIXEL is high.
    top->clk_sys = 0;
    top->eval();
    bool ce = top->ce_pix;
    bool hb = top->VGA_HB, vb = top->VGA_VB, vs = top->VGA_VS;
    if (ce) {
        if (!hb && !vb) {
            line.push_back(top->VGA_R);
            line.push_back(top->VGA_G);
            line.push_back(top->VGA_B);
        }
        if (hb && !prev_hb && !line.empty()) {
            int w = (int)line.size() / 3;
            if (fb_h == 0) fb_w = w;
            line.resize((size_t)fb_w * 3, 0);
            fb.insert(fb.end(), line.begin(), line.end());
            fb_h++;
            line.clear();
        }
        prev_hb = hb;
    }

    top->clk_sys = 1;
    top->eval();
    cycle++;

    if (fprn) {                               // UART receiver, 8N1: sample each bit in its middle
        double bit = CLK_HZ / opt.printer_baud;
        bool rx = top->prn_txd;
        if (prn_state < 0) {
            if (prev_prn_rx && !rx) { prn_state = 0; prn_next = cycle + (uint64_t)(bit * 1.5); prn_byte = 0; }
        }
        else if (cycle >= prn_next) {
            if (prn_state < 8) { prn_byte |= (rx ? 1 : 0) << prn_state; prn_state++; prn_next += (uint64_t)bit; }
            else { if (rx) fputc(prn_byte, fprn); else prn_errors++; fflush(fprn); prn_state = -1; }
        }
        prev_prn_rx = rx;
    }

    if (top->cpu_ce) cpu_cycles++;

    if (fio) {
        bool w = top->dbg_io_wr;
        if (w && !prev_io_wr)
            fprintf(fio, "%u,%04X,%02X,%02X,%X\n", frame, top->cpu_pc, top->dbg_io_port, top->dbg_io_data, top->dbg_m8_dmd);
        prev_io_wr = w;
        // The MZ-80K/80A video registers in the E page: E010-E012 (PCG) writes, E014/E015 (invert) and E200-E2FF
        // (MZ-80A scroll) reads, as "mem" lines (frame,pc,mem,R/W,address,data).
        static bool prev_mr = false, prev_mw = false;
        bool mr = top->dbg_memrd, mw = top->dbg_memwr;
        uint16_t a = top->dbg_addr;
        if (mr && !prev_mr && ((a & 0xFF00) == 0xE200 || a == 0xE014 || a == 0xE015))
            fprintf(fio, "%u,%04X,mem,R,%04X\n", frame, top->cpu_pc, a);
        if (mw && !prev_mw && (a & 0xF000) == 0xC000 && opt.trace_cxxx)   // --trace-cxxx: C000-CFFF writes, with the MZ-800 map
            fprintf(fio, "%u,%04X,mem,W,%04X,%02X,map%d\n", frame, top->cpu_pc, a, top->dbg_wdata, top->dbg_m8map);
        if (mw && !prev_mw && a >= 0xE010 && a <= 0xE012)
            fprintf(fio, "%u,%04X,mem,W,%04X,%02X\n", frame, top->cpu_pc, a, top->dbg_wdata);
        // The keyboard (8255 at E000-E003): row selects written to E000, key data read from E001, once the read's
        // data is on the bus (a few clocks into the read).
        static int kr = 0;
        // (E000-E00F: the 8255, 8253 and E008, with any mirrors a program may use.)
        static uint16_t ka = 0;
        // I/O reads: "io,R,port,data" (the data once on the bus).
        static bool prev_ir = false; static int ir = 0; static uint8_t ip = 0;
        bool irq_rd = top->dbg_io_rd;
        if (irq_rd && !prev_ir) { ir = 8; ip = top->dbg_io_port; }
        if (ir && --ir == 0) {
            if (ip >= 0xF4 && ip <= 0xF7)        // Quick Disk: also the CPU cycle, the head position and the FIFO count
                fprintf(fio, "%u,%04X,io,R,%02X,%02X,%llu,%u,%u\n", frame, top->cpu_pc, ip, top->dbg_rdata,
                        (unsigned long long)cpu_cycles, (unsigned)top->dbg_qdpos, (unsigned)top->dbg_qdfifo);
            else
                fprintf(fio, "%u,%04X,io,R,%02X,%02X\n", frame, top->cpu_pc, ip, top->dbg_rdata);
        }
        prev_ir = irq_rd;
        static bool prev_ovr = false;                           // Quick Disk: when the SIO overrun flag is set
        if (top->dbg_qdovr && !prev_ovr)
            fprintf(fio, "%u,%04X,qd,OVERRUN,pos=%u,fifo=%u,wr3=%02X,cyc=%llu\n", frame, top->cpu_pc, (unsigned)top->dbg_qdpos,
                    (unsigned)top->dbg_qdfifo, (unsigned)top->dbg_qdwr3, (unsigned long long)cpu_cycles);
        prev_ovr = top->dbg_qdovr;
        if (mw && !prev_mw && (a & 0xFFF0) == 0xE000)
            fprintf(fio, "%u,%04X,mem,W,%04X,%02X\n", frame, top->cpu_pc, a, top->dbg_wdata);
        if (mr && !prev_mr && (a & 0xFFF0) == 0xE000) { kr = 8; ka = a; }
        if (kr && --kr == 0)
            fprintf(fio, "%u,%04X,mem,R,%04X,%02X\n", frame, top->cpu_pc, ka, top->dbg_rdata);
        prev_mr = mr; prev_mw = mw;
    }

    if (opt.verbose) {                       // MZ-800 border (sim.v: always on): frame size as hps_io video_calc measures it
        static int ovs = 0, ode = 0, calch = 0, hcnt = 0, runs = 0;
        if (top->ce_pix) {
            if (calch && top->dbg_bde) hcnt++;
            if (ode && !top->dbg_bde) calch = 0;
            if (!top->VGA_VS && !ode && top->dbg_bde) runs++;
            if (ovs && !top->VGA_VS) { if (frame >= 58 && frame <= 60) fprintf(stderr, "[vc] frame %u width %d lines %d\n", frame, hcnt, runs); hcnt = 0; runs = 0; calch = 1; }
            ovs = top->VGA_VS; ode = top->dbg_bde;
        }
    }
    if (opt.verbose) {
        static int last_mw = 0;
        if (top->dbg_memwr && !last_mw && (top->dbg_addr & 0xFFF0) == 0xE000)
            fprintf(stderr, "[mw] frame %u pc %04X addr %04X data %02X cs_e_n %d cs_e2_n %d\n", frame, top->cpu_pc,
                    top->dbg_addr, top->dbg_wdata, (top->dbg_cse >> 1) & 1, top->dbg_cse & 1);
        last_mw = top->dbg_memwr;
    }
    if (opt.verbose) {
        static int last_en = -1, toggles = 0, last_snd = 0;
        static uint32_t last_frame = 0;
        if (top->dbg_snd != last_snd) { toggles++; last_snd = top->dbg_snd; }
        if (top->dbg_snd_en != last_en || frame != last_frame) {
            if (top->dbg_snd_en != last_en || toggles || frame % 10 == 0)
                fprintf(stderr, "[snd] frame %u gate %d out0 toggles %d map %d\n", frame, top->dbg_snd_en, toggles, top->dbg_map);
            last_en = top->dbg_snd_en; last_frame = frame; toggles = 0;
        }
    }

    if (fwav2) {                             // 48 kHz stereo, signed (the core's output is unsigned around 0)
        wav2_acc += 48000;
        if (wav2_acc >= (uint64_t)CLK_HZ) {
            wav2_acc -= (uint64_t)CLK_HZ;
            int16_t lr[2] = {(int16_t)(top->AUDIO_OUT_L - 0x8000), (int16_t)(top->AUDIO_OUT_R - 0x8000)};
            fwrite(lr, 2, 2, fwav2);
            wav2_samples++;
        }
    }

    if (fwav) {
        wav_acc += 48000;
        if (wav_acc >= (uint64_t)CLK_HZ) {
            wav_acc -= (uint64_t)CLK_HZ;
            // As SharpMZ.sv: the beeper is one PSG channel's level on the MZ-800/1500, full range elsewhere.
            int beep = ((top->dbg_model & 7) == 5 || top->dbg_mz1500) ? 0x1000 : 0x4000;
            int v = (top->AUDIO_L ? beep : 0) + top->AUDIO_PSG - 0x4000;
            int16_t smp = (int16_t)v;
            fwrite(&smp, 2, 1, fwav);
            wav_samples++;
        }
    }

    if (ftrace && frame >= opt.trace_from && frame <= opt.trace_to) {
        bool m1 = top->cpu_m1_n;
        if (!m1 && prev_m1) fprintf(ftrace, "%u,%llu,%04X\n", frame, (unsigned long long)cpu_cycles, top->cpu_pc);
        prev_m1 = m1;
    }

    // Keyboard: one PS/2 event at a time, spaced like hps_io delivers them.
    if (!ps2_queue.empty() && cycle >= ps2_next_ok) {
        Ps2Event e = ps2_queue.front();
        ps2_queue.pop_front();
        ps2_toggle = !ps2_toggle;
        top->ps2_key = (uint16_t)((ps2_toggle << 10) | (e.press << 9) | (e.ext << 8) | (e.code & 0xFF));
        ps2_next_ok = cycle + (uint64_t)(CLK_HZ / 2000);   // 0.5 ms
    }

    if (vs && !prev_vs) on_frame_end();
    prev_vs = vs;

    // Tape status changes (PLAY_READY, PLAYING, RECORD_READY, RECORDING, ACTIVE, APSS).
    if (opt.verbose) {
        static uint32_t rcv_last = 0xFFFFFFFF;
        uint32_t r = top->dbg_rcv;
        // Ignore the bit-level rcv_state and done bit churn; log FSM-level changes.
        uint32_t key = r & ~(0xFu << 9) & ~2u;
        if (key != rcv_last) {
            fprintf(stderr, "[rcv] frame %u ram_state %u recseq %u%u%u type %u err %u try %u ok %u done %u ready_set %u  sums ram %04X rcv %04X\n",
                    frame, (r >> 13) & 15, (r >> 8) & 1, (r >> 7) & 1, (r >> 6) & 1, (r >> 5) & 1, (r >> 4) & 1,
                    (r >> 3) & 1, (r >> 2) & 1, (r >> 1) & 1, r & 1, top->dbg_rcv_sum >> 16, top->dbg_rcv_sum & 0xFFFF);
            rcv_last = key;
        }
    }
    if (opt.verbose) {
        static bool pc1_l = 0, rb_l = 0; static uint64_t pc1_n = 0, rb_n = 0; static uint32_t st_l = 99;
        if (top->dbg_pc1 != pc1_l) { pc1_n++; pc1_l = top->dbg_pc1; }
        // Pulse phase lengths in CPU enables, while recording.
        static uint64_t ce_at_edge = 0; static std::map<uint32_t, uint32_t> hi_hist, lo_hist;
        if (top->dbg_readbit != rb_l) {
            uint32_t len = (uint32_t)(cpu_cycles - ce_at_edge);
            if (top->cmt_status & 8) (rb_l ? hi_hist : lo_hist)[len / 50 * 50]++;
            ce_at_edge = cpu_cycles;
        }
        if (frame == opt.stop_frame && top->VGA_VS && !hi_hist.empty()) {
            fprintf(stderr, "[pulse] high phase (CPU enables, 50-wide buckets):"); for (auto &h : hi_hist) fprintf(stderr, " %u:%u", h.first, h.second);
            fprintf(stderr, "\n[pulse] low phase:"); for (auto &h : lo_hist) fprintf(stderr, " %u:%u", h.first, h.second);
            fprintf(stderr, "\n"); hi_hist.clear();
        }
        if (top->dbg_readbit != rb_l) { rb_n++; rb_l = top->dbg_readbit; }
        uint32_t st = (top->dbg_rcv >> 9) & 15;
        if (st != st_l || (frame % 10 == 0 && top->VGA_VS && !prev_vs)) {
            fprintf(stderr, "[bit] frame %u rcv_state %u  pc1 toggles %llu  readbit toggles %llu\n", frame, st,
                    (unsigned long long)pc1_n, (unsigned long long)rb_n);
            st_l = st;
        }
    }
    static uint32_t dbg_last = 0xFFFFFFFF;
    uint32_t dm = top->dbg_cmt_debug & 0x0F04E700u;   // play state, motor toggle, MZ_80C, deck inputs
    if (opt.verbose && dm != dbg_last) {
        fprintf(stderr, "[cmt] frame %u debug %08X\n", frame, dm);
        dbg_last = dm;
    }
    static uint8_t rs_last = 0xFF;
    if (opt.verbose && top->dbg_tape_rs != rs_last) {   // transmitter: header (type 0) or data (1), and its state
        fprintf(stderr, "[xmit] frame %u cpu %llu type %d state %d\n", frame, (unsigned long long)cpu_cycles,
                top->dbg_tape_rs >> 4, top->dbg_tape_rs & 15);
        rs_last = top->dbg_tape_rs;
    }
    static uint8_t ctrl_last = 0xFF;
    if (opt.verbose && top->dbg_cmt_ctrl != ctrl_last) {
        uint8_t c = top->dbg_cmt_ctrl;   // CMT_BUS_IN, mctrl_pkg.vhd
        fprintf(stderr, "[cmt] frame %u ctrl %02X readbit %d reel %d stop %d play %d seek %d dir %d eject %d wren %d\n", frame, c,
                c & 1, (c >> 1) & 1, (c >> 2) & 1, (c >> 3) & 1, (c >> 4) & 1, (c >> 5) & 1, (c >> 6) & 1, (c >> 7) & 1);
        ctrl_last = c;
    }
    uint16_t cs = top->cmt_status & 0x3E1F;
    if (opt.verbose && cs != cmt_last) {
        fprintf(stderr, "[cmt] frame %u cycle %llu status %04X%s%s%s%s%s  tape_active %d\n", frame, (unsigned long long)cycle, cs,
                cs & 1 ? " PLAY_READY" : "", cs & 2 ? " PLAYING" : "", cs & 4 ? " RECORD_READY" : "",
                cs & 8 ? " RECORDING" : "", cs & 16 ? " ACTIVE" : "", top->tape_active);
        cmt_last = cs;
    }

    if (opt.verbose && (cycle % 10000000) == 0)
        fprintf(stderr, "[sim] cycle %lluM  %.3fs emulated  frame %u  pc %04X  vs %d hb %d vb %d ce_pix %d  cpu_ce %llu sysreset %d delay %d rm %d warm %d wait_n %d vwait_n %d model %d vga %d vid %d cpu %d\n",
                (unsigned long long)(cycle / 1000000), cycle / CLK_HZ, frame, top->cpu_pc, vs, hb, vb, ce, (unsigned long long)cpu_cycles, top->dbg_sysreset, top->dbg_delay, top->dbg_rm, top->dbg_warm, top->dbg_wait_n, top->dbg_vwait_n,
                (int)(top->dbg_config[0] & 0xFF), (int)((top->dbg_config[0] >> 17) & 3), (int)(((top->dbg_config[1] >> 30) & 3) | ((top->dbg_config[2] & 1) << 2)), (int)((top->dbg_config[1] >> 26) & 15));
}

void Sim::on_frame_end()
{
    // Frame `frame` is complete.
    uint32_t h = 2166136261u;
    for (uint8_t b : fb) { h ^= b; h *= 16777619u; }
    if (flog) fprintf(flog, "%u,%08x,%llu,%04X\n", frame, h, (unsigned long long)cpu_cycles, top->cpu_pc);
    if (want_png(frame)) write_png(frame);
    if (!opt.quiet && frame % 50 == 0)
        fprintf(stderr, "[sim] frame %u  %dx%d  pc %04X  %.2fs emulated\n", frame, fb_w, fb_h, top->cpu_pc, cycle / CLK_HZ);

    fb.clear(); fb_h = 0; line.clear();
    frame++;

    auto range = ps2_schedule.equal_range(frame);
    for (auto it = range.first; it != range.second; ++it) ps2_queue.push_back(it->second);

    if (!opt.mzf.empty() && opt.mzf_direct && frame == opt.mzf_direct_frame && frame != 0) load_mzf(true);
    if (!opt.mzf.empty() && !opt.mzf_direct && frame == opt.mzf_frame && frame != 0) load_mzf(false);

    if (!opt.fdd.empty() && opt.fdd_frame != 0 && frame == opt.fdd_frame) mount_fdd();
    auto sw = opt.qd_swaps.find(frame);
    if (sw != opt.qd_swaps.end()) {
        if (qd) fclose(qd);
        qd = nullptr;
        qd_path = sw->second;
        mount_qd();
    }

    top->tape_rewind = opt.tape_rewinds.count(frame) ? 1 : 0;   // Held for one frame.
    auto rl = opt.rom_loads.equal_range(frame);
    for (auto it = rl.first; it != rl.second; ++it) load_rom(it->second.first, it->second.second);
    if (opt.fast_tape_at.count(frame))
        { set_status(21, 3, (uint32_t)opt.fast_tape_at.at(frame)); apply_status(); }     // OSD Fast Tape (menu step)
    if (opt.warm_resets.count(frame)) {          // OSD Reset: Main sets status bit 0 and clears it at once
        set_status(0, 1, 1); apply_status(); clock(); set_status(0, 1, 0); apply_status();
    }
}

void Sim::ioctl_write(uint32_t addr, uint8_t data)
{
    top->ioctl_addr = addr;
    top->ioctl_dout = data;
    top->ioctl_wr = 1;
    clock();
    top->ioctl_wr = 0;
    clock();
    clock();
    for (int i = 0; i < 10000 && top->ioctl_wait; i++) clock();   // tape data buffer (DDR3) busy
}

void Sim::set_status(int lo, int width, uint32_t v)
{
    for (int b = 0; b < width; b++) {
        int bit = lo + b;
        if ((v >> b) & 1) status_bits[bit / 32] |= 1u << (bit % 32);
        else status_bits[bit / 32] &= ~(1u << (bit % 32));
    }
}

void Sim::apply_status()
{
    for (int i = 0; i < 4; i++) top->status[i] = status_bits[i];
}

// "Name=Value, Name=Value": names and values as the OSD shows them (case-insensitive), or a value's index.
bool Sim::apply_osd(const std::string &assignments)
{
    static std::vector<OsdOption> table;
    if (table.empty()) table = read_osd_options(opt.conf_str_file);
    if (table.empty()) { fprintf(stderr, "--osd: no OSD options found in %s\n", opt.conf_str_file.c_str()); return false; }
    std::string item;
    std::vector<std::string> items;
    for (char c : assignments + ",") { if (c == ',') { if (!lower_trim(item).empty()) items.push_back(item); item.clear(); } else item += c; }
    for (auto &it : items) {
        size_t eq = it.find('=');
        if (eq == std::string::npos) { fprintf(stderr, "--osd: '%s' is not NAME=VALUE\n", it.c_str()); return false; }
        std::string name = lower_trim(it.substr(0, eq)), val = lower_trim(it.substr(eq + 1));
        const OsdOption *o = nullptr;
        for (auto &x : table) if (lower_trim(x.name) == name) o = &x;
        if (!o) { fprintf(stderr, "--osd: no option '%s' (see --osd-list)\n", it.substr(0, eq).c_str()); return false; }
        int v = -1;
        for (size_t k = 0; k < o->values.size(); k++) if (lower_trim(o->values[k]) == val) v = (int)k;
        if (v < 0 && !val.empty() && val.find_first_not_of("0123456789") == std::string::npos) v = atoi(val.c_str());
        if (v < 0) { fprintf(stderr, "--osd: '%s' has no value '%s'\n", o->name.c_str(), it.substr(eq + 1).c_str()); return false; }
        set_status(o->lo, o->width, (uint32_t)v);
        if (!opt.quiet) fprintf(stderr, "[sim] OSD %s = %s (status[%d+%d] = %d)\n", o->name.c_str(),
                                v < (int)o->values.size() ? o->values[v].c_str() : "?", o->lo, o->width, v);
    }
    return true;
}

// The OSD status word for the sim's options, then --osd on top. Where the sim's defaults differ from the core's
// (Fast Tape Off, Keyboard Layout Sharp, Load Direct Start: Reset Only, MZ-800 Mode: MZ-800, Tape Messages Off),
// that is so the regression's expected results stay as they were made.
void Sim::write_config()
{
    static const struct { const char *name; int menu; } MODEL_MENU[] = {
        {"mz80a", 0}, {"mz80k", 1}, {"mz80c", 2}, {"mz1200", 3}, {"mz700", 4}, {"mz80b", 5}, {"mz2000", 6}, {"mz800", 7},
        {"mz1500", 8}};
    for (auto &m : MODEL_MENU) if (opt.model == m.name) set_status(35, 4, (uint32_t)m.menu);
    set_status(4, 3, (uint32_t)(opt.turbo & 7));             // CPU Speed
    set_status(30, 1, opt.boot_reset);                       // MZ-80B/2000 Boot Reset
    set_status(32, 1, opt.mz800_700 ? 0 : 1);               // MZ-800 Mode
    set_status(51, 1, opt.key_sharp);                        // Keyboard Layout: Sharp
    set_status(21, 3, (uint32_t)opt.fast_tape);              // Fast Tape (menu step)
    set_status(49, 1, opt.direct_start ? 0 : 1);             // Load Direct Start: Program / Reset Only
    set_status(52, 1, opt.tape_direct);                      // Tape Image Start: Direct
    set_status(55, 1, opt.tape_msgs ? 0 : 1);                // Tape Messages: On / Off
    set_status(33, 2, (uint32_t)opt.fdc_mode);              // Floppy Interface
    set_status(40, 1, opt.ramdisk);                          // MZ-800 RAM Disk
    set_status(48, 1, opt.fdd_b_hd);                         // Drive B Unit: 3rd
    set_status(47, 1, opt.printer.empty() ? 0 : 1);          // Printer: UART
    set_status(50, 1, opt.printer_ascii);                    // Printer Charset: ASCII
    for (auto &a : opt.osd) if (!apply_osd(a)) { exit_code = 2; return; }
    apply_status();
    top->prn_baud = opt.printer_baud;
    top->joy0     = opt.joy0;
    top->buttons  = 0;
}

// OSD ROM and RAM > Load System ROM: the file goes to download address 0x000000 + offset (SharpMZ.sv passes the
// address through), i.e. the 128 KB system ROM, whose first 4 KB is the MZ-80K 40-column monitor. No reset.
void Sim::load_rom(const std::string &path, uint32_t addr)
{
    std::ifstream f(path, std::ios::binary);
    std::vector<uint8_t> d((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (d.empty()) { fprintf(stderr, "cannot read ROM '%s'\n", path.c_str()); exit_code = 2; return; }
    if (!opt.quiet) fprintf(stderr, "[sim] loading ROM '%s' (%zu bytes) at %06X, frame %u\n", path.c_str(), d.size(), addr, frame);
    top->ioctl_index = 3;                                    // F3: Load System ROM (sharpmz_top holds the machine, then resets it)
    top->ioctl_download = 1;
    for (int i = 0; i < 8; i++) clock();                     // as Main: the file index is latched before the first byte
    for (size_t i = 0; i < d.size(); i++) ioctl_write(addr + (uint32_t)i, d[i]);
    top->ioctl_download = 0;
    for (int i = 0; i < 64; i++) clock();
}

// Load Tape to CMT (F1) or Load Direct to RAM (F2), sent as Main does; sharpmz_top maps the addresses and does the
// direct load's reset.
bool Sim::load_mzf(bool direct)
{
    std::ifstream f(opt.mzf, std::ios::binary);
    std::vector<uint8_t> d((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (d.size() < 128) { fprintf(stderr, "cannot read MZF '%s'\n", opt.mzf.c_str()); exit_code = 2; return false; }
    uint16_t size = d[18] | (d[19] << 8), load = d[20] | (d[21] << 8), exec = d[22] | (d[23] << 8);
    if (!opt.quiet)
        fprintf(stderr, "[sim] %s MZF '%s' size %04X load %04X exec %04X at frame %u\n",
                direct ? "direct-loading" : "loading tape", opt.mzf.c_str(), size, load, exec, frame);

    top->ioctl_index = direct ? 2 : 1;                       // F2 Load Direct to RAM / F1 Load Tape to CMT, as Main sends them
    top->ioctl_download = 1;
    for (int i = 0; i < 8; i++) clock();                     // as Main: the file index is latched before the first byte
    for (size_t i = 0; i < d.size(); i++) {
        if (direct && i >= 128 && size && i >= 128u + size) break;
        ioctl_write((uint32_t)i, d[i]);                      // the file offset: sharpmz_top maps it (10F0, load address, CMT)
    }
    top->ioctl_download = 0;
    for (int i = 0; i < 64; i++) clock();
    return true;
}

// Expand --type commands into timed PS/2 events.
void Sim::schedule_typing()
{
    for (auto &t : opt.types) {
        uint32_t f = t.frame;
        const std::string &s = t.text;
        for (size_t i = 0; i < s.size(); i++) {
            Ps2Key k;
            bool ok = false;
            if (s[i] == '\\' && i + 1 < s.size()) {
                char c = s[++i];
                ok = ps2_from_ascii(c == 'n' || c == 'r' ? '\n' : c, k);
            } else if (s[i] == '{') {
                size_t e = s.find('}', i);
                std::string name = s.substr(i + 1, e - i - 1);
                i = e;
                if (name.rfind("WAIT", 0) == 0) { f += parse_num(name.substr(4)); continue; }
                ok = ps2_from_name(name, k);
                if (!ok) fprintf(stderr, "--type: unknown key {%s}\n", name.c_str());
            } else {
                ok = ps2_from_ascii(s[i], k);
                if (!ok) fprintf(stderr, "--type: no key for '%c'\n", s[i]);
            }
            if (!ok) continue;
            uint32_t lead = k.shift ? opt.shift_lead : 0;
            if (k.shift) ps2_schedule.insert({f, {PS2_LSHIFT, false, true}});
            ps2_schedule.insert({f + lead, {k.code, k.extended, true}});
            ps2_schedule.insert({f + lead + opt.type_press, {k.code, k.extended, false}});
            if (k.shift) ps2_schedule.insert({f + lead + opt.type_press, {PS2_LSHIFT, false, false}});
            f += lead + opt.type_press + opt.type_release;
        }
    }
}

bool Sim::want_png(uint32_t f) const
{
    if (opt.screenshots.count(f)) return true;
    if (opt.dump_range && f >= opt.dump_from && f <= opt.dump_to) return true;
    if (opt.dump_every && f % opt.dump_every == 0) return true;
    return false;
}

void Sim::wav_header()
{
    uint32_t data = (uint32_t)(wav_samples * 2);
    auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, fwav); };
    auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, fwav); };
    fseek(fwav, 0, SEEK_SET);
    fwrite("RIFF", 1, 4, fwav); u32(36 + data); fwrite("WAVEfmt ", 1, 8, fwav);
    u32(16); u16(1); u16(1); u32(48000); u32(96000); u16(2); u16(16);
    fwrite("data", 1, 4, fwav); u32(data);
    fseek(fwav, 0, SEEK_END);
}

void Sim::wav_out_header()
{
    uint32_t data = (uint32_t)(wav2_samples * 4);
    auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, fwav2); };
    auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, fwav2); };
    fseek(fwav2, 0, SEEK_SET);
    fwrite("RIFF", 1, 4, fwav2); u32(36 + data); fwrite("WAVEfmt ", 1, 8, fwav2);
    u32(16); u16(1); u16(2); u32(48000); u32(192000); u16(4); u16(16);
    fwrite("data", 1, 4, fwav2); u32(data);
    fseek(fwav2, 0, SEEK_END);
}

void Sim::write_png(uint32_t f)
{
    if (fb_w == 0 || fb_h == 0) return;
    char name[1024];
    snprintf(name, sizeof(name), "%s/frame_%06u.png", opt.out_dir.c_str(), f);
    if (!stbi_write_png(name, fb_w, fb_h, 3, fb.data(), fb_w * 3)) {
        fprintf(stderr, "cannot write %s\n", name);
        exit_code = 3;
    }
}

void Sim::print_ascii()
{
    int cols = opt.ascii_cols;
    for (int row = 0; row < 25; row++) {
        std::string s;
        for (int col = 0; col < cols; col++) {
            // v1 video.vhd keeps character and attribute interleaved: even bytes are characters.
            top->vram_addr = (row * cols + col) * 2;
            top->eval();
            char c = sharp_vcode_ascii[top->vram_q];
            s += c ? c : '.';
        }
        while (!s.empty() && s.back() == ' ') s.pop_back();
        printf("%s\n", s.c_str());
    }
    fflush(stdout);
}

void Sim::dump_memory()
{
    for (auto &md : opt.memdumps) {
        std::vector<uint8_t> buf(md.len);
        for (uint32_t k = 0; k < md.len; k++) {
            top->sysram_addr = (md.addr + k) & 0xFFFF;
            top->eval();
            buf[k] = top->sysram_q;
        }
        FILE *f = fopen(md.path.c_str(), "wb");
        if (!f || fwrite(buf.data(), 1, buf.size(), f) != buf.size()) {
            fprintf(stderr, "--dump-mem: cannot write %s\n", md.path.c_str());
            exit_code = 3;
        }
        if (f) fclose(f);
    }
}

int Sim::run()
{
    bool known = false;
    for (auto &x : MODELS) if (opt.model == x.name) known = true;
    if (!known) { fprintf(stderr, "unknown model %s\n", opt.model.c_str()); return 2; }
    if (!opt.mzf.empty()) {
        struct stat st;
        if (stat(opt.mzf.c_str(), &st) != 0) { fprintf(stderr, "cannot open %s\n", opt.mzf.c_str()); return 2; }
    }
    mkdir(opt.out_dir.c_str(), 0777);
    if (!opt.frame_log.empty() && !(flog = fopen(opt.frame_log.c_str(), "w"))) {
        fprintf(stderr, "cannot write %s\n", opt.frame_log.c_str()); return 2;
    }
    if (flog) fprintf(flog, "frame,fb_hash,cpu_cycles,pc\n");
    if (!opt.io_file.empty() && !(fio = fopen(opt.io_file.c_str(), "w"))) { fprintf(stderr, "cannot write %s\n", opt.io_file.c_str()); return 2; }
    if (!opt.wav_file.empty()) {
        if (!(fwav = fopen(opt.wav_file.c_str(), "wb"))) { fprintf(stderr, "cannot write %s\n", opt.wav_file.c_str()); return 2; }
        wav_header();
    }
    if (!opt.wav_out_file.empty()) {
        if (!(fwav2 = fopen(opt.wav_out_file.c_str(), "wb"))) { fprintf(stderr, "cannot write %s\n", opt.wav_out_file.c_str()); return 2; }
        wav_out_header();
    }
    if (!opt.trace_file.empty() && !(ftrace = fopen(opt.trace_file.c_str(), "w"))) {
        fprintf(stderr, "cannot write %s\n", opt.trace_file.c_str()); return 2;
    }
    if (ftrace) fprintf(ftrace, "frame,cpu_cycle,pc\n");

    if (opt.osd_list) {
        for (auto &o : read_osd_options(opt.conf_str_file)) {
            printf("%-26s status[%d%s]:", o.name.c_str(), o.lo, o.width > 1 ? ("+" + std::to_string(o.width)).c_str() : "");
            for (size_t k = 0; k < o.values.size(); k++) printf(" %zu=%s", k, o.values[k].c_str());
            printf("\n");
        }
        return 0;
    }
    // Power-on: hold reset, then configure the machine the way SharpMZ.sv does.
    top->reset = 1;
    top->ps2_key = 0;
    write_config();
    if (exit_code) return exit_code;
    for (int i = 0; i < 256; i++) clock();
    top->reset = 0;
    for (int i = 0; i < 128; i++) clock();
    // Reset the frame count and counters so frame 0 starts with the configured machine.
    frame = 0; cpu_cycles = 0; fb.clear(); fb_h = 0; line.clear();

    schedule_typing();
    auto range = ps2_schedule.equal_range(0);
    for (auto it = range.first; it != range.second; ++it) ps2_queue.push_back(it->second);

    if (!opt.mzf.empty() && (opt.mzf_direct ? opt.mzf_direct_frame == 0 : opt.mzf_frame == 0))
        if (!load_mzf(opt.mzf_direct)) return exit_code;
    if (!opt.tape_image.empty()) { mount_tape(); if (exit_code) return exit_code; }
    if (!opt.fdd.empty() && opt.fdd_frame == 0) { mount_fdd(); if (exit_code) return exit_code; }
    if (!opt.fdd_b.empty()) { mount_fdd2(); if (exit_code) return exit_code; }
    if (!opt.qd.empty()) { mount_qd(); if (exit_code) return exit_code; }
    if (!opt.printer.empty()) {
        fprn = fopen(opt.printer.c_str(), "wb");
        if (!fprn) { fprintf(stderr, "cannot write %s\n", opt.printer.c_str()); return 2; }
    }

    uint32_t last = opt.stop_set ? opt.stop_frame : 150;
    while (frame <= last && !Verilated::gotFinish()) clock();

    if (img) {
        // Let a save in progress finish.
        for (int i = 0; i < 2000000 && top->tape_active; i++) clock();
        if (!opt.quiet) fprintf(stderr, "[sim] tape image: record %u%s\n", top->tape_record, top->tape_full ? ", TAPE FULL" : "");
        fclose(img);
    }
    if (opt.ascii_end) print_ascii();
    if (!opt.vram_dump.empty()) {
        FILE *f = fopen(opt.vram_dump.c_str(), "wb");
        for (int a = 0; f && a < 4096; a++) { top->vram_addr = a; top->eval(); fputc(top->vram_q, f); }
        if (f) fclose(f);
    }
    dump_memory();
    if (flog) fclose(flog);
    if (fwav) { wav_header(); fclose(fwav); }
    if (fwav2) { wav_out_header(); fclose(fwav2); }
    if (fio) fclose(fio);
    if (ftrace) fclose(ftrace);
    return exit_code;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Options opt;
    if (!parse_args(argc, argv, opt)) return 2;
    Sim sim(opt);
    return sim.run();
}
