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

`modified_source: yes`: a small set of build-time transforms and one
source patch adapt upstream's 1440x960-native assets to this panel, kept
as reviewable diffs in this package rather than as permanent commits on
the pinned upstream fork.

## Known rendering/scaling caveats

- Upstream hardcodes `SCREEN_WIDTH`/`SCREEN_HEIGHT` at 1440x960 in
  `src/res.h`, well above the panel's 640x480. The `.port` script sets
  `SDL_MMIYOO_STRETCH=1` so the backend fills the panel on both axes
  instead of aspect-preserving letterboxing it, but the game still
  renders internally at 1440x960 and everything is downscaled from
  there -- some sprites read small on the physical panel as a result.
- `patches/font-size.patch` bumps `FONT_SIZE` (`src/res.h`) from 32 to
  40 so menu/HUD text stays legible after that downscale; applied by
  `scripts/build.sh` right after cloning the pinned source, before the
  cross-compile.
- `scripts/fix-title-asset.py` downscales the title screen's sprite
  strip (`res/drawable/title.png`, originally 8004x93 -- 29 frames at
  276px each) below the MMIYOO renderer's 4096px max texture width,
  rewriting its frame descriptor to match; resizes each frame
  individually to avoid bleeding adjacent frames into each other.
- `scripts/fix-bgm-audio.sh` strips a multiplexed Theora cover-art
  stream from two BGM `.ogg` files -- the cross-built SDL2_mixer falls
  back to the bundled stb_vorbis decoder (no libvorbis in the toolchain
  sysroot), which can't demux past it.
- These three transforms run against the staged build output, not the
  pinned checkout itself, so the upstream ref stays trivially rebasable;
  only `font-size.patch` touches actual source.

## Notes

- DungeonRush links `SDL2_net` for local/online multiplayer; the
  `sdl2-mmiyoo-addons` provider ships it, so no extra dependency handling
  is required.
- Save data (`storage.dat`) and all asset paths (`res/...`) are relative to
  the process's current working directory. As a `port` artifact
  (`Roms/PORTS/Games/DungeonRush/`), the on-device launcher
  (`launch_standalone.sh`) `cd`s into the game directory before executing
  the binary, same as `run-host.sh` does for the native build.
