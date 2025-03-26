#!/usr/bin/env python3
# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Sch-scripts form.
"""
from _gi import Gtk
import os
import subprocess
import sys
from dbus.mainloop.glib import DBusGMainLoop
DBusGMainLoop(set_as_default=True)
from twisted.internet import gtk3reactor
gtk3reactor.install()
from twisted.internet import reactor, defer

import about_dialog
import config
import create_users
import dialogs
import export_dialog
import group_form
import import_dialog
import ip_dialog
import libuser
import ltsp_info
import parsers
import run_users
import shared_folders
import user_form
import version

class Gui:
    def __init__(self):
        self.system = libuser.system
        self.sf=shared_folders.SharedFolders(self.system)
        self.conf = config.parser

        self.builder = Gtk.Builder()
        self.builder.add_from_file('ui/sch-scripts.ui')
        self.builder.connect_signals(self)

        self.main_window = self.builder.get_object('main_window')
        self.users_tree = self.builder.get_object('users_treeview')
        self.groups_tree = self.builder.get_object('groups_treeview')
        self.users_sort = self.builder.get_object('users_sort')
        self.groups_sort = self.builder.get_object('groups_sort')
        self.users_filter = self.builder.get_object('users_filter')
        self.groups_filter = self.builder.get_object('groups_filter')
        self.users_model = self.builder.get_object('users_store')
        self.groups_model = self.builder.get_object('groups_store')

        # Show the tooltips in the statusbar
        self.statusbar = self.builder.get_object('statusbar')
        for obj in self.builder.get_objects():
            if isinstance(obj, Gtk.Widget):
                if obj.get_tooltip_text() is not None:
                    obj.set_has_tooltip(False)
                    obj.connect("enter_notify_event", self.on_enter_notify_event)
                    obj.connect("leave_notify_event", self.on_leave_notify_event)

        self.show_private_groups = False
        self.show_system_groups = False
        self.builder.get_object('mi_show_private_groups').set_active(self.conf.getboolean('GUI', 'show_private_groups'))
        self.builder.get_object('mi_show_system_groups').set_active(self.conf.getboolean('GUI', 'show_system_groups'))

        self.users_filter.set_visible_func(self.set_user_visibility)
        self.groups_filter.set_visible_func(self.set_group_visibility)

        # Fill the View -> Columns menu with all the columns of the treeview
        mn_view_columns = self.builder.get_object('mn_view_columns')
        users_columns = self.users_tree.get_columns()

        visible = self.conf.get('GUI', 'visible_user_columns')
        if visible == 'all':
            visible = [c.get_title() for c in users_columns]
        else:
            visible = visible.split(',')
        for column in users_columns:
            title = column.get_title()
            menuitem = Gtk.CheckMenuItem.new_with_label(title)
            menuitem.connect('toggled', self.on_mi_view_column_toggled, column)
            menuitem.set_active(title in visible)
            mn_view_columns.append(menuitem)
        self.populate_treeviews()

        # Disable some menus
        self.on_groups_selection_changed(None)
        self.on_users_selection_changed(None)

        self.queue = []
        self.system.connect_event(self.on_libuser_changed)
        self.main_window.show_all()

# General helper functions

    def edit_file(self, filename):
        subprocess.Popen(['xdg-open', filename], stdin=open(os.devnull))
        # TODO: Maybe throw an error message if not os.path.isfile(filename)

    def run_term(self, cmd):
        subprocess.Popen(('./scripts/run-in-terminal ' + cmd).split())

    def run_as_sudo_user(self, cmd):
        print('EXECUTE:\t' + '\t'.join(cmd))
        sys.stdout.flush()

    def open_link(self, link):
        self.run_as_sudo_user(['xdg-open', link])

    def get_selected_users(self):
        selection = self.users_tree.get_selection()
        paths = selection.get_selected_rows()[1]
        selected = [self.users_sort[path][0] for path in paths]
        return selected

    def get_selected_groups(self):
        selection = self.groups_tree.get_selection()
        paths = selection.get_selected_rows()[1]
        selected = [self.groups_sort[path][0] for path in paths]
        return selected

# INotify

    def on_libuser_changed(self, event):
        self.queue.append(event)
        d = defer.Deferred()
        reactor.callLater(1, d.callback, len(self.queue))
        d.addCallback(self.check_libuser_events)

    def check_libuser_events(self, len_queue):
        if len_queue == len(self.queue):
            self.queue = []
            self.repopulate_treeviews()

# Groups and users treeviews

    def populate_treeviews(self):
        """Fill the users and groups treeviews from the system"""
        for user in self.system.users.values():
            self.users_model.append([user, user.uid, user.name, user.primary_group, user.rname, user.office, user.wphone, user.hphone, user.other, user.directory, user.shell, user.lstchg, user.min, user.max, user.warn, user.inact, user.expire])
        for group in self.system.groups.values():
            self.groups_model.append([group, group.gid, group.name])

    def repopulate_treeviews(self):
        # Preserve the selected groups and users
        groups_selection = self.groups_tree.get_selection()
        users_selection = self.users_tree.get_selection()
        selected_groups = [i.name for i in self.get_selected_groups()]
        selected_users = [i.name for i in self.get_selected_users()]

        # Clear and refill the treeviews
        self.users_model.clear()
        self.groups_model.clear()
        self.populate_treeviews()

        # Reselect the previously selected groups and users, if possible
        groups_iters = dict((row[0].name, row.iter) for row in self.groups_sort)
        for gname in selected_groups:
            if gname in groups_iters:
                groups_selection.select_iter(groups_iters[gname])
        users_iters = dict((row[0].name, row.iter) for row in self.users_sort)
        for uname in selected_users:
            if uname in users_iters:
                users_selection.select_iter(users_iters[uname])

    def set_user_visibility(self, model, rowiter, options):
        user = model[rowiter][0]
        selected = self.get_selected_groups()
        # FIXME: The list comprehension here costs
        return (len(selected) == 0 and (self.show_system_groups or not user.is_system_user())) \
                or user in [u for g in selected for u in g.members.values()]

    def set_group_visibility(self, model, rowiter, options):
        group = model[rowiter][0]
        return (self.show_private_groups or not group.is_private()) and (self.show_system_groups or group.is_user_group())

    def on_groups_selection_changed(self, selection):
        self.users_filter.refilter()
        mi_edit_group = self.builder.get_object('mi_edit_group')
        mi_delete_group = self.builder.get_object('mi_delete_group')
        if selection is None:
            rows = 0
        else:
            rows = selection.count_selected_rows()
        if rows == 0:
            mi_edit_group.set_sensitive(False)
            mi_delete_group.set_sensitive(False)
        elif rows == 1:
            mi_edit_group.set_sensitive(True)
            mi_edit_group.set_label('Επεξεργασία ομάδας...')
            mi_delete_group.set_label('Διαγραφή ομάδας...')
            mi_delete_group.set_sensitive(True)
        else:
            mi_edit_group.set_sensitive(False)
            mi_delete_group.set_label('Διαγραφή ομάδων...')
            mi_delete_group.set_sensitive(True)

    def on_users_selection_changed(self, selection):
        mi_edit_user = self.builder.get_object('mi_edit_user')
        mi_delete_user = self.builder.get_object('mi_delete_user')
        mi_remove_user = self.builder.get_object('mi_remove_user')
        mi_run_users = self.builder.get_object('mi_run_users')
        if selection is None:
            rows = 0
        else:
            rows = selection.count_selected_rows()
        if rows == 0:
            mi_edit_user.set_sensitive(False)
            mi_delete_user.set_sensitive(False)
            mi_remove_user.set_sensitive(False)
            mi_run_users.set_sensitive(False)
        else:
            if self.groups_tree.get_selection().count_selected_rows() > 0:
                mi_remove_user.set_sensitive(True)
            else:
                mi_remove_user.set_sensitive(False)

            mi_delete_user.set_sensitive(True)
            mi_run_users.set_sensitive(True)

            if rows == 1:
                mi_edit_user.set_sensitive(True)
                mi_edit_user.set_label('Επεξεργασία χρήστη...')
                mi_delete_user.set_label('Διαγραφή χρήστη...')
            else:
                mi_edit_user.set_sensitive(False)
                mi_delete_user.set_label('Διαγραφή χρηστών...')


    def on_users_tv_button_press_event(self, widget, event):
        clicked = widget.get_path_at_pos(int(event.x), int(event.y))

        if event.button == 3:
            menu = self.builder.get_object('mn_users').popup(None, None, None, None, event.button, event.time)
            selection = widget.get_selection()
            selected = selection.get_selected_rows()[1]
            if clicked:
                clicked = clicked[0]
                if clicked not in selected:
                    selection.unselect_all()
                    selection.select_path(clicked)
            else:
                selection.unselect_all()
            return True

    def on_groups_tv_button_press_event(self, widget, event):
        clicked = widget.get_path_at_pos(int(event.x), int(event.y))

        if event.button == 3:
            menu = self.builder.get_object('mn_groups').popup(None, None, None, None, event.button, event.time)
            selection = widget.get_selection()
            selected = selection.get_selected_rows()[1]
            if clicked:
                clicked = clicked[0]
                if clicked not in selected:
                    selection.unselect_all()
                    selection.select_path(clicked)
            else:
                selection.unselect_all()
            return True

    def on_users_treeview_row_activated(self, widget, path, column):
        user_form.EditUserDialog(self.system, widget.get_model()[path][0])

    def on_groups_treeview_row_activated(self, widget, path, column):
        group_form.EditGroupDialog(self.system, self.sf, widget.get_model()[path][0])

    def on_unselect_all_groups_clicked(self, widget):
        self.groups_tree.get_selection().unselect_all()

    def on_main_window_delete_event(self, widget, event):
        self.conf.set('GUI', 'show_private_groups', str(self.show_private_groups))
        self.conf.set('GUI', 'show_system_groups', str(self.show_system_groups))
        visible_cols = [col.get_title() for col in self.users_tree.get_columns() if col.get_visible()]
        self.conf.set('GUI', 'visible_user_columns', ','.join(visible_cols))
        config.save()
        exit()

# File menu
    def on_menubar_set_focus_child(self, widget):
        print(widget)

    def on_mi_query_tooltip(self, widget, x, y, keyboard_mode, tooltip):
        tooltip.set_text("asdf")
        return False

    def on_enter_notify_event(self, widget, event):
        self.statusbar.push(0, widget.get_tooltip_markup())

    def on_leave_notify_event(self, widget, event):
        self.statusbar.push(0, "")

    def on_mi_signup_activate(self, widget):
        subprocess.Popen(['./signup_server.py'])

    #FIXME: Maybe use notify /etc/group then self.populate_treeviews not need to
    #update user groups for shared folder library
    def on_mi_new_users_activate(self, widget):
        create_users.NewUsersDialog(self.system, self.sf)

    def on_mi_import_passwd_activate(self, widget):
        chooser = Gtk.FileChooserDialog(title="Επιλέξτε το αρχείο passwd προς εισαγωγή",
                                        action=Gtk.FileChooserAction.OPEN,
                                        buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                                                 Gtk.STOCK_OK, Gtk.ResponseType.OK))

        chooser.set_icon_from_file('/usr/share/pixmaps/sch-scripts.svg')
        chooser.set_default_response(Gtk.ResponseType.OK)
        homepath = os.path.expanduser('~')
        chooser.set_current_folder(homepath)
        resp = chooser.run()
        if resp == Gtk.ResponseType.OK:
            passwd = chooser.get_filename()
            path = os.path.dirname(passwd)
            shadow = os.path.join(path, 'shadow')
            group = os.path.join(path, 'group')
            if not os.path.isfile(shadow):
                shadow = None
            if not os.path.isfile(group):
                group = None
            new_users = parsers.passwd().parse(passwd, shadow, group)
            if len(new_users.users) == 0:
                text = "Το αρχείο '%s' δεν περιέχει δεδομένα." % passwd
                dialogs.ErrorDialog(text, "Σφάλμα").showup()
                return False
            chooser.destroy()
            import_dialog.ImportDialog(new_users)
        else:
            chooser.destroy()

    def on_mi_import_csv_activate(self, widget):
        chooser = Gtk.FileChooserDialog(title="Επιλέξτε το αρχείο CSV προς εισαγωγή",
                                        action=Gtk.FileChooserAction.OPEN,
                                        buttons=(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                                                 Gtk.STOCK_OK, Gtk.ResponseType.OK))

        chooser.set_icon_from_file('/usr/share/pixmaps/sch-scripts.svg')
        chooser.set_default_response(Gtk.ResponseType.OK)
        homepath = os.path.expanduser('~')
        chooser.set_current_folder(homepath)
        resp = chooser.run()
        if resp == Gtk.ResponseType.OK:
            fname = chooser.get_filename()
            new_users = parsers.CSV().parse(fname)
            if len(new_users.users) == 0:
                text = "Το αρχείο '%s' δεν περιέχει δεδομένα." % fname
                dialogs.ErrorDialog(text, "Σφάλμα").showup()
                return False
            chooser.destroy()
            import_dialog.ImportDialog(new_users)
        else:
            chooser.destroy()

    def on_mi_export_csv_activate(self, widget):
        users = self.get_selected_users()
        if len(users) == 0:
            if self.show_system_groups:
                users = self.system.users.values()
            else:
                users = [u for u in self.system.users.values() if not u.is_system_user()]
        export_dialog.ExportDialog(self.system, users)

# Server menu

    #Actions
    
    def on_mi_initial_setup_activate(self, widget):
        self.run_term('./scripts/initial-setup.sh')

    def on_mi_configuration_network_activate(self, widget):
        ip_dialog.Ip_Dialog(self.main_window)

    def on_mi_updates_activate(self, widget):
        """Show the updates dialog in a different process."""
        subprocess.Popen(['./updates.py'], stdin=open(os.devnull))

    #LTSP Commands

    def on_mi_ltsp_image_activate(self, widget):
        message = "Θέλετε σίγουρα να προχωρήσετε στην δημοσίευση του εικονικού δίσκου;"
        second_message = "Ανάλογα με την ταχύτητα του επεξεργαστή σας και το μέγεθος του δίσκου σας, αυτή η διαδικασία μπορεί να χρειαστεί γύρω στα 10 λεπτά.\nΣτη συνέχεια (επαν)εκκινήστε τους σταθμούς εργασίας."
        dlg = dialogs.AskDialog(message)
        dlg.format_secondary_text(second_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp image /')

    def on_mi_ltsp_image_revert_activate(self, widget):
        message = "Θέλετε σίγουρα να προχωρήσετε στην επαναφορά του εικονικού δίσκου σε προηγούμενη έκδοση;"
        dlg = dialogs.AskDialog(message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp image --revert /')

    def on_mi_ltsp_dnsmasq_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να εκτελέσετε την εντολή 'ltsp dnsmasq';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp dnsmasq')

    def on_mi_ltsp_info_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να εκτελέσετε την εντολή 'ltsp info';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp info')

    def on_mi_ltsp_initrd_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να εκτελέσετε την εντολή 'ltsp initrd';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp initrd')

    def on_mi_ltsp_ipxe_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να εκτελέσετε την εντολή 'ltsp ipxe';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp ipxe')

    def on_mi_ltsp_kernel_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να εκτελέσετε την εντολή 'ltsp kernel';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp kernel')

    def on_mi_ltsp_nfs_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να εκτελέσετε την εντολή 'ltsp nfs';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.run_term('ltsp nfs')

    #Edit files

    def on_mi_edit_ltsp_conf_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να επεξεργαστείτε το αρχείο '/etc/ltsp/ltsp.conf';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.edit_file('/etc/ltsp/ltsp.conf')

    def on_mi_edit_ltsp_dnsmasq_conf_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να επεξεργαστείτε το αρχείο '/etc/dnsmasq.d/ltsp-dnsmasq.conf';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.edit_file('/etc/dnsmasq.d/ltsp-dnsmasq.conf')

    def on_mi_edit_ltsp_ipxe_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να επεξεργαστείτε το αρχείο '/srv/tftp/ltsp/ltsp.ipxe';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.edit_file('/srv/tftp/ltsp/ltsp.ipxe')

    def on_mi_edit_grub_cfg_activate(self, widget):
        confirm_message = "Θέλετε σίγουρα να επεξεργαστείτε το αρχείο '/etc/default/grub.d/sch-scripts.cfg';"
        dlg = dialogs.AskDialog(confirm_message)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            self.edit_file('/etc/default/grub.d/sch-scripts.cfg')


# View menu

    def on_mi_view_column_toggled(self, checkmenuitem, treeviewcolumn):
        treeviewcolumn.set_visible(checkmenuitem.get_active())

    def on_mi_show_system_groups_toggled(self, widget):
        self.show_system_groups = not self.show_system_groups
        self.groups_filter.refilter()
        self.users_filter.refilter()

    def on_mi_show_private_groups_toggled(self, widget):
        self.show_private_groups = not self.show_private_groups
        self.groups_filter.refilter()

    def on_mi_refresh_activate(self, widget):
        self.repopulate_treeviews()

# Users menu

    def on_mi_new_user_activate(self, widget):
        user_form.NewUserDialog(self.system)

    def on_mi_edit_user_activate(self, widget):
        user_form.EditUserDialog(self.system, self.get_selected_users()[0])

    def on_mi_delete_user_activate(self, widget):
        users = self.get_selected_users()
        users_n = len(users)
        if users_n == 1:
            message = "Θέλετε σίγουρα να διαγράψετε τον χρήστη %s;" % users[0].name
            homes_message = "Να διαγραφεί και ο αρχικός κατάλογος του παραπάνω χρήστη."
            homes_warn = "ΠΡΟΣΟΧΗ: Αν ενεργοποιήσετε αυτήν την επιλογή θα διαγραφεί ο αρχικός κατάλογος του χρήστη, καθώς και όλα τα αρχεία που αυτός περιέχει, αλλά και ο αντίστοιχος κατάλογος e-mail στο /var/mail (εάν υπάρχει)."
        else:
            message = "Θέλετε σίγουρα να διαγράψετε τους παρακάτω %d χρήστες;" % users_n
            message += "\n" + ', '.join([user.name for user in users])
            homes_message = "Να διαγραφούν και οι αρχικοί κατάλογοι των παραπάνω χρηστών."
            homes_warn = "ΠΡΟΣΟΧΗ: Αν ενεργοποιήσετε αυτήν την επιλογή θα διαγραφούν οι αρχικοί κατάλογοι όλων των παραπάνω χρηστών, καθώς και όλα τα αρχεία που αυτοί περιέχουν, αλλά και οι αντίστοιχοι κατάλογοι e-mail στο /var/mail (εάν υπάρχουν)."
        homes_warn += "\n\nΗ ενέργεια αυτή είναι μη-αναστρέψιμη."

        dlg = dialogs.AskDialog(message)
        vbox = dlg.get_message_area()
        rm_homes_check = Gtk.CheckButton(homes_message)
        rm_homes_check.get_child().set_tooltip_text(homes_warn)
        rm_homes_check.show()
        vbox.pack_start(rm_homes_check, False, False, 12)
        response = dlg.showup()
        if response == Gtk.ResponseType.YES:
            rm_homes = rm_homes_check.get_active()
            for user in self.get_selected_users():
                self.system.delete_user(user, rm_homes)

    def on_mi_remove_user_activate(self, widget):
        users = self.get_selected_users()
        groups = self.get_selected_groups()
        users_n = len(users)
        group_names = ', '.join([group.name for group in groups])
        if users_n == 1:
            message = "Θέλετε σίγουρα να αφαιρέσετε τον χρήστη %s από τις επιλεγμένες ομάδες (%s);" % (users[0].name, group_names)
        else:
            message = "Θέλετε σίγουρα να αφαιρέσετε τους παρακάτω %d χρήστες από τις επιλεγμένες ομάδες (%s);" % (users_n, group_names)
            message += "\n" + ', '.join([user.name for user in users])

        response = dialogs.AskDialog(message).showup()
        if response == Gtk.ResponseType.YES:
            for user in self.get_selected_users():
                self.system.remove_user_from_groups(user, groups)

    def on_mi_run_users_activate(self, widget):
        users = self.get_selected_users()
        users_n = len(users)
        run_users.RunUsers(self.main_window, [user.name for user in users], self)

# Groups menu

    def on_mi_new_group_activate(self, widget):
        group_form.NewGroupDialog(self.system, self.sf)

    def on_mi_edit_group_activate(self, widget):
        group_form.EditGroupDialog(self.system, self.sf, self.get_selected_groups()[0])

    def on_mi_delete_group_activate(self, widget):
        groups = self.get_selected_groups()
        groups_n = len(groups)
        if groups_n == 1:
            message = "Θέλετε σίγουρα να διαγράψετε την ομάδα %s;" % groups[0].name
        else:
            message = "Θέλετε σίγουρα να διαγράψετε τις παρακάτω %d ομάδες;" % groups_n
            message += "\n" + ', '.join([group.name for group in groups])

        response = dialogs.AskDialog(message).showup()
        if response == Gtk.ResponseType.YES:
            self.sf.remove([g.name for g in groups])
            for group in groups:
                self.system.delete_group(group)

# Help menu

    def on_mi_home_activate(self, widget):
        self.open_link('https://ts.sch.gr/wiki/linux')

    def on_mi_support_activate(self, widget):
        self.open_link("https://ts.sch.gr/wiki/linux/support")

    def on_mi_report_bug_activate(self, widget):
        self.open_link('https://gitlab.com/sch-scripts/sch-scripts/issues')

    def on_mi_ltsp_conf_manpage_activate(self, widget):
        self.open_link('https://ltsp.org/man/ltsp.conf')

    def on_mi_map_activate(self, widget):
        self.open_link('https://ts.sch.gr/wiki/linux/ltsp/map')

    def on_mi_about_activate(self, widget):
        about_dialog.AboutDialog(self.main_window)


# To export a man page:
# help2man -L el -s 8 -o sch-scripts.8 -N ./sch-scripts && man ./sch-scripts.8
def usage():
    print("""Χρήση: sch-scripts [ΕΠΙΛΟΓΕΣ]

Παρέχει ένα σύνολο εξαρτήσεων για την αυτοματοποίηση της εγκατάστασης
σχολικών εργαστηρίων και ένα γραφικό περιβάλλον που υποστηρίζει διαχείριση
λογαριασμών χρηστών, δημιουργία εικονικού δίσκου LTSP κ.α.

Πολλά από τα συμπεριλαμβανόμενα βοηθήματα προσανατολίζονται σε LTSP
εγκαταστάσεις, αλλά το πακέτο είναι χρήσιμο και χωρίς LTSP.

Περισσότερες πληροφορίες: https://ts.sch.gr/wiki/linux.

Επιλογές:
    -h, --help     Σελίδα βοήθειας της εφαρμογής.
    -v, --version  Προβολή έκδοσης των sch-scripts.

Αναφορά σφαλμάτων στο https://gitlab.com/sch-scripts/sch-scripts/issues.""")


def print_version():
    print("""sch-scripts %s
Copyright 2009-2022 ομάδα ανάπτυξης των sch-scripts.
Άδεια χρήσης GPLv3+: GNU GPL έκδοσης 3 ή νεότερη <https://gnu.org/licenses/gpl.html>.

Συγγραφή: δείτε το αρχείο AUTHORS.""" % version.__version__)

if __name__ == '__main__':
    if len(sys.argv) == 2 and (sys.argv[1] == '-v' or sys.argv[1] == '--version'):
        print_version()
        sys.exit(0)
    elif len(sys.argv) == 2 and (sys.argv[1] == '-h' or sys.argv[1] == '--help'):
        usage()
        sys.exit(0)
    elif len(sys.argv) >= 2:
        usage()
        sys.exit(1)
    Gui()
    reactor.run()
