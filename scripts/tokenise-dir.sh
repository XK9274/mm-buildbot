#!/usr/bin/env bash
set -euo pipefail

target_dir="${1:?usage: scripts/tokenise-dir.sh <dir> <KEY=VALUE>...}"
shift

if [[ ! -d "$target_dir" ]]; then
  printf 'Token target is not a directory: %s\n' "$target_dir" >&2
  exit 1
fi

for assignment in "$@"; do
  key="${assignment%%=*}"
  value="${assignment#*=}"

  if [[ -z "$key" || "$key" == "$assignment" ]]; then
    printf 'Invalid token assignment: %s\n' "$assignment" >&2
    exit 1
  fi

  while IFS= read -r -d '' file; do
    sed -i "s|{{$key}}|$value|g" "$file"
  done < <(find "$target_dir" -type f -print0)
done

