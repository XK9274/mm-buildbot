#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
root="${2:?repo root required}"
host_root="${3:?host root required}"
source_dir="${4:?source directory required}"
shift 4

binary="$host_root/build/src/blobby"
[[ -x "$binary" ]] || {
  printf 'Blobby host binary is missing: %s\n' "$binary" >&2
  exit 1
}
[[ -d "$source_dir/data" ]] || {
  printf 'Blobby runtime data directory is missing: %s/data\n' "$source_dir" >&2
  exit 1
}

export HOME="${HOST_HOME:-$host_root/home}"
mkdir -p "$HOME"

printf '[%s host] Running from %s\n' "$package_id" "$source_dir"
cd "$source_dir"
exec "$binary" "$@"
