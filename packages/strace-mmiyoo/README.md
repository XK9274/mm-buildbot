# Miyoo strace

This bundle provides a Union-toolchain ARM hard-float build of `strace` for
diagnosing programs on the Miyoo. It is a floating binary: copy `bin/strace`
to the device and run it directly. `strace` is dynamically linked to the
device-provided C library and has no private shared-library dependencies.

Tracing requires ptrace permission for the target process. Do not use it on
critical system processes unless a temporary slowdown or interruption is
acceptable.
