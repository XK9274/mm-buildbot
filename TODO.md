# TODO

Ports currently being worked on, and ports already shipped. Porting real
games is also how the shared `sdl2-mmiyoo-lib`/`sdl2-mmiyoo-addons`
providers get exercised and improved — each port tends to surface a gap
(missing symbol, missing addon component, wrong GLES/mixer config) that
the drivers/providers pick up as a fix.

## In progress

- **Blobby Volley 2** (`blobbyvolley2-mmiyoo`) — builds and runs, but
  input doesn't currently work on-device. See package README.

## Investigating feasibility

- **DungeonRush** — will render letterboxed unless the upstream source's
  resolution/aspect handling is changed.

## Shipped

- **VVVVVV** (`vvvvvv-mmiyoo`) — built and device-verified.

## Infrastructure

- **`sdl2-mmiyoo-lib` is always built with `--enable-gles`**, which makes
  `libSDL2-2.0.so.0` unconditionally require `libEGL.so`/`libGLESv2.so` to
  even load, regardless of whether the consumer uses GL. Some app-dists
  (e.g. Syncthing) bundle an SDL2 build without those libraries and broke
  when given a GLES-enabled one. Need to identify which app-dists genuinely
  don't need GLES and either build a non-GLES SDL2 for them or bundle
  `libEGL.so`/`libGLESv2.so` alongside — and make sure the build/packaging
  path can't silently hand a GLES-requiring library to one of them again.
