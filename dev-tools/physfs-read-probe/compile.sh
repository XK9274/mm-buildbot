#!/usr/bin/env bash
# Compiles probe.c into $1/physfs-read-probe (+ copies gfx.zip alongside for
# a manual run). No push -- see dev-tools/probes-app/.
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

physfs_build="${PHYSFS_BUILD_DIR:-$repo_root/work/blobbyvolley2-mmiyoo/physfs-build}"
physfs_src="${PHYSFS_SRC_DIR:-$repo_root/work/blobbyvolley2-mmiyoo/src/physfs/src}"
gfx_zip="${GFX_ZIP:-$repo_root/work/blobbyvolley2-mmiyoo/app-dist/BlobbyVolley2/gfx.zip}"
out_dir="${1:?usage: compile.sh <out_dir>}"

[[ -f "$physfs_build/libphysfs.a" ]] || {
  printf 'libphysfs.a not found at %s -- run: scripts/build-package.sh blobbyvolley2-mmiyoo\n' "$physfs_build" >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
mkdir -p "$out_dir/res"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro \
  -v "$physfs_build":/opt/physfs-build:ro \
  -v "$physfs_src":/opt/physfs-src:ro \
  -v "$out_dir":/workspace/out \
  "$image" /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc -O2 -g \
  -I/opt/physfs-src \
  /workspace/src/probe.c \
  -L/opt/physfs-build -lphysfs -lz -lm \
  -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
  -o /workspace/out/physfs-read-probe

if [[ -f "$gfx_zip" ]]; then
  install -m 644 "$gfx_zip" "$out_dir/res/gfx.zip"
else
  printf 'WARNING: gfx.zip not found at %s -- physfs-read-probe needs it at runtime\n' "$gfx_zip" >&2
fi

printf '%s\n' "$out_dir/physfs-read-probe"
