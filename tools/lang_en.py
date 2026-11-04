"""Make an English "arcade root" from the Japanese one and an English-language 3DX+ (the same build
as the Japanese: v386, main dated Mar 20 2010), for the other tools to read.

usage: lang_en.py <Japanese root> <English root (main, data/sprite-us, anime-us, movie-us, cutin/us)> <out root>

The cars, the rivals and the physics stay the Japanese build's (never run --phys on the out root).
What the out root holds:
- main: the Japanese one with its Japanese strings' pointers moved to the English build's strings.
  Each string is paired by place, not by text: a function of the same name and size in both builds
  gives (pointer here, pointer there) at each code offset that holds one, which pairs the code's own
  strings and gives each data table's distance between the builds. The strings go in a new load
  segment (GNU_STACK's program header, .comment's section header; both tool kinds read one of them).
  Also from the English build: the sprites' table sizes (+0x10). (Its UV table differs in 4 rows
  menupack.py does not use.)
  The titles: youTitle::TitleTableData's rows already hold the English at +0x18 beside +0x14's.
- data/sprite: the English picture of each name, but for the ones in keep_japanese. A swap of pictures
  misses what the English build's code draws differently: see english_hud, and storysel.py's STORYSEL_DAI.
- data/anime: the English layouts with their sprite ids back in the Japanese table's numbering, where
  they have the same frames and records (menu.c knows the frames) and all their sprites have numbers.
- data/cutin/jp: cutin/us's files, in UTF-8. data/movie: movie-us's, but for the opening. All else links
  to the Japanese.
- lang.txt: the port's own Japanese literals in the tools (menupack.py's localize).
"""
import bisect
import collections
import os
import re
import shutil
import struct
import sys

import numpy as np
from PIL import Image

SPRITES, SPRITES_N, SPRITE_SIZE = 0x9551560, 0x2000, 44  # clImageResourceManager's table (menupack.py)
TITLES, TITLES_N = 0x9745580, 5200                       # youTitle::TitleTableData (titledb.py)
NEW_SEGMENT = 0x0A000000

# Lines written for another car than the Japanese build's rival: the English build races a Z33, an
# RX-8 and so on where this one has the Gemballas.
CAR_FIXES = [("black Z33", "black Gemballa"), ("the 700 hp FR", "the 700 hp RR"), ("well made RX-8", "well made 3.8RS"),
             ("really like RX-8", "really like Gemballas"), ("That's black car might", "That black Gemballa might"),
             ("with my car.", "with my Gemballa."), ("Cosmo?", "Gemballa?"), ("The Mazda Eunos Cosmos,", "The Gemballa RSR,"),
             ("In 4th gear and D.", "In 5th gear and D."), ("going on with RX-8", "going on with the Gemballa")]
# '^' is the English script's comma: the Japanese fonts draw it as a caret
TEXT_FIXES = CAR_FIXES + [("^", ",")]

# the port's literals (from, to), in this order, applied by menupack.py to whatever text it renders
LITERALS = [("級　/", " /"), ("湾岸の新人", "Wangan Beginner"), ("馬力", "HP"), ("スタートランプ", "Start Ramp"),
            ("装着完了！", "Installed!"), ("純正ホイールに交換完了！", "Stock wheels installed!"),
            ("個人タクシー", "Private taxi"), ("教習車", "Driving school"),
            ("箱根往路", "Hakone outbound"), ("箱根復路", "Hakone inbound"), ("御殿場", "Gotemba"),
            ("丸の内ランプ", "Marunouchi ramp"), ("箱根", "Hakone"),
            ("うわ", "Wo"), ("ぁ", "a"), ("っ", "!")]  # (the rival's scream, which the English build left)

JAPANESE = re.compile("[぀-ヿ㐀-鿿＀-･]")  # (not the half-width katakana: bytes read as Shift-JIS)


class Elf:
    def __init__(self, path):
        self.d = open(path, "rb").read()
        phoff, = struct.unpack_from("<I", self.d, 28)
        phnum, = struct.unpack_from("<H", self.d, 44)
        self.segs = []
        for i in range(phnum):
            t, off, va, _, fsz = struct.unpack_from("<5I", self.d, phoff + 32 * i)
            if t == 1:
                self.segs.append((va, off, fsz))
        shoff, = struct.unpack_from("<I", self.d, 32)
        shnum, strndx = struct.unpack_from("<HH", self.d, 48)
        raw = [struct.unpack_from("<10I", self.d, shoff + 40 * i) for i in range(shnum)]
        names = raw[strndx][4]
        self.sec = {self.d[names + s[0]:self.d.index(b"\0", names + s[0])].decode(): s for s in raw}
        self.shoff, self.raw = shoff, raw
        self.text = self.range(".text")
        self.lo, self.hi = self.range(".rodata")[0], self.range(".bss")[1]  # all that a pointer can mean here

    def range(self, name):
        s = self.sec[name]
        return s[3], s[3] + s[5]

    def off(self, va):
        for v, o, n in self.segs:
            if v <= va < v + n:
                return o + va - v
        return None

    def u32(self, va):
        o = self.off(va)
        return None if o is None else struct.unpack_from("<I", self.d, o)[0]

    def string(self, va):
        """(encoding, text) of a string at va: a wchar_t's when it reads as one, else UTF-8, else Shift-JIS"""
        o = self.off(va)
        if o is None or not self.lo <= va < self.hi:
            return None
        if va % 4 == 0:
            s, p = [], o
            while p + 4 <= len(self.d) and len(s) < 400:
                c, = struct.unpack_from("<I", self.d, p)
                if c == 0:
                    if s:
                        return "utf-32-le", "".join(map(chr, s))
                    break
                if not (0x20 <= c < 0x110000 or c == 10) or 0xD800 <= c < 0xE000:
                    break
                s.append(c)
                p += 4
        end = self.d.find(b"\0", o, o + 1000)
        if end <= o:
            return None
        for enc in ("utf-8", "cp932"):
            try:
                return enc, self.d[o:end].decode(enc)
            except UnicodeDecodeError:
                pass
        return None

    def functions(self):
        """name -> [(address, size)] of the named functions, and under (name,) the code with no name
        after each (the static initializers), those of a repeated name in address order"""
        s = self.sec[".dynsym"]
        names = self.sec[".dynstr"][4]
        rows = []
        for o in range(s[4], s[4] + s[5], 16):
            nm, va, size, info = struct.unpack_from("<IIIB", self.d, o)
            if info & 15 == 2 and size and self.text[0] <= va < self.text[1]:
                rows.append((va, size, self.d[names + nm:self.d.index(b"\0", names + nm)]))
        rows.sort()
        out = collections.defaultdict(list)
        for k, (va, size, name) in enumerate(rows):
            out[name].append((va, size))
            end = va + size
            if k + 1 < len(rows) and rows[k + 1][0] > end:
                out[(name,)].append((end, rows[k + 1][0] - end))
        return {k: sorted(v) for k, v in out.items()}

    def string_or_empty(self, va, enc):
        """a string of that encoding at va, "" for a string with nothing in it (the English build
        blanks a Japanese line's second half)"""
        o = self.off(va)
        if o is None or not self.lo <= va < self.hi:
            return None
        if self.d[o:o + (4 if enc == "utf-32-le" else 1)].count(0) == (4 if enc == "utf-32-le" else 1):
            return ""
        s = self.string(va)
        return s[1] if s and s[0] == enc else None


def words(e, va, size):
    """(offset, value) of the words in a stretch of code that can be pointers in e"""
    x = np.frombuffer(e.d, np.uint8, size, e.off(va)).astype(np.uint32)
    w = x[:-3] | x[1:-2] << 8 | x[2:-1] << 16 | x[3:] << 24
    return w, (w >= e.lo) & (w < e.hi)


def text_refs(e, va, size):
    """the code's pointers to strings, in order, by encoding (a string is Japanese or plain words here:
    any bytes read as a short string)"""
    out = collections.defaultdict(list)
    w, m = words(e, va, size)
    for k in np.nonzero(m)[0]:
        s = e.string(int(w[k]))
        if s and (is_japanese(s) or re.fullmatch(r"[A-Za-z0-9 ,.!?'/()&#^\\-]{3,}", s[1])):
            out[s[0]].append((va + int(k), int(w[k])))
    return out


def code_pairs(j, a):
    """(address of the code's word in j, its value there, its value in a), for the words that are
    pointers in both: over the code of a name and size the two builds share, and in the code that
    changed size, its strings in order when both have as many"""
    fj, fa = j.functions(), a.functions()
    out, same, other, by_order = [], 0, 0, 0
    for name, rows in fj.items():
        if len(rows) != len(fa.get(name, ())):
            other += 1
            continue
        for (va, size), (vb, sizeb) in zip(rows, fa[name]):
            if size < 4 or sizeb < 4:
                continue
            if size != sizeb:
                ry, rx = text_refs(a, vb, sizeb), text_refs(j, va, size)
                paired = False
                for enc, xs in rx.items():
                    ys = ry.get(enc, ())
                    if len(xs) == len(ys):
                        out += [(at, x, y) for (at, x), (_, y) in zip(xs, ys)]
                        paired = True
                by_order += paired
                other += not paired
                continue
            same += 1
            wx, mx = words(j, va, size)
            wy, my = words(a, vb, size)
            for k in np.nonzero(mx & my)[0]:
                out.append((va + int(k), int(wx[k]), int(wy[k])))
    print(f"code: {same} stretches of the same size, {by_order} paired by their strings' order, "
          f"{other} not paired, {len(out)} pointers")
    return out


class Mapper:
    """a data address here -> there. Each address the code names gives the distance between the builds
    from there on; a table the code reaches only through its neighbour may lie past a change of
    distance, so of the nearby distances take the one whose surroundings match best."""

    def __init__(self, pairs, j, a):
        self.j, self.a = j, a
        votes = collections.defaultdict(collections.Counter)
        for _, x, y in pairs:
            if x != y and 0 < y - x < 0x20000:  # (0: a number that reads as an address)
                votes[x][y - x] += 1
        self.at = sorted(votes)
        self.delta = [votes[x].most_common(1)[0][0] for x in self.at]

    def score(self, va, delta):
        """about va: a pointer to a Japanese string there and a string here count most, then words of
        the same kind (pointers, or the same number)"""
        n = 0
        j, a = self.j, self.a
        for k in range(-32, 33):
            x, y = j.u32(va + 4 * k), a.u32(va + delta + 4 * k)
            if x is None or y is None:
                continue
            if j.lo <= x < j.hi:
                if a.lo <= y < a.hi:
                    n += 1
                    if is_japanese(j.string(x)):
                        n += 3 if a.string(y) else -3
                elif is_japanese(j.string(x)):
                    n -= 3
            elif x == y:
                n += 1
        return n

    def __call__(self, va):
        i = bisect.bisect_right(self.at, va) - 1
        if i < 0:
            return None
        near = dict.fromkeys(self.delta[max(0, i - 2):i + 6])
        return va + max(near, key=lambda d: (self.score(va, d), d == self.delta[i]))


def is_japanese(s):
    if s is None or not JAPANESE.search(s[1]):
        return False
    return not any(ord(c) < 32 and c != "\n" or "｡" <= c <= "ﾟ" or "\ue000" <= c <= "\uf8ff" for c in s[1])


def fix_text(s, space=" "):
    for x, y in TEXT_FIXES:
        s = s.replace(x.replace(" ", space), y.replace(" ", space))
    return s


def patch_main(jroot, eroot, out):
    j, a = Elf(f"{jroot}/main"), Elf(f"{eroot}/main")
    pairs = code_pairs(j, a)
    mapper = Mapper(pairs, j, a)
    moves = {}      # file offset of a word in main -> (encoding, English text)
    stats = collections.Counter()
    unpaired = {}

    for at, x, y in pairs:
        s = j.string(x)
        if is_japanese(s):
            t = a.string_or_empty(y, s[0])
            if t is not None and not is_japanese((s[0], t)):
                moves[j.off(at)] = (s[0], t)
                stats["code"] += 1
            else:
                unpaired[s[1]] = "code"

    # the tables: each aligned word in .rodata and .data that points at a Japanese string
    for sec in (".rodata", ".data"):
        lo, hi = j.range(sec)
        o = j.off(lo)
        words = np.frombuffer(j.d, "<u4", (hi - lo) // 4, o)
        for k in np.nonzero((words >= j.lo) & (words < j.hi))[0]:
            slot, x = lo + 4 * int(k), int(words[k])
            s = j.string(x)
            if not is_japanese(s):
                continue
            there = mapper(slot)
            y = a.u32(there) if there else None
            t = a.string_or_empty(y, s[0]) if y else None
            if t is not None and not is_japanese((s[0], t)):
                moves[j.off(slot)] = (s[0], t)
                stats["table"] += 1
            else:
                unpaired[s[1]] = "table"

    # the titles' own English; '/' is where a big title breaks, drawn here on one line
    for i in range(TITLES_N):
        row = TITLES + 0x1C * i
        t = j.string(j.u32(row + 0x18))
        if t and not is_japanese(t):
            moves[j.off(row + 0x14)] = (t[0], t[1].replace("/", " "))
            stats["title"] += 1

    # the sprites' sizes and the English names' table
    there = mapper(SPRITES)
    english = {}
    for i in range(SPRITES_N):
        p = a.u32(there + SPRITE_SIZE * i)
        if p and a.off(p) is not None:
            s = a.string(p)
            if s and s[1].startswith("data/sprite"):
                english[os.path.basename(s[1]).lower()] = (i, there + SPRITE_SIZE * i)
    names = {}
    for i in range(SPRITES_N):
        p = j.u32(SPRITES + SPRITE_SIZE * i)
        if p and j.off(p) is not None:
            s = j.string(p)
            if s and s[1].startswith("data/sprite"):
                names[i] = os.path.basename(s[1])

    d = bytearray(j.d)
    blob, where = bytearray(), {}
    for slot, (enc, text) in moves.items():
        key = (enc, fix_text(text))
        if key not in where:
            while enc == "utf-32-le" and len(blob) % 4:
                blob.append(0)
            where[key] = NEW_SEGMENT + len(blob)
            blob += key[1].encode(enc) + b"\0" * (4 if enc == "utf-32-le" else 1)
        struct.pack_into("<I", d, slot, where[key])
    # the new segment, at the end of the file
    while len(d) % 0x1000:
        d.append(0)
    file_at = len(d)
    d += blob
    phoff, = struct.unpack_from("<I", d, 28)
    phnum, = struct.unpack_from("<H", d, 44)
    for i in range(phnum):
        if struct.unpack_from("<I", d, phoff + 32 * i)[0] == 0x6474E551:  # PT_GNU_STACK
            struct.pack_into("<8I", d, phoff + 32 * i, 1, file_at, NEW_SEGMENT, NEW_SEGMENT, len(blob), len(blob), 4, 0x1000)
            break
    else:
        raise SystemExit("no GNU_STACK header to take")
    index = j.raw.index(j.sec[".comment"])
    struct.pack_into("<I", d, j.shoff + 40 * index + 12, NEW_SEGMENT)
    struct.pack_into("<I", d, j.shoff + 40 * index + 16, file_at)
    struct.pack_into("<I", d, j.shoff + 40 * index + 20, len(blob))

    print(f"strings: {dict(stats)} moved, {len(where)} English strings ({len(blob)} bytes), "
          f"{len(unpaired)} Japanese strings not paired")
    return d, j, a, names, english, unpaired


def english_hud(ed, out):
    """The race's own plate (hudpack.py): the English build's code takes HP/ from the atlas (UV table entry
    76, the 28 x 16 of cons_p_bariki_bariki's 馬力/) and draws no 級 after the class."""
    atlas = Image.open(f"{ed}/cons_p_01.png").convert("RGBA")
    for name, picture in (("cons_p_bariki_bariki.png", atlas.crop((216, 76, 244, 92))),
                          ("cons_p_rank_Q.png", Image.new("RGBA", (16, 16)))):
        os.unlink(f"{out}/{name}")
        picture.save(f"{out}/{name}")


def blank(path):
    try:
        return Image.open(path).convert("RGBA").getchannel("A").getbbox() is None
    except OSError:
        return True


def keep_japanese(name, en_path):
    """The English build blanks the Gemballas' pictures; its meters and logos go with its own cars"""
    return re.search(r"(_hari|_mater|logo)", name) is not None or blank(en_path)


def link_all(src, dst, skip=()):
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(src):
        if f not in skip:
            os.symlink(os.path.abspath(os.path.join(src, f)), os.path.join(dst, f))


def overlay_sprites(jd, ed, out):
    os.makedirs(out)
    used, kept = 0, []
    for f in os.listdir(jd):
        e = os.path.join(ed, f)
        src = os.path.join(jd, f)
        if os.path.exists(e):
            if keep_japanese(f, e):
                kept.append(f)
            else:
                src, used = e, used + 1
        os.symlink(os.path.abspath(src), os.path.join(out, f))
    english_hud(ed, out)
    print(f"sprites: {used} English, {len(kept)} kept Japanese over the English build's")
    return kept


def anm_layout(d):
    nf, _ = struct.unpack_from("<2I", d, 0)
    frames = struct.unpack_from(f"<{2 * nf}I", d, 8)
    base = 8 + 8 * nf
    return frames, base, (len(d) - base) // 64


def overlay_anime(jd, ed, out, sprite_id_of, english_names):
    """the English layout where the frames and records match, its ids renumbered to the Japanese table"""
    os.makedirs(out)
    used, other = 0, []
    for f in os.listdir(jd):
        src, e = os.path.join(jd, f), os.path.join(ed, f)
        if not f.endswith(".anm") or not os.path.exists(e):
            os.symlink(os.path.abspath(src), os.path.join(out, f))
            continue
        dj, de = open(src, "rb").read(), bytearray(open(e, "rb").read())
        fj, _, nj = anm_layout(dj)
        fe, base, ne = anm_layout(de)
        ok = fj == fe and nj == ne
        for k in range(ne if ok else 0):
            sid, = struct.unpack_from("<i", de, base + 64 * k)
            if sid < 0:
                continue
            name = english_names.get(sid)
            jid = sprite_id_of.get(name) if name else 0  # (no name: nothing to draw, as the table's first ids)
            if jid is None:
                ok = False
                break
            struct.pack_into("<i", de, base + 64 * k, jid)
        if ok:
            open(os.path.join(out, f), "wb").write(de)
            used += 1
        else:
            os.symlink(os.path.abspath(src), os.path.join(out, f))
            other.append(f)
    print(f"anime: {used} English layouts, {len(other)} Japanese: {sorted(other)}")


def overlay_cutin(jd, ed, out):
    os.makedirs(out)
    n = 0
    for f in os.listdir(jd):
        e = os.path.join(ed, f)
        if not os.path.exists(e):
            os.symlink(os.path.abspath(os.path.join(jd, f)), os.path.join(out, f))
            continue
        raw = open(e, "rb").read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = "".join(b.decode("utf-8", "ignore") if b.isascii() else b.decode("cp932", "replace")
                           for b in re.split(rb"(\s+)", raw))
        open(os.path.join(out, f), "w", encoding="utf-8", newline="").write(fix_text(text, "#"))  # (these files' spaces)
        n += 1
    print(f"cut-ins: {n} English files")


def check(out):
    """what a wrong pairing or a changed script would break: a table the code does not name, a title,
    the fixes' lines"""
    e = Elf(f"{out}/main")
    e.hi = NEW_SEGMENT + e.sec[".comment"][5]  # (the strings moved up there)
    assert e.string(e.u32(0x93FD340))[1] == "First half The return of the devil Z", "the chapter titles' table"
    assert e.string(e.u32(TITLES + 0x1C + 0x14))[1] == "Wangan Beginner", "the titles"
    assert e.string(e.u32(SPRITES + SPRITE_SIZE * 4))[1] == "data/sprite/3d.png", "the sprite table moved"
    assert Image.open(f"{out}/data/sprite/cons_p_bariki_bariki.png").getbbox(), "HP/ in the atlas"
    cut = "".join(open(os.path.join(f"{out}/data/cutin/jp", f), encoding="utf-8").read()
                  for f in os.listdir(f"{out}/data/cutin/jp"))
    for x, y in CAR_FIXES[:6]:
        assert x.replace(" ", "#") not in cut and y.replace(" ", "#") in cut, x


def main():
    jroot, eroot, out = sys.argv[1:4]
    if os.path.exists(out):
        shutil.rmtree(out)
    d, j, a, names, english, unpaired = patch_main(jroot, eroot, out)
    os.makedirs(f"{out}/data")
    jd, ed = f"{jroot}/data", f"{eroot}/data"
    link_all(jd, f"{out}/data", skip=("sprite", "anime", "cutin", "movie"))
    kept = overlay_sprites(f"{jd}/sprite", f"{ed}/sprite-us", f"{out}/data/sprite")
    kept_lower = {k.lower() for k in kept}
    jid = {v.lower(): k for k, v in names.items()}
    aname = {i: n for n, (i, _) in english.items()}
    overlay_anime(f"{jd}/anime", f"{ed}/anime-us", f"{out}/data/anime", jid, aname)
    os.makedirs(f"{out}/data/cutin")
    overlay_cutin(f"{jd}/cutin/jp", f"{ed}/cutin/us", f"{out}/data/cutin/jp")
    os.makedirs(f"{out}/data/movie")
    for f in os.listdir(f"{ed}/movie-us"):
        # atruct's English build drives a black Z33 for the Blackbird and keeps its Japanese captions
        src = f"{jd}/movie/{f}" if f == "atruct.bik" else f"{ed}/movie-us/{f}"
        os.symlink(os.path.abspath(src), f"{out}/data/movie/{f}")

    # the sprites' sizes (menupack.py draws at the table's) of the pictures now English
    for i, name in names.items():
        low = name.lower()
        if low in english and low not in kept_lower:
            size = struct.unpack_from("<2f", a.d, a.off(english[low][1] + 16))
            if min(size) > 0:
                struct.pack_into("<2f", d, j.off(SPRITES + SPRITE_SIZE * i + 16), *size)
    open(f"{out}/main", "wb").write(d)
    os.chmod(f"{out}/main", 0o755)
    with open(f"{out}/lang.txt", "w", encoding="utf-8") as o:
        for x, y in LITERALS:
            o.write(f"{x}\t{y}\n")
    with open(f"{out}/not_paired.txt", "w", encoding="utf-8") as o:  # (the tools' lists show what matters)
        for s, where in sorted(unpaired.items()):
            o.write(f"{where}\t{s!r}\n")
    check(out)
    print("->", out)


if __name__ == "__main__":
    main()
