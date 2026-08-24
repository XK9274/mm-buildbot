# VVVVVV (Miyoo Mini family)

Built from upstream source ([TerryCavanagh/VVVVVV](https://github.com/TerryCavanagh/VVVVVV),
tag `2.3.6`) against the shared `sdl2-mmiyoo-lib`/`sdl2-mmiyoo-addons`
providers. `main` upstream has since moved to SDL3; this package intentionally
tracks the last SDL2 release instead.

## Notable deviations from a stock build
- **No GLES.** The `VVVVVV` binary has zero OpenGL/EGL/GLES symbols, so this
  package builds `sdl2-mmiyoo-lib` with `sdl2_gles: no` and ships neither
  `libEGL.so` nor `libGLESv2.so`.
- **SDL2_mixer only.** Upstream's `CMakeLists.txt` links SDL2 + SDL2_mixer
  only — no `SDL2_image`/`SDL2_ttf` — so only `libSDL2_mixer-2.0.so.0` is
  cherry-picked out of the shared `sdl2-mmiyoo-addons` bundle.
- **Joypad-first default bindings.** Flip is bound to all four face buttons,
  Start/Select open the menu, Guide pauses — matching the control scheme
  tested on-device against this same source revision.

## Runtime data
Retail game data (`data.zip`) is proprietary and not bundled. Place your own
copy in `Roms/PORTS/Games/VVVVVV/` before launching, per
`PLACE data.zip HERE.txt`.
