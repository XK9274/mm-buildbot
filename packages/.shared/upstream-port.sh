#!/usr/bin/env bash
# Helpers intentionally kept small: upstream projects remain the source of
# truth for their build and package layouts.

shared_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/.shared/port-common.sh
source "$shared_dir/port-common.sh"

clone_pinned_source() {
  local repository="${1:?repository required}"
  local revision="${2:?revision required}"
  local destination="${3:?destination required}"

  mkdir -p "$(dirname "$destination")"
  git clone "$repository" "$destination"
  git -C "$destination" checkout --detach "$revision"
}

require_mmiyoo_sdl_provider() {
  : "${MMIYOO_SDL2_PREFIX:?This package needs the sdl2-mmiyoo-lib dependency. Build it after mk_mmiyoo.sh is published.}"
  [[ -f "$MMIYOO_SDL2_PREFIX/lib/libSDL2-2.0.so.0" ]] || {
    printf 'Invalid MMIYOO SDL2 provider: %s\n' "$MMIYOO_SDL2_PREFIX" >&2
    return 1
  }
}

copy_tree_contents() {
  local source="${1:?source required}"
  local destination="${2:?destination required}"
  [[ -d "$source" ]] || {
    printf 'Expected upstream package directory is missing: %s\n' "$source" >&2
    return 1
  }
  mkdir -p "$destination"
  cp -R "$source/." "$destination/"
}

ensure_union_toolchain_image() {
  local union_repo="${UNION_TOOLCHAIN_REPO:-https://github.com/XK9274/union-miyoomini-toolchain.git}"
  local union_dir="${UNION_TOOLCHAIN_DIR:-${repo_root:-.}/work/.toolchain-cache/union}"
  local image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"

  ensure_toolchain_image "union" "$union_repo" "$union_dir" "$image"
}

build_source_port() {
  local repository="${1:?repository required}"
  local revision="${2:?revision required}"
  local source_dir="${3:?source directory required}"
  local stage_dir="${4:?stage directory required}"
  local build_command="${5:?build command required}"
  local image

  require_mmiyoo_sdl_provider
  image="$(ensure_union_toolchain_image)"
  clone_pinned_source "$repository" "$revision" "$source_dir"

  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e SDL2_MIYOO_PREFIX=/opt/mmiyoo-sdl2 \
    -e SDL2_CONFIG=/opt/mmiyoo-sdl2/bin/sdl2-config \
    -e PKG_CONFIG_PATH=/opt/mmiyoo-sdl2/lib/pkgconfig \
    -e CFLAGS=-I/opt/mmiyoo-sdl2/include/SDL2 \
    -e LDFLAGS=-L/opt/mmiyoo-sdl2/lib \
    -v "$source_dir":/src \
    -v "$stage_dir":/out \
    -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
    --workdir /src \
    "$image" bash -lc "$build_command"

  stage_mmiyoo_sdl_runtime "$MMIYOO_SDL2_PREFIX" "$stage_dir/lib"
  verify_mmiyoo_runtime_closure "$stage_dir"
}
