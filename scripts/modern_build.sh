#!/bin/bash
set -e

# These come from the Makefile
VERSION=$1
HOSTNAME=$2
OUTPUT_IMG="dist/pwnagotchi-${VERSION}-64bit.img"
TARBALL="dist/pwnagotchi-${VERSION}.tar.gz"

echo "--- Preparing 64-bit Environment ---"
apt-get update && apt-get install -y wget xz-utils parted kpartx qemu-user-static curl python3-full

# 1. Download base image if it doesn't exist
if [ ! -f "dist/base_64.img" ]; then
    echo "Downloading base 64-bit image..."
    curl -L https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2023-12-06/2023-12-05-raspios-bookworm-arm64-lite.img.xz -o base.img.xz
    xz -d base.img.xz
    mv base.img dist/base_64.img
fi

echo "Creating build image: $OUTPUT_IMG"
cp dist/base_64.img "$OUTPUT_IMG"

# --- EXPANSION PHASE ---
echo "Expanding image size to accommodate Aluminum-Ice..."
# Add 4GB to the image file
dd if=/dev/zero bs=1M count=4096 >> "$OUTPUT_IMG"

# Fix the partition table and grow the root partition (partition 2)
parted "$OUTPUT_IMG" resizepart 2 100%

# Setup loop device to fix the filesystem
loop_dev=$(losetup -fP --show "$OUTPUT_IMG")
sleep 2

# Force a filesystem check and then resize the actual filesystem
e2fsck -f "${loop_dev}p2" || true
resize2fs "${loop_dev}p2"
# -----------------------

# 2. Mount the image
echo "Mounting image..."
mount "${loop_dev}p2" /mnt
mount "${loop_dev}p1" /mnt/boot

# 3. Inject and Install Pwnagotchi
echo "Injecting source: $TARBALL"
cp "$TARBALL" /mnt/tmp/
cp /usr/bin/qemu-aarch64-static /mnt/usr/bin/

# Use chroot to run commands INSIDE the Raspberry Pi image
echo "Starting internal installation (this will take a while)..."
chroot /mnt /bin/bash <<EOF
apt-get update
apt-get install -y --no-install-recommends \
    python3 python3-pip python3-full python3-dev \
    build-essential pkg-config cmake \
    libatlas-base-dev libgpiod-dev libxslt-dev \
    libxml2-dev zlib1g-dev \
    libdbus-1-dev libglib2.0-dev

echo "Installing Aluminum-Ice fork..."
python3 -m pip install /tmp/pwnagotchi-${VERSION}.tar.gz --break-system-packages

echo "Setting hostname to $HOSTNAME..."
echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
EOF

# 4. Cleanup
echo "Unmounting and cleaning up..."
umount /mnt/boot
umount /mnt
losetup -d "$loop_dev"

echo "--- SUCCESS: 64-bit Aluminum-Ice Image Created ---"
