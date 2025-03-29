if [ .profile == "dconf" ]; do
    echo "dconf write /org/gnome/libgnomekbd/keyboard/layouts \"['gr', 'us']\"" >> .profile
    echo "dconf write /org/gnome/libgnomekbd/keyboard/options \"['grp\tgrp:alt_shift_toggle']\"" >> .profile
    echo "gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/sch-walls/$(hostname).png'" >> .profile
    echo "dconf update" >> .profile
fi