#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
app_dist_dir="${4:?app-dist dir required}"
source "$repo_root/packages/.shared/port-common.sh"

konpacto_repo="${KONPACTO_REPO:-https://github.com/wapordev/konpacto.git}"
konpacto_ref="${KONPACTO_REF:-2d196a918bcd8311f57b46e75d60a390f0464701}"
luajit_repo="${LUAJIT_REPO:-https://github.com/LuaJIT/LuaJIT.git}"
luajit_ref="${LUAJIT_REF:-1ee778a4e37122d8ca7d5733c590a47dafd6b15c}"
tinydir_repo="${TINYDIR_REPO:-https://github.com/cxong/tinydir.git}"
tinydir_ref="${TINYDIR_REF:-1.2.6}"
union_dir="${UNION_TOOLCHAIN_DIR:?UNION_TOOLCHAIN_DIR required (path to your Union Miyoo Mini toolchain checkout)}"
base_docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
docker_image="${KONPACTO_TOOLCHAIN_IMAGE:-miyoomini-toolchain-konpacto}"
toolchain_dockerfile="$repo_root/docker/konpacto-mmiyoo-toolchain/Dockerfile"

konpacto_dir="$work_dir/src/konpacto"
luajit_dir="$work_dir/src/LuaJIT"
tinydir_dir="$work_dir/src/tinydir"
app_root="$app_dist_dir/Konpacto"

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
  [[ -f "$toolchain_dockerfile" ]] || {
    printf 'Missing Konpacto toolchain Dockerfile: %s\n' "$toolchain_dockerfile" >&2
    exit 1
  }
  if ! docker image inspect "$base_docker_image" >/dev/null 2>&1; then
    log "Building base Docker image $base_docker_image from $union_dir"
    docker build -t "$base_docker_image" "$union_dir"
  fi
  log "Building Konpacto toolchain image $docker_image with 32-bit host support"
  docker build --build-arg BASE_IMAGE="$base_docker_image" \
    -f "$toolchain_dockerfile" -t "$docker_image" "$repo_root"
}

require_tool git
require_tool docker

: "${MMIYOO_SDL2_PREFIX:?Missing sdl2-mmiyoo-lib dependency prefix}"
: "${MMIYOO_SDL2_ADDONS_PREFIX:?Missing sdl2-mmiyoo-addons dependency prefix}"

mkdir -p "$work_dir/src"

log "Cloning konpacto source at $konpacto_ref"
git clone "$konpacto_repo" "$konpacto_dir"
git -C "$konpacto_dir" checkout --detach "$konpacto_ref"

log "Cloning LuaJIT source at $luajit_ref (built fresh per package; not shared with love-mmiyoo-demo's host copy)"
git clone "$luajit_repo" "$luajit_dir"
git -C "$luajit_dir" checkout --detach "$luajit_ref"

log "Cloning tinydir header at $tinydir_ref (konpacto's own source tree does not vendor it)"
git clone "$tinydir_repo" "$tinydir_dir"
git -C "$tinydir_dir" checkout --detach "$tinydir_ref"
install -m 644 "$tinydir_dir/tinydir.h" "$konpacto_dir/src/tinydir.h"

ensure_toolchain_image

log "Cross-compiling LuaJIT and konpacto against the shared MMIYOO SDL2 and add-on providers"
docker run --rm \
  --user root \
  -e HOME=/root \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  --workdir /root/workspace \
  -v "$konpacto_dir":/root/workspace/konpacto \
  -v "$luajit_dir":/root/workspace/LuaJIT \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  -v "$MMIYOO_SDL2_ADDONS_PREFIX":/opt/mmiyoo-sdl2-addons:ro \
  "$docker_image" \
  bash -lc '
    set -euo pipefail
    cleanup() { chown -R "$HOST_UID:$HOST_GID" /root/workspace; }
    trap cleanup EXIT

    cross_root=/opt/miyoomini-toolchain
    export PATH="$cross_root/bin:$PATH"
    target_cflags="-march=armv7ve -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"

    cd /root/workspace/LuaJIT
    make clean >/dev/null 2>&1 || true
    # Static build: one less .so to bundle/verify in the app-dist runtime closure.
    make -j"$(nproc)" \
      CROSS=arm-linux-gnueabihf- \
      HOST_CC="gcc -m32" \
      TARGET_SYS=Linux \
      TARGET_CFLAGS="$target_cflags" \
      BUILDMODE=static
    make install PREFIX=/root/workspace/luajit-install

    luajit_include=$(find /root/workspace/luajit-install/include -maxdepth 1 -type d -name "luajit-*" | head -n1)
    [ -n "$luajit_include" ] || { echo "LuaJIT headers not found after install" >&2; exit 1; }

    mkdir -p /root/workspace/konpacto/build
    cd /root/workspace/konpacto
    arm-linux-gnueabihf-gcc \
      -O2 -Wall -std=gnu11 \
      -Isrc \
      -I/opt/mmiyoo-sdl2/include/SDL2 -I/opt/mmiyoo-sdl2/include \
      -I/opt/mmiyoo-sdl2-addons/include/SDL2 -I/opt/mmiyoo-sdl2-addons/include \
      -I"$luajit_include" \
      src/lua.c src/screen.c src/input.c src/pages.c src/file.c src/ui.c src/main.c src/sound.c src/synth.c src/sequence.c \
      -L/opt/mmiyoo-sdl2/lib -L/opt/mmiyoo-sdl2-addons/lib \
      -Wl,-Bstatic -L/root/workspace/luajit-install/lib -lluajit-5.1 -Wl,-Bdynamic \
      -lSDL2 -lSDL2_image -lSDL2_mixer -lEGL -lGLESv2 -lneonarmmiyoo -lm -ldl -lpthread \
      -o build/konpacto
  '

[[ -x "$konpacto_dir/build/konpacto" ]] || {
  printf 'konpacto binary was not built: %s/build/konpacto\n' "$konpacto_dir" >&2
  exit 1
}

log "Staging app distribution"
mkdir -p "$app_root/bin" "$app_root/lib"
install -m 755 "$konpacto_dir/build/konpacto" "$app_root/bin/konpacto"

cp -aL "$MMIYOO_SDL2_ADDONS_PREFIX/lib/." "$app_root/lib/"
for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
  install -m 755 "$MMIYOO_SDL2_PREFIX/lib/$library" "$app_root/lib/$library"
done
install -m 755 "$MMIYOO_SDL2_PREFIX/lib/libSDL2-2.0.so.0" "$app_root/lib/libSDL2.so"

# konpacto's own source reads/writes paths like "assets/songs" relative to
# its working directory, so its assets must sit at the app root, not under
# a res/ prefix like other packages here.
cp -a "$konpacto_dir/src/assets" "$app_root/assets"

verify_mmiyoo_runtime_closure "$app_root"

log "App distribution staged at $app_root"
