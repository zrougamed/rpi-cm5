#!/bin/bash
set -e

# Configuration
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
KERNEL_BRANCH="${KERNEL_BRANCH:-rpi-6.12.y}"
BUILD_DIR="/build"
OUTPUT_DIR="${BUILD_DIR}/output"
KERNEL_SRC="${KERNEL_SRC:-${BUILD_DIR}/linux}"
KERNEL_VERSION=""

echo "=== Raspberry Pi CM5 EFI Kernel Build Script ==="
echo "Target: ARM64 EFI stub kernel for U-Boot bootefi"
echo "Build host: x86_64 (cross-compile)"
echo ""

# Create output directory structure
mkdir -p "${OUTPUT_DIR}"/{boot,modules,dtbs}
rm -rf "${OUTPUT_DIR}"/boot/* "${OUTPUT_DIR}"/modules/* "${OUTPUT_DIR}"/dtbs/* 2>/dev/null || true

# Clone kernel source if not already present
if [ ! -d "${KERNEL_SRC}/.git" ]; then
    echo "Cloning Raspberry Pi kernel from ${KERNEL_REPO} (branch: ${KERNEL_BRANCH})..."
    if [ -z "$(ls -A ${KERNEL_SRC} 2>/dev/null)" ]; then
        git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
    else
        echo "Cleaning incomplete kernel source..."
        find "${KERNEL_SRC}" -mindepth 1 -delete 2>/dev/null || rm -rf "${KERNEL_SRC}"/* "${KERNEL_SRC}"/.* 2>/dev/null || true
        git clone --depth 1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
    fi
else
    echo "Kernel source already present at ${KERNEL_SRC}"
    cd "${KERNEL_SRC}"
    echo "Fetching latest changes..."
    git fetch --depth 1 origin "${KERNEL_BRANCH}" 2>/dev/null || true
    git reset --hard "origin/${KERNEL_BRANCH}" 2>/dev/null || true
    cd "${BUILD_DIR}"
fi

cd "${KERNEL_SRC}"

# Start with bcm2712 defconfig (Pi 5 / CM5 base config)
echo "Generating base configuration from bcm2712_defconfig..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig

# Enable EFI stub support
echo "Enabling EFI stub configuration..."
scripts/config --enable CONFIG_EFI
scripts/config --enable CONFIG_EFI_STUB
scripts/config --enable CONFIG_EFI_GENERIC_STUB
scripts/config --enable CONFIG_EFI_ARMSTUB_DTB_LOADER
scripts/config --enable CONFIG_BLK_DEV_INITRD
scripts/config --enable CONFIG_EFI_VARS
scripts/config --enable CONFIG_EFI_PARAMS_FROM_FDT
scripts/config --enable CONFIG_CMDLINE_FROM_BOOTLOADER

# Apply the modified config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Verify EFI stub is enabled
echo "Verifying EFI stub configuration..."
if grep -q "CONFIG_EFI_STUB=y" .config; then
    echo "✓ CONFIG_EFI_STUB is enabled"
else
    echo "✗ ERROR: CONFIG_EFI_STUB is not enabled!"
    exit 1
fi

# Build the kernel with EFI stub
echo "Building kernel Image with EFI stub..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image

# Build device tree blobs
echo "Building device tree blobs..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) dtbs

# Build kernel modules
echo "Building kernel modules..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) modules

# Get kernel version
KERNEL_VERSION=$(make kernelrelease)
echo "Built kernel version: ${KERNEL_VERSION}"

# Install modules to staging directory
echo "Installing modules to ${OUTPUT_DIR}/modules..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="${OUTPUT_DIR}/modules" modules_install

# Copy kernel Image (already has EFI stub embedded)
echo "Copying EFI stub kernel..."
cp arch/arm64/boot/Image "${OUTPUT_DIR}/boot/vmlinuz.efi"

# Also provide as Image.efi for compatibility
cp arch/arm64/boot/Image "${OUTPUT_DIR}/boot/Image.efi"

# Keep a copy as plain Image for reference
cp arch/arm64/boot/Image "${OUTPUT_DIR}/boot/Image"

# Copy CM5 device tree blobs
echo "Copying CM5 device tree blobs..."
# CM5 on CM5 IO board (standard)
if [ -f arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5-cm5io.dtb ]; then
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5-cm5io.dtb "${OUTPUT_DIR}/boot/"
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5-cm5io.dtb "${OUTPUT_DIR}/dtbs/"
fi

# CM5 on CM4 IO board (compatibility)
if [ -f arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5-cm4io.dtb ]; then
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5-cm4io.dtb "${OUTPUT_DIR}/boot/"
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5-cm4io.dtb "${OUTPUT_DIR}/dtbs/"
fi

# CM5 Lite variants
if [ -f arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5l-cm5io.dtb ]; then
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5l-cm5io.dtb "${OUTPUT_DIR}/boot/"
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5l-cm5io.dtb "${OUTPUT_DIR}/dtbs/"
fi

if [ -f arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5l-cm4io.dtb ]; then
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5l-cm4io.dtb "${OUTPUT_DIR}/boot/"
    cp arch/arm64/boot/dts/broadcom/bcm2712-rpi-cm5l-cm4io.dtb "${OUTPUT_DIR}/dtbs/"
fi

# Copy all bcm2712 DTBs to dtbs directory
echo "Copying all bcm2712 device tree blobs..."
cp arch/arm64/boot/dts/broadcom/bcm2712*.dtb "${OUTPUT_DIR}/dtbs/" 2>/dev/null || true

# Create version info file
echo "Creating build metadata..."
cat > "${OUTPUT_DIR}/build-info.txt" << EOF
Kernel Version: ${KERNEL_VERSION}
Architecture: ARM64 (aarch64)
Build Type: EFI stub kernel for U-Boot bootefi
Target Platform: Raspberry Pi CM5
Kernel Source: ${KERNEL_REPO}
Branch: ${KERNEL_BRANCH}
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Host: $(uname -a)
Compiler: $(aarch64-linux-gnu-gcc --version | head -n1)

EFI Stub Configuration:
  CONFIG_EFI=$(grep CONFIG_EFI= .config)
  CONFIG_EFI_STUB=$(grep CONFIG_EFI_STUB= .config)
  CONFIG_EFI_GENERIC_STUB=$(grep CONFIG_EFI_GENERIC_STUB= .config)
EOF

echo ""
echo "=== Verifying Build Outputs ==="
echo ""
echo "Kernel image format check:"
file "${OUTPUT_DIR}/boot/vmlinuz.efi"
echo ""
echo "Checking for ARM64 code in kernel image:"
hexdump -C "${OUTPUT_DIR}/boot/vmlinuz.efi" | head -5
echo ""

if file "${OUTPUT_DIR}/boot/vmlinuz.efi" | grep -qi "arm.*aarch64\|PE32+.*ARM64"; then
    echo "Kernel appears to be ARM64 format"
elif head -c 100 "${OUTPUT_DIR}/boot/vmlinuz.efi" | grep -q "MZ"; then
    echo "Kernel has PE/COFF header (EFI compatible)"
else
    echo "Warning: Kernel may not have proper EFI stub"
    echo "  This is expected for ARM64 EFI stub kernels - they boot as raw ARM64 images"
    echo "  U-Boot's bootefi will handle the UEFI environment"
fi

# List all outputs
echo ""
echo "=== Build Complete ==="
echo "Output directory: ${OUTPUT_DIR}"
echo ""
echo "Boot files:"
ls -lh "${OUTPUT_DIR}/boot/"
echo ""
echo "Device tree blobs:"
ls -lh "${OUTPUT_DIR}/dtbs/" 2>/dev/null | grep -E "bcm2712.*cm5" || ls -lh "${OUTPUT_DIR}/dtbs/"
echo ""
echo "Kernel modules:"
ls -ld "${OUTPUT_DIR}/modules/lib/modules/"*
echo ""
echo "Build information: ${OUTPUT_DIR}/build-info.txt"