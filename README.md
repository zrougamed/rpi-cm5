# RPI CM5 kernel builder

## Prerequisites system Setup (Debian/Ubuntu)
```bash
sudo apt-get update
sudo apt-get install -y docker.io git make file
sudo usermod -aG docker $USER
```

## Clone and Build
```bash
git clone https://github.com/zrougamed/rpi-cm5

cd rpi-cm5

make build-docker

make compile-boot-script

make test-efi
```

## Prepare SD Card
```bash
lsblk
export SD_DEVICE=/dev/sdX
sudo umount ${SD_DEVICE}* 2>/dev/null || true
sudo parted ${SD_DEVICE} --script mklabel msdos
sudo parted ${SD_DEVICE} --script mkpart primary fat32 1MiB 513MiB
sudo parted ${SD_DEVICE} --script set 1 boot on
sudo parted ${SD_DEVICE} --script mkpart primary ext4 513MiB 100%
sleep 2

sudo mkfs.vfat -F 32 -n BOOT ${SD_DEVICE}1
sudo mkfs.ext4 -L rootfs ${SD_DEVICE}2
```

## Deploy Everything
```bash
# CM5 on CM5 IO Board
./deploy.sh --build --alpine --deploy ${SD_DEVICE} --carrier cm5io

# CM5 on CM4 IO Board
./deploy.sh --build --alpine --deploy ${SD_DEVICE} --carrier cm4io

# CM5 Lite variants
./deploy.sh --build --alpine --deploy ${SD_DEVICE} --carrier cm5lio
./deploy.sh --build --alpine --deploy ${SD_DEVICE} --carrier cm4lio
```

## Boot
1. Insert SD card into RPI
2. Power on
3. Login: `root` / `alpine`
