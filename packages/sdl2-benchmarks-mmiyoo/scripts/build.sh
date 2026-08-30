#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
app_dist_dir="${4:?app-dist dir required}"

source "$repo_root/packages/.shared/upstream-port.sh"

benchmark_repo="${BENCHMARK_REPO:-https://github.com/XK9274/miyoo_sdl2_benchmarks.git}"
benchmark_ref="${BENCHMARK_REF:-main}"
local_source="${BENCHMARK_SOURCE_DIR:-}"
benchmark_src="$work_dir/src/miyoo_sdl2_benchmarks"
app_root="$app_dist_dir/sdl_bench"

log() {
  printf '[%s] %s\n' "$package_id" "$*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

require_tool docker
require_mmiyoo_sdl_provider
: "${MMIYOO_SDL2_ADDONS_PREFIX:?Missing sdl2-mmiyoo-addons dependency prefix}"

[[ -d "$MMIYOO_SDL2_PREFIX/include/SDL2" ]] || {
  printf 'SDL provider does not expose headers at %s/include/SDL2\n' "$MMIYOO_SDL2_PREFIX" >&2
  exit 1
}
[[ -d "$MMIYOO_SDL2_ADDONS_PREFIX/include/SDL2" ]] || {
  printf 'SDL add-on provider does not expose headers at %s/include/SDL2\n' "$MMIYOO_SDL2_ADDONS_PREFIX" >&2
  exit 1
}

mkdir -p "$work_dir/src"
if [[ -n "$local_source" ]]; then
  [[ -d "$local_source" ]] || {
    printf 'BENCHMARK_SOURCE_DIR is not a directory: %s\n' "$local_source" >&2
    exit 1
  }
  log "Copying local benchmark source from $local_source"
  mkdir -p "$benchmark_src"
  cp -a "$local_source/." "$benchmark_src/"
else
  require_tool git
  log "Cloning benchmark source at $benchmark_ref"
  git clone "$benchmark_repo" "$benchmark_src"
  git -C "$benchmark_src" checkout --detach "$benchmark_ref"
fi

[[ -f "$benchmark_src/Makefile" ]] || {
  printf 'Benchmark Makefile is missing: %s/Makefile\n' "$benchmark_src" >&2
  exit 1
}
[[ -d "$benchmark_src/app-dist/sdl_bench" ]] || {
  printf 'Benchmark app template is missing: %s/app-dist/sdl_bench\n' "$benchmark_src" >&2
  exit 1
}

image="$(ensure_union_toolchain_image)"
log "Building benchmark suite against shared MMIYOO SDL providers"
docker run --rm \
  --user root \
  -e HOME=/root \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -e DEBUG="${DEBUG:-0}" \
  -e TITLE_GIT_VERSION="${TITLE_GIT_VERSION:-}" \
  --workdir /workspace/src/miyoo_sdl2_benchmarks \
  -v "$work_dir":/workspace \
  -v "$MMIYOO_SDL2_PREFIX":/opt/mmiyoo-sdl2:ro \
  -v "$MMIYOO_SDL2_ADDONS_PREFIX":/opt/mmiyoo-sdl2-addons:ro \
  "$image" bash -lc '
    set -euo pipefail
    cleanup() { chown -R "$HOST_UID:$HOST_GID" /workspace; }
    trap cleanup EXIT

    export CROSS_PREFIX=/opt/miyoomini-toolchain/usr/bin/arm-linux-gnueabihf-
    export SYSROOT=/opt/miyoomini-toolchain/usr/arm-linux-gnueabihf/sysroot
    export SDL_PREFIX=/opt/mmiyoo-sdl2
    export SDL_ADDONS_PREFIX=/opt/mmiyoo-sdl2-addons
    export PATH=/opt/miyoomini-toolchain/usr/bin:$PATH

    cd /workspace/src/miyoo_sdl2_benchmarks
    make clean
    if [[ -n "$TITLE_GIT_VERSION" ]]; then
      make DEBUG="$DEBUG" TITLE_GIT_VERSION="$TITLE_GIT_VERSION"
    else
      make DEBUG="$DEBUG"
    fi
  '

expected_binaries=(
  sdl2_title
  sdl2_bench_double_buf
  sdl2_space_bench
  sdl2_render_suite
  sdl2_gl_fbo_effects
  sdl2_audio_bench
  sdl2_sprite_bench
  sdl2_gfx_bench
  sdl2_obj_model_loader
)

for binary in "${expected_binaries[@]}"; do
  [[ -x "$benchmark_src/build/bin/$binary" ]] || {
    printf 'Expected benchmark binary is missing: %s\n' "$benchmark_src/build/bin/$binary" >&2
    exit 1
  }
done

log "Staging benchmark app distribution"
mkdir -p "$app_root/bin" "$app_root/lib"
cp -a "$benchmark_src/app-dist/sdl_bench/." "$app_root/"

for binary in "${expected_binaries[@]}"; do
  install -m 755 "$benchmark_src/build/bin/$binary" "$app_root/bin/$binary"
done

for library in libSDL2-2.0.so.0 libEGL.so libGLESv2.so libneonarmmiyoo.so; do
  [[ -f "$MMIYOO_SDL2_PREFIX/lib/$library" ]] || {
    printf 'Missing SDL runtime library: %s/lib/%s\n' "$MMIYOO_SDL2_PREFIX" "$library" >&2
    exit 1
  }
  install -m 755 "$MMIYOO_SDL2_PREFIX/lib/$library" "$app_root/lib/$library"
done

for pattern in libSDL2_ttf*.so* libSDL2_gfx*.so* libSDL2_image*.so*; do
  found=0
  for library in "$MMIYOO_SDL2_ADDONS_PREFIX"/lib/$pattern; do
    [[ -e "$library" || -L "$library" ]] || continue
    cp -aL "$library" "$app_root/lib/"
    found=1
  done
  [[ "$found" == 1 ]] || {
    printf 'Missing SDL add-on runtime library matching %s\n' "$pattern" >&2
    exit 1
  }
done

if [[ -f "$MMIYOO_SDL2_ADDONS_PREFIX/lib/libz.so.1" ]]; then
  install -m 755 "$MMIYOO_SDL2_ADDONS_PREFIX/lib/libz.so.1" "$app_root/lib/libz.so.1"
fi
if [[ ! -f "$app_root/lib/libz.so.1" ]]; then
  docker run --rm --user "$(id -u):$(id -g)" \
    -v "$app_root/lib":/workspace/out \
    "$image" \
    bash -c 'found=$(find /opt/miyoomini-toolchain -name "libz.so.1" | head -n 1); [ -n "$found" ] && cp -aL "$found" /workspace/out/libz.so.1'
fi

verify_mmiyoo_runtime_closure "$app_root" "$image"
log "Benchmark app distribution staged at $app_root"
