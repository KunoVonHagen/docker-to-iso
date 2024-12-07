#!/bin/bash

# Get the script's directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Default output file name
OUTPUT_FILE="$SCRIPT_DIR/initramfs.cpio.gz"

# Display the help message
show_help() {
  echo "Usage: $0 [-o output_file] <Dockerfile>"
  echo
  echo "This script builds a Docker image from the provided Dockerfile, exports the container's"
  echo "filesystem, and packages it into a compressed initramfs (initrd) image."
  echo
  echo "Options:"
  echo "  -o <output_file>  Specify the output file name for the initramfs (default: initramfs.cpio.gz)"
  echo "  -h, --help         Display this help message"
  echo
}

# Parse the command-line options
while getopts "o:h-:" opt; do
  case $opt in
    o)
      OUTPUT_FILE="$OPTARG"
      ;;
    h|help)
      show_help
      exit 0
      ;;
    *)
      echo "Usage: $0 [-o output_file] <Dockerfile>"
      exit 1
      ;;
  esac
done

# Check if the Dockerfile path is provided as an argument
shift $((OPTIND - 1))
if [ -z "$1" ]; then
    echo "Please provide the path to the Dockerfile."
    exit 1
fi

# Set image and container names
IMAGE_NAME="initramfs"
CONTAINER_NAME="$IMAGE_NAME-container"
FS_DIR="$IMAGE_NAME-fs"
ROOT_DIR="root"
WORK_DIR="$IMAGE_NAME-workdir"

echo "Starting cleanup of previous work..."

# Clean up the working directory
rm -rf "$WORK_DIR"

# Create a working directory to store intermediate files
mkdir -p "$WORK_DIR"
echo "Created working directory: $WORK_DIR"

# Remove any previous containers
if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "Removing previous container: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME"
fi

# Build the Docker image using the provided Dockerfile path (relative to the script directory)
echo "Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/$1" "$SCRIPT_DIR"

# Create and start the container
echo "Creating container: $CONTAINER_NAME"
docker create --name "$CONTAINER_NAME" "$IMAGE_NAME"

echo "Exporting the filesystem of the container..."
# Export the filesystem of the container
docker export "$CONTAINER_NAME" -o "$WORK_DIR/$IMAGE_NAME.tar"

echo "Extracting the contents of the exported tarball..."
# Extract the contents of the exported tarball
mkdir "$WORK_DIR/$FS_DIR"
tar xf "$WORK_DIR/$IMAGE_NAME.tar" -C "$WORK_DIR/$FS_DIR"

echo "Copying the filesystem to the root directory..."
# Copy the filesystem to a 'root' directory
mkdir -p "$WORK_DIR/$ROOT_DIR"
cp -r "$WORK_DIR/$FS_DIR"/* "$WORK_DIR/$ROOT_DIR/"

# Create necessary folders (proc, sys)
echo "Creating necessary folders (proc, sys)..."
mkdir -p "$WORK_DIR/$ROOT_DIR/proc" "$WORK_DIR/$ROOT_DIR/sys"
mkdir -p "$WORK_DIR/$ROOT_DIR/tmp"  # Ensure /tmp exists

# Remove /dev/console if it exists as a regular file, then recreate it inside chroot
echo "Checking if /dev/console exists inside chroot..."
chroot "$WORK_DIR/$ROOT_DIR" bash -c "
    if [ -e /dev/console ]; then
        echo '/dev/console exists, removing it...'
        rm -f /dev/console
    fi
    echo 'Creating /dev/console device node inside chroot...'
    mknod /dev/console c 5 1
    chmod 600 /dev/console
"

# Check if the device was created correctly
if [ -c "$WORK_DIR/$ROOT_DIR/dev/console" ]; then
    echo "/dev/console created successfully."
else
    echo "/dev/console creation failed."
    exit 1
fi

# Backup the original resolv.conf if it exists inside the chroot
if [ -f "$WORK_DIR/$ROOT_DIR/etc/resolv.conf" ]; then
    echo "Backing up existing resolv.conf in chroot..."
    cp "$WORK_DIR/$ROOT_DIR/etc/resolv.conf" "$WORK_DIR/$ROOT_DIR/etc/resolv.conf.bak"
fi

# Copy the host's resolv.conf into the chroot environment
echo "Copying host's resolv.conf to chroot environment..."
cp /etc/resolv.conf "$WORK_DIR/$ROOT_DIR/etc/resolv.conf"

echo "Creating missing /tmp directory inside chroot..."
# Ensure /tmp exists in the chroot environment and has the correct permissions
mkdir -p "$WORK_DIR/$ROOT_DIR/tmp"
chmod 1777 "$WORK_DIR/$ROOT_DIR/tmp"

# Mount host directories to provide missing dependencies
echo "Mounting host directories to provide missing dependencies..."
mount --bind /dev "$WORK_DIR/$ROOT_DIR/dev"
mount --bind /sys "$WORK_DIR/$ROOT_DIR/sys"
mount --bind /proc "$WORK_DIR/$ROOT_DIR/proc"
mount --bind /tmp "$WORK_DIR/$ROOT_DIR/tmp"

# Install wget and gnupg inside chroot
echo "Installing wget and gnupg inside chroot..."
chroot "$WORK_DIR/$ROOT_DIR" /bin/bash <<'EOF'
apt-get update
apt-get install -y wget gnupg
EOF

echo "Importing GPG keys inside the chroot..."
# Import the GPG key for the Debian repositories
chroot "$WORK_DIR/$ROOT_DIR" /bin/bash <<'EOF'
wget -qO- https://ftp-master.debian.org/keys/archive-key-11.asc | apt-key add -
EOF

echo "Updating apt in the chroot environment..."
# Try updating apt in the chroot environment with logging
chroot "$WORK_DIR/$ROOT_DIR" /bin/bash <<EOF
export DEBIAN_FRONTEND=noninteractive

echo "Starting apt-get update..."
apt-get update || echo "Warning: apt update failed"

# Install required packages
apt-get install -y debootstrap initramfs-tools busybox mount || echo "Warning: apt-get install failed"
EOF

# Restore the original resolv.conf inside the chroot, if it was backed up
if [ -f "$WORK_DIR/$ROOT_DIR/etc/resolv.conf.bak" ]; then
    echo "Restoring original resolv.conf in chroot..."
    mv "$WORK_DIR/$ROOT_DIR/etc/resolv.conf.bak" "$WORK_DIR/$ROOT_DIR/etc/resolv.conf"
fi

# Unmount host directories after installation
echo "Unmounting host directories..."
umount "$WORK_DIR/$ROOT_DIR/dev"
umount "$WORK_DIR/$ROOT_DIR/sys"
umount "$WORK_DIR/$ROOT_DIR/proc"
umount "$WORK_DIR/$ROOT_DIR/tmp"

# Add init script
echo "Adding init script..."
cat <<'EOF' > "$WORK_DIR/$ROOT_DIR/init"
#!/bin/sh

echo "Starting the init script" > /dev/ttyS0

mount -t proc none /proc
mount -t sysfs none /sys

cat <<!

Boot took $(cut -d' ' -f1 /proc/uptime) seconds

Welcome to your docker image based Linux.

!

exec /bin/sh
EOF

# Make the init script executable
chmod +x "$WORK_DIR/$ROOT_DIR/init"
echo "Init script made executable."

echo "Packaging the filesystem into initrd image..."
# Package the filesystem into an initrd image (cpio.gz format)
cd "$WORK_DIR/$ROOT_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$OUTPUT_FILE"
cd "$SCRIPT_DIR"

# Clean up the working directory
rm -rf "$WORK_DIR"
echo "Cleaned up the working directory."

echo "$OUTPUT_FILE is ready!"
