#!/bin/bash

# Get the script's directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Default output file name
OUTPUT_FILE="$SCRIPT_DIR/initramfs.cpio.gz"
MOUNT_POINTS=() # To track mounted filesystems

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
  echo "The <Dockerfile_path> argument must specify the respective parent directory as the build context."
  echo "Example: ./mycontext/Dockerfile"
  echo
}

# Cleanup function to unmount and clean up resources
cleanup() {
  echo "Cleanup: Restoring system state..."

  # Unmount any mounted filesystems
  for mp in "${MOUNT_POINTS[@]}"; do
    if mountpoint -q "$mp"; then
      echo "Unmounting $mp..."
      umount "$mp" || echo "Failed to unmount $mp"
    fi
  done

  # Remove Docker container if it exists
  if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "Removing Docker container: $CONTAINER_NAME..."
    docker rm -f "$CONTAINER_NAME"
  fi

  echo "Cleanup completed."
}

# Trap signals and exit to invoke cleanup
trap cleanup EXIT INT TERM

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

# Clear the working directory at the beginning
if [ -d "$WORK_DIR" ]; then
  echo "Cleaning up existing working directory: $WORK_DIR"
  rm -rf "$WORK_DIR"
fi

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

# Extract initial commands and user from the Dockerfile
CMD_COMMAND=$(docker inspect --format='{{json .Config.Cmd}}' "$IMAGE_NAME" | jq -r 'join(" ")')
ENTRYPOINT_COMMAND=$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMAGE_NAME" | jq -r 'join(" ")')
DEFAULT_USER=$(docker inspect --format='{{.Config.User}}' "$IMAGE_NAME")

# Set defaults if no CMD or ENTRYPOINT is found
if [ -z "$ENTRYPOINT_COMMAND" ]; then
  RUN_COMMAND="$CMD_COMMAND"
else
  RUN_COMMAND="$ENTRYPOINT_COMMAND $CMD_COMMAND"
fi

if [ -z "$DEFAULT_USER" ]; then
  DEFAULT_USER="root"
fi

# Create and start the container
echo "Creating container: $CONTAINER_NAME"
docker create --name "$CONTAINER_NAME" "$IMAGE_NAME"

# Export the filesystem of the container
echo "Exporting the filesystem of the container..."
docker export "$CONTAINER_NAME" -o "$WORK_DIR/$IMAGE_NAME.tar"

# Extract the contents of the exported tarball
echo "Extracting the contents of the exported tarball..."
mkdir "$WORK_DIR/$FS_DIR"
tar xf "$WORK_DIR/$IMAGE_NAME.tar" -C "$WORK_DIR/$FS_DIR"

# Copy the filesystem to a 'root' directory
echo "Copying the filesystem to the root directory..."
mkdir -p "$WORK_DIR/$ROOT_DIR"
cp -r "$WORK_DIR/$FS_DIR"/* "$WORK_DIR/$ROOT_DIR/"

# Create necessary folders (proc, sys, tmp, dev)
echo "Creating necessary folders (proc, sys, tmp, dev)..."
mkdir -p "$WORK_DIR/$ROOT_DIR/proc" "$WORK_DIR/$ROOT_DIR/sys" "$WORK_DIR/$ROOT_DIR/tmp" "$WORK_DIR/$ROOT_DIR/dev"

# Add init script to the root filesystem
echo "Adding init script to the root filesystem..."
cat << EOF > "$WORK_DIR/$ROOT_DIR/init"
#!/bin/sh

set -x

echo "Starting the init script" > /dev/console

# Mount filesystems
echo "Mounting /proc..." > /dev/console
mount -t proc none /proc || echo "Failed to mount /proc" > /dev/console

echo "Mounting /sys..." > /dev/console
mount -t sysfs none /sys || echo "Failed to mount /sys" > /dev/console

echo "Mounting /dev..." > /dev/console
mount -t devtmpfs none /dev || echo "Failed to mount /dev" > /dev/console

# Check required directories
echo "Creating /tmp..." > /dev/console
mkdir -p /tmp || echo "Failed to create /tmp" > /dev/console

echo "Setting permissions for /tmp..." > /dev/console
chmod 1777 /tmp || echo "Failed to chmod /tmp" > /dev/console

# Debugging for command execution
echo "Prepared to execute the initial command." > /dev/console
echo "Default user: $DEFAULT_USER" > /dev/console
echo "Run command: $RUN_COMMAND" > /dev/console

# Switch to the specified user and execute the command
if [ "$DEFAULT_USER" != "root" ]; then
  echo "Switching to user: $DEFAULT_USER" > /dev/console
  su -s /bin/sh "$DEFAULT_USER" -c "$RUN_COMMAND" < /dev/console > /dev/console 2>&1 &
  EXIT_STATUS=$?
  echo "Command exited with status $EXIT_STATUS" > /dev/console
else
  echo "Executing as root: $RUN_COMMAND" > /dev/console
  $RUN_COMMAND < /dev/console > /dev/console 2>&1 &
fi

EXIT_STATUS=$?
echo "Final command exited with status $EXIT_STATUS" > /dev/console

# Keep the init script running to prevent kernel panic
echo "Init script completed." > /dev/console
exec /bin/sh < /dev/console > /dev/console 2>&1
EOF

chmod +x "$WORK_DIR/$ROOT_DIR/init"

# Package the root filesystem into a compressed initramfs
echo "Packaging the filesystem into an initramfs archive..."
(cd "$WORK_DIR/$ROOT_DIR" && find . | cpio -H newc -o | gzip > "$OUTPUT_FILE")

echo "Initramfs archive created at $OUTPUT_FILE"
