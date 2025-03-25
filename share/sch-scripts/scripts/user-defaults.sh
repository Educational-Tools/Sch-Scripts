#!/bin/bash

dconf write /org/gnome/libgnomekbd/keyboard/layouts "['gr', 'us']"
dconf write /org/gnome/libgnomekbd/keyboard/options "['grp\tgrp:alt_shift_toggle', 'terminate\tterminate:ctrl_alt_bksp']"
