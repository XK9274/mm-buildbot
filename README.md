# mm-buildbot

Personal build bot for producing packaged app distributions and standalone tool
bundles from upstream source repos.

This repo owns build recipes, templates, and automation. It does not own the
upstream application source.

> **AI disclosure:** there's been a substantial usage of various LLM in this
> project to both write the code & maintain the repo itself.

## Layout

```text
.github/workflows/      GitHub Actions entrypoints
packages/               One folder per app/package recipe
scripts/                Shared buildbot scripts
work/                   Temporary clone/build/app-dist workspace
artifacts/              Individual app zip outputs
dist/                   Aggregate outputs, such as all app zips together
docs/                   Notes on package config and app-dist shape
```

## Packages

One row per **committed** package under `packages/`. Add a row here only
once a package has actually landed in git -- several more package recipes
currently sit uncommitted in the working tree and are deliberately left off
this table until they're reviewed and committed.

| id | builds | notes |
| --- | --- | --- |
| `sdl2-mmiyoo-lib` | Shared SDL2 library bundle (`libSDL2-2.0.so.0`, `libEGL.so`, `libGLESv2.so`, `libneonarmmiyoo.so` + headers), cloned and built from `sdl2_miyoo` via `mk_miyoo.sh --docker --enable-gles --clean build`. | Not an app -- a shared provider consumed by other packages via `depends_on`. `build_all: false`; built on demand for whichever consumer needs it. |
| `retroarch-mmiyoo-sdl2-gl` | Upstream RetroArch for Miyoo Mini, built against the shared `sdl2_miyoo` SDL2 backend (Ozone menu, OpenGL/OpenGLES, SDL audio/input/rumble). | Links and bundles the single `sdl2-mmiyoo-lib` provider. See `docs/retroarch-mmiyoo-sdl2-gl.md` and `packages/retroarch-mmiyoo-sdl2-gl/README.md`. |
| `i2c-tools-mmiyoo` | Upstream `i2c-tools` 4.4 (`i2cdetect`, `i2cdump`, `i2cget`, `i2cset`, `i2ctransfer`). | Floating tool bundle, no `launch.sh`/app-dist shape -- copy `bin/` to the device and invoke directly. |
| `strace-mmiyoo` | Union-toolchain ARM hard-float build of `strace` 6.12. | Floating binary, dynamically linked against the device C library, no private shared-library deps. |
| `tcpdump-mmiyoo` | `tcpdump` 4.99.6 with its private `libpcap.so.1` dependency. | Floating bundle using an `$ORIGIN/../lib` runtime search path -- copy `bin/` and `lib/` together. |
| `love-mmiyoo-demo` | LÖVE 11.5 built against the shared `sdl2_miyoo` SDL2 backend, with a menu launcher over several test scenes. | **Early WIP** -- see `packages/love-mmiyoo-demo/STATUS.md` for known bugs. `build_all: false`; its reference build helper is local-machine-only, not yet buildable in CI. |
| `sdl2-mmiyoo-addons` | SDL2_image, SDL2_ttf, SDL2_mixer, and SDL2_net, built via `scripts/mksdl2.sh` in `SDL2_SKIP_CORE=1` mode against the `sdl2-mmiyoo-lib` provider. | Not an app -- a shared add-on provider consumed via `depends_on`. `build_all: false`; built on demand. |
| `yorisoft-pokedex` | Yorisoft's Retrodex Pokedex app, built against the shared `sdl2-mmiyoo-lib` and `sdl2-mmiyoo-addons` providers. | Links and bundles the core SDL2 provider plus the Image/TTF/Mixer add-ons. `build_all: false`. |
| `blobbyvolley2-mmiyoo` | Blobby Volley 2, built against the shared `sdl2-mmiyoo-lib` provider with PhysFS cross-built as a static library and Boost used header-only. | See `packages/blobbyvolley2-mmiyoo/README.md`. `build_all: false`. |

## Basic Flow

```text
clone upstream source
build upstream source
create app-dist directory
copy app-dist templates
copy built files into app-dist
tokenise config and launch scripts
zip app-dist
upload individual and aggregate artifacts
```

## Local Usage

Validate a package:

```sh
scripts/validate-package.sh retroarch-mmiyoo-sdl2-gl
```

Build a package:

```sh
scripts/build-package.sh retroarch-mmiyoo-sdl2-gl
```

Build every package and create `dist/all-artifacts.zip` (with
`dist/all-app-dists.zip` retained as a compatibility copy):

```sh
scripts/build-all.sh
```

The source-port recipes are deliberately excluded from `build-all` until each
one has been directly built and smoke-tested against the published MMIYOO SDL2
provider. Build one explicitly with `scripts/build-package.sh <id>`.

`build-all` creates one dependency-build session and builds
`sdl2-mmiyoo-lib` first when an enabled package consumes it. That provider is
then reused for all SDL consumers in the session; it is not rebuilt per app.

### SDL provider

The SDL provider is cloned from `sdl2-mmiyoo-lib`'s `package.yml`
`source.repo`/`ref` (currently `XK9274/sdl2_miyoo` at `main`) and built via
`mk_miyoo.sh`, giving every consumer the same known core, EGL/GLES, Neon
helper, and development headers. `main` can lag behind work still local to
whichever machine last touched `sdl2_miyoo` -- push before relying on this
for anything tested against the latest driver fixes.

Override the source explicitly when required:

```sh
SDL2_MIYOO_REPO=https://github.com/you/sdl2_miyoo.git \
SDL2_MIYOO_REF=your-branch \
scripts/build-all.sh
```

`build-all` builds the currently enabled recipes only. Disabled source-port
recipes remain individually opt-in until their upstream package layouts have
been verified.

## Local GitHub Actions Testing

This repo is structured to work with `act` once you install it locally.

```sh
act workflow_dispatch -W .github/workflows/build-app.yml \
  --input package=retroarch-mmiyoo-sdl2-gl
```
