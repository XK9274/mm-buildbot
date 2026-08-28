# Package Config

Each package has a `package.yml` file:

```yaml
id: example-app
name: Example App
modified_source: no
version: manual
source:
  repo: https://github.com/example/example-app.git
  ref: main
app_dist:
  template: packages/example-app/templates
  output_name: ExampleApp
tokens:
  APP_ID: example-app
  APP_NAME: Example App
```

`modified_source` is required on every package: `no` when the upstream
source tree is built unmodified, `yes` when the recipe patches or injects
files into it.

App distributions may use either a pinned Git source (`repo` and `ref`) or a
pinned release archive (`url` and `sha256`), plus an `app_dist` template. They
retain the current template/tokenisation flow.

Standalone diagnostic tools use an archive source and an `artifact` section:

```yaml
id: example-tool-bundle
name: Example Tool Bundle
modified_source: no
version: 1.0
source:
  url: https://example.invalid/example-tool-1.0.tar.xz
  sha256: <pinned SHA-256>
artifact:
  type: tool_bundle
  output_name: example-tool-bundle
```

`tool_bundle` build scripts receive a clean staging directory as their fourth
argument. Its contents are zipped directly: no `app-dist` template, token
replacement, or `launch.sh` is created.

`artifact.type` defaults to `app_dist` when omitted. A third type, `port`,
stages to `work/<id>/port` the same way `tool_bundle` stages to
`work/<id>/bundle` (no template copy, same required fields as `tool_bundle`)
— used for the `Roms/PORTS/...` Onion-launcher layout instead of an
`App/<name>` app-dist. See `packages/vvvvvv-mmiyoo` for a worked example.

Tool bundles use `bin/` for executables and `lib/` for every non-system shared
library built by the recipe. Keep executables dynamically linked where the
device provides the dependency; stage private shared libraries beside them
rather than converting them to static copies.

Required fields:

- `id`
- `name`
- `modified_source`
- for `app_dist`: either `source.repo`/`source.ref` or
  `source.url`/`source.sha256`, and `app_dist.template`
- for `tool_bundle`/`port`: either `source.repo`/`source.ref` or `source.url`/`source.sha256`, plus `artifact.output_name`

Optional fields:

- `build_all: false` excludes the package from `scripts/build-all.sh`'s
  aggregate build (see below). Omitting it defaults to enabled.
- `sdl2_gles: no`, on a package that depends on `sdl2-mmiyoo-lib`, builds
  that provider without GL/EGL/GLES symbols for consumers that don't use
  them (see `packages/vvvvvv-mmiyoo/package.yml`).
- `host:` declares a native WSL2/Linux build/run lane — see
  `docs/host-build-package-guide.md` for the full schema
  (`build_system`, `source_dir`, `pkg_config`, `prepare_script`/
  `post_build_script`/`run_script`, `configure_args`, `build_target`,
  `outputs`).

The scripts intentionally keep the package format small for now. More fields can
be added once real package examples are available.

## Dependencies and SDL runtime closure

An app distribution can declare packages it needs built first:

```yaml
depends_on:
  - sdl2-mmiyoo-lib
build_all: false
```

The builder detects dependency cycles, builds dependencies before the consumer,
and exports `MMIYOO_SDL2_PREFIX` when the SDL provider is used. The optional
`sdl2-mmiyoo-addons` provider is exported as `MMIYOO_SDL2_ADDONS_PREFIX`.
Source-port recipes use these prefixes for headers, `pkg-config`, linking, and
to stage/verify their shared-library runtime closure. `build_all: false` keeps
unverified or externally-blocked recipes out of aggregate builds.
