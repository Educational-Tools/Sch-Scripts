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
            "RESTRICT_DIRS": "true",
            "TEACHERS": "teachers",
            "SHARE_DIR": "/home/Shared",
            "SHARE_GROUPS": "teachers",
            "ADM_UID": "1000",
            "ADM_GID": "1000"
        }
        try:
            with open("/etc/default/shared-folders") as f:
                contents = shlex.split(f.read(), True)
                self.config.update(dict(v.split("=") for v in contents))
        except FileNotFoundError:
            pass
    def parse_mounts(self):
        """Parse what's currently mounted, to find what we mounted."""
        # https://serverfault.com/a/876592
        # https://unix.stackexchange.com/a/53901
        try:
            with open("/proc/self/mounts") as f:
                for line in f:
                    path = line.split()[1]
                    if path.startswith(self.config["SHARE_DIR"]):
                        yield {
                            "group": path.split("/")[-1],
                            "gid": int(line.split()[4].split("=")[-1]),
                        }
        except FileNotFoundError:
            pass

    def valid(self, groups):
        """Ensure the listed groups are valid."""
        if groups is None:
            # Only list the default groups, not the ones from the database
            groups=self.config["SHARE_GROUPS"].split()
        else:
            # This might be useful to check against the database?
            # groups=list(set(groups) & set(self.groups.keys()))
            pass

        return groups

    def ensure_dir(self, dir, mode, uid, gid):
        """Ensure a directory is present, with the right perms/ownership."""
        if not os.path.exists(dir):
            os.makedirs(dir, mode, exist_ok=True)
        else:
            os.chmod(dir, mode)
        os.chown(dir, uid, gid)

    def unmount(self, group):
        """Unmount the folders for the specified groups."""
        dir = self.config["SHARE_DIR"] + "/" + group
        # Unmount without removing it.
        if os.path.ismount(dir):
            subprocess.call(["umount", dir])

    def nfs_exports(self):
        """Export to NFS, if enabled."""
        if self.config["DISABLE_NFS_EXPORTS"] == "true":
            return
        with open("/etc/exports.d/shared-folders.exports", "w") as f:
            f.write("%s/ *(ro,async,no_subtree_check,insecure)\n"
                % self.config["SHARE_DIR"])
            f.write("%s/* *(rw,async,no_subtree_check,insecure)\n"
                % self.config["SHARE_DIR"])
        subprocess.call(["exportfs", "-a"])

    def mount(self, groups=None):
        """Mount or remount the folders for the specified groups."""
        groups=self.valid(groups)
        # Remove from groups the ones that don't need to be (re)mounted.
        # Unmount the ones that need remounting, without removing them.
        for mount in self.parse_mounts():
            group=mount["group"]
            if group not in groups:
                continue
            if self.system.groups[group].gid == mount["gid"]:
                groups.remove(group)
            else:
                self.unmount(group)
        # Then mount what's left.
        # This might actually be the first time to mount anything,
        # so ensure that all the dirs/symlinks are there.
        adm_uid=int(self.config["ADM_UID"])
        self.ensure_dir(self.config["SHARE_DIR"], 0o711,
            adm_uid, int(self.config["ADM_GID"]))
        self.ensure_dir(self.config["SHARE_DIR"] + "/.symlinks", 0o731,
            adm_uid, self.system.groups[self.config["TEACHERS"]].gid)
        for group in groups:
            dir=self.config["SHARE_DIR"] + "/" + group
            group_gid=self.system.groups[group].gid
            self.ensure_dir(dir, 0o770, adm_uid, group_gid)
            subprocess.call(["bindfs",
                "-u", str(adm_uid),
                "--create-for-user=%s" % adm_uid,
                "-g", str(group_gid),
                "--create-for-group=%s" % group_gid,
                "-p", "770,af-x", "--chown-deny", "--chgrp-deny",
                "--chmod-deny", dir, dir])
        self.nfs_exports()

if __name__ == "__main__":
    sf = SharedFolders()
    groups = None
    sf.mount(groups)
