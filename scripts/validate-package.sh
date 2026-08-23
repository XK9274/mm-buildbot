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
)

for field in "${required[@]}"; do
  if ! grep -q "^$field" "$config"; then
    printf 'Missing required field in %s: %s\n' "$config" "$field" >&2
    exit 1
  fi
done

artifact_type="$(awk '
  $1 == "artifact:" { in_artifact = 1; next }
  in_artifact && /^[^ ]/ { exit }
  in_artifact && $1 == "type:" { print $2; exit }
' "$config")"
artifact_type="${artifact_type:-app_dist}"

case "$artifact_type" in
  app_dist)
    required=("app_dist:" "  template:")
    ;;
  tool_bundle)
    required=("artifact:" "  output_name:")
    ;;
  *)
    printf 'Unsupported artifact.type in %s: %s\n' "$config" "$artifact_type" >&2
    exit 1
    ;;
esac

for field in "${required[@]}"; do
  if ! grep -q "^$field" "$config"; then
    printf 'Missing required field in %s: %s\n' "$config" "$field" >&2
    exit 1
  fi
done

has_git_source=0
has_archive_source=0
grep -q '^  repo:' "$config" && grep -q '^  ref:' "$config" && has_git_source=1
grep -q '^  url:' "$config" && grep -q '^  sha256:' "$config" && has_archive_source=1

if [[ "$has_git_source" != 1 && "$has_archive_source" != 1 ]]; then
  printf 'Package source in %s must provide repo/ref or url/sha256\n' "$config" >&2
  exit 1
fi

while IFS= read -r dependency; do
  [[ -n "$dependency" ]] || continue
  if [[ "$dependency" == "$package_id" ]]; then
    printf 'Package %s cannot depend on itself\n' "$package_id" >&2
    exit 1
  fi
  if [[ ! -f "$root/packages/$dependency/package.yml" ]]; then
    printf 'Package %s declares missing dependency: %s\n' "$package_id" "$dependency" >&2
    exit 1
  fi
done < <(package_dependencies "$config")

declared_id="$(yaml_value "$config" "id")"
if [[ "$declared_id" != "$package_id" ]]; then
  printf 'Package id mismatch: folder is %s, config is %s\n' "$package_id" "$declared_id" >&2
  exit 1
fi

if grep -q '^host:' "$config"; then
  host_build_system="$(awk '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == "build_system:" { print $2; exit }
  ' "$config")"
  case "$host_build_system" in
    cmake|make) ;;
    *)
      printf 'Unsupported host.build_system in %s: %s\n' "$config" "${host_build_system:-<missing>}" >&2
      exit 1
      ;;
  esac

  host_source_dir="$(awk '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == "source_dir:" { print $2; exit }
  ' "$config")"
  [[ -n "$host_source_dir" ]] || {
    printf 'Missing host.source_dir in %s\n' "$config" >&2
    exit 1
  }

  host_outputs="$(awk '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == "outputs:" { in_outputs = 1; next }
    in_outputs && /^[^ ]/ { exit }
    in_outputs && $1 == "-" { print $2 }
  ' "$config")"
  [[ -n "$host_outputs" ]] || {
    printf 'Missing host.outputs in %s\n' "$config" >&2
    exit 1
  }

  host_prepare_script="$(awk '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == "prepare_script:" { print $2; exit }
  ' "$config")"
  if [[ -n "$host_prepare_script" && ! -x "$root/$host_prepare_script" ]]; then
    printf 'Host prepare script is missing or not executable in %s: %s\n' "$config" "$host_prepare_script" >&2
    exit 1
  fi

  host_run_script="$(awk '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == "run_script:" { print $2; exit }
  ' "$config")"
  if [[ -n "$host_run_script" && ! -x "$root/$host_run_script" ]]; then
    printf 'Host run script is missing or not executable in %s: %s\n' "$config" "$host_run_script" >&2
    exit 1
  fi

  host_post_build_script="$(awk '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == "post_build_script:" { print $2; exit }
  ' "$config")"
  if [[ -n "$host_post_build_script" && ! -x "$root/$host_post_build_script" ]]; then
    printf 'Host post-build script is missing or not executable in %s: %s\n' "$config" "$host_post_build_script" >&2
    exit 1
  fi
fi

printf 'Package config OK: %s\n' "$package_id"
