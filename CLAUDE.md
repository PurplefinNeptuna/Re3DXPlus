# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Re3DX+ is an unofficial native port of the arcade game *Wangan Midnight Maximum Tune 3DX+* to iOS 6 (iPad 3, iPhone 4) and Android (arm64). The arcade's physics and race logic are statically recompiled from its i386 executable to C; everything else is rewritten from reverse engineering. `README.en.md` has the full asset-conversion table.

## No original content in git

The repo holds only the port's code and tools. The arcade data, anything derived from it (`data/`, generated headers, `src/phys/phys_rc.c`, `tools/*.json`, `tools/*_texts.txt`) and build output must never be committed. `.gitignore` covers what the tools generate today; a new generated file has to be added to it, so check `git status` before staging.

A clean checkout does not compile: `src/*.c` includes generated headers (`cardb.h`, `storysel.h`, ...) that step 1 below creates. To fix a wrong value in one of those files, change the tool that generates it. The output is deterministic for a given copy of the original.

## Commands

The original data is expected next to the repo, as `../Wangan Midnight Maximum Tune 3DX+ (Japan)/` (containing `main` and `data/`). Python tools need `pip install capstone unicorn pillow numpy`, plus `c++filt`.

```sh
# 1. Generated headers, tool lists, recompiled physics, data/phys.img
sh tools/gen_from_original.sh --phys          # optional first arg: path to the original
sh tools/recomp/build_phys.sh <path/to/main>  # physics only

# 2. Assets into data/, on all threads but 2 (JOBS=<n> overrides; README.en.md's table lists the steps)
sh tools/convert_assets.sh                    # optional first arg: path to the original

# Android (no Gradle). Defaults assume macOS, so set ANDROID_HOME and JAVA_HOME on Linux
./build_android.sh           # build/WMMT3DX-android.apk (Vulkan)
VK=0 ./build_android.sh      # OpenGL ES 3 build
./build_android.sh install   # build + adb install
./build_android.sh data      # build + install + push data/ to the phone

# iOS. macOS only (xcrun, plutil, sips, md5), plus the theos iPhoneOS9.3 SDK and ldid
./build.sh ipa               # iPad
PHONE=1 ./build.sh ipa       # iPhone 4
./build.sh deploy            # jailbroken iPad over the ssh host alias `ipad`

python3 tools/vs_server.py [port]   # online versus server, UDP 27015 by default
```

There is no linter, formatter, CI or test runner. Each `test/*.c` is a standalone desktop program that prints results for a human to read, with its build line and arguments in its header comment. To run one:

```sh
cc -O1 -ffp-contract=off -DWMMT_EGL -DRC_FPT=double -Isrc -Isrc/phys test/rival_test.c src/car.c \
  src/phys/rc_runtime.c src/phys/phys_rc.c -lm && ./a.out data 0 <type> <pack> <char> <level> <frames>
```

Some header comments have drifted, so treat them as a starting point:
- `test/sim.c` targets the old `car_update` and collision API and no longer matches `car.h`.
- `test/ten_test.c`'s build line names `rival_test.c`.
- A race with a rival also needs `<data dir>/carconfig/ytConfig*.txt`, copied from the original. Without them `car_start` hangs with no error. `build_android.sh data` copies them.
- `test/menushot.c`'s source list omits files `app.c` now needs (`lights`, `spark`, `net`, `vs_host`, `title`, `gk`).

`test/menushot.c` is the way to see the real game without a device: it scripts taps and frames and saves screenshots on Mesa GLES2 (`EGL_PLATFORM=surfaceless ./a.out <data dir> <script>`). It writes saves (`slot`, `garage<n>`, `records<n>`, `perf.log`) into the data dir, so point it at a folder of symlinks to `data/*`, and wait several hundred frames before each tap because taps during a screen's fade or load are dropped. `src/app.c` and `src/car.c` also read `WMMT_*` debug environment variables, such as `WMMT_PILOT`, where the arcade's own pilot steers the player's car at full throttle, and `WMMT_HQ_LEVEL`, which locks a `render_hq` level and turns the governor off. On Android, pass them at launch: `am start -n com.wmmt.port/.MainActivity --es env "'WMMT_HQ_LEVEL=5;WMMT_PILOT=1'"`.

## Architecture

**Layers.** The platform shells are `main.m` + `sound_ios.m` + `gk_ios.m` on iOS, and `MainActivity.java` + `main_android.c` + `gk.c` (a no-Bluetooth stub) on Android. Both drive the same game through `app.h`. `app.c` holds the game loop and global state `G`, and calls into `menu.c` (front end), `hud.c`, `render.c` (`.wpk` scenes), `car.c`, `sound.c` and `net.c`.

**Recompiled arcade code (`car.c` ↔ `phys_rc.c`).**
- `tools/recomp/recomp.py` translates the functions reachable from `tools/recomp/roots.txt` into C, keeping the i386 machine model: registers in `rc_cpu`, the original stack discipline, and a flat 32-bit address space reached through `VA()`, `M32` and `W32` (`src/phys/rc_runtime.h`).
- `car.c` is the only bridge. It calls generated functions by address (`f_89bcca8`) by pushing arguments on the emulated stack, and it reads and writes arcade structs at raw offsets.
- `data/phys.img` is the arcade's memory image after its static constructors, and each `car_start` reloads it.
- To reach more arcade logic, add its mangled symbol to `roots.txt` and regenerate. Non-logic code (display, sound, files) is stubbed to return 0; `STUB_IMPL` and `HOOKS` in `recomp.py` give the stubs that must answer differently or call back into the port (`rc_on_hook`).

**Bit-exact physics.** Behaviour must match the arcade, and versus machines must agree.
- Compile with `-ffp-contract=off` and `-DRC_FPT=double`. Every file that includes `rc_runtime.h` must use the same `RC_FPT`, because the default on x86 is `long double`.
- `car_update` is exactly one 60 Hz arcade frame and takes no `dt`. `app_frame` rounds its `dt` to a count of vsyncs and steps that many times.
- Above 60 Hz (`app_refresh`, which Android calls with the display's real rate), `race_ticks` still gives 60 ticks a second, and `car_blend` draws poses between the last two ticks into `G.car`, restored from `G.car_real` at the top of the next `app_frame`. Physics, input (`hud_input`) and `snd_update` run only on ticks. Anything in the race that counts draw calls instead of ticks runs at double speed on a 120 Hz display.
- Above 60 Hz the quality governor starts at and never climbs above `render_hq` level 5 (`GOV_FAST_BEST`, from a benchmark on one tablet), and can still step down.
- `WMMT_HZ=120` on `test/menushot.c` runs a 120 Hz display on desktop. A race there must match the 60 Hz run's positions at tick k (its frame 2k against the 60 Hz run's frame k).
- World units are 0.1 m, with +y up.

**Rendering: one GLES2 code path, three backends.** The game only makes GLES2 calls, and `src/gl.h` selects the backend: real GLES on iOS, Mesa or EGL with `-DWMMT_EGL`, and `vkgl.c` (GLES on Vulkan) with `-DWMMT_VK`. Android's Vulkan build passes both flags, and `WMMT_VK` wins in `gl.h`.

**Changing a shader needs an extra step on Vulkan.** Shaders are GLSL ES 1.0 strings in the C code. Vulkan finds precompiled SPIR-V by an FNV-1a hash of the exact source and attribute names, so any edit changes the key. A program with no match **draws nothing and only logs** `not in vkgl_spv.c: not drawn`. To add the new version:
1. Run the game on the phone. It dumps the missing program as `<key>.txt` in its save folder (`VKGL_MISSING_DIR`).
2. Move that file into `tools/vkprogs/` and delete the old key's file.
3. Rebuild. `build_android.sh` regenerates `src/vkgl_spv.c` through `tools/vkglsl.py`.

**Front end.** `menu.c` plays the arcade's own `.anm` animations and sprites from `data/menu.bin`, rather than laying out its own screens. Screen layout is 1024×768 (`.anm` coordinates are 640×480). Wider screens use `app_wide`, and `app_console` turns off the iPhone's cuts on Android.

**Versus.** `net.c` is the client. Two servers speak the same UDP protocol, so change them together: `tools/vs_server.py` and `src/vs_host.c` (LAN and Bluetooth host inside the app). Race packets are the arcade's own cabinet link, passed through `car_set_versus`. The protocol is documented at the top of `vs_server.py`.

**Binary formats** are documented in the docstrings of their packers: `.wpk` in `tools/stage/pack.py`, `menu.bin` and `.anm` in `tools/menupack.py`. Keep the packer and its C reader in sync.

## Things that must be updated together

- **New `.c` file:** add it to the explicit source lists in both `build.sh` and `build_android.sh`, which differ. For example, `collide.c` is only in Android's list, and nothing but `test/sim.c` uses it.
- **New data file:** add it to `build.sh`'s `ipa` and `deploy` lists and check that `build_android.sh data` picks it up; each has its own list.
- **New generated header or list:** add its tool to `tools/gen_from_original.sh`, in order, because some tools read earlier output (`namedb.py` and `tendb.py` import `menupack.py`, which reads the story headers).

## Conventions

Comments tie the code to the original binary by naming arcade symbols, addresses and struct offsets (`clRaceThread::race`, `SInfoCarEffect +0x68`, `0x97fda04`). This is the project's reverse-engineering record, so keep it and add the same references to new code. C is `gnu99` with 2-space indents. The Chinese `README.md` is the authoritative text of the legal notices.
