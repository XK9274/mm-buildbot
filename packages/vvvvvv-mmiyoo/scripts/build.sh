#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
stage_dir="${4:?stage dir required}"
source "$repo_root/packages/.shared/upstream-port.sh"

vvv_repo="https://github.com/TerryCavanagh/VVVVVV.git"
vvv_ref="2.3.6"
source_dir="$work_dir/src/vvvvvv"
build_dir="$work_dir/build"
game_dir="$stage_dir/Roms/PORTS/Games/VVVVVV"

log() { printf '[%s] %s\n' "$package_id" "$*"; }

require_mmiyoo_sdl_provider
: "${MMIYOO_SDL2_ADDONS_PREFIX:?This package needs the sdl2-mmiyoo-addons dependency (for SDL2_mixer).}"
[[ -f "$MMIYOO_SDL2_ADDONS_PREFIX/lib/libSDL2_mixer-2.0.so.0" ]] || {
  printf 'Invalid MMIYOO SDL2 addons provider: %s\n' "$MMIYOO_SDL2_ADDONS_PREFIX" >&2
  exit 1
}
image="$(ensure_union_toolchain_image)"
clone_pinned_source "$vvv_repo" "$vvv_ref" "$source_dir"

mkdir -p "$build_dir"
log "Cross-compiling VVVVVV $vvv_ref via CMake"
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
    export CC="${cross}gcc"
    export CXX="${cross}g++"
    export STRIP="${cross}strip"
    flags="-Os -marm -mtune=cortex-a7 -march=armv7ve+simd -mfpu=neon-vfpv4 -mfloat-abi=hard"
    cmake -S /src/desktop_version -B /build \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSTEM_PROCESSOR=arm \
      -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$flags" \
      -DCMAKE_CXX_FLAGS="$flags" \
      -DCMAKE_EXE_LINKER_FLAGS="-L/opt/mmiyoo-sdl2/lib -L/opt/mmiyoo-sdl2-addons/lib -Wl,-rpath-link,/opt/mmiyoo-sdl2/lib:/opt/mmiyoo-sdl2-addons/lib" \
      -DCMAKE_BUILD_TYPE=Release \
      -DSDL2_INCLUDE_DIRS="/opt/mmiyoo-sdl2/include/SDL2;/opt/mmiyoo-sdl2-addons/include/SDL2" \
      -DSDL2_LIBRARIES="/opt/mmiyoo-sdl2/lib/libSDL2-2.0.so.0;/opt/mmiyoo-sdl2-addons/lib/libSDL2_mixer-2.0.so.0"
    cmake --build /build --target VVVVVV --parallel "$(nproc)"
    "$STRIP" --strip-unneeded /build/VVVVVV
  '

[[ -x "$build_dir/VVVVVV" ]] || {
  printf 'Expected VVVVVV binary was not built: %s\n' "$build_dir" >&2
  exit 1
}

mkdir -p "$game_dir" "$game_dir/lib" \
  "$stage_dir/Roms/PORTS/Shortcuts/Arcade" \
  "$stage_dir/Roms/PORTS/Imgs"

install -m 755 "$build_dir/VVVVVV" "$game_dir/VVVVVV"
install -m 644 "$repo_root/packages/vvvvvv-mmiyoo/assets/icon.png" "$stage_dir/Roms/PORTS/Imgs/VVVVVV.png"

# No GL/EGL/GLES symbols in this binary (confirmed against the pinned
# source), so the no-GLES core alone plus SDL2_mixer is the full runtime.
install -m 755 "$MMIYOO_SDL2_PREFIX/lib/libSDL2-2.0.so.0" "$game_dir/lib/libSDL2-2.0.so.0"
install -m 755 "$MMIYOO_SDL2_PREFIX/lib/libneonarmmiyoo.so" "$game_dir/lib/libneonarmmiyoo.so"
install -m 755 "$MMIYOO_SDL2_ADDONS_PREFIX/lib/libSDL2_mixer-2.0.so.0" "$game_dir/lib/libSDL2_mixer-2.0.so.0"

# Default joypad bindings: flip on every face button, Start/Select open the
# menu, Guide pauses -- exact files pulled from an on-device install that was
# hand-validated this session (not retyped, to avoid drifting from what was
# actually tested). VVVVVV reads/writes these relative to its own directory
# (the launcher sets HOME=$game_dir), so both settings.vvv and unlock.vvv
# (the "master" copy) need seeding here.
saves_dir="$game_dir/.local/share/VVVVVV/saves"
mkdir -p "$saves_dir"
install -m 644 "$repo_root/packages/vvvvvv-mmiyoo/assets/settings.vvv" "$saves_dir/settings.vvv"
install -m 644 "$repo_root/packages/vvvvvv-mmiyoo/assets/unlock.vvv" "$saves_dir/unlock.vvv"

cat > "$stage_dir/Roms/PORTS/Shortcuts/Arcade/VVVVVV.port" <<'EOF'
#!/bin/sh
# Standalone Ports Script Template

# main configuration :
GameName="VVVVVV (Port)"
GameDir="VVVVVV"
GameExecutable="VVVVVV"
GameDataFile="data.zip"

# additional configuration
KillAudioserver=1
PerformanceMode=0

# specific to this port :
Arguments=""

# running command line :
/mnt/SDCARD/Emu/PORTS/launch_standalone.sh "$GameName" "$GameDir" "$GameExecutable" "$Arguments" "$GameDataFile" "$KillAudioserver" "$PerformanceMode"
EOF
chmod 755 "$stage_dir/Roms/PORTS/Shortcuts/Arcade/VVVVVV.port"

cat > "$game_dir/PLACE data.zip HERE.txt" <<'EOF'
Retail VVVVVV game data is not redistributed here. Place your own data.zip
in this folder before launching.
EOF

install -m 644 "$repo_root/packages/vvvvvv-mmiyoo/README.md" "$stage_dir/README.md"

log "Port staged at $stage_dir"
