#!/usr/bin/env bash
# Tars a local app-dist directory and pushes it to a device app directory
# over SSH, then extracts it there. Generic -- works for any app-dist
# shape (config.json/launch.sh/icon.png plus whatever bin/lib/res/data
# subdirectories the app has), not tied to any one package. This device's
# shell has no scp/sftp and its SD card filesystem supports neither
# symlinks nor hardlinks, so the tar is built with --dereference
# --hard-dereference (every entry becomes an independent regular file,
# even when multiple names share an inode, e.g. a lib's SONAME symlinks)
# and streamed over a plain `ssh ... tar xzf -`.
#
# Usage: push-app.sh <local_app_dist_dir> <device_app_name>
# Env:   MMIYOO_DEVICE_IP/USER/PASS   (defaults: 192.168.1.78/onion/onion)
#        MMIYOO_DEVICE_APP_ROOT       (default: /mnt/SDCARD/App)
set -euo pipefail

local_dir="${1:?usage: push-app.sh <local_app_dist_dir> <device_app_name>}"
app_name="${2:?usage: push-app.sh <local_app_dist_dir> <device_app_name>}"

device_ip="${MMIYOO_DEVICE_IP:-192.168.1.78}"
device_user="${MMIYOO_DEVICE_USER:-onion}"
device_pass="${MMIYOO_DEVICE_PASS:-onion}"
device_app_root="${MMIYOO_DEVICE_APP_ROOT:-/mnt/SDCARD/App}"
device_dir="$device_app_root/$app_name"

[[ -d "$local_dir" ]] || { printf 'push-app.sh: %s is not a directory\n' "$local_dir" >&2; exit 1; }

log() { printf '[push-app] %s\n' "$*"; }

log "Pushing $local_dir -> $device_user@$device_ip:$device_dir"
# Full replace, not a merge -- a stale file from a previous push of a
# different app-dist shape (e.g. fewer probes built this time) would
# otherwise linger forever and fail the checksum comparison below.
sshpass -p "$device_pass" ssh "$device_user@$device_ip" "rm -rf '$device_dir' && mkdir -p '$device_dir'"
tar --dereference --hard-dereference -C "$local_dir" -czf - . | \
  sshpass -p "$device_pass" ssh "$device_user@$device_ip" "tar -xzf - -C '$device_dir'"

# chmod anything that looks executable back to 755 -- tar preserves local
# perms, this is just a safety net for files created without +x locally.
sshpass -p "$device_pass" ssh "$device_user@$device_ip" \
  "find '$device_dir' -maxdepth 2 \\( -name 'launch.sh' -o -path '*/bin/*' \\) -exec chmod 755 {} +"

log "Checksum-verifying"
local_sums="$(cd "$local_dir" && find . -type f -exec md5sum {} + | sort)"
remote_sums="$(sshpass -p "$device_pass" ssh "$device_user@$device_ip" "cd '$device_dir' && find . -type f -exec md5sum {} + | sort")"
if [[ "$local_sums" == "$remote_sums" ]]; then
  log "OK -- all files match"
else
  log "MISMATCH -- local vs remote checksums differ:"
  diff <(printf '%s\n' "$local_sums") <(printf '%s\n' "$remote_sums") || true
  exit 1
fi

log "Deployed to $device_dir"
