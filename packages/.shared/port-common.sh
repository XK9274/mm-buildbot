#!/usr/bin/env bash
# Common staging helpers for Miyoo Mini-family app distributions.

# Writes the standard Union-toolchain CMake cross-compile settings (compiler
# paths, sysroot, find-root-path modes) to destination. Callers still supply
# their own SDL2 Find-module strategy on top of this (custom module, or
# pre-seeded SDL2*_INCLUDE_DIR/LIBRARY cache vars); this only covers the
# boilerplate that's identical across every CMake-based cross-compile package.
write_mmiyoo_cmake_toolchain_file() {
  local destination="${1:?destination path required}"
  cat > "$destination" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-g++)
set(CMAKE_FIND_ROOT_PATH /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
}

stage_mmiyoo_sdl_runtime() {
  local prefix="${1:?SDL prefix required}"
  local destination="${2:?runtime destination required}"
  local library

  [[ -d "$prefix/lib" ]] || {
    printf 'MMIYOO SDL2 provider bundle is incomplete: %s\n' "$prefix" >&2
    return 1
  }
  mkdir -p "$destination"
  for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
    [[ -f "$prefix/lib/$library" ]] || {
      printf 'Missing SDL runtime library: %s/lib/%s\n' "$prefix" "$library" >&2
      return 1
    }
    install -m 755 "$prefix/lib/$library" "$destination/$library"
  done
}

require_owned_data_dir() {
  local variable="${1:?environment variable name required}"
  local description="${2:?data description required}"
  local path="${!variable:-}"

  [[ -n "$path" && -d "$path" ]] || {
    printf '%s must point to a directory containing %s. Proprietary game data is not bundled.\n' "$variable" "$description" >&2
    return 1
  }
  printf '%s\n' "$path"
}

is_mmiyoo_platform_library() {
  case "$1" in
    libc.so.*|libm.so.*|libdl.so.*|librt.so.*|libpthread.so.*|libstdc++.so.*|libgcc_s.so.*|libz.so.*|ld-linux-armhf.so.*|libmi_*.so|libcam_os_wrapper.so)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Clones/refreshes repo_url into repo_dir and builds image from its
# Dockerfile, skipping the build only when image already exists locally and
# repo_dir's HEAD SHA matches the SHA recorded from the last successful
# build (stamped in repo_dir/.mm-buildbot-build-stamp).
ensure_toolchain_image() {
  local name="${1:?toolchain name required}"
  local repo_url="${2:?toolchain repo url required}"
  local repo_dir="${3:?toolchain checkout dir required}"
  local image="${4:?toolchain image tag required}"
  local stamp_file="$repo_dir/.mm-buildbot-build-stamp"
  local current_sha

  command -v docker >/dev/null 2>&1 || {
    printf 'Missing required tool: docker\n' >&2
    return 1
  }

  if [[ ! -d "$repo_dir/.git" ]]; then
    printf 'Cloning %s toolchain from %s\n' "$name" "$repo_url" >&2
    mkdir -p "$(dirname "$repo_dir")"
    git clone --depth=1 "$repo_url" "$repo_dir" >&2
  else
    git -C "$repo_dir" fetch --depth=1 origin HEAD >&2
    git -C "$repo_dir" reset --hard FETCH_HEAD >&2
  fi

  [[ -f "$repo_dir/Dockerfile" ]] || {
    printf 'Missing %s toolchain Dockerfile: %s/Dockerfile\n' "$name" "$repo_dir" >&2
    return 1
  }

  current_sha="$(git -C "$repo_dir" rev-parse HEAD)"
  if docker image inspect "$image" >/dev/null 2>&1 \
    && [[ "$(cat "$stamp_file" 2>/dev/null)" == "$image:$current_sha" ]]; then
    printf '%s\n' "$image"
    return 0
  fi

  printf 'Building %s toolchain image %s from %s (%s)\n' "$name" "$image" "$repo_dir" "$current_sha" >&2
  docker build -t "$image" "$repo_dir" >&2
  printf '%s:%s' "$image" "$current_sha" > "$stamp_file"
  printf '%s\n' "$image"
}

# Builds a Dockerfile layered on top of base_image, skipping the build only
# when image already exists locally and the Dockerfile's content hash
# matches the hash recorded in stamp_file from the last successful build.
ensure_derived_toolchain_image() {
  local name="${1:?derived image name required}"
  local base_image="${2:?base image required}"
  local dockerfile="${3:?dockerfile required}"
  local context_dir="${4:?build context dir required}"
  local image="${5:?derived image tag required}"
  local stamp_file="${6:?stamp file required}"
  local current_hash

  command -v docker >/dev/null 2>&1 || {
    printf 'Missing required tool: docker\n' >&2
    return 1
  }
  [[ -f "$dockerfile" ]] || {
    printf 'Missing %s Dockerfile: %s\n' "$name" "$dockerfile" >&2
    return 1
  }

  mkdir -p "$(dirname "$stamp_file")"
  current_hash="$(sha256sum "$dockerfile" | awk '{print $1}')"

  if docker image inspect "$image" >/dev/null 2>&1 \
    && [[ "$(cat "$stamp_file" 2>/dev/null)" == "$base_image:$current_hash" ]]; then
    printf '%s\n' "$image"
    return 0
  fi

  printf 'Building %s image %s from %s (base %s)\n' "$name" "$image" "$dockerfile" "$base_image" >&2
  docker build --build-arg "BASE_IMAGE=$base_image" -f "$dockerfile" -t "$image" "$context_dir" >&2
  printf '%s:%s' "$base_image" "$current_hash" > "$stamp_file"
  printf '%s\n' "$image"
}

mmiyoo_toolchain_readelf() {
  local image="${1:?toolchain image required}"
  local target="${2:?target required}"
  shift 2
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$target":/work/input:ro \
    "$image" \
    /opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-readelf "$@" /work/input
}

# With a toolchain_image, readelf runs inside that Docker image (no host
# arm-linux-gnueabihf-readelf required); without one, it runs on the host.
verify_mmiyoo_runtime_closure() {
  local root="${1:?distribution root required}"
  local toolchain_image="${2:-}"
  local target needed

  if [[ -n "$toolchain_image" ]]; then
    command -v docker >/dev/null 2>&1 || {
      printf 'Missing required tool: docker\n' >&2
      return 1
    }
  else
    command -v arm-linux-gnueabihf-readelf >/dev/null 2>&1 || {
      printf 'Missing required tool: arm-linux-gnueabihf-readelf\n' >&2
      return 1
    }
  fi

  while IFS= read -r -d '' target; do
    while IFS= read -r needed; do
      is_mmiyoo_platform_library "$needed" && continue
      if ! find "$root" -name "$needed" -print -quit | grep -q .; then
        printf 'Missing bundled runtime dependency for %s: %s\n' "$target" "$needed" >&2
        return 1
      fi
    done < <(
      if [[ -n "$toolchain_image" ]]; then
        mmiyoo_toolchain_readelf "$toolchain_image" "$target" -d 2>/dev/null
      else
        arm-linux-gnueabihf-readelf -d "$target" 2>/dev/null
      fi | awk -F'[][]' '/Shared library:/ { print $2 }'
    )
  done < <(find "$root" -type f \( -perm -0100 -o -name '*.so*' \) -print0)
}
