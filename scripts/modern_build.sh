#!/bin/bash
set -e

# These come from the Makefile
VERSION=$1
HOSTNAME=$2
OUTPUT_IMG="dist/pwnagotchi-${VERSION}-64bit.img"
TARBALL="dist/pwnagotchi-${VERSION}.tar.gz"

echo "--- Preparing 64-bit Environment ---"
apt-get update && apt-get install -y file wget xz-utils parted kpartx qemu-user-static curl python3-full

# 1. Download base image if it doesn't exist
if [ ! -f "dist/base_64.img" ]; then
    echo "Downloading and extracting base image..."
    curl -L https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-04-14/2026-04-13-raspios-trixie-arm64-lite.img.xz -o base.img.xz
    xz -df base.img.xz
    mv base.img dist/base_64.img
fi

echo "Creating build image: $OUTPUT_IMG"
cp dist/base_64.img "$OUTPUT_IMG"

# --- EXPANSION PHASE ---
echo "Expanding image size"
# Add 7GB to the image file
dd if=/dev/zero bs=1M count=7168 >> "$OUTPUT_IMG"

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

# 2.1: Bind mount system directories so DKMS can work
echo "Mounting system partitions for DKMS..."
for dir in /dev /dev/pts /proc /sys /run; do
    mount --bind $dir /mnt$dir
done

# 3. Inject and Install Pwnagotchi
echo "Injecting source: $TARBALL"
cp "$TARBALL" /mnt/tmp/
cp /usr/bin/qemu-aarch64-static /mnt/usr/bin/

# Enable SSH on boot
touch /mnt/boot/ssh

# Enable USB Ethernet Gadget mode in cmdline.txt
sed -i 's/$/ modules-load=dwc2,g_ether/' /mnt/boot/cmdline.txt

# Chroot to run commands INSIDE the Raspberry Pi image
echo "Starting internal installation (this will take a while)..."
chroot /mnt /bin/bash <<EOF
set -e  # This forces the internal script to stop on any error

apt-get update
apt-get install -y --no-install-recommends \
    dkms python3 python3-pip python3-full python3-dev \
    build-essential pkg-config cmake unzip \
    libopenblas-dev python3-smbus \
    libgpiod-dev python3-pil \
    libxslt1-dev libopenjp2-7 \
    libxml2-dev libtiff6 \
    zlib1g-dev aircrack-ng \
    linux-headers-rpi-v8 dphys-swapfile \
    libdbus-1-dev \
    libglib2.0-dev \
    golang-go \
    git \
    libpcap-dev \
    libusb-1.0-0-dev \
    libnetfilter-queue-dev \
    fonts-dejavu \
    fonts-freefont-ttf

echo "--- Installing Pwngrid (64-bit) ---"
# 1. Download the correct aarch64 zip
curl -L https://github.com/evilsocket/pwngrid/releases/download/v1.10.3/pwngrid_linux_aarch64_v1.10.3.zip -o /tmp/pwngrid.zip
# 2. Extract it directly to /usr/bin
unzip -o /tmp/pwngrid.zip -d /usr/bin/
# 3. Ensure it has execution permissions
chmod +x /usr/bin/pwngrid
# 4. Clean up the temp file
rm /tmp/pwngrid.zip

# 1. Compile Bettercap from Source (v2.32.0 is more compatible with older Go)
echo "Compiling Bettercap v2.32.0 from source..."
export GOPATH=/tmp/go
git clone --branch v2.32.0 https://github.com/bettercap/bettercap.git /tmp/bettercap
cd /tmp/bettercap
# 2. Build the binary
make build
# Install to /usr/bin so bettercap-launcher finds it
install -m 755 bettercap /usr/bin/bettercap
# 3. Cleanup build artifacts
cd /
rm -rf /tmp/bettercap /tmp/go

echo "--- Installing Bettercap Caplets and Web UI ---"
# Download Caplets
mkdir -p /usr/local/share/bettercap/caplets
git clone https://github.com/bettercap/caplets.git /tmp/caplets
cp -r /tmp/caplets/* /usr/local/share/bettercap/caplets/
rm -rf /tmp/caplets

# Download Web UI
mkdir -p /usr/local/share/bettercap/ui
curl -L https://github.com/bettercap/ui/releases/download/v1.3.0/ui.zip -o /tmp/ui.zip
unzip -o /tmp/ui.zip -d /usr/local/share/bettercap/ui
rm /tmp/ui.zip

echo "--- Installing Nexmon ---"
curl -LfH "User-Agent: Mozilla/5.0" https://http.kali.org/kali/pool/non-free-firmware/f/firmware-nexmon/firmware-nexmon_0.2_all.deb -o /tmp/firmware-nexmon.deb
curl -LfH "User-Agent: Mozilla/5.0" https://http.kali.org/kali/pool/contrib/b/brcmfmac-nexmon-dkms/brcmfmac-nexmon-dkms_6.12.2_all.deb -o /tmp/nexmon-dkms.deb

# 1. Safety check: make sure we didn't just download an HTML redirect page
if ! file /tmp/firmware-nexmon.deb | grep -q "Debian binary package"; then
    echo "ERROR: Download failed. The file is not a valid .deb archive."
    exit 1
fi
# 2. Purge the old stock firmware
apt-get purge -y firmware-brcm80211
# 3. Install the custom drivers
dpkg -i /tmp/firmware-nexmon.deb /tmp/nexmon-dkms.deb || apt-get install -f -y || true
# 4. Clean up the installers
rm /tmp/firmware-nexmon.deb /tmp/nexmon-dkms.deb

echo "Creating passwordless user 'pi'..."
if ! id "pi" &>/dev/null; then
    useradd -m -G sudo,video,input -s /bin/bash pi
fi

passwd -d pi
passwd -d root

echo "pi ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/010_pi-nopasswd

sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

echo "Installing Aluminum-Ice fork..."
# Downgrade pip so it ignores the broken 'gym' metadata syntax
python3 -m pip install "pip<24.1" --break-system-packages --ignore-installed
python3 -m pip install /tmp/pwnagotchi-${VERSION}.tar.gz --break-system-packages


# --- NEW SCRIPT INJECTION BLOCK ---
echo "Injecting official Pwnlib and Monitor scripts..."
# 1. Create the target folder inside the chroot
mkdir -p /tmp/pwn_source
# 2. Extract the tarball into that folder
tar -xzf /tmp/pwnagotchi-${VERSION}.tar.gz -C /tmp/pwn_source --strip-components=1
# 3. Copy the official scripts to their final homes
cp /tmp/pwn_source/builder/data/usr/bin/monstart /usr/bin/monstart
cp /tmp/pwn_source/builder/data/usr/bin/monstop /usr/bin/monstop
cp /tmp/pwn_source/builder/data/usr/bin/pwnlib /usr/bin/pwnlib
# 4. Clean up and set permissions
chmod +x /usr/bin/monstart /usr/bin/monstop /usr/bin/pwnlib
rm -rf /tmp/pwn_source
# --- END OF NEW BLOCK ---

# Create the directory for custom plugins
mkdir -p /usr/local/share/pwnagotchi/custom-plugins/
# ------------------------------

# --- fix to get werkzeug working ---
echo "Force-installing compatible Flask/Werkzeug for Web UI..."
python3 -m pip install Werkzeug==2.0.3 Flask==2.0.3 Jinja2==3.0.3 \
    --break-system-packages \
    --ignore-installed \
    --force-reinstall \
    --no-deps || true
# ------------------------

echo "Setting hostname to $HOSTNAME..."
echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

echo "Configuring MOTD (Message of the Day)..."
cat <<INNEREOF > /etc/motd
(◕‿‿◕) $HOSTNAME

Hi! I'm a pwnagotchi, please take good care of me!
Here are some basic things you need to know to raise me properly!

If you want to change my configuration, use /etc/pwnagotchi/config.toml

All the configuration options can be found on /etc/pwnagotchi/default.toml,
but don't change this file because I will recreate it every time I'm restarted!

I'm managed by systemd. Here are some basic commands.

If you want to know what I'm doing, you can check my logs with the command
tail -f /var/log/pwnagotchi.log

If you want to know if I'm running, you can use
systemctl status pwnagotchi

You can restart me using
systemctl restart pwnagotchi

But be aware I will go into MANUAL mode when restarted!
You can put me back into AUTO mode using
touch /root/.pwnagotchi-auto && systemctl restart pwnagotchi

You learn more about me at https://pwnagotchi.ai/
INNEREOF

# Increase swap size to 512MB for AI stability
echo "Adjusting swap size..."
sed -i 's/^CONF_SWAPSIZE=.*$/CONF_SWAPSIZE=512/' /etc/dphys-swapfile

# --- SERVICE ENABLING --
echo "Enabling core services..."

systemctl enable dphys-swapfile.service
systemctl enable bettercap.service
systemctl enable pwnagotchi.service
systemctl enable pwngrid-peer.service
systemctl enable fstrim.timer

systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer
systemctl disable wpa_supplicant.service

# Remove SSH host keys so they regenerate on first boot
rm -f /etc/ssh/ssh_host*_key*

EOF
###---- end chroot -----

# NEW: Unmount system partitions after chroot finishes
echo "Unmounting system partitions..."
for dir in /run /sys /proc /dev/pts /dev; do
    umount -l /mnt$dir
done

# Hardware Overlays and System Config
echo "dtoverlay=dwc2" >> /mnt/boot/config.txt
echo "dtoverlay=spi1-3cs" >> /mnt/boot/config.txt
echo "dtoverlay=pwm-2chan,pin=12,func=4,pin2=13,func2=4" >> /mnt/boot/config.txt
echo "dtparam=spi=on" >> /mnt/boot/config.txt
echo "dtparam=i2c_arm=on" >> /mnt/boot/config.txt
echo "gpu_mem=16" >> /mnt/boot/config.txt
echo -e "\ni2c-dev" >> /mnt/etc/modules

# 4. Cleanup
echo "Unmounting and cleaning up..."
umount /mnt/boot
umount /mnt
losetup -d "$loop_dev"

echo "--- SUCCESS: 64-bit Pwnagotchi Image Created ---"
