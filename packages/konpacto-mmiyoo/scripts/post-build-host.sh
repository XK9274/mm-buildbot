#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?missing package id}"
root="${2:?missing repository root}"
source_dir="${3:?missing source directory}"
host_root="${4:?missing host root}"

[[ "$package_id" == "konpacto-mmiyoo" ]] || exit 1

mkdir -p "$host_root/bin"
konpacto_binary="$source_dir/build/konpacto"
[[ -x "$konpacto_binary" ]] || {
  printf 'konpacto host executable was not found: %s\n' "$konpacto_binary" >&2
  exit 1
}
cp "$konpacto_binary" "$host_root/bin/konpacto"
