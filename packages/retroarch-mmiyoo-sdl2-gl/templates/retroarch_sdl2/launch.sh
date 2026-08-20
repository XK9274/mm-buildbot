#!/bin/sh
set -eu

app_dir=$(dirname "$0")

export HOME="$app_dir"
export PATH="$app_dir/bin:$PATH"
export LD_LIBRARY_PATH="$app_dir/lib:/config/lib:${LD_LIBRARY_PATH:-}"

# SDL2 should auto-detect the Miyoo backend on-device. Leave SDL_MMIYOO_*
# unset unless debugging a specific backend mode.
# export SDL_MMIYOO_GEOMETRY_QUICKPATH=
export SDL_MMIYOO_FRAME_TIMING=1

# Stop Onion's audio server so SDL2 can open the Miyoo AO device directly.
if [ -f /mnt/SDCARD/.tmp_update/script/stop_audioserver.sh ]; then
  /mnt/SDCARD/.tmp_update/script/stop_audioserver.sh || true
else
  killall audioserver audioserver.mod 2>/dev/null || true
fi

mkdir -p \
  "$app_dir/logs" \
  "$app_dir/.retroarch" \
  "$app_dir/assets" \
  "$app_dir/cores" \
  "$app_dir/info" \
  "$app_dir/system" \
  "$app_dir/saves/files" \
  "$app_dir/saves/states"

# Overclock the CPU to 1700MHz for extra sdl2/Ozone rendering headroom.
if [ -x /mnt/SDCARD/.tmp_update/bin/cpuclock ]; then
  /mnt/SDCARD/.tmp_update/bin/cpuclock 1700 || true
fi

cd "$app_dir"

# Core dumps for crash-on-exit debugging (dropped as "core" or "core.PID" in
# $app_dir, depending on /proc/sys/kernel/core_pattern).
ulimit -c unlimited 2>/dev/null || true

# No `exec` here on purpose: exec would replace this shell with retroarch,
# leaving nothing behind to run once it exits, so a crash-on-exit or an
# SD-card remount-ro triggered by the exit couldn't be observed or logged.
diag_log="$app_dir/logs/launch_diag.log"
{
  echo "=== launch $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "--- mount (pre-launch) ---"
  mount | grep SDCARD
} >> "$diag_log" 2>&1

set +e
"$app_dir/bin/{{LAUNCH_TARGET}}" \
  --config "$app_dir/cfg/retroarch.cfg" \
  --menu \
  >> "$app_dir/logs/retroarch.log" 2>&1
ra_exit=$?
set -e

{
  echo "--- exit $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
  echo "retroarch exit code: $ra_exit"
  echo "--- mount (post-exit) ---"
  mount | grep SDCARD
  echo "--- dmesg tail ---"
  dmesg | tail -n 60
  if [ -f "$app_dir/core" ] || ls "$app_dir"/core.* >/dev/null 2>&1; then
    echo "--- core dump present ---"
    ls -la "$app_dir"/core* 2>/dev/null
  fi
} >> "$diag_log" 2>&1

exit "$ra_exit"
