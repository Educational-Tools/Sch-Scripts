import subprocess
import os

schools = ["1ek-volou"]
background_dir = "/usr/share/backgrounds/sch-walls"
config_dir = "/usr/share/sch-scripts/configs"

def get_wallpaper_paths(server_name):
    """
    Generates the paths for the dark and light mode wallpapers based on the server name.

    Args:
        server_name: The name of the server.
    """
    dark_path = f"{background_dir}/{server_name}_dark.png"
    light_path = f"{background_dir}/{server_name}_light.png"
    return dark_path, light_path    

def get_current_theme():
    """Detects the current GTK theme (dark/light mode)."""
    try:
        # Use gsettings to get the current GTK theme
        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"],
            capture_output=True,
            text=True,
            check=True,
        )
        theme_name = result.stdout.strip().lower()

        # Simple heuristic to determine dark/light mode
        if "dark" in theme_name or "yaru-dark" in theme_name:
            return "dark"
        else:
            return "light"
    except subprocess.CalledProcessError:
        print("Error: Could not determine GTK theme. Assuming light mode.")
        return "light"

def get_hostname():
    """Retrieves the hostname of the system."""
    try:
        hostname = subprocess.getoutput("hostname")
        return hostname
    except subprocess.CalledProcessError as e:
        print(f"Error getting hostname: {e}")
        return None

def set_wallpaper(wallpaper_path):
    """
    Sets the wallpaper using gsettings.

    Args:
        wallpaper_path: The full path to the wallpaper file.
    """
    try:
        subprocess.run(
            ["gsettings", "set", "org.cinnamon.desktop.background", "picture-uri", f"file://{wallpaper_path}"],
            check=True,
        )
        print(f"Wallpaper set to: {wallpaper_path}")
    except subprocess.CalledProcessError as e:
        print(f"Error: Could not set wallpaper to {wallpaper_path}: {e}")

def main():
    hostname = get_hostname()
    if hostname in schools:
        mode = get_current_theme()
        dark_path, light_path = get_wallpaper_paths(hostname)
        wallpaper_path = dark_path if mode == "dark" else light_path
        if os.path.exists(wallpaper_path):
            set_wallpaper(wallpaper_path)

def main():
    mode = get_current_theme()
    hostname = get_hostname()
    if hostname in schools:
        dark_path, light_path = get_wallpaper_paths(hostname)
        wallpaper_path = dark_path if mode == "dark" else light_path
        if os.path.exists(wallpaper_path):
            set_wallpaper(wallpaper_path)

if __name__ == "__main__":
    main()
