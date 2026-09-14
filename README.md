# mm-buildbot

Build bot for packaged app distributions and standalone tool bundles from
upstream source repos. Owns build recipes, templates, and automation —
not the upstream application source.

Currently focused on SDL2-based source ports for the Miyoo Mini family
(Mini, Plus, Mini Flip), using a custom SDL2 fork.

> **AI disclosure:** substantial LLM usage writing code and maintaining
> this repo.

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

Generated from committed manifests under `packages/`; refreshed by GitHub
Actions whenever a manifest or app icon changes on `main`.

`native run` = the package also declares a WSL2/Linux host build path.
`modified source` = the recipe edits the upstream project's own source
files (supplying build-system config, missing deps, or bundled runtime
libraries doesn't count).

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
<tr><td><img src="packages/sdl2-benchmarks-mmiyoo/templates/sdl_bench/icon.png" alt="SDL2 Benchmarks icon" width="32" height="32"></td><td><code>sdl2-benchmarks-mmiyoo</code></td><td>16-binary SDL2 benchmark suite (render, audio, GLES, SDL2_gfx, SDL2_image, backend behavior).</td><td>—</td><td>no</td><td>Opt-in (<code>build_all: false</code>) pending a full clean-build + device test pass.</td></tr>
<tr><td><img src="packages/retroarch-mmiyoo-sdl2-gl/templates/retroarch_sdl2/icon.png" alt="RetroArch icon" width="32" height="32"></td><td><code>retroarch-mmiyoo-sdl2-gl</code></td><td>RetroArch (Ozone menu, GL/GLES, SDL audio/input/rumble).</td><td>—</td><td>yes</td><td>Patched for texture-load debug logging. See <code>docs/retroarch-mmiyoo-sdl2-gl.md</code>.</td></tr>
<tr><td><img src="packages/love-mmiyoo-demo/templates/LoveMiyoo/icon.png" alt="LÖVE icon" width="32" height="32"></td><td><code>love-mmiyoo-demo</code></td><td>LÖVE 11.5 + a menu launcher over several test scenes.</td><td>yes</td><td>no</td><td>Own cross-compile build system (<code>build_love.sh</code>/<code>cross.cmake</code>/<code>sdl2.m4</code>); engine source untouched. Early WIP, known bugs in <code>STATUS.md</code>. <code>build_all: true</code>.</td></tr>
<tr><td><img src="packages/konpacto-mmiyoo/templates/Konpacto/icon.png" alt="Konpacto icon" width="32" height="32"></td><td><code>konpacto-mmiyoo</code></td><td>Konpacto FM Macro Tracker.</td><td>—</td><td>no</td><td>Supplies LuaJIT + <code>tinydir.h</code>; source untouched. Native host build uses system SDL2/Image/Mixer. <code>build_all: true</code>.</td></tr>
<tr><td><img src="packages/yorisoft-pokedex/assets/icon.png" alt="Retrodex icon" width="32" height="32"></td><td><code>yorisoft-pokedex</code></td><td>Yorisoft's Retrodex Pokedex app.</td><td>—</td><td>no</td><td>Supplies the pinned SQLite amalgamation and tweaks <code>CMakeLists.txt</code> to link it; app source untouched. <code>build_all: true</code>.</td></tr>
<tr><td><img src="packages/blobbyvolley2-mmiyoo/assets/icon.png" alt="Blobby Volley 2 icon" width="32" height="32"></td><td><code>blobbyvolley2-mmiyoo</code></td><td>Blobby Volley 2 (PhysFS static, Boost header-only), staged as a <code>Roms/PORTS/...</code> port.</td><td>yes</td><td>yes</td><td>See <code>packages/blobbyvolley2-mmiyoo/README.md</code>. <code>build_all: true</code>.</td></tr>
<tr><td><img src="packages/vvvvvv-mmiyoo/assets/icon.png" alt="VVVVVV icon" width="32" height="32"></td><td><code>vvvvvv-mmiyoo</code></td><td>VVVVVV 2.3.6.</td><td>yes</td><td>no</td><td>No GLES (<code>sdl2_gles: no</code>); only the <code>mixer</code> addon. Retail <code>data.zip</code> not bundled. <code>build_all: true</code>.</td></tr>
</tbody>
</table>

## Dev Packages

`dev-tools/` holds standalone diagnostics and probes — no `package.yml`, no
upstream clone, not part of the table above. Each has its own
`compile.sh <out_dir>` (build only, no push). `dev-tools/probes-app/build.sh`
compiles a chosen set into one directory and `package.sh` assembles them
into an on-device app; `launch.sh`'s `PROBE=` line picks which one runs, so
switching probes on-device is a one-line edit. Deploy any app-dist with
`scripts/push-app.sh <local_dir> <device_app_name>`.

### Probes (SDL2, `dev-tools/*-probe`)

Unless noted, every probe logs to its own `probe.log` plus `launch.sh`'s
timestamped run log, and ships via the `dev-tools/probes-app` on-device app.

<table>
<colgroup>
<col width="200">
<col>
<col width="260">
</colgroup>
<thead>
<tr><th>tool</th><th>what it tests</th><th>control</th></tr>
</thead>
<tbody>
<tr><td><code>downscale-bench-probe</code></td><td>Hardware <code>MI_GFX_BitBlit</code> scale vs. NEON <code>downscale_area_n32</code>, 800x600 through 1920x1080.</td><td><code>PROBE=downscale-bench-probe</code>; <code>PROBE_ARGS</code> = <code>frames_per_variant</code> (default 150).</td></tr>
<tr><td><code>texture-count-probe</code></td><td>BlobbyVolley2 hang repro: many small <code>SDL_CreateTextureFromSurface</code> calls.</td><td><code>PROBE=texture-count-probe</code>; <code>PROBE_ARGS</code> = <code>KEEP_ALIVE</code> (0/1).</td></tr>
<tr><td><code>blend-compose-probe</code></td><td>Composed/premultiplied blend-mode translation, fill-blend correctness, and small-vs-large fill agreement (6 cases).</td><td><code>PROBE=blend-compose-probe</code>.</td></tr>
<tr><td><code>pixel-format-probe</code></td><td>Round-trip of <code>ARGB8888</code>/<code>ABGR8888</code>/<code>BGRA8888</code>/<code>RGBA8888</code> (<code>RGBA8888</code> fails by design — documented hardware limitation).</td><td><code>PROBE=pixel-format-probe</code>.</td></tr>
<tr><td><code>surface-alpha-probe</code></td><td>Per-pixel alpha survives an <code>ABGR8888</code> → <code>RGBA8888</code> conversion.</td><td><code>PROBE=surface-alpha-probe</code>.</td></tr>
<tr><td><code>colorkey-probe</code></td><td><code>SDL_MMIYOO_SetTextureColorKey</code> on <code>RGB565</code> and <code>ARGB8888</code> textures.</td><td><code>PROBE=colorkey-probe</code>.</td></tr>
<tr><td><code>blend-fill-bench-probe</code></td><td>Hardware-blit vs. scalar-C vs. NEON alpha-blend fill timing across a pixel-count matrix.</td><td><code>PROBE=blend-fill-bench-probe</code>; <code>PROBE_ARGS</code> = <code>frames_per_variant</code> (default 500).</td></tr>
</tbody>
</table>

### Standalone tools

- `i2c-tools-mmiyoo` — `i2cdetect`/`i2cdump`/`i2cget`/`i2cset`/`i2ctransfer`
  for I2C bus inspection. No `launch.sh`/app-dist shape — copy `bin/`.
- `strace-mmiyoo` — `strace` 6.12 for live syscall tracing. Floating
  binary, no private shared-library deps.
- `tcpdump-mmiyoo` — `tcpdump` 4.99.6 + its private `libpcap.so.1`. Copy
  `bin/` and `lib/` together (`$ORIGIN/../lib` search path).

### Providers (not standalone deliverables)

- `sdl2-mmiyoo-lib` — shared SDL2 bundle (`libSDL2`, `libEGL`, `libGLESv2`,
  `libneonarmmiyoo` + headers), built from `sdl2_miyoo`. Built on demand,
  consumed via `MMIYOO_SDL2_PREFIX`. `build_all: false`.
- `sdl2-mmiyoo-addons` — SDL2_image/ttf/gfx/mixer/net via `mksdl2.sh`.
  Built on demand, consumed via `MMIYOO_SDL2_ADDONS_PREFIX`.
  `build_all: false`.

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

Source-port recipes stay excluded from `build-all` until each is directly
built and smoke-tested against the published SDL2 provider — build one
explicitly with `scripts/build-package.sh <id>`.

`build-all` opens one dependency-build session and builds `sdl2-mmiyoo-lib`
first when an enabled package needs it, then reuses that build for every
consumer in the session rather than rebuilding it per app.

### WSL2 native host builds

Host builds compile selected packages with the WSL2-native compiler and
system SDL2 — no Miyoo ARM toolchain, `sdl2-mmiyoo-lib`, Docker, or
app-distribution packaging.

The first host-enabled package is Blobby Volley 2:

```sh
scripts/build-host.sh blobbyvolley2-mmiyoo
```

Build an editable local checkout (build dir stays separate from source):

```sh
HOST_SOURCE_DIR=/path/to/blobbyvolley2 \
  scripts/build-host.sh blobbyvolley2-mmiyoo
```

Run the resulting host executable with its required data directory:

```sh
HOST_SOURCE_DIR=/path/to/blobbyvolley2 \
  scripts/run-host.sh blobbyvolley2-mmiyoo
```

The runner supplies an isolated `HOME` under the host build directory by
default — override with `HOST_HOME` for persistent native settings.

Host output lives under `work/host/<package>/`. The runner checks native
requirements with `pkg-config`, fails without installing packages, and
creates no release archives. Host build metadata is optional, under the
package manifest's `host:` section.

For a reproducible native environment, use the `x86-mm-buildbot` container
(compiler, Autotools, system SDL2, native audio/video dev libs). The repo
is mounted in, so build output still lands under `work/host/`:

```sh
scripts/build-host-docker.sh build love-mmiyoo-demo
scripts/build-host-docker.sh run love-mmiyoo-demo
scripts/build-host-docker.sh shell
```

`run` forwards the WSLg/X11 video socket and WSLg PulseAudio socket when
available. Override the image with `MM_X86_BUILDBOT_IMAGE`.

### SDL provider

Cloned from `sdl2-mmiyoo-lib`'s `package.yml` (`source.repo`/`ref`,
currently `XK9274/sdl2_miyoo` at `main`) and built via `mk_miyoo.sh`, so
every consumer shares the same core, EGL/GLES, Neon helper, and headers.
`main` can lag behind work still local to whichever machine last touched
`sdl2_miyoo` — push before relying on it for anything tested against the
latest driver fixes.

Override the source explicitly when required:

```sh
SDL2_MIYOO_REPO=https://github.com/you/sdl2_miyoo.git \
SDL2_MIYOO_REF=your-branch \
scripts/build-all.sh
```

For an uncommitted `sdl2_miyoo` working-tree change, set
`SDL2_MIYOO_LOCAL_REPO=/path/to/sdl2_miyoo` instead — copies working-tree
bytes directly (`cp -a`), no commit/push needed, takes priority over
`SDL2_MIYOO_REPO`/`SDL2_MIYOO_REF`.

`build-all` builds only the currently enabled recipes; disabled
source-port recipes stay individually opt-in until their upstream package
layouts are verified.

## Local GitHub Actions Testing

This repo works with `act` once installed locally:

```sh
act workflow_dispatch -W .github/workflows/build-app.yml \
  --input package=retroarch-mmiyoo-sdl2-gl
```
