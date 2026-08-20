# RetroArch Miyoo SDL2 GL

Builds upstream RetroArch for Miyoo Mini using the Union Miyoo Mini toolchain
and the `sdl2_miyoo` backend.

Target features:

- upstream RetroArch, latest default branch
- SDL2 enabled
- OpenGL/OpenGLES path enabled
- Ozone menu enabled
- SDL audio path available
- SDL input and SDL2 controller path available
- SDL2 rumble/haptic path available where RetroArch exposes joypad rumble

Debugging scaffold:

- `SDL_MMIYOO_GEOMETRY_QUICKPATH` - SDL2 Miyoo geometry-path debug switch.
  Behaviour notes to be filled in after device testing.

The package script uses the local Union toolchain checkout by default while the
remote `sdl2_miyoo` build scripts are being pushed.

```sh
UNION_TOOLCHAIN_DIR=/home/mattpc/HueTesting/union-miyoomini-toolchain \
  scripts/build-package.sh retroarch-mmiyoo-sdl2-gl
```

Set `BUILD_SWIFTSHADER=1` to also run the SwiftShader build. That is disabled by
default because the script documents it as a multi-hour build.
