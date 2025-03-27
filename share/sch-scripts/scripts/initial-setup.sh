#!/bin/sh
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2019-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

# Contains some actions that the sysadmin should run after installation.

# Initial-setup will automatically prompt to run again if it detects that it
# was last ran before the following _VERSION. MANUALLY UPDATE THIS:
_PROMPT_AFTER="19.0"

. /usr/share/sch-scripts/scripts/common.sh

main() {
    chmod +x /usr/share/sch-scripts/*
    cmdline "$@"
    # configure_various goes first as it backgrounds a DNS task
    configure_various
    configure_ltsp
    configure_symlinks
    configure_teachers
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
        "# This file is regenerated when /usr/share/sch-scripts/scripts/initial-setup.sh runs.

# Remember the last version ran, to answer the --check parameter:
LAST_VERSION=%s\n" "$_VERSION" >"$conf"
}

configure_ltsp() {
    command -v ltsp >/dev/null || return 0
    mkdir -p /etc/ltsp
    if [ ! -f /etc/ltsp/ltsp.conf ]; then
        install -m 0660 -g sudo /usr/share/sch-scripts/conf/ltsp.conf /etc/ltsp/ltsp.conf
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
        # 685 = bash -c 'echo $((512 + 16#$(printf teachers | md5sum | cut -c1-2)))'
        addgroup --system --gid 685 "$TEACHERS"
        detect_administrator
        test -n "$_ADMINISTRATOR" || return 0
        before=$(groups "$_ADMINISTRATOR")
        usermod -a -G "$TEACHERS,epoptes" "$_ADMINISTRATOR"
        after=$(groups "$_ADMINISTRATOR")
        if [ "$before" != "$after" ]; then
            bold "Χρειάζεται αποσύνδεση και επανασύνδεση για να ενεργοποιηθούν οι αλλαγές στις ομάδες"
        fi
    fi
    # For shared folders to work, chmod 755 all teacher homes
    old_ifs="${IFS-not set}"
    IFS=","
    set -- $(getent group "$TEACHERS" | awk -F: '{ print $4 }')
    test "$old_ifs" = "not set" && unset IFS || IFS="$old_ifs"
    for teacher; do
        teacher_home=$(getent passwd "$teacher" | awk -F: '{ print $6 }')
        chmod 755 "$teacher_home"
    done
}

configure_symlinks() {
    # Immediately show security updates, don't install them in the background
    symlink /usr/share/sch-scripts/conf/apt.conf \
        /etc/apt/apt.conf.d/60sch-scripts
    # Allow flash by default in chromium-browser for educational applications
    symlink /usr/share/sch-scripts/conf/chromium-browser.json \
        /etc/chromium-browser/policies/managed/sch-scripts.json
    # Always display grub menu and used last saved entry
    symlink /usr/share/sch-scripts/conf/grub.cfg \
        /etc/default/grub.d/sch-scripts.cfg
    # Specify DNS servers that work inside or outside GSN
    symlink /usr/share/sch-scripts/conf/dnsmasq.conf \
        /etc/dnsmasq.d/sch-scripts.conf
    # Allow manual login (LP: #1804375)
    symlink /usr/share/sch-scripts/conf/lightdm.conf \
        /etc/lightdm/lightdm.conf.d/sch-scripts.conf || true
    # Disable internal PDF viewer, enable flash on file:// URLs
    symlink /usr/share/sch-scripts/conf/firefox.js \
        /usr/lib/firefox/defaults/pref/sch-scripts.js
    # Make gdebi-gtk work when run from a browser (LP #1854588)
    symlink /usr/share/sch-scripts/conf/gdebi-gtk /usr/local/bin/gdebi-gtk
    # Prevent marco from using XPresent on nouveau (marco #548)
    symlink /usr/share/sch-scripts/conf/marco /usr/local/bin/marco
    # Start tuxpaint fullscreen
    symlink /usr/share/sch-scripts/conf/tuxpaint /usr/local/bin/tuxpaint
    # Start tuxtype with the correct theme for the current locale
    symlink /usr/share/sch-scripts/conf/tuxtype /usr/local/bin/tuxtype
    # Work around unzip not using the correct charset (LP: #580961)
    symlink /usr/share/sch-scripts/conf/unzip /usr/local/bin/unzip
    # If mate is installed, use its mimeapps for root
    if [ ! -f /usr/local/share/applications/mimeapps.list ] &&
        [ -f /usr/share/mate/applications/defaults.list ]; then
        mkdir -p /usr/local/share/applications
        symlink /usr/share/mate/applications/defaults.list \
            /usr/local/share/applications/mimeapps.list
    fi
    # Work around for keyboard layout switching with Alt+Shift (LP: #1892014)
    # Adds 3 lines to each ueers .profile file. 
    symlink /usr/share/sch-scripts/conf/dconfs.sh \
        /etc/profile.d/apply_dconf_settings.sh
}


configure_various() {
    # Ensure that "server" is resolvable by DNS.
    if ! getent hosts server >/dev/null; then
        search_and_replace "^127.0.0.1[[:space:]]*localhost$" "& server" \
            /etc/hosts || true
    fi & # Background it in case the DNS resolve takes a long time.

    # Allow more simultaneous SSH connections from the local network.
    # TODO: use /etc/ssh/sshd_config.d instead
    search_and_replace "^#MaxStartups 10:30:100$" "MaxStartups 20:30:100" \
        /etc/ssh/sshd_config

    # Allow keyboard layout switching with Alt+Shift (LP: #1892014)
    # Does not work anymore...
    if grep '^XKBOPTIONS="grp_led:scroll"$' /etc/default/keyboard; then
        search_and_replace '^XKBOPTIONS="grp_led:scroll"$' \
            'XKBOPTIONS="grp:alt_shift_toggle,grp_led:scroll"' \
            /etc/default/keyboard 0
        test -n "$DISPLAY" &&
            setxkbmap -layout us,gr -option '' \
                -option grp:alt_shift_toggle,grp_led:scroll
    fi

    # Enable printer sharing, only if the user hasn't modified cups settings.
    # `cupsctl _share_printers=1` strips comments, but that's what the
    # system-config-printer does as well, and it takes care of restarting cups.
    if cmp --quiet /usr/share/cups/cupsd.conf.default /etc/cups/cupsd.conf; then
        cupsctl _share_printers=1
    fi

    # Set x-terminal-emulator, https://bugs.debian.org/931045
    if [ -x /usr/bin/mate-terminal.wrapper ] &&
        [ "$(readlink -f /etc/alternatives/x-terminal-emulator)" != /usr/bin/mate-terminal.wrapper ]; then
        update-alternatives --set x-terminal-emulator /usr/bin/mate-terminal.wrapper
    fi
}

main "$@"
