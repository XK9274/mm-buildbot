#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
app_dist_dir="${4:?app-dist dir required}"

blobby_repo="${BLOBBYVOLLEY2_REPO:-https://github.com/danielknobe/blobbyvolley2.git}"
blobby_ref="${BLOBBYVOLLEY2_REF:-c28c5fa87872b7592f34f5f86196e93d127b6cf9}"
physfs_repo="${PHYSFS_REPO:-https://github.com/icculus/physfs.git}"
physfs_ref="${PHYSFS_REF:-eb3383b532c5f74bfeb42ec306ba2cf80eed988c}"
union_dir="${UNION_TOOLCHAIN_DIR:-/home/mattpc/HueTesting/union-miyoomini-toolchain}"
package_dir="$repo_root/packages/blobbyvolley2-mmiyoo"
docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
blobby_image="${MIYOO_BLOBBYVOLLEY2_IMAGE:-${docker_image}-blobbyvolley2-build-v1}"
blobby_src="$work_dir/src/blobbyvolley2"
physfs_src="$work_dir/src/physfs"
cmake_modules_dir="$work_dir/cmake-modules"
app_root="$app_dist_dir/BlobbyVolley2"

log() { printf '[%s] %s\n' "$package_id" "$*"; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

ensure_image() {
  require_tool docker
  if ! docker image inspect "$docker_image" >/dev/null 2>&1; then
    [[ -f "$union_dir/Dockerfile" ]] || {
      printf 'Missing Union toolchain Dockerfile: %s/Dockerfile\n' "$union_dir" >&2
      exit 1
    }
    log "Building Docker image $docker_image from $union_dir"
    docker build -t "$docker_image" "$union_dir"
  fi
  if ! docker image inspect "$blobby_image" >/dev/null 2>&1; then
    log "Building Blobby Volley 2 dependency image $blobby_image"
    docker build --build-arg "BASE_IMAGE=$docker_image" -t "$blobby_image" "$package_dir"
  fi
}

toolchain_readelf() {
  local target="$1"
  shift
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$target":/work/input:ro \
    "$docker_image" \
    /opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-readelf "$@" /work/input
}

is_platform_library() {
  case "$1" in
    libc.so.*|libm.so.*|libdl.so.*|librt.so.*|libpthread.so.*|libstdc++.so.*|libgcc_s.so.*|ld-linux-armhf.so.*|libmi_*.so|libcam_os_wrapper.so)
      return 0 ;;
    *) return 1 ;;
  esac
}

verify_runtime_closure() {
  local target needed
  while IFS= read -r -d '' target; do
    while IFS= read -r needed; do
      if ! is_platform_library "$needed" && [[ ! -e "$app_root/lib/$needed" ]]; then
        printf 'Missing bundled runtime dependency for %s: %s\n' "$target" "$needed" >&2
        exit 1
      fi
    done < <(toolchain_readelf "$target" -d 2>/dev/null | awk -F'[][]' '/Shared library:/ { print $2 }')
  done < <(find "$app_root" -maxdepth 1 -type f -perm -0100 -print0; find "$app_root/lib" -type f -name '*.so*' -print0)
}

require_tool git
require_tool docker
: "${MMIYOO_SDL2_PREFIX:?Missing sdl2-mmiyoo-lib dependency prefix}"
[[ -d "$MMIYOO_SDL2_PREFIX/include/SDL2" ]] || {
  printf 'SDL provider does not expose headers at %s/include/SDL2\n' "$MMIYOO_SDL2_PREFIX" >&2
  exit 1
}

mkdir -p "$work_dir/src" "$cmake_modules_dir"
log "Cloning Blobby Volley 2 source at $blobby_ref"
git clone "$blobby_repo" "$blobby_src"
git -C "$blobby_src" checkout --detach "$blobby_ref"

log "Cloning PhysFS source at $physfs_ref"
git clone "$physfs_repo" "$physfs_src"
git -C "$physfs_src" checkout --detach "$physfs_ref"

# blobbyvolley2's deps/sdl2.cmake calls find_package(SDL2 REQUIRED) and falls
# back to defining its own SDL2::SDL2 target from SDL2_INCLUDE_DIRS/
# SDL2_LIBRARIES when no imported target is found -- there is no upstream
# SDL2Config.cmake staged in the sdl2-mmiyoo-lib bundle, so this Find module
# feeds that fallback path directly from the provider prefix mounted at
# /opt/mmiyoo-sdl2 inside the container.
cat > "$cmake_modules_dir/FindSDL2.cmake" <<'EOF'
set(SDL2_INCLUDE_DIRS /opt/mmiyoo-sdl2/include /opt/mmiyoo-sdl2/include/SDL2)
set(SDL2_LIBRARIES
  /opt/mmiyoo-sdl2/lib/libSDL2-2.0.so.0
  /opt/mmiyoo-sdl2/lib/libEGL.so
  /opt/mmiyoo-sdl2/lib/libGLESv2.so
  /opt/mmiyoo-sdl2/lib/libneonarmmiyoo.so)
set(SDL2_FOUND TRUE)
EOF

# deps/physfs.cmake expects the classic single-value PHYSFS_INCLUDE_DIR /
# PHYSFS_LIBRARY variables (there is no upstream FindPhysFS.cmake shipped
# with CMake). PhysFS is built as a static library below so no libphysfs.so
# needs to be bundled into the app-dist runtime closure.
cat > "$cmake_modules_dir/FindPhysFS.cmake" <<'EOF'
set(PHYSFS_INCLUDE_DIR /workspace/physfs-prefix/include)
set(PHYSFS_LIBRARY /workspace/physfs-prefix/lib/libphysfs.a)
set(PHYSFS_FOUND TRUE)
EOF

ensure_image
log "Building PhysFS and Blobby Volley 2 against the shared MMIYOO SDL2 provider"
docker run --rm --user root -e HOME=/root \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  --workdir /workspace \
  -v "$work_dir":/workspace \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  "$blobby_image" bash -lc '
    set -euo pipefail
    cleanup() { chown -R "$HOST_UID:$HOST_GID" /workspace; }
    trap cleanup EXIT

    sysroot=/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc
    cross_cc=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc
    cross_cxx=/opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-g++

    # Boost is header-only for this project (algorithm/string, crc, exception);
    # its FindBoost.cmake module still does find_path() under the hood, which
    # CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY restricts to the sysroot -- so
    # stage the (architecture-independent) apt headers into the sysroot
    # instead of relaxing that mode for the whole build.
    mkdir -p "$sysroot/usr/include"
    rm -rf "$sysroot/usr/include/boost"
    cp -a /usr/include/boost "$sysroot/usr/include/boost"

    rm -rf /workspace/physfs-build /workspace/physfs-prefix
    cmake -S /workspace/src/physfs -B /workspace/physfs-build \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_C_COMPILER="$cross_cc" \
      -DCMAKE_CXX_COMPILER="$cross_cxx" \
      -DCMAKE_FIND_ROOT_PATH="$sysroot" \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DCMAKE_INSTALL_PREFIX=/workspace/physfs-prefix \
      -DPHYSFS_BUILD_SHARED=OFF \
      -DPHYSFS_BUILD_TEST=OFF \
      -DPHYSFS_BUILD_DOCS=OFF
    cmake --build /workspace/physfs-build -j"$(nproc)"
    cmake --install /workspace/physfs-build

    rm -rf /workspace/blobby-build
    cmake -S /workspace/src/blobbyvolley2 -B /workspace/blobby-build \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_C_COMPILER="$cross_cc" \
      -DCMAKE_CXX_COMPILER="$cross_cxx" \
      -DCMAKE_FIND_ROOT_PATH="$sysroot" \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DCMAKE_MODULE_PATH=/workspace/cmake-modules \
      -DBUILD_TESTS=OFF
    cmake --build /workspace/blobby-build -j"$(nproc)"
  '

blobby_bin="$(find "$work_dir/blobby-build" -maxdepth 2 -type f -name blobby -perm -0100 | head -n1)"
[[ -n "$blobby_bin" ]] || {
  printf 'Blobby Volley 2 binary was not built under %s/blobby-build\n' "$work_dir" >&2
  exit 1
}

log "Staging app distribution"
mkdir -p "$app_root/lib"
install -m 755 "$blobby_bin" "$app_root/blobby"

# Engine data search order (src/main.cpp) tries, in this priority: ./data,
# then the executable's own directory, then (unix installs only) a
# compile-time BLOBBY_DATA_DIR -- so it's simplest and most relocatable to
# keep the data zips and lua/xml files directly alongside the binary rather
# than relying on any baked-in install prefix.
data_src="$work_dir/src/blobbyvolley2/data"
data_build="$work_dir/blobby-build/data"
for archive in gfx sounds scripts backgrounds rules; do
  zip_file="$(find "$data_build" -maxdepth 1 -name "$archive.zip" | head -n1)"
  [[ -n "$zip_file" ]] || { printf 'Missing built data archive: %s.zip\n' "$archive" >&2; exit 1; }
  install -m 644 "$zip_file" "$app_root/$archive.zip"
done
for file in api.lua bot_api.lua rules_api.lua config.xml inputconfig.xml server.xml \
            lang_cs.xml lang_de.xml lang_en.xml lang_es.xml lang_fr.xml lang_it.xml; do
  install -m 644 "$data_src/$file" "$app_root/$file"
done

for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
  install -m 755 "$MMIYOO_SDL2_PREFIX/lib/$library" "$app_root/lib/$library"
done

# libEGL.so needs libz.so.1, which only exists inside the toolchain image's
# sysroot, not on the host -- locate and copy it out via a throwaway container.
if [[ ! -f "$app_root/lib/libz.so.1" ]]; then
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$app_root/lib":/workspace/out \
    "$docker_image" \
    bash -c 'found=$(find /opt/miyoomini-toolchain -name "libz.so.1" | head -1); [ -n "$found" ] && cp -aL "$found" /workspace/out/libz.so.1'
fi

verify_runtime_closure
log "App distribution staged at $app_root"
