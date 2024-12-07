#!/bin/bash

# Check if the Linux kernel repository already exists
echo "Checking if the Linux kernel repository exists..."
if [ ! -d "linux" ]; then
    echo "Cloning the Linux kernel repository..."
    # Clone the Linux kernel repository
    git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
else
    echo "Linux kernel repository already exists. Skipping clone."
fi

cd linux

# Configure the kernel with minimal options for initramfs
echo "Running 'make allnoconfig' to configure the kernel with default options..."
make allnoconfig

# Modify the .config file to enable the necessary options
echo "Modifying .config to enable the necessary options..."

# Enabling 64-bit kernel
sed -i 's/^# CONFIG_X86_64 is not set/CONFIG_X86_64=y/' .config

# Enabling initramfs support
sed -i 's/^# CONFIG_BLK_DEV_INITRD is not set/CONFIG_BLK_DEV_INITRD=y/' .config
sed -i 's/^# CONFIG_INITRAMFS_SOURCE is not set/CONFIG_INITRAMFS_SOURCE=""/' .config
sed -i 's/^# CONFIG_INITRAMFS_INITRD is not set/CONFIG_INITRAMFS_INITRD=y/' .config

# Enabling printk support
sed -i 's/^# CONFIG_PRINTK is not set/CONFIG_PRINTK=y/' .config

# Enabling ELF support for binaries
sed -i 's/^# CONFIG_ELF_CORE is not set/CONFIG_ELF_CORE=y/' .config
sed -i 's/^# CONFIG_KERNEL_XZ is not set/CONFIG_KERNEL_XZ=y/' .config

# Enabling devtmpfs filesystem support
sed -i 's/^# CONFIG_DEVTMPFS is not set/CONFIG_DEVTMPFS=y/' .config
sed -i 's/^# CONFIG_SYSFS is not set/CONFIG_SYSFS=y/' .config

# Enabling /proc and /sys file system support
sed -i 's/^# CONFIG_PROC_FS is not set/CONFIG_PROC_FS=y/' .config
sed -i 's/^# CONFIG_DEVFS is not set/CONFIG_DEVFS=y/' .config

# Enabling TTY support and serial drivers for the console
sed -i 's/^# CONFIG_TTY is not set/CONFIG_TTY=y/' .config
sed -i 's/^# CONFIG_SERIAL_8250 is not set/CONFIG_SERIAL_8250=y/' .config
sed -i 's/^# CONFIG_SERIAL_8250_CONSOLE is not set/CONFIG_SERIAL_8250_CONSOLE=y/' .config

# Ensuring no prompt for missing options
sed -i 's/^# CONFIG_.* is not set/CONFIG_&=y/' .config
sed -i 's/^.* CONFIG_.* is not set/CONFIG_&=y/' .config

echo "Kernel configuration updated."


# Build the kernel
echo "Starting the kernel build process..."
make -j$(nproc)

echo "Kernel build completed."

# Copy the built kernel (bzImage) to the parent directory
echo "Copying the built kernel (bzImage) to the parent directory..."
cp arch/x86_64/boot/bzImage ..

echo "Kernel bzImage is ready!"
