# TODO

- Audit `packages/*` for hardcoded paths outside this repo (any
  `/home/<user>/...`-style absolute path) and for wording that frames this as
  a single person's local setup rather than general-purpose infrastructure.
  `dev-tools/probes-app` was fixed for this; other packages haven't been
  checked yet.
- DungeonRush package: Add [DungeonRush](https://github.com/XK9274/DungeonRush)
  as a package in the buildbot in the future. The original project hardcodes
  some values that may need to be changed for the buildbot package.
