# Konpacto FM Macro Tracker

Upstream: https://github.com/wapordev/konpacto (single squashed commit,
no CI-friendly build system of its own — its Makefile targets a Windows/MinGW
host build against prebuilt sibling-directory libraries, and its README's
device recipe predates this buildbot and assumed a manual sdl2_miyoo checkout).

## Dependencies this recipe adds

- `sdl2-mmiyoo-lib` / `sdl2-mmiyoo-addons` for SDL2 core, SDL2_image, and
  SDL2_mixer (device); native `libsdl2-dev`, `libsdl2-image-dev`,
  `libsdl2-mixer-dev` (host).
- LuaJIT (`LuaJIT/LuaJIT` @ `1ee778a4e37122d8ca7d5733c590a47dafd6b15c`, the
  same pin `love-mmiyoo-demo` already vets), cross-compiled statically for
  the device build and bootstrapped natively for the host build if the
  system has no `luajit` pkg-config module — same pattern as
  `love-mmiyoo-demo`'s host lane.
- `tinydir.h` (`cxong/tinydir` @ tag `1.2.6`, matching the version konpacto's
  own upstream Makefile references) — konpacto's source includes it but does
  not vendor it.

Nothing in the actual `src/*.c` sources uses SDL2_gfx, json-c, or portaudio
despite being mentioned in the upstream README/Makefile; those were dropped
from this recipe as dead weight.

## Runtime layout

konpacto's source reads/writes paths like `"assets/songs"` relative to its
own working directory (see `src/file.c`, `src/pages.c`, `src/screen.c`,
`src/sound.c`, `src/synth.c`). The device app-dist therefore stages
`src/assets` at the app root as `assets/`, not under a `res/` prefix like
other packages here, and `launch.sh` `cd`s into the app directory before
exec. The host `run-host.sh` does the equivalent by running from the
upstream checkout's `src/` directory.

## Build

```sh
scripts/validate-package.sh konpacto-mmiyoo
scripts/build-host.sh konpacto-mmiyoo   # native Linux build + run
scripts/run-host.sh konpacto-mmiyoo
scripts/build-package.sh konpacto-mmiyoo   # cross-compiled device app-dist
```
