# mm-buildbot

Personal build bot for producing packaged app distributions from upstream source
repos.

This repo owns build recipes, templates, and automation. It does not own the
upstream application source.

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

One row per package under `packages/`. Add a row here whenever a new package
lands.

| id | builds | notes |
| --- | --- | --- |
| `retroarch-mmiyoo-sdl2-gl` | Upstream RetroArch for Miyoo Mini, built against the `sdl2_miyoo` SDL2 backend (Ozone menu, OpenGL/OpenGLES, SDL audio/input/rumble). | `build.sh` also builds `sdl2_miyoo` itself first via the local Union toolchain checkout. See `docs/retroarch-mmiyoo-sdl2-gl.md` and `packages/retroarch-mmiyoo-sdl2-gl/README.md`. |

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

Build every package and create `dist/all-app-dists.zip`:

```sh
scripts/build-all.sh
```

## Local GitHub Actions Testing

This repo is structured to work with `act` once you install it locally.

```sh
act workflow_dispatch -W .github/workflows/build-app.yml \
  --input package=retroarch-mmiyoo-sdl2-gl
```
