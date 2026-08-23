#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
source_dir="${3:?source directory required}"
host_root="${4:?host root required}"

physfs_repo="${PHYSFS_HOST_REPO:-https://github.com/icculus/physfs.git}"
physfs_ref="${PHYSFS_HOST_REF:-eb3383b532c5f74bfeb42ec306ba2cf80eed988c}"
physfs_source="$host_root/source/physfs"
physfs_build="$host_root/physfs-build"
physfs_prefix="$host_root/physfs-prefix"

log() { printf '[%s host] %s\n' "$package_id" "$*"; }

command -v git >/dev/null 2>&1 || { printf 'Missing required host command: git\n' >&2; exit 1; }
command -v cmake >/dev/null 2>&1 || { printf 'Missing required host command: cmake\n' >&2; exit 1; }

mkdir -p "$host_root/source" "$host_root/cmake"
if [[ ! -d "$physfs_source/.git" ]]; then
  log "Cloning PhysFS at $physfs_ref"
  git clone "$physfs_repo" "$physfs_source"
  git -C "$physfs_source" checkout --detach "$physfs_ref"
fi

log "Building native PhysFS"
cmake -S "$physfs_source" -B "$physfs_build" \
  -DCMAKE_BUILD_TYPE="${HOST_BUILD_TYPE:-Debug}" \
  -DCMAKE_INSTALL_PREFIX="$physfs_prefix" \
  -DPHYSFS_BUILD_SHARED=OFF \
  -DPHYSFS_BUILD_TEST=OFF \
  -DPHYSFS_BUILD_DOCS=OFF
cmake --build "$physfs_build" --parallel "${HOST_JOBS:-$(nproc)}"
cmake --install "$physfs_build"

physfs_library="$physfs_prefix/lib/libphysfs.a"
physfs_include="$physfs_prefix/include"
[[ -f "$physfs_library" ]] || {
  printf 'Native PhysFS library was not produced: %s\n' "$physfs_library" >&2
  exit 1
}
[[ -d "$physfs_include" ]] || {
  printf 'Native PhysFS headers were not installed: %s\n' "$physfs_include" >&2
  exit 1
}

cat > "$host_root/cmake/FindPhysFS.cmake" <<EOF
set(PHYSFS_INCLUDE_DIR "$physfs_include")
set(PHYSFS_LIBRARY "$physfs_library")
set(PhysFS_FOUND TRUE)
set(PHYSFS_FOUND TRUE)
EOF
