#!/bin/bash

# Get the directory of the script
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Default output ISO file and directory
ISO_OUTPUT="$SCRIPT_DIR/bootable.iso"
OUTPUT_DIR="$SCRIPT_DIR/iso"

# Function to display usage information
usage() {
    echo "Usage: $0 [-o output_iso_path] <kernel> <initramfs.gpio.gz>"
    echo ""
    echo "This script creates a bootable ISO with the provided kernel and initramfs."
    echo ""
    echo "Options:"
    echo "  -o    Specify the output ISO path (default: bootable.iso)"
    echo "  -h, --help   Display this help message"
    echo ""
    echo "Arguments:"
    echo "  <kernel>       Path to the kernel file."
    echo "  <initramfs.gz> Path to the initramfs file."
    exit 1
}

# Parse the command-line options
while getopts "o:h-:" opt; do
  case $opt in
    o)
      # Split the output option into directory and file name
      ISO_OUTPUT="$OPTARG"
      OUTPUT_DIR=$(dirname "$ISO_OUTPUT")
      ;;
    h|?|-h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# Check if correct number of arguments is passed
shift $((OPTIND - 1))
if [ $# -ne 2 ]; then
    usage
fi

KERNEL=$1
INITRAMFS=$2
GRUB_DIR="$OUTPUT_DIR/boot/grub"
MOUNT_DIR="$OUTPUT_DIR/mnt"

# Make sure necessary directories exist
echo "Creating necessary directories..."
mkdir -p $GRUB_DIR $MOUNT_DIR/boot

# Copy the kernel and initramfs to appropriate locations
echo "Copying kernel to $OUTPUT_DIR/boot/vmlinuz..."
cp $KERNEL $OUTPUT_DIR/boot/vmlinuz
echo "Kernel copied."

echo "Copying initramfs to $OUTPUT_DIR/boot/initramfs.gz..."
cp $INITRAMFS $OUTPUT_DIR/boot/initramfs.gz
echo "Initramfs copied."

# Create the GRUB configuration
echo "Creating GRUB configuration file..."
cat > $GRUB_DIR/grub.cfg <<EOF
set default=0
set timeout=5

menuentry "Custom Linux Debug" {
    echo "Loading kernel..."
    linux /boot/vmlinuz rw console=tty0
    
    echo "Loading initramfs..."
    initrd /boot/initramfs.gz
    
    echo "Booting system..."
}
EOF
echo "GRUB configuration created."

# Set up the bootable ISO structure
echo "Setting up the bootable ISO structure..."

# Install GRUB to the boot directory
echo "Running grub-mkrescue to create the bootable ISO..."
grub-mkrescue -o $ISO_OUTPUT $OUTPUT_DIR

# Output the final bootable ISO file
echo "Bootable ISO created at $ISO_OUTPUT"

# Cleanup the working directories
echo "Cleaning up the working directories..."
rm -rf $OUTPUT_DIR
echo "Cleanup complete."
