# Blobby Volley 2

Builds [Blobby Volley 2](https://github.com/danielknobe/blobbyvolley2) against
the shared MMIYOO SDL2 provider. CMake's `find_package(SDL2 REQUIRED)` falls
back to defining its own `SDL2::SDL2` target from plain `SDL2_INCLUDE_DIRS`/
`SDL2_LIBRARIES` when no CMake package config is found, so `scripts/build.sh`
supplies a small `FindSDL2.cmake` pointing at the provider prefix instead of
staging an upstream SDL2 CMake config.

PhysFS has no vendored copy in this project and is cross-compiled from its
own upstream source as a static library (`FindPhysFS.cmake` points at that
build), so no `libphysfs.so` needs to be bundled at runtime. Lua and tinyxml2
are vendored in-tree by upstream and need no separate package. Boost is used
header-only (`algorithm/string`, `crc`, `exception`); its headers are staged
into the cross-compile sysroot from the toolchain image's `libboost-dev`
package rather than built. OpenGL is optional and unused by default -- the
engine's default renderer (`RenderManagerSDL`) uses SDL2's own accelerated
renderer, and the OpenGL renderer's code is compiled out entirely
(`#if HAVE_LIBGL`) when no desktop GL is found in the cross sysroot.

The engine looks for its data files (`gfx.zip`, `sounds.zip`, `scripts.zip`,
`backgrounds.zip`, `rules.zip`, and the `*.lua`/`*.xml` config files) next to
its own executable before anything else, so the app-dist keeps the `blobby`
binary and those files flat in the same directory rather than relying on a
baked-in install prefix.

## Known issues

Input does not currently work on-device.
