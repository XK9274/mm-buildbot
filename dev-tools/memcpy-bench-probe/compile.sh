#!/usr/bin/env bash
# Compiles probe.c into $1/memcpy-bench-probe. No push -- see
# dev-tools/probes-app/. No font needed (no on-screen text, timing-only
# probe -- see probe.c's header comment for why).
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
out_dir="${1:?usage: compile.sh <out_dir>}"

[[ -f "$sdl2_bundle/lib/libneonarmmiyoo.so" && -f "$sdl2_bundle/include/SDL2/neon.h" ]] || {
  printf 'sdl2-mmiyoo-lib not built -- run: scripts/build-package.sh sdl2-mmiyoo-lib\n' >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
mkdir -p "$out_dir"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro \
  -v "$sdl2_bundle":/opt/mmiyoo-sdl2:ro \
  -v "$out_dir":/workspace/out \
  "$image" /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc -O2 -g \
  -I/opt/mmiyoo-sdl2/include/SDL2 \
  /workspace/src/probe.c \
  -L/opt/mmiyoo-sdl2/lib -lneonarmmiyoo -lmi_sys -lmi_gfx -lcam_os_wrapper -ldl -lm \
  -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
  -o /workspace/out/memcpy-bench-probe

printf '%s\n' "$out_dir/memcpy-bench-probe"
