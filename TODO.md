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
