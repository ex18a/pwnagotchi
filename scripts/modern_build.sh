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

# Use chroot to run commands INSIDE the Raspberry Pi image
echo "Starting internal installation (this will take a while)..."
chroot /mnt /bin/bash <<EOF
set -e  # This forces the internal script to stop on any error

apt-get update
apt-get install -y --no-install-recommends \
    dkms python3 python3-pip python3-full python3-dev \
    build-essential pkg-config cmake \
    libatlas-base-dev libgpiod-dev libxslt-dev \
    libxml2-dev zlib1g-dev raspberrypi-kernel-headers \
    libdbus-1-dev libglib2.0-dev \
    golang-go git \
    libpcap-dev libusb-1.0-0-dev libnetfilter-queue-dev \
    fonts-dejavu fonts-freefont-ttf

# 2. Compile Bettercap from Source (v2.32.0 is more compatible with older Go)
echo "Compiling Bettercap v2.32.0 from source..."
export GOPATH=/tmp/go
git clone --branch v2.32.0 https://github.com/bettercap/bettercap.git /tmp/bettercap
cd /tmp/bettercap

# 3. Build the binary
make build
# Install to /usr/bin so bettercap-launcher finds it
install -m 755 bettercap /usr/bin/bettercap

# 4. Cleanup build artifacts
cd /
rm -rf /tmp/bettercap /tmp/go

echo "--- Installing Nexmon ---"
curl -LfH "User-Agent: Mozilla/5.0" https://http.kali.org/kali/pool/non-free-firmware/f/firmware-nexmon/firmware-nexmon_0.2_all.deb -o /tmp/firmware-nexmon.deb
curl -LfH "User-Agent: Mozilla/5.0" https://http.kali.org/kali/pool/contrib/b/brcmfmac-nexmon-dkms/brcmfmac-nexmon-dkms_6.12.2_all.deb -o /tmp/nexmon-dkms.deb

# 2. Safety check: make sure we didn't just download an HTML redirect page
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

echo "Creating Monitor Mode Helper Scripts..."

# Create the mon0 start script
cat <<INNEREOF > /usr/bin/monstart
#!/bin/bash
# 1. Ensure the radio isn't soft-blocked
rfkill unblock wifi

# 2. Ensure wlan0 is up so iw can see it
ip link set wlan0 up

# 3. Check if mon0 already exists, if not, create it
if ! ip link show mon0 > /dev/null 2>&1; then
    iw dev wlan0 interface add mon0 type monitor
fi

# 4. Bring the monitor interface up
ip link set mon0 up
echo "Monitor interface mon0 started."
INNEREOF

# Create the mon0 stop script
cat <<INNEREOF > /usr/bin/monstop
#!/bin/bash
if ip link show mon0 > /dev/null 2>&1; then
    ip link set mon0 down
    iw dev mon0 del
fi
echo "Monitor interface mon0 stopped."
INNEREOF

# Make them both executable
chmod +x /usr/bin/monstart /usr/bin/monstop

# Force the Pwnagotchi to use the new mon0 interface
mkdir -p /etc/pwnagotchi
cat <<INNEREOF > /etc/pwnagotchi/config.toml
main.name = "$HOSTNAME"
main.lang = "en"
main.whitelist = []
main.plugins.grid.enabled = true
main.iface = "mon0"
ui.display.enabled = true
ui.display.type = "waveshare_4"
INNEREOF

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
python3 -m pip install /tmp/pwnagotchi-${VERSION}.tar.gz --break-system-packages

# --- fix to get werkzeug working ---
echo "Pinning Flask/Werkzeug to working versions for Python 3.11..."
python3 -m pip install Werkzeug==2.0.3 Flask==2.0.3 Jinja2==3.0.3 --break-system-packages
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
EOF

###---- end chroot -----

# NEW: Unmount system partitions after chroot finishes
echo "Unmounting system partitions..."
for dir in /run /sys /proc /dev/pts /dev; do
    umount -l /mnt$dir
done

# Enable hardware overlay for Gadget Mode
echo "dtoverlay=dwc2" >> /mnt/boot/config.txt

# 4. Cleanup
echo "Unmounting and cleaning up..."
umount /mnt/boot
umount /mnt
losetup -d "$loop_dev"

echo "--- SUCCESS: 64-bit Pwnagotchi Image Created ---"
