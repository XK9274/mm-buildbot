#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
root="${2:?repo root required}"
host_root="${3:?host root required}"
source_dir="${4:?source directory required}"
shift 4

binary="$host_root/build/VVVVVV"
[[ -x "$binary" ]] || {
  printf 'VVVVVV host binary is missing: %s\n' "$binary" >&2
  exit 1
}

# Retail game data is proprietary and not bundled -- point this at a
# directory containing your own data.zip.
: "${VVVVVV_DATA_DIR:?Set VVVVVV_DATA_DIR to a directory containing your own data.zip}"
[[ -f "$VVVVVV_DATA_DIR/data.zip" ]] || {
  printf 'data.zip not found in VVVVVV_DATA_DIR: %s\n' "$VVVVVV_DATA_DIR" >&2
  exit 1
}
cp -f "$VVVVVV_DATA_DIR/data.zip" "$host_root/build/data.zip"

export HOME="${HOST_HOME:-$host_root/home}"
mkdir -p "$HOME"

printf '[%s host] Running from %s\n' "$package_id" "$host_root/build"
cd "$host_root/build"
exec "$binary" "$@"
