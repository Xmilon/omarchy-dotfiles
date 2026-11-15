#!/usr/bin/env python3
"""Storage for the Quick Notes bar widget.

Each page is a plain Markdown file in ~/Notes/Quick/<id>.md with a small header:

    ---
    title: Shopping
    created: 2026-11-15T20:16:00
    pinned: false
    ---
    the note text...

Commands (all print JSON on stdout):
    list                 every page, pinned first, then newest edit first
    save <json>          create or update a page from {"id","title","pinned","body"}
    trash <id>           move a page to the desktop trash
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

NOTES_DIR = Path(os.environ.get("QUICK_NOTES_DIR", Path.home() / "Notes" / "Quick"))
ID_RE = re.compile(r"^[a-z0-9-]{1,40}$")
MAX_TITLE = 120
MAX_BODY = 100_000


def now_iso():
    return datetime.now().replace(microsecond=0).isoformat()


def clean_title(title):
    title = " ".join(str(title or "").split())  # no newlines in the header
    return title[:MAX_TITLE]


def parse(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    meta, body = {}, text
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            for line in text[4:end].splitlines():
                key, sep, value = line.partition(":")
                if sep:
                    meta[key.strip()] = value.strip()
            body = text[end + 5:]
    stat = path.stat()
    return {
        "id": path.stem,
        "title": clean_title(meta.get("title", "")) or "Untitled",
        "created": meta.get("created")
        or datetime.fromtimestamp(stat.st_mtime).replace(microsecond=0).isoformat(),
        "updated": datetime.fromtimestamp(stat.st_mtime).replace(microsecond=0).isoformat(),
        "pinned": meta.get("pinned", "false").lower() == "true",
        "body": body,
    }


def list_notes():
    if not NOTES_DIR.is_dir():
        return []
    notes = []
    for path in NOTES_DIR.glob("*.md"):
        if ID_RE.match(path.stem):
            try:
                notes.append(parse(path))
            except OSError:
                continue
    notes.sort(key=lambda n: n["updated"], reverse=True)
    notes.sort(key=lambda n: not n["pinned"])  # stable: pinned first, newest first within
    return notes


def save(raw):
    data = json.loads(raw)
    note_id = str(data.get("id") or "")
    if not note_id:
        note_id = time.strftime("%Y%m%d-%H%M%S") + "-" + os.urandom(2).hex()
    if not ID_RE.match(note_id):
        raise ValueError("bad note id")

    NOTES_DIR.mkdir(parents=True, exist_ok=True)
    path = NOTES_DIR / f"{note_id}.md"
    created = parse(path)["created"] if path.exists() else now_iso()
    title = clean_title(data.get("title")) or "Untitled"
    body = str(data.get("body") or "")[:MAX_BODY]
    pinned = "true" if data.get("pinned") else "false"

    content = f"---\ntitle: {title}\ncreated: {created}\npinned: {pinned}\n---\n{body}"
    # Write to a temp file and rename, so a crash never leaves half a note.
    fd, tmp = tempfile.mkstemp(dir=NOTES_DIR, prefix=".tmp-", suffix=".md")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(content)
    os.replace(tmp, path)
    return parse(path)


def trash(note_id):
    if not ID_RE.match(note_id):
        raise ValueError("bad note id")
    path = NOTES_DIR / f"{note_id}.md"
    if path.exists():
        subprocess.run(["gio", "trash", "--", str(path)], check=True)
    return {"id": note_id, "trashed": True}


def main(argv):
    try:
        if len(argv) >= 2 and argv[1] == "list":
            out = list_notes()
        elif len(argv) >= 3 and argv[1] == "save":
            out = save(argv[2])
        elif len(argv) >= 3 and argv[1] == "trash":
            out = trash(argv[2])
        else:
            raise ValueError("usage: notes.py list | save <json> | trash <id>")
        print(json.dumps(out))
        return 0
    except Exception as exc:  # report to the widget instead of crashing silently
        print(json.dumps({"error": str(exc)}))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
