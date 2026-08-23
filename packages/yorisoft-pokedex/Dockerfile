ARG BASE_IMAGE=miyoomini-toolchain
FROM ${BASE_IMAGE}

# Retained for compatibility with local builds that still choose this image.
# The buildbot now uses scripts/mksdl2.sh as the shared add-ons provider.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libtool \
    && rm -rf /var/lib/apt/lists/*
