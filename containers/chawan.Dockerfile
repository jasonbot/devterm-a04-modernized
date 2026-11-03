FROM docker.io/library/debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive
# Nim 2.2.12 is newer than the compiler available in trixie; use the official
# aarch64 build.  Chawan compiles to C, so the rest is a normal gcc build.
ARG NIM_VER=2.2.12

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gcc \
        libbrotli-dev \
        libssh2-1-dev \
        libssl-dev \
        make \
        pkg-config \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fL "https://nim-lang.org/download/nim-${NIM_VER}-linux_arm64.tar.xz" \
        -o /tmp/nim.tar.xz \
    && tar -xJf /tmp/nim.tar.xz -C /opt \
    && rm -f /tmp/nim.tar.xz
ENV PATH=/opt/nim-2.2.12/bin:$PATH
