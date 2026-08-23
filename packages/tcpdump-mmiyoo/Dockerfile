ARG BASE_IMAGE=miyoomini-toolchain
FROM ${BASE_IMAGE}

# libpcap generates its packet-filter parser while cross-building.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bison flex \
    && rm -rf /var/lib/apt/lists/*
