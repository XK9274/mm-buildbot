#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"
root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

mkdir -p "$root/artifacts" "$root/dist"
rm -f "$root/dist/all-app-dists.zip"

for package_dir in "$root"/packages/*; do
  [[ -d "$package_dir" ]] || continue
  package_id="$(basename "$package_dir")"
  "$script_dir/build-package.sh" "$package_id"
done

archives=("$root"/artifacts/*.zip)
if [[ ! -e "${archives[0]}" ]]; then
  printf 'No app archives were created\n' >&2
  exit 1
fi

create_zip_from_files "$root/dist/all-app-dists.zip" "${archives[@]}"

printf 'Created aggregate artifact: %s\n' "$root/dist/all-app-dists.zip"
