#!/bin/bash

# --- Setup and Error Handling and functions ---

# Check if running with sudo, prompt for password if needed
if [[ $EUID -ne 0 ]]; then
    echo -e "\\e[1mΑυτό το σενάριο απαιτεί δικαιώματα root. Παρακαλώ εισάγετε τον κωδικό sudo σας:\\e[0m"
    sudo true || {
        echo -e "\\e[1mΣφάλμα: Αδυναμία απόκτησης δικαιωμάτων root.\\e[0m"
        exit 1
    }
    sudo bash "$0" "$@" # Re-execute script with sudo
    exit "$?" # Exit with the same exit code as the re-executed script
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
PROJECT_BACKGROUNDS="share/backgrounds/linuxmint"
DEST_BACKGROUNDS="/usr/share/backgrounds"
DEST_LINUXMINT_WALLPAPERS="/usr/share/backgrounds/linuxmint"

# Dependencies
DEPENDENCIES="python3 python3-gi python3-pip epoptes openssh-server iputils-arping libgtk-3-0 librsvg2-common policykit-1 util-linux dnsmasq ethtool net-tools p7zip-rar squashfs-tools symlinks"

# Uninstall Dependencies
UNINSTALL_DEPENDENCIES="epoptes openssh-server net-tools symlinks"

# Configurations variables
SHARE_DIR="/home/Shared"
PUBLIC_DIR="/home/Shared/Public"

# Error messages
ERROR_INSTALL_DEPENDENCIES="\\e[1mΣφάλμα: Αποτυχία εγκατάστασης των εξαρτήσεων.\\e[0m"
ERROR_MOVE_FILES="\\e[1mΣφάλμα: Αποτυχία μετακίνησης των αρχείων στους προορισμούς τους.\\e[0m"
ERROR_REVERT_FILES="\\e[1mΣφάλμα: Αποτυχία επαναφοράς των αρχείων στους αρχικούς τους προορισμούς.\\e[0m"
ERROR_REMOVE_DEPENDENCIES="\\e[1mΣφάλμα: Αποτυχία απεγκατάστασης των εξαρτήσεων.\\e[0m"
ERROR_CONFIGURE="\\e[1mΣφάλμα: Αποτυχία διαμόρφωσης των sch-scripts.\\e[0m"
ERROR_START_SERVICES="\\e[1mΣφάλμα: Αποτυχία εκκίνησης των απαραίτητων υπηρεσιών.\\e[0m"

# Backup and Revert Functions

backup_file() {
    local dest_dir="$1"
    local source_file="$2"
    local dest_file="$dest_dir/$(basename "$source_file")"
    local bak_file="$dest_file.bak"

    # Check if the destination file exists
    if [[ -f "$dest_file" ]]; then
        echo -e "\\e[1mΔημιουργία αντιγράφου ασφαλείας: $dest_file στο $bak_file\\e[0m"
        mv "$dest_file" "$bak_file"
    fi
}

revert_file() {
    local dest_dir="$1"
    local source_file="$2"
    local file_path="$dest_dir/$(basename "$source_file")"
    local bak_file="$file_path.bak"

    if [[ -f "$bak_file" ]]; then
        echo -e "\\e[1mΕπαναφορά: $file_path από $bak_file\\e[0m"
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
          echo -e "\\e[1mΑποτυχία αντιγραφής του καταλόγου.\\e[0m"
          exit 1
        }
    else
        # It's a file
        if [[ "$dest_path" == "$DEST_SBIN" ]]; then

            # Check if it is lightdm.conf and exit if it is:
            if [[ "$source_path" == "share/sch-scripts/configs/lightdm.conf" ]]; then
               return 0
            fi
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
        echo -e "\\e[1mΑναμονή για την απελευθέρωση του κλειδώματος apt...\\e[0m"
        sleep 1
    done
}

#install-dependencies
install_dependencies() {
    wait_apt_lock
    apt-get update
    apt-get install -y -o APT::Acquire::http::Pipeline-Depth=0 -o APT::Acquire::Retries=10 $DEPENDENCIES || {
        echo -e "$ERROR_INSTALL_DEPENDENCIES"
        exit 1
    }
}

#remove-dependencies
remove_dependencies() {
    apt-get remove  --allow-remove-essential $UNINSTALL_DEPENDENCIES || {
        echo -e "$ERROR_REMOVE_DEPENDENCIES"
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

    # Ensure the administrator is in the epoptes group
    if ! groups "$administrator" | grep -wq "epoptes"; then
        usermod -aG epoptes "$administrator"
    fi
}

#Get the hostname
get_hostname() {
  hostname
}

#Get the theme mode
get_mode() {
  local current_theme
  local dark_themes=("Adwaita-dark" "Yaru-dark" "Dark")
  local light_themes=("Adwaita" "Yaru" "Light")
  current_theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
  current_theme=${current_theme//\'/}

  local is_dark=false
  for theme in "${dark_themes[@]}"; do
    if [[ "$current_theme" == *"$theme"* ]]; then
      is_dark=true
      break
    fi
  done

  if "$is_dark"; then
    echo "dark"
  else
    echo "light"
  fi
}

# Install wallpapers
install_wallpapers() {
  local hostname wallpaper_file mode project_root
  SERVER_WALLPAPERS=("1ek-volou") #Add server names here
  hostname=$(get_hostname)
    mode=$(get_mode)
  # Get the root directory of the project
  project_root=$(pwd)

  for server in "${SERVER_WALLPAPERS[@]}"; do
        if [[ "$hostname" == "$server" ]]; then
            wallpaper_file="$server"_$(echo "$mode" | tr '[:upper:]' '[:lower:]').png
            
            # Create the directory if it does not exist
            mkdir -p "$DEST_LINUXMINT_WALLPAPERS" 
            #Check if the default_background.png exists and rename it
            #Check if the default_linuxmint.png exists and rename it
            if [[ -f "$DEST_LINUXMINT_WALLPAPERS/default_linuxmint.png" ]]; then
                mv "$DEST_LINUXMINT_WALLPAPERS/default_linuxmint.png" "$DEST_LINUXMINT_WALLPAPERS/default_linuxmint.png.bak"
            fi
            
            # Use the full path to the wallpaper file.
            install -o root -g root -m 0644 "$project_root/$PROJECT_BACKGROUNDS/$wallpaper_file" "$DEST_LINUXMINT_WALLPAPERS/$wallpaper_file" || { echo -e "\\e[1mΣφάλμα: Αποτυχία μετακίνησης των αρχείων στους προορισμούς τους.\\e[0m"; exit 1; }
            #Check if the default_background.png exists and rename it
             if [[ -f "$DEST_LINUXMINT_WALLPAPERS/default_background.png" ]]; then
                mv "$DEST_LINUXMINT_WALLPAPERS/default_background.png" "$DEST_LINUXMINT_WALLPAPERS/default_background.png.bak"
            fi
            cp "$DEST_LINUXMINT_WALLPAPERS/$wallpaper_file" "$DEST_LINUXMINT_WALLPAPERS/default_linuxmint.png" || { echo -e "\\e[1mΣφάλμα: Αποτυχία μετακίνησης των αρχείων στους προορισμούς τους.\\e[0m"; exit 1; }
           
            # Set permissions for the directory
            chmod 755 "$DEST_LINUXMINT_WALLPAPERS" || { echo -e "\\e[1mΣφάλμα: Αδυναμία αλλαγής των δικαιωμάτων του καταλόγου $DEST_LINUXMINT_WALLPAPERS.\\e[0m"; exit 1; }
            break
        fi    
   
  done
}

# Detect the user with id 1000 (the first normal user):
detect_administrator() {
  # Detect the administrator user
    # shellcheck disable=SC2034
    administrator="$(id -u 1000 >/dev/null && id -un 1000)"
}

#start_shared_folders service
start_shared_folders_service() {
    echo -e "\\e[1mΕκκίνηση shared-folders.service...\\e[0m"
    systemctl start shared-folders.service || { echo -e "\\e[1mΣφάλμα: Αποτυχία εκκίνησης του shared-folders.service.\\e[0m"; exit 1;}
    echo -e "\\e[1mΤο shared-folders.service ξεκίνησε με επιτυχία.\\e[0m"
}

#Create the public folder
create_public_folder() {
    echo -e "\\e[1mΔημιουργία του δημόσιου φακέλου...\\e[0m"
    mkdir -p "$PUBLIC_DIR"
    if [ $? -ne 0 ]; then
        echo -e "\\e[1mΣφάλμα: Αποτυχία δημιουργίας $PUBLIC_DIR.\\e[0m"
        exit 1
    fi
    chmod 0777 "$PUBLIC_DIR"
}

#install files
install_files() {
    echo -e "\\e[1mΜετακίνηση αρχείων στους προορισμούς τους...\\e[0m"

    # Create directories
    mkdir -p "$DEST_ETC" "$DEST_LIB" "$DEST_SHARE" "$DEST_SBIN" "$DEST_ROOT" "$DEST_CONFIGS" "$DEST_UI" "$DEST_BINS"

    # Create /etc/default/shared-folders from default
    if [ ! -f "$DEST_ETC/default/shared-folders" ]; then
        install -o root -g root -m 0644 "$PROJECT_ETC/default/shared-folders.default" "$DEST_ETC/default/shared-folders" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    fi

    # Move files
    for file in "$PROJECT_ETC"/*; do
         if [[ "$DEST_ETC" != "$DEST_ROOT" ]] && [[ "$DEST_ETC" != "$DEST_SBIN" ]] && [[ "$file" != "$PROJECT_ETC/default/shared-folders.default" ]]; then
            backup_file "$DEST_ETC" "$file"
        fi
        install_path "$file" "$DEST_ETC" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_LIB"/*; do
        if [[ "$DEST_LIB" != "$DEST_ROOT" ]] && [[ "$DEST_LIB" != "$DEST_SBIN" ]]; then
            backup_file "$DEST_LIB" "$file"
        fi
        install_path "$file" "$DEST_LIB" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done

    for file in "$PROJECT_SHARE"/*; do
        if [[ "$DEST_SHARE" != "$DEST_ROOT" ]] && [[ "$DEST_SHARE" != "$DEST_SBIN" ]]; then
            backup_file "$DEST_SHARE" "$file"
        fi
        install_path "$file" "$DEST_SHARE" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the sch-scripts.py
    for file in "$PROJECT_ROOT"/*; do
        # Exclude configs, ui and scripts directories
        if [[ ! "$file" == "$PROJECT_ROOT/configs" ]] && [[ ! "$file" == "$PROJECT_ROOT/ui" ]] && [[ ! "$file" == "$PROJECT_ROOT/scripts" ]]; then
           install_path "$file" "$DEST_ROOT" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
        fi
    done

    for file in "$PROJECT_SBIN"/*; do
       install_path "$file" "$DEST_SBIN" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the config files
    for file in "$PROJECT_CONFIGS"/*; do
        install_path "$file" "$DEST_CONFIGS" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the ui files
    for file in "$PROJECT_UI"/*; do
        install_path "$file" "$DEST_UI" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Include the script files
    for file in "$PROJECT_BINS"/*; do
        install_path "$file" "$DEST_BINS" || { echo -e "$ERROR_MOVE_FILES"; exit 1; }
    done
    #Move shared-folders.service
    install -o root -g root -m 0644 "etc/systemd/system/shared-folders.service" "$DEST_ETC/systemd/system/shared-folders.service" || {
        echo -e "\\e[1mΑποτυχία δημιουργίας του /etc/systemd/system/shared-folders.service\\e[0m"
        exit 1
    }
    #Move shared-folders
    install -o root -g root -m 0755 "sbin/shared-folders" "$DEST_SBIN/shared-folders" || {
        echo -e "\\e[1mΑποτυχία δημιουργίας του /usr/sbin/shared-folders.\\e[0m"
        exit 1
    }
    systemctl daemon-reload
    echo -e "\\e[1mΤα αρχεία μετακινήθηκαν με επιτυχία.\\e[0m"
}

#revert files
revert_files() {
    echo -e "\\e[1mΕπαναφορά αλλαγών αρχείων...\\e[0m"

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

    #Revert shared-folders.service
    rm -rf "$DEST_ETC/systemd/system/shared-folders.service"
    #Revert shared-folders
    rm -rf "$DEST_SBIN/shared-folders"
    #Revert wallpaper

    #Remove the lightdm changes

    rm -rf /etc/lightdm/lightdm-gtk-greeter.conf.d/98-sch-scripts.conf
    rm -rf /etc/lightdm/lightdm-gtk-greeter.conf.d/99-sch-scripts.conf


    echo -e "\\e[1mΟι αλλαγές στα αρχεία επαναφέρθηκαν με επιτυχία.\\e[0m"
}

# Install function
install_sch() {
    echo -e "\\e[1mΕγκατάσταση sch-scripts...\\e[0m"
    # Install dependencies
    install_dependencies
    echo -e "\\e[1mΟι εξαρτήσεις εγκαταστάθηκαν με επιτυχία.\\e[0m"
    #install files
    install_files
    #Create public directory
    create_public_folder
    #This are the configurations
    configure_teachers
    hostname=$(get_hostname)
    if [[ "$hostname" == "1ek-volou" ]]; then
        #Install the wallpapers
        install_wallpapers
        #Configure LightDM
          # Check if lightdm.conf exists.
          if [[ -f /etc/lightdm/lightdm.conf ]]; then
              # Check if greeter-session is set.
              if ! grep -q "^greeter-session" /etc/lightdm/lightdm.conf; then
                  # Add greeter-session=lightdm-gtk-greeter
                  echo "greeter-session=lightdm-gtk-greeter" >> /etc/lightdm/lightdm.conf
              else
                  # Check if greeter-session is different than lightdm-gtk-greeter
                  if ! grep -q "^greeter-session=lightdm-gtk-greeter" /etc/lightdm/lightdm.conf; then
                      sed -i "s/^greeter-session=.*/greeter-session=lightdm-gtk-greeter/" /etc/lightdm/lightdm.conf
                  fi
              fi
          fi
        #Check if lightdm is running
        if systemctl is-active --quiet lightdm; then
          mode=$(get_mode)
          wallpaper_file="/usr/share/backgrounds/linuxmint/${hostname}_$(echo "$mode" | tr '[:upper:]' '[:lower:]').png"
            sed -i "/^\[Seat:\*\]/s/^\(background=\).*/\1$wallpaper_file/" /etc/lightdm/lightdm.conf || sed -i "/^\[Seat:\*\]/a background=$wallpaper_file" /etc/lightdm/lightdm.conf
                #Check if the lines exists
                if ! grep -q "^greeter-hide-users=false" /etc/lightdm/lightdm.conf; then
                   #add greeter-hide-users=false
                     sed -i "/^\[Seat:\*\]/a greeter-hide-users=false" /etc/lightdm/lightdm.conf
                fi
                if ! grep -q "^autologin-user=testuser" /etc/lightdm/lightdm.conf; then
                   #Add autologin-user=testuser
                   sed -i "/^\[Seat:\*\]/a autologin-user=testuser" /etc/lightdm/lightdm.conf
                fi
            fi
        
        
    else
        echo -e "\\e[1mΗ εγκατάσταση δεν είναι στο server 1ek-volou. Εξοδος.\\e[0m"
        return 0
    fi
    #Start the service
    start_shared_folders_service
    
    echo -e "\\e[1mΗ εγκατάσταση των sch-scripts ολοκληρώθηκε με επιτυχία!\\e[0m"
}

#remove function
remove_sch() {
    echo -e "\\e[1mΑπεγκατάσταση sch-scripts...\\e[0m"
    #Remove dependencies
    remove_dependencies
    echo -e "\\e[1mΟι εξαρτήσεις απεγκαταστάθηκαν με επιτυχία.\\e[0m"
    #revert files
    revert_files
    
    

    echo -e "\\e[1mΗ επαναφορά των sch-scripts ολοκληρώθηκε με επιτυχία!\\e[0m"
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
