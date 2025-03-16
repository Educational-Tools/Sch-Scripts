#!/usr/bin/python3
# -*- coding: utf-8 -*-
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2012-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later

import os, sys, grp, pwd, subprocess, shlex

class System:
    """Encapsulate OS related functionality."""
    def __init__(self):
        self.groups = {g.gr_name: g for g in grp.getgrall()}
        self.users = {u.pw_name: u for u in pwd.getpwall()}
        self.system_groups = {"root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "uucp", "proxy", "www-data", "backup", "list", "irc", "gnats", "nobody", "systemd-timesync", "systemd-network", "systemd-resolve", "messagebus", "syslog", "_apt", "tss", "uuidd", "tcpdump", "avahi-autoipd", "usbmux", "rtkit", "dnsmasq", "speech-dispatcher", "colord", "hplip", "saned", "pulse", "avahi", "geoclue", "systemd-coredump"}

class SharedFolders:
    def __init__(self, system=None, config=None):
        if system is None:
            system = System()
        self.system = system
        self.config = {}
        self.load_config()
    def load_config(self):
        """Read the shell configuration files."""
        self.config = {
            "DISABLE_SHARED_FOLDERS": "false",
            "DISABLE_NFS_EXPORTS": "false",
            "RESTRICT_DIRS": "false",
            "TEACHERS": "teachers",
            "SHARE_DIR": "/home/Shared",
            "SHARE_GROUPS": "teachers",
            "PUBLIC_DIR": "/home/Shared/Public"
        }
        try:
            with open("/etc/default/shared-folders") as f:
                contents = shlex.split(f.read(), True)
                self.config.update(dict(v.split("=") for v in contents))
        except FileNotFoundError:
            pass

    def ensure_dir(self, dir, mode, uid, gid):
        """Ensure a directory is present, with the right perms/ownership."""
        if not os.path.exists(dir):
            os.makedirs(dir, mode, exist_ok=True)
        os.chmod(dir, mode)
        os.chown(dir, uid, gid)

    def mount(self, groups=None):
        """Create the folders for the specified groups."""
        
        # Ensure main shared directory exists
        self.ensure_dir(self.config["SHARE_DIR"], 0o755, 0, 0)
        
        # Create public folder
        self.ensure_dir(self.config["PUBLIC_DIR"], 0o777, 0, 0)

        #Create the folders for the groups
        groups=self.config["SHARE_GROUPS"].split()
        for group in groups:
            if group in self.system.system_groups:
                continue
            group_dir=self.config["SHARE_DIR"] + "/" + group
            group_gid = self.system.groups[group].gr_gid if group in self.system.groups else None
            if group_gid:
                self.ensure_dir(group_dir, 0o770, 0, group_gid)

            

    

if __name__ == "__main__":
    sf = SharedFolders()
    groups = None
    if sf.config["DISABLE_SHARED_FOLDERS"] != "true":
        sf.mount(groups)
