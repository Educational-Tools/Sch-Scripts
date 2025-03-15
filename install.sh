#!/bin/bash

# --- Setup and Error Handling ---

# Check if running with sudo, prompt for password if needed
if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges. Please enter your sudo password:"
    sudo true || {
        echo "Error: Failed to obtain root privileges."
        exit 1
    }
    sudo bash "$0" "$@" # Re-execute script with sudo
    exit $? # Exit with the same exit code as the re-executed script
fi

# Set -e for immediate exit on errors
set -e

# Check for revert argument
REVERT=false
if [[ "$1" == "-u" ]]; then
    REVERT=true
    shift # Remove -u from argument list
fi

# Define variables
DEST_ETC="/etc"
DEST_LIB="/lib"
DEST_SHARE="/usr/share"
DEST_SBIN="/usr/sbin"

PACKAGE_ROOT="/usr/share/sch-scripts"

# Dependencies
DEPENDENCIES="python3 python3-gi python3-pip epoptes openssh-server bindfs iputils-arping libgtk-3-0 librsvg2-common policykit-1 util-linux dnsmasq ethtool ltsp net-tools nfs-kernel-server p7zip-rar squashfs-tools"

# Error messages
ERROR_INSTALL_DEPENDENCIES="Error: Failed to install dependencies."
ERROR_MOVE_FILES="Error: Failed to move files to their destinations."
ERROR_REVERT_FILES="Error: Failed to revert files to their original destinations."
ERROR_REMOVE_DEPENDENCIES="Error: Failed to remove dependencies."
ERROR_RUN_INITIAL_SETUP="Error: Failed to run initial setup script."
ERROR_START_SERVICES="Error: Failed to start required services."

# Backup and Revert Functions

backup_file() {
    local source_file="$1"
    local bak_file="$source_file.bak"

    # Check if the destination file exists
    if [[ -f "$source_file" ]]; then
        echo "Backing up: $source_file to $bak_file"
        mv "$source_file" "$bak_file"
    fi
}

revert_file() {
    local file_path="$1"
    local bak_file="$file_path.bak"

    if [[ -f "$bak_file" ]]; then
        echo "Restoring: $file_path from $bak_file"
        mv "$bak_file" "$file_path"
    else
        rm -f "$file_path"
    fi
}

# --- Dependency Installation/Removal ---

if [[ "$REVERT" == false ]]; then
    echo "Installing dependencies..."

    # Get number of CPU cores for parallel installation
    NUM_CORES=$(nproc)

    apt-get update

    # Install Dependencies with parallel downloads
    apt-get install -y -o APT::Acquire::http::Pipeline-Depth=0 -o APT::Acquire::Retries=10 -j"$NUM_CORES" $DEPENDENCIES || {
        echo "$ERROR_INSTALL_DEPENDENCIES"
        exit 1
    }

    echo "Dependencies installed successfully."
else
    echo "Removing dependencies..."
    apt-get remove -y $DEPENDENCIES || {
        echo "$ERROR_REMOVE_DEPENDENCIES"
        exit 1
    }
    echo "Dependencies removed successfully."
fi

# --- File Movement/Revert ---

if [[ "$REVERT" == false ]]; then
    echo "Moving files to their destinations..."

    # Create directories
    mkdir -p "$DEST_ETC" "$DEST_LIB" "$DEST_SHARE" "$DEST_SBIN"

    # Move files
    backup_file "$DEST_ETC/$(ls etc/*)"
    install -m 644 etc/* "$DEST_ETC" || { echo "$ERROR_MOVE_FILES"; exit 1; }

    backup_file "$DEST_LIB/$(ls lib/*)"
    install -m 644 lib/* "$DEST_LIB" || { echo "$ERROR_MOVE_FILES"; exit 1; }

    backup_file "$DEST_SHARE/$(ls share/*)"
    install -m 644 share/* "$DEST_SHARE" || { echo "$ERROR_MOVE_FILES"; exit 1; }

    backup_file "$DEST_SBIN/$(ls sbin/*)"
    install -m 755 sbin/* "$DEST_SBIN" || { echo "$ERROR_MOVE_FILES"; exit 1; }

    echo "Files moved successfully."
else
    echo "Reverting file changes..."

    # Revert files
    revert_file "$DEST_ETC/$(ls etc/*)"
    revert_file "$DEST_LIB/$(ls lib/*)"
    revert_file "$DEST_SHARE/$(ls share/*)"
    revert_file "$DEST_SBIN/$(ls sbin/*)"

    echo "File changes reverted successfully."
fi

# --- Configuration ---

if [[ "$REVERT" == false ]]; then
    echo "Running initial setup..."

    # Run initial-setup.sh
    /usr/share/sch-scripts/scripts/initial-setup.sh || {
        echo "$ERROR_RUN_INITIAL_SETUP"
        exit 1
    }

    echo "Initial setup completed successfully."
else
    echo "Skipping initial setup..."
fi

# --- Start services ---

if [[ "$REVERT" == false ]]; then
    echo "Starting required services..."

    # Start shared-folders.service
    systemctl start shared-folders.service || {
        echo "$ERROR_START_SERVICES"
        exit 1
    }

    echo "Required services started successfully."
else
    echo "Skipping starting services..."
fi

# --- Final Message ---

if [[ "$REVERT" == false ]]; then
    echo "Installation of sch-scripts completed successfully!"
else
    echo "Revert of sch-scripts completed successfully!"
fi

exit 0
