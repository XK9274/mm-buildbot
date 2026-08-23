#!/bin/sh
set -eu

app_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export HOME="$app_dir"
export LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Stop Onion's audio server so SDL2 can open the Miyoo AO device directly.
if [ -f /mnt/SDCARD/.tmp_update/script/stop_audioserver.sh ]; then
  /mnt/SDCARD/.tmp_update/script/stop_audioserver.sh || true
else
  killall audioserver audioserver.mod 2>/dev/null || true
fi

if [ -x /mnt/SDCARD/.tmp_update/bin/cpuclock ]; then
  /mnt/SDCARD/.tmp_update/bin/cpuclock 1700 || true
fi

cd "$app_dir"

set +e
"$app_dir/blobby"
blobby_exit=$?
set -e

if [ -f /mnt/SDCARD/.tmp_update/script/start_audioserver.sh ]; then
  /mnt/SDCARD/.tmp_update/script/start_audioserver.sh || true
fi

exit "$blobby_exit"
