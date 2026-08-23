#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?missing package id}"
root="${2:?missing repository root}"
source_dir="${3:?missing source directory}"
host_root="${4:?missing host root}"

[[ "$package_id" == "love-mmiyoo-demo" ]] || exit 1

mkdir -p "$host_root/bin" "$host_root/lib"
love_binary="$source_dir/love"
[[ -x "$love_binary" ]] || love_binary="$source_dir/src/.libs/love11.5"
[[ -x "$love_binary" ]] || {
  printf 'LÖVE host executable was not found under %s\n' "$source_dir" >&2
  exit 1
}
cp "$love_binary" "$host_root/bin/love"

love_library="$(find "$source_dir/src/.libs" -maxdepth 1 -type f -name 'liblove*.so*' -print -quit 2>/dev/null || true)"
if [[ -n "$love_library" ]]; then
  cp "$love_library" "$host_root/lib/$(basename "$love_library")"
fi
