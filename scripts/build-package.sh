#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

package_id="${1:?usage: scripts/build-package.sh <package>}"
root="$(repo_root)"
package_dir="$(require_package "$root" "$package_id")"
config="$package_dir/package.yml"

# A build-all invocation exports one session directory.  Dependency artifacts
# are built at most once per session, while a standalone package invocation
# always starts a fresh session and therefore remains reproducible.
if [[ -z "${BUILDBOT_SESSION_DIR:-}" ]]; then
  export BUILDBOT_SESSION_DIR="$root/work/.buildbot-sessions/$$"
fi
mkdir -p "$BUILDBOT_SESSION_DIR"

"$script_dir/validate-package.sh" "$package_id"

# Build dependencies first.  Recipes consume their staged bundle through a
# stable prefix instead of assuming host-installed SDL headers or libraries.
dependency_stack=":${BUILDBOT_PACKAGE_STACK:-}:"
if [[ "$dependency_stack" == *":$package_id:"* ]]; then
  printf 'Dependency cycle detected while building %s: %s\n' "$package_id" "$BUILDBOT_PACKAGE_STACK" >&2
  exit 1
fi
export BUILDBOT_PACKAGE_STACK="${BUILDBOT_PACKAGE_STACK:+$BUILDBOT_PACKAGE_STACK:}$package_id"

while IFS= read -r dependency; do
  [[ -n "$dependency" ]] || continue
  dependency_prefix=""
  use_external_dependency=0
  case "$dependency" in
    sdl2-mmiyoo-lib)
      dependency_prefix="${MMIYOO_SDL2_PREFIX:-}"
      [[ -n "$dependency_prefix" ]] && use_external_dependency=1
      ;;
    sdl2-mmiyoo-addons)
      dependency_prefix="${MMIYOO_SDL2_ADDONS_PREFIX:-}"
      [[ -n "$dependency_prefix" ]] && use_external_dependency=1
      ;;
  esac

  if (( use_external_dependency )); then
    [[ -d "$dependency_prefix" ]] || {
      printf 'External dependency prefix is not a directory for %s: %s\n' "$dependency" "$dependency_prefix" >&2
      exit 1
    }
    printf 'Using external dependency prefix for %s: %s\n' "$dependency" "$dependency_prefix"
  else
    dependency_prefix="$root/work/$dependency/bundle"
    dependency_marker="$BUILDBOT_SESSION_DIR/$dependency.complete"
    if [[ ! -f "$dependency_marker" ]]; then
      if [[ "$dependency" == "sdl2-mmiyoo-lib" ]]; then
        # Let the consumer opt out of GLES (e.g. an app with no GL/EGL symbols).
        sdl2_gles="$(awk '$1 == "sdl2_gles:" { print $2; exit }' "$config")"
        if [[ "$sdl2_gles" == "no" ]]; then
          export SDL2_MIYOO_ENABLE_GLES=0
        fi
      fi
      "$script_dir/build-package.sh" "$dependency"
    fi
  fi
  dependency_var="PACKAGE_DEPENDENCY_${dependency//-/_}"
  export "$dependency_var=$dependency_prefix"
  if [[ "$dependency" == "sdl2-mmiyoo-lib" ]]; then
    export MMIYOO_SDL2_PREFIX="$dependency_prefix"
  fi
  if [[ "$dependency" == "sdl2-mmiyoo-addons" ]]; then
    export MMIYOO_SDL2_ADDONS_PREFIX="$dependency_prefix"
  fi
done < <(package_dependencies "$config")

work_dir="$root/work/$package_id"
artifact="$root/artifacts/$package_id.zip"

artifact_type="$(awk '
  $1 == "artifact:" { in_artifact = 1; next }
  in_artifact && /^[^ ]/ { exit }
  in_artifact && $1 == "type:" { print $2; exit }
' "$config")"
artifact_type="${artifact_type:-app_dist}"

rm -rf "$work_dir" "$artifact"
mkdir -p "$work_dir" "$root/artifacts"

case "$artifact_type" in
  app_dist)
    stage_dir="$work_dir/app-dist"
    template_dir="$root/$(awk '
      $1 == "app_dist:" { in_app_dist = 1; next }
      in_app_dist && $1 == "template:" { print $2; exit }
    ' "$config")"

    mkdir -p "$stage_dir"
    if [[ -d "$template_dir" ]]; then
      cp -R "$template_dir/." "$stage_dir/"
    fi
    ;;
  tool_bundle)
    stage_dir="$work_dir/bundle"
    mkdir -p "$stage_dir"
    ;;
  port)
    stage_dir="$work_dir/port"
    mkdir -p "$stage_dir"
    ;;
  *)
    printf 'Unsupported artifact.type in %s: %s\n' "$config" "$artifact_type" >&2
    exit 1
    ;;
esac

if [[ -x "$package_dir/scripts/build.sh" ]]; then
  "$package_dir/scripts/build.sh" "$package_id" "$root" "$work_dir" "$stage_dir"
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

if [[ "$artifact_type" == "app_dist" ]] && (( ${#tokens[@]} > 0 )); then
  "$script_dir/tokenise-dir.sh" "$stage_dir" "${tokens[@]}"
fi

create_zip_from_dir "$stage_dir" "$artifact"
touch "$BUILDBOT_SESSION_DIR/$package_id.complete"

printf 'Created artifact: %s\n' "$artifact"
