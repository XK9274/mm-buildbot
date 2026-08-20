#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

package_id="${1:?usage: scripts/validate-package.sh <package>}"
root="$(repo_root)"
package_dir="$(require_package "$root" "$package_id")"
config="$package_dir/package.yml"

required=(
  "id:"
  "name:"
  "source:"
  "  repo:"
  "  ref:"
  "app_dist:"
  "  template:"
)

for field in "${required[@]}"; do
  if ! grep -q "^$field" "$config"; then
    printf 'Missing required field in %s: %s\n' "$config" "$field" >&2
    exit 1
  fi
done

declared_id="$(yaml_value "$config" "id")"
if [[ "$declared_id" != "$package_id" ]]; then
  printf 'Package id mismatch: folder is %s, config is %s\n' "$package_id" "$declared_id" >&2
  exit 1
fi

printf 'Package config OK: %s\n' "$package_id"

