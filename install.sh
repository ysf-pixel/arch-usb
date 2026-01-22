#!/bin/bash

# --- CONFIGURATION ---
# Stop on error
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/arch_usb_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${GREEN}
   _          _    _    _                _   _ ___ ___ 
  /_\  _ _ __| |_ | |  (_)_ _ _  ___ __ | | | / __| _ )
 / _ \| '_/ _| ' \| |__| | ' \ || \ \ / | |_| \__ \ _ \
/_/ \_\_| \__|_||_|____|_|_||_\_,_/_\_\  \___/|___/___/
${NC}"
echo "Portable Arch USB Installer (Enhanced)"
echo "---------------------------------------"
echo -e "${BLUE}Log file: $LOG_FILE${NC}"
echo ""

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root.${NC}" 
   exit 1
fi

# Helper function for error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}"
    echo -e "${YELLOW}Check the log file: $LOG_FILE${NC}"
    exit 1
}

# Checkpoint system
CHECKPOINT_FILE="/tmp/arch_install_checkpoint"
save_checkpoint() {
    echo "$1" > "$CHECKPOINT_FILE"
}

load_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        cat "$CHECKPOINT_FILE"
    else
        echo "START"
    fi
}

# Check for resume
LAST_CHECKPOINT=$(load_checkpoint)
if [ "$LAST_CHECKPOINT" != "START" ]; then
    echo -e "${YELLOW}Previous installation detected at checkpoint: $LAST_CHECKPOINT${NC}"
    read -p "Do you want to resume? (yes/no): " RESUME
    if [ "$RESUME" = "yes" ]; then
        echo -e "${GREEN}Resuming from checkpoint: $LAST_CHECKPOINT${NC}"
    else
        rm -f "$CHECKPOINT_FILE"
        LAST_CHECKPOINT="START"
    fi
else
    rm -f "$CHECKPOINT_FILE"
fi

# Dry run option
if [ "$LAST_CHECKPOINT" = "START" ]; then
    read -p "Run in DRY RUN mode (preview only, no changes)? (yes/no): " DRY_RUN
    if [ "$DRY_RUN" = "yes" ]; then
        echo -e "${YELLOW}=== DRY RUN MODE ===${NC}"
        echo "This will show you what would happen without making any changes."
    fi
fi

# WiFi setup helper
if [ "$LAST_CHECKPOINT" = "START" ] && [ "$DRY_RUN" != "yes" ]; then
    echo -e "${GREEN}[*] Checking Network Connection...${NC}"
    if ! ping -c 1 -W 2 archlinux.org &>/dev/null; then
        echo -e "${YELLOW}No internet connection detected.${NC}"
        read -p "Do you need to set up WiFi? (yes/no): " SETUP_WIFI
        if [ "$SETUP_WIFI" = "yes" ]; then
            echo -e "${BLUE}WiFi Setup Guide:${NC}"
            echo "1. Run: iwctl"
            echo "2. List devices: device list"
            echo "3. Scan networks: station <device> scan"
            echo "4. List networks: station <device> get-networks"
            echo "5. Connect: station <device> connect <SSID>"
            echo "6. Exit: exit"
            echo ""
            read -p "Press ENTER when ready to continue..."
            
            if ! ping -c 1 -W 2 archlinux.org &>/dev/null; then
                error_exit "Still no internet connection. Please configure network and try again."
            fi
        else
            error_exit "Internet connection required. Please configure network and try again."
        fi
    fi
    echo -e "${GREEN}Internet connection verified.${NC}"
fi

# 1. SELECT DEVICE
if [ "$LAST_CHECKPOINT" = "START" ]; then
    echo -e "${GREEN}[*] Detecting Block Devices...${NC}"
    
    # Create device array
    mapfile -t DEVICES < <(lsblk -d -p -n -o NAME,SIZE,MODEL,TYPE | grep -v "loop" | grep -v "rom")
    
    if [ ${#DEVICES[@]} -eq 0 ]; then
        error_exit "No suitable devices found."
    fi
    
    echo ""
    echo "Available devices:"
    for i in "${!DEVICES[@]}"; do
        echo "$((i+1)). ${DEVICES[$i]}"
    done
    echo ""
    
    read -p "Select device number (1-${#DEVICES[@]}): " DEVICE_NUM
    
    if ! [[ "$DEVICE_NUM" =~ ^[0-9]+$ ]] || [ "$DEVICE_NUM" -lt 1 ] || [ "$DEVICE_NUM" -gt ${#DEVICES[@]} ]; then
        error_exit "Invalid selection."
    fi
    
    TARGET_DEVICE=$(echo "${DEVICES[$((DEVICE_NUM-1))]}" | awk '{print $1}')
    
    if [ ! -b "$TARGET_DEVICE" ]; then
        error_exit "Device $TARGET_DEVICE not found."
    fi
    
    # Disk size check
    DEVICE_SIZE=$(lsblk -b -d -n -o SIZE "$TARGET_DEVICE")
    MIN_SIZE=$((8*1024*1024*1024)) # 8GB
    
    if [ "$DEVICE_SIZE" -lt "$MIN_SIZE" ]; then
        echo -e "${YELLOW}Warning: Device is smaller than 8GB. Installation may fail or be cramped.${NC}"
        read -p "Continue anyway? (yes/no): " CONTINUE
        if [ "$CONTINUE" != "yes" ]; then
            echo "Aborted."
            exit 1
        fi
    fi
    
    # Backup check - show existing data
    echo -e "${YELLOW}Checking for existing data on $TARGET_DEVICE...${NC}"
    if lsblk -f "$TARGET_DEVICE" | grep -q "[a-z]"; then
        echo -e "${RED}WARNING: This device appears to have existing partitions/data:${NC}"
        lsblk -f "$TARGET_DEVICE"
        echo ""
    fi
    
    echo -e "${RED}WARNING: The device $TARGET_DEVICE will be COMPLETELY WIPED.${NC}"
    read -p "Are you ABSOLUTELY SURE you want to wipe $TARGET_DEVICE? (Type 'YES' to confirm): " CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        echo "Aborted."
        exit 1
    fi
    
    save_checkpoint "DEVICE_SELECTED"
fi

# 2. GATHER USER INFO
if [ "$LAST_CHECKPOINT" = "START" ] || [ "$LAST_CHECKPOINT" = "DEVICE_SELECTED" ]; then
    
    # Timezone selection
    echo -e "${GREEN}[*] Timezone Selection${NC}"
    echo "Detecting timezone..."
    AUTO_TZ=$(curl -s http://ip-api.com/line?fields=timezone 2>/dev/null || echo "UTC")
    echo "Auto-detected: $AUTO_TZ"
    read -p "Enter timezone (or press ENTER for $AUTO_TZ): " USER_TZ
    TIMEZONE=${USER_TZ:-$AUTO_TZ}
    
    # Validate timezone
    if [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
        echo -e "${YELLOW}Timezone not found, using UTC${NC}"
        TIMEZONE="UTC"
    fi
    
    # Locale selection
    echo -e "${GREEN}[*] Locale Selection${NC}"
    echo "Common locales:"
    echo "1. en_US.UTF-8 (English - US)"
    echo "2. en_GB.UTF-8 (English - UK)"
    echo "3. de_DE.UTF-8 (German)"
    echo "4. fr_FR.UTF-8 (French)"
    echo "5. es_ES.UTF-8 (Spanish)"
    echo "6. Custom"
    read -p "Select locale (1-6, default 1): " LOCALE_CHOICE
    
    case $LOCALE_CHOICE in
        2) LOCALE="en_GB.UTF-8";;
        3) LOCALE="de_DE.UTF-8";;
        4) LOCALE="fr_FR.UTF-8";;
        5) LOCALE="es_ES.UTF-8";;
        6) read -p "Enter custom locale (e.g., ja_JP.UTF-8): " LOCALE;;
        *) LOCALE="en_US.UTF-8";;
    esac
    
    read -p "Enter desired Hostname: " NEW_HOSTNAME
    read -p "Enter desired Username: " NEW_USER
    echo "Enter password for Root and User:"
    read -s NEW_PASSWORD
    echo
    
    # Swap file option
    read -p "Create swap file? Recommended for systems with <4GB RAM (yes/no): " CREATE_SWAP
    if [ "$CREATE_SWAP" = "yes" ]; then
        read -p "Swap file size in GB (default 2): " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-2}
    fi
    
    save_checkpoint "INFO_GATHERED"
fi

# Dry run summary
if [ "$DRY_RUN" = "yes" ]; then
    echo -e "${YELLOW}"
    echo "========================================"
    echo "DRY RUN SUMMARY - NO CHANGES WILL BE MADE"
    echo "========================================"
    echo "Target Device: $TARGET_DEVICE"
    echo "Timezone: $TIMEZONE"
    echo "Locale: $LOCALE"
    echo "Hostname: $NEW_HOSTNAME"
    echo "Username: $NEW_USER"
    echo "Swap: ${CREATE_SWAP:-no} ${SWAP_SIZE:+($SWAP_SIZE GB)}"
    echo ""
    echo "Operations that WOULD be performed:"
    echo "1. Wipe $TARGET_DEVICE completely"
    echo "2. Create partitions: 10MB BIOS, 500MB EFI, remaining for root"
    echo "3. Format partitions (FAT32 for EFI, ext4 for root)"
    echo "4. Install base Arch system via pacstrap"
    echo "5. Configure system (timezone, locale, users, bootloader)"
    echo "6. Install GRUB for both BIOS and UEFI"
    echo "========================================"
    echo -e "${NC}"
    exit 0
fi

# 3. WIPE AND PARTITION
if [ "$LAST_CHECKPOINT" = "START" ] || [ "$LAST_CHECKPOINT" = "DEVICE_SELECTED" ] || [ "$LAST_CHECKPOINT" = "INFO_GATHERED" ]; then
    echo -e "${GREEN}[*] Wiping and Partitioning $TARGET_DEVICE...${NC}"
    
    # Unmount if mounted
    umount ${TARGET_DEVICE}* 2>/dev/null || true
    
    # Zap all data
    sgdisk --zap-all $TARGET_DEVICE || error_exit "Failed to wipe device"
    
    # Create partitions
    sgdisk -o -n 1:0:+10M -t 1:EF02 -n 2:0:+500M -t 2:EF00 -n 3:0:0 -t 3:8304 $TARGET_DEVICE || error_exit "Failed to create partitions"
    
    # Wait for kernel to update partition table
    sleep 2
    partprobe $TARGET_DEVICE 2>/dev/null || true
    sleep 1
    
    # Identify partitions
    if [[ "$TARGET_DEVICE" == *"nvme"* ]]; then
        PART1="${TARGET_DEVICE}p1"
        PART2="${TARGET_DEVICE}p2"
        PART3="${TARGET_DEVICE}p3"
    else
        PART1="${TARGET_DEVICE}1"
        PART2="${TARGET_DEVICE}2"
        PART3="${TARGET_DEVICE}3"
    fi
    
    save_checkpoint "PARTITIONED"
fi

# 4. FORMAT
if [ "$LAST_CHECKPOINT" = "PARTITIONED" ] || [ "$LAST_CHECKPOINT" = "INFO_GATHERED" ]; then
    echo -e "${GREEN}[*] Formatting Partitions...${NC}"
    
    mkfs.fat -F32 $PART2 || error_exit "Failed to format EFI partition"
    mkfs.ext4 -F $PART3 || error_exit "Failed to format root partition"
    
    save_checkpoint "FORMATTED"
fi

# 5. MOUNT
if [ "$LAST_CHECKPOINT" = "FORMATTED" ] || [ "$LAST_CHECKPOINT" = "PARTITIONED" ]; then
    echo -e "${GREEN}[*] Mounting...${NC}"
    
    mkdir -p /mnt/usb
    mount $PART3 /mnt/usb || error_exit "Failed to mount root partition"
    mkdir -p /mnt/usb/boot
    mount $PART2 /mnt/usb/boot || error_exit "Failed to mount EFI partition"
    
    save_checkpoint "MOUNTED"
fi

# 6. PACSTRAP
if [ "$LAST_CHECKPOINT" = "MOUNTED" ] || [ "$LAST_CHECKPOINT" = "FORMATTED" ]; then
    echo -e "${GREEN}[*] Installing Base System (Pacstrap)...${NC}"
    echo -e "${BLUE}This may take 5-15 minutes depending on your internet connection...${NC}"
    
    pacstrap /mnt/usb linux linux-firmware base vim grub efibootmgr iwd polkit sudo amd-ucode intel-ucode networkmanager || error_exit "Pacstrap failed"
    
    save_checkpoint "PACSTRAP_DONE"
fi

# 7. FSTAB
if [ "$LAST_CHECKPOINT" = "PACSTRAP_DONE" ] || [ "$LAST_CHECKPOINT" = "MOUNTED" ]; then
    echo -e "${GREEN}[*] Generating Fstab...${NC}"
    
    genfstab -U /mnt/usb > /mnt/usb/etc/fstab || error_exit "Failed to generate fstab"
    sed -i 's/relatime/noatime/g' /mnt/usb/etc/fstab
    
    save_checkpoint "FSTAB_DONE"
fi

# 8. CONFIGURE SYSTEM (CHROOT)
if [ "$LAST_CHECKPOINT" = "FSTAB_DONE" ] || [ "$LAST_CHECKPOINT" = "PACSTRAP_DONE" ]; then
    echo -e "${GREEN}[*] Configuring System (Chroot)...${NC}"
    
    # Create setup script
    cat <<EOF > /mnt/usb/setup_internal.sh
#!/bin/bash
set -e

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Hostname
echo "$NEW_HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1  localhost
::1        localhost
127.0.1.1  $NEW_HOSTNAME.localdomain  $NEW_HOSTNAME
HOSTS

# Passwords
echo "root:$NEW_PASSWORD" | chpasswd

# Bootloader (GRUB)
grub-install --target=i386-pc --recheck $TARGET_DEVICE
grub-install --target=x86_64-efi --efi-directory /boot --recheck --removable

# Network Configuration
cat <<NET1 > /etc/systemd/network/20-eth.network
[Match]
Name=en*
Name=eth*
[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
[DHCPv4]
RouteMetric=100
[IPv6AcceptRA]
RouteMetric=100
NET1

cat <<NET2 > /etc/systemd/network/30-wlan.network
[Match]
Name=wl*
[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
[DHCPv4]
RouteMetric=200
[IPv6AcceptRA]
RouteMetric=200
NET2

# Enable Services
systemctl enable systemd-networkd.service
systemctl enable iwd.service
systemctl enable systemd-resolved.service
systemctl enable systemd-timesyncd.service

# Fix DNS
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Create User
useradd -m $NEW_USER
echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
groupadd wheel 2>/dev/null || true
usermod -aG wheel $NEW_USER
groupadd sudo 2>/dev/null || true
usermod -aG sudo $NEW_USER

# Sudo Privileges
echo "%sudo ALL=(ALL) ALL" > /etc/sudoers.d/10-sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/10-sudo

# Journal Optimization
mkdir -p /etc/systemd/journald.conf.d
cat <<JRNL > /etc/systemd/journald.conf.d/10-volatile.conf
[Journal]
Storage=volatile
SystemMaxUse=16M
RuntimeMaxUse=32M
JRNL

# Swap file
if [ "$CREATE_SWAP" = "yes" ]; then
    dd if=/dev/zero of=/swapfile bs=1G count=$SWAP_SIZE status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
fi

# Mkinitcpio
sed -i 's/autodetect //g' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB Config
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nomodeset /' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Interface Names
ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules

EOF

    chmod +x /mnt/usb/setup_internal.sh
    arch-chroot /mnt/usb /setup_internal.sh || error_exit "Chroot configuration failed"
    rm /mnt/usb/setup_internal.sh
    
    save_checkpoint "CONFIGURED"
fi

# 9. VERIFICATION
echo -e "${GREEN}[*] Verifying Installation...${NC}"
if mountpoint -q /mnt/usb; then
    arch-chroot /mnt/usb /bin/bash -c "which grub-mkconfig && which systemctl" 2>/dev/null || echo -e "${YELLOW}Warning: Verification checks failed (non-critical)${NC}"
else
    echo -e "${YELLOW}Warning: /mnt/usb not mounted, skipping verification${NC}"
fi

# 10. FINISH
echo -e "${GREEN}[*] Unmounting...${NC}"
if mountpoint -q /mnt/usb/boot; then
    umount /mnt/usb/boot || echo -e "${YELLOW}Warning: Could not unmount /mnt/usb/boot${NC}"
fi
if mountpoint -q /mnt/usb; then
    umount /mnt/usb || echo -e "${YELLOW}Warning: Could not unmount /mnt/usb${NC}"
fi
sync

# Cleanup checkpoint
rm -f "$CHECKPOINT_FILE"

echo -e "${GREEN}
===========================================
INSTALLATION COMPLETE!
===========================================
Device: $TARGET_DEVICE
Timezone: $TIMEZONE
Locale: $LOCALE
Hostname: $NEW_HOSTNAME
User: $NEW_USER
Swap: ${CREATE_SWAP:-no} ${SWAP_SIZE:+($SWAP_SIZE GB)}

Log saved to: $LOG_FILE

You can now:
1. Remove the USB drive safely
2. Boot from it on any computer
3. Login with your credentials

To boot from USB:
- Enter BIOS/UEFI (F2/F12/Del/Esc)
- Select USB as boot device
===========================================
${NC}"
