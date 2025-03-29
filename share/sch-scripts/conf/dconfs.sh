# Set Keyboard Layouts

dconf write /org/gnome/libgnomekbd/keyboard/layouts "['gr', 'us']"
dconf write /org/gnome/libgnomekbd/keyboard/options "['grp\tgrp:alt_shift_toggle']"
dconf update

# Set Wallpaper
sleep 10
hostname=$(hostname)
command="gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/sch-walls/${hostname}.png'"
exec -c "$command"