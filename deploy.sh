#!/bin/bash
set -e

# End-to-end deployment script for CM5 EFI kernel
# This script handles the complete workflow from build to SD card deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/cm5-build-output}"
BOOT_DEV=""
ROOT_DEV=""
CARRIER_BOARD="cm5io"  # cm5io, cm4io, cm5lio, cm4lio

show_help() {
    cat << EOF
CM5 EFI Kernel - End-to-End Deployment

Usage: $0 [OPTIONS]

Options:
    -b, --build           Build kernel (skipped if already built)
    -a, --alpine          Prepare Alpine rootfs with kernel modules
    -d, --deploy DEVICE   Deploy to SD card device (e.g., /dev/sdc)
    -c, --carrier BOARD   Carrier board type (default: cm5io)
                          Options: cm5io, cm4io, cm5lio (lite), cm4lio (lite)
    -o, --output DIR      Output directory (default: /tmp/cm5-build-output)
    -r, --rootfs DIR      Alpine rootfs directory (default: /tmp/alpine-rootfs)
    -h, --help            Show this help

Examples:
    # Build kernel only
    $0 --build

    # Build kernel and prepare Alpine rootfs
    $0 --build --alpine

    # Build, prepare Alpine, and deploy to /dev/sdc
    $0 --build --alpine --deploy /dev/sdc

    # Deploy existing build with Alpine
    $0 --alpine --deploy /dev/sdc --carrier cm4io

Carrier Board Types:
    cm5io   - CM5 on CM5 IO Board (standard)
    cm4io   - CM5 on CM4 IO Board (compatibility)
    cm5lio  - CM5 Lite on CM5 IO Board
    cm4lio  - CM5 Lite on CM4 IO Board

EOF
}

# Parse arguments
DO_BUILD=false
DO_DEPLOY=false
DO_ALPINE=false
ROOTFS_DIR="/tmp/alpine-rootfs"

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--build)
            DO_BUILD=true
            shift
            ;;
        -a|--alpine)
            DO_ALPINE=true
            shift
            ;;
        -d|--deploy)
            DO_DEPLOY=true
            BOOT_DEV="$2"
            shift 2
            ;;
        -c|--carrier)
            CARRIER_BOARD="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -r|--rootfs)
            ROOTFS_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate carrier board
case $CARRIER_BOARD in
    cm5io)
        DTB_FILE="bcm2712-rpi-cm5-cm5io.dtb"
        ;;
    cm4io)
        DTB_FILE="bcm2712-rpi-cm5-cm4io.dtb"
        ;;
    cm5lio)
        DTB_FILE="bcm2712-rpi-cm5l-cm5io.dtb"
        ;;
    cm4lio)
        DTB_FILE="bcm2712-rpi-cm5l-cm4io.dtb"
        ;;
    *)
        echo "Error: Invalid carrier board: $CARRIER_BOARD"
        exit 1
        ;;
esac

echo "=== CM5 EFI Kernel Deployment ==="
echo "Output directory: ${OUTPUT_DIR}"
echo "Carrier board: ${CARRIER_BOARD}"
echo "DTB file: ${DTB_FILE}"
echo ""

# Build if requested
if [ "$DO_BUILD" = true ]; then
    echo "--- Building Kernel ---"
    
    if command -v docker &> /dev/null; then
        echo "Using Docker build..."
        make -C "${SCRIPT_DIR}" build-docker OUTPUT_DIR="${OUTPUT_DIR}"
    else
        echo "Docker not found, using native build..."
        if [ -z "$CROSS_COMPILE" ]; then
            export ARCH=arm64
            export CROSS_COMPILE=aarch64-linux-gnu-
        fi
        make -C "${SCRIPT_DIR}" build OUTPUT_DIR="${OUTPUT_DIR}"
    fi
    
    echo ""
    echo "--- Compiling Boot Script ---"
    make -C "${SCRIPT_DIR}" compile-boot-script
    
    echo ""
    echo "--- Verifying Build ---"
    "${SCRIPT_DIR}/verify-build.sh" "${OUTPUT_DIR}"
    
    echo ""
fi

# Prepare Alpine rootfs if requested
if [ "$DO_ALPINE" = true ]; then
    echo "--- Preparing Alpine Rootfs ---"
    "${SCRIPT_DIR}/prepare-alpine-rootfs.sh" "${ROOTFS_DIR}" "${OUTPUT_DIR}"
    echo ""
fi

# Verify build exists
if [ ! -f "${OUTPUT_DIR}/boot/vmlinuz.efi" ]; then
    echo "Error: Kernel not built. Run with --build first."
    exit 1
fi

if [ ! -f "${OUTPUT_DIR}/dtbs/${DTB_FILE}" ]; then
    echo "Error: DTB not found: ${DTB_FILE}"
    echo "Available DTBs:"
    ls -1 "${OUTPUT_DIR}/dtbs/"
    exit 1
fi

# Deploy if requested
if [ "$DO_DEPLOY" = true ]; then
    if [ -z "$BOOT_DEV" ]; then
        echo "Error: No device specified for deployment"
        exit 1
    fi
    
    if [ ! -b "$BOOT_DEV" ]; then
        echo "Error: Device not found: $BOOT_DEV"
        exit 1
    fi
    
    # Determine partitions
    if [[ "$BOOT_DEV" == *"nvme"* ]]; then
        BOOT_PART="${BOOT_DEV}p1"
        ROOT_PART="${BOOT_DEV}p2"
    else
        BOOT_PART="${BOOT_DEV}1"
        ROOT_PART="${BOOT_DEV}2"
    fi
    
    echo ""
    echo "--- Deployment Configuration ---"
    echo "Target device: ${BOOT_DEV}"
    echo "Boot partition: ${BOOT_PART}"
    echo "Root partition: ${ROOT_PART}"
    echo ""
    
    read -p "WARNING: This will modify ${BOOT_DEV}. Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
    
    # Create mount points
    BOOT_MNT=$(mktemp -d)
    ROOT_MNT=$(mktemp -d)
    
    cleanup() {
        echo "Cleaning up..."
        umount "$BOOT_MNT" 2>/dev/null || true
        umount "$ROOT_MNT" 2>/dev/null || true
        rmdir "$BOOT_MNT" "$ROOT_MNT" 2>/dev/null || true
    }
    trap cleanup EXIT
    
    echo ""
    echo "--- Deploying Boot Files ---"
    
    # Mount boot partition
    echo "Mounting boot partition..."
    sudo mount "$BOOT_PART" "$BOOT_MNT"
    
    # Copy kernel
    echo "Copying EFI kernel..."
    sudo cp "${OUTPUT_DIR}/boot/vmlinuz.efi" "$BOOT_MNT/"
    
    # Copy DTB
    echo "Copying DTB (${DTB_FILE})..."
    sudo cp "${OUTPUT_DIR}/dtbs/${DTB_FILE}" "$BOOT_MNT/"
    
    # Copy boot script
    if [ -f "${SCRIPT_DIR}/boot.scr" ]; then
        echo "Copying boot script..."
        sudo cp "${SCRIPT_DIR}/boot.scr" "$BOOT_MNT/"
    else
        echo "Warning: boot.scr not found, skipping"
    fi
    
    # Update boot script configuration
    echo "Updating boot configuration..."
    sudo bash -c "cat > $BOOT_MNT/boot-config.txt" << EOF
# CM5 EFI Boot Configuration
# Generated: $(date)
Carrier Board: ${CARRIER_BOARD}
DTB File: ${DTB_FILE}
Kernel: vmlinuz.efi
EOF
    
    sudo umount "$BOOT_MNT"
    echo "✓ Boot files deployed"
    
    echo ""
    echo "--- Deploying Kernel Modules ---"
    
    # Mount root partition
    echo "Mounting root partition..."
    sudo mount "$ROOT_PART" "$ROOT_MNT"
    
    # Deploy Alpine rootfs if prepared, otherwise just copy modules
    if [ "$DO_ALPINE" = true ] && [ -d "${ROOTFS_DIR}" ]; then
        echo "Deploying complete Alpine rootfs with kernel modules..."
        sudo rsync -av --delete "${ROOTFS_DIR}/" "$ROOT_MNT/"
        echo "✓ Alpine rootfs deployed"
    else
        echo "Copying kernel modules only..."
        sudo mkdir -p "$ROOT_MNT/lib/modules"
        sudo cp -r "${OUTPUT_DIR}/modules/lib/modules/"* "$ROOT_MNT/lib/modules/"
        
        # Update module dependencies
        KVER=$(ls -1 "${OUTPUT_DIR}/modules/lib/modules/" | head -n1)
        if [ -n "$KVER" ]; then
            echo "Running depmod for kernel ${KVER}..."
            sudo depmod -b "$ROOT_MNT" "$KVER" 2>/dev/null || echo "Warning: depmod failed (may need to run on target)"
        fi
        echo "✓ Kernel modules deployed"
    fi
    
    sudo umount "$ROOT_MNT"
    
    echo ""
    echo "=== Deployment Complete ==="
    echo ""
    if [ "$DO_ALPINE" = true ]; then
        echo "Alpine Linux with CM5 EFI kernel deployed successfully!"
        echo ""
        echo "Default credentials:"
        echo "  Username: root"
        echo "  Password: alpine"
        echo ""
    fi
    echo "Next steps:"
    echo "  1. Insert SD card into CM5"
    echo "  2. Connect serial console (GPIO 14/15, 115200 baud)"
    echo "  3. Power on and watch U-Boot boot messages"
    echo "  4. Kernel should boot automatically via boot.scr"

else
    echo "Build complete! Outputs in: ${OUTPUT_DIR}"
    if [ "$DO_ALPINE" = true ]; then
        echo "Alpine rootfs in: ${ROOTFS_DIR}"
    fi
    echo ""
    echo "To deploy to SD card, run:"
    CMD="  $0 --deploy /dev/sdX --carrier ${CARRIER_BOARD}"
    if [ "$DO_ALPINE" = true ]; then
        CMD="${CMD} --alpine"
    fi
    echo "${CMD}"
fi