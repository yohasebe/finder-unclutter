#!/usr/bin/env python3
"""Inject source/scripts/ into source/info.plist, then package the workflow.

    python3 tools/build.py            # update source/info.plist only
    python3 tools/build.py --package  # also write finder-unclutter.alfredworkflow
    python3 tools/build.py --install  # also copy into the live Alfred workflow dir
"""

import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
from fnmatch import fnmatch

from workflow import (
    PLIST,
    ROOT,
    SCRIPTS,
    expand_includes,
    load_manifest,
    load_plist,
    save_plist,
    script_objects,
)

BUNDLE_ID = "com.yohasebe.finder.unclutter"
INSTALL_DIR_ENV = "FINDER_UNCLUTTER_WORKFLOW_DIR"


def alfred_preferences_dir():
    """Where Alfred keeps its workflows, honouring a synced preferences folder."""
    candidates = []
    try:
        synced = subprocess.run(
            ["defaults", "read", "com.runningwithcrayons.Alfred-Preferences", "syncfolder"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if synced:
            candidates.append(os.path.join(os.path.expanduser(synced), "Alfred.alfredpreferences"))
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    candidates.append(
        os.path.expanduser("~/Library/Application Support/Alfred/Alfred.alfredpreferences")
    )
    return [c for c in candidates if os.path.isdir(c)]


def installed_workflow_dir():
    """The live workflow directory for this workflow, found by its bundle id.

    Alfred names workflow directories with a random uuid, so the path differs on
    every machine and must never be hard-coded here. Set
    FINDER_UNCLUTTER_WORKFLOW_DIR to override.
    """
    override = os.environ.get(INSTALL_DIR_ENV)
    if override:
        return os.path.expanduser(override)
    for prefs in alfred_preferences_dir():
        workflows = os.path.join(prefs, "workflows")
        if not os.path.isdir(workflows):
            continue
        for name in sorted(os.listdir(workflows)):
            candidate = os.path.join(workflows, name, "info.plist")
            try:
                with open(candidate, "rb") as fh:
                    if plistlib.load(fh).get("bundleid") == BUNDLE_ID:
                        return os.path.dirname(candidate)
            except Exception:
                continue
    return None


def inject():
    manifest = load_manifest()
    data = load_plist()
    configs = script_objects(data)
    changed = []

    for uid, name in sorted(manifest.items(), key=lambda kv: kv[1]):
        path = SCRIPTS / name
        if not path.exists():
            sys.exit(f"error: {name} is in the manifest but missing from source/scripts/")
        if uid not in configs:
            sys.exit(f"error: {name}: uid {uid} is not in info.plist")
        body = expand_includes(path.read_text(), SCRIPTS).rstrip("\n")
        if configs[uid].get("script", "") != body:
            configs[uid]["script"] = body
            changed.append(name)

    orphans = sorted(set(configs) - set(manifest))
    if orphans:
        sys.exit("error: Run Script objects with no manifest entry: " + ", ".join(orphans))

    if changed:
        save_plist(data)
    return changed


def lint():
    subprocess.run(["plutil", "-lint", str(PLIST)], check=True, stdout=subprocess.DEVNULL)
    print("lint       info.plist ok")


# What may go into the distributed .alfredworkflow. Anything under source/ that
# is not allowed here aborts the build rather than shipping, because the
# 2025-09-22 release went out with an `info.plist.bak` inside it -- picked up by
# Alfred's own GUI export from the live workflow directory -- and the history had
# to be rewritten to get it out again.
#
# Files are matched by name wherever the set is fixed, and only by pattern where
# Alfred itself generates names: List Filter images, which it names by content
# hash, and per-object icons, which it writes to the workflow root as
# <object-uid>.png. Those two patterns are narrow on purpose -- a bare "*.png"
# would wave through a screenshot dropped into source/, which is the same shape
# of mistake as the .bak.
BUNDLE_ALLOW_NAMES = ("info.plist", "icon.png", "finder-unclutter@2x.png")
BUNDLE_ALLOW_GLOBS = ("List Filter Images/*.png",)
ALFRED_OBJECT_ICON = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.png$"
)
BUNDLE_REQUIRE = ("info.plist",)


def allowed_in_bundle(rel_path):
    if rel_path in BUNDLE_ALLOW_NAMES:
        return True
    if any(fnmatch(rel_path, glob) for glob in BUNDLE_ALLOW_GLOBS):
        return True
    return bool(ALFRED_OBJECT_ICON.match(rel_path))


def package():
    out = ROOT / "finder-unclutter.alfredworkflow"
    src = ROOT / "source"

    members = []
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if d != "scripts"]
        for fn in sorted(filenames):
            if fn == ".DS_Store":
                continue
            full = os.path.join(dirpath, fn)
            members.append(os.path.relpath(full, src))
    members.sort()

    rejected = [m for m in members if not allowed_in_bundle(m)]
    if rejected:
        sys.exit(
            "error: source/ holds files that are not allowed in the workflow bundle:\n"
            + "".join(f"  {m}\n" for m in rejected)
            + "Remove them, or allow them in tools/build.py (BUNDLE_ALLOW_NAMES / "
            + "BUNDLE_ALLOW_GLOBS)."
        )
    missing = [p for p in BUNDLE_REQUIRE if p not in members]
    if missing:
        sys.exit("error: missing from source/: " + ", ".join(missing))

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for m in members:
            zf.write(os.path.join(src, m), m)
    print(f"packaged   {out.name} ({len(members)} files)")


def install():
    target = installed_workflow_dir()
    if not target:
        sys.exit(
            f"error: no installed workflow with bundle id {BUNDLE_ID} found.\n"
            f"Install it in Alfred first, or set {INSTALL_DIR_ENV} to its directory."
        )
    shutil.copy2(PLIST, os.path.join(target, "info.plist"))
    print(f"installed  info.plist -> {target}")
    print("           restart Alfred so it reloads the workflow")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", action="store_true")
    ap.add_argument("--install", action="store_true")
    args = ap.parse_args()

    changed = inject()
    for name in changed:
        print(f"injected   {name}")
    if not changed:
        print("injected   (no changes)")
    lint()
    if args.package:
        package()
    if args.install:
        install()


if __name__ == "__main__":
    main()
