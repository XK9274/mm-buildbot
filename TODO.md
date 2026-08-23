# TODO

- Nested toolchain: `sdl2-mmiyoo-lib`'s build.sh runs `mk_miyoo.sh --docker`,
  which spins its own Docker container for cross-compiling. Under
  `scripts/build-all.sh` (and inside CI/`act`, which is itself containerized)
  this means Docker-in-Docker. Should support a single-toolchain mode where
  the outer build process (CI runner, act, or a host build) cross-compiles
  directly instead of nesting another container.
