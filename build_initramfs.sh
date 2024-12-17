#!/bin/bash

# Get the script's directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Default output file name
OUTPUT_FILE="$SCRIPT_DIR/initramfs.cpio.gz"

# Display the help message
show_help() {
  echo "Usage: $0 [-o output_file] <Dockerfile_path>"
  echo
  echo "This script builds a Docker image from the specified Dockerfile, exports the container's"
  echo "filesystem, and packages it into a compressed initramfs (initrd) image."
  echo
  echo "Options:"
  echo "  -o <output_file>  Specify the output file name for the initramfs (default: initramfs.cpio.gz)"
  echo "  -h, --help        Display this help message"
  echo
  echo "The <Dockerfile_path> argument must include the build context as a parent directory."
  echo "Example: ./mycontext/Dockerfile"
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
      echo "Invalid option or missing argument"
      show_help
      exit 1
      ;;
  esac
done

# Check if the Dockerfile path is provided as an argument
shift $((OPTIND - 1))
if [ -z "$1" ]; then
    echo "Error: Please provide the path to the Dockerfile."
    show_help
    exit 1
fi

DOCKERFILE_PATH=$(readlink -f "$1")

# Validate the resolved path
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile not found at $DOCKERFILE_PATH."
    exit 1
fi

# Extract the build context and Dockerfile name
BUILD_CONTEXT=$(dirname "$DOCKERFILE_PATH")
DOCKERFILE_NAME=$(basename "$DOCKERFILE_PATH")

echo "Resolved build context: $BUILD_CONTEXT"
echo "Dockerfile name: $DOCKERFILE_NAME"

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

# Build the Docker image using the provided Dockerfile and context
echo "Building Docker image: $IMAGE_NAME with context $BUILD_CONTEXT and Dockerfile $DOCKERFILE_NAME"
docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT"

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
echo "Creating necessary folders (proc, sys, tmp, dev)..."
mkdir -p "$WORK_DIR/$ROOT_DIR/proc" "$WORK_DIR/$ROOT_DIR/sys"
mkdir -p "$WORK_DIR/$ROOT_DIR/tmp" "$WORK_DIR/$ROOT_DIR/dev"

# Create device nodes outside of chroot for robustness
echo "Creating device nodes..."

# Helper function to create device nodes safely
create_device_node() {
  local path="$1"
  local type="$2"
  local major="$3"
  local minor="$4"

  if [ -e "$path" ]; then
    if [ ! -c "$path" ]; then
      echo "Removing non-character device file: $path"
      rm -f "$path"
    else
      echo "Device node already exists: $path"
      return
    fi
  fi

  echo "Creating device node: $path"
  mknod -m 666 "$path" "$type" "$major" "$minor"
}

# Create console, null, and tty device nodes
create_device_node "$WORK_DIR/$ROOT_DIR/dev/console" c 5 1
create_device_node "$WORK_DIR/$ROOT_DIR/dev/null" c 1 3
create_device_node "$WORK_DIR/$ROOT_DIR/dev/tty" c 5 0

# Verify device nodes were created
if [ ! -c "$WORK_DIR/$ROOT_DIR/dev/console" ] || \
   [ ! -c "$WORK_DIR/$ROOT_DIR/dev/null" ] || \
   [ ! -c "$WORK_DIR/$ROOT_DIR/dev/tty" ]; then
    echo "Error: Failed to create necessary device nodes."
    exit 1
fi

# Add init script
echo "Adding init script..."
cat <<'EOF' > "$WORK_DIR/$ROOT_DIR/init"
#!/bin/sh

set -x

echo "Starting the init script" > /dev/console

# Mount filesystems
mount -t proc none /proc || echo "Failed to mount /proc" > /dev/console
mount -t sysfs none /sys || echo "Failed to mount /sys" > /dev/console
mount -t devtmpfs none /dev || echo "Failed to mount /dev" > /dev/console

# Check required directories
mkdir -p /tmp || echo "Failed to create /tmp" > /dev/console
chmod 1777 /tmp || echo "Failed to chmod /tmp" > /dev/console

# Inform the user about successful initialization
echo "Initialization complete!" > /dev/console
echo "Boot took $(cut -d' ' -f1 /proc/uptime) seconds" > /dev/console

# Launch a shell for user interaction
exec /bin/sh < /dev/console > /dev/console 2>&1
EOF

# Make the init script executable
chmod +x "$WORK_DIR/$ROOT_DIR/init"
echo "Init script made executable."

echo "Packaging the filesystem into initrd image..."
# Package the filesystem into an initrd image (cpio.gz format)
cd "$WORK_DIR/$ROOT_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$OUTPUT_FILE"
if [ $? -eq 0 ]; then
    echo "Initrd successfully created: $OUTPUT_FILE"
else
    echo "Error: Failed to create initrd image."
    exit 1
fi
cd "$SCRIPT_DIR"

# Clean up the working directory
#echo "Cleaning up the working directory..."
#rm -rf "$WORK_DIR"
#if [ $? -eq 0 ]; then
#    echo "Working directory cleaned up successfully."
#else
#    echo "Warning: Failed to clean up the working directory."
#fi

echo "$OUTPUT_FILE is ready!"
