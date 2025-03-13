#!/bin/sh
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2019-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

# Contains some actions that the sysadmin should run after installation.

# Initial-setup will automatically prompt to run again if it detects that it
# was last ran before the following _VERSION. MANUALLY UPDATE THIS:
_PROMPT_AFTER="19.0"

. /usr/share/sch-scripts/common.sh

install_dependencies() {
    # Wait for apt lock to be released
    while ! flock -w 10 /var/lib/dpkg/lock-frontend -c :; do
        echo "Waiting for apt lock to be released..."
        sleep 1
    done
    apt-get update
    apt-get install -y bindfs iputils-arping libgtk-3-0 librsvg2-common policykit-1 util-linux dnsmasq ethtool ltsp net-tools nfs-kernel-server p7zip-rar squashfs-tools || {
        echo "Error: Failed to install soft dependencies."
        exit 1
    }
}

main() {
    cmdline "$@"
    # configure_various goes first as it backgrounds a DNS task
    install_dependencies
    configure_various
    configure_ltsp
    configure_symlinks
    configure_teachers
    start_shared_folders_service
}

cmdline() {
    local conf _dummy

    conf=/var/lib/sch-scripts/initial-setup.conf
    if [ "$1" = "--check" ]; then
        test -f "$conf" && . "$conf"
        printf "LAST_VERSION=%s, _VERSION=%s, _PROMPT_AFTER=%s: " \
            "$LAST_VERSION" "$_VERSION" "$_PROMPT_AFTER"
        if [ "$(printf "%s\n%s\n" "$_PROMPT_AFTER" "$LAST_VERSION" | sort -V | tail -n 1)" = "$_PROMPT_AFTER" ]; then
            echo "χρειάζεται να εκτελεστεί"
            exit 1
        else
            echo "δεν χρειάζεται να εκτελεστεί"
            exit 0
        fi
    fi
    if [ "$1" != "--no-prompt" ]; then
        printf "Θα εκτελεστούν κάποιες ενέργειες αρχικοποίησης των sch-scripts.
Πατήστε [Enter] για συνέχεια ή Ctrl+C για εγκατάλειψη: "
        # shellcheck disable=SC2034
        read -r _dummy
    fi
    mkdir -p "${conf%/*}"
    printf \
        "# This file is regenerated when /usr/share/sch-scripts/initial-setup.sh runs.

# Remember the last version ran, to answer the --check parameter:
LAST_VERSION=%s\n" "$_VERSION" >"$conf"
}

configure_ltsp() {
    command -v ltsp >/dev/null || return 0
    mkdir -p /etc/ltsp
    if [ ! -f /etc/ltsp/ltsp.conf ]; then
        install -m 0660 -g sudo /usr/share/sch-scripts/ltsp.conf /etc/ltsp/ltsp.conf
    fi
    rm -f /etc/dnsmasq.d/ltsp-server-dnsmasq.conf
    test -f /etc/dnsmasq.d/ltsp-dnsmasq.conf || ltsp dnsmasq
    test -f /etc/exports.d/ltsp-nfs.exports || ltsp nfs
}

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

start_shared_folders_service() {
    echo "Starting shared-folders.service..."
    systemctl start shared-folders.service || {
        echo "Error: Failed to start shared-folders.service."
        exit 1
    }
    echo "shared-folders.service started successfully."
    systemctl status shared-folders.service
}