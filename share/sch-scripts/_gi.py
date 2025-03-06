#!/usr/bin/env python3
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Avoid pycodestyle warnings when importing from gi.repository.
"""
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk as giGtk


Gtk = giGtk
