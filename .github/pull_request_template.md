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

## Checks

- [ ] `scripts/validate-package.sh <package>`
- [ ] `scripts/build-package.sh <package>`
- [ ] `scripts/build-all.sh`
- [ ] `act workflow_dispatch -W .github/workflows/build-app.yml --input package=<package> -n`
