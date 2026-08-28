#!/usr/bin/env bash
set -euo pipefail
script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"
sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
addons="$repo_root/work/sdl2-mmiyoo-addons/bundle"
physfs_build="$repo_root/work/blobbyvolley2-mmiyoo/physfs-build"
physfs_src="$repo_root/work/blobbyvolley2-mmiyoo/src/physfs/src"
stage_dir="$repo_root/work/live-asset-load-probe/stage"
app_dir="$repo_root/work/blobbyvolley2-mmiyoo/app-dist/BlobbyVolley2"
runtime_libs="$repo_root/work/love-mmiyoo-demo/sysroot-libs"
image="$(ensure_union_toolchain_image)"
rm -rf "$stage_dir"; mkdir -p "$stage_dir/lib"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro -v "$sdl2_bundle":/opt/sdl2:ro \
  -v "$addons":/opt/addons:ro -v "$physfs_build":/opt/physfs:ro \
  -v "$physfs_src":/opt/physfs-src:ro -v "$stage_dir":/workspace/out \
  "$image" /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc -O2 -g -no-pie \
  -I/opt/sdl2/include -I/opt/sdl2/include/SDL2 -I/opt/addons/include -I/opt/addons/include/SDL2 -I/opt/physfs-src /workspace/src/probe.c \
  -L/opt/sdl2/lib -L/opt/addons/lib -L/opt/physfs -lSDL2 -lSDL2_ttf -lphysfs -lz -lm -lfreetype -lEGL -lGLESv2 -lneonarmmiyoo \
  -Wl,-rpath-link=/opt/addons/lib -Wl,-rpath-link=/opt/sdl2/lib \
  -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib -o /workspace/out/probe
for f in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do install -m 755 "$sdl2_bundle/lib/$f" "$stage_dir/lib/$f"; done
install -m 755 "$addons/lib/libSDL2_ttf-2.0.so.0.2000.2" "$stage_dir/lib/libSDL2_ttf-2.0.so.0"
install -m 755 "$app_dir/lib/libz.so.1" "$stage_dir/lib/"
install -m 755 "$runtime_libs/libfreetype.so.6" "$stage_dir/lib/"
install -m 755 "$runtime_libs/libpng16.so.16" "$stage_dir/lib/"
install -m 644 "$app_dir/gfx.zip" "$stage_dir/gfx.zip"
install -m 644 "$app_dir/backgrounds.zip" "$stage_dir/backgrounds.zip"
install -m 644 "$app_dir/Icon.bmp" "$stage_dir/Icon.bmp"
install -m 644 /home/mattpc/HueTesting/pokedex_miyoo/App/Retrodex/res/assets/font/pokemon-dppt/pokemon-dppt.ttf "$stage_dir/pokemon-dppt.ttf"
printf 'Built local probe at %s/probe\n' "$stage_dir"
printf 'No device push performed. Manual run after transfer:\n'
printf '  LD_LIBRARY_PATH=./lib:/config/lib ./probe gfx.zip backgrounds.zip pokemon-dppt.ttf 1000 800\n'
printf '  LD_LIBRARY_PATH=./lib:/config/lib ./probe gfx.zip backgrounds.zip pokemon-dppt.ttf 1000 640\n'
printf '  LD_LIBRARY_PATH=./lib:/config/lib ./probe gfx.zip backgrounds.zip pokemon-dppt.ttf 1000 mixed\n'
printf '  LD_LIBRARY_PATH=./lib:/config/lib ./probe gfx.zip backgrounds.zip pokemon-dppt.ttf 1000 oversized\n'
