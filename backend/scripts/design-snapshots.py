#!/usr/bin/env python3
"""design-snapshots.py — save / restore full visual designs (solstice).

A "design" is everything that defines the look: wallpaper, theme engine,
matugen scheme + mode, wallpaper settings, topbar/font styling and the
application-theming toggles. Snapshots let you try designs freely and jump
back to an earlier one at any time from Settings → Wallpaper & style.

Usage:
    design-snapshots.py save              # snapshot current design, prints id
    design-snapshots.py list              # print index.json (newest first)
    design-snapshots.py restore <id>      # restore files, print meta JSON
    design-snapshots.py delete <id>       # delete a snapshot

Snapshots live in ~/.config/quickshell/solstice/style/themes/snapshots/<id>/ with a
meta.json, copies of the design configs and a copy of the wallpaper (so a
snapshot survives the original file being moved or deleted).
"""
import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys

HOME = pathlib.Path.home()
SOLSTICE = HOME / ".config/quickshell/solstice"
THEMES = SOLSTICE / "style" / "themes"
CONFIG = SOLSTICE / "backend" / "config"
SNAP_BASE = THEMES / "snapshots"
INDEX = SNAP_BASE / "index.json"

# design state files, relative to SOLSTICE
STATE_FILES = [
    "style/themes/theme_engine.json",
    "style/themes/matugen_settings.json",
    "backend/config/current_wallpaper.txt",
    "backend/config/wallpaper_settings.json",
    "backend/config/topbar_settings.json",
    "backend/config/font_settings.json",
    "backend/config/theming_settings.json",
]

PRESET_IDS = ("everforest", "tokyonight", "petrichor", "monochrome", "catppuccin", "gruvbox")
MAX_KEEP = 20
WALLPAPER_COPY_LIMIT = 64 * 1024 * 1024

ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*")


def notify(summary: str) -> None:
    try:
        subprocess.run(["notify-send", "-u", "low", "Designs", summary],
                       check=False, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=5)
    except Exception:
        pass


def atomic_write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def read_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def read_index() -> list:
    try:
        data = json.loads(INDEX.read_text())
        return data if isinstance(data, list) else []
    except Exception:
        return []


def write_index(entries: list) -> None:
    atomic_write(INDEX, json.dumps(entries, indent=2, ensure_ascii=False) + "\n")


def current_state() -> dict:
    engine = read_json(THEMES / "theme_engine.json").get("engine", "wallpaper")
    if engine not in ("wallpaper",) + PRESET_IDS:
        engine = "wallpaper"
    matugen = read_json(THEMES / "matugen_settings.json")
    mtype = matugen.get("type", "scheme-tonal-spot")
    if not re.fullmatch(r"scheme-[a-z-]+", mtype or ""):
        mtype = "scheme-tonal-spot"
    mode = matugen.get("mode", "dark")
    if mode not in ("dark", "light"):
        mode = "dark"
    try:
        wall = (CONFIG / "current_wallpaper.txt").read_text().strip().splitlines()[0].strip()
    except Exception:
        wall = ""
    return {"engine": engine, "type": mtype, "mode": mode, "wallpaper": wall}


def display_name(state: dict) -> str:
    now = datetime.datetime.now().strftime("%d.%m. %H:%M")
    mode_label = "Light" if state["mode"] == "light" else "Dark"
    if state["engine"] == "wallpaper":
        short = state["type"].replace("scheme-", "").replace("-", " ")
        short = " ".join(w[:1].upper() + w[1:] for w in short.split())
        return f"Wallpaper • {short} • {mode_label} — {now}"
    label = {"everforest": "Everforest", "tokyonight": "Tokyo Night",
             "petrichor": "Petrichor", "monochrome": "Monochrome",
             "catppuccin": "Catppuccin", "gruvbox": "Gruvbox"}.get(state["engine"], state["engine"])
    return f"{label} • {mode_label} — {now}"


def cmd_save() -> int:
    state = current_state()
    SNAP_BASE.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    snap_id = stamp
    n = 1
    while (SNAP_BASE / snap_id).exists():
        n += 1
        snap_id = f"{stamp}-{n}"
    dest = SNAP_BASE / snap_id
    dest.mkdir(parents=True)
    for rel in STATE_FILES:
        src = SOLSTICE / rel
        if src.is_file():
            (dest / pathlib.Path(rel).name).write_bytes(src.read_bytes())
    wall_copy = ""
    wall = state["wallpaper"]
    if wall:
        try:
            src = pathlib.Path(wall)
            if src.is_file() and src.stat().st_size <= WALLPAPER_COPY_LIMIT:
                wall_copy = "wallpaper" + src.suffix.lower()[:8]
                shutil.copy2(src, dest / wall_copy)
        except OSError:
            wall_copy = ""
    meta = {"id": snap_id, "name": display_name(state),
            "created": datetime.datetime.now().isoformat(timespec="seconds"),
            "engine": state["engine"], "type": state["type"], "mode": state["mode"],
            "wallpaper": wall, "wallpaper_copy": wall_copy}
    (dest / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    entries = [e for e in read_index() if e.get("id") != snap_id]
    entries.insert(0, {"id": snap_id, "name": meta["name"], "created": meta["created"],
                       "engine": meta["engine"], "type": meta["type"], "mode": meta["mode"]})
    # bound disk usage: wallpapers add up, keep the newest MAX_KEEP
    for old in entries[MAX_KEEP:]:
        shutil.rmtree(SNAP_BASE / old["id"], ignore_errors=True)
    del entries[MAX_KEEP:]
    write_index(entries)
    notify(f"Saved: {meta['name']}")
    print(snap_id)
    return 0


def cmd_list() -> int:
    print(json.dumps(read_index(), ensure_ascii=False))
    return 0


def cmd_restore(snap_id: str) -> int:
    if not ID_RE.fullmatch(snap_id or ""):
        print("error: invalid snapshot id", file=sys.stderr)
        return 1
    dest = SNAP_BASE / snap_id
    meta_path = dest / "meta.json"
    if not meta_path.is_file():
        print(f"error: unknown snapshot {snap_id}", file=sys.stderr)
        return 1
    try:
        meta = json.loads(meta_path.read_text())
    except Exception:
        print("error: unreadable snapshot meta", file=sys.stderr)
        return 1
    for rel in STATE_FILES:
        src = dest / pathlib.Path(rel).name
        if src.is_file():
            dst = SOLSTICE / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            tmp = dst.with_name(dst.name + ".tmp")
            tmp.write_bytes(src.read_bytes())
            tmp.replace(dst)
    wall = ""
    copy_name = meta.get("wallpaper_copy", "")
    copy_path = str(dest / copy_name) if copy_name and (dest / copy_name).is_file() else ""
    orig = meta.get("wallpaper", "")
    # Prefer the original path when it still exists (keeps wallpaper-grid
    # highlighting and stable pointers); the snapshot copy is the fallback
    # that survives moves/deletes of the original.
    if orig and pathlib.Path(orig).is_file():
        wall = orig
    else:
        wall = copy_path
    out = {"id": snap_id, "name": meta.get("name", snap_id),
           "engine": meta.get("engine", "wallpaper"),
           "type": meta.get("type", "scheme-tonal-spot"),
           "mode": meta.get("mode", "dark"), "wallpaper": wall,
           "wallpaper_copy": copy_path}
    if out["engine"] not in ("wallpaper",) + PRESET_IDS:
        out["engine"] = "wallpaper"
    notify(f"Restored: {out['name']}")
    print(json.dumps(out, ensure_ascii=False))
    return 0


def cmd_delete(snap_id: str) -> int:
    if not ID_RE.fullmatch(snap_id or ""):
        print("error: invalid snapshot id", file=sys.stderr)
        return 1
    shutil.rmtree(SNAP_BASE / snap_id, ignore_errors=True)
    write_index([e for e in read_index() if e.get("id") != snap_id])
    print(f"deleted {snap_id}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        sys.exit(1)
    action = sys.argv[1]
    if action == "save":
        sys.exit(cmd_save())
    if action == "list":
        sys.exit(cmd_list())
    if action == "restore" and len(sys.argv) > 2:
        sys.exit(cmd_restore(sys.argv[2]))
    if action == "delete" and len(sys.argv) > 2:
        sys.exit(cmd_delete(sys.argv[2]))
    print(f"usage: {sys.argv[0]} {{save|list|restore <id>|delete <id>}}", file=sys.stderr)
    sys.exit(1)
