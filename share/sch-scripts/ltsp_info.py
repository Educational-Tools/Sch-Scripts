# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Show the output of `ltsp info` in a dialog.
"""
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk
import re
import textwrap

import common

class LtspInfo:
    def __init__(self, main_window):
        gladefile = "ui/ltsp_info.ui"
        self.builder = Gtk.Builder()
        self.builder.add_from_file(gladefile)
        self.builder.connect_signals(self)
        self.dialog = self.builder.get_object("dialog1")
        self.dialog.set_transient_for(main_window)
        self.buffer = self.builder.get_object("textbuffer1")
        self.Fill()

    def Close(self, widget):
        self.dialog.destroy()

    def Fill(self):
        success, response = common.run_command(['ltsp', 'info'])
        self.buffer.set_text(response)
        self.dialog.show()
