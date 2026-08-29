#!/usr/bin/env bash

set -euo pipefail

# Buildbot SDL policy
# -------------------
# This is the canonical shared copy of mksdl2.sh.  It builds SDL2's
# companion libraries (SDL2_image, SDL2_ttf, SDL2_gfx, SDL2_net, and SDL2_mixer) and
# their headers/pkg-config metadata for the Miyoo toolchain.
#
# The primary libSDL2 implementation comes from the `sdl2_miyoo` repository,
# through the sdl2-mmiyoo-lib provider. Buildbot calls this script with
# SDL2_SKIP_CORE=1 after installing that provider at SDL2_PREFIX; in that mode
# this script neither downloads nor compiles the stock SDL2 core.  Running
# without SDL2_SKIP_CORE retains the standalone, upstream-compatible behavior.
#
# SDL2_ADDONS selects which companion libraries to build, e.g.
# SDL2_ADDONS="image ttf gfx"; unset or "all" builds every component listed
# in sdl2-addons.conf.sh.

MKSDL2_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/sdl2-addons.conf.sh
source "$MKSDL2_DIR/sdl2-addons.conf.sh"

SCRIPT_DIR=$(pwd -P)
WORKSPACE=${WORKSPACE:-$SCRIPT_DIR}
SDL2_PREFIX=${SDL2_PREFIX:-${FIN_BIN_DIR:-/root/workspace/build}}
FIN_BIN_DIR="$SDL2_PREFIX"
SYSROOT=${SYSROOT:-/opt/miyoomini-toolchain/arm-linux-gnueabihf/libc}
PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-}
PKG_CONFIG_SYSROOT_DIR=${PKG_CONFIG_SYSROOT_DIR:-}
CROSS_COMPILE_RAW=${CROSS_COMPILE:-arm-linux-gnueabihf}
if [[ "$CROSS_COMPILE_RAW" == *- ]]; then
  CROSS_PREFIX="$CROSS_COMPILE_RAW"
else
  CROSS_PREFIX="${CROSS_COMPILE_RAW}-"
fi
CROSS_TRIPLET=$(basename "${CROSS_PREFIX%-}")
CROSS_COMPILE="$CROSS_PREFIX"
BUILD=${BUILD:-x86_64-linux-gnu}
HOST=${HOST:-$CROSS_TRIPLET}
CC=${CC:-${CROSS_PREFIX}gcc}
CXX=${CXX:-${CROSS_PREFIX}g++}
STRIP=${STRIP:-${CROSS_PREFIX}strip}
AR=${AR:-${CROSS_PREFIX}ar}
AS=${AS:-${CROSS_PREFIX}as}
LD=${LD:-${CROSS_PREFIX}ld}
RANLIB=${RANLIB:-${CROSS_PREFIX}ranlib}
NM=${NM:-${CROSS_PREFIX}nm}
CFLAGS=${CFLAGS:-"-Wno-undef -Os -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -march=armv7ve+simd -mfloat-abi=hard -ffunction-sections -fdata-sections"}
CXXFLAGS=${CXXFLAGS:-"-s -O3 -fPIC -pthread"}
CPPFLAGS=${CPPFLAGS:-"-I${FIN_BIN_DIR}/include -I${FIN_BIN_DIR}/include/SDL2 -I${SYSROOT}/include -I${SYSROOT}/usr/include"}
LDFLAGS=${LDFLAGS:-"-L${FIN_BIN_DIR}/lib -L${SYSROOT}/lib -L${SYSROOT}/usr/lib"}
STAMP_DIR="$WORKSPACE/cache"
LOG_DIR="$WORKSPACE/logs"
EMPTY_PKGCONFIG_DIR="$STAMP_DIR/pkgconfig-null"
if [[ -z "${NPROC:-}" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    NPROC=$(nproc)
  else
    NPROC=2
  fi
  NPROC=$((NPROC - 1))
fi
[[ $NPROC -lt 1 ]] && NPROC=1

mkdir -p "$LOG_DIR" "$STAMP_DIR" "$FIN_BIN_DIR" "$EMPTY_PKGCONFIG_DIR"

: "${PKG_CONFIG_LIBDIR:=$EMPTY_PKGCONFIG_DIR}"
: "${PKG_CONFIG_SYSROOT_DIR:=$SYSROOT}"

export FIN_BIN_DIR
export WORKSPACE
export SYSROOT
export PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR
export PKG_CONFIG_PATH=
PKG_CONFIG=${PKG_CONFIG:-pkg-config}
export PKG_CONFIG
export CROSS_COMPILE BUILD HOST CC CXX STRIP AR AS LD RANLIB NM
export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

configure_apt_sources() {
  if [ -w /etc/apt/sources.list ]; then
    if grep -q "deb.debian.org" /etc/apt/sources.list; then
      sed -i 's|https\?://deb.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list
      sed -i 's|https\?://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list
      # The Bullseye security archive no longer exposes a usable Release file.
      # Its packages are available from the main archived suite for the small
      # host-side build-tool set used here, so omit this stale source.
      sed -i '\|^[[:space:]]*deb .*archive.debian.org/debian-security|s|^|# |' /etc/apt/sources.list
    fi
    cat >/etc/apt/apt.conf.d/99onion-archive <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
EOF
  fi
}

install_missing_tools() {
  local missing_tools=("$@")
  if [ ${#missing_tools[@]} -eq 0 ]; then
    return
  fi

  echo "Installing build dependencies: ${missing_tools[*]}"
  configure_apt_sources
  DEBIAN_FRONTEND=noninteractive \
    apt-get -o Acquire::Check-Valid-Until=false \
            -o Acquire::AllowInsecureRepositories=true \
            update
  DEBIAN_FRONTEND=noninteractive \
    apt-get -o Acquire::Check-Valid-Until=false \
            -o Acquire::AllowInsecureRepositories=true \
            install -y --no-install-recommends "${missing_tools[@]}"
}

check_dev_tools() {
  declare -A tool_map=(
    [pkg-config]=pkg-config
    [autoconf]=autoconf
    [automake]=automake
    [libtoolize]=libtool
    [m4]=m4
    [autoupdate]=autoconf
    [autoreconf]=autoconf
    [wget]=wget
  )

  local missing_packages=()
  for tool in "${!tool_map[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      pkg=${tool_map[$tool]}
      missing_packages+=("$pkg")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    local unique_packages=()
    for pkg in "${missing_packages[@]}"; do
      if [[ ! " ${unique_packages[*]} " =~ " ${pkg} " ]]; then
        unique_packages+=("$pkg")
      fi
    done
    install_missing_tools "${unique_packages[@]}"
  fi
}

download_sources() {
  local sources=()
  local name var_tarball var_url
  for name in "${SELECTED_ADDONS[@]}"; do
    var_tarball="SDL2_ADDON_${name}_TARBALL"
    var_url="SDL2_ADDON_${name}_URL"
    sources+=("${!var_tarball}|${!var_url}")
  done
  if [[ "${SDL2_SKIP_CORE:-0}" != 1 ]]; then
    sources=("SDL2-2.26.5.tar.gz|https://github.com/libsdl-org/SDL/releases/download/release-2.26.5/SDL2-2.26.5.tar.gz" "${sources[@]}")
  fi

  for source in "${sources[@]}"; do
    local file="${source%%|*}"
    local url="${source#*|}"
    if [ -f "$file" ]; then
      continue
    fi
    echo "Downloading $file..."
    wget -q -O "$file" "$url"
  done
}

run_logged() {
  local log_name=$1
  shift
  local log_file="$LOG_DIR/$log_name.log"
  echo "[RUN] $*" | tee -a "$log_file"
  "$@" 2>&1 | tee -a "$log_file"
}

resolve_selected_addons() {
  local requested="${SDL2_ADDONS:-all}"
  if [[ -z "$requested" || "$requested" == "all" ]]; then
    printf '%s\n' "${SDL2_ADDON_ORDER[@]}"
    return
  fi
  local name candidate found
  for name in $requested; do
    found=0
    for candidate in "${SDL2_ADDON_ORDER[@]}"; do
      [[ "$candidate" == "$name" ]] && { found=1; break; }
    done
    [[ "$found" == 1 ]] || {
      printf 'Unknown SDL2_ADDONS component: %s (expected one of: %s)\n' \
        "$name" "${SDL2_ADDON_ORDER[*]}" >&2
      exit 1
    }
    printf '%s\n' "$name"
  done
}

build_tarball() {
  local name=$1
  local tarball=$2
  local dir=$3
  shift 3
  local configure_args=("$@")
  echo "- Building $name"
  : >"$LOG_DIR/$name.log"
  rm -rf "$dir"
  tar -xf "$tarball"
  pushd "$dir" >/dev/null
  if [ -x ./autogen.sh ]; then
    run_logged "$name" ./autogen.sh
  fi
  run_logged "$name" ./configure "${configure_args[@]}"
  run_logged "$name" make clean
  run_logged "$name" make -j"$NPROC"
  run_logged "$name" make -j"$NPROC" install
  popd >/dev/null
}

main() {
  cd "$WORKSPACE"
  mapfile -t SELECTED_ADDONS < <(resolve_selected_addons)
  echo "Building SDL2 add-ons: ${SELECTED_ADDONS[*]}"
  check_dev_tools
  download_sources

  if [[ "${SDL2_SKIP_CORE:-0}" == 1 ]]; then
    [[ -f "$FIN_BIN_DIR/lib/libSDL2-2.0.so.0" && -d "$FIN_BIN_DIR/include/SDL2" ]] || {
      echo "SDL2_SKIP_CORE=1 requires a preinstalled SDL2 provider at $FIN_BIN_DIR" >&2
      exit 1
    }
  else
    build_tarball "SDL2" "SDL2-2.26.5.tar.gz" "SDL2-2.26.5" \
      CC=$CC --host=$HOST --build=$BUILD --prefix="$FIN_BIN_DIR" \
      --disable-joystick-virtual --disable-sensor --disable-power \
      --disable-alsa --disable-diskaudio --disable-video-x11 \
      --disable-video-wayland --disable-video --disable-video-vulkan \
      --disable-dbus --disable-ime --disable-fcitx --disable-hidapi \
      --disable-pulseaudio --disable-sndio --disable-libudev --disable-jack \
      --disable-video-opengl --disable-video-opengles --disable-video-opengles2 \
      --disable-oss --disable-dummyaudio --disable-video-dummy
  fi

  export SDL2_CONFIG="$FIN_BIN_DIR/bin/sdl2-config"
  export SDL_CONFIG="$FIN_BIN_DIR/bin/sdl2-config"
  export PATH="$FIN_BIN_DIR/bin:$PATH"
  if [ -n "$PKG_CONFIG_LIBDIR" ]; then
    export PKG_CONFIG_LIBDIR="$FIN_BIN_DIR/lib/pkgconfig:$FIN_BIN_DIR/share/pkgconfig:$PKG_CONFIG_LIBDIR"
  else
    export PKG_CONFIG_LIBDIR="$FIN_BIN_DIR/lib/pkgconfig:$FIN_BIN_DIR/share/pkgconfig"
  fi

  local name var_tarball var_dir
  for name in "${SELECTED_ADDONS[@]}"; do
    var_tarball="SDL2_ADDON_${name}_TARBALL"
    var_dir="SDL2_ADDON_${name}_DIR"
    local -n addon_args="SDL2_ADDON_${name}_ARGS"
    build_tarball "SDL2_${name}" "${!var_tarball}" "${!var_dir}" \
      CC=$CC --host=$HOST --build=$BUILD --prefix="$FIN_BIN_DIR" \
      "${addon_args[@]}"
  done

  echo "SDL2 build artifacts installed to $FIN_BIN_DIR"
}

main "$@"
