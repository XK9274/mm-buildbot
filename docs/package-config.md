# Package Config

Each package has a `package.yml` file:

```yaml
id: example-app
name: Example App
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

App distributions may use either a pinned Git source (`repo` and `ref`) or a
pinned release archive (`url` and `sha256`), plus an `app_dist` template. They
retain the current template/tokenisation flow.

Standalone diagnostic tools use an archive source and an `artifact` section:

```yaml
id: example-tool-bundle
name: Example Tool Bundle
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

Tool bundles use `bin/` for executables and `lib/` for every non-system shared
library built by the recipe. Keep executables dynamically linked where the
device provides the dependency; stage private shared libraries beside them
rather than converting them to static copies.

Required fields:

- `id`
- `name`
- for `app_dist`: either `source.repo`/`source.ref` or
  `source.url`/`source.sha256`, and `app_dist.template`
- for `tool_bundle`: either `source.repo`/`source.ref` or `source.url`/`source.sha256`, plus `artifact.output_name`

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
