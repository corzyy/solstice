#!/usr/bin/env python3
"""umbriel-keybinds.py — list and edit Umbriel keybinds for the solstice settings app.

Usage:
    umbriel-keybinds.py list [--json]
    umbriel-keybinds.py set <action> <chord> [--file <keybinds-*.toml>] [--json]
    umbriel-keybinds.py unbind <action> [--file <keybinds-*.toml>] [--json]

`list` reads ~/.config/umbriel/config.toml plus every [include] /
[include.optional] file and collects each [keybinds] entry, keeping the last
bind per chord like Umbriel's deep merge. TSV rows:

    kind \t combo \t action \t source \t description

kind:        key | mouse | scroll
combo:       display chord (Mod mapped to the configured mod_key, e.g. SUPER)
action:      raw action string ("window-focus-left", "spawn:kitty", ...)
source:      basename of the file the bind came from
description: human text from `umbriel msg --help` (empty for spawn actions)

`set`/`unbind` edit one of the hand-written keybind files in place — by
default configs/keybinds-user.toml, or the `--file` target
(keybinds-user.toml / keybinds-system.toml). Only the quoted chord on the
matching line is replaced, so comments and table-form options survive. A bind
moved to a chord that is already taken disables the other line with a
`# solstice-off:` prefix (still readable, easy to restore). Umbriel is asked to
reload after every write. JSON mode prints

    {"ok": bool, "action": str, "chord": str, "message": str,
     "disabled": [chord...], "overrides": [source...],
     "shadowedBy": [source...], "stale": [str...]}

for the settings app.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

try:
    import tomllib
except ImportError:
    sys.exit("python3 tomllib unavailable (need Python 3.11+)")

HOME = os.path.expanduser("~")
UMBRIEL_DIR = os.path.join(HOME, ".config", "umbriel")
CONFIG_TOML = os.path.join(UMBRIEL_DIR, "config.toml")
KEYBINDS_TOML = os.path.join(UMBRIEL_DIR, "configs", "keybinds-user.toml")
EDITABLE_FILES = ("keybinds-user.toml", "keybinds-system.toml")

DISABLED_PREFIX = "# solstice-off: "
SECTION_RE = re.compile(r"^\s*\[")
ACTION_RE = re.compile(r'action\s*=\s*"((?:[^"\\]|\\.)*)"')


def load(path):
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except Exception:
        return {}


def include_paths(main_cfg):
    inc = main_cfg.get("include", {}) or {}
    names = list(inc.get("files", []) or [])
    names += list((inc.get("optional", {}) or {}).get("files", []) or [])
    out = []
    for name in names:
        if not isinstance(name, str):
            continue
        path = os.path.expanduser(name) if name.startswith("~") else name
        if not os.path.isabs(path):
            path = os.path.join(UMBRIEL_DIR, path)
        out.append(path)
    return out


def action_descriptions():
    """action token -> help text, parsed from `umbriel msg --help`."""
    try:
        out = subprocess.run(["umbriel", "msg", "--help"], capture_output=True,
                             text=True, timeout=5).stdout
    except Exception:
        return {}
    desc = {}
    for line in out.splitlines():
        m = re.match(r"^  (\S+)\s{2,}(.+)$", line)
        if not m:
            continue
        token, text = m.group(1), m.group(2).strip()
        desc.setdefault(token.split(":", 1)[0], text)
    return desc


def display_combo(chord, mod_key):
    parts = [p.strip() for p in chord.split("+") if p.strip()]
    out = []
    for part in parts:
        if part == "Mod":
            out.append(mod_key.upper())
        elif part.startswith("Wheel"):
            out.append("Scroll " + part[5:])
        elif part.startswith("Mouse"):
            out.append("Mouse " + part[5:])
        else:
            out.append(part)
    return " + ".join(out)


def kind_for(chord):
    if "Wheel" in chord:
        return "scroll"
    if "Mouse" in chord:
        return "mouse"
    return "key"


def collect():
    main_cfg = load(CONFIG_TOML)
    mod_key = str((main_cfg.get("general", {}) or {}).get("mod_key", "Super"))
    desc = action_descriptions()

    binds = {}
    order = []
    files = include_paths(main_cfg)
    files.append(CONFIG_TOML)
    for path in files:
        table = load(path).get("keybinds", {}) or {}
        if not isinstance(table, dict):
            continue
        src = os.path.basename(path)
        for chord, value in table.items():
            if isinstance(value, dict):
                action = value.get("action", "")
            else:
                action = value
            action = str(action or "").strip()
            if not action:
                continue
            if chord not in binds:
                order.append(chord)
            binds[chord] = (action, src)

    rows = []
    for chord in order:
        action, src = binds[chord]
        base = action.split(":", 1)[0]
        text = "" if base == "spawn" else desc.get(base, "")
        rows.append({
            "chord": chord,
            "display": display_combo(chord, mod_key),
            "action": action,
            "kind": kind_for(chord),
            "source": src,
            "description": text,
        })
    return rows


# ---- keybinds-user.toml line editor -------------------------------------

def _find_string_end(text, start):
    """Index of the closing quote for a TOML basic/literal string at `start`."""
    if start >= len(text) or text[start] not in "\"'":
        return -1
    quote = text[start]
    i = start + 1
    while i < len(text):
        c = text[i]
        if quote == '"' and c == "\\":
            i += 2
            continue
        if c == quote:
            return i
        i += 1
    return -1


def _unquote(token):
    token = token.strip()
    if len(token) >= 2 and token[0] == token[-1] and token[0] in "\"'":
        body = token[1:-1]
        if token[0] == '"':
            body = body.replace('\\"', '"').replace("\\\\", "\\")
        return body
    return token


def _quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _split_comment(line):
    """Split on the first # outside quotes: (code, comment)."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote is not None:
            if quote == '"' and c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#":
            return line[:i], line[i:]
        i += 1
    return line, ""


def _value_action(value):
    value = value.strip()
    if value.startswith('"'):
        end = _find_string_end(value, 0)
        return _unquote(value[:end + 1]).strip() if end > 0 else None
    if value.startswith("'"):
        end = value.find("'", 1)
        return value[1:end].strip() if end > 0 else None
    if value.startswith("{"):
        m = ACTION_RE.search(value)
        return m.group(1).replace('\\"', '"').strip() if m else None
    return None


def _parse_bind_line(line):
    stripped = line.lstrip()
    disabled = False
    if stripped.startswith(DISABLED_PREFIX):
        disabled = True
        stripped = stripped[len(DISABLED_PREFIX):]
    elif stripped.startswith("#"):
        return None
    code, comment = _split_comment(stripped)
    code = code.rstrip()
    if not code.startswith('"'):
        return None
    end = _find_string_end(code, 0)
    if end < 0:
        return None
    chord = _unquote(code[:end + 1])
    rest = code[end + 1:].lstrip()
    if not rest.startswith("="):
        return None
    value = rest[1:].strip()
    action = _value_action(value)
    if action is None:
        return None
    return {
        "chord": chord,
        "action": action,
        "value": value,
        "comment": comment,
        "disabled": disabled,
        "indent": line[:len(line) - len(line.lstrip())],
    }


def _render_bind(indent, chord, value, comment):
    text = indent + _quote(chord) + " = " + value
    if comment and comment.strip():
        text += "  " + comment.strip()
    return text


def _render_disabled(line):
    stripped = line.lstrip()
    if stripped.startswith(DISABLED_PREFIX):
        return line
    return line[:len(line) - len(stripped)] + DISABLED_PREFIX + stripped


def _keybinds_range(lines):
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "[keybinds]":
            start = i + 1
        elif start is not None and SECTION_RE.match(line):
            return start, i
    if start is None:
        return None, None
    return start, len(lines)


def target_path(name):
    """Resolve a --file basename to an editable keybind file path."""
    if not name:
        return KEYBINDS_TOML
    if os.path.basename(name) != name or name not in EDITABLE_FILES:
        return None
    return os.path.join(os.path.dirname(KEYBINDS_TOML), name)


def _file_rank(source):
    """Merge rank of a file basename: later files override earlier ones."""
    order = [os.path.basename(p) for p in include_paths(load(CONFIG_TOML))]
    order.append("config.toml")
    return order.index(source) if source in order else -1


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            original = fh.read()
    except FileNotFoundError:
        original = ""
    newline = "\r\n" if "\r\n" in original else "\n"
    lines = original.split(newline)
    if lines and lines[-1] == "":
        lines.pop()
    return lines, newline


def _write_lines(path, lines, newline):
    text = newline.join(lines)
    if text:
        text += newline
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def _reload():
    try:
        subprocess.run(["umbriel", "msg", "config-reload"], timeout=2,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def _validate_chord(chord):
    if not chord or any(c.isspace() for c in chord):
        return False
    return all(part for part in chord.split("+"))


def _empty_result(ok, action, chord, message):
    return {"ok": ok, "action": action, "chord": chord, "message": message,
            "disabled": [], "overrides": [], "shadowedBy": [], "stale": []}


def set_bind(action, chord, target=None):
    target = target or KEYBINDS_TOML
    target_base = os.path.basename(target)
    if not _validate_chord(chord):
        return _empty_result(False, action, chord,
                             "Invalid chord '{}'.".format(chord))

    before = collect()
    overrides, shadowed_by, stale = [], [], []
    for row in before:
        if row["source"] == target_base:
            continue
        if row["chord"] == chord and row["action"] != action:
            if _file_rank(row["source"]) > _file_rank(target_base):
                shadowed_by.append(row["source"])
            else:
                overrides.append(row["source"])
        elif row["action"] == action and row["chord"] != chord:
            stale.append("{} ({})".format(row["chord"], row["source"]))

    lines, newline = _read_lines(target)
    start, end = _keybinds_range(lines)
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append("[keybinds]")
        start = end = len(lines)

    exact = []
    for i in range(start, end):
        parsed = _parse_bind_line(lines[i])
        if parsed is not None and parsed["action"] == action:
            exact.append((i, parsed))

    disabled = []
    for i in range(start, end):
        parsed = _parse_bind_line(lines[i])
        if (parsed is not None and not parsed["disabled"]
                and parsed["chord"] == chord and parsed["action"] != action):
            lines[i] = _render_disabled(lines[i])
            disabled.append(chord)

    if exact:
        target_index, hit = exact[-1]
        for i, _parsed in exact[:-1]:
            lines[i] = _render_disabled(lines[i])
        lines[target_index] = _render_bind(
            hit["indent"], chord, hit["value"], hit["comment"])
    else:
        insert_at = end
        while insert_at > start and lines[insert_at - 1].strip() == "":
            insert_at -= 1
        lines.insert(insert_at, _quote(chord) + " = " + _quote(action))

    _write_lines(target, lines, newline)
    _reload()

    overrides = sorted(set(overrides))
    shadowed_by = sorted(set(shadowed_by))
    message = "Bound to {} in {}.".format(chord, target_base)
    if disabled:
        message += " Freed the previous {} bind.".format(", ".join(disabled))
    if overrides:
        message += " Shadows the same chord in {}.".format(", ".join(overrides))
    if shadowed_by:
        message += " Shadowed by the same chord in {}.".format(", ".join(shadowed_by))
    if stale:
        message += " Still bound to {} outside {}.".format(", ".join(stale), target_base)
    return {"ok": True, "action": action, "chord": chord, "message": message,
            "disabled": disabled, "overrides": overrides,
            "shadowedBy": shadowed_by, "stale": stale}


def unbind(action, target=None):
    target = target or KEYBINDS_TOML
    target_base = os.path.basename(target)
    lines, newline = _read_lines(target)
    start, end = _keybinds_range(lines)
    found = []
    if start is not None:
        for i in range(start, end):
            parsed = _parse_bind_line(lines[i])
            if parsed is not None and parsed["action"] == action:
                found.append(i)
    stale = ["{} ({})".format(row["chord"], row["source"]) for row in collect()
             if row["source"] != target_base and row["action"] == action]
    if not found:
        message = "Not bound in {}.".format(target_base)
        if stale:
            message += " Still bound to {} outside it.".format(", ".join(stale))
        return {"ok": False, "action": action, "chord": "",
                "message": message, "disabled": [], "overrides": [],
                "shadowedBy": [], "stale": stale}
    chord = ""
    for i in found:
        parsed = _parse_bind_line(lines[i])
        lines[i] = _render_disabled(lines[i])
        if not chord and parsed is not None:
            chord = parsed["chord"]
    _write_lines(target, lines, newline)
    _reload()
    message = "Unbound {} in {}.".format(chord, target_base)
    if stale:
        message += " Still bound to {} outside {}.".format(", ".join(stale), target_base)
    return {"ok": True, "action": action, "chord": chord,
            "message": message, "disabled": [], "overrides": [],
            "shadowedBy": [], "stale": stale}


# ---- output --------------------------------------------------------------

def print_tsv(rows):
    for row in rows:
        print("\t".join([row["kind"], row["display"], row["action"],
                         row["source"], row["description"]]))


def emit(payload, as_json):
    if as_json:
        json.dump(payload, sys.stdout)
        sys.stdout.write("\n")
    elif isinstance(payload, list):
        print_tsv(payload)
    else:
        print(payload.get("message", payload))


def usage():
    print(__doc__)


def _parse_args(argv):
    opts = {"json": False, "file": None}
    rest = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--json":
            opts["json"] = True
        elif arg == "--file" and i + 1 < len(argv):
            opts["file"] = argv[i + 1]
            i += 1
        else:
            rest.append(arg)
        i += 1
    return opts, rest


def main(argv):
    opts, args = _parse_args(argv)
    as_json = opts["json"]
    if not args or args[0] in ("-h", "--help", "help"):
        usage()
        return 0

    target = target_path(opts["file"])
    if target is None:
        emit(_empty_result(False, "", "", "Unknown keybind file '{}'.".format(opts["file"])),
             as_json)
        return 1

    cmd = args[0]
    if cmd == "list":
        emit(collect(), as_json)
        return 0
    if cmd == "set" and len(args) >= 3:
        result = set_bind(args[1], args[2], target)
        emit(result, as_json)
        return 0 if result["ok"] else 1
    if cmd == "unbind" and len(args) >= 2:
        result = unbind(args[1], target)
        emit(result, as_json)
        return 0 if result["ok"] else 1
    usage()
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
