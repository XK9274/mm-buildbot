FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        binutils \
        build-essential \
        ca-certificates \
        cmake \
        git \
        libasound2-dev \
        libboost-dev \
        libfreetype6-dev \
        libgl1-mesa-dev \
        libgles2-mesa-dev \
        libglu1-mesa-dev \
        libmodplug-dev \
        libmpg123-dev \
        libopenal-dev \
        libpulse-dev \
        libsdl2-dev \
        libsdl2-image-dev \
        libsdl2-mixer-dev \
        libtheora-dev \
        libvorbis-dev \
        libwayland-dev \
        libx11-dev \
        libxcursor-dev \
        libxext-dev \
        libxinerama-dev \
        libxi-dev \
        libxkbcommon-dev \
        libxrandr-dev \
        libxss-dev \
        libxtst-dev \
        libtool \
        m4 \
        make \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
