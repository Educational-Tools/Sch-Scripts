echo "dconf write org.gnome.libgnomekbd.keyboard layouts \"['gr', 'us']\"" >> .profile
echo "dconf write org.gnome.libgnomekbd.keyboard options \"['grp\tgrp:alt_shift_toggle']\"" >> .profile
echo "dconf update" >> .profile