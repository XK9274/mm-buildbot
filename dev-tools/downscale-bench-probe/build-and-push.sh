#!/usr/bin/env bash
# Dev-only tool, not a formal mm-buildbot package (see docs/package-config.md --
# its schema expects a real upstream source, this probe's C file is authored
# inline). Cross-compiles dev-tools/downscale-bench-probe/probe.c and pushes
# it (+ libneonarmmiyoo.so + a generated launch.sh) to the device. No SDL2 --
# raw MI_SYS/MI_GFX only, linked against the toolchain image's own baked-in
# mi_sys.h/mi_gfx.h (already declare BitBlit/QuickFill/WaitAllDone) and the
# already-built sdl2-mmiyoo-lib bundle for downscale_area_c32/n32 via
# libneonarmmiyoo.so + neon.h.
#
# Usage:
#   scripts/build-package.sh sdl2-mmiyoo-lib   # build the driver bundle first (for libneonarmmiyoo.so + neon.h)
#   dev-tools/downscale-bench-probe/build-and-push.sh [frames_per_variant]
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd)"
source "$repo_root/packages/.shared/upstream-port.sh"

sdl2_bundle="${MMIYOO_SDL2_PREFIX:-$repo_root/work/sdl2-mmiyoo-lib/bundle}"
stage_dir="$repo_root/work/downscale-bench-probe/stage"
device_ip="${MMIYOO_DEVICE_IP:-192.168.1.78}"
device_user="${MMIYOO_DEVICE_USER:-onion}"
device_pass="${MMIYOO_DEVICE_PASS:-onion}"
device_dir="${MMIYOO_DEVICE_APP_DIR:-/mnt/SDCARD/App/DownscaleBenchProbe}"
frames_per_variant="${1:-300}"

log() { printf '[downscale-bench-probe] %s\n' "$*"; }

[[ -f "$sdl2_bundle/lib/libneonarmmiyoo.so" ]] || {
  printf 'libneonarmmiyoo.so not found at %s/lib -- build sdl2-mmiyoo-lib first:\n' "$sdl2_bundle" >&2
  printf '  scripts/build-package.sh sdl2-mmiyoo-lib\n' >&2
  exit 1
}
[[ -f "$sdl2_bundle/include/SDL2/neon.h" ]] || {
  printf 'neon.h not found at %s/include/SDL2 -- build sdl2-mmiyoo-lib first\n' "$sdl2_bundle" >&2
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
    -I/opt/mmiyoo-sdl2/include/SDL2 \
    /workspace/src/probe.c \
    -L/opt/mmiyoo-sdl2/lib -lneonarmmiyoo \
    -lmi_sys -lmi_gfx -lcam_os_wrapper -ldl -lm \
    -Wl,-rpath-link=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr/lib \
    -o /workspace/out/probe

[[ -f "$stage_dir/probe" ]] || {
  printf 'Probe binary was not produced at %s/probe\n' "$stage_dir" >&2
  exit 1
}

install -m 755 "$sdl2_bundle/lib/libneonarmmiyoo.so" "$stage_dir/lib/libneonarmmiyoo.so"

# Same diagnostic instrumentation baked into blobbyvolley2-mmiyoo's
# launch.sh template (packages/blobbyvolley2-mmiyoo/templates/BlobbyVolley2/launch.sh,
# commits 6331e07/8fc0f81/3db3461 on sdl2_miyoo's neon-downscale-composite --
# dev-tools/ has no shared launch wrapper of its own to inherit) -- the
# untested MI_GFX-hardware-scale variant is structurally close enough to the
# original oversized-composite hang shape to warrant the full playbook, not
# just a bare launch.
cat > "$stage_dir/launch.sh" <<'EOF'
#!/bin/sh
cd "$(dirname "$0")"
app_dir="$(pwd)"
export LD_LIBRARY_PATH="./lib:/config/lib:$LD_LIBRARY_PATH"

rm -f "$app_dir/probe.log" "$app_dir/dmesg.log" "$app_dir/mi_status.log" "$app_dir/proc_status.log"

sh -c 'while true; do sync; sleep 0.02; done' &
sync_loop_pid=$!

sh -c 'while true; do { date +%s; dmesg -c 2>&1; echo ---; } >> "'"$app_dir"'/dmesg.log"; sleep 0.5; done' &
dmesg_poll_pid=$!

sh -c 'while true; do { date +%s; echo "=== mi_gfx0 ==="; cat /proc/mi_modules/mi_gfx/mi_gfx0 2>&1; echo "=== mi_sys0 ==="; cat /proc/mi_modules/mi_sys/mi_sys0 2>&1; echo "=== mi_disp0 ==="; cat /proc/mi_modules/mi_disp/mi_disp0 2>&1; echo ---; } >> "'"$app_dir"'/mi_status.log"; sleep 0.5; done' &
mi_status_poll_pid=$!

"$app_dir/probe" "$@" &
probe_pid=$!

sh -c '
  ppid='"$probe_pid"'
  while [ -d "/proc/$ppid" ]; do
    {
      date +%s
      echo "--- /proc/$ppid/status ---"
      cat "/proc/$ppid/status" 2>&1
      echo "--- per-thread state (pid comm state) ---"
      for t in /proc/$ppid/task/*/stat; do
        cat "$t" 2>&1
        echo
      done
      echo ---
    } >> "'"$app_dir"'/proc_status.log"
    sleep 0.1
  done
' &
proc_poll_pid=$!

wait "$probe_pid"
kill "$sync_loop_pid" "$dmesg_poll_pid" "$mi_status_poll_pid" "$proc_poll_pid" 2>/dev/null
wait 2>/dev/null
EOF
chmod 755 "$stage_dir/launch.sh"

log "Pushing to $device_user@$device_ip:$device_dir"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "mkdir -p '$device_dir/lib'"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/probe'" < "$stage_dir/probe"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/launch.sh'" < "$stage_dir/launch.sh"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cat > '$device_dir/lib/libneonarmmiyoo.so'" < "$stage_dir/lib/libneonarmmiyoo.so"
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "chmod 755 '$device_dir/probe' '$device_dir/launch.sh'"

log "Staged at $stage_dir, pushed to $device_dir"
log "Checksum-verify before running:"
log "  md5sum $stage_dir/probe $stage_dir/lib/libneonarmmiyoo.so"
log "  ssh $device_user@$device_ip md5sum $device_dir/probe $device_dir/lib/libneonarmmiyoo.so"
log "Run on-device with: cd $device_dir && ./launch.sh $frames_per_variant"
log "  frames_per_variant (default 300): frames measured per resolution/variant combo"
