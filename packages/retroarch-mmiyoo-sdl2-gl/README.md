# RetroArch Miyoo SDL2 GL

Builds upstream RetroArch for Miyoo Mini using the Union Miyoo Mini toolchain
and the shared `sdl2-mmiyoo-lib` provider built from the `sdl2_miyoo` backend.

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

The package script consumes the `sdl2-mmiyoo-lib` dependency provider for
both headers/linking and the bundled SDL2/EGL/GLES/Neon runtime.

```sh
scripts/build-package.sh retroarch-mmiyoo-sdl2-gl
```

Override the cached Union toolchain checkout location with
`UNION_TOOLCHAIN_DIR` if needed (defaults to `/tmp/union-miyoomini-toolchain`).

Set `BUILD_SWIFTSHADER=1` to also run the SwiftShader build. That is disabled by
default because the script documents it as a multi-hour build.
