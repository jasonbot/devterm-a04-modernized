SHELL := /bin/bash
.DEFAULT_GOAL := image

IMAGE := artifacts/devterm-a04.img
COMPRESSED := $(IMAGE).zst
DEVICE ?= /dev/sdX

.PHONY: all image fetch uboot ly chawan kmscon rootfs verify flash clean distclean

all: image

fetch:
	./scripts/fetch.sh

uboot: fetch
	./scripts/build-uboot.sh

ly: fetch
	./scripts/build-ly.sh

chawan: fetch
	./scripts/build-chawan.sh

kmscon: fetch
	./scripts/build-kmscon.sh

rootfs: ly uboot chawan kmscon
	./scripts/build-rootfs.sh

image: rootfs
	./scripts/build-image.sh

verify:
	./scripts/verify-image.sh

flash: $(COMPRESSED)
	@test "$(DEVICE)" != "/dev/sdX" || { echo "set DEVICE=/dev/sdX"; exit 1; }
	zstd -dc "$(COMPRESSED)" | sudo dd of="$(DEVICE)" bs=4M iflag=fullblock oflag=direct status=progress conv=fsync

clean:
	rm -rf build

distclean: clean
	rm -rf artifacts/devterm-a04.img artifacts/devterm-a04.img.zst \
	       artifacts/rootfs artifacts/rootfs.ext4 artifacts/export \
	       artifacts/fonts artifacts/carbonyl artifacts/carboxyl artifacts/chawan \
	       artifacts/kmscon artifacts/nmtui-go \
	       artifacts/vendor artifacts/uboot \
	       artifacts/src artifacts/SHA256SUMS artifacts/*.partition-table.txt
