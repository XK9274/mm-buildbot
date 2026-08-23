ARG BASE_IMAGE=miyoomini-toolchain
FROM ${BASE_IMAGE}

# The reference LÖVE builder uses Autotools/CMake and needs a 32-bit host
# compiler for LuaJIT while cross-compiling its ARM target.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf automake cmake g++-multilib gcc-multilib libtool m4 pkg-config \
    && rm -rf /var/lib/apt/lists/*
