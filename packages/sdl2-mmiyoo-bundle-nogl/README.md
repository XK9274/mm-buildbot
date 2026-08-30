# MMIYOO SDL2 no-GLES bundle (core + TTF + image)

Merges `sdl2-mmiyoo-lib` (built with `sdl2_gles: no`, so no `libEGL`/
`libGLESv2`) and `sdl2-mmiyoo-addons` (built with `sdl2_addons: [ttf,
image]`) into a single `include/`+`lib/` bundle for consumers that link SDL2
core, SDL2_ttf, and SDL2_image without any GL/EGL dependency.

Intended for apps built outside this buildbot's own package/consumer
pipeline (e.g. `syncthing-app-miyoo`'s `installer/build.sh`, which downloads
this bundle as a release artifact rather than declaring `sdl2_addons` in a
`package.yml` here).
