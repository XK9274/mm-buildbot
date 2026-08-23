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

The package matrix below is generated from committed manifests under
`packages/`. It is refreshed by GitHub Actions whenever a package manifest or
app icon is added or changed on `main`.

<p align="center">
  <img src="assets/package-table.svg" alt="mm-buildbot package matrix">
</p>

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

### WSL2 native host builds

Host builds compile selected packages with the WSL2-native compiler and the
system SDL2 installation. They do not use the Miyoo ARM toolchain,
`sdl2-mmiyoo-lib`, Docker, or app-distribution packaging.

The first host-enabled package is Blobby Volley 2:

```sh
scripts/build-host.sh blobbyvolley2-mmiyoo
```

Use `HOST_SOURCE_DIR` to build an editable local checkout while keeping the
build directory separate from the source tree:

```sh
HOST_SOURCE_DIR=/path/to/blobbyvolley2 \
  scripts/build-host.sh blobbyvolley2-mmiyoo
```

Run the resulting host executable with its required data directory:

```sh
HOST_SOURCE_DIR=/path/to/blobbyvolley2 \
  scripts/run-host.sh blobbyvolley2-mmiyoo
```

The run helper supplies an isolated `HOME` under the host build directory by
default. Override it with `HOST_HOME` when persistent native settings are
needed.

Host output is kept under `work/host/<package>/`. The runner checks native
requirements with `pkg-config`, fails without installing packages, and does
not create release archives. Host build metadata is optional and lives in the
package manifest's `host:` section.

For a reproducible native environment, use the supplied `x86-mm-buildbot`
container. It includes the compiler, Autotools, system SDL2, and the native
audio/video development libraries. The repository is mounted into the
container, so build output remains under the normal `work/host/` directory:

```sh
scripts/build-host-docker.sh build love-mmiyoo-demo
scripts/build-host-docker.sh run love-mmiyoo-demo
scripts/build-host-docker.sh shell
```

The `run` command forwards the WSLg/X11 video socket and WSLg PulseAudio
socket when available. The image name can be overridden with
`MM_X86_BUILDBOT_IMAGE`.

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
