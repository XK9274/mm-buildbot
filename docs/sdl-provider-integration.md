# Shared MMIYOO SDL2 integration

The buildbot has one authoritative SDL core: `sdl2-mmiyoo-lib`, built from a
clone of `sdl2_miyoo` (`package.yml`'s `source.repo`/`ref`, currently
`main`). It supplies SDL2 and Khronos EGL/GLES headers, `sdl2.pc`,
`sdl2-config`, `libSDL2-2.0.so.0`, EGL, GLESv2, and the Neon helper.

`sdl2-mmiyoo-addons` runs the canonical buildbot copy of `mksdl2.sh` with
`SDL2_SKIP_CORE=1`. It provides Image, TTF, Net, and Mixer while linking against
that core provider. It never compiles stock SDL2.

## Consumer audit

| recipe | core SDL2 | add-ons | runtime handling |
| --- | --- | --- | --- |
| `retroarch-mmiyoo-sdl2-gl` | yes | no | Links and stages the core runtime from `sdl2-mmiyoo-lib`. |
| `yorisoft-pokedex` | yes | Image/TTF/Net/Mixer | Stages the core and required add-ons from their providers. |
| `love-mmiyoo-demo` | yes | no | Its local build hook installs the provider; it does not invoke `mk_mmiyoo.sh`. |
| Half-Life, POSTAL, OpenRCT2, Elma, Frozen Bubble, Super Haxagon, ONScripter-JH, Captain Claw | yes | no | Shared source-port adapter exports the provider include/lib/pkg-config paths and stages/verifies the core runtime closure. |

## Build-all behaviour

`scripts/build-all.sh` creates one session, detects enabled packages that need
the core provider, and builds it first. `scripts/build-package.sh` records a
completed dependency per session, so each provider is built only once and is
then shared from `work/<provider>/bundle` by all consumers.

The provider packages and unverified source ports remain `build_all: false`
until direct target builds have passed.

The provider clones `sdl2_miyoo`, builds it via `mk_miyoo.sh`, and stages
source-style `include/` headers as `include/SDL2/` in its normalized bundle.
It does not modify the source checkout. `ref` tracks `main`, which can lag
behind work still local to whichever machine last touched `sdl2_miyoo`.
