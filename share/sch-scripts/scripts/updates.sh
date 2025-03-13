#!/bin/sh
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

# Perform selected update actions

. /usr/share/sch-scripts/common.sh

# Show usage; receive an optional fd parameter, 1 for stdout or 2 for stderr
usage() {
    local ret

    if [ "$1" = 2 ]; then
        exec >&2
        ret=1
    else
        ret=0
    fi
    printf "Χρήση: %s [ΕΠΙΛΟΓΗ=0|1]

ΕΠΙΛΟΓΕΣ:
Σε κάθε επιλογή παρατίθεται η προεπιλεγμένη τιμή της.

-u, --update=1
    Λήψη και εγκατάσταση ενημερώσεων.
-c, --clean=1
    Καθαρισμός προσωρινής μνήμης πακέτων.
-a, --autoremove=1
    Διαγραφή ορφανών πακέτων.
-i, --ltsp_image=0
    Δημοσίευση εικονικού δίσκου.
    Εκτελείται μόνο εάν οι προηγούμενες ενέργειες ήταν επιτυχείς.
-p, --poweroff=0
    Τερματισμός του υπολογιστή.

ΠΑΡΑΔΕΙΓΜΑ:
Η παρακάτω εντολή κάνει τις ενημερώσεις, δημοσίευση και τερματισμό:
    %s --ltsp_image=1 -p1
" "$_PROGRAM" "$_PROGRAM"
    exit "$ret"
}

main() {
    cmdline "$@"
    require_root
    apt_update
    apt_clean
    apt_autoremove
    ltsp_image
    power_off
}

cmdline() {
    local args

    args=$(getopt -n "${_PROGRAM##*/}" -o "a::c::i::p::u::" -l \
        "autoremove::,clean::,ltsp_image::,poweroff::,update::" -- "$@") ||
        usage 2
    eval "set -- $args"
    while true; do
        case "$1" in
        -a | --autoremove)
            shift
            # The short form may include the equals sign, e.g. -a=0
            AUTOREMOVE=${1#=}
            ;;
        -c | --clean)
            shift
            CLEAN=${1#=}
            ;;
        -i | --ltsp_image)
            shift
            LTSP_IMAGE=${1#=}
            ;;
        -p | --poweroff)
            shift
            POWEROFF=${1#=}
            ;;
        -u | --update)
            shift
            UPDATE=${1#=}
            ;;
        --)
            shift
            break
            ;;
        *) die "${_PROGRAM##*/}: error in cmdline: $*" ;;
        esac
        shift
    done
    if [ "$#" -ne 0 ]; then
        usage 2
    fi
}

abort() {
    warn "Εγκαταλείπονται όλες οι υπόλοιπες εργασίες"
    power_off
    exit 1
}

apt_autoremove() {
    # Suppose AUTOREMOVE=whatever is defined by mistake in the environment.
    # Assume anything different than 0 is equivalent to the default value, 1.
    test "${AUTOREMOVE:-1}" != 0 || return 0
    bold "Διαγραφή ορφανών πακέτων:"
    rwr apt-get autoremove --purge --yes -- \
        $(dpkg -l | awk '/^rc/ { print $2 }') ||
        abort
}

apt_clean() {
    test "${CLEAN:-1}" != 0 || return 0
    bold "Καθαρισμός προσωρινής μνήμης πακέτων:"
    rwr apt-get clean ||
        abort
}

apt_update() {
    test "${UPDATE:-1}" != 0 || return 0
    bold "Λήψη και εγκατάσταση ενημερώσεων:"
    if ! apt-get update; then
        bold "Η \`apt-get update\` απέτυχε αλλά η ενημέρωση συνεχίζεται"
    fi
    rwr apt-get --yes dist-upgrade ||
        abort
}

ltsp_image() {
    test "${LTSP_IMAGE:-0}" = 1 || return 0
    bold "Δημοσίευση εικονικού δίσκου:"
    rwr ltsp image / ||
        abort
}

power_off() {
    test "${POWEROFF:-0}" = 1 || return 0
    bold "Ο υπολογιστής θα τερματιστεί σε ένα λεπτό.
Πατήστε Ctrl+C για ακύρωση."
    if sleep 60; then
        if [ -x /usr/share/epoptes-client/endsession ]; then
            /usr/share/epoptes-client/endsession --shutdown
        else
            PATH="$PATH:/usr/sbin" poweroff
        fi
    fi
}

main "$@"
