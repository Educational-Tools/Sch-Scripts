#!/bin/bash

# This script is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

if [ "$(id -un)" != "administrator" ]; then
    echo "This script must be run by the 'administrator' user."
    exit 1
fi

# Function to set the wallpaper
set_wallpaper() {
    hostname=$(hostname)
    wallpaper_path="/usr/share/backgrounds/sch-walls/${hostname}.png"

    echo "Setting wallpaper for all users to: ${wallpaper_path}"

    for user_home in /home/*; do
        if [ -d "$user_home" ] && [ "$(basename "$user_home")" != "Shared" ]; then
            user=$(basename "$user_home")
            su - "$user" -c "gsettings set org.cinnamon.desktop.background picture-uri file://${wallpaper_path}"
        fi
    done
}

main() {
    for arg in "$@"; do
        if [ "$arg" == "walls" ]; then
            set_wallpaper
        else
            echo "Unknown argument: $arg"
        fi
    done
}

# Call the main function with all arguments
main "$@"
