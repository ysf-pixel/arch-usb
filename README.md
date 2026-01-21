# Arch USB Installer

**Automated Portable Arch Linux USB Installation Script**

Create a fully functional, bootable Arch Linux system on a USB drive that works on any computer (BIOS or UEFI).

---

## 🚀 Quick Start

Run this single command on an existing Arch Linux system:

```bash
curl -sL https://raw.githubusercontent.com/ysf-pixel/arch-usb/main/install.sh | sudo bash
```

**⚠️ WARNING:** This will **completely wipe** the USB drive you select. Make sure you have backups!

---

## ✨ Features

- ✅ **Dual Boot Support** - Works on both BIOS and UEFI systems
- ✅ **Fully Portable** - Boot on any computer, hardware autodetection included
- ✅ **Interactive Setup** - Easy device selection, timezone, locale configuration
- ✅ **Dry Run Mode** - Preview changes before committing
- ✅ **Error Recovery** - Resume installation if something fails
- ✅ **USB Optimized** - Reduced writes, volatile logging, noatime mounts
- ✅ **Network Ready** - Automatic DHCP for Ethernet and WiFi support
- ✅ **Optional Swap** - Configurable swap file for low-RAM systems
- ✅ **Full Logging** - Complete installation log saved for troubleshooting

---

## 📋 Requirements

- Running Arch Linux system (or Arch-based distro)
- Root/sudo access
- Internet connection
- USB drive (8GB+ recommended)
- `curl` installed

---

## 🛠️ Manual Installation

If you prefer to review the script first:

```bash
# Download the script
curl -O https://raw.githubusercontent.com/ysf-pixel/arch-usb/main/install.sh

# Review it
cat install.sh

# Make it executable
chmod +x install.sh

# Run it
sudo ./install.sh
```

---

## 📖 Usage Guide

### Step 1: Run the script
```bash
curl -sL https://raw.githubusercontent.com/ysf-pixel/arch-usb/main/install.sh | sudo bash
```

### Step 2: Choose options
- **Dry Run**: Preview what will happen (recommended first time)
- **Network Check**: Script will verify internet and help with WiFi if needed
- **Device Selection**: Pick your USB from a numbered menu
- **Timezone**: Auto-detected or custom
- **Locale**: Choose from common locales or enter custom
- **User Setup**: Set hostname, username, and password
- **Swap File**: Optional (recommended for <4GB RAM systems)

### Step 3: Wait
Installation takes 5-15 minutes depending on internet speed.

### Step 4: Boot
1. Remove USB drive
2. Insert into any computer
3. Boot from USB (usually F2/F12/Del/Esc during startup)
4. Login with your credentials

---

## 🔧 What Gets Installed

**Base System:**
- Linux kernel + firmware
- Base utilities (vim, sudo, polkit)
- Network tools (iwd, NetworkManager, systemd-networkd)
- Both AMD and Intel microcode

**Bootloader:**
- GRUB for BIOS (legacy systems)
- GRUB for UEFI (modern systems)
- Configured with `nomodeset` for maximum compatibility

**Optimizations:**
- Removed autodetect hook (works on different hardware)
- `noatime` filesystem mount (reduces USB writes)
- Volatile journal storage (uses RAM, not USB)
- Traditional network interface names

---

## 🐛 Troubleshooting

### No Internet Connection
If WiFi setup is needed:
```bash
iwctl
device list
station <device> scan
station <device> get-networks
station <device> connect <SSID>
exit
```

### Installation Failed Mid-Way
The script saves checkpoints. Just re-run it and choose "yes" to resume.

### Check Installation Log
```bash
cat /tmp/arch_usb_install_*.log
```

### USB Won't Boot
- Ensure Secure Boot is disabled in BIOS/UEFI
- Try changing boot mode (UEFI ↔ Legacy)
- Verify boot order in BIOS

---

## ⚙️ Customization

After installation, boot into your USB and customize:

```bash
# Install desktop environment
sudo pacman -S xorg plasma kde-applications

# Install additional software
sudo pacman -S firefox git htop

# Enable services
sudo systemctl enable sddm
```

---

## 📊 Partition Layout

| Partition | Size | Type | Purpose |
|-----------|------|------|---------|
| 1 | 10MB | BIOS Boot | GRUB BIOS |
| 2 | 500MB | EFI System | GRUB UEFI |
| 3 | Remaining | Linux Root | System files |

---

## 🤝 Contributing

Contributions welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

---

## 📜 License

This project is free and open-source. Use at your own risk.

---

## ⚠️ Disclaimer

This script will **completely erase** the selected USB drive. Always verify you've selected the correct device. The author is not responsible for data loss.

---

## 🙏 Credits

Created by **ysf-pixel**

Based on the Arch Linux installation guide with portability and automation enhancements.

---

**Enjoy your portable Arch Linux system! 🐧**
