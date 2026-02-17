#!/bin/bash

# Configuration
IMAGE_PATH="$HOME/Scrivania/floppy.img"
# We will now detect or confirm the device rather than hardcoding it
TARGET_DEVICE="/dev/sdb"
SCRIPT_NAME="$(basename "$0")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[$SCRIPT_NAME]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[$SCRIPT_NAME]${NC} $1"; }
print_error() { echo -e "${RED}[$SCRIPT_NAME]${NC} $1"; }

# 1. Root check
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root directly."
    exit 1
fi

# 2. Dependency Check
if ! command -v lsblk &> /dev/null; then
    print_error "lsblk is required. Please install it."
    exit 1
fi

# 3. File existence check
if [[ ! -f "$IMAGE_PATH" ]]; then
    print_error "Image file not found: $IMAGE_PATH"
    exit 1
fi

# 4. Hardware Verification Logic
# This lists all USB devices to help the user verify /dev/sdb is correct
echo "--- DETECTED USB DEVICES ---"
lsblk -o NAME,SIZE,MODEL,TRAN | grep "usb"
echo "----------------------------"

if [ ! -b "$TARGET_DEVICE" ]; then
    print_error "Target device $TARGET_DEVICE not found or is not a block device."
    exit 1
fi

# 5. Warning message
print_warning "=== HARDWARE FLASHING WARNING ==="
print_warning "Target: $(lsblk -no MODEL "$TARGET_DEVICE" | xargs) ($TARGET_DEVICE)"
print_warning "This will DESTROY all data on the drive."
echo
read -p "Type 'YES' to confirm: " confirmation
[[ "$confirmation" != "YES" ]] && { print_error "Aborted."; exit 0; }

# 6. Unmount existing partitions (Improved)
print_status "Unmounting all partitions on $TARGET_DEVICE..."
# The '|| true' ensures the script continues even if nothing was mounted
sudo umount "${TARGET_DEVICE}"* 2>/dev/null || true

# 7. The Write Process (Hardware Optimized)
print_status "Writing image to $TARGET_DEVICE..."
# Added 'conv=fdatasync' to ensure data is physically on the platters/flash
# Added 'oflag=direct' to bypass system cache for more reliable flashing
if sudo dd if="$IMAGE_PATH" of="$TARGET_DEVICE" bs=4M status=progress conv=fdatasync oflag=direct; then
    print_status "Write complete."
else
    print_error "Write failed. Check if the USB stick is write-protected."
    exit 1
fi

# 8. Force Hardware Refresh
print_status "Refreshing partition table and syncing..."
sudo partprobe "$TARGET_DEVICE"
sudo sync

print_status "SUCCESS! You can now boot from this USB on real hardware."
