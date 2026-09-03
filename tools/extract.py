#!/usr/bin/env python3
"""Pull every Run Script body out of source/info.plist into source/scripts/.

Use this after editing scripts inside Alfred's own editor, to bring those edits
back under version control. Scripts that use --#include cannot be round-tripped,
so extract.py refuses to overwrite a file whose built form still matches the
plist (i.e. nothing changed in Alfred).
"""

import sys

from workflow import SCRIPTS, expand_includes, load_manifest, load_plist, script_objects


def main():
    manifest = load_manifest()
    configs = script_objects(load_plist())
    SCRIPTS.mkdir(parents=True, exist_ok=True)

    unmapped = sorted(set(configs) - set(manifest))
    if unmapped:
        print("warning: no manifest entry for", ", ".join(unmapped), file=sys.stderr)

    for uid, name in sorted(manifest.items(), key=lambda kv: kv[1]):
        if uid not in configs:
            print(f"warning: {name}: uid {uid} is not in info.plist", file=sys.stderr)
            continue
        plist_body = configs[uid].get("script", "")
        path = SCRIPTS / name
        if path.exists():
            built = expand_includes(path.read_text(), SCRIPTS).rstrip("\n")
            if built == plist_body.rstrip("\n"):
                print(f"unchanged  {name}")
                continue
            if built != path.read_text().rstrip("\n"):
                print(
                    f"SKIPPED    {name} (uses --#include; edit the source files "
                    "instead of Alfred)",
                    file=sys.stderr,
                )
                continue
        path.write_text(plist_body.rstrip("\n") + "\n")
        print(f"extracted  {name}")


if __name__ == "__main__":
    main()
