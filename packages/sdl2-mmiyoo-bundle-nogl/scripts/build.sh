#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
bundle_dir="${4:?bundle dir required}"

: "${PACKAGE_DEPENDENCY_sdl2_mmiyoo_lib:?Missing sdl2-mmiyoo-lib dependency prefix}"
: "${PACKAGE_DEPENDENCY_sdl2_mmiyoo_addons:?Missing sdl2-mmiyoo-addons dependency prefix}"

mkdir -p "$bundle_dir/include" "$bundle_dir/lib"
cp -a "$PACKAGE_DEPENDENCY_sdl2_mmiyoo_lib/include/." "$bundle_dir/include/"
cp -a "$PACKAGE_DEPENDENCY_sdl2_mmiyoo_lib/lib/." "$bundle_dir/lib/"
cp -a "$PACKAGE_DEPENDENCY_sdl2_mmiyoo_addons/include/." "$bundle_dir/include/"
cp -a "$PACKAGE_DEPENDENCY_sdl2_mmiyoo_addons/lib/." "$bundle_dir/lib/"

if compgen -G "$bundle_dir/lib/libEGL*" >/dev/null || compgen -G "$bundle_dir/lib/libGLESv2*" >/dev/null; then
  printf 'GLES libraries present in a bundle built with sdl2_gles: no\n' >&2
  exit 1
fi

install -m 644 "$repo_root/packages/sdl2-mmiyoo-bundle-nogl/README.md" "$bundle_dir/README.md"
