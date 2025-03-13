// Disable firefox cache
pref("browser.cache.disk.enable",false);

// Disable internal PDF viewer
pref("pdfjs.disabled",true);

// Enable flash on file:// URLs
pref("plugins.http_https_only",false);

// Install uBlock Origin extension
pref("extensions.autoDisableScopes", 0);
pref("extensions.enabledScopes", 15);
pref("extensions.installDistroAddons", false);
pref("extensions.autoDisableScopes", 0);
pref("extensions.enabledScopes", 15);
pref("extensions.installDistroAddons", false);
pref("extensions.install.requireBuiltInCerts", false);
pref("extensions.update.enabled", true);
pref("extensions.update.autoUpdateDefault", true);
pref("extensions.update.autoUpdate", true);
pref("extensions.update.background.url", "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-607454-latest.xpi");