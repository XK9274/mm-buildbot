#!/usr/bin/env bash
# Component data for scripts/mksdl2.sh: version, tarball, download URL, and
# extra ./configure arguments (beyond CC/host/build/prefix) per SDL2 add-on.

SDL2_ADDON_ORDER=(ttf image gfx net mixer)

SDL2_ADDON_ttf_VERSION=2.20.2
SDL2_ADDON_ttf_TARBALL=SDL2_ttf-2.20.2.tar.gz
SDL2_ADDON_ttf_URL=https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.20.2/SDL2_ttf-2.20.2.tar.gz
SDL2_ADDON_ttf_DIR=SDL2_ttf-2.20.2
SDL2_ADDON_ttf_ARGS=()

SDL2_ADDON_image_VERSION=2.6.3
SDL2_ADDON_image_TARBALL=SDL2_image-2.6.3.tar.gz
SDL2_ADDON_image_URL=https://github.com/libsdl-org/SDL_image/releases/download/release-2.6.3/SDL2_image-2.6.3.tar.gz
SDL2_ADDON_image_DIR=SDL2_image-2.6.3
SDL2_ADDON_image_ARGS=(--enable-stb-image --disable-avif --disable-jxl --disable-libpng --disable-libtiff --disable-libwebp --disable-webpdecoder --disable-jpg --disable-tif)

SDL2_ADDON_gfx_VERSION=1.0.4
SDL2_ADDON_gfx_TARBALL=SDL2_gfx-1.0.4.tar.gz
SDL2_ADDON_gfx_URL=https://sourceforge.net/projects/sdl2gfx/files/SDL2_gfx-1.0.4.tar.gz/download
SDL2_ADDON_gfx_DIR=SDL2_gfx-1.0.4
SDL2_ADDON_gfx_ARGS=(--disable-mmx)

SDL2_ADDON_net_VERSION=2.2.0
SDL2_ADDON_net_TARBALL=SDL2_net-2.2.0.tar.gz
SDL2_ADDON_net_URL=https://github.com/libsdl-org/SDL_net/releases/download/release-2.2.0/SDL2_net-2.2.0.tar.gz
SDL2_ADDON_net_DIR=SDL2_net-2.2.0
SDL2_ADDON_net_ARGS=(--disable-examples)

SDL2_ADDON_mixer_VERSION=2.6.3
SDL2_ADDON_mixer_TARBALL=SDL2_mixer-2.6.3.tar.gz
SDL2_ADDON_mixer_URL=https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.6.3/SDL2_mixer-2.6.3.tar.gz
SDL2_ADDON_mixer_DIR=SDL2_mixer-2.6.3
SDL2_ADDON_mixer_ARGS=()
