#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

days="${1:-30}"
root="$(repo_root)"
cache_root="$root/work/.toolchain-cache"

usage() {
  printf 'usage: %s [days]\n' "$(basename "$0")" >&2
  printf '  Removes docker images and content-hash stamps under work/.toolchain-cache\n' >&2
  printf '  whose stamp file has not been touched in at least [days] (default 30).\n' >&2
}

[[ "$days" =~ ^[0-9]+$ ]] || { usage; exit 2; }

command -v docker >/dev/null 2>&1 || {
  printf 'Missing required tool: docker\n' >&2
  exit 1
}

[[ -d "$cache_root" ]] || {
  printf 'No toolchain cache at %s\n' "$cache_root"
  exit 0
}

prune_stamp() {
  local stamp_file="$1"
  local image_tag
  image_tag="$(cut -d: -f1 <"$stamp_file")"

  [[ -n "$image_tag" ]] || {
    printf 'Skipping %s: could not read an image tag from it\n' "$stamp_file" >&2
    return
  }

  if docker image inspect "$image_tag" >/dev/null 2>&1; then
    if docker image rm "$image_tag" >/dev/null 2>&1; then
      printf 'Removed stale image: %s (stamp: %s)\n' "$image_tag" "$stamp_file"
    else
      printf 'Warning: could not remove %s (likely still referenced by a container); leaving its stamp in place\n' "$image_tag" >&2
      return
    fi
  else
    printf 'Image already gone: %s (stamp: %s)\n' "$image_tag" "$stamp_file"
  fi

  rm -f "$stamp_file"
}

found=0
while IFS= read -r -d '' stamp_file; do
  found=1
  prune_stamp "$stamp_file"
done < <(find "$cache_root" \( -name '*.stamp' -o -name '.mm-buildbot-build-stamp' \) -mtime "+$days" -print0)

(( found )) || printf 'No stamps older than %s day(s) under %s\n' "$days" "$cache_root"
