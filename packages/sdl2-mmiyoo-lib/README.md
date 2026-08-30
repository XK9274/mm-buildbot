# Miyoo SDL2 shared-library bundle

The provider clones `sdl2_miyoo` (`package.yml`'s `source.repo`/`ref`),
builds it via `build-scripts/mk_miyoo.sh --docker --enable-gles --clean
build`, and stages its shared-library outputs:

- `lib/libSDL2-2.0.so.0`
- `lib/libEGL.so`
- `lib/libGLESv2.so`
- `lib/libneonarmmiyoo.so`

Override the source with `SDL2_MIYOO_REPO`/`SDL2_MIYOO_REF`. `ref` currently
tracks `main`, which can lag behind local `sdl2_miyoo` work in progress on
whichever machine built this package -- push before relying on this for
anything tested against the latest driver fixes.

For iterating on an uncommitted `sdl2_miyoo` working-tree change, set
`SDL2_MIYOO_LOCAL_REPO=/path/to/sdl2_miyoo` instead -- it copies the
working-tree bytes directly (`cp -a`), no commit or push required, and takes
priority over `SDL2_MIYOO_REPO`/`SDL2_MIYOO_REF` when set.
