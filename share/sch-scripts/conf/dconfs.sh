# Apply dconf settings for the current user
profile_file="$HOME/.profile"
if [ -f "$profile_file" ] && ! grep -q "dconf" "$profile_file"; then
    {
        echo "dconf write /org/gnome/libgnomekbd/keyboard/layouts \"['gr', 'us']\""
        echo "dconf write /org/gnome/libgnomekbd/keyboard/options \"['grp\tgrp:alt_shift_toggle']\""
        echo "gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/sch-walls/$(hostname).png'
        echo "dconf update"
    } >> "$profile_file"
fi