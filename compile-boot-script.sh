#!/bin/bash
set -e

# Compile U-Boot boot script to boot.scr
# Requires u-boot-tools (mkimage)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD_FILE="${1:-boot-efi.cmd}"
SCR_FILE="${2:-boot.scr}"

if [ ! -f "${CMD_FILE}" ]; then
    echo "Error: Boot script not found: ${CMD_FILE}"
    exit 1
fi

# Check if mkimage is available
if ! command -v mkimage &> /dev/null; then
    echo "Error: mkimage not found. Install u-boot-tools:"
    echo "  Ubuntu/Debian: apt-get install u-boot-tools"
    echo "  Alpine: apk add u-boot-tools"
    exit 1
fi

echo "Compiling U-Boot boot script..."
echo "Input:  ${CMD_FILE}"
echo "Output: ${SCR_FILE}"

mkimage -A arm64 -O linux -T script -C none -n "CM5 EFI Boot Script" \
    -d "${CMD_FILE}" "${SCR_FILE}"

echo ""
echo "✓ Boot script compiled successfully!"
echo ""
echo "To use this script:"
echo "  1. Copy ${SCR_FILE} to your boot partition (FAT32/EXT4)"
echo "  2. U-Boot will automatically find and run boot.scr"
echo "  3. Or manually run: source ${SCR_FILE}"