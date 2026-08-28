# DungeonRush

Builds [DungeonRush](https://github.com/XK9274/DungeonRush) (a fork of
[dzy1997/DungeonRush](https://github.com/dzy1997/DungeonRush)) against the
shared MMIYOO SDL2 provider and its Image/Mixer/Net/TTF add-ons.

DungeonRush's `CMakeLists.txt` uses its own vendored, upstream-community
`cmake/sdl2/Find{SDL2,SDL2_image,SDL2_mixer,SDL2_net,SDL2_ttf}.cmake`
modules, which already produce modern `SDL2::*` imported targets once the
usual `SDL2*_INCLUDE_DIR`/`SDL2*_LIBRARY` cache variables are populated -- no
custom `FindSDL2.cmake` override needs to be written for this package.
Because those modules fall back to `find_path`/`find_library`, which is
subject to `CMAKE_FIND_ROOT_PATH` re-rooting under
`CMAKE_FIND_ROOT_PATH_MODE_{INCLUDE,LIBRARY}=ONLY`, `scripts/build.sh`
pre-seeds all five include/library cache variables directly on the `cmake`
command line, pointing straight at files resolved from the two provider
prefixes, instead of relying on the `ENV SDL2*DIR` hint search path.

The source tree is used unmodified (`modified_source: no`); no patches or
injected files are needed.

## Notes

- DungeonRush links `SDL2_net` for local/online multiplayer; the
  `sdl2-mmiyoo-addons` provider ships it, so no extra dependency handling
  is required.
- Upstream hardcodes a fixed `SCREEN_WIDTH`/`SCREEN_HEIGHT` of 1440x960 in
  `src/res.h` (which also drives the in-game dungeon grid's tile
  dimensions, not just the window size); left unpatched for now.
- On-device launch currently renders a black screen and crashes;
  `build_all` stays `false` until that's diagnosed.
- Save data (`storage.dat`) and all asset paths (`res/...`) are relative to
  the process's current working directory. As a `port` artifact
  (`Roms/PORTS/Games/DungeonRush/`), the on-device launcher
  (`launch_standalone.sh`) `cd`s into the game directory before executing
  the binary, same as `run-host.sh` does for the native build.
- `build_all: false` until the staged rollout in
  `docs/buildbot-plan.md` (validate -> host build/run -> device
  cross-build + runtime closure -> on-device push/launch) has been
  completed end-to-end.
