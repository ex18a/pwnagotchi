#!/bin/bash
set -e

# ==============================================================================
# PHASE 1: INITIAL ENVIRONMENT SETUP & VARIABLE DECLARATION
# ==============================================================================
VERSION=$1
HOSTNAME=$2
OUTPUT_IMG="dist/pwnagotchi-${VERSION}-32bit.img"
TARBALL="dist/pwnagotchi-${VERSION}.tar.gz"

echo "========================================================================"
echo " [+] STARTING 32-BIT UNIVERSAL PWNAGOTCHI BUILD PIPELINE "
echo "========================================================================"

# Basic validation
if [ -z "$VERSION" ] || [ -z "$HOSTNAME" ]; then
    echo " [!] ERROR: Missing arguments. Usage: $0 <version> <hostname>"
    exit 1
fi

echo " [*] Step 1: Installing Host Build Toolchain dependencies..."
apt-get update && apt-get install -y file wget xz-utils parted kpartx qemu-user-static curl python3-full unzip

# ==============================================================================
# PHASE 2: BASE IMAGE PROVISIONING & STORAGE EXPANSION
# ==============================================================================
mkdir -p dist

if [ ! -f "dist/base_32.img" ]; then
    echo " [*] Step 2: Base image not found. Fetching Raspberry Pi OS Lite (Buster)..."
    curl -L -H "User-Agent: Mozilla/5.0" \
        "https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip" \
        -o base.zip

    FILESIZE=$(stat -c%s "base.zip")
    if [ "$FILESIZE" -lt 1000000 ]; then
        echo " [!] ERROR: Downloaded file is corrupted or too small ($FILESIZE bytes)."
        exit 1
    fi

    echo " [*] Extracting clean base image partition layout..."
    unzip -p base.zip > dist/base_32.img
    rm base.zip
fi

echo " [*] Step 3: Generating fresh workspace image: $OUTPUT_IMG"
cp dist/base_32.img "$OUTPUT_IMG"

echo " [*] Step 4: Expanding filesystem bounds (+12GB payload room)..."
dd if=/dev/zero bs=1M count=12288 >> "$OUTPUT_IMG"
parted "$OUTPUT_IMG" resizepart 2 100%

echo " [*] Step 5: Mounting loopback blocks and checking system integrity..."
loop_dev=$(losetup -fP --show "$OUTPUT_IMG")
sleep 2

e2fsck -f "${loop_dev}p2" || true
resize2fs "${loop_dev}p2"

echo " [*] Mounting root and boot workspaces onto host system tree..."
mount "${loop_dev}p2" /mnt
mount "${loop_dev}p1" /mnt/boot

echo " [*] Establishing active virtual mapping layout for DKMS subsystems..."
for dir in /dev /dev/pts /proc /sys /run; do
    mount --bind $dir /mnt$dir
done

# ==============================================================================
# PHASE 3: HOST-SIDE PRE-CHROOT ASSET INJECTION
# ==============================================================================
echo " [*] Step 6: Injecting raw tarball runtime packages and QEMU emulator binary..."
cp "$TARBALL" /mnt/tmp/
cp /usr/bin/qemu-arm-static /mnt/usr/bin/

echo " [*] Step 7: Profiling and stage-routing Nexmon driver assets..."
# Hardcoded to match the Makefile working directory mapping
cp -r builder/assets/nexmon /mnt/tmp/nexmon

echo " [*] Step 8: Fetching matching uncorrupted legacy kernel archives onto host workspace..."
wget -q -O /mnt/tmp/raspberrypi-kernel.deb "http://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-firmware/raspberrypi-kernel_1.20210527-1_armhf.deb"
wget -q -O /mnt/tmp/raspberrypi-kernel-headers.deb "http://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-firmware/raspberrypi-kernel-headers_1.20210527-1_armhf.deb"

# Append serial module interface components for USB Gadget Mode
touch /mnt/boot/ssh
sed -i 's/$/ modules-load=dwc2,g_ether/' /mnt/boot/cmdline.txt
# Enable SPI and I2C hardware buses for the Waveshare screen
echo "dtparam=spi=on" >> /mnt/boot/config.txt
echo "dtparam=i2c_arm=on" >> /mnt/boot/config.txt

# ==============================================================================
# PHASE 4: INTERNAL ISOLATED CHROOT EMULATION CONFIGURATION
# ==============================================================================
echo "------------------------------------------------------------------------"
echo " [+] DIVING INTO QEMU EMULATED ENVIRONMENT - RUNNING INTERNAL BUILD"
echo "------------------------------------------------------------------------"

chroot /mnt /bin/bash <<EOF
set -e

echo "  -> [Chroot] Adjusting system sources to stable Raspbian Legacy Archive mirrors..."
# Fetch the Raspberry Pi key
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E || true
# Fetch the Raspbian archive key
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9165938D90FDDD2E || true

cat <<REPO_EOF > /etc/apt/sources.list
# [trusted=yes] prevents apt from fatally crashing, legacy.raspbian is REQUIRED for Pi packages
deb [trusted=yes] http://legacy.raspbian.org/raspbian/ buster main contrib non-free rpi
REPO_EOF

cat <<REPO_EOF > /etc/apt/sources.list.d/raspi.list
deb [trusted=yes] http://archive.raspberrypi.org/debian/ buster main
REPO_EOF

# Synchronize package arrays bypassing expired repository checks
apt-get update -o Acquire::Check-Valid-Until=false || true
apt-get update --allow-unauthenticated -y

echo "  -> [Chroot] Installing matching kernel targets and establishing package locks..."
dpkg -i /tmp/raspberrypi-kernel.deb /tmp/raspberrypi-kernel-headers.deb
apt-mark hold raspberrypi-kernel raspberrypi-kernel-headers

echo "  -> [Chroot] Fetching mandatory system core packages and library builds..."
apt-get install -y --allow-unauthenticated --no-install-recommends \
    dkms python3 python3-pip python3-dev \
    build-essential pkg-config cmake unzip \
    libatlas-base-dev libgpiod-dev libxslt1-dev \
    libxml2-dev zlib1g-dev \
    libdbus-1-dev libglib2.0-dev \
    golang-go git \
    libpcap-dev libusb-1.0-0-dev libnetfilter-queue-dev \
    fonts-dejavu fonts-freefont-ttf \
    libavcodec58 libavformat58 libswscale5 \
    libv4l-0 libxvidcore4 libx264-155 \
    libgtk-3-0 libatlas3-base

echo "  -> [Chroot] Purging redundant network and telemetry packages..."
apt-get purge -y raspberrypi-net-mods dhcpcd5 triggerhappy nfs-common

echo "  -> [Chroot] Fetching and deploying armhf Pwngrid binaries..."
curl -L https://github.com/evilsocket/pwngrid/releases/download/v1.10.3/pwngrid_linux_armhf_v1.10.3.zip -o /tmp/pwngrid.zip
unzip -o /tmp/pwngrid.zip -d /usr/bin/
chmod +x /usr/bin/pwngrid
rm /tmp/pwngrid.zip

echo "  -> [Chroot] Injecting Go 1.15.15 framework environment tools..."
curl -L https://golang.org/dl/go1.15.15.linux-armv6l.tar.gz -o /tmp/go.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz

export GOROOT=/usr/local/go
export GOPATH=/tmp/go_path
export PATH=/usr/local/go/bin:\$PATH

echo "  -> [Chroot] Compiling Bettercap core execution modules..."
git clone --branch v2.32.0 https://github.com/bettercap/bettercap.git /tmp/bettercap
cd /tmp/bettercap
go build -o bettercap main.go
install -m 755 bettercap /usr/bin/bettercap

cd /
rm -rf /tmp/bettercap /tmp/go_path /usr/local/go

echo "  -> [Chroot] Provisioning Bettercap Caplets and deployment components..."
mkdir -p /usr/local/share/bettercap/caplets
git clone https://github.com/bettercap/caplets.git /tmp/caplets
cp -r /tmp/caplets/* /usr/local/share/bettercap/caplets/
rm -rf /tmp/caplets

echo "  -> [Chroot] Stitching Bettercap Responsive Web Layout interface panels..."
mkdir -p /usr/local/share/bettercap/ui
curl -fL https://github.com/bettercap/ui/releases/download/v1.3.0/ui.zip -o /tmp/ui.zip
unzip -o /tmp/ui.zip -d /tmp/ui_temp
cp -r /tmp/ui_temp/ui/* /usr/local/share/bettercap/ui/
rm -rf /tmp/ui.zip /tmp/ui_temp
chown -R root:root /usr/local/share/bettercap/ui

echo "  -> [Chroot] Satisfying and building core hcxtools elements..."
apt-get install -y --allow-unauthenticated --no-install-recommends libcurl4-openssl-dev libssl-dev
cd /tmp
curl -L "https://github.com/ZerBea/hcxtools/archive/refs/tags/6.2.7.tar.gz" -o 6.2.7.tar.gz
tar -xvf 6.2.7.tar.gz
cd hcxtools-6.2.7
make
mv hcxpcapngtool /usr/bin/hcxpcapngtool
chmod +x /usr/bin/hcxpcapngtool

cd /
rm -rf /tmp/hcxtools-6.2.7 /tmp/6.2.7.tar.gz
apt-get purge -y libcurl4-openssl-dev libssl-dev
apt-get autoremove -y

echo "  -> [Chroot] Hardening local user definitions and authentication profiles..."
if ! id "pi" &>/dev/null; then
    useradd -m -G sudo,video,input -s /bin/bash pi
fi
passwd -d pi
passwd -d root
echo "pi ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/010_pi-nopasswd
sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

echo "  -> [Chroot] Unpacking application core and dependencies arrays..."
mkdir -p /tmp/pwn_source
tar -xzf /tmp/pwnagotchi-${VERSION}.tar.gz -C /tmp/pwn_source --strip-components=1

# Reset and scale setup utilities
rm -rf /root/.cache/pip
python3 -m pip install "pip<23.1" setuptools wheel
python3 -m pip install "markupsafe==2.0.1" "itsdangerous==2.0.1" "jinja2==3.0.3" "werkzeug==2.0.3" "markdown==3.3.7"
python3 -m pip install --only-binary=:all: --force-reinstall "numpy==1.21.4"

# QEMU network mitigation handling
sed -i 's/https:/http:/g' /tmp/pwn_source/requirements.txt

python3 -m pip install --ignore-installed \
    --only-binary=:all: \
    --prefer-binary \
    --default-timeout=1000 \
    --retries=10 \
    --trusted-host www.piwheels.org \
    -r /tmp/pwn_source/requirements.txt

python3 -m pip install --no-deps /tmp/pwnagotchi-${VERSION}.tar.gz
mkdir -p /usr/local/share/pwnagotchi/custom-plugins/

echo "alias pwnlog='tail -f -n300 /var/log/pwn*.log | sed --unbuffered \"s/,[[:digit:]]\\\\{3\\\\}\\\\]//g\" | cut -d \" \" -f 2-'" >> /home/pi/.bashrc
chown pi:pi /home/pi/.bashrc

echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

sed -i 's/^CONF_SWAPSIZE=.*$/CONF_SWAPSIZE=512/' /etc/dphys-swapfile
sed -i 's|^ExecStart=/usr/lib/bluetooth/bluetoothd$|ExecStart=/usr/lib/bluetooth/bluetoothd --noplugin=sap|' /lib/systemd/system/bluetooth.service

echo "  -> [Chroot] Deploying Universal dual-architecture Nexmon drivers..."
# Raspberry Pi 3B Drivers Configuration
cp /tmp/nexmon/pi3b/brcmfmac43430-sdio.bin /lib/firmware/brcm/brcmfmac43430-sdio.bin
cp /tmp/nexmon/pi3b/brcmfmac43430-sdio.txt /lib/firmware/brcm/brcmfmac43430-sdio.txt
ln -sf brcmfmac43430-sdio.bin /lib/firmware/brcm/brcmfmac43430-sdio.raspberrypi,3-model-b.bin
ln -sf brcmfmac43430-sdio.txt /lib/firmware/brcm/brcmfmac43430-sdio.raspberrypi,3-model-b.txt

mkdir -p /lib/firmware/cypress
cp /tmp/nexmon/pi3b/cyfmac43430-sdio.bin /lib/firmware/cypress/cyfmac43430-sdio.bin
cp /tmp/nexmon/pi3b/cyfmac43430-sdio.clm_blob /lib/firmware/cypress/cyfmac43430-sdio.clm_blob
ln -sf ../cypress/cyfmac43430-sdio.bin /lib/firmware/brcm/cyfmac43430-sdio.bin

mkdir -p /lib/modules/5.10.17-v7+/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/
cp /tmp/nexmon/pi3b/brcmfmac_3b.ko /lib/modules/5.10.17-v7+/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko

# Raspberry Pi Zero 2 W Drivers Configuration
cp /tmp/nexmon/zero2w/brcmfmac43436-sdio.bin /lib/firmware/brcm/brcmfmac43436-sdio.bin
cp /tmp/nexmon/zero2w/brcmfmac43436-sdio.clm_blob /lib/firmware/brcm/brcmfmac43436-sdio.clm_blob
cp /tmp/nexmon/zero2w/brcmfmac43436-sdio.txt /lib/firmware/brcm/brcmfmac43436-sdio.txt
ln -sf brcmfmac43436-sdio.bin /lib/firmware/brcm/brcmfmac43436-sdio.raspberrypi,model-zero-2-w.bin
ln -sf brcmfmac43436-sdio.clm_blob /lib/firmware/brcm/brcmfmac43436-sdio.raspberrypi,model-zero-2-w.clm_blob
ln -sf brcmfmac43436-sdio.txt /lib/firmware/brcm/brcmfmac43436-sdio.raspberrypi,model-zero-2-w.txt

cp /tmp/nexmon/zero2w/brcmfmac43436s-sdio.bin /lib/firmware/brcm/brcmfmac43436s-sdio.bin
cp /tmp/nexmon/zero2w/brcmfmac43436s-sdio.txt /lib/firmware/brcm/brcmfmac43436s-sdio.txt
ln -sf brcmfmac43436s-sdio.bin /lib/firmware/brcm/brcmfmac43436s-sdio.raspberrypi,model-zero-2-w.bin
ln -sf brcmfmac43436s-sdio.txt /lib/firmware/brcm/brcmfmac43436s-sdio.raspberrypi,model-zero-2-w.txt

mkdir -p /lib/modules/5.10.41+/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/
cp /tmp/nexmon/zero2w/brcmfmac_z2w.ko /lib/modules/5.10.41+/kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko

cp /tmp/nexmon/nexutil /usr/bin/nexutil
chmod +x /usr/bin/nexutil

depmod -a 5.10.17-v7+ || true
depmod -a 5.10.41+ || true

echo "  -> [Chroot] Registering network unit configurations..."
systemctl enable dphys-swapfile.service
systemctl enable bettercap.service
systemctl enable pwnagotchi.service
systemctl enable pwngrid-peer.service
systemctl enable fstrim.timer
systemctl disable apt-daily.timer apt-daily.service apt-daily-upgrade.timer wpa_supplicant.service dnsmasq.service
rm -f /etc/ssh/ssh_host*_key*

cat <<MOTD_EOF > /etc/motd
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
MOTD_EOF
sed -i 's/#PrintMotd yes/PrintMotd yes/' /etc/ssh/sshd_config
sed -i 's/PrintMotd no/PrintMotd yes/' /etc/ssh/sshd_config

echo "  -> [Chroot] Installing Hardware Auto-Gadget for zero2w..."
cat <<'GADGET_EOF' > /usr/local/bin/hw-gadget.sh
#!/bin/bash

# Check the actual hardware name burned into the device tree
if grep -q "Zero 2" /sys/firmware/devicetree/base/model; then
    # It's a Zero 2 W! Add the overlay if it is missing.
    if ! grep -q "^dtoverlay=dwc2" /boot/config.txt; then
        echo "dtoverlay=dwc2" >> /boot/config.txt
        reboot
    fi
else
    # It is a Pi 3B (or anything else). Safely strip the overlay.
    if grep -q "^dtoverlay=dwc2" /boot/config.txt; then
        sed -i '/^dtoverlay=dwc2/d' /boot/config.txt
        reboot
    fi
fi
GADGET_EOF

chmod +x /usr/local/bin/hw-gadget.sh

# Tell the system to run the auto-gadget every time the OS boots
sed -i 's|^exit 0|/usr/local/bin/hw-gadget.sh\nexit 0|' /etc/rc.local

# ==============================================================================
# AGGRESSIVE INTERNAL CLEANUP (REDUCES IMAGE CAPACITY FOOTPRINT)
# ==============================================================================
echo "  -> [Chroot] Starting storage scrubbing cycle (removing junk)..."
rm -rf /tmp/* /root/.cache /var/cache/apt/archives/*
apt-get clean
rm -rf /var/lib/apt/lists/*

EOF

echo "------------------------------------------------------------------------"
echo " [+] EXITED EMULATED ENVIRONMENT - SAFELY DECOUPLING FILESYSTEMS"
echo "------------------------------------------------------------------------"

echo " [*] Step 9: Detaching system interface loops cleanly..."
for dir in /run /sys /proc /dev/pts /dev; do
    umount -l /mnt$dir
done

# Ensure hardware layouts read the i2c interface but keep standard broadcom overlays enabled
echo "i2c-dev" >> /mnt/etc/modules

echo " [*] Step 10: Finalizing image bounds and unlocking workspace devices..."
umount /mnt/boot
umount /mnt
losetup -d "$loop_dev"

echo "========================================================================"
echo " [+] SUCCESS: DUAL-ARCH HYBRID PWNAGOTCHI TARGET DEPLOYED COMPLETED "
echo "========================================================================"
