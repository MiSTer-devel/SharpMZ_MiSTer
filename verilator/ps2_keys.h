// PS/2 set 2 scancodes for typing text into the core, as MiSTer's hps_io
// delivers them in ps2_key (US layout). The core's keymap ROM translates
// these to the Sharp key matrix.
#pragma once
#include <cstdint>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>

struct Ps2Key {
    uint8_t code;      // set 2 make code
    bool    extended;  // E0 prefix
    bool    shift;     // needs left shift held
};

static const uint8_t PS2_LSHIFT = 0x12;

// Printable ASCII -> key. Returns false if there is no key for it.
static bool ps2_from_ascii(char c, Ps2Key &k)
{
    static const struct { char c; uint8_t code; bool shift; } tab[] = {
        {'a',0x1C,0},{'b',0x32,0},{'c',0x21,0},{'d',0x23,0},{'e',0x24,0},{'f',0x2B,0},{'g',0x34,0},
        {'h',0x33,0},{'i',0x43,0},{'j',0x3B,0},{'k',0x42,0},{'l',0x4B,0},{'m',0x3A,0},{'n',0x31,0},
        {'o',0x44,0},{'p',0x4D,0},{'q',0x15,0},{'r',0x2D,0},{'s',0x1B,0},{'t',0x2C,0},{'u',0x3C,0},
        {'v',0x2A,0},{'w',0x1D,0},{'x',0x22,0},{'y',0x35,0},{'z',0x1A,0},
        {'1',0x16,0},{'2',0x1E,0},{'3',0x26,0},{'4',0x25,0},{'5',0x2E,0},{'6',0x36,0},{'7',0x3D,0},
        {'8',0x3E,0},{'9',0x46,0},{'0',0x45,0},
        {'!',0x16,1},{'@',0x1E,1},{'#',0x26,1},{'$',0x25,1},{'%',0x2E,1},{'^',0x36,1},{'&',0x3D,1},
        {'*',0x3E,1},{'(',0x46,1},{')',0x45,1},
        {' ',0x29,0},{'-',0x4E,0},{'_',0x4E,1},{'=',0x55,0},{'+',0x55,1},{'[',0x54,0},{'{',0x54,1},
        {']',0x5B,0},{'}',0x5B,1},{'\\',0x5D,0},{'|',0x5D,1},{';',0x4C,0},{':',0x4C,1},{'\'',0x52,0},
        {'"',0x52,1},{',',0x41,0},{'<',0x41,1},{'.',0x49,0},{'>',0x49,1},{'/',0x4A,0},{'?',0x4A,1},
        {'`',0x0E,0},{'~',0x0E,1},
    };
    // Sharp monitors and BASIC expect capitals; type letters unshifted, which
    // the keymap presents as upper case.
    char lc = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
    for (auto &t : tab) {
        if (t.c == lc) { k = {t.code, false, t.shift}; return true; }
    }
    if (c == '\n' || c == '\r') { k = {0x5A, false, false}; return true; }
    return false;
}

// Named keys for {NAME} escapes.
static bool ps2_from_name(const std::string &n, Ps2Key &k)
{
    static const struct { const char *name; uint8_t code; bool ext; bool shift; } tab[] = {
        {"RETURN",0x5A,0,0}, {"ENTER",0x5A,0,0}, {"SPACE",0x29,0,0},
        {"BREAK",0x76,0,0},  {"ESC",0x76,0,0},
        {"DEL",0x66,0,0},    {"BS",0x66,0,0},    {"INS",0x70,1,0},
        {"HOME",0x6C,1,0},   {"CLR",0x6C,1,1},
        {"UP",0x75,1,0},     {"DOWN",0x72,1,0},  {"LEFT",0x6B,1,0}, {"RIGHT",0x74,1,0},
        {"F1",0x05,0,0},     {"F2",0x06,0,0},    {"F3",0x04,0,0},   {"F4",0x0C,0,0}, {"F5",0x03,0,0},
        {"TAB",0x0D,0,0},    {"CTRL",0x14,0,0},  {"SHIFT",0x12,0,0},
    };
    for (auto &t : tab) {
        if (n == t.name) { k = {t.code, t.ext, t.shift}; return true; }
    }
    // {SCxx} a raw scan code, {E0xx} an extended one, {SSCxx} with SHIFT (hex).
    bool sh = n.rfind("SSC", 0) == 0;
    std::string h = sh ? n.substr(3) : n.size() > 2 && (n.rfind("SC", 0) == 0 || n.rfind("E0", 0) == 0) ? n.substr(2) : "";
    if (h.size() == 2 && isxdigit((unsigned char)h[0]) && isxdigit((unsigned char)h[1])) {
        k = {(uint8_t)strtoul(h.c_str(), nullptr, 16), n.rfind("E0", 0) == 0, sh};
        return true;
    }
    return false;
}
