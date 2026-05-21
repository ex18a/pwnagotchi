#!/bin/bash
set -e

# These come from the Makefile
VERSION=$1
HOSTNAME=$2
OUTPUT_IMG="dist/pwnagotchi-${VERSION}-32bit.img"
# FIXED: Pointing to the dist folder where the Makefile puts the tarball
TARBALL="dist/pwnagotchi-${VERSION}.tar.gz"

echo "--- Preparing 32-bit Environment ---"
apt-get update && apt-get install -y file wget xz-utils parted kpartx qemu-user-static curl python3-full unzip

echo "Downloading Raspberry Pi OS Lite image..."
if [ ! -f "dist/base_32.img" ]; then
    echo "Downloading Raspberry Pi OS Lite image..."
    curl -L -H "User-Agent: Mozilla/5.0" \
        "https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip" \
        -o base.zip

    FILESIZE=$(stat -c%s "base.zip")
    if [ "$FILESIZE" -lt 1000000 ]; then
        echo "ERROR: Downloaded file is too small ($FILESIZE bytes)."
        exit 1
    fi

    echo "Extracting image..."
    unzip -p base.zip > dist/base_32.img
    rm base.zip
fi

echo "Creating build image: $OUTPUT_IMG"
cp dist/base_32.img "$OUTPUT_IMG"

echo "Expanding image size"
dd if=/dev/zero bs=1M count=12288 >> "$OUTPUT_IMG"
parted "$OUTPUT_IMG" resizepart 2 100%

loop_dev=$(losetup -fP --show "$OUTPUT_IMG")
sleep 2

e2fsck -f "${loop_dev}p2" || true
resize2fs "${loop_dev}p2"

echo "Mounting image..."
mount "${loop_dev}p2" /mnt
mount "${loop_dev}p1" /mnt/boot

echo "Mounting system partitions for DKMS..."
for dir in /dev /dev/pts /proc /sys /run; do
    mount --bind $dir /mnt$dir
done

echo "Injecting source: $TARBALL"
cp "$TARBALL" /mnt/tmp/
cp /usr/bin/qemu-arm-static /mnt/usr/bin/

touch /mnt/boot/ssh
sed -i 's/$/ modules-load=dwc2,g_ether/' /mnt/boot/cmdline.txt

echo "Starting internal installation..."
chroot /mnt /bin/bash <<EOF
set -e

echo "--- Patching Repositories for Legacy Buster ---"
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E || true

cat <<REPO_EOF > /etc/apt/sources.list
deb [trusted=yes] http://legacy.raspbian.org/raspbian/ buster main contrib non-free rpi
REPO_EOF

cat <<REPO_EOF > /etc/apt/sources.list.d/raspi.list
deb [trusted=yes] http://archive.raspberrypi.org/debian/ buster main
REPO_EOF

apt-get update -o Acquire::Check-Valid-Until=false || true
apt-get update --allow-unauthenticated -y

apt-get install -y --no-install-recommends \
    dkms python3 python3-pip python3-dev \
    build-essential pkg-config cmake unzip \
    libatlas-base-dev libgpiod-dev libxslt1-dev \
    libxml2-dev zlib1g-dev raspberrypi-kernel-headers \
    libdbus-1-dev libglib2.0-dev \
    golang-go git \
    libpcap-dev libusb-1.0-0-dev libnetfilter-queue-dev \
    fonts-dejavu fonts-freefont-ttf \
    libavcodec58 \
    libavformat58 \
    libswscale5 \
    libv4l-0 \
    libxvidcore4 \
    libx264-155 \
    libgtk-3-0 \
    libatlas3-base


#    these make ai work but are huge
#    libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libgtk-3-dev


apt-get purge -y raspberrypi-net-mods dhcpcd5 triggerhappy nfs-common

echo "--- Installing Pwngrid (32-bit armhf) ---"
curl -L https://github.com/evilsocket/pwngrid/releases/download/v1.10.3/pwngrid_linux_armhf_v1.10.3.zip -o /tmp/pwngrid.zip
unzip -o /tmp/pwngrid.zip -d /usr/bin/
chmod +x /usr/bin/pwngrid
rm /tmp/pwngrid.zip

echo "Replacing system Go with 1.15.15..."
curl -L https://golang.org/dl/go1.15.15.linux-armv6l.tar.gz -o /tmp/go.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz

export GOROOT=/usr/local/go
export GOPATH=/tmp/go_path
export PATH=/usr/local/go/bin:\$PATH

echo "Compiling Bettercap v2.32.0..."
git clone --branch v2.32.0 https://github.com/bettercap/bettercap.git /tmp/bettercap
cd /tmp/bettercap
go build -o bettercap main.go
install -m 755 bettercap /usr/bin/bettercap

cd /
rm -rf /tmp/bettercap /tmp/go_path /usr/local/go

echo "--- Installing Bettercap Caplets and Web UI ---"
mkdir -p /usr/local/share/bettercap/caplets
git clone https://github.com/bettercap/caplets.git /tmp/caplets
cp -r /tmp/caplets/* /usr/local/share/bettercap/caplets/
rm -rf /tmp/caplets

# Install Web UI
echo "--- Installing Bettercap Web UI ---"
mkdir -p /usr/local/share/bettercap/ui
curl -fL https://github.com/bettercap/ui/releases/download/v1.3.0/ui.zip -o /tmp/ui.zip

# Unzip and immediately move the contents
unzip -o /tmp/ui.zip -d /tmp/ui_temp

# The v1.3.0 zip contains a folder named 'ui'. 
# Move everything from /tmp/ui_temp/ui/* to the destination.
cp -r /tmp/ui_temp/ui/* /usr/local/share/bettercap/ui/

# Cleanup
rm -rf /tmp/ui.zip /tmp/ui_temp
chown -R root:root /usr/local/share/bettercap/ui

echo "Installing build dependencies for hcxtools..."
apt-get install -y --no-install-recommends libcurl4-openssl-dev libssl-dev

echo "Downloading and compiling hcxtools v6.2.7..."
cd /tmp
curl -L "https://github.com/ZerBea/hcxtools/archive/refs/tags/6.2.7.tar.gz" -o 6.2.7.tar.gz
tar -xvf 6.2.7.tar.gz
cd hcxtools-6.2.7
make

echo "Moving hcxpcapngtool binary..."
mv hcxpcapngtool /usr/bin/hcxpcapngtool
chmod +x /usr/bin/hcxpcapngtool

echo "Cleaning up hcxtools source and dev packages..."
cd /
rm -rf /tmp/hcxtools-6.2.7 /tmp/6.2.7.tar.gz
apt-get purge -y libcurl4-openssl-dev libssl-dev
apt-get autoremove -y

echo "Creating passwordless user 'pi'..."
if ! id "pi" &>/dev/null; then
    useradd -m -G sudo,video,input -s /bin/bash pi
fi
passwd -d pi
passwd -d root
echo "pi ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/010_pi-nopasswd
sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

echo "Unpacking Pwnagotchi source for requirements..."
mkdir -p /tmp/pwn_source
tar -xzf /tmp/pwnagotchi-${VERSION}.tar.gz -C /tmp/pwn_source --strip-components=1

echo "Installing Pwnagotchi dependencies..."
# Clean up any failed build artifacts
rm -rf /root/.cache/pip

# Upgrade core tools
python3 -m pip install "pip<23.1" setuptools wheel
python3 -m pip install "markupsafe==2.0.1" "itsdangerous==2.0.1" "jinja2==3.0.3" "werkzeug==2.0.3" "markdown==3.3.7"

echo "Forcing Legacy NumPy Binary..."
# Changed to 1.21.4 based on your logs of available versions
python3 -m pip install --only-binary=:all: --force-reinstall "numpy==1.21.4"

echo "Installing requirements (Binary-Only Mode)..."
# 1. We force pip to ONLY look for pre-compiled .whl files. 
# 2. We skip any package that requires a compiler (which is what's failing).
python3 -m pip install --ignore-installed \
    --only-binary=:all: \
    --prefer-binary \
    -r /tmp/pwn_source/requirements.txt

python3 -m pip install --no-deps /tmp/pwnagotchi-${VERSION}.tar.gz

rm -rf /tmp/pwn_source
mkdir -p /usr/local/share/pwnagotchi/custom-plugins/

echo "alias pwnlog='tail -f -n300 /var/log/pwn*.log | sed --unbuffered \"s/,[[:digit:]]\\\\{3\\\\}\\\\]//g\" | cut -d \" \" -f 2-'" >> /home/pi/.bashrc
chown pi:pi /home/pi/.bashrc

echo "$HOSTNAME" > /etc/hostname
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

echo "Adjusting swap size..."
sed -i 's/^CONF_SWAPSIZE=.*$/CONF_SWAPSIZE=512/' /etc/dphys-swapfile
sed -i 's|^ExecStart=/usr/lib/bluetooth/bluetoothd$|ExecStart=/usr/lib/bluetooth/bluetoothd --noplugin=sap|' /lib/systemd/system/bluetooth.service

echo "Enabling core services..."
systemctl enable dphys-swapfile.service
systemctl enable bettercap.service
systemctl enable pwnagotchi.service
systemctl enable pwngrid-peer.service
systemctl enable fstrim.timer
systemctl disable apt-daily.timer apt-daily.service apt-daily-upgrade.timer wpa_supplicant.service dnsmasq.service
rm -f /etc/ssh/ssh_host*_key*

echo "Message of the day..."
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

EOF

echo "Unmounting system partitions..."
for dir in /run /sys /proc /dev/pts /dev; do
    umount -l /mnt$dir
done

# Disable onboard wifi
echo "dtoverlay=disable-wifi" >> /mnt/boot/config.txt
# Add the i2c module for the screen
echo "i2c-dev" >> /mnt/etc/modules

echo "Unmounting and cleaning up..."
umount /mnt/boot
umount /mnt
losetup -d "$loop_dev"

echo "--- SUCCESS: 32-bit Pwnagotchi Image Created ---"
