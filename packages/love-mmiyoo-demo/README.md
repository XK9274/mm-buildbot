# LÖVE Miyoo SDL2 demo

This recipe clones the official pinned LÖVE 11.5 source revision, then runs the
existing known-good `workspace/love/build_love.sh` dependency builder in the
Union toolchain. Its copied `mksdl2.sh` hook is replaced with an adapter that
installs the shared buildbot MMIYOO SDL2 provider into the temporary toolchain
sysroot before LÖVE is configured; it never compiles a second SDL2.

The output is a normal Onion-style `LoveMiyoo/` app distribution containing:

- `love` and `liblove-11.5.so` built from official upstream LÖVE;
- all non-platform shared LÖVE dependencies;
- the SDL2, EGL, GLES2, and Neon helper libraries produced by the MMIYOO SDL
  provider; and
- `game/`, a menu launcher (`main.lua`) over test scenes under `scenes/`:
  a ball-in-a-rotating-hexagon physics demo, a state-machine-driven text
  tutorial, a keyboard-controlled circle dodging squares (collision via
  `lib/bump.lua`), and a procedural rain/lightning scene. Plain
  `love.graphics` primitives throughout, no custom shaders. SDL2 gamepad
  input quits on the Menu or Select button (see below).

It is deliberately excluded from `build-all` until it's been smoke-tested under
CI/`act`. Its reference `build_love.sh`/`mksdl2.sh`/`cross.cmake` helper scripts
currently exist only on one dev machine's disk (untracked in the `XK9274/love`
fork they live alongside), so this package cannot yet build from a fresh clone
or in CI -- vendoring those scripts, or committing them upstream, is tracked as
a follow-up. A direct build fails before making changes if the helper is
absent. Override its location with `LOVE_REFERENCE_BUILD_DIR`.

## Input

`game/main.lua` quits on keyboard `escape`/`home`, or on gamepad `guide`
(physical Menu) / `back` (physical Select) -- the MMIYOO joystick driver maps
those buttons via its `SDL_GameController` mapping, so no raw button-index
guessing is needed.

## Third-party code

`scenes/hexagon.lua`'s physics simulation (ball bouncing inside a rotating
hexagon, including the rotating-wall collision response) is adapted from
[meenbeese/Love2D-Demo](https://github.com/meenbeese/Love2D-Demo), MIT
licensed:

> MIT License
>
> Copyright (c) 2025 Kuzey Bilgin
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to
> deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
> sell copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
> FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
> DEALINGS IN THE SOFTWARE.

`scenes/tutorial.lua`, `scenes/circle_squares.lua`, and `scenes/thunderstorm.lua`
are adapted from [messersm/love2d-demos](https://github.com/messersm/love2d-demos)
(GPL-3.0), each trimmed to drop audio and image assets in favor of procedural
rendering. `lib/bump.lua` is [kikito/bump.lua](https://github.com/kikito/bump.lua)
v3.1.7, MIT licensed, copyright (c) 2012 Enrique García Cota, vendored
unmodified for `circle_squares.lua`'s collision detection.
