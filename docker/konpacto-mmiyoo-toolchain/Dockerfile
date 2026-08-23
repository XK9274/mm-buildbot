ARG BASE_IMAGE=miyoomini-toolchain
FROM ${BASE_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc-multilib \
        libc6-dev-i386 \
    && rm -rf /var/lib/apt/lists/*
