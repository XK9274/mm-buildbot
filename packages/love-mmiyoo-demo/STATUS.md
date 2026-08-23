# Status: early WIP

This package is an early work-in-progress test suite, built to exercise the
MMIYOO SDL2 driver through LÖVE rather than to ship a finished product. The
scenes under `game/scenes/` are adapted from third-party demos (see
README.md) and have not all been verified working on-device yet.

## Known issues

- **The Tutorial**: pressing Start does nothing at the "Welcome" screen --
  the `KeyDown("return")` transition isn't firing.
- **Circle Amongst Squares**: the d-pad doesn't move the circle.
- **Thunderstorm**: appears to be missing textures/surfaces on-device.

Not yet root-caused. Revisit before treating any scene here as a reliable
driver regression test.
