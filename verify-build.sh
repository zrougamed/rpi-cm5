#!/bin/bash

OUTPUT_DIR="${1:-/build/output}"
ERRORS=0
WARNINGS=0

echo "=== CM5 EFI Kernel Build Verification ==="
echo "Checking outputs in: ${OUTPUT_DIR}"
echo ""

check_file() {
    local file=$1
    local description=$2
    local required=${3:-yes}
    
    if [ -f "${file}" ]; then
        echo "✓ ${description}: ${file}"
        local size=$(stat -c%s "${file}")
        echo "  Size: ${size} bytes"
        return 0
    else
        if [ "${required}" = "yes" ]; then
            echo "✗ MISSING (required): ${description}"
            echo "  Expected: ${file}"
            ERRORS=$((ERRORS + 1))
        else
            echo "⚠ MISSING (optional): ${description}"
            echo "  Expected: ${file}"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    fi
}

check_dir() {
    local dir=$1
    local description=$2
    
    if [ -d "${dir}" ]; then
        echo "✓ ${description}: ${dir}"
        local count=$(find "${dir}" -type f | wc -l)
        echo "  Files: ${count}"
        return 0
    else
        echo "✗ MISSING: ${description}"
        echo "  Expected: ${dir}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

echo "--- Boot Files ---"
if check_file "${OUTPUT_DIR}/boot/vmlinuz.efi" "EFI stub kernel"; then
    # Verify it's actually an EFI binary
    echo -n "  Checking EFI format: "
    if file "${OUTPUT_DIR}/boot/vmlinuz.efi" | grep -q "executable"; then
        echo "✓ Valid PE/COFF executable"
    else
        echo "⚠ Warning: May not be proper EFI format"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

check_file "${OUTPUT_DIR}/boot/Image" "Raw kernel Image" "no"
check_file "${OUTPUT_DIR}/boot/Image.efi" "Alternate EFI kernel name" "no"
echo ""

echo "--- Device Tree Blobs ---"
DTB_FOUND=0
for dtb in "bcm2712-rpi-cm5-cm5io.dtb" "bcm2712-rpi-cm5-cm4io.dtb" \
           "bcm2712-rpi-cm5l-cm5io.dtb" "bcm2712-rpi-cm5l-cm4io.dtb"; do
    if check_file "${OUTPUT_DIR}/dtbs/${dtb}" "CM5 DTB: ${dtb}" "no"; then
        DTB_FOUND=$((DTB_FOUND + 1))
    fi
done

if [ ${DTB_FOUND} -eq 0 ]; then
    echo "✗ ERROR: No CM5 DTBs found!"
    ERRORS=$((ERRORS + 1))
elif [ ${DTB_FOUND} -lt 2 ]; then
    echo "⚠ Warning: Only ${DTB_FOUND} CM5 DTB(s) found (expected 2-4)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

echo "--- Kernel Modules ---"
if check_dir "${OUTPUT_DIR}/modules/lib/modules" "Kernel modules directory"; then
    KVER=$(ls -1 "${OUTPUT_DIR}/modules/lib/modules/" | head -n1)
    if [ -n "${KVER}" ]; then
        echo "  Kernel version: ${KVER}"
        if [ -d "${OUTPUT_DIR}/modules/lib/modules/${KVER}/kernel" ]; then
            echo "  ✓ kernel/ directory present"
        else
            echo "  ⚠ kernel/ directory missing"
            WARNINGS=$((WARNINGS + 1))
        fi

    else
        echo "  ✗ No kernel version directory found"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

echo "--- Build Metadata ---"
check_file "${OUTPUT_DIR}/build-info.txt" "Build information file" "no"
echo ""

echo "=== Verification Summary ==="
echo "Errors: ${ERRORS}"
echo "Warnings: ${WARNINGS}"
echo ""

if [ ${ERRORS} -eq 0 ]; then
    if [ ${WARNINGS} -eq 0 ]; then
        echo "✓ All checks passed! Build appears successful."
    else
        echo "⚠ Build completed with ${WARNINGS} warning(s)."
    fi
    exit 0
else
    echo "✗ Build verification failed with ${ERRORS} error(s)."
    exit 1
fi