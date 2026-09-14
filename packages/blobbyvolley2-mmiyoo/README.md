# Blobby Volley 2

Builds [Blobby Volley 2](https://github.com/XK9274/blobbyvolley2) (a fork of
[danielknobe/blobbyvolley2](https://github.com/danielknobe/blobbyvolley2),
`miyoo` branch) against the shared MMIYOO SDL2 provider, staged as a
`Roms/PORTS/...` Onion-launcher port. CMake's `find_package(SDL2 REQUIRED)`
falls back to defining its own `SDL2::SDL2` target from plain
`SDL2_INCLUDE_DIRS`/`SDL2_LIBRARIES` when no CMake package config is found,
so `scripts/build.sh` supplies a small `FindSDL2.cmake` pointing at the
provider prefix instead of staging an upstream SDL2 CMake config.

The fork adds a `__MIYOO__` build define (always on for this package):
fullscreen, accelerated/vsync rendering, no window icon or software cursor
sprite (this device has neither a window manager nor a mouse), the joystick
opened eagerly at startup rather than waiting on a hotplug event, and a
joystick button mapping matching the mmiyoo driver's own button indices
instead of the stale placeholder mapping upstream ships outside `__SWITCH__`.
`assets/inputconfig.xml` binds both sides to the joystick (D-pad for
left/right, A for jump); `assets/config.xml` enables `show_shadow` by
default.

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

Menu navigation and in-match joystick controls are functional. UX of the
current default button mapping has not yet had a final confirmation pass
on hardware following the most recent input/rendering changes.
