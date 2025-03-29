#!/bin/bash

# This script is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

if [ "$(id -un)" != "administrator" ]; then
    echo "This script must be run by the 'administrator' user."
    exit 1
fi

# Function to set the wallpaper
walls() {
    if [ ! -d /usr/share/backgrounds/sch-walls ]; then
        echo "Directory /usr/share/backgrounds/sch-walls does not exist."
        return 1
    else
        gsettings set org.gnome.desktop.background picture-uri "file:///usr/share/backgrounds/sch-walls/$(hostname).png"
    fi
}

main() {
    for arg in "$@"; do
        if [ "$arg" == "walls" ]; then
            walls
        else
            echo "Unknown argument: $arg"
        fi
    done
}

main "$@"
