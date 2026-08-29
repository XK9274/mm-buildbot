# Miyoo SDL2 Benchmarks

This package builds the benchmark suite from
`XK9274/miyoo_sdl2_benchmarks` against the shared buildbot SDL providers.

It consumes `sdl2-mmiyoo-lib` for SDL2, EGL/GLES, and the Neon helper, and
`sdl2-mmiyoo-addons` for SDL2_ttf, SDL2_gfx, and SDL2_image. The benchmark
package does not build any SDL implementation itself.

The package is currently opt-in (`build_all: false`) until the complete suite
has been clean-built and tested on hardware.
