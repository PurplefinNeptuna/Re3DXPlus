#!/bin/sh
# Step 2 of the README in one go: every asset in data/ from the arcade's files, on all threads but 2
# (steps that write separate files run side by side). Run tools/gen_from_original.sh first.
# A failed step does not stop the others; the script exits 1 at the end if any failed.
# Usage: JOBS=<n> tools/convert_assets.sh [arcade root]
#   arcade root: as gen_from_original.sh's. pack_tokyo.sh and friends read the default place.
cd "$(dirname "$0")/.."
ORIG="$(cd "${1:-../Wangan Midnight Maximum Tune 3DX+ (Japan)}" && pwd)" || exit 1
[ "$2" = "--step" ] && shift
D="$ORIG/data"
LOG=build/convert
# all threads but 2, left for the system (JOBS= overrides)
JOBS="${JOBS:-$(( $(getconf _NPROCESSORS_ONLN) - 2 ))}"; [ "$JOBS" -ge 1 ] || JOBS=1
export JOBS

step() { # name command...: its output in build/convert/<name>.log, FAILED there if it fails
  n=$1; shift
  s=$(date +%s)
  if "$@" > "$LOG/$n.log" 2>&1; then echo "$n ok $(( $(date +%s) - s ))s"
  else echo "$n FAILED, see $LOG/$n.log"; touch "$LOG/$n.failed"; fi
}
# (xargs below runs this script once per line of build/convert/steps)
if [ "$1" = "--step" ]; then eval "step $(sed -n "$2p" "$LOG/steps")"; exit 0; fi

rm -rf "$LOG"
mkdir -p "$LOG" data/carconfig data/cutin/jp
cp "$D/carconfig/"ytConfig*.txt data/carconfig/
cp "$D/cutin/jp/"*.txt data/cutin/jp/
step sound sh prepare_sound.sh
# (first: the aero packs below share the textures of their car's stock pack, reading it as they go)
step cars python3 tools/stage/pack_cars.py "$ORIG" data/cars

# these write separate files, so up to JOBS of them side by side. The lights and minimaps come
# from the arcade's scene files (<city>/<time>/<time>.lua's StreetLight, BuildingLight, MiniMap);
# Hakone has no lights, so its file is valid and empty.
cat > "$LOG/steps" <<'STEPS'
tokyo_day sh tools/stage/pack_tokyo.sh daytime
tokyo_night sh tools/stage/pack_tokyo.sh night
city_oosaka_day python3 tools/stage/pack_city.py "$D" oosaka daytime data
city_oosaka_night python3 tools/stage/pack_city.py "$D" oosaka night data
city_hakone_day python3 tools/stage/pack_city.py "$D" hakone daytime data
city_hakone_night python3 tools/stage/pack_city.py "$D" hakone night data
city_nagoya_day python3 tools/stage/pack_city.py "$D" nagoya daytime data
city_nagoya_night python3 tools/stage/pack_city.py "$D" nagoya night data
city_fukuoka_day python3 tools/stage/pack_city.py "$D" fukuoka daytime data
city_fukuoka_night python3 tools/stage/pack_city.py "$D" fukuoka night data
aero_a python3 tools/stage/pack_cars.py "$ORIG" data/cars --aero a
aero_b python3 tools/stage/pack_cars.py "$ORIG" data/cars --aero b
aero_c python3 tools/stage/pack_cars.py "$ORIG" data/cars --aero c
wheels python3 tools/stage/pack_cars.py "$ORIG" data/wheels --wheels
chara python3 tools/stage/pack_cars.py "$ORIG" data/chara --chara
traffic sh tools/stage/pack_traffic.sh
fd3s sh tools/stage/pack_car.sh
neon python3 tools/stage/pack_neon.py "$D" data/neon.wpk
hud python3 tools/hudpack.py "$D/sprite" "$ORIG/main" data
lights python3 tools/stage/pack_lights.py "$D" data
lights_oosaka python3 tools/stage/pack_lights.py "$D" data oosaka effect/streetlight_distribution_osaka.igb effect/buildinglight_distribution_ok.igb
lights_hakone python3 tools/stage/pack_lights.py "$D" data hakone - -
lights_nagoya python3 tools/stage/pack_lights.py "$D" data nagoya effect/streetlight_distribution_nk.igb effect/buildinglight_distribution_nk.igb
lights_fukuoka python3 tools/stage/pack_lights.py "$D" data fukuoka effect/streetlight_distribution_fk.igb effect/buildinglight_distribution_fk.igb
navi python3 tools/navipack.py "$D" "$ORIG/main" data
navi_oosaka python3 tools/navipack.py "$D" "$ORIG/main" data OsNavi.igb navi_oosaka.bin
navi_hakone python3 tools/navipack.py "$D" "$ORIG/main" data HkNavi.igb navi_hakone.bin
navi_nagoya python3 tools/navipack.py "$D" "$ORIG/main" data NkNavi.igb navi_nagoya.bin
navi_fukuoka python3 tools/navipack.py "$D" "$ORIG/main" data FkNavi.igb navi_fukuoka.bin
STEPS
awk 'END { for (i = 1; i <= NR; i++) print i }' "$LOG/steps" | xargs -P "$JOBS" -I{} sh "tools/convert_assets.sh" "$ORIG" --step {}

# these share the threads themselves, so one at a time
step movie sh prepare_movie.sh
step vinyl python3 tools/stage/pack_vinyl.py "$ORIG" data/vinyl
step bgm sh prepare_bgm.sh
# (vsdiscs.py makes the pictures menupack.py reads)
step vsdiscs python3 tools/vsdiscs.py "$D/sprite"
step menu python3 tools/menupack.py "$ORIG" data/menu.bin

du -sh data
if ls "$LOG"/*.failed >/dev/null 2>&1; then echo "FAILED: $(cd "$LOG" && ls *.failed | sed 's/\.failed//' | tr '\n' ' ')"; exit 1; fi
echo "all assets done"
