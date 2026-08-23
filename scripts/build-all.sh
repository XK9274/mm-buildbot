#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"
root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

mkdir -p "$root/artifacts" "$root/dist"
rm -f "$root/dist/all-artifacts.zip" "$root/dist/all-app-dists.zip"
export BUILDBOT_SESSION_DIR="$root/work/.buildbot-sessions/build-all-$$"
mkdir -p "$BUILDBOT_SESSION_DIR"

# SDL2 is the common provider.  Build it before any enabled consumer so every
# downstream package links against the exact same headers and shared library.
needs_mmiyoo_sdl2=0
for package_dir in "$root"/packages/*; do
  [[ -f "$package_dir/package.yml" ]] || continue
  [[ "$(yaml_value "$package_dir/package.yml" "build_all")" == "false" ]] && continue
  if package_dependencies "$package_dir/package.yml" | grep -qx 'sdl2-mmiyoo-lib'; then
    needs_mmiyoo_sdl2=1
    break
  fi
done
if [[ "$needs_mmiyoo_sdl2" == 1 ]]; then
  "$script_dir/build-package.sh" sdl2-mmiyoo-lib
fi

for package_dir in "$root"/packages/*; do
  [[ -d "$package_dir" && -f "$package_dir/package.yml" ]] || continue
  package_id="$(basename "$package_dir")"
  if [[ "$(yaml_value "$package_dir/package.yml" "build_all")" == "false" ]]; then
    printf 'Skipping disabled package: %s\n' "$package_id"
    continue
  fi
  "$script_dir/build-package.sh" "$package_id"
done

archives=("$root"/artifacts/*.zip)
if [[ ! -e "${archives[0]}" ]]; then
  printf 'No package archives were created\n' >&2
  exit 1
fi

create_zip_from_files "$root/dist/all-artifacts.zip" "${archives[@]}"
cp "$root/dist/all-artifacts.zip" "$root/dist/all-app-dists.zip"

printf 'Created aggregate artifact: %s\n' "$root/dist/all-artifacts.zip"
printf 'Created compatibility aggregate: %s\n' "$root/dist/all-app-dists.zip"
