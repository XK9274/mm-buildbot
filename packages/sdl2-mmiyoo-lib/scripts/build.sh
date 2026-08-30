#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
bundle_dir="${4:?bundle dir required}"
source "$repo_root/packages/.shared/upstream-port.sh"

sdl_repo="${SDL2_MIYOO_REPO:-https://github.com/XK9274/sdl2_miyoo.git}"
sdl_ref="${SDL2_MIYOO_REF:-main}"
sdl_dir="$work_dir/src/sdl2_miyoo"
# Local-only override: copies working-tree bytes as-is (cp -a), no commit/push needed.
sdl_local_repo="${SDL2_MIYOO_LOCAL_REPO:-}"
enable_gles="${SDL2_MIYOO_ENABLE_GLES:-1}"
# Local-only override for testing a neon-arm-library-miyoo branch that hasn't
# been pushed to the real remote yet -- mounted read-only into the container
# and passed to mk_miyoo.sh as NEON_REPO (file:// URL) so nothing touches the
# actual GitHub repo. Leave unset for the normal/default build.
neon_local_repo="${SDL2_MIYOO_NEON_LOCAL_REPO:-}"
strip_flag=""
[[ "${SDL2_MIYOO_DEBUG:-0}" == "1" ]] && strip_flag="--no-strip"

log() {
  printf '[%s] %s\n' "$package_id" "$*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

stage_headers() {
  local source_dir="$1"
  local destination="$2"

  mkdir -p "$destination/include"
  if [[ -d "$source_dir/include/SDL2" ]]; then
    cp -R "$source_dir/include/SDL2" "$destination/include/"
  elif [[ -f "$source_dir/include/SDL.h" ]]; then
    mkdir -p "$destination/include/SDL2"
    cp -R "$source_dir/include/." "$destination/include/SDL2/"
  else
    printf 'Expected SDL2 headers are missing under %s/include\n' "$source_dir" >&2
    exit 1
  fi

  [[ -f "$source_dir/src/video/khronos/EGL/egl.h" ]] || {
    printf 'Expected EGL development headers are missing: %s/src/video/khronos/EGL/egl.h\n' "$source_dir" >&2
    exit 1
  }
  cp -R "$source_dir/src/video/khronos/." "$destination/include/"
}

mkdir -p "$work_dir/src" "$bundle_dir/bin" "$bundle_dir/lib" "$bundle_dir/include" "$bundle_dir/lib/pkgconfig"

if [[ -n "$sdl_local_repo" ]]; then
  [[ -d "$sdl_local_repo" ]] || {
    printf 'SDL2_MIYOO_LOCAL_REPO is not a directory: %s\n' "$sdl_local_repo" >&2
    exit 1
  }
  log "Copying local sdl2_miyoo checkout from $sdl_local_repo"
  mkdir -p "$sdl_dir"
  cp -a "$sdl_local_repo/." "$sdl_dir/"
else
  require_tool git
  if [[ ! -d "$sdl_dir/.git" ]]; then
    log "Cloning SDL2 from $sdl_repo ($sdl_ref)"
    git clone "$sdl_repo" "$sdl_dir"
    git -C "$sdl_dir" checkout --detach "$sdl_ref"
  else
    log "Updating SDL2 in $sdl_dir"
    git -C "$sdl_dir" fetch origin "$sdl_ref"
    git -C "$sdl_dir" checkout --force --detach FETCH_HEAD
  fi
fi

gles_flag=""
[[ "$enable_gles" == "1" ]] && gles_flag="--enable-gles"

image="$(ensure_union_toolchain_image)"
log "Building SDL2 via mk_miyoo.sh ($gles_flag $strip_flag --clean build) in $image"
neon_mount_args=()
neon_repo_env=""
if [[ -n "$neon_local_repo" ]]; then
  [[ -d "$neon_local_repo/.git" ]] || {
    printf 'SDL2_MIYOO_NEON_LOCAL_REPO does not look like a git repo: %s\n' "$neon_local_repo" >&2
    exit 1
  }
  log "Using local neon-arm-library-miyoo checkout: $neon_local_repo"
  neon_mount_args=(-v "$neon_local_repo":/workspace/neon-src:ro)
  neon_repo_env="file:///workspace/neon-src"
fi
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e NEON_REF="${SDL2_MIYOO_NEON_REF:-}" \
  -e NEON_REPO="$neon_repo_env" \
  "${neon_mount_args[@]}" \
  --workdir /workspace/sdl2 \
  -v "$sdl_dir":/workspace/sdl2 \
  "$image" \
  /workspace/sdl2/build-scripts/mk_miyoo.sh $gles_flag $strip_flag --clean build

[[ -f "$sdl_dir/output/libSDL2-2.0.so.0" ]] || {
  printf 'Expected SDL output was not built: %s/output/libSDL2-2.0.so.0\n' "$sdl_dir" >&2
  exit 1
}
install -m 755 "$sdl_dir/output/libSDL2-2.0.so.0" "$bundle_dir/lib/libSDL2-2.0.so.0"

if [[ "$enable_gles" == "1" ]]; then
  for library in libEGL.so libGLESv2.so; do
    [[ -f "$sdl_dir/$library" ]] || {
      printf 'Expected vendored EGL/GLES library is missing: %s/%s\n' "$sdl_dir" "$library" >&2
      exit 1
    }
    install -m 755 "$sdl_dir/$library" "$bundle_dir/lib/$library"
  done
fi

[[ -f "$sdl_dir/libneonarmmiyoo.so" ]] || {
  printf 'Expected shared Neon helper was not built: %s/libneonarmmiyoo.so\n' "$sdl_dir" >&2
  exit 1
}
install -m 755 "$sdl_dir/libneonarmmiyoo.so" "$bundle_dir/lib/libneonarmmiyoo.so"
ln -sf libSDL2-2.0.so.0 "$bundle_dir/lib/libSDL2.so"

stage_headers "$sdl_dir" "$bundle_dir"

gl_libs=""
[[ "$enable_gles" == "1" ]] && gl_libs="-lEGL -lGLESv2 "

cat > "$bundle_dir/lib/pkgconfig/sdl2.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: sdl2-mmiyoo
Description: SDL2 MMIYOO backend
Version: 2.0.0
Libs: -L\${libdir} -lSDL2 ${gl_libs}-lneonarmmiyoo
Cflags: -I\${includedir}/SDL2 -I\${includedir}
EOF
cat > "$bundle_dir/bin/sdl2-config" <<EOF
#!/usr/bin/env sh
prefix=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
case "\${1:-}" in
  --cflags) printf '%s\n' "-I\$prefix/include/SDL2 -I\$prefix/include" ;;
  --libs) printf '%s\n' "-L\$prefix/lib -lSDL2 ${gl_libs}-lneonarmmiyoo" ;;
  --version) printf '%s\n' '2.0' ;;
  *) printf '%s\n' 'usage: sdl2-config [--cflags|--libs|--version]' >&2; exit 1 ;;
esac
EOF
chmod 755 "$bundle_dir/bin/sdl2-config"
if [[ -f "$sdl_dir/COPYING.txt" ]]; then
  install -m 644 "$sdl_dir/COPYING.txt" "$bundle_dir/SDL2-COPYING.txt"
elif [[ -f "$sdl_dir/COPYING" ]]; then
  install -m 644 "$sdl_dir/COPYING" "$bundle_dir/SDL2-COPYING.txt"
elif [[ -f "$sdl_dir/LICENSE" ]]; then
  install -m 644 "$sdl_dir/LICENSE" "$bundle_dir/SDL2-COPYING.txt"
else
  printf 'Expected SDL license file is missing: %s/COPYING[.txt] or LICENSE\n' "$sdl_dir" >&2
  exit 1
fi
install -m 644 "$repo_root/packages/sdl2-mmiyoo-lib/README.md" "$bundle_dir/README.md"

log "Shared-library bundle staged at $bundle_dir"
