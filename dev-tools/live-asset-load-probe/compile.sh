#!/usr/bin/env bash
# Compiles probe.c into $1/live-asset-load-probe (+ its data files under
# $1/res). No push -- see dev-tools/probes-app/. Heaviest-dependency probe
# (SDL2 + SDL2_ttf + physfs + freetype + png16); needs a TTF font supplied
# via LIVE_ASSET_TTF_FONT (no default -- point it at any real TTF).
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
addons="${MMIYOO_ADDONS_PREFIX:-$repo_root/work/sdl2-mmiyoo-addons/bundle}"
physfs_build="${PHYSFS_BUILD_DIR:-$repo_root/work/blobbyvolley2-mmiyoo/physfs-build}"
physfs_src="${PHYSFS_SRC_DIR:-$repo_root/work/blobbyvolley2-mmiyoo/src/physfs/src}"
bv2_app_dist="${BLOBBYVOLLEY2_APP_DIST:-$repo_root/work/blobbyvolley2-mmiyoo/app-dist/BlobbyVolley2}"
runtime_libs="${RUNTIME_LIBS_DIR:-$repo_root/work/love-mmiyoo-demo/sysroot-libs}"
ttf_font="${LIVE_ASSET_TTF_FONT:-}"
out_dir="${1:?usage: compile.sh <out_dir>}"

for req in "$sdl2_bundle/lib/libSDL2-2.0.so.0" "$addons/lib/libSDL2_ttf-2.0.so.0.2000.2" \
           "$physfs_build/libphysfs.a" "$bv2_app_dist/gfx.zip" "$runtime_libs/libfreetype.so.6"; do
  [[ -f "$req" ]] || { printf 'missing prerequisite: %s\n' "$req" >&2; exit 1; }
done
[[ -n "$ttf_font" && -f "$ttf_font" ]] || {
  printf 'LIVE_ASSET_TTF_FONT must point at a real .ttf file (got: %s)\n' "${ttf_font:-<unset>}" >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
mkdir -p "$out_dir/res"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro \
  -v "$sdl2_bundle":/opt/sdl2:ro -v "$addons":/opt/addons:ro \
  -v "$physfs_build":/opt/physfs:ro -v "$physfs_src":/opt/physfs-src:ro \
  -v "$out_dir":/workspace/out \
  "$image" /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc -O2 -g -no-pie \
  -I/opt/sdl2/include -I/opt/sdl2/include/SDL2 -I/opt/addons/include -I/opt/addons/include/SDL2 -I/opt/physfs-src \
  /workspace/src/probe.c \
  -L/opt/sdl2/lib -L/opt/addons/lib -L/opt/physfs -lSDL2 -lSDL2_ttf -lphysfs -lz -lm -lfreetype -lEGL -lGLESv2 -lneonarmmiyoo \
  -Wl,-rpath-link=/opt/addons/lib -Wl,-rpath-link=/opt/sdl2/lib \
  -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
  -o /workspace/out/live-asset-load-probe

install -m 644 "$bv2_app_dist/gfx.zip" "$out_dir/res/gfx.zip"
install -m 644 "$bv2_app_dist/backgrounds.zip" "$out_dir/res/backgrounds.zip"
install -m 644 "$bv2_app_dist/Icon.bmp" "$out_dir/res/Icon.bmp"
install -m 644 "$ttf_font" "$out_dir/res/font.ttf"

printf '%s\n' "$out_dir/live-asset-load-probe"
