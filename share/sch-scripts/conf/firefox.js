// Disable firefox cache
pref("browser.cache.disk.enable", false);

// Disable internal PDF viewer
pref("pdfjs.disabled", true);

// Enable flash on file:// URLs
pref("plugins.http_https_only", false);

// Install uBlock Origin
pref("extensions.autoDisableScopes", 10);
pref("extensions.blocklist.enabled", false);
pref("extensions.install.requireBuiltInCerts", false);
pref("extensions.install.allowInstallationWithoutUserInteraction", true);
pref("extensions.install.allowDowngrades", true);
pref("extensions.update.enabled", true);
pref("extensions.update.autoUpdateDefault", true);
pref("xpinstall.signatures.required", false);

// uBlock Origin extension ID
pref("extensions.install.url", "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-607465-latest.xpi");
pref("extensions.install.id", "uBlock0@raymondhill.net");
