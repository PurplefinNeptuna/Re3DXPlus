#!/bin/sh
# Build the Android port (build/WMMT3DX-android.apk: arm64-v8a, Android 9+, Vulkan (src/vkgl.c;
# VK=0 for OpenGL ES 3) + AAudio) with the SDK's build-tools and the NDK, no Gradle. Usage:
#   ./build_android.sh            the apk
#   ./build_android.sh install    and adb install it (the phone on USB with USB debugging on)
#   ./build_android.sh data       and push the game data (as build.sh deploy's) to the phone:
#                                 /sdcard/Android/data/com.wmmt.port/files/wmmt (once; big)
set -e
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
BT="$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)"
PLAT="$SDK/platforms/$(ls "$SDK/platforms" | sort -V | tail -1)"
NDK="$SDK/ndk/$(ls "$SDK/ndk" | sort -V | tail -1)"
HOST=$(ls "$NDK/toolchains/llvm/prebuilt" | head -1)
API=28
CC="$NDK/toolchains/llvm/prebuilt/$HOST/bin/aarch64-linux-android$API-clang"
ADB="$SDK/platform-tools/adb"; [ -x "$ADB" ] || ADB=adb
# all threads but 2, left for the system (JOBS= overrides)
JOBS="${JOBS:-$(( $(getconf _NPROCESSORS_ONLN) - 2 ))}"; [ "$JOBS" -ge 1 ] || JOBS=1
OUT=build/android
rm -rf "$OUT/apk" "$OUT/classes" && mkdir -p "$OUT/apk/lib/arm64-v8a" "$OUT/classes" "$OUT/obj"

# the programs' SPIR-V for Vulkan (tools/vkglsl.py) from their sources (tools/vkprogs: a new
# one the game meets is written to the phone's save folder, <key>.txt, to put there), by the
# NDK's glslc unless there is a glslangValidator
VK="${VK:-1}"
if [ "$VK" = 1 ]; then
  GLSLC="$NDK/shader-tools/$HOST/glslc"
  if ! command -v glslangValidator >/dev/null 2>&1 && [ -x "$GLSLC" ]; then export VKGLSL_CC="$GLSLC"; fi
  if [ ! -f src/vkgl_spv.c ] || [ -n "$(find tools/vkprogs tools/vkglsl.py -newer src/vkgl_spv.c | head -1)" ]; then
    echo "the programs to SPIR-V..."
    python3 tools/vkglsl.py table tools/vkprogs src/vkgl_spv.c
  fi
  GFX="-DWMMT_VK"
  GFX_SRC="src/vkgl.c src/vkgl_spv.c"
  GFX_LIBS="-lvulkan"
else
  GFX=""
  GFX_SRC=""
  GFX_LIBS="-lEGL -lGLESv2"
fi

# the native library: the game as on iOS, with main_android.c for main.m and sound_ios.m
if [ ! -f "$OUT/obj/phys_rc.o" ] || [ src/phys/phys_rc.c -nt "$OUT/obj/phys_rc.o" ]; then
  echo "compiling the arcade physics (takes a minute)..."
  $CC -O2 -fPIC -ffp-contract=off -DRC_FPT=double -w -c src/phys/phys_rc.c -o "$OUT/obj/phys_rc.o"
fi
# (xargs fails if any of the compilers does)
SRCS="src/main_android.c src/app.c src/render.c src/hud.c src/car.c src/collide.c src/sound.c src/anm.c src/menu.c
  src/lights.c src/spark.c src/net.c src/vs_host.c src/title.c src/gk.c src/phys/rc_runtime.c $GFX_SRC"
# (-ffp-contract=off: car.c works on the physics' floats, and a fused multiply-add rounds differently)
CFLAGS="-O2 -fPIC -ffp-contract=off -std=gnu99 -Wall -Wno-unused-function -DRC_FPT=double -DWMMT_EGL $GFX -mcpu=cortex-a73"
rm -f "$OUT"/obj/game_*.o
printf '%s\n' $SRCS | xargs -P "$JOBS" -I{} \
  sh -c '$0 $1 -c "{}" -o "$2/game_$(basename "{}" .c).o"' "$CC" "$CFLAGS" "$OUT/obj"
$CC -shared "$OUT"/obj/game_*.o "$OUT/obj/phys_rc.o" \
  -o "$OUT/apk/lib/arm64-v8a/libwmmt.so" \
  -landroid $GFX_LIBS -laaudio -llog -lz -lm -Wl,-z,max-page-size=16384

# the Java side
"$JAVA_HOME/bin/javac" -source 8 -target 8 -nowarn -classpath "$PLAT/android.jar" -d "$OUT/classes" \
  android/java/com/wmmt/port/MainActivity.java
"$BT/d8" --min-api $API --lib "$PLAT/android.jar" --output "$OUT/apk" $(find "$OUT/classes" -name '*.class')

# the manifest and icon, then the apk, aligned and signed with a key of its own
[ -f data/icon/Icon-76@2x.png ] || python3 tools/make_icon.py
mkdir -p "$OUT/res/mipmap"
cp data/icon/Icon-76@2x.png "$OUT/res/mipmap/icon.png"
"$BT/aapt2" compile --dir "$OUT/res" -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$PLAT/android.jar" --manifest android/AndroidManifest.xml \
  --min-sdk-version $API --target-sdk-version 33 --version-code 1 --version-name 1.0 "$OUT/res.zip"
# (the library stored, not deflated, and page-aligned: it is mapped from the apk as it is)
python3 - "$OUT" <<'PY'
import sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out + "/base.apk", "a") as z:
    z.write(out + "/apk/classes.dex", "classes.dex", zipfile.ZIP_DEFLATED)
    z.write(out + "/apk/lib/arm64-v8a/libwmmt.so", "lib/arm64-v8a/libwmmt.so", zipfile.ZIP_STORED)
PY
"$BT/zipalign" -f -P 16 4 "$OUT/base.apk" "$OUT/aligned.apk"
KS="$OUT/wmmt.keystore"
[ -f "$KS" ] || "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storepass wmmtport -keypass wmmtport \
  -alias wmmt -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=WMMT3DX port" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:wmmtport --key-pass pass:wmmtport --out build/WMMT3DX-android.apk "$OUT/aligned.apk"
echo "built $(pwd)/build/WMMT3DX-android.apk"

if [ "$1" = "install" ] || [ "$1" = "data" ]; then
  "$ADB" install -r build/WMMT3DX-android.apk
fi
if [ "$1" = "data" ]; then
  # the game data as the iPad has it (build.sh deploy's list), in the app's own folder
  D=/sdcard/Android/data/com.wmmt.port/files/wmmt
  "$ADB" shell mkdir -p $D
  for f in data/*.wpk data/*.wcl data/*.bin data/*.names data/*.img data/*.mp4; do
    if [ -f "$f" ]; then "$ADB" push --sync "$f" $D/; fi
  done
  mkdir -p data/carconfig
  cp "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/carconfig/"ytConfig*.txt data/carconfig/
  mkdir -p data/cutin/jp
  cp -n "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/cutin/jp/"*.txt data/cutin/jp/  # (-n: tools/convert_en.sh's English stays)
  for d in traffic carconfig cars chara sound wheels vinyl cutin; do
    if [ -d data/$d ]; then "$ADB" push --sync data/$d $D/; fi
  done
  "$ADB" shell mkdir -p $D/rtmovie
  "$ADB" push --sync "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/rtmovie/table" "../Wangan Midnight Maximum Tune 3DX+ (Japan)/data/rtmovie/trail" $D/rtmovie/
  echo "data pushed to $D"
fi
