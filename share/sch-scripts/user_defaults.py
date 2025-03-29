#!/usr/bin/env python3
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Sch-scripts user defaults.
"""
import os
import subprocess
import socket
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
        self.checkbutton_shortcuts = self.builder.get_object("checkbutton_shortcuts")

        self.window.show_all()

    def on_window_user_defaults_delete_event(self, widget, event):
        Gtk.main_quit()

    def on_button_cancel_clicked(self, button):
        self.window.destroy()

    def on_button_apply_clicked(self, button):
        users = [user for user in os.listdir('/home') if os.path.isdir(os.path.join('/home', user)) and user != 'Shared']

        for user in users:
            user_home = os.path.join('/home', user)
            self.apply_settings(user_home)

    def apply_settings(self, user_home):
        hostname = socket.gethostname()
        wallpaper_path = f"/usr/share/backgrounds/sch-walls/{hostname}.png"

        if self.checkbutton_wallpaper.get_active():
            self.run_as_user(user_home, ["gsettings", "set", "org.cinnamon.desktop.background.picture-uri", f"file://{wallpaper_path}"])

        if self.checkbutton_shortcuts.get_active():
            # Example: Set a custom keyboard shortcut
            self.run_as_user(user_home, ["gsettings", "set", "org.cinnamon.desktop.keybindings.custom-keybindings.custom0.name", "My Shortcut"])
            self.run_as_user(user_home, ["gsettings", "set", "org.cinnamon.desktop.keybindings.custom-keybindings.custom0.command", "my-command"])
            self.run_as_user(user_home, ["gsettings", "set", "org.cinnamon.desktop.keybindings.custom-keybindings.custom0.binding", "<Ctrl><Alt>S"])

    def run_as_user(self, user_home, command):
        user = os.path.basename(user_home)
        subprocess.run(['su', '-', user, '-c', ' '.join(command)], check=True)

if __name__ == "__main__":
    app = UserDefaultsApp()
    Gtk.main()
