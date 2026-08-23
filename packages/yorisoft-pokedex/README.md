# Yorisoft Retrodex Pokedex

This package builds [Yorisoft's Pokedex source](https://github.com/Yorisoft/pokedex_miyoo)
into a standard Onion app distribution. The buildbot adapts upstream
the canonical buildbot copy of `mksdl2.sh`, as the shared
`sdl2-mmiyoo-addons` provider, to build
SDL_image, SDL_ttf, and SDL_mixer. The main `libSDL2` is always the buildbot's
MMIYOO SDL2 provider. It downloads a pinned SQLite amalgamation for the
upstream source tree, builds `retrodex`, and stages the complete `App/Retrodex`
asset tree.

The artifact contains `Retrodex/retrodex`, `Retrodex/lib/`, `Retrodex/res/`,
and the upstream launcher/configuration. The buildbot SDL core and add-ons
replace upstream prebuilt copies; any remaining upstream runtime libraries are
retained only when required by the app's dependency closure.
