#!/usr/bin/env python3
"""matugen-themes.py — App Theming catalogue for solstice.

Browses the InioX/matugen-themes template collection (catalogue in
backend/config/matugen_themes.json), detects which templates are installed
([templates.*] blocks in ~/.config/matugen/config.toml) and active
(theming_settings.json toggles), and installs or removes them.

Usage:
    matugen-themes.py list                 # JSON status for the settings page
    matugen-themes.py install <id>         # download + wire + enable one theme
    matugen-themes.py remove <id>          # drop the config blocks again
    matugen-themes.py download <remote> <dest>   # internal helper

All commands print a single JSON object on stdout; failures exit non-zero.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

HOME = Path.home()
SOLSTICE = HOME / ".config/quickshell/solstice"
CATALOG_FILE = SOLSTICE / "backend/config/matugen_themes.json"
THEMING_FILE = SOLSTICE / "backend/config/theming_settings.json"
MATUGEN_CONFIG = HOME / ".config/matugen/config.toml"
TEMPLATES_DIR = HOME / ".config/matugen/templates"

BLOCK_RE = re.compile(r'^\s*\[templates\.([^\]\s]+)\]\s*$')


def expand(text: str) -> str:
    if not text:
        return ""
    out = text.replace("{HOME}", str(HOME)).replace("{templates}", str(TEMPLATES_DIR))
    if out.startswith("~/"):
        out = str(HOME / out[2:])
    return out


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    tmp.write_text(text)
    os.replace(tmp, path)


def catalog():
    data = read_json(CATALOG_FILE)
    entries = data.get("entries", [])
    data["entries"] = [e for e in entries if isinstance(e, dict) and e.get("id")]
    return data


def config_text() -> str:
    try:
        return MATUGEN_CONFIG.read_text()
    except OSError:
        return ""


def installed_block_ids() -> set:
    ids = set()
    for line in config_text().splitlines():
        m = BLOCK_RE.match(line)
        if m:
            ids.add(m.group(1))
    return ids


def theming() -> dict:
    return read_json(THEMING_FILE)


def block_text(block: dict) -> str:
    lines = [f"[templates.{block['id']}]"]
    lines.append(f'input_path = "{expand(block.get("input", ""))}"')
    lines.append(f'output_path = "{expand(block.get("output", ""))}"')
    hook = expand(block.get("post_hook", ""))
    if hook:
        escaped = hook.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'post_hook = "{escaped}"')
    return "\n".join(lines) + "\n"


def remove_blocks(text: str, ids: set) -> str:
    out, cur_id, cur = [], None, []

    def flush() -> None:
        if cur_id is None:
            return
        if cur_id not in ids:
            out.append("".join(cur))
        elif out:
            # Drop the blank separator line that install added with the block.
            if out[-1].strip() == "":
                out.pop()
            elif out[-1].endswith("\n\n"):
                out[-1] = out[-1][:-1]

    for line in text.splitlines(keepends=True):
        m = BLOCK_RE.match(line)
        if m:
            flush()
            cur_id, cur = m.group(1), [line]
        elif cur_id is not None and line.startswith("[") and not line.startswith("[templates."):
            flush()
            cur_id, cur = None, []
            out.append(line)
        elif cur_id is not None:
            cur.append(line)
        else:
            out.append(line)
    flush()
    return "".join(out)


def download(remote: str, dest: Path, raw_base: str) -> None:
    url = raw_base.rstrip("/") + "/" + remote.lstrip("/")
    req = urllib.request.Request(url, headers={"User-Agent": "solstice-app-theming"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + f".tmp.{os.getpid()}")
    tmp.write_bytes(data)
    os.replace(tmp, dest)


def entry_status(entry: dict, have: set, t: dict) -> dict:
    blocks = entry.get("blocks", [])
    real = [b for b in blocks if b.get("id") and b.get("output")]
    tracked = [b for b in blocks if b.get("id") or b.get("output")]
    present = [b for b in real if b["id"] in have]
    if real:
        installed = len(present) == len(real)
        partial = len(present) > 0 and not installed
    else:
        files = [expand(b.get("input", "")) for b in blocks if b.get("input")]
        exist = [f for f in files if f and Path(f).exists()]
        installed = len(exist) == len(files) and len(files) > 0
        partial = len(exist) > 0 and not installed
    toggle = entry.get("toggle", "")
    enabled = True
    if toggle:
        enabled = t.get(toggle, True) is not False
    outputs = [expand(b.get("output", "")) for b in real]
    applied = bool(outputs) and all(p and Path(p).exists() for p in outputs)
    return {
        "installed": installed,
        "partial": partial,
        "active": installed and enabled,
        "enabled": enabled,
        "applied": applied,
        "manual": not tracked,
        "blocks": len(real),
    }


def cmd_list() -> dict:
    data = catalog()
    have = installed_block_ids()
    t = theming()
    out = []
    installed_count = 0
    for entry in data["entries"]:
        status = entry_status(entry, have, t)
        if status["installed"] or status["partial"]:
            installed_count += 1
        out.append({
            "id": entry["id"],
            "title": entry.get("title", entry["id"]),
            "category": entry.get("category", "Other"),
            "desc": entry.get("desc", ""),
            "note": entry.get("note", ""),
            "toggle": entry.get("toggle", ""),
            "source": data.get("source", ""),
            **status,
        })
    return {
        "ok": True,
        "source": data.get("source", ""),
        "installedCount": installed_count,
        "total": len(out),
        "entries": out,
    }


def find_entry(id: str):
    for entry in catalog()["entries"]:
        if entry["id"] == id:
            return entry
    return None


def cmd_install(id: str) -> dict:
    data = catalog()
    entry = find_entry(id)
    if entry is None:
        return {"ok": False, "error": f"unknown theme: {id}"}
    raw_base = data.get("rawBase", "")
    have = installed_block_ids()
    downloaded, added, skipped = [], [], []
    for block in entry.get("blocks", []):
        remote = block.get("remote", "")
        dest = Path(expand(block.get("input", "")))
        if remote and dest.name:
            if dest.exists():
                skipped.append(dest.name)
            else:
                download(remote, dest, raw_base)
                downloaded.append(dest.name)
        if block.get("id") and block.get("output"):
            if block["id"] in have:
                continue
            text = config_text()
            if text and not text.endswith("\n"):
                text += "\n"
            text += ("\n" if text else "") + block_text(block)
            atomic_write(MATUGEN_CONFIG, text)
            have.add(block["id"])
            added.append(block["id"])
    toggle = entry.get("toggle", "")
    if toggle:
        t = theming()
        if t.get(toggle, True) is False:
            t[toggle] = True
            atomic_write(THEMING_FILE, json.dumps(t, indent=4, sort_keys=True) + "\n")
    return {
        "ok": True,
        "action": "installed",
        "title": entry.get("title", id),
        "downloaded": downloaded,
        "skipped": skipped,
        "blocks": added,
        "manual": not any(b.get("id") and b.get("output") for b in entry.get("blocks", [])),
        "note": entry.get("note", ""),
    }


def delete_artifact(path: str, removed_files: list, removed_dirs: list) -> None:
    """Delete one generated file (or an empty dir) if it exists."""
    if not path:
        return
    p = Path(path)
    try:
        if p.is_symlink() or p.is_file():
            p.unlink()
            removed_files.append(str(p))
        elif p.is_dir() and not any(p.iterdir()):
            p.rmdir()
            removed_dirs.append(str(p))
    except OSError:
        pass


# Never prune into the top of the config/state trees, only theme-owned dirs.
PRUNE_STOP = {
    HOME, HOME / ".config", HOME / ".local", HOME / ".local/share",
    HOME / ".local/state", HOME / ".cache", HOME / ".var", HOME / ".var/app",
}


def tree_has_files(path: Path) -> bool:
    """True as soon as any regular file/symlink exists anywhere below path."""
    try:
        for child in path.iterdir():
            if child.is_dir() and not child.is_symlink():
                if tree_has_files(child):
                    return True
            else:
                return True
    except OSError:
        return True
    return False


def prune_empty_parents(path: Path, removed_dirs: list) -> None:
    """Remove up to three ancestors that hold no files at all (e.g.
    PrismLauncher's themes/Matugen with only empty resource folders after
    theme.json was deleted). Anything containing a user file stays."""
    parent = path.parent
    for _ in range(3):
        if parent in PRUNE_STOP or HOME not in parent.parents:
            break
        try:
            if not parent.is_dir() or tree_has_files(parent):
                break
            shutil.rmtree(parent)
            removed_dirs.append(str(parent))
        except OSError:
            break
        parent = parent.parent


def remove_artifacts(entry: dict) -> tuple:
    """Delete the app's generated theme file(s) + extra cleanup paths."""
    removed_files, removed_dirs = [], []
    blocks = entry.get("blocks", [])
    real = [b for b in blocks if b.get("id") and b.get("output")]
    for block in real:
        out = expand(block["output"])
        delete_artifact(out, removed_files, removed_dirs)
        prune_empty_parents(Path(out), removed_dirs)
    for extra in entry.get("cleanup", []):
        delete_artifact(expand(extra), removed_files, removed_dirs)
    if not real:
        # Manual entries (Zen, Telegram, …) only own the downloaded template
        # inside the matugen templates dir; removing drops that copy again.
        for block in blocks:
            inp = Path(expand(block.get("input", "")))
            if inp.exists() and TEMPLATES_DIR in inp.parents:
                delete_artifact(str(inp), removed_files, removed_dirs)
    return removed_files, removed_dirs


def run_remove_hook(entry: dict) -> bool:
    """Best-effort app-side revert/reload (notify daemons, reset btop theme,
    drop the empty wezterm.lua we touched, …)."""
    hook = expand(entry.get("remove_hook", ""))
    if not hook:
        return False
    try:
        subprocess.run(["bash", "-c", hook], capture_output=True, timeout=30)
        return True
    except Exception:
        return False


def cmd_remove(id: str) -> dict:
    entry = find_entry(id)
    if entry is None:
        return {"ok": False, "error": f"unknown theme: {id}"}
    ids = {b["id"] for b in entry.get("blocks", []) if b.get("id")}
    present = ids & installed_block_ids()
    text = config_text()
    new_text = remove_blocks(text, ids)
    changed = new_text != text
    if changed:
        atomic_write(MATUGEN_CONFIG, new_text)
    removed_files, removed_dirs = remove_artifacts(entry)
    ran_hook = run_remove_hook(entry) if (present or removed_files or removed_dirs) else False
    return {
        "ok": True,
        "action": "removed",
        "title": entry.get("title", id),
        "blocks": sorted(ids),
        "changed": changed,
        "removedFiles": removed_files,
        "removedDirs": removed_dirs,
        "removeHook": ran_hook,
    }


def main(argv) -> int:
    if len(argv) < 2 or argv[1] not in ("list", "install", "remove", "download"):
        print("usage: matugen-themes.py {list|install <id>|remove <id>}", file=sys.stderr)
        return 2
    cmd = argv[1]
    try:
        if cmd == "list":
            result = cmd_list()
        elif cmd == "install":
            if len(argv) < 3:
                result = {"ok": False, "error": "missing theme id"}
            else:
                result = cmd_install(argv[2])
        elif cmd == "remove":
            if len(argv) < 3:
                result = {"ok": False, "error": "missing theme id"}
            else:
                result = cmd_remove(argv[2])
        else:
            result = {"ok": False, "error": "unused"}
    except Exception as exc:  # network / IO failures reach the page as JSON
        result = {"ok": False, "error": str(exc)}
    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
