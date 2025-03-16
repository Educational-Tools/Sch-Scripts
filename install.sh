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
DEST_ROOT="/usr/share/sch-scripts"
DEST_CONFIGS="/usr/share/sch-scripts/configs"
DEST_UI="/usr/share/sch-scripts/ui"
DEST_BINS="/usr/share/sch-scripts/scripts"

PROJECT_ETC="etc"
PROJECT_LIB="lib"
PROJECT_SHARE="share"
PROJECT_SBIN="sbin"
PROJECT_ROOT="share/sch-scripts"
PROJECT_CONFIGS="share/sch-scripts/configs"
PROJECT_UI="share/sch-scripts/ui"
PROJECT_BINS="share/sch-scripts/scripts"

# Dependencies
DEPENDENCIES="python3 python3-gi python3-pip epoptes openssh-server iputils-arping libgtk-3-0 librsvg2-common policykit-1 util-linux dnsmasq ethtool net-tools p7zip-rar squashfs-tools symlinks"

# Uninstall Dependencies
UNINSTALL_DEPENDENCIES="epoptes openssh-server net-tools symlinks"

# Configurations variables
SHARE_DIR="/home/Shared"
PUBLIC_DIR="/home/Shared/Public"

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
        if [[ "$dest_path" == "$DEST_SBIN" ]]; then
            install -o root -g root -m 0755 "$source_path" "$dest_path"
        elif [[ "$source_path" == *.py ]] || [[ "$source_path" == *.sh ]]; then
            install -o root -g root -m 0755 "$source_path" "$dest_path"
        else
            install -o root -g root -m 0644 "$source_path" "$dest_path"
        fi
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
    apt-get remove  --allow-remove-essential $UNINSTALL_DEPENDENCIES || {
        echo "$ERROR_REMOVE_DEPENDENCIES"
        exit 1
    }
}

#teachers configuration
configure_teachers() {
    local before after old_ifs teacher teacher_home

    # Create "teachers" group and add the administrator to epoptes,teachers
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
    #Create the symlinks:
    # Find the home directory for the administrator
    home_dir=$(getent passwd "$administrator" | cut -d: -f6)

    # Create symlinks
    if [ -d "$home_dir" ]; then
        for dir in "$SHARE_DIR"/*; do
          group=$(basename "$dir")
          # Create symlinks
          ln -sf "$SHARE_DIR/$group" "$home_dir/Public/$group"
        done
        ln -sf "$PUBLIC_DIR" "$home_dir/Public/Public"
    fi
}
#common.sh functions
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
}

#Create the public folder
create_public_folder() {
    echo "Creating the public folder..."
    mkdir -p "$PUBLIC_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create $PUBLIC_DIR."
        exit 1
    fi
    chmod 0777 "$PUBLIC_DIR"
}

#install files
install_files() {
    echo "Moving files to their destinations..."

    # Create directories
    mkdir -p "$DEST_ETC" "$DEST_LIB" "$DEST_SHARE" "$DEST_SBIN" "$DEST_ROOT" "$DEST_CONFIGS" "$DEST_UI" "$DEST_BINS"

    # Create /etc/default/shared-folders from default
    if [ ! -f "$DEST_ETC/default/shared-folders" ]; then
        install -o root -g root -m 0644 "$PROJECT_ETC/default/shared-folders.default" "$DEST_ETC/default/shared-folders" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    fi

    # Move files
    for file in "$PROJECT_ETC"/*; do
         if [[ "$DEST_ETC" != "$DEST_ROOT" ]] && [[ "$DEST_ETC" != "$DEST_SBIN" ]] && [[ "$file" != "$PROJECT_ETC/default/shared-folders.default" ]]; then
            backup_file "$DEST_ETC" "$file"
        fi
        install_path "$file" "$DEST_ETC" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_LIB"/*; do
        if [[ "$DEST_LIB" != "$DEST_ROOT" ]] && [[ "$DEST_LIB" != "$DEST_SBIN" ]]; then
            backup_file "$DEST_LIB" "$file"
        fi
        install_path "$file" "$DEST_LIB" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_SHARE"/*; do
        if [[ "$DEST_SHARE" != "$DEST_ROOT" ]] && [[ "$DEST_SHARE" != "$DEST_SBIN" ]]; then
            backup_file "$DEST_SHARE" "$file"
        fi
        install_path "$file" "$DEST_SHARE" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the sch-scripts.py
    for file in "$PROJECT_ROOT"/*; do
        # Exclude configs, ui and scripts directories
        if [[ ! "$file" == "$PROJECT_ROOT/configs" ]] && [[ ! "$file" == "$PROJECT_ROOT/ui" ]] && [[ ! "$file" == "$PROJECT_ROOT/scripts" ]]; then
           install_path "$file" "$DEST_ROOT" || { echo "$ERROR_MOVE_FILES"; exit 1; }
        fi
    done

    for file in "$PROJECT_SBIN"/*; do
       install_path "$file" "$DEST_SBIN" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the config files
    for file in "$PROJECT_CONFIGS"/*; do
        install_path "$file" "$DEST_CONFIGS" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the ui files
    for file in "$PROJECT_UI"/*; do
        install_path "$file" "$DEST_UI" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the script files
    for file in "$PROJECT_BINS"/*; do
        install_path "$file" "$DEST_BINS" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Move shared-folders.service
    install -o root -g root -m 0644 "etc/systemd/system/shared-folders.service" "$DEST_ETC/systemd/system/shared-folders.service" || {
        echo "Failed to create /etc/systemd/system/shared-folders.service"
        exit 1
    }
    #Move shared-folders
    install -o root -g root -m 0755 "sbin/shared-folders" "$DEST_SBIN/shared-folders" || {
        echo "Failed to create /usr/sbin/shared-folders."
        exit 1
    }
    systemctl daemon-reload
    echo "Files moved successfully."
}

#revert files
revert_files() {
    echo "Reverting file changes..."

    # Revert files
    for file in "$PROJECT_ETC"/*; do
         if [[ "$DEST_ETC" != "$DEST_ROOT" ]] && [[ "$DEST_ETC" != "$DEST_SBIN" ]]; then
            revert_file "$DEST_ETC" "$file"
        fi
    done
    for file in "$PROJECT_LIB"/*; do
         if [[ "$DEST_LIB" != "$DEST_ROOT" ]] && [[ "$DEST_LIB" != "$DEST_SBIN" ]]; then
            revert_file "$DEST_LIB" "$file"
        fi
    done
    for file in "$PROJECT_SHARE"/*; do
         if [[ "$DEST_SHARE" != "$DEST_ROOT" ]] && [[ "$DEST_SHARE" != "$DEST_SBIN" ]]; then
            revert_file "$DEST_SHARE" "$file"
         fi
    done
    #Revert the sch-scripts files
    for file in "$PROJECT_ROOT"/*; do
        # Exclude configs, ui and scripts directories
        if [[ ! "$file" == "$PROJECT_ROOT/configs" ]] && [[ ! "$file" == "$PROJECT_ROOT/ui" ]] && [[ ! "$file" == "$PROJECT_ROOT/scripts" ]]; then
            revert_file "$DEST_ROOT" "$file"
        fi
    done
    for file in "$PROJECT_SBIN"/*; do
        revert_file "$DEST_SBIN" "$file"
    done
    #Revert configs
    for file in "$PROJECT_CONFIGS"/*; do
        revert_file "$DEST_CONFIGS" "$file"
    done
    #Revert ui
    for file in "$PROJECT_UI"/*; do
        revert_file "$DEST_UI" "$file"
    done
    #Revert scripts
    for file in "$PROJECT_BINS"/*; do
        revert_file "$DEST_BINS" "$file"
    done
    #Revert shared-folders.service
    rm -rf "$PUBLIC_DIR"

    revert_file "$DEST_ETC/systemd/system" "etc/systemd/system/shared-folders.service"
    #Revert shared-folders
    revert_file "$DEST_SBIN" "sbin/shared-folders"

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
    #Create public directory
    create_public_folder
    #This are the configurations
    configure_teachers
    #Start the service
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
#Create the directory of configs if it does not exist
if [ ! -d "$PROJECT_CONFIGS" ]; then
    mkdir -p "$PROJECT_CONFIGS"
    #Copy the ltsp config to config directory
    cp "$PROJECT_ROOT/ltsp.conf" "$PROJECT_CONFIGS/ltsp.conf"
fi
#Create the directory of UI if it does not exist
if [ ! -d "$PROJECT_UI" ]; then
    mkdir -p "$PROJECT_UI"
fi
#Create the directory of BINS if it does not exist
if [ ! -d "$PROJECT_BINS" ]; then
    mkdir -p "$PROJECT_BINS"
fi

#Execute the main
main "$@"

exit 0
