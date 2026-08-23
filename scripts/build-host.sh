#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$script_dir/common.sh"

package_id="${1:?usage: scripts/build-host.sh <package>}"
root="$(repo_root)"
package_dir="$(require_package "$root" "$package_id")"
config="$package_dir/package.yml"

grep -q '^host:' "$config" || {
  printf 'Package does not declare a host build: %s\n' "$package_id" >&2
  exit 1
}

host_value() {
  local key="$1"
  awk -v key="$key" '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == key ":" { gsub(/^"|"$/, $2); print $2; exit }
  ' "$config"
}

host_list() {
  local section="$1"
  awk -v section="$section" '
    $1 == "host:" { in_host = 1; next }
    in_host && /^[^ ]/ { exit }
    in_host && $1 == section ":" { in_section = 1; next }
    in_section && /^[[:space:]]{2}[A-Za-z_][A-Za-z0-9_]*:/ { exit }
    in_section && $1 == "-" { print $2 }
  ' "$config"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required host command: %s\n' "$1" >&2
    exit 1
  }
}

require_pkg_config_module() {
  local module="$1"
  pkg-config --exists "$module" || {
    printf 'Missing required pkg-config module: %s\n' "$module" >&2
    printf 'Install the native development package for %s in WSL2 and retry.\n' "$module" >&2
    exit 1
  }
  printf 'Using %s %s\n' "$module" "$(pkg-config --modversion "$module")"
}

clone_pinned_source() {
  local destination="$1"
  local repository revision
  repository="$(yaml_value "$config" "repo")"
  revision="$(yaml_value "$config" "ref")"

  [[ -n "$repository" && -n "$revision" ]] || {
    printf 'Host builds require a pinned Git source unless HOST_SOURCE_DIR is set\n' >&2
    exit 1
  }
  require_command git
  git clone "$repository" "$destination"
  git -C "$destination" checkout --detach "$revision"
}

verify_native_output() {
  local output="$1"
  [[ -f "$output" && -x "$output" ]] || {
    printf 'Declared host output is missing or not executable: %s\n' "$output" >&2
    exit 1
  }
  require_command readelf
  local header
  header="$(readelf -h "$output")"
  grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header" || {
    printf 'Host output is not ELF64: %s\n' "$output" >&2
    exit 1
  }
  grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64|Machine:[[:space:]]+X86-64' <<<"$header" || {
    printf 'Host output is not x86-64: %s\n' "$output" >&2
    exit 1
  }
}

"$script_dir/validate-package.sh" "$package_id"
require_command pkg-config
require_command cmake
require_command make
require_command gcc
require_command g++

build_system="$(host_value build_system)"
source_subdir="$(host_value source_dir)"
source_subdir="${source_subdir:-.}"
host_root="$root/work/host/$package_id"
source_root="$host_root/source"
build_dir="$host_root/build"
mkdir -p "$host_root"

if [[ -n "${HOST_SOURCE_DIR:-}" ]]; then
  [[ -d "$HOST_SOURCE_DIR" ]] || {
    printf 'HOST_SOURCE_DIR is not a directory: %s\n' "$HOST_SOURCE_DIR" >&2
    exit 1
  }
  source_dir="$HOST_SOURCE_DIR/$source_subdir"
else
  if [[ ! -d "$source_root/.git" ]]; then
    rm -rf "$source_root"
    clone_pinned_source "$source_root"
  fi
  source_dir="$source_root/$source_subdir"
fi

[[ -d "$source_dir" ]] || {
  printf 'Resolved host source directory is missing: %s\n' "$source_dir" >&2
  exit 1
}

while IFS= read -r module; do
  [[ -n "$module" ]] || continue
  require_pkg_config_module "$module"
done < <(host_list pkg_config)

prepare_script="$(host_value prepare_script)"
if [[ -n "$prepare_script" ]]; then
  "$root/$prepare_script" "$package_id" "$root" "$source_dir" "$host_root"
fi

configure_args=()
while IFS= read -r argument; do
  [[ -n "$argument" ]] || continue
  configure_args+=("$argument")
done < <(host_list configure_args)

build_target="$(host_value build_target)"
mkdir -p "$build_dir"

case "$build_system" in
  cmake)
    require_command cmake
    cmake_args=("-DCMAKE_BUILD_TYPE=${HOST_BUILD_TYPE:-Debug}")
    if [[ -d "$host_root/cmake" ]]; then
      cmake_args+=("-DCMAKE_MODULE_PATH=$host_root/cmake")
    fi
    cmake_args+=("${configure_args[@]}")
    cmake -S "$source_dir" -B "$build_dir" "${cmake_args[@]}"
    if [[ -n "$build_target" ]]; then
      cmake --build "$build_dir" --parallel "${HOST_JOBS:-$(nproc)}" --target "$build_target"
    else
      cmake --build "$build_dir" --parallel "${HOST_JOBS:-$(nproc)}"
    fi
    ;;
  make)
    make_args=("-C" "$source_dir" "-j${HOST_JOBS:-$(nproc)}")
    [[ -n "$build_target" ]] && make_args+=("$build_target")
    make "${make_args[@]}"
    ;;
  *)
    printf 'Unsupported host build system: %s\n' "$build_system" >&2
    exit 1
    ;;
esac

while IFS= read -r output; do
  [[ -n "$output" ]] || continue
  output_path="$host_root/$output"
  verify_native_output "$output_path"
  printf 'Host output: %s\n' "$output_path"
done < <(host_list outputs)

printf 'Host build complete: %s\n' "$host_root"
