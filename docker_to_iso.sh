#!/bin/bash

# Check if the script is NOT run as root or with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    exit 1
fi

# Get the directory of the script to handle relative paths
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Log file
LOG_FILE="/tmp/bootable_iso_build.log"

# Show help message
show_help() {
    echo "Usage: $0 <Dockerfile_path> [options]"
    echo
    echo "This script converts a Dockerfile into a bootable ISO."
    echo
    echo "Options:"
    echo "  <Dockerfile_path>        Path to the Dockerfile"
    echo "  -o <ISO_output_path>     Optional path to output the ISO (default: bootable.iso)"
    echo "  --build-kernel           Build the kernel"
    echo "  --build-busybox          Build BusyBox"
    echo "  -h, --help               Show this help message"
    exit 0
}

# Function to execute commands and handle errors
execute_with_logging() {
    local summary_message="$1"
    local command="$2"
    echo "$summary_message"
    $command > "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Command failed. See log for details."
        echo "Displaying log:"
        cat "$LOG_FILE"
        exit 1
    fi
}

# Parse options
BUILD_KERNEL=false
BUILD_BUSYBOX=false

# First, check for flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --build-kernel)
            BUILD_KERNEL=true
            shift
            ;;
        --build-busybox)
            BUILD_BUSYBOX=true
            shift
            ;;
        -o)
            ISO_OUTPUT_PATH=$2
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            if [ -z "$DOCKERFILE_PATH" ]; then
                DOCKERFILE_PATH=$1
            else
                echo "Error: Multiple Dockerfile paths detected. Only one path is allowed."
                exit 1
            fi
            shift
            ;;
    esac
done

# Ensure Dockerfile path is provided
if [ -z "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile path is required."
    show_help
fi

# Check if the Dockerfile exists
if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile '$DOCKERFILE_PATH' not found."
    exit 1
fi

# Build kernel if option is set or kernel is missing
if [ "$BUILD_KERNEL" = true ]; then
    execute_with_logging "Building kernel..." "$SCRIPT_DIR/build_kernel.sh"
    echo "Kernel build completed."
fi

if [ ! -f "bzImage" ]; then
	echo "Error: Kernel file 'bzImage' not found. Use --build-kernel to build it."
	exit 1
fi

# Build BusyBox if option is set or BusyBox executable is missing
if [ "$BUILD_BUSYBOX" = true ]; then
    execute_with_logging "Building BusyBox..." "$SCRIPT_DIR/build_busybox.sh"
    echo "BusyBox build completed."
fi

if [ ! -f "busybox" ]; then
    echo "Error: BusyBox executable not found. Use --build-busybox to build it."
    exit 1
fi

# Build initramfs
execute_with_logging "Building initramfs from Dockerfile..." "$SCRIPT_DIR/build_initramfs.sh $DOCKERFILE_PATH"
echo "Initramfs build completed."

# Test initramfs file
execute_with_logging "Testing initramfs file..." "$SCRIPT_DIR/test_initramfs_file.sh initramfs.cpio.gz"
echo "Initramfs file test passed."

# Build ISO
if [ -n "$ISO_OUTPUT_PATH" ]; then
    execute_with_logging "Building ISO with output path '$ISO_OUTPUT_PATH'..." "$SCRIPT_DIR/build_iso.sh -o $ISO_OUTPUT_PATH bzImage initramfs.cpio.gz"
else
    ISO_OUTPUT_PATH="$(pwd)/bootable.iso"
    execute_with_logging "Building ISO with default output path 'bootable.iso'..." "$SCRIPT_DIR/build_iso.sh bzImage initramfs.cpio.gz"
fi
echo "ISO build completed. Output saved to '$ISO_OUTPUT_PATH'."
