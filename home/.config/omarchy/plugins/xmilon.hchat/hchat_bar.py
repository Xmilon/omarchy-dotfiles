#!/usr/bin/env python3
"""Local reader for the hchat bar widget. Never connects to the hchat server:
it only reads what hchat-relay already delivered to ~/.hchat/inbox/ and the
relay's heartbeat.

Read positions use hchat-inbox's format with its own reader name "bar"
(~/.hchat/inbox/.read-bar-<agent>: a byte offset, whole lines only, back to 0
if the file shrank). It never touches the agents' own .read-<agent>-<agent>
files. On first use the position starts at the end, so old messages are not
counted as unread.

    hchat_bar.py status            JSON: relay health, unread count and newest messages per agent
    hchat_bar.py read AGENT...     mark everything so far as read for the bar
"""
import json
import sys
import time
from pathlib import Path

HOME = Path.home() / ".hchat"
INBOX, RELAY = HOME / "inbox", HOME / "relay"
AGENTS = ["website", "game", "main"]
READER = "bar"
RECENT = 8          # newest messages listed per agent
TEXT_MAX = 400      # characters of each message passed to the widget


def pos_file(agent):
    return INBOX / f".read-{READER}-{agent}"


def whole_size(path):
    """Size up to the last complete line."""
    data = path.read_bytes()
    return data.rfind(b"\n") + 1


def read_pos(agent, path):
    pf = pos_file(agent)
    try:
        pos = int(pf.read_text())
    except FileNotFoundError:
        pos = whole_size(path)          # first use: start at the end
        pf.write_text(str(pos))
    except Exception:
        pos = 0
    if pos > path.stat().st_size:       # inbox truncated or rotated
        pos = 0
    return pos


def agent_status(agent):
    path = INBOX / f"{agent}.jsonl"
    if not path.exists():
        return {"name": agent, "unread": 0, "recent": []}
    pos = read_pos(agent, path)
    data = path.read_bytes()
    end = data.rfind(b"\n") + 1
    rows, offset = [], 0
    for raw in data[:end].split(b"\n")[:-1]:
        start = offset
        offset += len(raw) + 1
        try:
            m = json.loads(raw)
        except Exception:
            continue
        text = str(m.get("text", ""))
        rows.append({
            "id": m.get("id"),
            "from": m.get("from", ""),
            "to": m.get("to", ""),
            "kind": m.get("kind", "msg"),
            "at": m.get("at", 0),
            "text": text[:TEXT_MAX] + ("…" if len(text) > TEXT_MAX else ""),
            "unread": start >= pos,
        })
    unread = sum(1 for r in rows if r["unread"])
    return {"name": agent, "unread": unread, "recent": rows[-RECENT:][::-1]}


def relay_status():
    try:
        beat = int((RELAY / "heartbeat").read_text())
        age = int(time.time()) - beat
        return {"alive": age < 90, "age": age}
    except Exception:
        return {"alive": False, "age": None}


def main(argv):
    if len(argv) >= 2 and argv[1] == "status":
        out = {"relay": relay_status(), "agents": [agent_status(a) for a in AGENTS]}
        out["unread"] = sum(a["unread"] for a in out["agents"])
        print(json.dumps(out, ensure_ascii=False))
        return 0
    if len(argv) >= 3 and argv[1] == "read":
        for agent in argv[2:]:
            if agent not in AGENTS:
                continue
            path = INBOX / f"{agent}.jsonl"
            if path.exists():
                pos_file(agent).write_text(str(whole_size(path)))
        print(json.dumps({"ok": True}))
        return 0
    print(json.dumps({"error": "usage: hchat_bar.py status | read AGENT..."}))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
