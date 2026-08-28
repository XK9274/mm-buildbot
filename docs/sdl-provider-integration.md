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

## CMake cross-compile boilerplate

`packages/.shared/port-common.sh`'s `write_mmiyoo_cmake_toolchain_file
<destination>` writes the Union-toolchain cross-compile settings that are
identical across every CMake-based recipe (compiler paths, sysroot,
`CMAKE_FIND_ROOT_PATH_MODE_*`). Point `cmake` at it with
`-DCMAKE_TOOLCHAIN_FILE=<destination>` instead of repeating those `-D` flags
inline (see `blobbyvolley2-mmiyoo/scripts/build.sh`).

It does not cover SDL2 discovery — how a recipe wires the provider prefixes
into its own build varies with what upstream's `CMakeLists.txt` already does,
and each recipe still picks the matching approach itself:

- No upstream `find_package(SDL2)` call at all (SDL2 paths passed as plain
  variables, e.g. `SDL2_INCLUDE_DIRS`/`SDL2_LIBRARIES`): pass those variables
  directly (`vvvvvv-mmiyoo`).
- Upstream's own `find_package(SDL2)` has no CMake config to find and no
  fallback: supply a small `FindSDL2.cmake` in `-DCMAKE_MODULE_PATH` that
  sets the result variables directly (`blobbyvolley2-mmiyoo`).
- Upstream vendors its own `FindSDL2*.cmake` modules (classic
  `find_path`/`find_library`-based): pre-seed the `SDL2*_INCLUDE_DIR`/
  `SDL2*_LIBRARY` cache variables on the `cmake` command line so
  `find_path`/`find_library` short-circuit, avoiding the
  `CMAKE_FIND_ROOT_PATH` re-rooting that would otherwise apply to their
  `ENV SDL2*DIR` hints.

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
