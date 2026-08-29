#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
stage_dir="${4:?stage dir required}"
source "$repo_root/packages/.shared/upstream-port.sh"

dungeonrush_repo="${DUNGEONRUSH_REPO:-https://github.com/XK9274/DungeonRush.git}"
dungeonrush_ref="${DUNGEONRUSH_REF:-master}"
source_dir="$work_dir/src/dungeonrush"
build_dir="$work_dir/build"
game_dir="$stage_dir/Roms/PORTS/Games/DungeonRush"

log() { printf '[%s] %s\n' "$package_id" "$*"; }

require_mmiyoo_sdl_provider
: "${MMIYOO_SDL2_ADDONS_PREFIX:?This package needs the sdl2-mmiyoo-addons dependency (for SDL2_image/SDL2_mixer/SDL2_net/SDL2_ttf).}"
for library in libSDL2_image libSDL2_mixer libSDL2_net libSDL2_ttf; do
  if ! compgen -G "$MMIYOO_SDL2_ADDONS_PREFIX/lib/${library}*.so*" >/dev/null; then
    printf 'Invalid MMIYOO SDL2 addons provider, missing %s: %s\n' "$library" "$MMIYOO_SDL2_ADDONS_PREFIX" >&2
    exit 1
  fi
done

image="$(ensure_union_toolchain_image)"
clone_pinned_source "$dungeonrush_repo" "$dungeonrush_ref" "$source_dir"

mkdir -p "$build_dir"
log "Cross-compiling DungeonRush $dungeonrush_ref via CMake"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$source_dir":/src \
  -v "$build_dir":/build \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  -v "$MMIYOO_SDL2_ADDONS_PREFIX":/opt/mmiyoo-sdl2-addons:ro \
  --workdir /build \
  "$image" bash -lc '
    set -euo pipefail
    cross=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-
    CC="${cross}gcc"
    CXX="${cross}g++"
    STRIP="${cross}strip"
    sysroot=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc

    # Pre-seed the FindSDL2*.cmake cache vars directly to avoid CMAKE_FIND_ROOT_PATH re-rooting.
    resolve_lib() {
      find "$1" -maxdepth 1 -name "$2" -print -quit
    }
    sdl2_include=/opt/mmiyoo-sdl2/include/SDL2
    sdl2_library="$(resolve_lib /opt/mmiyoo-sdl2/lib "libSDL2.so")"
    image_include=/opt/mmiyoo-sdl2-addons/include/SDL2
    image_library="$(resolve_lib /opt/mmiyoo-sdl2-addons/lib "libSDL2_image*.so*")"
    mixer_include=/opt/mmiyoo-sdl2-addons/include/SDL2
    mixer_library="$(resolve_lib /opt/mmiyoo-sdl2-addons/lib "libSDL2_mixer*.so*")"
    net_include=/opt/mmiyoo-sdl2-addons/include/SDL2
    net_library="$(resolve_lib /opt/mmiyoo-sdl2-addons/lib "libSDL2_net*.so*")"
    ttf_include=/opt/mmiyoo-sdl2-addons/include/SDL2
    ttf_library="$(resolve_lib /opt/mmiyoo-sdl2-addons/lib "libSDL2_ttf*.so*")"

    for pair in "SDL2:$sdl2_library" "SDL2_image:$image_library" "SDL2_mixer:$mixer_library" "SDL2_net:$net_library" "SDL2_ttf:$ttf_library"; do
      name="${pair%%:*}"
      value="${pair#*:}"
      [[ -n "$value" ]] || { printf "Could not resolve library for %s under the addons/core provider\n" "$name" >&2; exit 1; }
    done

    cmake -S /src -B /build \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_FIND_ROOT_PATH="$sysroot" \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,/opt/mmiyoo-sdl2/lib:/opt/mmiyoo-sdl2-addons/lib" \
      -DSDL2_INCLUDE_DIR="$sdl2_include" \
      -DSDL2_LIBRARY="$sdl2_library" \
      -DSDL2_IMAGE_INCLUDE_DIR="$image_include" \
      -DSDL2_IMAGE_LIBRARY="$image_library" \
      -DSDL2_MIXER_INCLUDE_DIR="$mixer_include" \
      -DSDL2_MIXER_LIBRARY="$mixer_library" \
      -DSDL2_NET_INCLUDE_DIR="$net_include" \
      -DSDL2_NET_LIBRARY="$net_library" \
      -DSDL2_TTF_INCLUDE_DIR="$ttf_include" \
      -DSDL2_TTF_LIBRARY="$ttf_library"
    cmake --build /build --target dungeon_rush --parallel "$(nproc)"
    "$STRIP" --strip-unneeded /build/bin/dungeon_rush
  '

[[ -x "$build_dir/bin/dungeon_rush" ]] || {
  printf 'Expected dungeon_rush binary was not built: %s/bin\n' "$build_dir" >&2
  exit 1
}
[[ -d "$build_dir/bin/res" ]] || {
  printf 'Expected res/ directory was not staged by CMake: %s/bin/res\n' "$build_dir" >&2
  exit 1
}

log "Staging port"
mkdir -p "$game_dir/lib" \
  "$stage_dir/Roms/PORTS/Shortcuts/Arcade" \
  "$stage_dir/Roms/PORTS/Imgs"

install -m 755 "$build_dir/bin/dungeon_rush" "$game_dir/dungeon_rush"
rm -rf "$game_dir/res"
cp -R "$build_dir/bin/res" "$game_dir/res"
install -m 644 "$repo_root/packages/dungeonrush-mmiyoo/assets/icon.png" "$stage_dir/Roms/PORTS/Imgs/DungeonRush.png"

stage_mmiyoo_sdl_runtime "$MMIYOO_SDL2_PREFIX" "$game_dir/lib"
for pattern in libSDL2_image*.so* libSDL2_mixer*.so* libSDL2_net*.so* libSDL2_ttf*.so*; do
  for library in "$MMIYOO_SDL2_ADDONS_PREFIX"/lib/$pattern; do
    [[ -e "$library" ]] || continue
    install -m 755 "$library" "$game_dir/lib/$(basename "$library")"
  done
done

cat > "$stage_dir/Roms/PORTS/Shortcuts/Arcade/DungeonRush.port" <<'EOF'
#!/bin/sh
# Standalone Ports Script Template

# main configuration :
GameName="DungeonRush (Port)"
GameDir="DungeonRush"
GameExecutable="dungeon_rush"
GameDataFile=""

# additional configuration
KillAudioserver=1
PerformanceMode=0

# specific to this port :
Arguments=""

# running command line :
/mnt/SDCARD/Emu/PORTS/launch_standalone.sh "$GameName" "$GameDir" "$GameExecutable" "$Arguments" "$GameDataFile" "$KillAudioserver" "$PerformanceMode"
EOF
chmod 755 "$stage_dir/Roms/PORTS/Shortcuts/Arcade/DungeonRush.port"

install -m 644 "$repo_root/packages/dungeonrush-mmiyoo/README.md" "$game_dir/README.md"

verify_mmiyoo_runtime_closure "$game_dir" "$image"
log "Port staged at $game_dir"
