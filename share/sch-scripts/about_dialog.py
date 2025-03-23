# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
About dialog.
"""
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
import version

class AboutDialog:
    def __init__(self, main_window):
        self.builder = Gtk.Builder()
        self.builder.add_from_file("ui/about_dialog.ui")
        self.dialog = self.builder.get_object("aboutdialog1")
        self.dialog.set_version(version.__version__)
        self.dialog.set_transient_for(main_window)
        self.dialog.run()
        self.dialog.destroy()
