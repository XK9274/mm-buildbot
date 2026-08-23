#!/usr/bin/env bash
set -euo pipefail

package_id="${1:?missing package id}"
root="${2:?missing repository root}"
source_dir="${3:?missing source directory}"
host_root="${4:?missing host root}"

[[ "$package_id" == "love-mmiyoo-demo" ]] || exit 1

for command in autoheader autoconf automake aclocal libtoolize make git; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'LÖVE host build requires command: %s\n' "$command" >&2
    printf 'Install the native Autotools development tools in WSL2 and retry.\n' >&2
    exit 1
  }
done

deps_dir="$host_root/deps"
luajit_prefix="$deps_dir/luajit"
luajit_source="$deps_dir/LuaJIT"
mkdir -p "$deps_dir"

if pkg-config --exists luajit; then
  luajit_pkg_config_path=""
else
  if [[ ! -f "$luajit_source/Makefile" ]]; then
    rm -rf "$luajit_source"
    if [[ -n "${HOST_LUAJIT_SOURCE_DIR:-}" ]]; then
      git clone --shared "$HOST_LUAJIT_SOURCE_DIR" "$luajit_source" >/dev/null
    else
      git init "$luajit_source" >/dev/null
      git -C "$luajit_source" remote add origin https://github.com/LuaJIT/LuaJIT.git
      git -C "$luajit_source" fetch --depth 1 origin 1ee778a4e37122d8ca7d5733c590a47dafd6b15c >/dev/null
      git -C "$luajit_source" checkout --detach FETCH_HEAD >/dev/null
    fi
  fi

  if [[ ! -f "$luajit_prefix/lib/pkgconfig/luajit.pc" || ! -e "$luajit_prefix/lib/libluajit-5.1.so" ]]; then
    make -C "$luajit_source" clean >/dev/null 2>&1 || true
    make -C "$luajit_source" -j"${HOST_JOBS:-$(nproc)}" \
      CFLAGS="-fPIC" BUILDMODE=dynamic
    make -C "$luajit_source" install PREFIX="$luajit_prefix"
  fi
  luajit_pkg_config_path="$luajit_prefix/lib/pkgconfig"
fi

if [[ -n "$luajit_pkg_config_path" ]]; then
  export PKG_CONFIG_PATH="$luajit_pkg_config_path${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi
pkg-config --exists luajit || {
  printf 'Native LuaJIT was not found after preparation.\n' >&2
  exit 1
}

cd "$source_dir"
rm -f aclocal.m4
rm -rf autom4te.cache
./platform/unix/automagic 11.5

export CPPFLAGS="$(pkg-config --cflags sdl2 freetype2 zlib luajit)"
export LDFLAGS="$(pkg-config --libs-only-L sdl2 freetype2 zlib luajit)"

./configure \
  --prefix="$host_root/stage" \
  --with-lua=luajit
