#!/bin/bash

# Get the directory of the script to handle relative paths
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Define the BusyBox repository URL and local directory
BUSYBOX_REPO="https://github.com/mirror/busybox.git"
BUSYBOX_DIR="$SCRIPT_DIR/busybox_repo"
CONFIG_FILE="$SCRIPT_DIR/busybox.config"
OUTPUT_DIR="$SCRIPT_DIR"  # Default output directory is the script's directory
OUTPUT_FILE="busybox"     # Default output file name

# Function to display usage information
usage() {
    echo "Usage: $0 [-c config_path] [-o output_path] [-w workdir]"
    echo ""
    echo "This script clones or updates the BusyBox repository, configures it,"
    echo "applies custom settings from a configuration file, compiles BusyBox,"
    echo "and copies the resulting binary to a specified output directory."
    echo ""
    echo "Options:"
    echo "  -c    Path to the custom busybox.config file (default: $SCRIPT_DIR/busybox.config)"
    echo "  -o    Specify the output path for the compiled BusyBox binary (default: ./busybox)"
    echo "  -w    Path to the BusyBox source directory (default: $SCRIPT_DIR/busybox_repo)"
    echo "  -h, --help   Display this help message"
    echo ""
    exit 1
}

# Parse the command-line options
while getopts "c:o:w:h-:" opt; do
  case $opt in
    c)
      CONFIG_FILE=$(readlink -f "$OPTARG")
      ;;
    o)
      OUTPUT_DIR=$(dirname "$OPTARG")
      OUTPUT_FILE=$(basename "$OPTARG")
      ;;
    w)
      BUSYBOX_DIR=$(readlink -f "$OPTARG")
      ;;
    h|?|-h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# Ensure the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Step 1: Clone or update the BusyBox repository
echo "Pulling latest changes from the BusyBox repository..."
if [ ! -d "$BUSYBOX_DIR" ]; then
    echo "Cloning the BusyBox repository..."
    git clone "$BUSYBOX_REPO" "$BUSYBOX_DIR"
else
    cd "$BUSYBOX_DIR" || exit
    echo "Repository found. Pulling the latest changes..."
    git pull
fi

# Step 2: Change to the BusyBox directory
cd "$BUSYBOX_DIR" || { echo "Error: Unable to access BusyBox directory."; exit 1; }
echo "Changed to BusyBox directory: $(pwd)"

# Step 3: Generate allnoconfig
echo "Generating allnoconfig..."
make allnoconfig || { echo "Error: Failed to run 'make allnoconfig'."; exit 1; }

# Step 4: Apply custom configuration
echo "Updating .config with values from $CONFIG_FILE..."
while IFS= read -r line; do
    # Skip empty lines or comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    
    # Extract variable and value
    if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
        VAR="${BASH_REMATCH[1]}"
        VAL="${BASH_REMATCH[2]}"
        
        # Update or append to .config
        if grep -q "^$VAR=" .config; then
            sed -i "s/^$VAR=.*/$VAR=$VAL/" .config
        else
            echo "$VAR=$VAL" >> .config
        fi
    fi
done < "$CONFIG_FILE"

# Step 5: Configure BusyBox for static build (if not already set in .config)
echo "Configuring BusyBox for static build..."
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
sed -i 's/CONFIG_STATIC=n/CONFIG_STATIC=y/' .config

# Step 6: Compile BusyBox
echo "Starting the BusyBox compilation process with $(nproc) jobs..."
make -j "$(nproc)" || {
  echo "Error: Build failed. Check the output above for details."
  exit 1
}

# Step 7: Copy the compiled BusyBox binary to the specified output location
echo "Copying the compiled BusyBox binary to $OUTPUT_DIR/$OUTPUT_FILE..."
mkdir -p "$OUTPUT_DIR"
cp busybox "$OUTPUT_DIR/$OUTPUT_FILE"

# Final message
echo "BusyBox build completed successfully!"
echo "The binary has been installed to $OUTPUT_DIR/$OUTPUT_FILE"
