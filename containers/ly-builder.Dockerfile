FROM docker.io/library/debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        libpam0g-dev \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*
