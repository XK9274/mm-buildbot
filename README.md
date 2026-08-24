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

<table>
<colgroup>
<col width="280">
<col>
<col width="90">
<col width="120">
<col>
</colgroup>
<thead>
<tr><th>icon / id</th><th>builds</th><th>native run</th><th>modified source</th><th>notes</th></tr>
</thead>
<tbody>
<tr><td>—<br><code>sdl2-mmiyoo-lib</code></td><td>Shared SDL2 library bundle (<code>libSDL2-2.0.so.0</code>, <code>libEGL.so</code>, <code>libGLESv2.so</code>, <code>libneonarmmiyoo.so</code> + headers), cloned and built from <code>sdl2_miyoo</code> via <code>mk_miyoo.sh --docker --enable-gles --clean build</code>.</td><td>—</td><td>no</td><td>Not an app — a shared provider consumed by other packages via <code>depends_on</code>. <code>build_all: false</code>; built on demand for whichever consumer needs it.</td></tr>
<tr><td><img src="packages/retroarch-mmiyoo-sdl2-gl/templates/retroarch_sdl2/icon.png" alt="RetroArch icon" width="32" height="32">&nbsp;<code>retroarch-mmiyoo-sdl2-gl</code></td><td>Upstream RetroArch for Miyoo Mini, built against the shared <code>sdl2_miyoo</code> SDL2 backend (Ozone menu, OpenGL/OpenGLES, SDL audio/input/rumble).</td><td>—</td><td>yes</td><td>Patched for texture-load diagnostics/debug logging; links and bundles the single <code>sdl2-mmiyoo-lib</code> provider. See <code>docs/retroarch-mmiyoo-sdl2-gl.md</code> and <code>packages/retroarch-mmiyoo-sdl2-gl/README.md</code>.</td></tr>
<tr><td>—<br><code>i2c-tools-mmiyoo</code></td><td>Upstream <code>i2c-tools</code> 4.4 (<code>i2cdetect</code>, <code>i2cdump</code>, <code>i2cget</code>, <code>i2cset</code>, <code>i2ctransfer</code>).</td><td>—</td><td>no</td><td>Floating tool bundle, no <code>launch.sh</code>/app-dist shape — copy <code>bin/</code> to the device and invoke directly.</td></tr>
<tr><td>—<br><code>strace-mmiyoo</code></td><td>Union-toolchain ARM hard-float build of <code>strace</code> 6.12.</td><td>—</td><td>no</td><td>Floating binary, dynamically linked against the device C library, no private shared-library deps.</td></tr>
<tr><td>—<br><code>tcpdump-mmiyoo</code></td><td><code>tcpdump</code> 4.99.6 with its private <code>libpcap.so.1</code> dependency.</td><td>—</td><td>no</td><td>Floating bundle using an <code>$ORIGIN/../lib</code> runtime search path — copy <code>bin/</code> and <code>lib/</code> together.</td></tr>
<tr><td><img src="packages/love-mmiyoo-demo/templates/LoveMiyoo/icon.png" alt="LÖVE icon" width="32" height="32">&nbsp;<code>love-mmiyoo-demo</code></td><td>LÖVE 11.5 built against the shared <code>sdl2_miyoo</code> SDL2 backend, with a menu launcher over several test scenes.</td><td>yes</td><td>yes</td><td>Alters the app's bundled SDL2 libraries/build inputs. <strong>Early WIP</strong> — see <code>packages/love-mmiyoo-demo/STATUS.md</code> for known bugs. <code>build_all: true</code>; its build helper and cross-compilation configuration are vendored in the package.</td></tr>
<tr><td><img src="packages/konpacto-mmiyoo/templates/Konpacto/icon.png" alt="Konpacto icon" width="32" height="32">&nbsp;<code>konpacto-mmiyoo</code></td><td>Konpacto FM Macro Tracker built against the shared <code>sdl2_miyoo</code> and <code>sdl2-mmiyoo-addons</code> providers.</td><td>yes</td><td>yes</td><td>Alters the app's bundled SDL2 libraries and injects LuaJIT plus <code>tinydir.h</code>; native host build uses system SDL2, SDL2_image, and SDL2_mixer. <code>build_all: false</code>.</td></tr>
<tr><td>—<br><code>sdl2-mmiyoo-addons</code></td><td>SDL2_image, SDL2_ttf, SDL2_mixer, and SDL2_net, built via <code>scripts/mksdl2.sh</code> in <code>SDL2_SKIP_CORE=1</code> mode against the <code>sdl2-mmiyoo-lib</code> provider.</td><td>—</td><td>no</td><td>Not an app — a shared add-on provider consumed via <code>depends_on</code>. <code>build_all: false</code>; built on demand.</td></tr>
<tr><td>—<br><code>yorisoft-pokedex</code></td><td>Yorisoft's Retrodex Pokedex app, built against the shared <code>sdl2-mmiyoo-lib</code> and <code>sdl2-mmiyoo-addons</code> providers.</td><td>—</td><td>yes</td><td>Alters the app's bundled SDL2/Image/TTF/Mixer libraries and injects the pinned SQLite amalgamation. <code>build_all: false</code>.</td></tr>
<tr><td><img src="packages/blobbyvolley2-mmiyoo/templates/BlobbyVolley2/icon.png" alt="Blobby Volley 2 icon" width="32" height="32">&nbsp;<code>blobbyvolley2-mmiyoo</code></td><td>Blobby Volley 2, built against the shared <code>sdl2-mmiyoo-lib</code> provider with PhysFS cross-built as a static library and Boost used header-only.</td><td>yes</td><td>no</td><td>See <code>packages/blobbyvolley2-mmiyoo/README.md</code>. <code>build_all: false</code>.</td></tr>
</tbody>
</table>

`native run` indicates that the package declares a WSL2/Linux host build and
run path using native system libraries. `modified source` indicates that the
package recipe changes or injects files into the upstream source tree during
the build.

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
