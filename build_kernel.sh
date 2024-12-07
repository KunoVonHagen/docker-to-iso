#!/bin/bash

# Get the directory of the script to handle relative paths
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Define the kernel repository URL and local directory
KERNEL_REPO="https://github.com/torvalds/linux.git"
KERNEL_DIR="$SCRIPT_DIR/linux"
OUTPUT_DIR="$SCRIPT_DIR"  # Default output directory is the script's directory
OUTPUT_FILE="bzImage"     # Default output file name

# Function to display usage information
usage() {
    echo "Usage: $0 [-o output_path]"
    echo ""
    echo "This script clones or updates the Linux kernel repository, compiles the kernel,"
    echo "and copies the resulting bzImage to a specified output directory."
    echo ""
    echo "Options:"
    echo "  -o    Specify the output path for the compiled kernel bzImage (default: ./bzImage)"
    echo "  -h, --help   Display this help message"
    echo ""
    exit 1
}

# Parse the command-line options
while getopts "o:h-:" opt; do
  case $opt in
    o)
      # Split the output option into directory and file name
      OUTPUT_DIR=$(dirname "$OPTARG")
      OUTPUT_FILE=$(basename "$OPTARG")
      ;;
    h|?|-h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# Step 1: Git pull the Linux kernel repository
echo "Pulling latest changes from the Linux kernel repository..."
if [ ! -d "$KERNEL_DIR" ]; then
    echo "Cloning the Linux kernel repository..."
    git clone $KERNEL_REPO $KERNEL_DIR
else
    cd $KERNEL_DIR
    echo "Repository found. Pulling the latest changes..."
    git pull
fi

# Step 2: Copy the kernel.config file and cd into the kernel directory
echo "Copying the kernel.config file into the Linux directory..."
cp "$SCRIPT_DIR/kernel.config" "$KERNEL_DIR/.config"
cd "$KERNEL_DIR"
echo "Changed to kernel directory: $(pwd)"

# Step 3: Compile the kernel
echo "Starting the kernel compilation process with $(nproc) jobs..."
make -j $(nproc)

# Step 4: Copy the compiled bzImage to the specified output location
echo "Copying the compiled kernel bzImage to $OUTPUT_DIR/$OUTPUT_FILE..."
cp arch/x86/boot/bzImage "$OUTPUT_DIR/$OUTPUT_FILE"

cd "$SCRIPT_DIR"

echo "Kernel build completed successfully!"
