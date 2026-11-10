"""Builds everything for a release.

  python tools/package.py            build helper, run tests, write dist/ zips
  python tools/package.py --install  same, then copy the addon into WoW Forever's AddOns folder

dist/DinkForDiscord-<version>.zip         upload to CurseForge (contains the DinkForDiscord folder)
dist/DinkForDiscordHelper-<version>.zip   attach to a GitHub release (contains DinkHelper.exe)
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "DinkForDiscord")
HELPER_PROJ = os.path.join(ROOT, "Helper", "DinkHelper")
HELPER_EXE = os.path.join(HELPER_PROJ, "bin", "Release", "net48", "DinkHelper.exe")
DIST = os.path.join(ROOT, "dist")
WOW_ADDONS = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"


def version():
    toc = open(os.path.join(ADDON, "DinkForDiscord.toc"), encoding="utf-8").read()
    return re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)


def run(cmd, **kw):
    print("> " + " ".join(cmd))
    subprocess.run(cmd, check=True, **kw)


def main():
    ver = version()
    run(["dotnet", "build", "-c", "Release", "-nologo", "-v", "q", HELPER_PROJ])
    run([sys.executable, os.path.join(ROOT, "tests", "run_tests.py")])

    os.makedirs(DIST, exist_ok=True)
    addon_zip = os.path.join(DIST, f"DinkForDiscord-{ver}.zip")
    with zipfile.ZipFile(addon_zip, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(ADDON):
            for f in files:
                full = os.path.join(base, f)
                z.write(full, os.path.join("DinkForDiscord", os.path.relpath(full, ADDON)))
    helper_zip = os.path.join(DIST, f"DinkForDiscordHelper-{ver}.zip")
    with zipfile.ZipFile(helper_zip, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(HELPER_EXE, "DinkHelper.exe")
        z.write(HELPER_EXE + ".config", "DinkHelper.exe.config")
    try:
        shutil.copy2(HELPER_EXE, os.path.join(DIST, "DinkHelper.exe"))
        shutil.copy2(HELPER_EXE + ".config", os.path.join(DIST, "DinkHelper.exe.config"))
    except PermissionError:
        print("note: dist/DinkHelper.exe is running, so it wasn't replaced (the zip is up to date)")
    print("wrote", addon_zip)
    print("wrote", helper_zip)

    if "--install" in sys.argv:
        target = os.path.join(WOW_ADDONS, "DinkForDiscord")
        if os.path.isdir(target):
            shutil.rmtree(target)
        shutil.copytree(ADDON, target)
        print("installed to", target)


if __name__ == "__main__":
    main()
