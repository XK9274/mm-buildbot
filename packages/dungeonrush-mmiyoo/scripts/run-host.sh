#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
root="${2:?repo root required}"
host_root="${3:?host root required}"
source_dir="${4:?source directory required}"
shift 4

bin_dir="$host_root/build/bin"
binary="$bin_dir/dungeon_rush"
[[ -x "$binary" ]] || {
  printf 'DungeonRush host binary is missing: %s\n' "$binary" >&2
  exit 1
}
[[ -d "$bin_dir/res" ]] || {
  printf 'DungeonRush runtime res directory is missing: %s/res\n' "$bin_dir" >&2
  exit 1
}

export HOME="${HOST_HOME:-$host_root/home}"
mkdir -p "$HOME"

printf '[%s host] Running from %s\n' "$package_id" "$bin_dir"
cd "$bin_dir"
exec "$binary" "$@"
