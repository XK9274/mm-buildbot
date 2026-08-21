#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?package id required}"
repo_root="${2:?repo root required}"
work_dir="${3:?work dir required}"
app_dist_dir="${4:?app-dist dir required}"

retroarch_repo="${RETROARCH_REPO:-https://github.com/libretro/RetroArch.git}"
retroarch_ref="${RETROARCH_REF:-master}"
retroarch_assets_repo="${RETROARCH_ASSETS_REPO:-https://github.com/libretro/retroarch-assets.git}"
retroarch_assets_ref="${RETROARCH_ASSETS_REF:-master}"
union_repo="${UNION_TOOLCHAIN_REPO:-https://github.com/XK9274/union-miyoomini-toolchain.git}"
union_dir="${UNION_TOOLCHAIN_DIR:-/home/mattpc/HueTesting/union-miyoomini-toolchain}"
build_swiftshader="${BUILD_SWIFTSHADER:-0}"
build_sdl2_stubs="${BUILD_SDL2_STUBS:-0}"
make_jobs="${MAKE_JOBS:-}"
docker_image="${MIYOO_TOOLCHAIN_IMAGE:-miyoomini-toolchain}"
libz_path="${LIBZ_PATH:-/home/mattpc/HueTesting/miyoo_sdl2_benchmarks/app-dist/sdl_bench/lib/libz.so.1}"

retroarch_src="$work_dir/src/RetroArch"
retroarch_assets_src="$work_dir/src/retroarch-assets"
retroarch_build="$work_dir/build/retroarch"
toolchain_work="$work_dir/toolchain"
app_root="$app_dist_dir/retroarch_sdl2"

log() {
  printf '[%s] %s\n' "$package_id" "$*"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  fi
}

ensure_toolchain_image() {
  local toolchain="$1"

  require_tool docker

  if docker image inspect "$docker_image" >/dev/null 2>&1; then
    return
  fi

  if [[ ! -f "$toolchain/Dockerfile" ]]; then
    printf 'Missing toolchain Dockerfile: %s/Dockerfile\n' "$toolchain" >&2
    exit 1
  fi

  log "Building Docker image $docker_image from $toolchain"
  docker build -t "$docker_image" "$toolchain"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"

  if [[ -e "$src" ]]; then
    cp -a "$src" "$dst"
  fi
}

toolchain_root() {
  if [[ -d "$union_dir/workspace" ]]; then
    printf '%s\n' "$union_dir"
    return
  fi

  # TODO: once sdl2_miyoo/build-scripts/mk_miyoo.sh is pushed to the remote,
  # make the cloned toolchain path the default in CI.
  if [[ ! -d "$toolchain_work/.git" ]]; then
    log "Cloning Union toolchain from $union_repo"
    git clone --depth=1 "$union_repo" "$toolchain_work"
  else
    log "Updating Union toolchain in $toolchain_work"
    git -C "$toolchain_work" fetch --depth=1 origin
    git -C "$toolchain_work" reset --hard origin/HEAD
  fi

  printf '%s\n' "$toolchain_work"
}

build_stub_sdl2_deps() {
  local toolchain="$1"
  local script="$toolchain/workspace/mksdl2.sh"

  if [[ "$build_sdl2_stubs" != "1" ]]; then
    log "Skipping legacy SDL2 stub dependency build; set BUILD_SDL2_STUBS=1 to enable it"
    return
  fi

  if [[ ! -x "$script" ]]; then
    log "Skipping SDL2 dependency stub build; script not found or not executable: $script"
    return
  fi

  ensure_toolchain_image "$toolchain"

  log "Building SDL2 dependency stubs in the toolchain container"
  docker run --rm \
    --user root \
    -e HOME=/root \
    --workdir /root/workspace \
    -v "$toolchain/workspace":/root/workspace \
    "$docker_image" \
    bash ./mksdl2.sh
}

build_miyoo_sdl2() {
  local toolchain="$1"
  local script="$toolchain/workspace/sdl2_miyoo/build-scripts/mk_miyoo.sh"

  if [[ ! -x "$script" ]]; then
    printf 'Missing Miyoo SDL2 build script: %s\n' "$script" >&2
    printf 'TODO: place this script manually until the remote toolchain has it.\n' >&2
    exit 1
  fi

  log "Building local sdl2_miyoo with GLES enabled"
  "$script" --docker --enable-gles
}

build_swiftshader_libs() {
  local toolchain="$1"
  local script="$toolchain/workspace/sdl2_miyoo/build-scripts/mk_swiftshader.sh"

  if [[ "$build_swiftshader" != "1" ]]; then
    log "Skipping SwiftShader build; set BUILD_SWIFTSHADER=1 to enable it"
    return
  fi

  if [[ ! -x "$script" ]]; then
    printf 'Missing SwiftShader build script: %s\n' "$script" >&2
    exit 1
  fi

  log "Building SwiftShader GLES/EGL libraries"
  "$script" --docker
}

fetch_retroarch() {
  if [[ ! -d "$retroarch_src/.git" ]]; then
    log "Cloning RetroArch from $retroarch_repo"
    git clone --depth=1 --branch "$retroarch_ref" "$retroarch_repo" "$retroarch_src"
  else
    log "Updating RetroArch in $retroarch_src"
    git -C "$retroarch_src" fetch --depth=1 origin "$retroarch_ref"
    git -C "$retroarch_src" checkout --force FETCH_HEAD
    git -C "$retroarch_src" clean -fdx
  fi

  git -C "$retroarch_src" submodule update --init --recursive --depth=1
}

apply_sdl2_load_texture_diagnostic() {
  local target="$retroarch_src/gfx/drivers/sdl2_gfx.c"

  if [[ ! -f "$target" ]]; then
    printf 'Missing sdl2_gfx.c for diagnostic patch: %s\n' "$target" >&2
    exit 1
  fi

  log "Patching sdl2_load_texture() with caller-identifying diagnostic"
  python3 - "$target" <<'PY'
import sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

include_anchor = "#include <string/stdstring.h>\n"
includes = "#include <execinfo.h>\n#include <stdio.h>\n#include <time.h>\n"
if include_anchor not in src:
    sys.exit(f"apply_sdl2_load_texture_diagnostic: include anchor not found in {path}")
if includes not in src:
    src = src.replace(include_anchor, include_anchor + includes, 1)

call_anchor = (
    "   if (!vid || !vid->renderer || !ti || !ti->pixels || !ti->width || !ti->height)\n"
    "      return 0;\n\n"
    "   tex = SDL_CreateTexture(vid->renderer,\n"
)
diagnostic = (
    "   if (!vid || !vid->renderer || !ti || !ti->pixels || !ti->width || !ti->height)\n"
    "      return 0;\n\n"
    "   {\n"
    "      static unsigned s_load_texture_calls = 0;\n"
    "      static time_t s_load_texture_last_log = 0;\n"
    "      time_t now = time(NULL);\n"
    "      s_load_texture_calls++;\n"
    "      if (now != s_load_texture_last_log)\n"
    "      {\n"
    "         void *bt[16];\n"
    "         int bt_n = backtrace(bt, 16);\n"
    "         FILE *diag = fopen(\"logs/sdl2_load_texture_diag.log\", \"a\");\n"
    "         if (diag)\n"
    "         {\n"
    "            int i;\n"
    "            fprintf(diag, \"[%ld] call#%u w=%u h=%u ret=%p\", (long)now,\n"
    "                  s_load_texture_calls, ti->width, ti->height,\n"
    "                  __builtin_return_address(0));\n"
    "            for (i = 0; i < bt_n; i++)\n"
    "               fprintf(diag, \" bt%d=%p\", i, bt[i]);\n"
    "            fprintf(diag, \"\\n\");\n"
    "            fclose(diag);\n"
    "         }\n"
    "         s_load_texture_last_log = now;\n"
    "      }\n"
    "   }\n\n"
    "   tex = SDL_CreateTexture(vid->renderer,\n"
)
if call_anchor not in src:
    sys.exit(f"apply_sdl2_load_texture_diagnostic: call-site anchor not found in {path}")
src = src.replace(call_anchor, diagnostic, 1)

with open(path, "w") as f:
    f.write(src)
PY
}

fetch_retroarch_assets() {
  if [[ ! -d "$retroarch_assets_src/.git" ]]; then
    log "Cloning RetroArch assets from $retroarch_assets_repo"
    git clone --depth=1 --branch "$retroarch_assets_ref" "$retroarch_assets_repo" "$retroarch_assets_src"
  else
    log "Updating RetroArch assets in $retroarch_assets_src"
    git -C "$retroarch_assets_src" fetch --depth=1 origin "$retroarch_assets_ref"
    git -C "$retroarch_assets_src" checkout --force FETCH_HEAD
    git -C "$retroarch_assets_src" clean -fdx
  fi
}

build_retroarch() {
  local toolchain="$1"
  local sdl_dir="$toolchain/workspace/sdl2_miyoo"

  if [[ -z "$make_jobs" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      make_jobs="$(nproc)"
    else
      make_jobs=4
    fi
  fi

  mkdir -p "$retroarch_build"

  ensure_toolchain_image "$toolchain"

  log "Configuring RetroArch for SDL2, OpenGL/GLES, and Ozone in Docker"
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e MAKE_JOBS="$make_jobs" \
    --workdir /workspace/RetroArch \
    -v "$retroarch_src":/workspace/RetroArch \
    -v "$sdl_dir":/workspace/sdl2_miyoo \
    -v "$sdl_dir/include":/usr/include/SDL2:ro \
    "$docker_image" \
    bash -lc '
      set -euo pipefail

      cross_root=/opt/miyoomini-toolchain
      sdl_dir=/workspace/sdl2_miyoo

      export CROSS_COMPILE="$cross_root/bin/arm-linux-gnueabihf-"
      export CC="${CROSS_COMPILE}gcc"
      export CXX="${CROSS_COMPILE}g++"
      export AR="${CROSS_COMPILE}ar"
      export AS="${CROSS_COMPILE}as"
      export LD="${CROSS_COMPILE}ld"
      export RANLIB="${CROSS_COMPILE}ranlib"
      export STRIP="${CROSS_COMPILE}strip"
      export PATH="$cross_root/bin:$PATH"
      export SDL2_CONFIG="$sdl_dir/sdl2-config"
      export PKG_CONFIG_PATH="$sdl_dir:$sdl_dir/build:$sdl_dir/build/.libs:${PKG_CONFIG_PATH:-}"
      include_flags="-I$sdl_dir/include -I$sdl_dir/src/video/khronos -I$cross_root/arm-linux-gnueabihf/libc/usr/include"
      export CPPFLAGS="$include_flags ${CPPFLAGS:-}"
      export CFLAGS="$include_flags -Ofast -marm -mtune=cortex-a7 -march=armv7ve+simd -mfpu=neon-vfpv4 -mfloat-abi=hard -ffast-math -fomit-frame-pointer -ffunction-sections -fdata-sections ${CFLAGS:-}"
      export CXXFLAGS="-fno-exceptions -fno-rtti -std=c++11 $CFLAGS ${CXXFLAGS:-}"
      export LDFLAGS="-L$sdl_dir/output -L$sdl_dir/build/.libs -L$sdl_dir -L$cross_root/arm-linux-gnueabihf/libc/usr/lib -Wl,-rpath-link,$sdl_dir/output -Wl,-rpath-link,$sdl_dir -Wl,--gc-sections -lEGL -lGLESv2 -lneonarmmiyoo ${LDFLAGS:-}"
      export LIBS="-lSDL2 -lEGL -lGLESv2 -ldl -lrt -pthread -lm ${LIBS:-}"

      ./configure \
        --host=arm-linux-gnueabihf \
        --enable-sdl2 \
        --disable-opengl \
        --enable-opengles \
        --enable-egl \
        --enable-ozone \
        --enable-menu \
        --enable-neon \
        --enable-floathard \
        --disable-vulkan \
        --disable-x11 \
        --disable-wayland \
        --disable-kms \
        --disable-udev \
        --disable-alsa \
        --disable-pulse \
        --disable-jack \
        --disable-oss \
        --disable-ffmpeg \
        --disable-qt

      make -j"$MAKE_JOBS"
    '

  cp -a "$retroarch_src/retroarch" "$retroarch_build/retroarch.debug"
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --workdir /workspace/RetroArch \
    -v "$retroarch_src":/workspace/RetroArch \
    "$docker_image" \
    /opt/miyoomini-toolchain/bin/arm-linux-gnueabihf-strip --strip-unneeded retroarch

  log "Unstripped binary kept for addr2line at $retroarch_build/retroarch.debug"
  log "Resolve diagnostic addresses with: arm-linux-gnueabihf-addr2line -f -C -e $retroarch_build/retroarch.debug <addr>"
}

# WORKAROUND, not an RA fix: upstream ships assets/xmb/monochrome/png/*.png at
# 256x256 even though Ozone only ever displays them at ~24-46px. On this device
# that's ~116 files x 262144 bytes = ~30MB of MI_SYS/MMA pressure at Ozone
# startup alone, blowing the ~20.75MB budget and causing the icon-load OOM
# storm (confirmed via caller-address diagnostics run against
# gfx_display_reset_icon_texture / video_driver_texture_load). Shrinking the
# staged PNGs post-copy avoids patching any RetroArch source.
shrink_xmb_monochrome_icons() {
  local icon_dir="$app_root/assets/xmb/monochrome/png"

  if [[ ! -d "$icon_dir" ]]; then
    return 0
  fi

  log "Workaround: shrinking $icon_dir PNGs to 64x64 (was 256x256) to fix the Ozone icon-load OOM storm"
  python3 - "$icon_dir" <<'PY'
import sys
from pathlib import Path
from PIL import Image

icon_dir = Path(sys.argv[1])
target = (64, 64)
shrunk = 0
for path in icon_dir.glob("*.png"):
    with Image.open(path) as img:
        if img.size[0] <= target[0] and img.size[1] <= target[1]:
            continue
        img = img.convert("RGBA")
        img.thumbnail(target, Image.LANCZOS)
        img.save(path)
        shrunk += 1
print(f"shrunk {shrunk} icon(s) in {icon_dir}")
PY
}

stage_app_dist() {
  local toolchain="$1"
  local sdl_dir="$toolchain/workspace/sdl2_miyoo"

  mkdir -p \
    "$app_root/bin" \
    "$app_root/cfg" \
    "$app_root/lib" \
    "$app_root/logs" \
    "$app_root/assets" \
    "$app_root/cores" \
    "$app_root/info" \
    "$app_root/system" \
    "$app_root/saves/files" \
    "$app_root/saves/states"

  if [[ ! -f "$retroarch_src/retroarch" ]]; then
    printf 'RetroArch binary not found after build: %s/retroarch\n' "$retroarch_src" >&2
    exit 1
  fi

  install -m 755 "$retroarch_src/retroarch" "$app_root/bin/retroarch"

  copy_if_exists "$sdl_dir/output/libSDL2-2.0.so.0" "$app_root/lib/"
  copy_if_exists "$sdl_dir/libneonarmmiyoo.so" "$app_root/lib/"
  copy_if_exists "$sdl_dir/output/libEGL.so" "$app_root/lib/"
  copy_if_exists "$sdl_dir/output/libGLESv2.so" "$app_root/lib/"
  copy_if_exists "$libz_path" "$app_root/lib/"

  if [[ -d "$retroarch_assets_src" ]]; then
    cp -a "$retroarch_assets_src/." "$app_root/assets/"
    rm -rf "$app_root/assets/.git"
  elif [[ -d "$retroarch_src/media/assets" ]]; then
    cp -a "$retroarch_src/media/assets/." "$app_root/assets/"
  else
    log "RetroArch assets not found; menu assets will be omitted"
  fi

  shrink_xmb_monochrome_icons

  log "App dist staged at $app_root"
}

require_tool git
require_tool make

mkdir -p "$work_dir/src"
toolchain="$(toolchain_root)"

build_stub_sdl2_deps "$toolchain"
build_miyoo_sdl2 "$toolchain"
build_swiftshader_libs "$toolchain"
fetch_retroarch
apply_sdl2_load_texture_diagnostic
fetch_retroarch_assets
build_retroarch "$toolchain"
stage_app_dist "$toolchain"
