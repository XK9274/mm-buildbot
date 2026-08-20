#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  local script_dir
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  CDPATH= cd -- "$script_dir/.." && pwd
}

require_package() {
  local root="$1"
  local package_id="$2"
  local package_dir="$root/packages/$package_id"

  if [[ ! -d "$package_dir" ]]; then
    printf 'Package not found: %s\n' "$package_id" >&2
    exit 1
  fi

  if [[ ! -f "$package_dir/package.yml" ]]; then
    printf 'Missing package config: %s/package.yml\n' "$package_dir" >&2
    exit 1
  fi

  printf '%s\n' "$package_dir"
}

yaml_value() {
  local file="$1"
  local key="$2"

  awk -F ': *' -v key="$key" '
    $1 == key {
      value = $2
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

create_zip_from_dir() {
  local source_dir="$1"
  local artifact="$2"

  if command -v zip >/dev/null 2>&1; then
    (
      cd "$source_dir"
      zip -qr "$artifact" . -x '*/.gitkeep' '.gitkeep'
    )
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$source_dir" "$artifact" <<'PY'
import os
import sys
import zipfile

source_dir, artifact = sys.argv[1], sys.argv[2]

with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for root, _, files in os.walk(source_dir):
        for name in files:
            if name == ".gitkeep":
                continue
            path = os.path.join(root, name)
            archive.write(path, os.path.relpath(path, source_dir))
PY
    return
  fi

  printf 'Neither zip nor python3 is available to create archives\n' >&2
  exit 1
}

create_zip_from_files() {
  local artifact="$1"
  shift

  if command -v zip >/dev/null 2>&1; then
    zip -qr "$artifact" "$@"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$artifact" "$@" <<'PY'
import os
import sys
import zipfile

artifact, files = sys.argv[1], sys.argv[2:]

with zipfile.ZipFile(artifact, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, os.path.basename(path))
PY
    return
  fi

  printf 'Neither zip nor python3 is available to create archives\n' >&2
  exit 1
}
