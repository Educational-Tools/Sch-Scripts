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

# --- Global Variables ---
REVERT=false

# Define variables
DEST_ETC="/etc"
DEST_LIB="/lib"
DEST_SHARE="/usr/share"
DEST_SBIN="/usr/sbin"
DEST_SCRIPTS="/usr/share/sch-scripts"

PROJECT_ETC="etc"
PROJECT_LIB="lib"
PROJECT_SHARE="share"
PROJECT_SBIN="sbin"
PROJECT_SCRIPTS="share/sch-scripts"

PACKAGE_ROOT="/usr/share/sch-scripts"

# Dependencies
DEPENDENCIES="python3 python3-gi python3-pip epoptes openssh-server bindfs iputils-arping libgtk-3-0 librsvg2-common policykit-1 util-linux dnsmasq ethtool ltsp net-tools nfs-kernel-server p7zip-rar squashfs-tools"

# Error messages
ERROR_INSTALL_DEPENDENCIES="Error: Failed to install dependencies."
ERROR_MOVE_FILES="Error: Failed to move files to their destinations."
ERROR_REVERT_FILES="Error: Failed to revert files to their original destinations."
ERROR_REMOVE_DEPENDENCIES="Error: Failed to remove dependencies."
ERROR_CONFIGURE="Error: Failed to configure sch-scripts."
ERROR_START_SERVICES="Error: Failed to start required services."

# Backup and Revert Functions

backup_file() {
    local dest_dir="$1"
    local source_file="$2"
    local dest_file="$dest_dir/$(basename "$source_file")"
    local bak_file="$dest_file.bak"

    # Check if the destination file exists
    if [[ -f "$dest_file" ]]; then
        echo "Backing up: $dest_file to $bak_file"
        mv "$dest_file" "$bak_file"
    fi
}

revert_file() {
    local dest_dir="$1"
    local source_file="$2"
    local file_path="$dest_dir/$(basename "$source_file")"
    local bak_file="$file_path.bak"

    if [[ -f "$bak_file" ]]; then
        echo "Restoring: $file_path from $bak_file"
        mv "$bak_file" "$file_path"
    else
        rm -f "$file_path"
    fi
}

# Install function (for directories and files)

install_path() {
    local source_path="$1"
    local dest_path="$2"

    if [[ -d "$source_path" ]]; then
        # It's a directory, use cp -r to copy recursively
        mkdir -p "$dest_path/$(basename "$source_path")"
        cp -r "$source_path"/* "$dest_path/$(basename "$source_path")" || {
          echo "Failed to copy directory."
          exit 1
        }
    else
        # It's a file
        install -o root -g root -m 644 "$source_path" "$dest_path"
    fi
}

#Wait for apt lock
wait_apt_lock() {
    while ! flock -w 10 /var/lib/dpkg/lock-frontend -c :; do
        echo "Waiting for apt lock to be released..."
        sleep 1
    done
}

#install-dependencies
install_dependencies() {
    wait_apt_lock
    apt-get update
    apt-get install -y -o APT::Acquire::http::Pipeline-Depth=0 -o APT::Acquire::Retries=10 $DEPENDENCIES || {
        echo "$ERROR_INSTALL_DEPENDENCIES"
        exit 1
    }
}

#remove-dependencies
remove_dependencies() {
    apt-get remove  --allow-remove-essential $DEPENDENCIES || {
        echo "$ERROR_REMOVE_DEPENDENCIES"
        exit 1
    }
}

#ltsp configurations
configure_ltsp() {
    command -v ltsp >/dev/null || return 0
    mkdir -p /etc/ltsp
    if [ ! -f /etc/ltsp/ltsp.conf ]; then
        install -o root -g root -m 0660 /usr/share/sch-scripts/ltsp.conf /etc/ltsp/ltsp.conf
    fi
    rm -f /etc/dnsmasq.d/ltsp-server-dnsmasq.conf
    test -f /etc/dnsmasq.d/ltsp-dnsmasq.conf || ltsp dnsmasq
    test -f /etc/exports.d/ltsp-nfs.exports || ltsp nfs
}

#teachers configuration
configure_teachers() {
    local before after old_ifs teacher teacher_home

    # Create "teachers" group and add the administrator to epoptes,teachers
    test -f /etc/default/shared-folders && . /etc/default/shared-folders
    test -n "$TEACHERS" || return 0
    # If the group doesn't exist, create it and add the administrator
    if ! getent group "$TEACHERS" >/dev/null; then
        addgroup --system --gid 685 "$TEACHERS"
        detect_administrator
    fi
    # TODO: implement what we discussed: https://gitlab.com/sch-scripts/sch-scripts/-/issues/12
    # If the group exists, ensure the administrator is there
    if getent group "$TEACHERS" >/dev/null; then
        # Create a default "teachers" home:
        teacher_home="/home/$TEACHERS"
        mkdir -p "$teacher_home"
        detect_administrator
        if ! groups "$administrator" | grep -wq "$TEACHERS"; then
            # administrator was not in group, put it there now
            adduser "$administrator" "$TEACHERS"
        fi
    fi
}

#common.sh functions
# Detect the user with id 1000 (the first normal user):
detect_administrator() {
    # shellcheck disable=SC2034
    administrator="$(id -u 1000 >/dev/null && id -un 1000)"
}

#start_shared_folders service
start_shared_folders_service() {
    echo "Starting shared-folders.service..."
    systemctl start shared-folders.service || {
        echo "Error: Failed to start shared-folders.service."
        exit 1
    }
    echo "shared-folders.service started successfully."
    systemctl status shared-folders.service
}

#This is the equivalent of cmdline in the old initial-setup.sh
prompt() {
    local conf _dummy

    conf=/var/lib/sch-scripts/initial-setup.conf
    if [ "$1" != "--no-prompt" ]; then
        printf "Θα εκτελεστούν κάποιες ενέργειες αρχικοποίησης των sch-scripts.\nΠατήστε [Enter] για συνέχεια ή Ctrl+C για εγκατάλειψη: "
        # shellcheck disable=SC2034
        read -r _dummy
    fi
    mkdir -p "${conf%/*}"
    printf \
        "# This file is regenerated when /usr/share/sch-scripts/initial-setup.sh runs.\n\n# Remember the last version ran, to answer the --check parameter:\nLAST_VERSION=%s\n" "$_VERSION" >"$conf"
}

#install files
install_files() {
    echo "Moving files to their destinations..."

    # Create directories
    mkdir -p "$DEST_ETC" "$DEST_LIB" "$DEST_SHARE" "$DEST_SBIN" "$DEST_SCRIPTS"

    # Move files
    for file in "$PROJECT_ETC"/*; do
        backup_file "$DEST_ETC" "$file"
        install_path "$file" "$DEST_ETC" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_LIB"/*; do
        backup_file "$DEST_LIB" "$file"
        install_path "$file" "$DEST_LIB" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_SHARE"/*; do
        backup_file "$DEST_SHARE" "$file"
        install_path "$file" "$DEST_SHARE" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the sch-scripts.py
    for file in "$PROJECT_SCRIPTS"/*; do
        backup_file "$DEST_SCRIPTS" "$file"
        install_path "$file" "$DEST_SCRIPTS" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_SBIN"/*; do
        backup_file "$DEST_SBIN" "$file"
        install_path "$file" "$DEST_SBIN" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done

    echo "Files moved successfully."
}

#revert files
revert_files() {
    echo "Reverting file changes..."

    # Revert files
    for file in "$PROJECT_ETC"/*; do
        revert_file "$DEST_ETC" "$file"
    done
    for file in "$PROJECT_LIB"/*; do
        revert_file "$DEST_LIB" "$file"
    done
    for file in "$PROJECT_SHARE"/*; do
        revert_file "$DEST_SHARE" "$file"
    done
    for file in "$PROJECT_SCRIPTS"/*; do
        revert_file "$DEST_SCRIPTS" "$file"
    done
    for file in "$PROJECT_SBIN"/*; do
        revert_file "$DEST_SBIN" "$file"
    done

    echo "File changes reverted successfully."
}

# Install function
install_sch() {
    echo "Installing sch-scripts..."
    # Install dependencies
    install_dependencies
    echo "Dependencies installed successfully."
    #install files
    install_files
    # This is the prompt
    prompt "$@"
    #This are the configurations
    configure_ltsp
    configure_teachers
    start_shared_folders_service

    echo "Installation of sch-scripts completed successfully!"
}

#remove function
remove_sch() {
    echo "Removing sch-scripts..."
    #Remove dependencies
    remove_dependencies
    echo "Dependencies removed successfully."
    #revert files
    revert_files

    echo "Revert of sch-scripts completed successfully!"
}

# This is the main
main() {
    
    if [[ "$1" == "-u" ]]; then
        REVERT=true
    fi
    echo "Value of REVERT inside main: $REVERT"
    
    if [[ $REVERT == false ]]; then
        install_sch "$@"
    else
        remove_sch
    fi

}
#Execute the main
main "$@"

exit 0
