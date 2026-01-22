#!/bin/bash

# --- CONFIGURATION ---
set -e
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

# Log file
LOG_FILE="/tmp/arch_usb_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- BANNER ---
clear
echo -e "${GREEN}"
cat << "EOF"
   _          _    _    _                _   _ ___ ___ 
  /_\  _ _ __| |_ | |  (_)_ _ _  ___ __ | | | / __| _ )
 / _ \| '_/ _| ' \| |__| | ' \ || \ \ / | |_| \__ \ _ \
/_/ \_\_| \__|_||_|____|_|_||_\_,_/_\_\  \___/|___/___/
EOF
echo -e "${NC}"
echo "Portable Arch USB Installer (Enhanced + Optimized)"
echo "By: Y.S.F"
echo "--------------------------------------------------"
echo -e "${BLUE}Log file: $LOG_FILE${NC}\n"

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}" 
   exit 1
fi

# 1. PRE-INSTALL SPEED OPTIMIZATION
echo -e "${GREEN}[*] Enabling Parallel Downloads for speed...${NC}"
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# 2. GATHER USER INFO
read -p "Enter desired Hostname: " NEW_HOSTNAME
read -p "Enter name for Superuser: " NEW_USER
echo -n "Enter password for Root and $NEW_USER: "
read -s NEW_PASSWORD
echo -e "\n${GREEN}Credentials saved.${NC}"

# 3. SELECT DEVICE
echo -e "\n${CYAN}--- DEVICE SELECTION ---${NC}"
lsblk -d -p -n -o NAME,SIZE,MODEL,TYPE | grep -v "loop" | grep -v "rom"
read -p "Select device path (e.g., /dev/sdb): " TARGET_DEVICE

if [ ! -b "$TARGET_DEVICE" ]; then echo -e "${RED}Device not found!${NC}"; exit 1; fi

echo -e "${RED}WARNING: $TARGET_DEVICE WILL BE WIPED!${NC}"
read -p "Type 'YES' to confirm: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then echo "Aborted."; exit 1; fi

# 4. MIRROR RANKING (Fastest Downloads)
echo -e "${GREEN}[*] Ranking mirrors (picking the fastest servers)...${NC}"
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# 5. WIPE AND PARTITION
echo -e "${GREEN}[*] Partitioning $TARGET_DEVICE...${NC}"
umount ${TARGET_DEVICE}* 2>/dev/null || true
sgdisk --zap-all $TARGET_DEVICE
sgdisk -o -n 1:0:+10M -t 1:EF02 -n 2:0:+500M -t 2:EF00 -n 3:0:0 -t 3:8304 $TARGET_DEVICE
sleep 2

# Identify partitions
if [[ "$TARGET_DEVICE" == *"nvme"* ]]; then
    P2="${TARGET_DEVICE}p2"; P3="${TARGET_DEVICE}p3"
else
    P2="${TARGET_DEVICE}2"; P3="${TARGET_DEVICE}3"
fi

# 6. FORMAT & MOUNT
mkfs.fat -F32 $P2
mkfs.ext4 -F $P3
mkdir -p /mnt/usb
mount $P3 /mnt/usb
mkdir -p /mnt/usb/boot
mount $P2 /mnt/usb/boot

# 7. PACSTRAP (With Essential build tools for the user)
echo -e "${GREEN}[*] Installing Base System + Build Essentials...${NC}"
# Added: base-devel, git, bash-completion, and fastfetch
pacstrap /mnt/usb base base-devel linux linux-firmware git vim nano bash-completion grub efibootmgr iwd polkit sudo amd-ucode intel-ucode networkmanager fastfetch

# 8. FSTAB (USB Optimization)
genfstab -U /mnt/usb > /mnt/usb/etc/fstab
sed -i 's/relatime/noatime/g' /mnt/usb/etc/fstab

# 9. CONFIGURE SYSTEM (CHROOT)
cat <<EOF > /mnt/usb/setup_internal.sh
#!/bin/bash
set -e

# Enable Parallel Downloads in the NEW system too
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Localization
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Networking
echo "$NEW_HOSTNAME" > /etc/hostname
systemctl enable systemd-networkd systemd-resolved iwd

# Users & Passwords
echo "root:$NEW_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash $NEW_USER
echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel

# Bootloader (Universal BIOS + UEFI)
grub-install --target=i386-pc --recheck $TARGET_DEVICE
grub-install --target=x86_64-efi --efi-directory /boot --recheck --removable
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nomodeset /' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# USB Optimizations (Journal to RAM)
mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]\nStorage=volatile\nSystemMaxUse=16M" > /etc/systemd/journald.conf.d/10-volatile.conf

# Portability (Load all drivers)
sed -i 's/autodetect //g' /etc/mkinitcpio.conf
mkinitcpio -P

# Clean naming
ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
EOF

chmod +x /mnt/usb/setup_internal.sh
arch-chroot /mnt/usb /setup_internal.sh
rm /mnt/usb/setup_internal.sh

# 10. FINISH
umount -R /mnt/usb
sync

echo -e "${GREEN}
==================================================
        INSTALLATION COMPLETE (by: Y.S.F)
==================================================
The USB is now a portable Arch workstation.
- Build tools (git/make/gcc) are pre-installed.
- Parallel downloads are enabled.
- All hardware drivers will load on boot.

Next step: Boot from USB and run 'fastfetch'!
==================================================
${NC}"
