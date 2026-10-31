FROM docker.io/library/debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc \
        bison \
        build-essential \
        ca-certificates \
        curl \
        device-tree-compiler \
        flex \
        gcc-aarch64-linux-gnu \
        git \
        libgnutls28-dev \
        libssl-dev \
        make \
        python3 \
        python3-dev \
        python3-setuptools \
        swig \
        xz-utils \
        bzip2 \
    && rm -rf /var/lib/apt/lists/*
