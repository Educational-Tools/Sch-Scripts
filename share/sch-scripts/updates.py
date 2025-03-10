#!/usr/bin/env python3
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Updates form.
"""
import os
from _gi import Gtk


class UpdatesDialog(object):
    def __init__(self, standalone=False):
        self.builder = Gtk.Builder()
        self.builder.add_from_file('ui/updates.ui')
        self.cancelled = False
        self.wnd_updates = self.builder.get_object('wnd_updates')
        self.builder.connect_signals(self)
        self.wnd_updates.show()

    def on_btn_cancel_clicked(self, _widget):
        """Handle btn_cancel clicked event."""
        self.quit(True)

    def on_btn_execute_clicked(self, _widget):
        """Handle btn_execute clicked event."""
        self.quit(False)

    def on_wnd_updates_delete_event(self, _widget, _event):
        """Handle wnd_updates delete event."""
        self.quit(True)

    def run_updates(self):
        """Execute updates if the window wasn't cancelled."""
        if self.cancelled:
            return
        cmd = ['run-in-terminal', './updates.sh']
        if not self.builder.get_object('chb_update').get_active():
            cmd += ['-u0']
        if not self.builder.get_object('chb_clean').get_active():
            cmd += ['-c0']
        if not self.builder.get_object('chb_autoremove').get_active():
            cmd += ['-a0']
        if self.builder.get_object('chb_ltsp_image').get_active():
            cmd += ['-i1']
        if self.builder.get_object('chb_poweroff').get_active():
            cmd += ['-p1']
        if self.standalone:
            os.execv('./run-in-terminal', cmd)
        else:
            os.spawnvp(os.P_NOWAIT, './run-in-terminal', cmd)

    def quit(self, cancelled):
        """Close the main window."""
        self.cancelled = cancelled
        if self.standalone:
            Gtk.main_quit()


def main():
    """Run the module from the command line."""
    ud = UpdatesDialog(True)
    Gtk.main()
    ud.run_updates()


if __name__ == '__main__':
    main()
