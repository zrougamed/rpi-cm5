#!/bin/sh
# U-Boot boot script for CM5 EFI kernel loading
# This script should be compiled with mkimage and placed on the boot partition

# =============================================================================
# Configuration - Adjust these for your setup
# =============================================================================

# Boot device and partition (adjust based on your setup)
# Example: mmc 0:1 for SD card partition 1
# Example: nvme 0:1 for NVMe partition 1
setenv boot_dev "mmc 0"
setenv boot_part "1"
setenv boot_dev_part "${boot_dev}:${boot_part}"

# Kernel and DTB paths on boot partition
setenv kernel_file "vmlinuz.efi"
setenv dtb_file "bcm2712-rpi-cm5-cm5io.dtb"

# Memory addresses for loading (standard ARM64 locations)
setenv kernel_addr_r 0x00080000
setenv fdt_addr_r 0x02600000
setenv ramdisk_addr_r 0x02700000

# Root filesystem location
# For SD/eMMC: root=/dev/mmcblk0p2
# For NVMe: root=/dev/nvme0n1p2
setenv rootdev "/dev/mmcblk0p2"

# Kernel command line arguments
setenv bootargs "console=serial0,115200 console=tty1 root=${rootdev} rootfstype=ext4 rootwait rw"

# =============================================================================
# Boot sequence
# =============================================================================

echo "=== Raspberry Pi CM5 EFI Boot ==="
echo "Boot device: ${boot_dev_part}"
echo "Kernel: ${kernel_file}"
echo "DTB: ${dtb_file}"
echo ""

# Load kernel (EFI stub)
echo "Loading EFI kernel from ${boot_dev_part}..."
if load ${boot_dev} ${boot_dev_part} ${kernel_addr_r} ${kernel_file}; then
    echo "Kernel loaded at ${kernel_addr_r}"
else
    echo "Failed to load kernel ${kernel_file}"
    exit 1
fi

# Load device tree
echo "Loading device tree from ${boot_dev_part}..."
if load ${boot_dev} ${boot_dev_part} ${fdt_addr_r} ${dtb_file}; then
    echo "DTB loaded at ${fdt_addr_r}"
else
    echo "Failed to load DTB ${dtb_file}"
    exit 1
fi

# Optional: Load initramfs if present
if test -e ${boot_dev} ${boot_dev_part} initramfs.cpio.gz; then
    echo "Loading initramfs..."
    load ${boot_dev} ${boot_dev_part} ${ramdisk_addr_r} initramfs.cpio.gz
    setenv ramdisk_size ${filesize}
fi

# Set FDT address for EFI
fdt addr ${fdt_addr_r}
fdt resize

# Boot using EFI
echo ""
echo "Booting kernel via EFI stub..."
echo "Kernel address: ${kernel_addr_r}"
echo "FDT address: ${fdt_addr_r}"
echo "Command line: ${bootargs}"
echo ""

# Boot the EFI kernel with device tree
bootefi ${kernel_addr_r} ${fdt_addr_r}

# If we get here, boot failed
echo ""
echo "Boot failed!"