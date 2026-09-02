#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
bundle_dir="${4:?bundle dir required}"
source "$repo_root/packages/.shared/port-common.sh"

source_url="https://www.kernel.org/pub/software/utils/i2c-tools/i2c-tools-4.4.tar.xz"
source_sha256="8b15f0a880ab87280c40cfd7235cfff28134bf14d5646c07518b1ff6642a2473"
source_archive="$work_dir/downloads/i2c-tools-4.4.tar.xz"
source_dir="$work_dir/src/i2c-tools-4.4"
union_repo="${UNION_TOOLCHAIN_REPO:-https://github.com/XK9274/union-miyoomini-toolchain.git}"
union_dir="${UNION_TOOLCHAIN_DIR:-$repo_root/work/.toolchain-cache/union}"
docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
make_jobs="${MAKE_JOBS:-}"

log() {
  printf '[%s] %s\n' "$package_id" "$*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

require_tool curl
require_tool sha256sum
require_tool tar

if [[ -z "$make_jobs" ]]; then
  make_jobs="$(command -v nproc >/dev/null 2>&1 && nproc || printf '4')"
fi

mkdir -p "$work_dir/downloads" "$work_dir/src" "$bundle_dir/bin" "$bundle_dir/licenses"

log "Downloading i2c-tools 4.4"
curl --fail --location --retry 3 --output "$source_archive" "$source_url"
printf '%s  %s\n' "$source_sha256" "$source_archive" | sha256sum --check --status

tar -xJf "$source_archive" -C "$work_dir/src"
[[ -f "$source_dir/Makefile" ]] || {
  printf 'Unexpected i2c-tools source layout: %s\n' "$source_dir" >&2
  exit 1
}

docker_image="$(ensure_toolchain_image "union" "$union_repo" "$union_dir" "$docker_image")"

log "Cross-compiling with the Union Miyoo toolchain"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e MAKE_JOBS="$make_jobs" \
  --workdir /work/src/i2c-tools-4.4 \
  -v "$source_dir":/work/src/i2c-tools-4.4 \
  "$docker_image" \
  bash -lc '
    set -euo pipefail
    cross=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-
    export CC="${cross}gcc"
    export AR="${cross}ar"
    export STRIP="${cross}strip"
    export CFLAGS="-Os -marm -mtune=cortex-a7 -march=armv7ve+simd -mfpu=neon-vfpv4 -mfloat-abi=hard"
    make -j"$MAKE_JOBS" \
      CC="$CC" AR="$AR" STRIP="$STRIP" CFLAGS="$CFLAGS" \
      BUILD_STATIC_LIB=1 BUILD_DYNAMIC_LIB=0 USE_STATIC_LIB=1
    for binary in i2cdetect i2cdump i2cget i2cset i2ctransfer; do
      "$STRIP" --strip-unneeded "tools/$binary"
    done
  '

for binary in i2cdetect i2cdump i2cget i2cset i2ctransfer; do
  [[ -x "$source_dir/tools/$binary" ]] || {
    printf 'Expected i2c-tools binary was not built: %s\n' "$binary" >&2
    exit 1
  }
  install -m 755 "$source_dir/tools/$binary" "$bundle_dir/bin/$binary"
done

install -m 644 "$source_dir/COPYING.LGPL" "$bundle_dir/licenses/i2c-tools-COPYING.LGPL"
install -m 644 "$repo_root/packages/i2c-tools-mmiyoo/README.md" "$bundle_dir/README.md"

log "Tool bundle staged at $bundle_dir"
