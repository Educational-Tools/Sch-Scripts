server_hostname=$(hostname)

for user in /home/*; do
    if [ -d "$user" ] && [ "$(basename "$user")" != "Shared" ]; then
        profile_file="$user/.profile"
        if [ -f "$profile_file" ] && ! grep -q "dconf" "$profile_file"; then
            {
                echo "dconf write org.gnome.libgnomekbd.keyboard layouts \"['gr', 'us']\""
                echo "dconf write org.gnome.libgnomekbd.keyboard options \"['grp\tgrp:alt_shift_toggle']\""
                echo "gsettings set org.gnome.desktop.background picture-uri \\\"file:///usr/share/backgrounds/sch-walls/${server_hostname}.png\\\""
            } >> "$profile_file"
        fi
    fi
done