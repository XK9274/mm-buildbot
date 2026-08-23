#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
app_dist_dir="${4:?app-dist dir required}"

love_repo="${LOVE_REPO:-https://github.com/love2d/love.git}"
love_ref="${LOVE_REF:-f834ab72481e95fa90abf573643c8dd168ae0660}"
union_dir="${UNION_TOOLCHAIN_DIR:-/home/mattpc/HueTesting/union-miyoomini-toolchain}"
package_dir="$repo_root/packages/love-mmiyoo-demo"
docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
love_image="${MIYOO_LOVE_IMAGE:-${docker_image}-love-build-v1}"
love_src="$work_dir/src/love"
app_root="$app_dist_dir/LoveMiyoo"

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
  if ! docker image inspect "$love_image" >/dev/null 2>&1; then
    log "Building LÖVE dependency image $love_image"
    docker build --build-arg "BASE_IMAGE=$docker_image" -t "$love_image" \
      "$repo_root/packages/love-mmiyoo-demo"
  fi
}

copy_soname_library() {
  local source="$1"
  local destination="$2"
  local soname
  soname="$(arm-linux-gnueabihf-readelf -d "$source" 2>/dev/null | awk -F'[][]' '/SONAME/ { print $2; exit }')"
  install -m 755 "$source" "$destination/${soname:-$(basename "$source")}" 
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
    done < <(arm-linux-gnueabihf-readelf -d "$target" 2>/dev/null | awk -F'[][]' '/Shared library:/ { print $2 }')
  done < <(find "$app_root" -type f -perm -0100 -print0; find "$app_root/lib" -type f -name '*.so*' -print0)
}

require_tool git
require_tool arm-linux-gnueabihf-readelf
: "${MMIYOO_SDL2_PREFIX:?Missing sdl2-mmiyoo-lib dependency prefix}"
[[ -d "$MMIYOO_SDL2_PREFIX/include/SDL2" ]] || {
  printf 'SDL provider does not expose headers at %s/include/SDL2\n' "$MMIYOO_SDL2_PREFIX" >&2
  exit 1
}

mkdir -p "$work_dir/src"
log "Cloning official LÖVE source at $love_ref"
git clone --depth=1 "$love_repo" "$love_src"
git -C "$love_src" fetch --depth=1 origin "$love_ref"
git -C "$love_src" checkout --detach FETCH_HEAD

# Vendored dependency builder, replacing its SDL hook with a provider
# installer below. No second SDL2 implementation is compiled here.
install -m 755 "$package_dir/build_love.sh" "$love_src/build_love.sh"
install -m 644 "$package_dir/cross.cmake" "$love_src/cross.cmake"
install -m 644 "$package_dir/sdl2.m4" "$love_src/sdl2.m4"
cat > "$love_src/mksdl2.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

prefix=/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot/usr

mkdir -p "$prefix/include" "$prefix/lib/pkgconfig"
rm -rf "$prefix/include/SDL2"
cp -a /opt/mmiyoo-sdl2/include/SDL2 "$prefix/include/"
install -m 755 /opt/mmiyoo-sdl2/lib/libSDL2-2.0.so.0 "$prefix/lib/libSDL2-2.0.so.0"
ln -sf libSDL2-2.0.so.0 "$prefix/lib/libSDL2.so"
# sdl2.pc's Libs: line pulls in -lEGL -lGLESv2 -lneonarmmiyoo too, so the
# linker needs all of them on the search path, not just SDL2 itself.
install -m 755 /opt/mmiyoo-sdl2/lib/libEGL.so "$prefix/lib/libEGL.so"
install -m 755 /opt/mmiyoo-sdl2/lib/libGLESv2.so "$prefix/lib/libGLESv2.so"
install -m 755 /opt/mmiyoo-sdl2/lib/libneonarmmiyoo.so "$prefix/lib/libneonarmmiyoo.so"
cp -a /opt/mmiyoo-sdl2/lib/pkgconfig/sdl2.pc "$prefix/lib/pkgconfig/"
EOF
chmod +x "$love_src/mksdl2.sh"

ensure_image
log 'Building LÖVE and dependencies with the GLES SDL provider'
docker run --rm --user root -e HOME=/root \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  --workdir /root/workspace/love \
  -v "$love_src":/root/workspace/love \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  "$love_image" bash -lc '
    set -euo pipefail
    cleanup() { chown -R "$HOST_UID:$HOST_GID" /root/workspace/love; }
    trap cleanup EXIT
    mkdir -p logs
    # aclocal needs AM_PATH_SDL2 findable before configure.ac is processed;
    # LOVEs autotools files reference it, but nothing installs the macro.
    install -m 644 sdl2.m4 /usr/share/aclocal/sdl2.m4
    # LOVE ships its autotools files under platform/unix/; build_love.sh
    # expects them already staged at the repo root (its own readme documents
    # running this first), but never runs it itself.
    bash platform/unix/automagic > logs/automagic.log 2>&1 || {
      tail -n 200 logs/automagic.log >&2
      exit 1
    }
    bash ./build_love.sh > logs/build_love.log 2>&1 || {
      tail -n 200 logs/build_love.log >&2
      exit 1
    }
  '

[[ -x "$love_src/output/love/love" ]] || {
  printf 'LÖVE build did not produce output/love/love\n' >&2
  exit 1
}
mkdir -p "$app_root/lib"
install -m 755 "$love_src/output/love/love" "$app_root/love"
cp -a "$love_src/output/love/lib/." "$app_root/lib/"

love_library="$(find "$love_src/src/.libs" -maxdepth 1 -type f -name 'liblove-*.so' | head -n 1)"
[[ -n "$love_library" ]] || { printf 'LÖVE build did not produce liblove\n' >&2; exit 1; }
copy_soname_library "$love_library" "$app_root/lib"

for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
  install -m 755 "$MMIYOO_SDL2_PREFIX/lib/$library" "$app_root/lib/$library"
done

# libfreetype/libz only exist inside the toolchain image's sysroot, not on
# the host -- locate and copy them out via a throwaway container.
mkdir -p "$work_dir/sysroot-libs"
for library in libfreetype.so.6 libz.so.1 libpng16.so.16 libatomic.so.1; do
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$work_dir/sysroot-libs":/workspace/out \
    "$docker_image" \
    bash -c "found=\$(find /opt/miyoomini-toolchain -name '$library' | head -1); [ -n \"\$found\" ] && cp -aL \"\$found\" /workspace/out/$library"
  candidate="$work_dir/sysroot-libs/$library"
  [[ -f "$candidate" ]] && copy_soname_library "$candidate" "$app_root/lib"
done

verify_runtime_closure
log "App distribution staged at $app_root"
