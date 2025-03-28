# Apply dconf settings for the current user
profile_file="$HOME/.profile"
if [ -f "$profile_file" ] && ! grep -q "dconf" "$profile_file"; then
    {
        echo "dconf write /org/gnome/libgnomekbd/keyboard/layouts \"['gr', 'us']\""
        echo "dconf write /org/gnome/libgnomekbd/keyboard/options \"['grp\tgrp:alt_shift_toggle']\""
        echo "dconf update"
    } >> "$profile_file"
fi