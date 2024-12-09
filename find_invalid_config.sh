#!/bin/bash

# Paths to input and valid configuration files
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CUSTOM_CONFIG="$SCRIPT_DIR/busybox.config"
VALID_CONFIG="$SCRIPT_DIR/.config"

# Ensure the necessary files exist
if [ ! -f "$CUSTOM_CONFIG" ]; then
    echo "Error: Custom configuration file not found at $CUSTOM_CONFIG."
    exit 1
fi

if [ ! -f "$VALID_CONFIG" ]; then
    echo "Error: Valid configuration file not found at $VALID_CONFIG."
    echo "Please generate a .config using 'make allnoconfig' or 'make menuconfig'."
    exit 1
fi

# Generate a mapping of valid options
declare -A valid_options
while IFS= read -r line; do
    if [[ "$line" =~ ^CONFIG_([A-Z0-9_]+)= ]]; then
        option="${BASH_REMATCH[1]}"
        valid_options["CONFIG_$option"]=1
    fi
done < "$VALID_CONFIG"

# Check for invalid variables in the custom configuration
echo "Invalid variables found in $CUSTOM_CONFIG:"
found_invalid=0
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ -z "$line" || "$line" == \#* ]]; then
        continue
    fi

    # Extract variable
    if [[ "$line" =~ ^(CONFIG_[A-Z0-9_]+)= ]]; then
        var="${BASH_REMATCH[1]}"

        # Check if the variable is not in the valid options
        if [[ ! ${valid_options[$var]+_} ]]; then
            echo "$var"
            found_invalid=1
        fi
    fi
done < "$CUSTOM_CONFIG"

if [ "$found_invalid" -eq 0 ]; then
    echo "No invalid variables found."
fi
