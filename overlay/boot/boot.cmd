setenv bootargs root=LABEL=devterm-root rootfstype=ext4 rootwait rw console=ttyS0,115200 console=tty0 fbcon=rotate:1 loglevel=4 mem_sleep_default=s2idle
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/Image
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/devterm-a04.dtb
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /boot/initrd.img
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
