#!/bin/sh
# Optional, and the default build stays Japanese: English text on the Japanese build's cars and
# physics, from an English-language 3DX+'s data. Regenerates the headers and text lists from the
# English root (tools/lang_en.py) and the assets with text in them. Run after the Japanese
# gen_from_original.sh --phys and convert_assets.sh, then rebuild the app.
# --japanese puts the same files back from the Japanese data.
# Usage: tools/convert_en.sh [--japanese] [--japan-dir <path>] [--english-dir <path>]
set -e
cd "$(dirname "$0")/.."
JAPANESE=
ORIG="../Wangan Midnight Maximum Tune 3DX+ (Japan)"
EN="../Wangan Midnight Maximum Tune 3DX+ (English)"
while [ $# -gt 0 ]; do
  case "$1" in
    --japanese) JAPANESE=1; shift ;;
    --japan-dir|--english-dir)
      [ $# -ge 2 ] || { echo "$1 needs a path" >&2; exit 2; }
      if [ "$1" = "--japan-dir" ]; then ORIG="$2"; else EN="$2"; fi
      shift 2 ;;
    *) echo "usage: tools/convert_en.sh [--japanese] [--japan-dir <path>] [--english-dir <path>]" >&2; exit 2 ;;
  esac
done
[ -f "$ORIG/main" ] || { echo "no Japanese data at $ORIG (--japan-dir <path>); the build stays as it is" >&2; exit 1; }
if [ -n "$JAPANESE" ]; then
  OUT="$ORIG"
  WAV=japan
else
  if [ ! -f "$EN/main" ] || [ ! -d "$EN/data/sprite-us" ]; then
    echo "no English data at $EN (--english-dir <path>; see the README's \"Optional: English text\"); the build stays as it is" >&2
    exit 1
  fi
  OUT=build/en_root
  WAV=english
  python3 tools/lang_en.py "$ORIG" "$EN" "$OUT"
fi
sh tools/gen_from_original.sh "$OUT"  # (never --phys: the recompiler must read the real main)
mkdir -p data/cutin/jp
cp "$OUT"/data/cutin/jp/*.txt data/cutin/jp/
rm -f data/intro.mp4 data/playdemo.mp4 data/tutorial.mp4
MOVIE_DATA="$(cd "$OUT/data" && pwd)" MOVIE_WAV="$WAV" sh prepare_movie.sh
python3 tools/hudpack.py "$OUT/data/sprite" "$OUT/main" data
python3 tools/vsdiscs.py "$OUT/data/sprite"
python3 tools/menupack.py "$OUT" data/menu.bin
echo "assets done (${WAV}); rebuild the app, which compiles the new headers"
