#!/bin/bash

# Check if correct number of arguments is passed
if [ $# -ne 2 ]; then
    echo "Usage: $0 <kernel> <initramfs.gpio.gz>"
    exit 1
fi

KERNEL=$1
INITRAMFS=$2
OUTPUT_DIR="iso"
GRUB_DIR="$OUTPUT_DIR/boot/grub"
MOUNT_DIR="$OUTPUT_DIR/mnt"
ISO_OUTPUT="bootable.iso"

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

menuentry "Custom Linux" {
	echo "Loading kernel..." 
    linux /boot/vmlinuz root=/dev/ram0 rw
    
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
