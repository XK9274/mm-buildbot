#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?missing package id}"
root="${2:?missing repository root}"
host_root="${3:?missing host root}"
source_dir="${4:?missing source directory}"
shift 4

[[ "$package_id" == "love-mmiyoo-demo" ]] || exit 1

game_dir="$root/packages/love-mmiyoo-demo/templates/LoveMiyoo/game"
[[ -d "$game_dir" ]] || {
  printf 'LÖVE demo game directory is missing: %s\n' "$game_dir" >&2
  exit 1
}

export LD_LIBRARY_PATH="$host_root/deps/luajit/lib:$host_root/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$host_root/bin/love" "$game_dir"
