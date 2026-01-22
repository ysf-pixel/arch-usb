#!/bin/bash

# --- THEMES & COLORS ---
set -e
PRIMARY='\033[1;34m'   # Bold Blue
SUCCESS='\033[1;32m'   # Bold Green
WARNING='\033[1;33m'   # Bold Yellow
DANGER='\033[1;31m'    # Bold Red
INFO='\033[1;36m'      # Bold Cyan
BOLD='\033[1m'
NC='\033[0m' 

# Visual Helpers
print_line() { echo -e "${PRIMARY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${INFO}➜ ${BOLD}$1${NC}"; }
print_success() { echo -e "${SUCCESS}✔ $1${NC}"; }
print_error() { echo -e "${DANGER}✖ $1${NC}"; }

# --- BANNER ---
clear
echo -e "${PRIMARY}"
cat << "EOF"
  ▄▄▄▄▄▄▄ ▄▄▄▄▄▄   ▄▄▄▄▄▄▄ ▄▄   ▄▄    ▄▄   ▄▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄    ▄▄▄ ▄▄    ▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄ ▄▄▄     ▄▄▄     ▄▄▄▄▄▄▄ ▄▄▄▄▄▄   
█       █   ▄  █ █       █  █ █  █  █  █ █  █       █  ▄    █  █   █  █  █ █       █       █       █   █   █   █   █       █   ▄  █  
█   ▄   █  █ █ █ █       █  █▄█  █  █  █ █  █  ▄▄▄▄▄█ █▄█   █  █   █   █▄█ █  ▄▄▄▄▄█▄     ▄█   ▄   █   █   █   █   █    ▄▄▄█  █ █ █  
█  █▄█  █   █▄▄█▄█     ▄▄█       █  █  █▄█  █ █▄▄▄▄▄█       █  █   █       █ █▄▄▄▄▄  █   █ █  █▄█  █   █   █   █   █   █▄▄▄█   █▄▄█▄ 
█       █    ▄▄  █    █  █   ▄   █  █       █▄▄▄▄▄  █  ▄   █   █   █  ▄    █▄▄▄▄▄  █ █   █ █       █   █▄▄▄█   █▄▄▄█    ▄▄▄█    ▄▄  █
█   ▄   █   █  █ █    █▄▄█  █ █  █  █       █▄▄▄▄▄█ █ █▄█   █  █   █ █ █   █▄▄▄▄▄█ █ █   █ █   ▄   █       █       █   █▄▄▄█   █  █ █
█▄▄█ █▄▄█▄▄▄█  █▄█▄▄▄▄▄▄▄█▄▄█ █▄▄█  █▄▄▄▄▄▄▄█▄▄▄▄▄▄▄█▄▄▄▄▄▄▄█  █▄▄▄█▄█  █▄▄█▄▄▄▄▄▄▄█ █▄▄▄█ █▄▄█ █▄▄█▄▄▄▄▄▄▄█▄▄▄▄▄▄▄█▄▄▄▄▄▄▄█▄▄▄█  █▄█

        -- P O R T A B L E   U S B   E D I T I O N --
EOF
echo -e "          ${BOLD}Created by: Y.S.F${NC}"
print_line

# 1. INITIALIZATION & NETWORK
print_step "Checking environment..."
if [[ $EUID -ne 0 ]]; then
   print_error "You must be root! Run with: sudo ./script.sh" 
   exit 1
fi

# Fix for Image 1: Speed/Mirror optimization
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
print_success "Super-speed downloads enabled."

# 2. GATHER DATA
print_line
print_step "System Configuration"
read -p "  Enter Hostname: " NEW_HOSTNAME
read -p "  Enter Username: " NEW_USER
read -s -p "  Enter Password: " PASS
echo -e "\n"

# 3. DRIVE SELECTION
print_line
print_step "Drive Selection"
lsblk -d -p -n -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "  Type the target drive path (e.g., /dev/sdb): " TARGET
if [ ! -b "$TARGET" ]; then print_error "Invalid device!"; exit 1; fi

print_line
echo -e "${DANGER}  WIPING ALL DATA ON: $TARGET${NC}"
read -p "  Are you absolutely sure? (Type YES to confirm): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then print_error "Aborted."; exit 1; fi

# 4. PREPARATION (Partition/Format)
print_line
print_step "Preparing partitions on $TARGET..."
umount ${TARGET}* 2>/dev/null || true
sgdisk --zap-all "$TARGET" > /dev/null
sgdisk -n 1:0:+1M -t 1:EF02 -n 2:0:+512M -t 2:EF00 -n 3:0:0 -t 3:8304 "$TARGET" > /dev/null
sleep 1

P2="${TARGET}2"; P3="${TARGET}3"
[[ "$TARGET" == *"nvme"* ]] && P2="${TARGET}p2" && P3="${TARGET}p3"

mkfs.fat -F32 "$P2" > /dev/null
mkfs.ext4 -F "$P3" > /dev/null
mount "$P3" /mnt
mkdir -p /mnt/boot
mount "$P2" /mnt/boot
print_success "Drive ready and mounted."

# 5. PACSTRAP (Fix for Image 2: Automation Freeze)
print_line
print_step "Installing Arch Linux (Please wait...)"
# Added --noconfirm to prevent freeze on iptables choice
# Added sof-firmware to resolve missing firmware warnings
pacstrap -K /mnt --noconfirm base base-devel linux linux-firmware sof-firmware git nano networkmanager grub efibootmgr sudo bash-completion fastfetch 
print_success "Base system installed successfully."

# 6. CONFIGURATION
print_line
print_step "Configuring your portable workstation..."
genfstab -U /mnt >> /mnt/etc/fstab

cat <<EOF > /mnt/setup.sh
#!/bin/bash
set -e

# FIX for Image 3: Create vconsole.conf BEFORE mkinitcpio runs
echo "KEYMAP=us" > /etc/vconsole.conf

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen > /dev/null
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$NEW_HOSTNAME" > /etc/hostname
systemctl enable NetworkManager > /dev/null

# Users
echo "root:$PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
echo "$NEW_USER:$PASS" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel

# Bootloader (Universal BIOS/UEFI)
grub-install --target=i386-pc --recheck "$TARGET" > /dev/null 2>&1
grub-install --target=x86_64-efi --efi-directory /boot --removable --recheck > /dev/null 2>&1
grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1

# Portable Kernel build - Autodetect removed for universal booting
sed -i 's/autodetect //g' /etc/mkinitcpio.conf
mkinitcpio -P > /dev/null
EOF

arch-chroot /mnt /bin/bash /setup.sh
rm /mnt/setup.sh
print_success "System configuration finished."

# 7. FINAL EXIT
print_line
umount -R /mnt
sync

echo -e "${SUCCESS}"
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │          INSTALLATION COMPLETE BY Y.S.F          │"
echo "  ├──────────────────────────────────────────────────┤"
echo "    Hostname: $NEW_HOSTNAME"
echo "    User    : $NEW_USER"
echo "    Status  : Portable & Bootable (Universal)"
echo "  └──────────────────────────────────────────────────┘"
echo -e "${NC}"
echo -e "${INFO}➜ Reboot your PC and select the USB from the boot menu!${NC}\n"
