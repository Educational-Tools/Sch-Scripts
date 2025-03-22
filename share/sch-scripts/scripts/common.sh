# /bin/sh -n
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2019-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

# Sourced by all sch-scripts shell scripts, provides some common functions
chmod +x /usr/share/sch-scripts/*
_PROGRAM="$0"
_VERSION=$(. /usr/share/sch-scripts/version.py >/dev/null && printf "%s\n" "$__version__")

# POSIX recommends that printf is preferred over echo.
# But do offer a simple wrapper to avoid "%s\n" all the time.
echo() {
    printf "%s\n" "$*"
}

bold() {
    if [ -z "$printbold_first_time" ]; then
        printbold_first_time=true
        bold_face=$(tput bold 2>/dev/null) || true
        normal_face=$(tput sgr0 2>/dev/null) || true
    fi
    printf "%s\n" "${bold_face}$*${normal_face}"
}

log() {
    logger -t sch-scripts -p syslog.err "$@"
}

# Try to find the user that ran sudo or su
detect_administrator() {
    _ADMINISTRATOR=$(id -un) || true
    if [ "${_ADMINISTRATOR:-root}" = "root" ]; then
        _ADMINISTRATOR=$(loginctl user-status | awk '{ print $1; exit 0 }') ||
            true
    fi
    if [ "${_ADMINISTRATOR:-root}" = "root" ]; then
        _ADMINISTRATOR=${SUDO_USER}
    fi
    if [ "${_ADMINISTRATOR:-root}" = "root" ] && [ "${PKEXEC_UID:-0}" != "0" ]
    then
        _ADMINISTRATOR=${PKEXEC_UID}
    fi
    if [ "${_ADMINISTRATOR:-root}" != "root" ]; then
        IFS=: read -r _ADMINISTRATOR _dummy _ADMIN_UID _ADMIN_GID _dummy <<EOF
$(getent passwd "$_ADMINISTRATOR")
EOF
    fi
    if [ "${_ADMINISTRATOR:-root}" = "root" ]; then
        unset _ADMINISTRATOR _ADMIN_UID _ADMIN_GID
    fi
    return 0
}

# Output a message to stderr and abort execution
die() {
    log "$@"
    bold "ERROR in ${0##*/}:" >&2
    echo "$@" >&2
    pause_exit 1
}

# Check if parameter is a command; `command -v` isn't allowed by POSIX
is_command() {
    local fun

    if [ -z "$is_command" ]; then
        command -v is_command >/dev/null ||
            die "Your shell doesn't support command -v"
        is_command=1
    fi
    for fun in "$@"; do
        command -v "$fun" >/dev/null || return $?
    done
}

pause_exit() {
    local _dummy

    if [ "$SPAWNED_TERM" = true ]; then
        printf "Πατήστε [Enter] για να κλείσετε το παρόν παράθυρο."
        read -r _dummy
    fi
    exit "$@"
}

re() {
    "$@" || die "sch-scripts command failed: [$0] $*"
}

require_root() {
    if [ "$(/usr/bin/id -u)" != 0 ]; then
        die "${1:-$0 must be run as root}"
    fi
}

rs() {
    "$@" >/dev/null 2>&1 || true
}

rw() {
    "$@" || printf "sch-scripts command failed: %s\n" "$0 $*"
}

# Run a command. Warn if it failed. Return $?.
# Don't warn if $RWR_SILENCE is set, to easily implement rs() and rsr().
# Used like `rwr cmd1 || cmd2`.
rwr() {
    local want got

    if [ "$1" = "!" ]; then
        want=1
        shift
    else
        want=0
    fi
    got=0
    if [ "$_RWR_SILENCE" = "1" ]; then
        "$@" >/dev/null 2>&1 || got=$?
    else
        "$@" || got=$?
    fi
    # Failed if either of them is zero and the other non-zero
    # Use {} to avoid subshells and shellcheck's SC2166
    if { [ "$want" = 0 ] && [ "$got" != 0 ]; } ||
       { [ "$want" != 0 ] && [ "$got" = 0 ]; } then
        test "$_RWR_SILENCE" = "1" || warn "sch-scripts command failed: $*"
    fi
    return $got
}

# $search must be ready for sed, e.g. '^whole line$'.
# Return 0 if a replacement was made, 1 otherwise.
search_and_replace() {
    local search replace file backup comment
    search=$1
    replace=$2
    file=$3
    backup=$4

    if [ "${backup:-1}" = "1" ]; then
        comment=" # Commented by sch-scripts: &"
    else
        comment=""
    fi
    if grep -qs "$search" "$file"; then
        sed "s/$search/$replace$comment/" -i "$file"
        return 0
    fi
    return 1
}

# Create a relative symlink only if the destination directory exists,
# while overwriting existing symlinks, but not files/dirs.
symlink() {
    local dst src

    dst=$1
    src=$2
    test -d "${dst%/*}" || return 0
    test -h "$src" && rm "$src"
    if [ -e "$src" ]; then
        warn "Not overwriting $src with a symlink to $dst"
        return 0
    fi
    mkdir -p "${src%/*}" || return 0
    ln -rs "$dst" "$src"
}

# Print a message to stderr
warn() {
    printf "%s\n" "$*" >&2
}
