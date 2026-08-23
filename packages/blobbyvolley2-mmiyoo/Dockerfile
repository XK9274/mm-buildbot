ARG BASE_IMAGE=miyoomini-toolchain
FROM ${BASE_IMAGE}

# Blobby Volley 2 only uses header-only Boost (algorithm/string, crc,
# exception) -- installing the host package is sufficient since none of it
# is architecture-specific; build.sh copies the headers into the cross
# sysroot so CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY still finds them.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libboost-dev \
    && rm -rf /var/lib/apt/lists/*
