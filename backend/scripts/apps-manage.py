#!/usr/bin/env python3
"""apps-manage.py — default applications and app removal for the solstice Apps page.

Usage:
    apps-manage.py defaults [--json]
    apps-manage.py set-default --kind <terminal|browser|fileManager> --id <desktop-id> [--name <name>] [--json]
    apps-manage.py info --id <desktop-id> [--json]
    apps-manage.py uninstall --id <desktop-id> [--json]

`defaults` resolves the terminal / browser / file manager selection. State lives
in ~/.config/quickshell/solstice/backend/config/default_apps.json (written by
`set-default`); kinds without a stored selection fall back to the historic
Umbriel spawn commands (kitty / helium / nautilus).

`set-default` reads the Exec line of the picked .desktop file, binds
`spawn:<command>` to the chord the previous command was bound to (falling back
to Mod+Return / Mod+B / Mod+E) through umbriel-keybinds.py and persists the
selection. Umbriel reloads its config, so the shortcut changes live.

`info` reports where the app comes from: `rpm`, `dpkg`, `pacman`, `flatpak`,
`webapp` (solstice web app), `user` (hand-written desktop file) or `unknown`,
plus the owning package and version when available.

`uninstall` removes the owning package. System packages go through the distro
package manager behind pkexec (the shell's polkit agent asks for the password),
flatpaks through `flatpak uninstall`, solstice web apps through
webapp-remove.sh, and user-local desktop entries by deleting the launcher file.

JSON mode prints:
    {"ok": bool, "defaults": {...}, "info": {...}, "message": str, "error": str}
for the settings app.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KEYBINDS_SCRIPT = os.path.join(SCRIPT_DIR, "umbriel-keybinds.py")
WEBAPP_REMOVE = os.path.join(SCRIPT_DIR, "webapp-remove.sh")
STATE_FILE = os.path.join(HOME, ".config", "quickshell", "solstice",
                          "backend", "config", "default_apps.json")

KINDS = ("terminal", "browser", "fileManager")
KIND_DEFAULTS = {
    "terminal": {"command": "kitty", "chord": "Mod+Return"},
    "browser": {"command": "helium", "chord": "Mod+B"},
    "fileManager": {"command": "nautilus", "chord": "Mod+E"},
}

FLATPAK_DIRS = (
    "/var/lib/flatpak/",
    os.path.join(HOME, ".local", "share", "flatpak") + os.sep,
)
USER_APPS_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"),
    "applications")

FIELD_CODES = set("fFuUickdDnNvm")
WEBAPP_RE = re.compile(r"^Exec=.*(launch-webapp|webapp-handler|webapp-launch|solstice-webapp|--app=)", re.MULTILINE)


# ---- desktop entry lookup ------------------------------------------------

def app_dirs():
    dirs = [USER_APPS_DIR]
    xdg_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    for d in xdg_dirs.split(":"):
        d = d.strip()
        if d:
            dirs.append(os.path.join(d, "applications"))
    dirs.append("/var/lib/flatpak/exports/share/applications")
    dirs.append(os.path.join(HOME, ".local/share/flatpak/exports/share/applications"))
    out = []
    for d in dirs:
        if d not in out and os.path.isdir(d):
            out.append(d)
    return out


def find_desktop_file(app_id):
    needle = str(app_id or "").strip()
    if needle.endswith(".desktop"):
        needle = needle[:-8]
    if not needle:
        return None
    for d in app_dirs():
        direct = os.path.join(d, needle + ".desktop")
        if os.path.exists(direct):
            return direct
    for d in app_dirs():
        for root, _dirs, files in os.walk(d):
            for name in files:
                if not name.endswith(".desktop"):
                    continue
                rel = os.path.relpath(os.path.join(root, name), d)
                rid = rel[:-8].replace(os.sep, "-")
                if rid == needle or name[:-8] == needle:
                    return os.path.join(root, name)
    return None


def exec_args(path):
    """Parsed Exec argv from [Desktop Entry] with field codes stripped."""
    section = None
    raw = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                    continue
                if section == "Desktop Entry" and line.startswith("Exec="):
                    raw = line[5:].strip()
                    break
    except OSError:
        return []
    if not raw:
        return []
    return [a for a in (_strip_field_codes(tok) for tok in _tokenize(raw)) if a]


def _tokenize(text):
    args = []
    cur = []
    quote = None
    i = 0
    while i < len(text):
        ch = text[i]
        if quote is not None:
            if ch == "\\" and quote == '"' and i + 1 < len(text):
                cur.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
                i += 1
                continue
            cur.append(ch)
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            i += 1
            continue
        if ch == "\\" and i + 1 < len(text):
            cur.append(text[i + 1])
            i += 2
            continue
        if ch.isspace():
            if cur:
                args.append("".join(cur))
                cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    if cur:
        args.append("".join(cur))
    return args


def _strip_field_codes(arg):
    out = []
    i = 0
    while i < len(arg):
        ch = arg[i]
        if ch == "%" and i + 1 < len(arg):
            nxt = arg[i + 1]
            if nxt == "%":
                out.append("%")
                i += 2
                continue
            if nxt in FIELD_CODES:
                i += 2
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def _shell_quote(arg):
    if arg == "" or re.search(r"""[\s"'$`\\|&;<>()*?\[\]{}!#~]""", arg):
        arg = (arg.replace("\\", "\\\\").replace('"', '\\"')
               .replace("$", "\\$").replace("`", "\\`"))
        return '"' + arg + '"'
    return arg


def to_spawn_command(args):
    return " ".join(_shell_quote(a) for a in args)


# ---- keybinds bridge -----------------------------------------------------

_KEYBINDS = None


def keybinds():
    global _KEYBINDS
    if _KEYBINDS is None:
        spec = importlib.util.spec_from_file_location("umbriel_keybinds", KEYBINDS_SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _KEYBINDS = mod
    return _KEYBINDS


def chord_for(action, rows):
    for row in rows:
        if row.get("action") == action and row.get("chord"):
            return row["chord"]
    return ""


# ---- state ---------------------------------------------------------------

def load_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=4, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, STATE_FILE)


def resolve_defaults():
    state = load_state()
    try:
        rows = keybinds().collect()
    except Exception:
        rows = []
    out = {}
    for kind in KINDS:
        fallback = KIND_DEFAULTS[kind]
        stored = state.get(kind)
        if not isinstance(stored, dict):
            stored = {}
        command = str(stored.get("command") or fallback["command"])
        action = str(stored.get("action") or ("spawn:" + command))
        chord = chord_for(action, rows)
        bound = chord != ""
        if not bound:
            chord = str(stored.get("chord") or fallback["chord"])
        out[kind] = {
            "kind": kind,
            "id": str(stored.get("id") or ""),
            "name": str(stored.get("name") or ""),
            "command": command,
            "action": action,
            "chord": chord,
            "bound": bound,
        }
    return out


def set_default(kind, app_id, name=None):
    if kind not in KINDS:
        return {"ok": False, "error": "Unknown app kind '{}'.".format(kind)}
    path = find_desktop_file(app_id)
    if path is None:
        return {"ok": False, "error": "No desktop entry found for '{}'.".format(app_id)}
    args = exec_args(path)
    if not args:
        return {"ok": False, "error": "The desktop entry has no runnable Exec line."}
    command = to_spawn_command(args)
    resolved = resolve_defaults()
    old = resolved[kind]
    chord = old["chord"] or KIND_DEFAULTS[kind]["chord"]
    new_action = "spawn:" + command
    message = ""
    if new_action != old["action"]:
        try:
            res = keybinds().set_bind(new_action, chord)
        except Exception as exc:
            return {"ok": False, "error": "Could not update the shortcut: {}".format(exc)}
        if not res.get("ok"):
            return {"ok": False, "error": res.get("message") or "Could not update the shortcut."}
        message = "Bound {} to {}.".format(command, chord)
        notes = []
        if res.get("disabled"):
            notes.append("freed " + ", ".join(res["disabled"]))
        if res.get("shadowedBy"):
            notes.append("shadowed by " + ", ".join(res["shadowedBy"]))
        if notes:
            message += " (" + "; ".join(notes) + ")"
    else:
        message = "{} is already the default.".format(command)
    display = str(name or os.path.splitext(os.path.basename(path))[0])
    state = load_state()
    state[kind] = {
        "id": str(app_id),
        "name": display,
        "command": command,
        "action": new_action,
        "chord": chord,
    }
    save_state(state)
    return {"ok": True, "defaults": resolve_defaults(), "message": message}


# ---- package provenance --------------------------------------------------

def _run(cmd):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return res.returncode, (res.stdout or "").strip(), (res.stderr or "").strip()
    except Exception:
        return 1, "", ""


def _is_webapp(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        return WEBAPP_RE.search(text) is not None
    except OSError:
        return False


def _rpm_info(path):
    code, out, _err = _run(["rpm", "-qf", "--queryformat",
                            "%{NAME}\n%{VERSION}-%{RELEASE}\n%{SUMMARY}", path])
    if code != 0 or not out:
        return None
    lines = out.splitlines()
    name = lines[0].strip() if lines else ""
    version = lines[1].strip() if len(lines) > 1 else ""
    summary = lines[2].strip() if len(lines) > 2 else ""
    if not name:
        return None
    return name, version, summary


def _dpkg_info(path):
    code, out, _err = _run(["dpkg", "-S", path])
    if code != 0 or not out:
        return None
    name = out.split(":", 1)[0].split(",")[0].strip()
    if not name:
        return None
    code, out, _err = _run(["dpkg-query", "-W", "-f=${Version}", name])
    return name, (out if code == 0 else ""), ""


def _pacman_info(path):
    code, out, _err = _run(["pacman", "-Qoq", path])
    name = out.splitlines()[0].strip() if code == 0 and out else ""
    if not name:
        code, out, _err = _run(["pacman", "-Qo", path])
        m = re.search(r"is owned by (\S+) (\S+)", out)
        if code != 0 or not m:
            return None
        return m.group(1), m.group(2), ""
    code, out, _err = _run(["pacman", "-Q", name])
    version = out.split(" ", 1)[1].strip() if code == 0 and " " in out else ""
    return name, version, ""


def _flatpak_version(app_id):
    for flag in ("--system", "--user", None):
        cmd = ["flatpak", "info"]
        if flag:
            cmd.append(flag)
        cmd.append(app_id)
        code, out, _err = _run(cmd)
        if code == 0 and out:
            m = re.search(r"^\s*Version:\s*(.+)$", out, re.MULTILINE)
            return (m.group(1).strip() if m else "")
    return ""


def app_info(app_id):
    path = find_desktop_file(app_id)
    if path is None:
        return {"ok": False, "error": "No desktop entry found for '{}'.".format(app_id)}
    real = os.path.realpath(path)
    base = os.path.splitext(os.path.basename(path))[0]
    kind = "unknown"
    package = ""
    version = ""
    for root in FLATPAK_DIRS:
        if real.startswith(root):
            kind = "flatpak"
            package = base
            version = _flatpak_version(base)
            break
    else:
        if real.startswith(USER_APPS_DIR + os.sep):
            kind = "webapp" if _is_webapp(path) else "user"
            package = base if kind == "webapp" else ""
        elif shutil.which("rpm"):
            info = _rpm_info(real)
            if info:
                kind, package, version = "rpm", info[0], info[1]
        if kind == "unknown" and shutil.which("dpkg"):
            info = _dpkg_info(real)
            if info:
                kind, package, version = "dpkg", info[0], info[1]
        if kind == "unknown" and shutil.which("pacman"):
            info = _pacman_info(real)
            if info:
                kind, package, version = "pacman", info[0], info[1]
    info = {
        "id": str(app_id),
        "path": real,
        "kind": kind,
        "package": package,
        "version": version,
    }
    return {"ok": True, "info": info}


def _system_remove(package, kind):
    if kind == "rpm":
        if shutil.which("dnf"):
            return ["pkexec", shutil.which("dnf"), "remove", "-y", package]
        if shutil.which("zypper"):
            return ["pkexec", shutil.which("zypper"), "--non-interactive", "remove", package]
    if kind == "dpkg" and shutil.which("apt-get"):
        return ["pkexec", shutil.which("apt-get"), "remove", "-y", package]
    if kind == "pacman" and shutil.which("pacman"):
        return ["pkexec", shutil.which("pacman"), "-Rns", "--noconfirm", package]
    return None


def uninstall(app_id):
    info_res = app_info(app_id)
    if not info_res.get("ok"):
        return {"ok": False, "error": info_res.get("error") or "Could not identify the app."}
    info = info_res["info"]
    kind = info["kind"]
    package = info["package"]
    if kind == "webapp":
        if not os.path.isfile(WEBAPP_REMOVE):
            return {"ok": False, "error": "webapp-remove.sh is missing."}
        code, out, err = _run(["bash", WEBAPP_REMOVE, package])
        if code != 0:
            return {"ok": False, "error": err or out or "Could not remove the web app."}
        return {"ok": True, "message": (out.strip().splitlines() or ["Web app removed."])[-1]}
    if kind == "user":
        target = info["path"]
        if not target.startswith(USER_APPS_DIR + os.sep):
            return {"ok": False, "error": "Refusing to delete {}".format(target)}
        try:
            os.remove(target)
        except OSError as exc:
            return {"ok": False, "error": str(exc)}
        _update_desktop_database()
        return {"ok": True,
                "message": "Removed the user launcher entry (the app itself was not uninstalled)."}
    if kind == "flatpak":
        cmd = ["flatpak", "uninstall", "-y", package]
    elif kind in ("rpm", "dpkg", "pacman"):
        cmd = _system_remove(package, kind)
        if cmd is None:
            return {"ok": False, "error": "No supported package manager found."}
    else:
        return {"ok": False,
                "error": "This app has no package owner; remove it manually or hide it instead."}
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    output = ((res.stdout or "") + "\n" + (res.stderr or "")).strip()
    if res.returncode != 0:
        last = [l for l in output.splitlines() if l.strip()]
        return {"ok": False,
                "error": last[-1] if last else "Package manager failed (exit {}).".format(res.returncode)}
    _update_desktop_database()
    last = [l for l in output.splitlines() if l.strip()]
    return {"ok": True, "message": last[-1] if last else "Uninstalled {}.".format(package)}


def _update_desktop_database():
    tool = shutil.which("update-desktop-database")
    if tool:
        try:
            subprocess.run([tool, USER_APPS_DIR], capture_output=True, timeout=10)
        except Exception:
            pass


# ---- cli -----------------------------------------------------------------

def usage():
    print(__doc__)


def emit(payload, as_json):
    if as_json:
        json.dump(payload, sys.stdout)
        sys.stdout.write("\n")
    else:
        if payload.get("ok"):
            print(payload.get("message") or json.dumps(payload, indent=2, sort_keys=True))
        else:
            print(payload.get("error") or "error")


def main(argv):
    opts = {"kind": None, "id": None, "name": None, "json": False}
    rest = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--json":
            opts["json"] = True
        elif arg in ("--kind", "--id", "--name") and i + 1 < len(argv):
            opts[arg[2:]] = argv[i + 1]
            i += 1
        else:
            rest.append(arg)
        i += 1

    if not rest or rest[0] in ("-h", "--help", "help"):
        usage()
        return 0
    cmd = rest[0]

    if cmd == "defaults":
        payload = {"ok": True, "defaults": resolve_defaults()}
    elif cmd == "set-default":
        if not opts["kind"] or not opts["id"]:
            payload = {"ok": False, "error": "set-default needs --kind and --id."}
        else:
            payload = set_default(opts["kind"], opts["id"], opts["name"])
    elif cmd == "info":
        if not opts["id"]:
            payload = {"ok": False, "error": "info needs --id."}
        else:
            payload = app_info(opts["id"])
    elif cmd == "uninstall":
        if not opts["id"]:
            payload = {"ok": False, "error": "uninstall needs --id."}
        else:
            payload = uninstall(opts["id"])
    else:
        usage()
        return 1

    emit(payload, opts["json"])
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
