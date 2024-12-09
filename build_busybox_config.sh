#!/bin/bash

# Get the directory of the script to handle relative paths
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/busybox.config"
BUSYBOX_DIR="$SCRIPT_DIR/busybox_repo"

# Function to display usage information
usage() {
    echo "Usage: $0 [-c config_path] [-w workdir]"
    echo ""
    echo "This script generates a BusyBox configuration by first running 'make allnoconfig'"
    echo "and then applying the settings from a custom configuration file."
    echo ""
    echo "Options:"
    echo "  -c    Path to the custom busybox.config file (default: $SCRIPT_DIR/busybox.config)"
    echo "  -w    Path to the BusyBox source directory (default: $SCRIPT_DIR/busybox)"
    echo "  -h, --help   Display this help message"
    echo ""
    exit 1
}

# Parse the command-line options
while getopts "c:w:h-:" opt; do
  case $opt in
    c)
      CONFIG_FILE=$(readlink -f "$OPTARG")
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

# Ensure the BusyBox directory exists
if [ ! -d "$BUSYBOX_DIR" ]; then
    echo "Error: BusyBox directory $BUSYBOX_DIR not found."
    exit 1
fi

# Step 1: Change to the BusyBox directory
cd "$BUSYBOX_DIR" || { echo "Error: Unable to access BusyBox directory."; exit 1; }
echo "Changed to BusyBox directory: $(pwd)"

# Step 2: Generate allnoconfig
echo "Generating allnoconfig..."
make allnoconfig || { echo "Error: Failed to run 'make allnoconfig'."; exit 1; }

# Step 3: Update the .config file with values from the custom configuration
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

# Final message
echo "Configuration updated successfully."
echo "You can now run 'make' to build BusyBox."
