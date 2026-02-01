#!/bin/bash
set -e

ALPINE_VERSION="${ALPINE_VERSION:-3.23.0}"
ALPINE_ARCH="aarch64"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ROOTFS_DIR="${1:-/tmp/alpine-rootfs}"
KERNEL_OUTPUT="${2:-/tmp/cm5-build-output}"

echo "=== Alpine Linux Rootfs Preparation for CM5 ==="
echo "Alpine version: ${ALPINE_VERSION}"
echo "Rootfs directory: ${ROOTFS_DIR}"
echo "Kernel output: ${KERNEL_OUTPUT}"
echo ""

if [ ! -d "${KERNEL_OUTPUT}/modules/lib/modules" ]; then
    echo "Error: Kernel modules not found in ${KERNEL_OUTPUT}"
    echo "Run 'make build-docker' first"
    exit 1
fi

echo "Creating rootfs directory..."
mkdir -p "${ROOTFS_DIR}"

ROOTFS_TARBALL="alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
if [ ! -f "/tmp/${ROOTFS_TARBALL}" ]; then
    echo "Downloading Alpine minirootfs..."
    wget -O "/tmp/${ROOTFS_TARBALL}" \
        "${ALPINE_MIRROR}/v${ALPINE_VERSION%.*}/releases/${ALPINE_ARCH}/${ROOTFS_TARBALL}"
else
    echo "Using cached Alpine rootfs: /tmp/${ROOTFS_TARBALL}"
fi

echo "Extracting Alpine rootfs..."
sudo tar -xzf "/tmp/${ROOTFS_TARBALL}" -C "${ROOTFS_DIR}"

echo "Installing kernel modules..."
KVER=$(ls -1 "${KERNEL_OUTPUT}/modules/lib/modules/" | head -n1)
echo "Kernel version: ${KVER}"
sudo cp -r "${KERNEL_OUTPUT}/modules/lib/modules/"* "${ROOTFS_DIR}/lib/modules/"


echo "Creating mount points..."
sudo mkdir -p "${ROOTFS_DIR}"/{dev,proc,sys,run,tmp,boot}

echo "Configuring fstab..."
sudo bash -c "cat > ${ROOTFS_DIR}/etc/fstab" << 'EOF'
# <file system>    <mount point>   <type>  <options>           <dump>  <pass>
/dev/mmcblk0p2     /               ext4    defaults,noatime    0       1
/dev/mmcblk0p1     /boot           vfat    defaults            0       2
proc               /proc           proc    defaults            0       0
sysfs              /sys            sysfs   defaults            0       0
devpts             /dev/pts        devpts  gid=5,mode=620      0       0
tmpfs              /run            tmpfs   defaults            0       0
tmpfs              /tmp            tmpfs   defaults            0       0
EOF


echo "Configuring hostname..."
echo "box" | sudo tee "${ROOTFS_DIR}/etc/hostname" > /dev/null

echo "Configuring network..."
sudo bash -c "cat > ${ROOTFS_DIR}/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname box
EOF

echo "Configuring init system..."
sudo mkdir -p "${ROOTFS_DIR}/etc/runlevels/"{boot,default,sysinit}
for service in devfs dmesg hwdrivers mdev; do
    sudo ln -sf /etc/init.d/$service "${ROOTFS_DIR}/etc/runlevels/sysinit/$service" 2>/dev/null || true
done
for service in bootmisc hostname hwclock modules networking swap sysctl urandom; do
    sudo ln -sf /etc/init.d/$service "${ROOTFS_DIR}/etc/runlevels/boot/$service" 2>/dev/null || true
done
for service in local; do
    sudo ln -sf /etc/init.d/$service "${ROOTFS_DIR}/etc/runlevels/default/$service" 2>/dev/null || true
done

echo "Configuring serial console..."
sudo bash -c "cat >> ${ROOTFS_DIR}/etc/inittab" << 'EOF'
# Serial console
ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
EOF



echo "Setting root password to 'alpine'..."
echo "root:alpine" | sudo chroot "${ROOTFS_DIR}" /usr/sbin/chpasswd 2>/dev/null || \
    echo "Warning: Could not set password in chroot"

echo "Configuring package repositories..."
sudo bash -c "cat > ${ROOTFS_DIR}/etc/apk/repositories" << EOF
${ALPINE_MIRROR}/v${ALPINE_VERSION%.*}/main
${ALPINE_MIRROR}/v${ALPINE_VERSION%.*}/community
EOF

echo ""
echo "=== Alpine Rootfs Preparation Complete ==="

