# MMIYOO SDL2 add-ons

This provider uses the buildbot's canonical `scripts/mksdl2.sh` to build
SDL2_image, SDL2_ttf, SDL2_gfx, SDL2_net, and SDL2_mixer. `SDL2_SKIP_CORE=1` makes the
`sdl2-mmiyoo-lib` headers and library the only SDL core available, so every
consumer links to the buildbot's MMIYOO SDL2 implementation.

Per-component versions, download URLs, and configure args live in
`scripts/sdl2-addons.conf.sh`. A consumer's `package.yml` can declare
`sdl2_addons: [image, mixer]` to build only the components it links against;
omitting the field builds all five, as before.
