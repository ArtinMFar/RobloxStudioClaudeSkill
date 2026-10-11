#!/usr/bin/env python3
"""Download and unpack the current Roblox Studio (WindowsStudio64) build.

This replaces RobloxStudioInstaller.exe, which needs WebView2 and is flaky
under Wine. It does what Vinegar / Bloxstrap do: read the deployment's
rbxPkgManifest.txt, fetch every package zip from setup.rbxcdn.com, verify the
MD5, and extract it into the directory Studio expects.

Usage: bootstrap_studio.py [--dest DIR] [--channel CHANNEL] [--version VERSION]
Prints the install directory (the one containing RobloxStudioBeta.exe) on the
last line of stdout.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import sys
import time
import urllib.request
import zipfile

CDN = "https://setup.rbxcdn.com"
CLIENT_VERSION = "https://clientsettingscdn.roblox.com/v2/client-version/WindowsStudio64"

# Package -> sub directory, from Bloxstrap's RobloxStudioData/CommonAppData.
PACKAGE_DIRS = {
    "RobloxStudio.zip": "",
    "LibrariesQt5.zip": "",
    "Libraries.zip": "",
    "redist.zip": "",
    "WebView2.zip": "",
    "content-studio_svg_textures.zip": "content/studio_svg_textures",
    "content-qt_translations.zip": "content/qt_translations",
    "content-api-docs.zip": "content/api_docs",
    "extracontent-scripts.zip": "ExtraContent/scripts",
    "studiocontent-models.zip": "StudioContent/models",
    "studiocontent-textures.zip": "StudioContent/textures",
    "BuiltInPlugins.zip": "BuiltInPlugins",
    "BuiltInStandalonePlugins.zip": "BuiltInStandalonePlugins",
    "ApplicationConfig.zip": "ApplicationConfig",
    "Plugins.zip": "Plugins",
    "Qml.zip": "Qml",
    "StudioFonts.zip": "StudioFonts",
    "RibbonConfig.zip": "RibbonConfig",
    "shaders.zip": "shaders",
    "ssl.zip": "ssl",
    "WebView2RuntimeInstaller.zip": "WebView2RuntimeInstaller",
    "content-avatar.zip": "content/avatar",
    "content-configs.zip": "content/configs",
    "content-fonts.zip": "content/fonts",
    "content-sky.zip": "content/sky",
    "content-sounds.zip": "content/sounds",
    "content-textures2.zip": "content/textures",
    "content-models.zip": "content/models",
    "content-textures3.zip": "PlatformContent/pc/textures",
    "content-terrain.zip": "PlatformContent/pc/terrain",
    "content-platform-fonts.zip": "PlatformContent/pc/fonts",
    "content-platform-dictionaries.zip": "PlatformContent/pc/shared_compression_dictionaries",
    "extracontent-luapackages.zip": "ExtraContent/LuaPackages",
    "extracontent-translations.zip": "ExtraContent/translations",
    "extracontent-models.zip": "ExtraContent/models",
    "extracontent-textures.zip": "ExtraContent/textures",
    "extracontent-places.zip": "ExtraContent/places",
}

APP_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<Settings>
\t<ContentFolder>content</ContentFolder>
\t<BaseUrl>http://www.roblox.com</BaseUrl>
</Settings>
"""


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()


def parse_manifest(text):
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    if lines[0] != "v0":
        raise SystemExit(f"unexpected manifest header {lines[0]!r}")
    pkgs = []
    for i in range(1, len(lines), 4):
        pkgs.append({"name": lines[i], "md5": lines[i + 1]})
    return pkgs


def download(base, pkg, cache):
    path = os.path.join(cache, pkg["md5"] + ".zip")
    if os.path.exists(path):
        if hashlib.md5(open(path, "rb").read()).hexdigest() == pkg["md5"]:
            return path
    for attempt in range(6):
        try:
            data = fetch(f"{base}-{pkg['name']}")
        except Exception as e:  # proxies sometimes cut long transfers
            print(f"{pkg['name']}: {e!r} (attempt {attempt + 1})", file=sys.stderr)
            time.sleep(2 ** attempt)
            continue
        if hashlib.md5(data).hexdigest() == pkg["md5"]:
            with open(path + ".part", "wb") as f:
                f.write(data)
            os.replace(path + ".part", path)
            return path
        print(f"md5 mismatch for {pkg['name']} (attempt {attempt + 1})", file=sys.stderr)
    raise SystemExit(f"could not download {pkg['name']}")


def extract(zpath, dest):
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            # Roblox zips use Windows separators.
            name = info.filename.replace("\\", "/").lstrip("/")
            if not name or name.endswith("/"):
                continue
            out = os.path.normpath(os.path.join(dest, name))
            if not out.startswith(os.path.normpath(dest)):
                continue
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(info) as src, open(out, "wb") as dst:
                shutil.copyfileobj(src, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default=os.path.expanduser("~/.local/share/roblox-studio/versions"))
    ap.add_argument("--version", help="explicit version-xxxxxxxx hash")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/roblox-studio/downloads"))
    args = ap.parse_args()

    version = args.version or json.loads(fetch(CLIENT_VERSION))["clientVersionUpload"]
    install = os.path.join(args.dest, version)
    exe = os.path.join(install, "RobloxStudioBeta.exe")
    if os.path.exists(exe) and os.path.exists(os.path.join(install, ".complete")):
        print(f"{version} already installed", file=sys.stderr)
        print(install)
        return

    base = f"{CDN}/{version}"
    pkgs = parse_manifest(fetch(f"{base}-rbxPkgManifest.txt").decode())
    os.makedirs(args.cache, exist_ok=True)
    os.makedirs(install, exist_ok=True)

    unknown = [p["name"] for p in pkgs if p["name"] not in PACKAGE_DIRS]
    if unknown:
        print(f"warning: unknown packages, extracting to root: {unknown}", file=sys.stderr)

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        futs = {ex.submit(download, base, p, args.cache): p for p in pkgs}
        for fut in concurrent.futures.as_completed(futs):
            p = futs[fut]
            zpath = fut.result()
            extract(zpath, os.path.join(install, PACKAGE_DIRS.get(p["name"], "")))
            print(f"  {p['name']}", file=sys.stderr)

    with open(os.path.join(install, "AppSettings.xml"), "w") as f:
        f.write(APP_SETTINGS)
    os.makedirs(os.path.join(install, "ClientSettings"), exist_ok=True)
    open(os.path.join(install, ".complete"), "w").close()
    print(f"installed {version}", file=sys.stderr)
    print(install)


if __name__ == "__main__":
    main()
