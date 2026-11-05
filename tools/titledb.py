"""Read the arcade's titles (称号) out of `main` and write src/titledb.h.

usage: titledb.py <main> [--check]

- youTitle::TitleTableData (0x9745580): 5200 entries of 0x1c bytes: +0 the id (its index),
  +0xc the rank StockTitle keeps the higher of, +0x14 the title (wchar_t *). Title 1 is
  湾岸の新人, every card's first. GetTitleList's slots hold these ids.
- the card's car (clEffCarType, the colour select's model: tools/cars.json) gives judgeTitle's
  _TitleData_ +4 nsCarParts::BNGCarIDGetFromCarModelID (0x893ce28) and +8 GetTitleColor
  (0x8568778): MODEL_INFO below, from running them under the emulator (`--check` runs them
  again, with the unicorn module), and +0x3c isTaxi, +0x58 isSchool, +0x59 isHighLift, +0xdc
  isR35SpecV (clEffCarType's, plain compares of the model).
- the characters the titles use, in code order: the glyphs menupack.py renders (fonts 1 and 5).
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE, N = 0x9745580, 5200
# model: (BNGCarIDGetFromCarModelID, GetTitleColor)
MODEL_INFO = {
    0: (3, 6), 1: (3, 0), 2: (3, 3), 3: (3, 4), 4: (3, 5), 5: (1, 0), 6: (1, 3), 7: (1, 6), 8: (1, 4),
    9: (1, 5), 10: (2, 3), 11: (2, 0), 12: (2, 6), 13: (2, 4), 14: (2, 5), 15: (4, 1), 16: (4, 7),
    17: (4, 4), 18: (4, 3), 19: (4, 0), 20: (4, 5), 21: (5, 3), 22: (5, 2), 23: (5, 0), 24: (5, 4),
    25: (5, 6), 26: (5, 5), 27: (6, 0), 28: (6, 4), 29: (6, 5), 30: (6, 7), 31: (6, 1), 32: (7, 6),
    33: (7, 0), 34: (7, 5), 35: (7, 2), 36: (7, 1), 37: (7, 3), 38: (13, 4), 39: (13, 7), 40: (13, 6),
    41: (13, 0), 42: (9, 7), 43: (9, 4), 44: (9, 0), 45: (9, 6), 46: (10, 1), 47: (10, 4), 48: (10, 6),
    49: (10, 2), 50: (10, 5), 51: (14, 6), 52: (14, 3), 53: (14, 4), 54: (14, 0), 55: (14, 5),
    56: (11, 3), 57: (11, 4), 58: (11, 6), 59: (11, 0), 60: (11, 5), 61: (12, 0), 62: (12, 5),
    63: (12, 4), 64: (12, 6), 65: (12, 1), 66: (15, 1), 67: (15, 7), 68: (15, 4), 69: (15, 6),
    70: (15, 5), 71: (16, 9), 72: (16, 2), 73: (16, 6), 74: (16, 4), 75: (16, 5), 76: (16, 0),
    77: (17, 7), 78: (17, 4), 79: (17, 5), 80: (17, 0), 81: (17, 6), 82: (17, 2), 83: (18, 6),
    84: (18, 0), 85: (18, 8), 86: (18, 1), 87: (18, 5), 88: (18, 4), 89: (19, 0), 90: (19, 4),
    91: (19, 3), 92: (19, 6), 93: (19, 5), 94: (19, 2), 95: (20, 8), 96: (20, 6), 97: (20, 0),
    98: (20, 3), 99: (20, 4), 100: (20, 2), 101: (21, 3), 102: (21, 6), 103: (21, 2), 104: (21, 0),
    105: (21, 4), 106: (21, 5), 107: (23, 1), 108: (23, 0), 109: (23, 4), 110: (23, 6), 111: (23, 5),
    112: (27, 4), 113: (27, 1), 114: (27, 0), 115: (27, 7), 116: (27, 5), 117: (27, 6), 118: (24, 3),
    119: (24, 4), 120: (24, 1), 121: (24, 6), 122: (24, 7), 123: (25, 5), 124: (25, 4), 125: (25, 6),
    126: (25, 0), 127: (25, 2), 128: (26, 6), 129: (26, 0), 130: (26, 7), 131: (26, 11), 132: (26, 5),
    133: (26, 4), 134: (28, 6), 135: (28, 4), 136: (28, 5), 137: (28, 0), 138: (28, 3), 139: (28, 1),
    140: (29, 5), 141: (29, 4), 142: (29, 0), 143: (29, 10), 144: (29, 1), 145: (30, 0), 146: (30, 3),
    147: (30, 1), 148: (30, 4), 149: (30, 5), 150: (31, 4), 151: (31, 6), 152: (31, 2), 153: (31, 11),
    154: (31, 10), 155: (33, 10), 156: (33, 5), 157: (33, 4), 158: (33, 6), 159: (33, 9), 160: (34, 6),
    161: (34, 11), 162: (34, 0), 163: (34, 6), 164: (43, 4), 165: (43, 6), 166: (43, 6), 167: (43, 5),
    168: (43, 11), 169: (43, 10), 170: (44, 4), 171: (44, 4), 172: (44, 6), 173: (44, 10),
    174: (44, 10), 175: (44, 2), 176: (42, 4), 177: (42, 10), 178: (42, 1), 179: (42, 0), 180: (42, 6),
    181: (42, 5), 182: (22, 6), 183: (22, 10), 184: (22, 5), 185: (22, 7), 186: (22, 0), 187: (22, 4),
    188: (32, 6), 189: (32, 4), 190: (32, 5), 191: (32, 11), 192: (32, 10), 193: (32, 2), 194: (32, 4),
    195: (8, 6), 196: (8, 5), 197: (8, 11), 198: (8, 0), 199: (8, 4), 200: (8, 7), 201: (37, 0),
    202: (37, 0), 203: (37, 0), 204: (37, 0), 205: (37, 0), 206: (37, 0), 207: (36, 0), 208: (36, 0),
    209: (36, 0), 210: (36, 0), 211: (36, 0), 212: (38, 0), 213: (38, 0), 214: (38, 0), 215: (38, 0),
    216: (38, 0), 217: (38, 0), 218: (35, 0), 219: (35, 0), 220: (35, 0), 221: (35, 0), 222: (35, 0),
    223: (35, 0), 224: (44, 4624), 225: (44, 4624), 226: (44, 4624), 227: (44, 4624), 228: (44, 4624),
    229: (44, 4624), 230: (8, 5524), 231: (33, 4624), 232: (39, 0), 233: (39, 0), 234: (39, 0),
    235: (39, 0), 236: (39, 0), 237: (39, 0), 238: (39, 0), 239: (39, 350), 240: (39, 6), 241: (39, 1),
    242: (39, 6171), 243: (40, 0), 244: (40, 0), 245: (40, 0), 246: (40, 0)
}


class Elf:
    def __init__(self, path):
        self.d = open(path, "rb").read()
        e_phoff, = struct.unpack_from("<I", self.d, 0x1C)
        e_phnum, = struct.unpack_from("<H", self.d, 0x2C)
        self.segs = []
        for i in range(e_phnum):
            p_type, p_off, p_va, _, p_filesz = struct.unpack_from("<5I", self.d, e_phoff + 32 * i)
            if p_type == 1:
                self.segs.append((p_va, p_off, p_filesz))

    def u32(self, va):
        for s_va, s_off, size in self.segs:
            if s_va <= va < s_va + size:
                return struct.unpack_from("<I", self.d, va - s_va + s_off)[0]
        raise ValueError(hex(va))


def title_strings(e):
    out = []
    for i in range(N):
        p = e.u32(TABLE + 0x1C * i + 0x14)
        s = []
        while p:
            c = e.u32(p + 4 * len(s))
            if not c:
                break
            s.append(c)
        out.append((e.u32(TABLE + 0x1C * i + 0xC), "".join(map(chr, s))))
    return out


def title_chars(titles):
    return sorted({c for _, t in titles for c in t})


def emu(main):
    os.environ["WMMT_MAIN"] = main
    sys.path.insert(0, os.path.join(HERE, "recomp"))
    from x86emu import Emu
    return Emu(trace_unknown=False)


def main():
    titles = title_strings(Elf(sys.argv[1]))
    chars = title_chars(titles)
    index = {c: k for k, c in enumerate(chars)}
    cars = json.load(open(os.path.join(HERE, "cars.json")))
    models = sorted({col["model"] for m in cars["makers"] for car in m["cars"] for col in car["colors"]})
    out = open(os.path.join(HERE, "..", "src", "titledb.h"), "w")
    w = out.write
    w("/* Generated by tools/titledb.py from the arcade's youTitle tables: do not edit. */\n")
    w("#ifndef TITLEDB_H\n#define TITLEDB_H\n\n")
    w("/* the titles (youTitle::TitleTableData): each one's rank (StockTitle keeps the higher)\n")
    w(" * and its characters, TITLEDB_TEXT[TITLEDB_AT[i] ..] (TITLEDB_LEN[i] of them), glyphs\n")
    w(" * of TITLEDB_CHAR (menupack.py's TITLE_GLYPH1_BASE / TITLE_GLYPH5_BASE + k) */\n")
    w("#define TITLEDB_N %d\n#define TITLEDB_CHARS %d\n" % (N, len(chars)))
    w("static const unsigned short TITLEDB_CHAR[TITLEDB_CHARS] = {\n")
    for k in range(0, len(chars), 16):
        w("  " + ", ".join("0x%04x" % ord(c) for c in chars[k:k + 16]) + ",\n")
    w("};\n")
    w("static const unsigned char TITLEDB_RANK[TITLEDB_N] = {\n")
    for k in range(0, N, 32):
        w("  " + ", ".join(str(r) for r, _ in titles[k:k + 32]) + ",\n")
    w("};\n")
    w("static const unsigned char TITLEDB_LEN[TITLEDB_N] = {\n")
    for k in range(0, N, 32):
        w("  " + ", ".join(str(len(t)) for _, t in titles[k:k + 32]) + ",\n")
    w("};\n")
    at, text = [], []
    for _, t in titles:
        at.append(len(text))
        text += [index[c] for c in t]
    w("static const unsigned int TITLEDB_AT[TITLEDB_N] = {\n")
    for k in range(0, N, 16):
        w("  " + ", ".join(str(a) for a in at[k:k + 16]) + ",\n")
    w("};\n")
    w("static const unsigned short TITLEDB_TEXT[%d] = {\n" % len(text))
    for k in range(0, len(text), 16):
        w("  " + ", ".join(str(g) for g in text[k:k + 16]) + ",\n")
    w("};\n\n")
    # the card's car: each colour's model and what judgeTitle takes of it
    w("/* the colour select's models (clEffCarType) by tools/cars.json's maker, car and colour */\n")
    w("static const unsigned char TITLEDB_MODEL[%d][%d][8] = {\n" % (len(cars["makers"]), max(len(m["cars"]) for m in cars["makers"])))
    for m in cars["makers"]:
        w("  {\n")
        for car in m["cars"]:
            ms = [col["model"] for col in car["colors"]] + [0] * (8 - len(car["colors"]))
            w("    { " + ", ".join(map(str, ms)) + " },\n")
        w("  },\n")
    w("};\n")
    w("/* a model's _TitleData_ +4 (BNGCarIDGetFromCarModelID), +8 (GetTitleColor), and +0x3c isTaxi,\n")
    w(" * +0x58 isSchool, +0x59 isHighLift, +0xdc isR35SpecV as bits 0..3 */\n")
    w("typedef struct { short bng, color; unsigned char flags; } titledb_model;\n")
    w("static const titledb_model TITLEDB_MODELS[256] = {\n")
    e = emu(sys.argv[1]) if "--check" in sys.argv else None
    for mo in models:
        bng, color = MODEL_INFO[mo]
        if e and (e.call(0x893CE28, mo), e.call(0x8568778, mo)) != (bng & 0xFFFFFFFF, color & 0xFFFFFFFF):
            sys.exit("model %d: MODEL_INFO differs from the arcade's" % mo)
        flags = (mo in (0xC2, 0xE7)) | (mo == 0xE6) << 1 | (0xE0 <= mo <= 0xE5) << 2 | (0xEE <= mo <= 0xF2) << 3
        w("  [%d] = { %d, %d, %d },\n" % (mo, bng, color, flags))
    w("};\n\n#endif\n")


if __name__ == "__main__":
    main()
