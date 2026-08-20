# Contributing

This repo is local-first build automation. Keep package recipes small and make
the generated `app-dist` output reproducible from scripts.

Follow the docs already set up in `docs/` when adding or changing packages. The
docs are intentionally light for now and will be expanded as real packages are
added.

## Pull Request Body

Use this shape for PRs:

```md
## Summary

Briefly explain the package or buildbot change.

## What It Adds

Describe the app, package recipe, scripts, templates, or workflow behavior being
added.

## Build Behavior

Explain what the build does: upstream repo/ref, dependencies, build commands,
files copied into `app-dist`, tokenised config, and generated archives.

## Device Behavior

Explain what the app should do on the target device after install or launch.
```

## Checks

Run these before opening a PR or publishing changes:

```sh
scripts/validate-package.sh retroarch-mmiyoo-sdl2-gl
scripts/build-package.sh retroarch-mmiyoo-sdl2-gl
scripts/build-all.sh
act workflow_dispatch -W .github/workflows/build-app.yml --input package=retroarch-mmiyoo-sdl2-gl -n
act workflow_dispatch -W .github/workflows/build-all.yml -n
```

Generated files under `work/`, `artifacts/`, and `dist/` should not be committed.

`work/` is scratch space for cloned sources, intermediate build files, and the
temporary `app-dist` directory before packaging.
