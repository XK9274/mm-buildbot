#!/bin/sh
set -eu

app_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Kill any stale instance before launching.
my_pid=$$
for stale_pid in $(pgrep -f "$app_dir/bin/konpacto" 2>/dev/null); do
  [ "$stale_pid" != "$my_pid" ] && kill -9 "$stale_pid" 2>/dev/null
done

# Stop Onion's audio server so SDL2_mixer can open the Miyoo AO device directly.
if [ -f /mnt/SDCARD/.tmp_update/script/stop_audioserver.sh ]; then
  /mnt/SDCARD/.tmp_update/script/stop_audioserver.sh || true
else
  killall audioserver audioserver.mod 2>/dev/null || true
fi

# konpacto reads/writes assets relative to its own working directory.
cd "$app_dir"

# No bare exec, so audioserver restarts on exit; set +e so that doesn't skip it.
set +e
"$app_dir/bin/konpacto"
konpacto_exit=$?
set -e

if [ -f /mnt/SDCARD/.tmp_update/script/start_audioserver.sh ]; then
  /mnt/SDCARD/.tmp_update/script/start_audioserver.sh || true
fi

exit "$konpacto_exit"
