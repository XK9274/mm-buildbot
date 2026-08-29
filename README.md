# mm-buildbot

Build bot for producing packaged app distributions and standalone tool
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
<col width="48">
<col width="220">
<col>
<col width="90">
<col width="120">
<col>
</colgroup>
<thead>
<tr><th></th><th>id</th><th>builds</th><th>native run</th><th>modified source</th><th>notes</th></tr>
</thead>
<tbody>
<tr><td><img src="packages/sdl2-benchmarks-mmiyoo/templates/sdl_bench/icon.png" alt="SDL2 Benchmarks icon" width="32" height="32"></td><td><code>sdl2-benchmarks-mmiyoo</code></td><td>Miyoo SDL2 benchmark suite with eight binaries covering SDL2 rendering, audio, OpenGL ES, SDL2_gfx, SDL2_image, and backend behaviour, built against the shared SDL providers.</td><td>—</td><td>no</td><td>Opt-in package (<code>build_all: false</code>) while the complete suite is clean-built and device-tested.</td></tr>
<tr><td><img src="packages/retroarch-mmiyoo-sdl2-gl/templates/retroarch_sdl2/icon.png" alt="RetroArch icon" width="32" height="32"></td><td><code>retroarch-mmiyoo-sdl2-gl</code></td><td>Upstream RetroArch for Miyoo Mini, built against the shared <code>sdl2_miyoo</code> SDL2 backend (Ozone menu, OpenGL/OpenGLES, SDL audio/input/rumble).</td><td>—</td><td>yes</td><td>Patched for texture-load diagnostics/debug logging; links and bundles the single <code>sdl2-mmiyoo-lib</code> provider. See <code>docs/retroarch-mmiyoo-sdl2-gl.md</code> and <code>packages/retroarch-mmiyoo-sdl2-gl/README.md</code>.</td></tr>
<tr><td><img src="packages/love-mmiyoo-demo/templates/LoveMiyoo/icon.png" alt="LÖVE icon" width="32" height="32"></td><td><code>love-mmiyoo-demo</code></td><td>LÖVE 11.5 built against the shared <code>sdl2_miyoo</code> SDL2 backend, with a menu launcher over several test scenes.</td><td>yes</td><td>no</td><td>Supplies its own cross-compilation build system (<code>build_love.sh</code>/<code>cross.cmake</code>/<code>sdl2.m4</code>) and bundles the shared SDL2 libraries; LÖVE's own engine source is untouched. <strong>Early WIP</strong> — see <code>packages/love-mmiyoo-demo/STATUS.md</code> for known bugs. <code>build_all: true</code>.</td></tr>
<tr><td><img src="packages/konpacto-mmiyoo/templates/Konpacto/icon.png" alt="Konpacto icon" width="32" height="32"></td><td><code>konpacto-mmiyoo</code></td><td>Konpacto FM Macro Tracker built against the shared <code>sdl2_miyoo</code> and <code>sdl2-mmiyoo-addons</code> providers.</td><td>yes</td><td>no</td><td>Bundles the shared SDL2 libraries and supplies LuaJIT plus the missing <code>tinydir.h</code> dependency as build inputs; Konpacto's own source is untouched. Native host build uses system SDL2, SDL2_image, and SDL2_mixer. <code>build_all: false</code>.</td></tr>
<tr><td><img src="packages/yorisoft-pokedex/assets/icon.png" alt="Retrodex icon" width="32" height="32"></td><td><code>yorisoft-pokedex</code></td><td>Yorisoft's Retrodex Pokedex app, built against the shared <code>sdl2-mmiyoo-lib</code> and <code>sdl2-mmiyoo-addons</code> providers.</td><td>—</td><td>no</td><td>Bundles the shared SDL2/Image/TTF/Mixer libraries, supplies the pinned SQLite amalgamation as a build input, and tweaks <code>CMakeLists.txt</code> to link them; Retrodex's own app source is untouched. <code>build_all: false</code>.</td></tr>
<tr><td><img src="packages/blobbyvolley2-mmiyoo/templates/BlobbyVolley2/icon.png" alt="Blobby Volley 2 icon" width="32" height="32"></td><td><code>blobbyvolley2-mmiyoo</code></td><td>Blobby Volley 2, built against the shared <code>sdl2-mmiyoo-lib</code> provider with PhysFS cross-built as a static library and Boost used header-only.</td><td>yes</td><td>no</td><td>See <code>packages/blobbyvolley2-mmiyoo/README.md</code>. <code>build_all: false</code>.</td></tr>
<tr><td><img src="packages/vvvvvv-mmiyoo/assets/icon.png" alt="VVVVVV icon" width="32" height="32"></td><td><code>vvvvvv-mmiyoo</code></td><td>VVVVVV 2.3.6, built from upstream source against the shared <code>sdl2-mmiyoo-lib</code>/<code>sdl2-mmiyoo-addons</code> providers via the Union toolchain container.</td><td>yes</td><td>no</td><td>Port artifact type; builds with <code>sdl2_gles: no</code> (no GL/EGL/GLES symbols) and requests only <code>mixer</code> from the addons provider via <code>sdl2_addons:</code>. Retail <code>data.zip</code> is proprietary and not bundled. See <code>packages/vvvvvv-mmiyoo/README.md</code>. <code>build_all: false</code>.</td></tr>
</tbody>
</table>

`native run` indicates that the package declares a WSL2/Linux host build and
run path using native system libraries. `modified source` indicates that the
package recipe edits the upstream project's own source files (e.g. patching a
`.c`/`.h`). Supplying build-system config, missing third-party build
dependencies, or bundled runtime libraries doesn't count.

## Dev Packages

`dev-tools/` holds standalone diagnostic tools and probes — device-hang
repro cases, benchmarks, and utility bundles. Unlike `packages/`, these have
no `package.yml`, clone no upstream source, and don't appear in the table
above; each probe's C source is authored directly in this repo. Every probe
has its own `compile.sh <out_dir>` (build only, no push).
`dev-tools/probes-app/build.sh` compiles any set of probes into one
directory and `package.sh` assembles them into a single on-device app
(`config.json`/`icon.png`/`launch.sh`/`bin`/`lib`/`res`) — `launch.sh` runs
whichever probe its `PROBE=` line names, so switching probes on-device is a
one-line edit, not a re-push. Deploy any app-dist (probes or a real package)
with `scripts/push-app.sh <local_dir> <device_app_name>`.

<table>
<colgroup>
<col width="220">
<col>
<col width="200">
<col width="160">
<col width="180">
</colgroup>
<thead>
<tr><th>tool</th><th>what it tests / does</th><th>logging</th><th>control</th><th>delivery</th></tr>
</thead>
<tbody>
<tr><td><code>downscale-bench-probe</code></td><td>Compares <code>MI_GFX_BitBlit</code>'s implicit hardware scale against the NEON <code>downscale_area_n32</code> fallback across a resolution matrix (800x600 through 1920x1080); each variant's result is rotated 180° and held on-screen with an on-screen banner naming resolution/target/variant.</td><td>Per-frame timing and a final summary table, both to the probe's own <code>probe.log</code> and to <code>launch.sh</code>'s <code>logs/&lt;probe&gt;-&lt;timestamp&gt;.log</code> capture.</td><td><code>PROBE=downscale-bench-probe</code> in <code>launch.sh</code>; <code>PROBE_ARGS</code> sets <code>frames_per_variant</code> (default 150).</td><td><code>dev-tools/probes-app</code> on-device app.</td></tr>
<tr><td><code>fragmented-composite-probe</code></td><td>Repro matching BlobbyVolley2's real <code>RenderManagerSDL::init()</code>/<code>refresh()</code> window/renderer/viewport sequence exactly, isolating a BV2-only hang from the generic oversized-composite one.</td><td>Checkpoint log to <code>probe.log</code>, plus <code>launch.sh</code>'s timestamped run log.</td><td><code>PROBE=fragmented-composite-probe</code> in <code>launch.sh</code>; <code>PROBE_ARGS</code> sets <code>small_count</code> (default 200, textures created before the oversized composite).</td><td><code>dev-tools/probes-app</code> on-device app.</td></tr>
<tr><td><code>texture-count-probe</code></td><td>Repro for a hang theory tied to BlobbyVolley2's asset loading (many small <code>SDL_CreateTextureFromSurface</code> calls); <code>KEEP_ALIVE</code> toggles whether textures stay live or are destroyed between creates.</td><td>Checkpoint log to <code>probe.log</code>, plus <code>launch.sh</code>'s timestamped run log.</td><td><code>PROBE=texture-count-probe</code> in <code>launch.sh</code>; <code>PROBE_ARGS</code> sets <code>KEEP_ALIVE</code> (<code>0</code>/<code>1</code>).</td><td><code>dev-tools/probes-app</code> on-device app.</td></tr>
<tr><td><code>i2c-tools-mmiyoo</code></td><td>Upstream <code>i2c-tools</code> 4.4 (<code>i2cdetect</code>, <code>i2cdump</code>, <code>i2cget</code>, <code>i2cset</code>, <code>i2ctransfer</code>) for direct I2C bus inspection.</td><td>stdout only, whatever the invoking command captures.</td><td>Invoked directly per-command over SSH.</td><td>Floating tool bundle, no <code>launch.sh</code>/app-dist shape — copy <code>bin/</code> to the device.</td></tr>
<tr><td><code>strace-mmiyoo</code></td><td>Union-toolchain ARM hard-float build of <code>strace</code> 6.12, for live syscall tracing during a device-hang investigation.</td><td>stdout, or wherever the invoking command redirects it.</td><td>Invoked directly over SSH, typically wrapping another process's launch.</td><td>Floating binary, dynamically linked against the device C library, no private shared-library deps.</td></tr>
<tr><td><code>tcpdump-mmiyoo</code></td><td><code>tcpdump</code> 4.99.6 with its private <code>libpcap.so.1</code> dependency, for capturing on-device network traffic.</td><td>stdout or a <code>.pcap</code> file, whichever <code>tcpdump</code>'s own arguments target.</td><td>Invoked directly over SSH.</td><td>Floating bundle using an <code>$ORIGIN/../lib</code> runtime search path — copy <code>bin/</code> and <code>lib/</code> together.</td></tr>
<tr><td><code>sdl2-mmiyoo-lib</code></td><td>Shared SDL2 library bundle (<code>libSDL2-2.0.so.0</code>, <code>libEGL.so</code>, <code>libGLESv2.so</code>, <code>libneonarmmiyoo.so</code> + headers), cloned and built from <code>sdl2_miyoo</code> via a single <code>docker run</code> against the shared Union toolchain image, invoking <code>mk_miyoo.sh --enable-gles --clean build</code> directly (no nested Docker).</td><td>—</td><td>Not invoked directly — built on demand via <code>depends_on</code> whenever a consumer package needs it.</td><td>Not a standalone deliverable; consumed only as <code>MMIYOO_SDL2_PREFIX</code> by dependent packages' <code>build.sh</code>. <code>build_all: false</code>.</td></tr>
<tr><td><code>sdl2-mmiyoo-addons</code></td><td>SDL2_image, SDL2_ttf, SDL2_gfx, SDL2_mixer, and SDL2_net, built via <code>scripts/mksdl2.sh</code> in <code>SDL2_SKIP_CORE=1</code> mode against the <code>sdl2-mmiyoo-lib</code> provider. A consumer's <code>sdl2_addons:</code> list selects which components get built (default: all).</td><td>—</td><td>Not invoked directly — built on demand via <code>depends_on</code> whenever a consumer package needs it.</td><td>Not a standalone deliverable; consumed only as <code>MMIYOO_SDL2_ADDONS_PREFIX</code> by dependent packages' <code>build.sh</code>. <code>build_all: false</code>.</td></tr>
</tbody>
</table>

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
