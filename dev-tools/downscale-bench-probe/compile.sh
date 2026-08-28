#!/usr/bin/env bash
# Compiles probe.c into $1/downscale-bench-probe (+ its on-screen-text font
# under $1/res). No push -- see dev-tools/probes-app/. Needs a TTF/OTF font
# supplied via FONT_PATH (no default -- point it at any real font file).
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
font_path="${FONT_PATH:-}"
out_dir="${1:?usage: compile.sh <out_dir>}"

[[ -f "$sdl2_bundle/lib/libneonarmmiyoo.so" && -f "$sdl2_bundle/include/SDL2/neon.h" ]] || {
  printf 'sdl2-mmiyoo-lib not built -- run: scripts/build-package.sh sdl2-mmiyoo-lib\n' >&2
  exit 1
}
[[ -n "$font_path" && -f "$font_path" ]] || {
  printf 'FONT_PATH must point at a real .ttf/.otf file (got: %s)\n' "${font_path:-<unset>}" >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
mkdir -p "$out_dir/res"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro \
  -v "$sdl2_bundle":/opt/mmiyoo-sdl2:ro \
  -v "$out_dir":/workspace/out \
  "$image" /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc -O2 -g \
  -I/opt/mmiyoo-sdl2/include/SDL2 \
  -I/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/include/freetype2 \
  /workspace/src/probe.c \
  -L/opt/mmiyoo-sdl2/lib -lneonarmmiyoo -lmi_sys -lmi_gfx -lcam_os_wrapper -ldl -lfreetype -lm \
  -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
  -o /workspace/out/downscale-bench-probe

install -m 644 "$font_path" "$out_dir/res/font.otf"

printf '%s\n' "$out_dir/downscale-bench-probe"
