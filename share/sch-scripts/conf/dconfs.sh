# Set Keyboard Layouts

dconf write /org/gnome/libgnomekbd/keyboard/layouts "['gr', 'us']"
dconf write /org/gnome/libgnomekbd/keyboard/options "['grp\tgrp:alt_shift_toggle']"
dconf update

# Set Wallpaper

hostname=$(hostname)
path="/usr/share/backgrounds/sch-walls/${hostname}.png"
command="gsettings set org.gnome.desktop.background picture-uri 'file://${path}'"
eval "$command"