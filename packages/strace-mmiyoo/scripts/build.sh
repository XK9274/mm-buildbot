#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
bundle_dir="${4:?bundle dir required}"
source "$repo_root/packages/.shared/port-common.sh"

source_url="https://github.com/strace/strace/releases/download/v6.12/strace-6.12.tar.xz"
source_sha256="c47da93be45b6055f4dc741d7f20efaf50ca10160a5b100c109b294fd9c0bdfe"
source_archive="$work_dir/downloads/strace-6.12.tar.xz"
source_dir="$work_dir/src/strace-6.12"
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

mkdir -p "$work_dir/downloads" "$work_dir/src" "$bundle_dir/bin"
log "Downloading strace 6.12"
curl --fail --location --retry 3 --output "$source_archive" "$source_url"
printf '%s  %s\n' "$source_sha256" "$source_archive" | sha256sum --check --status
tar -xJf "$source_archive" -C "$work_dir/src"
[[ -x "$source_dir/configure" ]] || {
  printf 'Unexpected strace source layout: %s\n' "$source_dir" >&2
  exit 1
}

docker_image="$(ensure_toolchain_image "union" "$union_repo" "$union_dir" "$docker_image")"
log "Cross-compiling strace with the Union Miyoo toolchain"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e MAKE_JOBS="$make_jobs" \
  --workdir /work/src/strace-6.12 \
  -v "$source_dir":/work/src/strace-6.12 \
  "$docker_image" \
  bash -lc '
    set -euo pipefail
    cross=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-
    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    export STRIP="${cross}strip"
    export CFLAGS="-Os -marm -mtune=cortex-a7 -march=armv7ve+simd -mfpu=neon-vfpv4 -mfloat-abi=hard"
    if ! ./configure --host=arm-linux-gnueabihf --enable-mpers=no > configure.log 2>&1; then
      tail -n 160 configure.log >&2
      exit 1
    fi
    if ! make -s -j"$MAKE_JOBS" > build.log 2>&1; then
      tail -n 160 build.log >&2
      exit 1
    fi
    "$STRIP" --strip-unneeded src/strace
  '

[[ -x "$source_dir/src/strace" ]] || {
  printf 'strace binary was not built: %s/src/strace\n' "$source_dir" >&2
  exit 1
}
install -m 755 "$source_dir/src/strace" "$bundle_dir/bin/strace"
install -m 644 "$source_dir/COPYING" "$bundle_dir/COPYING"
install -m 644 "$repo_root/packages/strace-mmiyoo/README.md" "$bundle_dir/README.md"

log "Tool bundle staged at $bundle_dir"
