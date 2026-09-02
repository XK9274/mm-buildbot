#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
bundle_dir="${4:?bundle dir required}"
source "$repo_root/packages/.shared/port-common.sh"

tcpdump_url="https://www.tcpdump.org/release/tcpdump-4.99.6.tar.xz"
tcpdump_sha256="40a8cefd45f0d2a06827e6658efb830d484868c449ad80f7efb33516af44f3da"
libpcap_url="https://www.tcpdump.org/release/libpcap-1.10.6.tar.xz"
libpcap_sha256="ec97d1206bdd19cb6bdd043eaa9f0037aa732262ec68e070fd7c7b5f834d5dfc"
sources_dir="$work_dir/src"
tcpdump_dir="$sources_dir/tcpdump-4.99.6"
libpcap_dir="$sources_dir/libpcap-1.10.6"
union_repo="${UNION_TOOLCHAIN_REPO:-https://github.com/XK9274/union-miyoomini-toolchain.git}"
union_dir="${UNION_TOOLCHAIN_DIR:-$repo_root/work/.toolchain-cache/union}"
docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
tcpdump_image="${MIYOO_TCPDUMP_IMAGE:-${docker_image}-tcpdump-build}"
tcpdump_stamp="$repo_root/work/.toolchain-cache/tcpdump-mmiyoo.stamp"
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

download_verified() {
  local url="$1"
  local expected_sha256="$2"
  local output="$3"
  curl --fail --location --retry 3 --output "$output" "$url"
  printf '%s  %s\n' "$expected_sha256" "$output" | sha256sum --check --status
}

require_tool curl
require_tool sha256sum
require_tool tar
if [[ -z "$make_jobs" ]]; then
  make_jobs="$(command -v nproc >/dev/null 2>&1 && nproc || printf '4')"
fi

mkdir -p "$work_dir/downloads" "$sources_dir" "$bundle_dir/bin" "$bundle_dir/lib"
log "Downloading tcpdump and libpcap sources"
download_verified "$tcpdump_url" "$tcpdump_sha256" "$work_dir/downloads/tcpdump-4.99.6.tar.xz"
download_verified "$libpcap_url" "$libpcap_sha256" "$work_dir/downloads/libpcap-1.10.6.tar.xz"
tar -xJf "$work_dir/downloads/tcpdump-4.99.6.tar.xz" -C "$sources_dir"
tar -xJf "$work_dir/downloads/libpcap-1.10.6.tar.xz" -C "$sources_dir"

[[ -x "$tcpdump_dir/configure" && -x "$libpcap_dir/configure" ]] || {
  printf 'Unexpected tcpdump/libpcap source layout under %s\n' "$sources_dir" >&2
  exit 1
}

docker_image="$(ensure_toolchain_image "union" "$union_repo" "$union_dir" "$docker_image")"
tcpdump_image="$(ensure_derived_toolchain_image "tcpdump-mmiyoo" "$docker_image" "$repo_root/packages/tcpdump-mmiyoo/Dockerfile" "$repo_root/packages/tcpdump-mmiyoo" "$tcpdump_image" "$tcpdump_stamp")"
log "Cross-compiling shared libpcap and tcpdump with the Union toolchain"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e MAKE_JOBS="$make_jobs" \
  --workdir /work/src \
  -v "$sources_dir":/work/src \
  -v "$bundle_dir":/work/bundle \
  "$tcpdump_image" \
  bash -lc '
    set -euo pipefail
    cross=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-
    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    export STRIP="${cross}strip"
    export CFLAGS="-Os -marm -mtune=cortex-a7 -march=armv7ve+simd -mfpu=neon-vfpv4 -mfloat-abi=hard"

    cd /work/src/libpcap-1.10.6
    if ! ./configure --host=arm-linux-gnueabihf --enable-shared > configure.log 2>&1; then
      tail -n 160 configure.log >&2
      exit 1
    fi
    if ! make -s -j"$MAKE_JOBS" > build.log 2>&1; then
      tail -n 160 build.log >&2
      exit 1
    fi
    ln -sf libpcap.so.1.10.6 libpcap.so
    rm -f libpcap.a

    cd /work/src/tcpdump-4.99.6
    if ! CPPFLAGS="-I/work/src/libpcap-1.10.6" \
      LDFLAGS="-L/work/src/libpcap-1.10.6 -Wl,-rpath,\\\$\$ORIGIN/../lib" \
      PCAP_CONFIG=/work/src/libpcap-1.10.6/pcap-config \
      ./configure --host=arm-linux-gnueabihf --disable-local-libpcap > configure.log 2>&1; then
      tail -n 160 configure.log >&2
      exit 1
    fi
    if ! make -s -j"$MAKE_JOBS" > build.log 2>&1; then
      tail -n 160 build.log >&2
      exit 1
    fi
    "$STRIP" --strip-unneeded tcpdump

    install -m 755 tcpdump /work/bundle/bin/tcpdump
    install -m 755 /work/src/libpcap-1.10.6/libpcap.so.1.10.6 /work/bundle/lib/libpcap.so.1
  '

install -m 644 "$tcpdump_dir/LICENSE" "$bundle_dir/tcpdump-LICENSE"
install -m 644 "$libpcap_dir/LICENSE" "$bundle_dir/libpcap-LICENSE"
install -m 644 "$repo_root/packages/tcpdump-mmiyoo/README.md" "$bundle_dir/README.md"
log "Tool bundle staged at $bundle_dir"
