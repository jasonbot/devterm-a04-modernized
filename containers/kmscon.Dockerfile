FROM docker.io/library/debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'deb http://deb.debian.org/debian trixie-backports main' \
        > /etc/apt/sources.list.d/backports.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        libdbus-1-dev \
        libdrm-dev \
        libegl-dev \
        libfontconfig-dev \
        libfreetype-dev \
        libgbm-dev \
        libgles-dev \
        libpango1.0-dev \
        libsystemd-dev \
        libudev-dev \
        libxkbcommon-dev \
        meson \
        ninja-build \
        patch \
        pkg-config \
        python3 \
        systemd-dev \
        zlib1g-dev \
    && apt-get install -y --no-install-recommends -t trixie-backports \
        libtsm-dev \
    && rm -rf /var/lib/apt/lists/*
