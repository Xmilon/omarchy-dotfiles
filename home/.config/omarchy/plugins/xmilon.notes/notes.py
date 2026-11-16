#!/usr/bin/env python3
"""Storage for the Quick Notes bar widget.

Each page is a plain Markdown file in ~/Notes/Quick/<id>.md with a small header:

    ---
    title: Shopping
    created: 2026-11-15T20:16:00
    pinned: false
    ---
    the note text...

Attachments (images, videos, any file) live in ~/Notes/Quick/media/<id>/.

Commands (all print JSON on stdout):
    list                 every page, pinned first, then newest edit first
    save <json>          create or update a page from {"id","title","pinned","body"}
    trash <id>           move a page (and its attachments) to the desktop trash
    attach <id> <path>   copy a file into the page's attachments
    paste-image <id>     save the image on the clipboard as an attachment
    detach <id> <name>   move one attachment to the trash
"""

import json
import mimetypes
import os
import shutil
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
from datetime import datetime
from pathlib import Path

NOTES_DIR = Path(os.environ.get("QUICK_NOTES_DIR", Path.home() / "Notes" / "Quick"))
ID_RE = re.compile(r"^[a-z0-9-]{1,40}$")
MAX_TITLE = 120
MAX_BODY = 100_000
MAX_ATTACHMENT = 500 * 1024 * 1024
MEDIA_DIR = NOTES_DIR / "media"


def attachments(note_id):
    folder = MEDIA_DIR / note_id
    if not folder.is_dir():
        return []
    items = []
    for f in sorted(folder.iterdir(), key=lambda p: p.stat().st_mtime):
        if not f.is_file() or f.name.startswith("."):
            continue
        mime = mimetypes.guess_type(f.name)[0] or "application/octet-stream"
        items.append({
            "name": f.name,
            "path": str(f),
            "kind": mime.split("/")[0],      # image, video, audio, text, application
            "size": f.stat().st_size,
        })
    return items


def safe_name(name):
    name = os.path.basename(str(name)).strip().replace("/", "_")
    name = "".join(c for c in name if c.isprintable() and c not in '\\:*?"<>|')
    return name[:120] or "file"


def unique_path(folder, name):
    stem, ext = os.path.splitext(name)
    candidate, n = folder / name, 2
    while candidate.exists():
        candidate, n = folder / f"{stem} ({n}){ext}", n + 1
    return candidate


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
        "attachments": attachments(path.stem),
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
    media = MEDIA_DIR / note_id
    if media.is_dir():
        subprocess.run(["gio", "trash", "--", str(media)], check=True)
    return {"id": note_id, "trashed": True}


def check_note(note_id):
    if not ID_RE.match(note_id):
        raise ValueError("bad note id")
    if not (NOTES_DIR / f"{note_id}.md").exists():
        raise ValueError("save the page before attaching files")


def attach(note_id, src):
    check_note(note_id)
    src = str(src)
    if src.startswith("file://"):                 # dragged files arrive as URLs
        src = urllib.parse.unquote(urllib.parse.urlparse(src).path)
    src = Path(src).expanduser().resolve()
    if not src.is_file():
        raise ValueError(f"not a file: {src}")
    if src.stat().st_size > MAX_ATTACHMENT:
        raise ValueError("file is larger than 500 MB")
    folder = MEDIA_DIR / note_id
    folder.mkdir(parents=True, exist_ok=True)
    dst = unique_path(folder, safe_name(src.name))
    shutil.copy2(src, dst)
    return attachments(note_id)


def paste_image(note_id):
    check_note(note_id)
    types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True).stdout.split()
    image_type = next((t for t in ("image/png", "image/jpeg", "image/webp", "image/gif") if t in types), None)
    if not image_type:
        raise ValueError("no image on the clipboard")
    data = subprocess.run(["wl-paste", "--type", image_type], capture_output=True).stdout
    if not data or len(data) > MAX_ATTACHMENT:
        raise ValueError("clipboard image is empty or too large")
    folder = MEDIA_DIR / note_id
    folder.mkdir(parents=True, exist_ok=True)
    ext = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "image/gif": ".gif"}[image_type]
    dst = unique_path(folder, "pasted-" + time.strftime("%Y%m%d-%H%M%S") + ext)
    dst.write_bytes(data)
    return attachments(note_id)


def detach(note_id, name):
    if not ID_RE.match(note_id):
        raise ValueError("bad note id")
    target = MEDIA_DIR / note_id / safe_name(name)
    if target.parent != MEDIA_DIR / note_id or not target.is_file():
        raise ValueError("no such attachment")
    subprocess.run(["gio", "trash", "--", str(target)], check=True)
    return attachments(note_id)


def main(argv):
    try:
        if len(argv) >= 2 and argv[1] == "list":
            out = list_notes()
        elif len(argv) >= 3 and argv[1] == "save":
            out = save(argv[2])
        elif len(argv) >= 3 and argv[1] == "trash":
            out = trash(argv[2])
        elif len(argv) >= 4 and argv[1] == "attach":
            out = attach(argv[2], argv[3])
        elif len(argv) >= 3 and argv[1] == "paste-image":
            out = paste_image(argv[2])
        elif len(argv) >= 4 and argv[1] == "detach":
            out = detach(argv[2], argv[3])
        else:
            raise ValueError("usage: notes.py list | save <json> | trash <id> | attach <id> <path> | paste-image <id> | detach <id> <name>")
        print(json.dumps(out))
        return 0
    except Exception as exc:  # report to the widget instead of crashing silently
        print(json.dumps({"error": str(exc)}))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
