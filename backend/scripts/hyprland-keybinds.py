#!/usr/bin/env python3
"""hyprland-keybinds.py — list and edit Hyprland binds for the solstice settings app.

Usage:
    hyprland-keybinds.py list [--json]
    hyprland-keybinds.py set <action> <chord> [--file <binds-*.lua>] [--json]
    hyprland-keybinds.py unbind <action> [--file <binds-*.lua>] [--json]

`list` reads ~/.config/hypr/configs/binds/system.lua plus
configs/binds/user.lua and collects each `hl.bind("chord", expr)` entry.

Actions are shell-level ids. `spawn:<cmd>` maps to
hl.dsp.exec_cmd("<cmd>"); the curated dispatcher ids below map to their lua
expressions; anything starting with `hl.` is used verbatim. Hyprland is asked
to reload after every write. JSON mode prints rows / result objects for the
settings app.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

HOME = os.path.expanduser("~")
BINDS_DIR = os.path.join(HOME, ".config", "hypr", "configs", "binds")
SYSTEM_LUA = os.path.join(BINDS_DIR, "system.lua")
USER_LUA = os.path.join(BINDS_DIR, "user.lua")

# action id -> lua expression (must stay in sync with KeybindsPage.qml's
# compositorCatalog).
ACTIONS = {
    "close": 'hl.dsp.window.close()',
    "toggle-float": 'hl.dsp.window.float({ action = "toggle" })',
    "toggle-fullscreen": 'hl.dsp.window.fullscreen({ action = "toggle" })',
    "toggle-maximize": 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })',
    "focus-left": 'hl.dsp.focus({ direction = "left" })',
    "focus-right": 'hl.dsp.focus({ direction = "right" })',
    "focus-up": 'hl.dsp.focus({ direction = "up" })',
    "focus-down": 'hl.dsp.focus({ direction = "down" })',
    "move-left": 'hl.dsp.window.move({ direction = "left" })',
    "move-right": 'hl.dsp.window.move({ direction = "right" })',
    "move-up": 'hl.dsp.window.move({ direction = "up" })',
    "move-down": 'hl.dsp.window.move({ direction = "down" })',
    "layout-toggle": 'hl.dsp.exec_cmd("solstice layout toggle")',
    "ws-next": 'hl.dsp.focus({ workspace = "m+1" })',
    "ws-prev": 'hl.dsp.focus({ workspace = "m-1" })',
    "ws-move-next": 'hl.dsp.window.move({ workspace = "m+1" })',
    "ws-move-prev": 'hl.dsp.window.move({ workspace = "m-1" })',
    "scratchpad": 'hl.dsp.workspace.toggle_special()',
    "out-left": 'hl.dsp.focus({ monitor = "l" })',
    "out-right": 'hl.dsp.focus({ monitor = "r" })',
    "out-move-left": 'hl.dsp.window.move({ monitor = "l" })',
    "out-move-right": 'hl.dsp.window.move({ monitor = "r" })',
    "quit": 'hl.dsp.exit()',
}
for _i in range(1, 10):
    ACTIONS["ws-%d" % _i] = "hl.dsp.focus({ workspace = %d })" % _i
    ACTIONS["win-move-%d" % _i] = "hl.dsp.window.move({ workspace = %d })" % _i

DESCRIPTIONS = {
    "close": "Close the focused window",
    "toggle-float": "Float or tile the focused window",
    "toggle-fullscreen": "Fullscreen the focused window",
    "toggle-maximize": "Maximize, keeping gaps and borders",
    "focus-left": "Focus the window to the left",
    "focus-right": "Focus the window to the right",
    "focus-up": "Focus the window above",
    "focus-down": "Focus the window below",
    "move-left": "Move the focused window left",
    "move-right": "Move the focused window right",
    "move-up": "Move the focused window up",
    "move-down": "Move the focused window down",
    "layout-toggle": "Switch the tiling layout (master / dwindle / scrolling)",
    "ws-next": "Switch to the next workspace",
    "ws-prev": "Switch to the previous workspace",
    "ws-move-next": "Take the focused window along",
    "ws-move-prev": "Take the focused window along",
    "scratchpad": "Toggle the scratchpad workspace",
    "out-left": "Focus the monitor to the left",
    "out-right": "Focus the monitor to the right",
    "out-move-left": "Send the focused window to the left monitor",
    "out-move-right": "Send the focused window to the right monitor",
    "quit": "Exit Hyprland",
}
for _i in range(1, 10):
    DESCRIPTIONS["ws-%d" % _i] = "Switch to workspace %d" % _i
    DESCRIPTIONS["win-move-%d" % _i] = "Send the focused window to workspace %d" % _i

_EXPR_TO_ACTION = {re.sub(r"\s+", " ", v): k for k, v in ACTIONS.items()}


def _lua_quote(text):
    return '"' + str(text).replace("\\", "\\\\").replace('"', '\\"') + '"'


def action_string(node):
    """Normalized action id (compat helper; nodes here are already strings)."""
    if isinstance(node, str):
        return node.strip()
    return str(node).strip()


def serialize_action(action):
    """Lua expression for a normalized action (used when inserting a bind)."""
    action = (action or "").strip()
    if action.startswith("spawn:"):
        try:
            args = shlex.split(action[6:])
        except ValueError:
            args = [action[6:]]
        cmd = " ".join(args).strip()
        if not cmd:
            return ""
        return "hl.dsp.exec_cmd(%s)" % _lua_quote(cmd)
    if action in ACTIONS:
        return ACTIONS[action]
    if action.startswith("hl."):
        return action
    return ""


def _norm_expr(expr):
    return re.sub(r"\s+", " ", (expr or "").strip())


def _exec_cmd_of(expr):
    m = re.match(r'^hl\.dsp\.exec_cmd\(\s*"((?:[^"\\]|\\.)*)"\s*\)$', _norm_expr(expr))
    if not m:
        return None
    try:
        return json.loads('"%s"' % m.group(1))
    except ValueError:
        return m.group(1)


def expr_to_action(expr):
    """Normalized action id for a lua bind expression."""
    norm = _norm_expr(expr)
    if norm in _EXPR_TO_ACTION:
        return _EXPR_TO_ACTION[norm]
    cmd = _exec_cmd_of(norm)
    if cmd is not None:
        if cmd.startswith("hyprctl dispatch "):
            inner = cmd[len("hyprctl dispatch "):].strip()
            for act, lex in ACTIONS.items():
                inner_cmd = _exec_cmd_of(_norm_expr(lex))
                if inner_cmd == cmd:
                    return act
            return "dispatch:" + inner
        if cmd == "hyprctl reload":
            return "spawn:hyprctl reload"
        if cmd == "solstice layout toggle":
            return "layout-toggle"
        return "spawn:" + cmd
    return norm


def display_combo(chord):
    parts = [p.strip() for p in chord.split("+") if p.strip()]
    out = []
    for part in parts:
        low = part.lower()
        if low == "mod":
            out.append("SUPER")
        elif low == "super":
            out.append("SUPER")
        else:
            out.append(part)
    return " + ".join(out)


def normalize_chord(chord):
    """Canonical `A + B` spacing, Mod accepted as an alias for SUPER."""
    parts = [p.strip() for p in str(chord or "").split("+")]
    norm = []
    for part in parts:
        if not part:
            return ""
        if part.lower() == "mod":
            norm.append("SUPER")
        else:
            norm.append(part)
    if not norm:
        return ""
    return " + ".join(norm)


def _validate_chord(chord):
    norm = normalize_chord(chord)
    if not norm:
        return ""
    if '"' in norm or "\n" in norm or "\\" in norm:
        return ""
    return norm


def kind_for(chord):
    low = chord.lower()
    if "mouse" in low:
        return "mouse"
    return "key"


def _file_variables(lines):
    """`local NAME = "value"` string aliases (e.g. `local M = "SUPER"`)."""
    variables = {}
    for raw in lines:
        m = re.match(r'^\s*local\s+([A-Za-z_]\w*)\s*=\s*"((?:[^"\\]|\\.)*)"\s*$',
                     raw.strip())
        if m:
            try:
                variables[m.group(1)] = json.loads('"%s"' % m.group(2))
            except ValueError:
                pass
    return variables


def _unroll_loops(lines):
    """Expand simple `for i = A, B do ... end` blocks (workspace number binds)."""
    out = []
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)for\s+([A-Za-z_]\w*)\s*=\s*(-?\d+)\s*,\s*(-?\d+)\s*do\s*$",
                     lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        indent, var, start, end = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
        depth = 1
        body = []
        j = i + 1
        while j < len(lines) and depth > 0:
            s = lines[j].strip()
            if re.match(r"^(for\b|while\b|if\b.*\bthen\s*$)", s):
                depth += 1
            if s == "end" or s.startswith("end ") or s.startswith("end--"):
                depth -= 1
                if depth == 0:
                    break
            body.append(lines[j])
            j += 1
        if depth != 0 or end - start > 32 or any(
                re.match(r"^\s*(for\b|while\b|if\b|function\b)", b.strip()) for b in body):
            out.append(lines[i])
            i += 1
            continue
        for n in range(start, end + 1 if end >= start else start - 1,
                       1 if end >= start else -1):
            for b in body:
                out.append(re.sub(r"\b%s\b" % re.escape(var), str(n), b))
        i = j + 1
    return out


def _resolve_chord(raw, variables):
    """Evaluate a chord expression of string literals / known aliases."""
    parts = re.split(r"\.\.", raw)
    out = []
    for part in parts:
        part = part.strip()
        if not part:
            return ""
        if part in variables:
            out.append(variables[part])
            continue
        if re.match(r"^-?\d+$", part):
            out.append(part)
            continue
        m = re.match(r'^"((?:[^"\\]|\\.)*)"$', part)
        if m:
            try:
                out.append(json.loads('"%s"' % m.group(1)))
            except ValueError:
                return ""
            continue
        return ""
    return "".join(out).strip()


def _strip_opts_suffix(text):
    """Split trailing `, { ... }` bind options off a hl.bind argument string."""
    m = re.match(r"^(.*),\s*\{[^{}]*\}\s*$", text, re.DOTALL)
    if m:
        return m.group(1).rstrip(), True
    return text, False


def parse_binds(lines, variables=None):
    """[{line, chord, expr, disabled}] for every hl.bind in the given lines."""
    variables = variables or {}
    binds = []
    for idx, raw in enumerate(lines):
        line = raw.strip()
        disabled = False
        if line.startswith("--"):
            disabled = True
            line = line[2:].strip()
        if not line.startswith("hl.bind(") or not line.endswith(")"):
            continue
        inner = line[len("hl.bind("):-1].strip()
        inner, _opts = _strip_opts_suffix(inner)
        m = re.match(r"^(.*?)\s*,\s*(.*)$", inner, re.DOTALL)
        if not m:
            continue
        chord = _resolve_chord(m.group(1), variables)
        expr = m.group(2).strip()
        if not chord or not expr:
            continue
        binds.append({"line": idx, "chord": chord, "expr": expr,
                      "disabled": disabled})
    return binds


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return [], "\n"
    newline = "\r\n" if "\r\n" in text else "\n"
    return text.splitlines(), newline


def _write_lines(path, lines, newline):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(newline.join(lines))
        if lines:
            fh.write(newline)


def _bind_files():
    files = []
    for path in (SYSTEM_LUA, USER_LUA):
        if os.path.isfile(path):
            files.append(path)
    if not files:
        files = [SYSTEM_LUA, USER_LUA]
    return files


def collect():
    rows = []
    for path in _bind_files():
        lines, _nl = _read_lines(path)
        variables = _file_variables(lines)
        src = os.path.basename(path)
        for bind in parse_binds(_unroll_loops(lines), variables):
            if bind["disabled"]:
                continue
            action = expr_to_action(bind["expr"])
            if not action:
                continue
            base = action.split(":", 1)[0]
            rows.append({
                "chord": bind["chord"],
                "display": display_combo(bind["chord"]),
                "action": action,
                "kind": kind_for(bind["chord"]),
                "source": src,
                "description": DESCRIPTIONS.get(action, ""),
            })
    # Later files (user.lua) win per chord, like the config require order.
    merged = {}
    order = []
    for row in rows:
        if row["chord"] not in merged:
            order.append(row["chord"])
        merged[row["chord"]] = row
    return [merged[c] for c in order]


def _reload():
    try:
        subprocess.run(["hyprctl", "reload"], timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def _empty_result(ok, action, chord, message):
    return {"ok": ok, "action": action, "chord": chord, "message": message,
            "disabled": [], "overrides": [], "shadowedBy": [], "stale": []}


def set_bind(action, chord, target=None):
    target = target or USER_LUA
    target_base = os.path.basename(target)
    norm_chord = _validate_chord(chord)
    if not norm_chord:
        return _empty_result(False, action, chord,
                             "Invalid chord '{}'.".format(chord))
    expr = serialize_action(action)
    if not expr:
        return _empty_result(False, action, norm_chord,
                             "Cannot serialize the action '{}'.".format(action))

    before = collect()
    overrides, shadowed_by, stale = [], [], []
    for row in before:
        if row["source"] == target_base:
            continue
        if row["chord"] == norm_chord and row["action"] != action:
            # user.lua is required after system.lua, so it always wins.
            if target_base == os.path.basename(USER_LUA):
                overrides.append(row["source"])
            else:
                shadowed_by.append(row["source"])
        elif row["action"] == action and row["chord"] != norm_chord:
            stale.append("{} ({})".format(row["chord"], row["source"]))

    lines, newline = _read_lines(target)
    original = list(lines)
    variables = _file_variables(lines)
    binds = parse_binds(lines, variables)

    disabled = []
    for bind in binds:
        if (not bind["disabled"] and bind["chord"] == norm_chord
                and _norm_expr(bind["expr"]) != _norm_expr(expr)):
            lines[bind["line"]] = "-- " + lines[bind["line"]].lstrip()
            disabled.append(norm_chord)

    # Re-read line numbers after commenting (indices are unchanged).
    binds = parse_binds(lines, variables)
    exact = [b for b in binds
             if not b["disabled"] and expr_to_action(b["expr"]) == action]
    if exact:
        for bind in exact[:-1]:
            lines[bind["line"]] = "-- " + lines[bind["line"]].lstrip()
        hit = exact[-1]
        lines[hit["line"]] = 'hl.bind("%s", %s)' % (norm_chord, expr)
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append('hl.bind("%s", %s)' % (norm_chord, expr))

    if lines != original:
        _write_lines(target, lines, newline)
        _reload()

    overrides = sorted(set(overrides))
    shadowed_by = sorted(set(shadowed_by))
    message = "Bound to {} in {}.".format(norm_chord, target_base)
    if disabled:
        message += " Freed the previous {} bind.".format(", ".join(disabled))
    if overrides:
        message += " Shadows the same chord in {}.".format(", ".join(overrides))
    if shadowed_by:
        message += " Shadowed by the same chord in {}.".format(", ".join(shadowed_by))
    if stale:
        message += " Still bound to {} outside {}.".format(", ".join(stale), target_base)
    return {"ok": True, "action": action, "chord": norm_chord, "message": message,
            "disabled": disabled, "overrides": overrides,
            "shadowedBy": shadowed_by, "stale": stale}


def unbind(action, target=None):
    target = target or USER_LUA
    target_base = os.path.basename(target)
    lines, newline = _read_lines(target)
    original = list(lines)
    variables = _file_variables(lines)
    binds = parse_binds(lines, variables)
    found = [b for b in binds
             if not b["disabled"] and expr_to_action(b["expr"]) == action]
    stale = ["{} ({})".format(row["chord"], row["source"]) for row in collect()
             if row["source"] != target_base and row["action"] == action]
    if not found:
        message = "Not bound in {}.".format(target_base)
        if stale:
            message += " Still bound to {} outside it.".format(", ".join(stale))
        return {"ok": False, "action": action, "chord": "",
                "message": message, "disabled": [], "overrides": [],
                "shadowedBy": [], "stale": stale}
    chord = found[-1]["chord"]
    for bind in found:
        lines[bind["line"]] = "-- " + lines[bind["line"]].lstrip()
    if lines != original:
        _write_lines(target, lines, newline)
        _reload()
    message = "Unbound {} in {}.".format(chord, target_base)
    if stale:
        message += " Still bound to {} outside {}.".format(", ".join(stale), target_base)
    return {"ok": True, "action": action, "chord": chord,
            "message": message, "disabled": [], "overrides": [],
            "shadowedBy": [], "stale": stale}


def target_path(name):
    if not name:
        return USER_LUA
    base = os.path.basename(name)
    if base in ("system.lua", "binds-system.lua", "keybinds-system.kdl"):
        return SYSTEM_LUA
    if base in ("user.lua", "binds-user.lua", "keybinds-user.kdl"):
        return USER_LUA
    Rejected = ("..", "/", "\\")
    if any(tok in name for tok in Rejected) or not name.endswith(".lua"):
        return None
    candidate = name if os.path.isabs(name) else os.path.join(BINDS_DIR, base)
    if os.path.realpath(candidate).startswith(os.path.realpath(BINDS_DIR) + os.sep):
        return candidate
    return None


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
