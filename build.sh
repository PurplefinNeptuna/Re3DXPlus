#!/bin/sh
# Build WMMT.app (armv7, iOS 6.0+) with Xcode 16 clang and the patched iPhoneOS 9.3 SDK,
# fake-signed with ldid. Usage: ./build.sh [deploy|ipa]; PHONE=1 ./build.sh ipa builds the
# iPhone 4's (iPhone family, its own bundle id and icons; main.m/app.c fit the game to its 3:2).
#   deploy: copy the app (and data, first time) to the iPad over `ssh ipad` (needs iproxy 2222:22).
#   ipa: build/WMMT3DX-<version>.ipa with the game data inside the bundle (for AppSync installs;
#        the player's files then go to the app's Documents, see main.m SaveDir).
set -e
cd "$(dirname "$0")"
SDK="$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk"
APP=build/WMMT.app
rm -rf "$APP" && mkdir -p "$APP" build/obj
CC="xcrun --sdk iphoneos clang -arch armv7 -miphoneos-version-min=6.0 -isysroot $SDK"
# the recompiled arcade physics (2.8 MB of generated C) only rebuilds when it changes
if [ ! -f build/obj/phys_rc.o ] || [ src/phys/phys_rc.c -nt build/obj/phys_rc.o ]; then
  echo "compiling the arcade physics (takes a minute)..."
  $CC -O2 -ffp-contract=off -DRC_FPT=double -w -c src/phys/phys_rc.c -o build/obj/phys_rc.o
fi
$CC -O2 -std=gnu99 -Wall -Wno-unused-function -DRC_FPT=double \
  src/main.m src/sound_ios.m src/app.c src/render.c src/hud.c src/car.c src/sound.c src/anm.c src/menu.c src/lights.c src/spark.c src/net.c src/vs_host.c src/title.c src/gk_ios.m \
  src/phys/rc_runtime.c build/obj/phys_rc.o -o "$APP/WMMT" \
  -framework UIKit -framework Foundation -framework OpenGLES -framework QuartzCore \
  -framework AVFoundation -framework AudioToolbox -framework CoreMedia -framework CoreMotion -framework GameKit -lz
cat > "$APP/Info.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>WMMT</string>
  <key>CFBundleIdentifier</key><string>com.wmmt.port</string>
  <key>CFBundleName</key><string>WMMT3DX</string>
  <key>CFBundleDisplayName</key><string>Wangan 3DX+ Portable</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleIconFiles</key><array>
    <string>Icon-72.png</string><string>Icon-72@2x.png</string><string>Icon-76.png</string><string>Icon-76@2x.png</string>
    <string>Icon-Small-50.png</string><string>Icon-Small-50@2x.png</string><string>Icon-Small.png</string><string>Icon-Small@2x.png</string></array>
  <key>UIPrerenderedIcon</key><true/>
  <key>MinimumOSVersion</key><string>6.0</string>
  <key>UIDeviceFamily</key><array><integer>2</integer></array>
  <key>UIStatusBarHidden</key><true/>
  <key>UIRequiresPersistentWiFi</key><false/>
  <key>UISupportedInterfaceOrientations</key><array>
    <string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>UIInterfaceOrientation</key><string>UIInterfaceOrientationLandscapeRight</string>
</dict></plist>
PL
if [ -n "$PHONE" ]; then
  plutil -replace CFBundleIdentifier -string com.wmmt.port.iphone "$APP/Info.plist"
  plutil -replace UIDeviceFamily -json '[1]' "$APP/Info.plist"
  plutil -replace CFBundleIconFiles -json '["Icon.png","Icon@2x.png","Icon-Small.png","Icon-Small@2x.png"]' "$APP/Info.plist"
fi
plutil -convert binary1 "$APP/Info.plist"
# the springboard icons, pre-rendered with iOS 6's rounded corners and shine (tools/make_icon.py)
[ -f data/icon/Icon-72.png ] || python3 tools/make_icon.py
cp data/icon/Icon-*.png "$APP/"
if [ -n "$PHONE" ]; then
  sips -z 57 57 data/icon/Icon-76@2x.png --out "$APP/Icon.png" >/dev/null
  sips -z 114 114 data/icon/Icon-76@2x.png --out "$APP/Icon@2x.png" >/dev/null
fi
ldid -S "$APP/WMMT"
echo "built $(pwd)/$APP"

if [ "$1" = "ipa" ]; then
  # everything deploy copies to /var/mobile/Media/wmmt, inside the bundle (main.m DataDir finds tokyo.wpk there)
  mkdir -p data/carconfig
  cp "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/carconfig/"ytConfig*.txt data/carconfig/
  sh prepare_bgm.sh
  for f in tokyo.wpk tokyo_night.wpk sky.wpk sky_night.wpk arrows.wpk arrows_night.wpk arrows.names \
           lights.wpk lights.bin neon.wpk fd3s.wpk hud.bin navi.bin meters.bin phys.img menu.bin minicourse.wpk intro.mp4 playdemo.mp4 tutorial.mp4; do
    if [ -f data/$f ]; then cp data/$f "$APP/"; fi
  done
  # the other cities (tools/stage/pack_city.py, pack_lights.py, navipack.py)
  for c in oosaka hakone nagoya fukuoka; do
    for f in data/$c.wpk data/${c}_night.wpk data/sky_$c.wpk data/sky_${c}_night.wpk data/arrows_$c.wpk \
             data/arrows_${c}_night.wpk data/arrows_$c.names data/lights_$c.bin data/navi_$c.bin; do
      if [ -f $f ]; then cp $f "$APP/"; fi
    done
  done
  mkdir -p "$APP/traffic" "$APP/carconfig" "$APP/cars" "$APP/sound/bgm" "$APP/sound/engine"
  cp data/traffic/*.wpk "$APP/traffic/"
  cp data/carconfig/*.txt "$APP/carconfig/"
  mkdir -p "$APP/rtmovie"
  cp -R "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/rtmovie/table" "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/rtmovie/trail" "$APP/rtmovie/"
  # the story's in-race lines (Cut::clCutIn: data/cutin/jp)
  mkdir -p "$APP/cutin/jp"
  cp data/cutin/jp/*.txt "$APP/cutin/jp/"
  cp data/cars/* "$APP/cars/"
  # (and their baked ambient occlusion, tools/stage/bake_ao.c, as the car models' in data/cars)
  if [ -d data/chara ]; then mkdir -p "$APP/chara" && cp data/chara/*.wpk "$APP/chara/" && { cp data/chara/*.ao "$APP/chara/" 2>/dev/null || true; }; fi
  # the dress-up wheels and their GET screen models (pack_cars.py --wheels)
  if [ -d data/wheels ]; then mkdir -p "$APP/wheels" && cp data/wheels/*.wpk "$APP/wheels/"; fi
  # the stickers by car (tools/stage/pack_vinyl.py)
  if [ -d data/vinyl ]; then mkdir -p "$APP/vinyl" && cp data/vinyl/*.vpk "$APP/vinyl/"; fi
  cp data/sound/bgm/*.m4a "$APP/sound/bgm/"
  cp data/sound/*.wav "$APP/sound/"
  cp data/sound/engine/*.wav "$APP/sound/engine/"
  ver=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")${PHONE:+-iPhone4}
  rm -rf build/ipa && mkdir -p build/ipa/Payload && cp -R "$APP" build/ipa/Payload/
  (cd build/ipa && rm -f "../WMMT3DX-$ver.ipa" && zip -qry -1 "../WMMT3DX-$ver.ipa" Payload)
  rm -rf build/ipa
  echo "packed $(pwd)/build/WMMT3DX-$ver.ipa ($(du -h "build/WMMT3DX-$ver.ipa" | cut -f1))"
fi

if [ "$1" = "deploy" ]; then
  # game data lives outside the bundle so app updates stay small
  if ! ssh ipad 'test -f /var/mobile/Media/wmmt/c1.wpk'; then
    ssh ipad 'mkdir -p /var/mobile/Media/wmmt'
    scp -O data/c1.wpk data/c1.wcl ipad:/var/mobile/Media/wmmt/
  fi
  # the player's car (tools/stage/pack_car.sh) and the traffic's (tools/stage/pack_traffic.sh); small, so always
  scp -O data/fd3s.wpk ipad:/var/mobile/Media/wmmt/
  [ -f data/traffic/rc2.wpk ] || sh tools/stage/pack_traffic.sh
  ssh ipad 'mkdir -p /var/mobile/Media/wmmt/traffic'
  scp -O data/traffic/*.wpk ipad:/var/mobile/Media/wmmt/traffic/
  # the race HUD and every car's meters (tools/hudpack.py); meters.bin is 14 MB, so only when it changed
  scp -O data/hud.bin ipad:/var/mobile/Media/wmmt/
  # the course selects' 3D map of Tokyo (tools/stage/pack_mini.py, which also writes src/minicourse.h)
  [ -f data/minicourse.wpk ] || python3 tools/stage/pack_mini.py "../Wangan Midnight Maximum Tune 3DX+ (Japan)" data/minicourse.wpk src/minicourse.h
  scp -O data/minicourse.wpk ipad:/var/mobile/Media/wmmt/
  # the time attack's minimap (tools/navipack.py)
  if [ -f data/navi.bin ]; then scp -O data/navi.bin ipad:/var/mobile/Media/wmmt/; fi
  if [ "$(ssh ipad 'md5sum /var/mobile/Media/wmmt/meters.bin 2>/dev/null' | cut -d' ' -f1)" != "$(md5 -q data/meters.bin)" ]; then
    scp -O data/meters.bin ipad:/var/mobile/Media/wmmt/
  fi
  # the whole Tokyo map with its buildings, morning and night (tools/stage/pack_tokyo.sh);
  # 197 MB each, so only when they changed
  for m in tokyo tokyo_night; do
    if [ -f data/$m.wpk ] && [ "$(ssh ipad "md5sum /var/mobile/Media/wmmt/$m.wpk 2>/dev/null" | cut -d' ' -f1)" != "$(md5 -q data/$m.wpk)" ]; then
      scp -O data/$m.wpk ipad:/var/mobile/Media/wmmt/
    fi
  done
  # junction arrow boards and sky boxes (also from pack_tokyo.sh), street and building
  # lights (tools/stage/pack_lights.py); small, so always
  scp -O data/arrows.wpk data/arrows.names data/sky.wpk ipad:/var/mobile/Media/wmmt/
  for f in data/arrows_night.wpk data/sky_night.wpk data/lights.wpk data/lights.bin data/neon.wpk; do
    if [ -f $f ]; then scp -O $f ipad:/var/mobile/Media/wmmt/; fi
  done
  # the stickers by car (tools/stage/pack_vinyl.py; 30 MB in all, so only when they changed)
  if [ -d data/vinyl ] && [ "$(ssh ipad 'cat /var/mobile/Media/wmmt/vinyl/*.vpk 2>/dev/null | md5sum' | cut -d' ' -f1)" != "$(cat data/vinyl/*.vpk | md5 -q)" ]; then
    ssh ipad 'mkdir -p /var/mobile/Media/wmmt/vinyl'
    scp -O data/vinyl/*.vpk ipad:/var/mobile/Media/wmmt/vinyl/
  fi
  # the other cities' maps (tools/stage/pack_city.py; 50 to 100 MB each, so only when they
  # changed) with their sky boxes, arrow boards, lights and minimaps
  for c in oosaka hakone nagoya fukuoka; do
    for f in data/$c.wpk data/${c}_night.wpk data/sky_$c.wpk data/sky_${c}_night.wpk data/arrows_$c.wpk \
             data/arrows_${c}_night.wpk data/arrows_$c.names data/lights_$c.bin data/navi_$c.bin; do
      if [ -f $f ] && [ "$(ssh ipad "md5sum /var/mobile/Media/wmmt/$(basename $f) 2>/dev/null" | cut -d' ' -f1)" != "$(md5 -q $f)" ]; then
        scp -O $f ipad:/var/mobile/Media/wmmt/
      fi
    done
  done
  # arcade memory image for the physics (tools/recomp/build_phys.sh); 6.6 MB, so only when it changed
  if [ "$(ssh ipad 'md5sum /var/mobile/Media/wmmt/phys.img 2>/dev/null' | cut -d' ' -f1)" != "$(md5 -q data/phys.img)" ]; then
    scp -O data/phys.img ipad:/var/mobile/Media/wmmt/
  fi
  # the arcade's race config (yt::CConfigLoader: the story's rivals, the 10-in-a-row); small, so always
  mkdir -p data/carconfig
  cp "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/carconfig/"ytConfig*.txt data/carconfig/
  ssh ipad 'mkdir -p /var/mobile/Media/wmmt/carconfig'
  scp -O data/carconfig/*.txt ipad:/var/mobile/Media/wmmt/carconfig/
  # the story's realtime movies (YOURTMOVIE_CPP: table and trails, 8 MB); only when the iPad has fewer files
  RT="../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/rtmovie"
  if [ "$(ssh ipad 'ls /var/mobile/Media/wmmt/rtmovie/trail 2>/dev/null | wc -l' | tr -d ' ')" != "$(ls "$RT/trail" | wc -l | tr -d ' ')" ]; then
    ssh ipad 'mkdir -p /var/mobile/Media/wmmt/rtmovie'
    scp -O -r "$RT/table" "$RT/trail" ipad:/var/mobile/Media/wmmt/rtmovie/
  fi
  # the story's in-race lines (Cut::clCutIn); small, so always
  ssh ipad 'mkdir -p /var/mobile/Media/wmmt/cutin/jp'
  scp -O data/cutin/jp/*.txt ipad:/var/mobile/Media/wmmt/cutin/jp/
  # front-end sprites and animations (tools/menupack.py); 18 MB, so only when it changed
  if [ "$(ssh ipad 'md5sum /var/mobile/Media/wmmt/menu.bin 2>/dev/null' | cut -d' ' -f1)" != "$(md5 -q data/menu.bin)" ]; then
    scp -O data/menu.bin ipad:/var/mobile/Media/wmmt/
  fi
  # the attract movies (prepare_movie.sh); 10-30 MB each, so only when they changed
  for m in intro playdemo tutorial; do
    if [ -f data/$m.mp4 ] && [ "$(ssh ipad "md5sum /var/mobile/Media/wmmt/$m.mp4 2>/dev/null" | cut -d' ' -f1)" != "$(md5 -q data/$m.mp4)" ]; then
      scp -O data/$m.mp4 ipad:/var/mobile/Media/wmmt/
    fi
  done
  # the car-select models (tools/stage/pack_cars.py); ~130 MB in all, so only the files that changed
  if [ -d data/cars ]; then
    ssh ipad 'mkdir -p /var/mobile/Media/wmmt/cars'
    have="$(ssh ipad 'cd /var/mobile/Media/wmmt/cars && md5sum * 2>/dev/null' || true)"
    for f in data/cars/*; do
      n=$(basename "$f")
      if ! printf '%s\n' "$have" | grep -q "^$(md5 -q "$f")  $n\$"; then
        scp -O "$f" ipad:/var/mobile/Media/wmmt/cars/
      fi
    done
  fi
  # the dress-up wheels and their GET screen models (tools/stage/pack_cars.py --wheels); ~120 MB, so only the files that changed
  if [ -d data/wheels ]; then
    ssh ipad 'mkdir -p /var/mobile/Media/wmmt/wheels'
    have="$(ssh ipad 'cd /var/mobile/Media/wmmt/wheels && md5sum * 2>/dev/null' || true)"
    for f in data/wheels/*.wpk; do
      n=$(basename "$f")
      if ! printf '%s\n' "$have" | grep -q "^$(md5 -q "$f")  $n\$"; then
        scp -O "$f" ipad:/var/mobile/Media/wmmt/wheels/
      fi
    done
  fi
  # the story rivals' own cars (tools/stage/pack_cars.py --chara); ~70 MB, so only the files that changed
  if [ -d data/chara ]; then
    ssh ipad 'mkdir -p /var/mobile/Media/wmmt/chara'
    have="$(ssh ipad 'cd /var/mobile/Media/wmmt/chara && md5sum * 2>/dev/null' || true)"
    for f in data/chara/*.wpk data/chara/*.ao; do
      [ -f "$f" ] || continue
      n=$(basename "$f")
      if ! printf '%s\n' "$have" | grep -q "^$(md5 -q "$f")  $n\$"; then
        scp -O "$f" ipad:/var/mobile/Media/wmmt/chara/
      fi
    done
  fi
  # the menu and race BGM (prepare_bgm.sh encodes what is missing); ~60 MB, so only the files that changed
  sh prepare_bgm.sh
  ssh ipad 'mkdir -p /var/mobile/Media/wmmt/sound/bgm'
  have="$(ssh ipad 'cd /var/mobile/Media/wmmt/sound/bgm && md5sum * 2>/dev/null' || true)"
  for f in data/sound/bgm/*.m4a; do
    n=$(basename "$f")
    if ! printf '%s\n' "$have" | grep -q "^$(md5 -q "$f")  $n\$"; then
      scp -O "$f" ipad:/var/mobile/Media/wmmt/sound/bgm/
    fi
  done
  # the sound effects and every car's engine loops (prepare_sound.sh); only the files that changed
  [ -f data/sound/engine/rx714.wav ] && [ -f data/sound/rank.wav ] || sh prepare_sound.sh
  ssh ipad 'mkdir -p /var/mobile/Media/wmmt/sound/engine'
  for d in sound sound/engine; do
    have="$(ssh ipad "cd /var/mobile/Media/wmmt/$d && md5sum *.wav 2>/dev/null" || true)"
    new=""
    for f in data/$d/*.wav; do
      if ! printf '%s\n' "$have" | grep -q "^$(md5 -q "$f")  $(basename "$f")\$"; then new="$new $f"; fi
    done
    if [ -n "$new" ]; then scp -O $new ipad:/var/mobile/Media/wmmt/$d/; fi
  done
  # the app runs as mobile: data copied in as root must stay readable
  ssh ipad 'chown -R mobile:mobile /var/mobile/Media/wmmt; chmod -R a+rX /var/mobile/Media/wmmt'
  scp -O -r "$APP" ipad:/Applications/
  ssh ipad 'chown -R root:wheel /Applications/WMMT.app; chmod 755 /Applications/WMMT.app/WMMT; su mobile -c uicache'
  echo "deployed; tap the Wangan 3DX+ Portable icon on the iPad"
fi
