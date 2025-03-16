#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "This script requires root privileges. Please enter your sudo password:"
    sudo true || {
        echo "Error: Failed to obtain root privileges."
        exit 1
    }
    sudo bash "$0" "$@"
    exit $?
fi

set -e

# Global Variables
REVERT=false

# System Directories.
DEST_ETC="/etc"
DEST_LIB="/lib"
DEST_SHARE="/usr/share"
DEST_SBIN="/usr/sbin"
DEST_ROOT="/usr/share/sch-scripts"

# Project Directories.
PROJECT_ETC="etc"
PROJECT_LIB="lib"
PROJECT_SHARE="share"
PROJECT_SBIN="sbin"
PROJECT_ROOT="share/sch-scripts"

#Specific Project Directories
DEST_CONFIGS="/usr/share/sch-scripts/configs"
DEST_UI="/usr/share/sch-scripts/ui"
DEST_BINS="/usr/share/sch-scripts/scripts"
PROJECT_CONFIGS="share/sch-scripts/configs"
PROJECT_UI="share/sch-scripts/ui"
PROJECT_BINS="share/sch-scripts/scripts"

# Dependencies.
DEPENDENCIES="python3 python3-gi python3-pip epoptes openssh-server iputils-arping libgtk-3-0 librsvg2-common policykit-1 util-linux dnsmasq ethtool net-tools p7zip-rar squashfs-tools symlinks"

# Uninstall Dependencies.
UNINSTALL_DEPENDENCIES="epoptes openssh-server net-tools symlinks ltsp"

# Configuration variables.
SHARE_DIR="/home/Shared"
PUBLIC_DIR="/home/Shared/Public"

# Error messages.
ERROR_INSTALL_DEPENDENCIES="Error: Failed to install dependencies."
ERROR_MOVE_FILES="Error: Failed to move files to their destinations."
ERROR_REVERT_FILES="Error: Failed to revert files to their original destinations."
ERROR_REMOVE_DEPENDENCIES="Error: Failed to remove dependencies."


backup_file() {
    local dest_dir="$1"
    local source_file="$2"
    local dest_file="$dest_dir/$(basename "$source_file")"
    local bak_file="$dest_file.bak"

    # Check if the destination file exists.
    if [[ -f "$dest_file" ]]; then
        echo "Backing up: $dest_file to $bak_file"
        mv "$dest_file" "$bak_file" || exit 1
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

#Install function.
install_path() {
    local source_path="$1"
    local dest_path="$2"
    if [[ -d "$source_path" ]]; then
        # If it's a directory, use cp -r to copy recursively.
        mkdir -p "$dest_path/$(basename "$source_path")"
        cp -r "$source_path"/* "$dest_path/$(basename "$source_path")" || { 
          echo "Failed to copy directory."
          exit 1
        }
    else
        if [[ "$dest_path" == "$DEST_SBIN" ]]; then
            install -o root -g root -m 0755 "$source_path" "$dest_path"
        elif [[ "$source_path" == *.py ]] || [[ "$source_path" == *.sh ]]; then
            install -o root -g root -m 0755 "$source_path" "$dest_path"
        else
            install -o root -g root -m 0644 "$source_path" "$dest_path"
        fi
    fi
}

# Wait for apt lock.
wait_apt_lock() {
    while ! flock -w 10 /var/lib/dpkg/lock-frontend -c :; do
        echo "Waiting for apt lock to be released..."
        sleep 1
    done
}
install_dependencies() {
    wait_apt_lock
    apt-get update
    apt-get install -y -o APT::Acquire::http::Pipeline-Depth=0 -o APT::Acquire::Retries=10 $DEPENDENCIES || {
        echo "$ERROR_INSTALL_DEPENDENCIES"
        exit 1 
    }
}
remove_dependencies() {
    apt-get remove --allow-remove-essential $UNINSTALL_DEPENDENCIES || {
        echo "$ERROR_REMOVE_DEPENDENCIES"
        exit 1
    }
}
configure_teachers() {
    test -n "$TEACHERS" || return 0
    if ! getent group "$TEACHERS" >/dev/null; then
        addgroup --system --gid 685 "$TEACHERS"
        detect_administrator
    fi
    if getent group "$TEACHERS" >/dev/null; then
        teacher_home="/home/$TEACHERS"
        mkdir -p "$teacher_home"
        detect_administrator
        if ! groups "$administrator" | grep -wq "$TEACHERS"; then
            adduser "$administrator" "$TEACHERS"
        fi
    fi
    home_dir=$(getent passwd "$administrator" | cut -d: -f6)
    if [ -d "$home_dir" ]; then
        for dir in "$SHARE_DIR"/*; do
          group=$(basename "$dir")
          ln -sf "$SHARE_DIR/$group" "$home_dir/Public/$group"
        done
        ln -sf "$PUBLIC_DIR" "$home_dir/Public/Public"
    fi
}
detect_administrator() {
    administrator="$(id -u 1000 >/dev/null && id -un 1000)"
}
start_services() {   
    systemctl enable shared-folders.service || {
        echo "Error: Failed to enable shared-folders.service."
        exit 1
    }
    systemctl enable user-defaults.service || {
        echo "Error: Failed to enable user-defaults.service."
        exit 1
    }
    systemctl start shared-folders.service && echo "shared-folders.service enabled successfully." || {
        echo "Error: Failed to start shared-folders.service."
        exit 1
    }

    systemctl daemon-reload
    
    systemctl start user-defaults.service && echo "user-defaults.service started successfully." || {
        echo "Error: Failed to start user-defaults.service."
        exit 1
    }
    
}
create_public_folder() {
    echo "Creating the public folder..."
    test -d "$PUBLIC_DIR" && return 0
    mkdir -p "$PUBLIC_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create $PUBLIC_DIR."
        exit 1
    fi
    chmod 0777 "$PUBLIC_DIR"
}
install_files() {
    echo "Moving files to their destinations..."
    mkdir -p "$DEST_ETC" "$DEST_LIB" "$DEST_SHARE" "$DEST_SBIN" "$DEST_ROOT" "$DEST_CONFIGS" "$DEST_UI" "$DEST_BINS"
    if [ ! -f "$DEST_ETC/default/shared-folders" ]; then
        install -o root -g root -m 0644 "$PROJECT_ETC/default/shared-folders.default" "$DEST_ETC/default/shared-folders" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    fi
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
    for file in "$PROJECT_ROOT"/*; do
        if [[ ! "$file" == "$PROJECT_ROOT/configs" ]] && [[ ! "$file" == "$PROJECT_ROOT/ui" ]] && [[ ! "$file" == "$PROJECT_ROOT/scripts" ]]; then 
           install_path "$file" "$DEST_ROOT" || { echo "$ERROR_MOVE_FILES"; exit 1; }
        fi
    done
    for file in "$PROJECT_SBIN"/*; do
       install_path "$file" "$DEST_SBIN" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    for file in "$PROJECT_CONFIGS"/*; do
        install_path "$file" "$DEST_CONFIGS" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    for file in "$PROJECT_UI"/*; do
        install_path "$file" "$DEST_UI" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    for file in "$PROJECT_BINS"/*; do
        install_path "$file" "$DEST_BINS" || { echo "$ERROR_MOVE_FILES"; exit 1; }
    done
    install -o root -g root -m 0644 "etc/systemd/system/shared-folders.service" "$DEST_ETC/systemd/system/shared-folders.service" || {
        echo "Failed to create /etc/systemd/system/shared-folders.service"
        exit 1
    }
    sed -i 's|Type=simple|Type=forking|g' "$DEST_ETC/systemd/system/user-defaults.service" 
    sed -i 's|After=graphical-session.target|After=shared-folders.service|g' "$DEST_ETC/systemd/system/user-defaults.service"
    install -o root -g root -m 0644 "etc/systemd/system/user-defaults.service" "$DEST_ETC/systemd/system/user-defaults.service" || {
        echo "Failed to create /etc/systemd/system/user-defaults.service"
        exit 1
    }
    install -o root -g root -m 0755 "sbin/shared-folders" "$DEST_SBIN/shared-folders" || {
        echo "Failed to create /usr/sbin/shared-folders."
        exit 1
    }
    install -o root -g root -m 0755 "sbin/user-defaults" "$DEST_SBIN/" || {
        echo "Failed to create /usr/sbin/user-defaults."
        exit 1
    }
    echo "Files moved successfully."
} 
revert_files() {
    echo "Reverting file changes..."
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
    for file in "$PROJECT_ROOT"/*; do
        if [[ ! "$file" == "$PROJECT_ROOT/configs" ]] && [[ ! "$file" == "$PROJECT_ROOT/ui" ]] && [[ ! "$file" == "$PROJECT_ROOT/scripts" ]]; then 
            revert_file "$DEST_ROOT" "$file"
        fi
    done
    for file in "$PROJECT_SBIN"/*; do
        revert_file "$DEST_SBIN" "$file"
    done
    for file in "$PROJECT_CONFIGS"/*; do 
        revert_file "$DEST_CONFIGS" "$file"
    done
    for file in "$PROJECT_UI"/*; do 
        revert_file "$DEST_UI" "$file"
    done
    for file in "$PROJECT_BINS"/*; do 
        revert_file "$DEST_BINS" "$file"
    done
    rm -rf "$PUBLIC_DIR"
    revert_file "$DEST_ETC/systemd/system" "etc/systemd/system/shared-folders.service"
    rm -rf "$PUBLIC_DIR"
    revert_file "$DEST_ETC/systemd/system" "etc/systemd/system/user-defaults.service"
    revert_file "$DEST_SBIN" "sbin/shared-folders"
    echo "File changes reverted successfully."
    revert_file "$DEST_SBIN" "sbin/user-defaults"
    echo "File changes reverted successfully."
}
install_sch() {
    echo "Installing sch-scripts..."

    install_dependencies
    echo "Dependencies installed successfully."
    install_files
    create_public_folder
    configure_teachers
    start_services
    echo "Installation of sch-scripts completed successfully!"
}

remove_sch() {
    echo "Removing sch-scripts..."
    remove_dependencies
    echo "Dependencies removed successfully."
    revert_files
    echo "Revert of sch-scripts completed successfully!"
}

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
if [ ! -d "$PROJECT_CONFIGS" ]; then
    mkdir -p "$PROJECT_CONFIGS"
    cp "$PROJECT_ROOT/ltsp.conf" "$PROJECT_CONFIGS/ltsp.conf"
fi

if [ ! -d "$PROJECT_UI" ]; then
    mkdir -p "$PROJECT_UI"
fi
if [ ! -d "$PROJECT_BINS" ]; then
    mkdir -p "$PROJECT_BINS"
fi

main "$@"

exit 0
