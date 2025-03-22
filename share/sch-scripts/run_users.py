#!/usr/bin/env python3
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2020-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Run commands for selected users dialog.
"""
import inspect
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
import subprocess
import sys

import dialogs


class RunUsers:
    """Load the dialog and settings into local variables."""
    def __init__(self, parent, users, schscripts=None):
        self.schscripts = schscripts
        builder = Gtk.Builder()
        builder.add_from_file('ui/run_users.ui')
        self.dialog = builder.get_object('dlg_run_users')
        self.dialog.set_transient_for(parent)
        self.txv_commands = builder.get_object('txv_commands')
        self.btn_execute = builder.get_object('btn_execute')
        self.lbl_users = builder.get_object('lbl_users')
        self.lbl_users.set_text('Επιλεγμένοι χρήστες: ' + ', '.join(users))
        self.users = users
        builder.connect_signals(self)
        self.dialog.show()

    def on_btn_cancel_clicked(self, _widget):
        """Handle btn_cancel.clicked event."""
        self.dialog.destroy()

    def on_btn_help_clicked(self, _widget):
        """Handle btn_help.clicked event."""
        cmd = ["xdg-open", "https://ts.sch.gr/wiki/linux/ltsp/run-commands"]
        if self.schscripts:
            self.schscripts.run_as_sudo_user(cmd)
        else:
            print('EXECUTE:\t' + '\t'.join(cmd))

    def on_btn_run_clicked(self, widget):
        """Handle btn_run.clicked event."""
        title = 'Αδυναμία εκτέλεσης εντολών'
        if not self.users:
            dialogs.ErrorDialog('Δεν επιλέχθηκαν χρήστες', title).showup()
            return
        buffer = self.txv_commands.get_buffer()
        startIter, endIter = buffer.get_bounds()
        text = buffer.get_text(startIter, endIter, False).strip()
        if not text:
            dialogs.ErrorDialog('Δεν δόθηκαν εντολές προς εκτέλεση', title).showup()
            return
        subprocess.Popen(['./run-in-terminal', './run-users',
            ','.join(self.users), text])
        self.on_btn_cancel_clicked(widget)

    def on_dlg_run_users_delete_event(self, widget, _event):
        self.on_btn_cancel_clicked(widget)


if __name__ == '__main__':
    runusers = RunUsers(None, sys.argv[1:])
    Gtk.main()
