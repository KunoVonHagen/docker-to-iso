#!/bin/bash

# Determine the script's directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Check if initramfs file is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <relative_path_to_initramfs.cpio.gz>"
    exit 1
fi

# Resolve the initramfs file path based on the provided argument
INITRAMFS_PATH="$SCRIPT_DIR/$1"
WORK_DIR=$(mktemp -d)

echo "Testing initramfs at: $INITRAMFS_PATH"
echo "Using temporary directory: $WORK_DIR"
echo

# Function to print test results
print_result() {
    local test="$1"
    local status="$2"
    if [ "$status" -eq 0 ]; then
        echo "✅ $test: SUCCESS"
    else
        echo "❌ $test: FAILURE"
    fi
}

# 1. Check if initramfs file exists
test="Check if initramfs file exists"
if [ -f "$INITRAMFS_PATH" ]; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: File $INITRAMFS_PATH does not exist."
    exit 1
fi

# 2. Extract initramfs
test="Extract initramfs"
mkdir -p "$WORK_DIR/initramfs"
cd "$WORK_DIR/initramfs" || { echo "Failed to enter work directory"; exit 1; }
gzip -dc "$INITRAMFS_PATH" | cpio -idm >"$WORK_DIR/extract_log.txt" 2>&1
if [ $? -eq 0 ]; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: Extraction failed. Check $WORK_DIR/extract_log.txt for details."
    exit 1
fi

# 3. Check for the init script
test="Check for /init script"
if [ -f "$WORK_DIR/initramfs/init" ]; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: /init script missing from extracted initramfs."
fi

# 4. Check if init script is executable
test="Check if /init script is executable"
if [ -x "$WORK_DIR/initramfs/init" ]; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: /init script exists but is not executable."
fi

# 5. Check for required directories
required_dirs=(/proc /sys /dev /tmp)
for dir in "${required_dirs[@]}"; do
    test="Check for $dir directory"
    if [ -d "$WORK_DIR/initramfs$dir" ]; then
        print_result "$test" 0
    else
        print_result "$test" 1
        echo "DEBUG: $dir directory missing from extracted initramfs."
    fi
done

# 6. Check for /bin/sh
test="Check for /bin/sh"
if [ -f "$WORK_DIR/initramfs/bin/sh" ]; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: /bin/sh missing from extracted initramfs."
fi

# 7. Check if /bin/sh has required libraries
test="Check /bin/sh dependencies"
if ldd "$WORK_DIR/initramfs/bin/sh" &>/dev/null; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: /bin/sh dependencies check failed. Ensure required libraries are present."
fi

# 8. Check for /dev/console
test="Check for /dev/console"
if [ -c "$WORK_DIR/initramfs/dev/console" ]; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: /dev/console is missing or not a character device."
fi

# 9. Simulate boot with QEMU
test="Simulate boot with QEMU"
QEMU_LOG="$WORK_DIR/qemu_log.txt"
qemu-system-x86_64 \
    -kernel /boot/vmlinuz-linux \
    -initrd "$INITRAMFS_PATH" \
    -nographic \
    -append "console=ttyS0" &> "$QEMU_LOG" &
QEMU_PID=$!
sleep 5
kill $QEMU_PID &>/dev/null
if grep -q "Welcome to your docker image based Linux" "$QEMU_LOG"; then
    print_result "$test" 0
else
    print_result "$test" 1
    echo "DEBUG: QEMU simulation failed. Check the log at $QEMU_LOG for details."
fi

# Cleanup
rm -rf "$WORK_DIR"

echo
echo "All tests complete."
