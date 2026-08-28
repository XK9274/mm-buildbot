#!/usr/bin/env bash
# Dev-only tool, not a formal mm-buildbot package (see docs/package-config.md --
# its schema expects a real upstream source, this probe's C file is authored
# inline). Cross-compiles dev-tools/oversize-composite-probe/probe.c against
# an already-built sdl2-mmiyoo-lib bundle and pushes it to the device.
#
# Usage:
#   scripts/build-package.sh sdl2-mmiyoo-lib   # build the driver bundle first
#     (with SDL2_MIYOO_REPO/REF/NEON_REF pointed at the branches under test)
#   dev-tools/oversize-composite-probe/build-and-push.sh
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
stage_dir="$repo_root/work/oversize-composite-probe/stage"
device_ip="${MMIYOO_DEVICE_IP:-192.168.1.78}"
device_user="${MMIYOO_DEVICE_USER:-onion}"
device_pass="${MMIYOO_DEVICE_PASS:-onion}"
device_dir="${MMIYOO_DEVICE_APP_DIR:-/mnt/SDCARD/App/OversizeCompositeProbe}"

log() { printf '[oversize-composite-probe] %s\n' "$*"; }

[[ -f "$sdl2_bundle/lib/libSDL2-2.0.so.0" ]] || {
  printf 'sdl2-mmiyoo-lib bundle not found at %s -- build it first:\n' "$sdl2_bundle" >&2
  printf '  scripts/build-package.sh sdl2-mmiyoo-lib\n' >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
log "Cross-compiling probe.c in $image"
rm -rf "$stage_dir"
mkdir -p "$stage_dir/lib"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$script_dir":/workspace/src:ro \
  -v "$sdl2_bundle":/opt/mmiyoo-sdl2:ro \
  -v "$stage_dir":/workspace/out \
  "$image" \
  /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc \
    -O2 -g \
    -I/opt/mmiyoo-sdl2/include -I/opt/mmiyoo-sdl2/include/SDL2 \
    /workspace/src/probe.c \
    -L/opt/mmiyoo-sdl2/lib -lSDL2 -lEGL -lGLESv2 -lneonarmmiyoo \
    -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
    -o /workspace/out/probe

[[ -f "$stage_dir/probe" ]] || {
  printf 'Probe binary was not produced at %s/probe\n' "$stage_dir" >&2
  exit 1
}

for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
  install -m 755 "$sdl2_bundle/lib/$library" "$stage_dir/lib/$library"
done

log "Pushing to $device_user@$device_ip:$device_dir"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "mkdir -p '$device_dir/lib'"
sshpass -p "$device_pass" scp -r "$stage_dir/probe" "$stage_dir/lib" "$device_user@$device_ip:$device_dir/" 2>/dev/null || {
  # dropbear on-device has no scp/sftp -- fall back to cat-over-ssh per file.
  sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/probe'" < "$stage_dir/probe"
  sshpass -p "$device_pass" ssh "$device_user@$device_ip" "chmod 755 '$device_dir/probe'"
  for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
    sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/lib/$library'" < "$stage_dir/lib/$library"
  done
}
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "chmod 755 '$device_dir/probe'"

log "Staged at $stage_dir, pushed to $device_dir"
log "Run on-device with: cd $device_dir && LD_LIBRARY_PATH=./lib ./probe"
