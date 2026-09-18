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

# Phase 0 (sequential): SDL2 is the common provider.  Build it before any
# enabled consumer so every downstream package links against the exact same
# headers and shared library.
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

  # Seed sdl2-mmiyoo-lib's mode markers so build-package.sh's dependency
  # resolution sees this build as current instead of redundantly rebuilding.
  requested_gles_mode="gles"
  [[ "${SDL2_MIYOO_ENABLE_GLES:-1}" == "0" ]] && requested_gles_mode="nogl"
  printf '%s' "$requested_gles_mode" >"$BUILDBOT_SESSION_DIR/sdl2-mmiyoo-lib.gles-mode"
  printf '%s' "${SDL2_MIYOO_DEBUG:-0}" >"$BUILDBOT_SESSION_DIR/sdl2-mmiyoo-lib.debug-mode"
fi

# Phase 0.5 (sequential): precompute the sdl2-mmiyoo-addons union across
# every enabled consumer up front, so Phase 1's parallel jobs see a
# same-session cache hit instead of racing to extend it themselves.
addons_union=""
for package_dir in "$root"/packages/*; do
  [[ -f "$package_dir/package.yml" ]] || continue
  [[ "$(yaml_value "$package_dir/package.yml" "build_all")" == "false" ]] && continue
  package_dependencies "$package_dir/package.yml" | grep -qx 'sdl2-mmiyoo-addons' || continue
  requested_addons="$(yaml_list "$package_dir/package.yml" "sdl2_addons" | tr '\n' ' ')"
  requested_addons="${requested_addons:-all}"
  if [[ "$addons_union" == "all" || "$requested_addons" == "all" ]]; then
    addons_union="all"
  else
    addons_union="$(printf '%s %s\n' "$addons_union" "$requested_addons" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  fi
done
if [[ -n "$addons_union" ]]; then
  printf '%s' "$addons_union" >"$BUILDBOT_SESSION_DIR/sdl2-mmiyoo-addons.selection"
  SDL2_ADDONS="$addons_union" "$script_dir/build-package.sh" sdl2-mmiyoo-addons
fi

# Phase 1, split into two sequential batches (each internally parallel):
# a GLES-mode switch rebuilds the shared bundle in place, so default- and
# nogl-mode consumers of sdl2-mmiyoo-lib must never run concurrently.
jobs="${MM_BUILDBOT_JOBS:-$(nproc)}"
default_mode_ids=()
nogl_mode_ids=()
for package_dir in "$root"/packages/*; do
  [[ -d "$package_dir" && -f "$package_dir/package.yml" ]] || continue
  package_id="$(basename "$package_dir")"
  if [[ "$(yaml_value "$package_dir/package.yml" "build_all")" == "false" ]]; then
    printf 'Skipping disabled package: %s\n' "$package_id"
    continue
  fi
  if package_dependencies "$package_dir/package.yml" | grep -qx 'sdl2-mmiyoo-lib' \
    && [[ "$(yaml_value "$package_dir/package.yml" "sdl2_gles")" == "no" ]]; then
    nogl_mode_ids+=("$package_id")
  else
    default_mode_ids+=("$package_id")
  fi
done

failed_packages_file="$BUILDBOT_SESSION_DIR/failed-packages"
rm -f "$failed_packages_file"

run_package_job() {
  set -o pipefail
  local package_id="$1"
  local log_file="$BUILDBOT_SESSION_DIR/$package_id.log"
  if "$script_dir/build-package.sh" "$package_id" 2>&1 | tee "$log_file" | sed "s/^/[$package_id] /"; then
    return 0
  fi
  printf '%s\n' "$package_id" >>"$BUILDBOT_SESSION_DIR/failed-packages"
  return 1
}
export -f run_package_job
export script_dir BUILDBOT_SESSION_DIR

run_batch() {
  local batch=("$@")
  (( ${#batch[@]} > 0 )) || return 0
  printf '%s\n' "${batch[@]}" | xargs -P "$jobs" -I{} bash -c 'run_package_job "$@"' _ {} || true
}

run_batch "${default_mode_ids[@]}"
run_batch "${nogl_mode_ids[@]}"

if [[ -f "$failed_packages_file" ]]; then
  mapfile -t failed_packages <"$failed_packages_file"
  printf 'Failed packages (%d): %s\n' "${#failed_packages[@]}" "${failed_packages[*]}" >&2
  printf 'See per-package logs under %s\n' "$BUILDBOT_SESSION_DIR" >&2
  exit 1
fi

archives=("$root"/artifacts/*.zip)
if [[ ! -e "${archives[0]}" ]]; then
  printf 'No package archives were created\n' >&2
  exit 1
fi

create_zip_from_files "$root/dist/all-artifacts.zip" "${archives[@]}"
cp "$root/dist/all-artifacts.zip" "$root/dist/all-app-dists.zip"

printf 'Created aggregate artifact: %s\n' "$root/dist/all-artifacts.zip"
printf 'Created compatibility aggregate: %s\n' "$root/dist/all-app-dists.zip"
