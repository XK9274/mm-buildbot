#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
app_dist_dir="${4:?app-dist dir required}"
source "$repo_root/packages/.shared/port-common.sh"

pokedex_repo="${YORISOFT_POKEDEX_REPO:-https://github.com/Yorisoft/pokedex_miyoo.git}"
pokedex_ref="${YORISOFT_POKEDEX_REF:-7e998b923738d3b00e3a2867c8aa29c4b7b1d06a}"
sqlite_url="https://www.sqlite.org/2026/sqlite-amalgamation-3530400.zip"
sqlite_sha256="1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d"
union_dir="${UNION_TOOLCHAIN_DIR:?UNION_TOOLCHAIN_DIR required (path to your Union Miyoo Mini toolchain checkout)}"
docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
pokedex_dir="$work_dir/src/pokedex_miyoo"
workspace_dir="$pokedex_dir/Source/union-miyoomini-toolchain/workspace"
retrodex_dir="$workspace_dir/retrodex"
app_root="$app_dist_dir/Retrodex"

log() {
  printf '[%s] %s\n' "$package_id" "$*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

ensure_toolchain_image() {
  require_tool docker
  if docker image inspect "$docker_image" >/dev/null 2>&1; then
    return
  fi
  [[ -f "$union_dir/Dockerfile" ]] || {
    printf 'Missing Union toolchain Dockerfile: %s/Dockerfile\n' "$union_dir" >&2
    exit 1
  }
  log "Building Docker image $docker_image from $union_dir"
  docker build -t "$docker_image" "$union_dir"
}

require_tool git
require_tool curl
require_tool sha256sum
require_tool unzip

: "${MMIYOO_SDL2_PREFIX:?Missing sdl2-mmiyoo-lib dependency prefix}"
: "${MMIYOO_SDL2_ADDONS_PREFIX:?Missing sdl2-mmiyoo-addons dependency prefix}"

mkdir -p "$work_dir/src" "$work_dir/downloads"
log "Cloning Yorisoft Pokedex source at $pokedex_ref"
git clone "$pokedex_repo" "$pokedex_dir"
git -C "$pokedex_dir" checkout --detach "$pokedex_ref"

[[ -d "$retrodex_dir" ]] || {
  printf 'Unexpected Yorisoft Pokedex source layout under %s\n' "$pokedex_dir" >&2
  exit 1
}

sqlite_archive="$work_dir/downloads/sqlite-amalgamation-3530400.zip"
curl --fail --location --retry 3 --output "$sqlite_archive" "$sqlite_url"
printf '%s  %s\n' "$sqlite_sha256" "$sqlite_archive" | sha256sum --check --status
unzip -q "$sqlite_archive" -d "$work_dir/src"
sqlite_dir="$work_dir/src/sqlite-amalgamation-3530400"
[[ -f "$sqlite_dir/sqlite3.c" && -f "$sqlite_dir/sqlite3.h" ]] || {
  printf 'SQLite amalgamation extraction failed: %s\n' "$sqlite_dir" >&2
  exit 1
}
mkdir -p "$retrodex_dir/core/include/sqlite"
install -m 644 "$sqlite_dir/sqlite3.c" "$sqlite_dir/sqlite3.h" "$retrodex_dir/core/include/sqlite/"

ensure_toolchain_image
log "Building Retrodex against the shared MMIYOO SDL2 and add-on providers"
docker run --rm \
  --user root \
  -e HOME=/root \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  --workdir /root/workspace \
  -v "$workspace_dir":/root/workspace \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  -v "$MMIYOO_SDL2_ADDONS_PREFIX":/opt/mmiyoo-sdl2-addons:ro \
  "$docker_image" \
  bash -lc '
    set -euo pipefail
    cleanup() { chown -R "$HOST_UID:$HOST_GID" /root/workspace; }
    trap cleanup EXIT
    rm -rf /root/workspace/build
    mkdir -p /root/workspace/build
    cp -a /opt/mmiyoo-sdl2/. /root/workspace/build/
    cp -a /opt/mmiyoo-sdl2-addons/. /root/workspace/build/
    cd /root/workspace/retrodex
    cp targets/miyoo/CMakeLists.txt ./CMakeLists.txt
    sed -i '"'"'/${SDL2_MIXER_LIBRARIES}/a\  /root/workspace/build/lib/libEGL.so /root/workspace/build/lib/libGLESv2.so /root/workspace/build/lib/libneonarmmiyoo.so'"'"' ./CMakeLists.txt
    cmake -S . -B build \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_C_COMPILER=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc \
      -DCMAKE_CXX_COMPILER=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-g++ \
      -DCMAKE_FIND_ROOT_PATH=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    cmake --build build -j"$(nproc)"
  '

[[ -x "$retrodex_dir/build/bin/retrodex" ]] || {
  printf 'Retrodex binary was not built: %s/build/bin/retrodex\n' "$retrodex_dir" >&2
  exit 1
}

log "Staging complete Onion app distribution"
cp -a "$pokedex_dir/App/Retrodex" "$app_root"
rm -f "$app_root/retrodex"
install -m 755 "$retrodex_dir/build/bin/retrodex" "$app_root/retrodex"

# The upstream package includes non-SDL runtime libraries.  Keep those and
# stage the one buildbot-owned SDL core plus the separately built add-ons.
mkdir -p "$app_root/lib"
cp -a "$MMIYOO_SDL2_ADDONS_PREFIX/lib/." "$app_root/lib/"
rm -f "$app_root/lib"/libSDL2.so* "$app_root/lib/libEGL.so" "$app_root/lib/libGLESv2.so" "$app_root/lib/libneonarmmiyoo.so"
for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
  install -m 755 "$MMIYOO_SDL2_PREFIX/lib/$library" "$app_root/lib/$library"
done
# This unused legacy GLESv1 library is present in the upstream prebuilt payload,
# but requires an additional libglapi runtime library. Retrodex and its freshly
# built SDL stack do not link to it.
rm -f "$app_root/lib/libGLESv1_CM.so"
verify_mmiyoo_runtime_closure "$app_root"

log "App distribution staged at $app_root"
