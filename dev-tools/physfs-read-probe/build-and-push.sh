#!/usr/bin/env bash
# Dev-only tool, not a formal mm-buildbot package. Cross-compiles
# dev-tools/physfs-read-probe/probe.c against the physfs static lib already
# built for blobbyvolley2-mmiyoo, and pushes it (+ gfx.zip) to the device.
# No SDL2/MI_SYS/MI_GFX involved at all -- isolates whether the hang is a
# PhysFS/zlib issue on its own.
#
# Usage:
#   scripts/build-package.sh blobbyvolley2-mmiyoo   # build physfs first
#   dev-tools/physfs-read-probe/build-and-push.sh [iterations]
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

physfs_build="$repo_root/work/blobbyvolley2-mmiyoo/physfs-build"
physfs_src="$repo_root/work/blobbyvolley2-mmiyoo/src/physfs/src"
gfx_zip="$repo_root/work/blobbyvolley2-mmiyoo/app-dist/BlobbyVolley2/gfx.zip"
stage_dir="$repo_root/work/physfs-read-probe/stage"
device_ip="${MMIYOO_DEVICE_IP:-192.168.1.78}"
device_user="${MMIYOO_DEVICE_USER:-onion}"
device_pass="${MMIYOO_DEVICE_PASS:-onion}"
device_dir="${MMIYOO_DEVICE_APP_DIR:-/mnt/SDCARD/App/PhysfsReadProbe}"
iterations="${1:-20}"

log() { printf '[physfs-read-probe] %s\n' "$*"; }

[[ -f "$physfs_build/libphysfs.a" ]] || {
  printf 'libphysfs.a not found at %s -- build blobbyvolley2-mmiyoo first:\n' "$physfs_build" >&2
  printf '  scripts/build-package.sh blobbyvolley2-mmiyoo\n' >&2
  exit 1
}
[[ -f "$gfx_zip" ]] || {
  printf 'gfx.zip not found at %s -- build blobbyvolley2-mmiyoo first\n' "$gfx_zip" >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
log "Cross-compiling probe.c in $image"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro \
  -v "$physfs_build":/opt/physfs-build:ro \
  -v "$physfs_src":/opt/physfs-src:ro \
  -v "$stage_dir":/workspace/out \
  "$image" \
  /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc \
    -O2 -g \
    -I/opt/physfs-src \
    /workspace/src/probe.c \
    -L/opt/physfs-build -lphysfs -lz -lm \
    -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
    -o /workspace/out/probe

[[ -f "$stage_dir/probe" ]] || {
  printf 'Probe binary was not produced at %s/probe\n' "$stage_dir" >&2
  exit 1
}

log "Pushing to $device_user@$device_ip:$device_dir"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "mkdir -p '$device_dir'"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/probe'" < "$stage_dir/probe"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "chmod 755 '$device_dir/probe'"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/gfx.zip'" < "$gfx_zip"

log "Staged at $stage_dir, pushed to $device_dir"
log "Run on-device with: cd $device_dir && ./probe gfx.zip $iterations"
