#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

package_id="${1:?usage: scripts/run-host.sh <package> [args...]}"
shift
root="$(repo_root)"
package_dir="$(require_package "$root" "$package_id")"
config="$package_dir/package.yml"
host_root="$root/work/host/$package_id"

host_value() {
  local key="$1"
  awk -v key="$key" '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == key ":" { print $2; exit }
  ' "$config"
}

run_script="$(host_value run_script)"
[[ -n "$run_script" ]] || {
  printf 'Package does not declare a host run script: %s\n' "$package_id" >&2
  exit 1
}
[[ -x "$root/$run_script" ]] || {
  printf 'Host run script is missing or not executable: %s\n' "$root/$run_script" >&2
  exit 1
}
[[ -d "$host_root" ]] || {
  printf 'Host build directory is missing: %s\n' "$host_root" >&2
  printf 'Build the package first with scripts/build-host.sh %s\n' "$package_id" >&2
  exit 1
}

if [[ -n "${HOST_SOURCE_DIR:-}" ]]; then
  source_dir="$HOST_SOURCE_DIR"
elif [[ -f "$host_root/source-dir" ]]; then
  source_dir="$(<"$host_root/source-dir")"
else
  source_dir="$host_root/source"
fi
[[ -d "$source_dir" ]] || {
  printf 'Host source directory is missing: %s\n' "$source_dir" >&2
  exit 1
}

exec "$root/$run_script" "$package_id" "$root" "$host_root" "$source_dir" "$@"
