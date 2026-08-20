# RetroArch Miyoo SDL2 GL Package

This package builds upstream RetroArch with the Miyoo SDL2 backend from the
Union Miyoo Mini toolchain.

## RetroArch Targets

- `HAVE_SDL2`
- `HAVE_OPENGL`
- `HAVE_OPENGLES`
- `HAVE_EGL`
- `HAVE_OZONE`

Runtime defaults are staged in `cfg/retroarch.cfg`:

```ini
menu_driver = "ozone"
video_driver = "gl"
video_context_driver = "sdl-gl"
audio_driver = "sdl"
input_driver = "sdl"
input_joypad_driver = "sdl2"
```

## SDL2 Miyoo Feature Mapping

The target SDL2 backend currently exposes video/window/framebuffer support,
SDL renderer support, audio output, joystick/controller support, haptic
left/right rumble, power info, and GLES context functions.

RetroArch should exercise these via:

- SDL video/context setup for the GL driver
- SDL audio driver
- SDL input driver
- SDL2 controller/joypad driver
- joypad rumble where cores request it

## Debugging

`SDL_MMIYOO_GEOMETRY_QUICKPATH` is reserved here as the SDL2 Miyoo
geometry-path debug switch. Add the exact values and expected behaviour once
the driver-side testing is finalised.

## TODO

- Confirm the pushed Union toolchain remote contains
  `workspace/sdl2_miyoo/build-scripts/mk_miyoo.sh`.
- Compare against Onion's current RetroArch build flags before the first real
  release artifact.
- Decide whether SwiftShader should ship in the default app-dist or remain an
  opt-in build.
- Add device-tested notes once the first archive launches on hardware.
