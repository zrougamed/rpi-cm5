#!/bin/bash
set -e
# Downloads latest release or uses local archive and deploys to SD card

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="zrougamed/rpi-cm5"
CARRIER_BOARD="cm5io"
BOOT_DEV=""
WORK_DIR="/tmp/cm5-gh-release"
ARCHIVE_PATH=""

show_help() {
    cat << EOF
CM5 EFI Kernel - GitHub Release Deployment

Usage: $0 [OPTIONS]

Options:
    -d, --deploy DEVICE   Deploy to SD card device (e.g., /dev/sdc) [REQUIRED]
    -c, --carrier BOARD   Carrier board type (default: cm5io)
                          Options: cm5io, cm4io, cm5lio (lite), cm4lio (lite)
    -r, --repo REPO       GitHub repository (default: ${REPO})
    -f, --file PATH       Use local archive instead of downloading
    -w, --work-dir DIR    Working directory (default: ${WORK_DIR})
    -h, --help            Show this help

Examples:
    # Deploy from local archive
    $0 --deploy /dev/sdc --file ~/Downloads/cm5-system-6.12.67-v8-16k.zip

    # Deploy from local archive for CM5 on CM4 IO
    $0 --deploy /dev/sdc --carrier cm4io --file ~/Downloads/cm5-system-6.12.67-v8-16k.zip


Carrier Board Types:
    cm5io   - CM5 on CM5 IO Board (standard)
    cm4io   - CM5 on CM4 IO Board (compatibility)
    cm5lio  - CM5 Lite on CM5 IO Board
    cm4lio  - CM5 Lite on CM4 IO Board

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--deploy)
            BOOT_DEV="$2"
            shift 2
            ;;
        -c|--carrier)
            CARRIER_BOARD="$2"
            shift 2
            ;;
        -r|--repo)
            REPO="$2"
            shift 2
            ;;
        -f|--file)
            ARCHIVE_PATH="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
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

# Validate required arguments
if [ -z "$BOOT_DEV" ]; then
    echo "Error: Device required. Use --deploy /dev/sdX"
    show_help
    exit 1
fi

if [ ! -b "$BOOT_DEV" ]; then
    echo "Error: Device not found: $BOOT_DEV"
    exit 1
fi

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

echo "=== CM5 GitHub Release Deployment ==="
echo "Repository: ${REPO}"
echo "Carrier board: ${CARRIER_BOARD}"
echo "DTB file: ${DTB_FILE}"
echo "Target device: ${BOOT_DEV}"
echo ""

# Determine partitions
if [[ "$BOOT_DEV" == *"nvme"* ]]; then
    BOOT_PART="${BOOT_DEV}p1"
    ROOT_PART="${BOOT_DEV}p2"
else
    BOOT_PART="${BOOT_DEV}1"
    ROOT_PART="${BOOT_DEV}2"
fi

echo "Boot partition: ${BOOT_PART}"
echo "Root partition: ${ROOT_PART}"
echo ""

# Verify partitions exist
if [ ! -b "$BOOT_PART" ] || [ ! -b "$ROOT_PART" ]; then
    echo "Error: Partitions not found. Please prepare SD card first."
    echo "See README.md for SD card preparation instructions."
    exit 1
fi

read -p "WARNING: This will modify ${BOOT_DEV}. Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

# Create working directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Get or extract archive

# Use local archive
echo ""
echo "--- Using Local Archive ---"

if [ ! -f "$ARCHIVE_PATH" ] && [ ! -d "$ARCHIVE_PATH" ]; then
    echo "Error: Archive not found: $ARCHIVE_PATH"
    exit 1
fi

if [ -d "$ARCHIVE_PATH" ]; then
    # Already extracted directory
    ARCHIVE_FILE=$(basename "$ARCHIVE_PATH")
    echo "Using extracted directory: $ARCHIVE_FILE"
    cp -r "$ARCHIVE_PATH"/* .
else
    # Archive file
    ARCHIVE_FILE=$(basename "$ARCHIVE_PATH")
    echo "Archive: $ARCHIVE_FILE"
    echo "Extracting archive..."
    
    if [[ "$ARCHIVE_FILE" == *.zip ]]; then
        if ! command -v unzip &> /dev/null; then
            echo "Error: unzip not found. Install with: sudo apt-get install unzip"
            exit 1
        fi
        unzip -q "$ARCHIVE_PATH"
    elif [[ "$ARCHIVE_FILE" == *.tar.gz ]] || [[ "$ARCHIVE_FILE" == *.tgz ]]; then
        tar -xzf "$ARCHIVE_PATH"
    else
        echo "Error: Unsupported archive format. Use .zip or .tar.gz"
        exit 1
    fi
fi
    

# Verify required files exist
echo ""
echo "--- Verifying Release Contents ---"

REQUIRED_FILES=(
    "cm5-boot-files.tar.gz"
    "cm5-dtbs.tar.gz"
    "cm5-modules.tar.gz"
    "alpine-rootfs.tar.gz"
    "boot.scr"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Error: Required file not found: $file"
        echo "Archive contents:"
        ls -la
        exit 1
    fi
done

echo "✓ All required files present"

# Verify checksums if available
if [ -f "SHA256SUMS" ]; then
    echo "Verifying checksums..."
    if sha256sum -c --ignore-missing SHA256SUMS 2>/dev/null; then
        echo "✓ Checksums verified"
    else
        echo "Warning: Checksum verification failed"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Extract components
echo ""
echo "--- Extracting Components ---"

mkdir -p boot dtbs modules rootfs

echo "Extracting boot files..."
tar -xzf cm5-boot-files.tar.gz

echo "Extracting device tree blobs..."
tar -xzf cm5-dtbs.tar.gz

echo "Extracting kernel modules..."
tar -xzf cm5-modules.tar.gz

echo "Extracting Alpine rootfs..."
tar -xzf alpine-rootfs.tar.gz -C rootfs

# Verify DTB exists
if [ ! -f "dtbs/${DTB_FILE}" ]; then
    echo ""
    echo "Error: DTB not found: ${DTB_FILE}"
    echo "Available DTBs:"
    ls -1 dtbs/
    exit 1
fi

echo "✓ All components extracted"

# Display build info if available
if [ -f "build-info.txt" ]; then
    echo ""
    echo "--- Build Information ---"
    cat build-info.txt
fi

# Create mount points
BOOT_MNT=$(mktemp -d)
ROOT_MNT=$(mktemp -d)

cleanup() {
    echo "Cleaning up..."
    umount "$BOOT_MNT" 2>/dev/null || true
    umount "$ROOT_MNT" 2>/dev/null || true
    rmdir "$BOOT_MNT" "$ROOT_MNT" 2>/dev/null || true
    cd /
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Deploy boot files
echo ""
echo "--- Deploying Boot Files ---"

echo "Mounting boot partition..."
sudo mount "$BOOT_PART" "$BOOT_MNT"

# Copy kernel
echo "Copying EFI kernel..."
sudo cp boot/vmlinuz.efi "$BOOT_MNT/"

# Copy DTB
echo "Copying DTB (${DTB_FILE})..."
sudo cp "dtbs/${DTB_FILE}" "$BOOT_MNT/"

# Copy boot script
echo "Copying boot script..."
sudo cp boot.scr "$BOOT_MNT/"

# Create boot configuration
echo "Creating boot configuration..."
sudo bash -c "cat > $BOOT_MNT/boot-config.txt" << EOF
# CM5 EFI Boot Configuration
# Deployed: $(date)
Carrier Board: ${CARRIER_BOARD}
DTB File: ${DTB_FILE}
Kernel: vmlinuz.efi
EOF

sudo umount "$BOOT_MNT"
echo "✓ Boot files deployed"

# Deploy rootfs
echo ""
echo "--- Deploying Root Filesystem ---"

echo "Mounting root partition..."
sudo mount "$ROOT_PART" "$ROOT_MNT"

echo "Deploying Alpine rootfs with kernel modules..."
sudo rsync -av --delete rootfs/ "$ROOT_MNT/"

sudo umount "$ROOT_MNT"
echo "✓ Root filesystem deployed"

# Success message
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Alpine Linux with CM5 EFI kernel deployed successfully!"
echo ""
echo "Carrier: ${CARRIER_BOARD}"
echo "Device: ${BOOT_DEV}"
echo ""
echo "Default credentials:"
echo "  Username: root"
echo "  Password: alpine"
echo ""
echo "Next steps:"
echo "  1. Insert SD card into CM5"
echo "  2. Connect serial console (GPIO 14/15, 115200 baud)"
echo "  3. Power on and watch boot process"
echo "  4. Login with credentials above"