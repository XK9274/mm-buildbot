#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

package_id="${1:?usage: scripts/build-package.sh <package>}"
root="$(repo_root)"
package_dir="$(require_package "$root" "$package_id")"
config="$package_dir/package.yml"

"$script_dir/validate-package.sh" "$package_id"

work_dir="$root/work/$package_id"
app_dist_dir="$work_dir/app-dist"
artifact="$root/artifacts/$package_id.zip"

rm -rf "$work_dir" "$artifact"
mkdir -p "$work_dir" "$app_dist_dir" "$root/artifacts"

template_dir="$root/$(awk '
  $1 == "app_dist:" { in_app_dist = 1; next }
  in_app_dist && $1 == "template:" { print $2; exit }
' "$config")"

if [[ -d "$template_dir" ]]; then
  cp -R "$template_dir/." "$app_dist_dir/"
fi

if [[ -x "$package_dir/scripts/build.sh" ]]; then
  "$package_dir/scripts/build.sh" "$package_id" "$root" "$work_dir" "$app_dist_dir"
else
  printf 'Missing executable build script: %s/scripts/build.sh\n' "$package_dir" >&2
  exit 1
fi

tokens=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]{2}([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]] || continue
  tokens+=("${BASH_REMATCH[1]}=${BASH_REMATCH[2]}")
done < <(awk '
  $1 == "tokens:" { in_tokens = 1; next }
  in_tokens && /^[^ ]/ { exit }
  in_tokens { print }
' "$config")

if (( ${#tokens[@]} > 0 )); then
  "$script_dir/tokenise-dir.sh" "$app_dist_dir" "${tokens[@]}"
fi

create_zip_from_dir "$app_dist_dir" "$artifact"

printf 'Created artifact: %s\n' "$artifact"
