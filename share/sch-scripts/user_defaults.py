#!/usr/bin/env python3
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Sch-scripts user defaults configuration.
"""

import os
import subprocess
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk

class UserDefaultsApp:
    def __init__(self):
        self.builder = Gtk.Builder()
        self.builder.add_from_file("ui/user_defaults.ui")
        self.builder.connect_signals(self)

        self.window = self.builder.get_object("window_user_defaults")
        self.checkbutton_wallpaper = self.builder.get_object("checkbutton_wallpaper")

        self.window.show_all()

    def on_window_user_defaults_delete_event(self, widget, event):
        Gtk.main_quit()

    def on_button_cancel_clicked(self, button):
        self.window.destroy()

    def on_button_apply_clicked(self, button):
        arguments = []

        if self.checkbutton_wallpaper.get_active():
            arguments.append("walls")

        if arguments:
            subprocess.Popen(('/home/administrator/.local/share/sch-scripts/scripts/user_defaults.sh ' + arguments))
if __name__ == "__main__":
    app = UserDefaultsApp()
    Gtk.main()
