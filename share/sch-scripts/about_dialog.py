# This file is part of sch-scripts, https://sch-scripts.gitlab.io
# Copyright 2009-2022 the sch-scripts team, see AUTHORS
# SPDX-License-Identifier: GPL-3.0-or-later
"""
About dialog.
"""
from PyQt5.QtWidgets import QDialog, QLabel, QVBoxLayout, QPushButton, QApplication
from PyQt5.QtGui import QPixmap
from PyQt5.QtCore import Qt
import version
import os

class AboutDialog(QDialog):
    def __init__(self, main_window=None):
        super().__init__(main_window)

        self.setWindowTitle("About sch-scripts")
        self.setWindowModality(Qt.ApplicationModal)  # Make it modal

        layout = QVBoxLayout()

        # Add logo (if available)
        logo_path = "/usr/share/pixmaps/sch-scripts.svg"
        if os.path.exists(logo_path):
            try:
                logo_label = QLabel()
                pixmap = QPixmap(logo_path)
                # Scale down the logo if it's too big
                if pixmap.width() > 200 or pixmap.height() > 200:
                    pixmap = pixmap.scaled(200, 200, Qt.KeepAspectRatio)
                logo_label.setPixmap(pixmap)
                logo_label.setAlignment(Qt.AlignCenter)
                layout.addWidget(logo_label)
            except Exception as e:
                print(f"Error loading logo: {e}")

        # Add version information
        version_label = QLabel(f"sch-scripts {version.__version__}")
        version_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(version_label)

        # Add copyright information
        copyright_label = QLabel("Copyright 2009-2022 the sch-scripts team")
        copyright_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(copyright_label)

        # Add license information
        license_label = QLabel("SPDX-License-Identifier: GPL-3.0-or-later")
        license_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(license_label)

        # Add close button
        close_button = QPushButton("Close")
        close_button.clicked.connect(self.accept)
        layout.addWidget(close_button)

        self.setLayout(layout)
        self.exec_()  # Show the dialog modally

# Example usage (for testing):
if __name__ == "__main__":
    import sys
    app = QApplication(sys.argv)
    about_dialog = AboutDialog()
    sys.exit(app.exec_())
