"""Shared helpers for moving Run Script bodies between source/scripts/ and info.plist.

The workflow ships as a single info.plist with every AppleScript inlined, which
makes diffs unreadable and single-script testing impossible. tools/extract.py and
tools/build.py use this module to keep the scripts in source/scripts/ as the
editable form and treat info.plist as a build artifact.
"""

import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / "source" / "info.plist"
SCRIPTS = ROOT / "source" / "scripts"
MANIFEST = Path(__file__).resolve().parent / "manifest.json"

INCLUDE_RE = re.compile(r"^[ \t]*--#include[ \t]+(\S+)[ \t]*$", re.MULTILINE)


def load_manifest():
    data = json.loads(MANIFEST.read_text())
    return {k: v for k, v in data.items() if not k.startswith("_")}


def load_plist():
    with PLIST.open("rb") as fh:
        return plistlib.load(fh)


def save_plist(data):
    # plistlib writes <real>3000.0</real> where Alfred writes <real>3000</real>.
    # Normalising keeps the diff limited to the scripts we actually changed.
    raw = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=True)
    raw = re.sub(rb"<real>(-?\d+)\.0</real>", rb"<real>\1</real>", raw)
    PLIST.write_bytes(raw)


def script_objects(data):
    """uid -> config dict for every Run Script object."""
    return {
        o["uid"]: o["config"]
        for o in data["objects"]
        if o["type"] == "alfred.workflow.action.script"
    }


def expand_includes(text, base, _seen=None):
    """Inline `--#include lib/foo.applescript` directives, recursively."""
    _seen = _seen or []

    def repl(match):
        rel = match.group(1)
        path = (base / rel).resolve()
        if path in _seen:
            raise SystemExit(f"circular --#include: {rel}")
        if not path.exists():
            raise SystemExit(f"--#include target not found: {rel}")
        body = path.read_text().rstrip("\n")
        return expand_includes(body, base, _seen + [path])

    return INCLUDE_RE.sub(repl, text)
