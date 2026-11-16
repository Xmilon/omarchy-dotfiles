#!/usr/bin/env python3
"""Copy several clipboard-history items at once (Ctrl+click, then Ctrl+C).

    clipcopy.py '{"texts": ["a", "b"], "files": ["/path/img.png"]}'

Only text: copied as one text, items separated by a blank line.
Any images or files: copied as a file list (paste into Files, Discord, a
browser upload...). Text items then go along as .txt files so nothing is lost.
"""

import json
import os
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "xmilon-clipboard"


def main():
    data = json.loads(sys.argv[1])
    texts = [str(t) for t in data.get("texts", []) if str(t)]
    files = [str(f) for f in data.get("files", []) if f and Path(f).exists()]

    if not files:
        subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"],
                       input="\n\n".join(texts).encode(), check=True)
        return

    if texts:
        folder = CACHE / time.strftime("%Y%m%d-%H%M%S")
        folder.mkdir(parents=True, exist_ok=True)
        for n, text in enumerate(texts, 1):
            path = folder / f"text-{n}.txt"
            path.write_text(text, encoding="utf-8")
            files.append(str(path))

    uris = "".join("file://" + urllib.parse.quote(os.path.abspath(f)) + "\r\n" for f in files)
    subprocess.run(["wl-copy", "--type", "text/uri-list"], input=uris.encode(), check=True)


if __name__ == "__main__":
    main()
