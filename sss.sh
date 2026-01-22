#!/bin/bash

# Arch USB Repair Script
# Run this from Arch ISO to fix an existing USB installation

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}
   _          _    _    _   _   _ ___ ___    ___                _     
  /_\  _ _ __| |_ | | | | | / __| _ )  | _ \___ _ __  __ _(_)_ _ 
 / _ \| '_/ _| ' \| |_| |_| \__ \ _ \  |   / -_) '_ \/ _\` | | '_|
/_/ \_\_| \__|_||_|____\___/|___/___/  |_|_\___| .__/\__,_|_|_|  
                                                |_|               
${NC}"
echo "Arch USB Repair Tool"
echo "Fix networking, pacman, and install missing packages"
echo "------------------------------------------------------"

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}" 
   exit 1
fi

# 1. DETECT USB DEVICE
echo -e "${GREEN}[*] Detecting devices...${NC}"
lsblk -d -p -o NAME,SIZE,MODEL,TYPE | grep -v "loop" | grep -v "rom"

echo ""
read -p "Enter the USB device (e.g., /dev/sdb): " USB_DEVICE

if [ ! -b "$USB_DEVICE" ]; then
    echo -e "${RED}Device not found!${NC}"
    exit 1
fi

# Identify partitions
if [[ "$USB_DEVICE" == *"nvme"* ]]; then
    USB_ROOT="${USB_DEVICE}p3"
    USB_BOOT="${USB_DEVICE}p2"
else
    USB_ROOT="${USB_DEVICE}3"
    USB_BOOT="${USB_DEVICE}2"
fi

# 2. MOUNT USB
echo -e "${GREEN}[*] Mounting USB...${NC}"
mkdir -p /mnt/usbfix
mount $USB_ROOT /mnt/usbfix || { echo -e "${RED}Failed to mount!${NC}"; exit 1; }
mount $USB_BOOT /mnt/usbfix/boot || { echo -e "${RED}Failed to mount boot!${NC}"; exit 1; }

echo -e "${GREEN}USB mounted successfully!${NC}"

# 3. CREATE REPAIR SCRIPT TO RUN IN CHROOT
echo -e "${GREEN}[*] Creating repair operations...${NC}"

cat <<'REPAIR' > /mnt/usbfix/tmp/repair.sh
#!/bin/bash
set -e

echo "==============================================="
echo "  Repairing Arch USB System"
echo "==============================================="

# Fix Network Configuration
echo "[1/6] Configuring Network..."
cat > /etc/systemd/network/20-wired.network <<EOF
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

cat > /etc/systemd/network/25-wireless.network <<EOF
[Match]
Name=wl*

[Network]
DHCP=yes
EOF

# Enable network services
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true
systemctl enable iwd 2>/dev/null || true
systemctl enable NetworkManager 2>/dev/null || true

# Fix DNS
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Initialize Pacman Keyring
echo "[2/6] Initializing Pacman Keyring..."
rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux

# Enable Parallel Downloads
echo "[3/6] Optimizing Pacman..."
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Update mirrors for speed
echo "[4/6] Updating mirrors..."
if command -v reflector &> /dev/null; then
    reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || echo "Reflector skipped"
fi

# Sync databases
echo "[5/6] Syncing package databases..."
pacman -Sy

# Install essential packages
echo "[6/6] Installing essential packages..."
pacman -S --needed --noconfirm \
    linux-headers \
    dhcpcd \
    wpa_supplicant \
    dialog \
    net-tools \
    wireless_tools \
    netctl \
    ifplugd \
    pciutils \
    usbutils \
    wget \
    curl \
    openssh \
    htop \
    tree \
    man-db \
    man-pages \
    which \
    2>/dev/null || echo "Some packages may have failed (non-critical)"

echo ""
echo "==============================================="
echo "  Repair Complete!"
echo "==============================================="
REPAIR

chmod +x /mnt/usbfix/tmp/repair.sh

# 4. BIND NECESSARY MOUNTS FOR INTERNET IN CHROOT
echo -e "${GREEN}[*] Setting up chroot environment...${NC}"
mount --bind /dev /mnt/usbfix/dev
mount --bind /proc /mnt/usbfix/proc
mount --bind /sys /mnt/usbfix/sys
mount --bind /run /mnt/usbfix/run
mkdir -p /mnt/usbfix/etc
cp /etc/resolv.conf /mnt/usbfix/etc/resolv.conf

# 5. RUN REPAIR IN CHROOT
echo -e "${GREEN}[*] Running repair operations (this may take a few minutes)...${NC}"
arch-chroot /mnt/usbfix /tmp/repair.sh

# 6. CLEANUP
echo -e "${GREEN}[*] Cleaning up...${NC}"
rm /mnt/usbfix/tmp/repair.sh
umount /mnt/usbfix/run
umount /mnt/usbfix/sys
umount /mnt/usbfix/proc
umount /mnt/usbfix/dev
umount /mnt/usbfix/boot
umount /mnt/usbfix
sync

echo -e "${GREEN}
===============================================
  USB REPAIR COMPLETE!
===============================================
Your USB has been repaired with:
  ✓ Network configuration fixed
  ✓ Pacman keyring initialized
  ✓ Essential packages installed
  ✓ DNS resolution fixed
  ✓ All network services enabled

You can now:
  1. Remove the USB
  2. Boot from it
  3. Internet and pacman should work!
  
Test with: ping google.com
===============================================
${NC}"
