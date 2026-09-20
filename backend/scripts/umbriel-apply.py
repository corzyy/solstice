#!/usr/bin/env python3
"""Umbriel appearance bridge for the solstice settings app.

The Appearance > Umbriel page never edits the hand-written files under
~/.config/umbriel/configs/. It owns configs/shell.toml, which is pulled in by
the optional include at the bottom of ~/.config/umbriel/config.toml, so its
values override the hand-written configs without touching them.

Usage:
    umbriel-apply.py dump            # effective managed values as JSON
    umbriel-apply.py apply '<json>'  # rewrite shell.toml + live reload
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
UMBRIEL_DIR = os.path.join(HOME, ".config", "umbriel")
CONFIG_TOML = os.path.join(UMBRIEL_DIR, "config.toml")
SHELL_TOML = os.path.join(UMBRIEL_DIR, "configs", "shell.toml")

# shell key -> (toml path, default)
FIELDS = {
    "layout": (("layout", "mode"), "dwindle"),
    "gap": (("layout", "gap"), 10),
    "borderWidth": (("appearance", "border_width"), 3),
    "cornerRadius": (("appearance", "corner_radius"), 10),
    "blur": (("appearance", "blur", "enabled"), True),
    "blurOptimized": (("appearance", "blur", "optimized"), True),
    "shadows": (("appearance", "shadow", "enabled"), False),
    "animations": (("animation", "enabled"), True),
    "animOpen": (("animation", "windows_in", "style"), "slide"),
    "animClose": (("animation", "windows_out", "style"), "slide"),
    "animDurOpen": (("animation", "windows_in", "duration_ms"), 400),
    "animDurClose": (("animation", "windows_out", "duration_ms"), 800),
    "animDurMove": (("animation", "windows_move", "duration_ms"), 500),
    "animDurWorkspace": (("animation", "workspaces", "duration_ms"), 400),
}

LAYOUTS = ("dwindle", "scrolling", "master")
OPEN_STYLES = ("popin", "zoom", "slide", "fade", "none")
CLOSE_STYLES = ("fade", "slide")
# Layer-rule namespace of the solstice shell surfaces. The override rule written
# into shell.toml matches the same namespaces so its blur_optimized value
# takes precedence over the hand-written rule in rules.toml.
SHELL_NS = ("^(bar|menu|calendar|settings|updatecenter|vitals|systemtray|"
            "launcher|networkpanel|volumepanel|bluetoothpanel|"
            "controlcenterpanel|volumeosd|notifications)$")
INT_RANGES = {
    "gap": (0, 500),
    "borderWidth": (0, 100),
    "cornerRadius": (0, 100),
    "animDurOpen": (1, 10000),
    "animDurClose": (1, 10000),
    "animDurMove": (1, 10000),
    "animDurWorkspace": (1, 10000),
}


def _merge(dst: dict, src: dict) -> None:
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dst.get(key), dict):
            _merge(dst[key], value)
        else:
            dst[key] = value


def effective() -> dict:
    """Merge config.toml + its includes (required, then optional, then main)."""
    try:
        import tomllib
    except ImportError:
        return {}
    try:
        with open(CONFIG_TOML, "rb") as fh:
            main = tomllib.load(fh)
    except Exception:
        return {}
    data: dict = {}
    include = main.get("include", {}) or {}
    names = list(include.get("files", []) or [])
    names += list((include.get("optional", {}) or {}).get("files", []) or [])
    for name in names:
        if not isinstance(name, str):
            continue
        path = os.path.expanduser(name) if name.startswith("~") else name
        if not os.path.isabs(path):
            path = os.path.join(UMBRIEL_DIR, path)
        try:
            with open(path, "rb") as fh:
                _merge(data, tomllib.load(fh))
        except Exception:
            continue
    _merge(data, main)
    return data


def _get(data: dict, path: tuple, default):
    cur = data
    for part in path:
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def dump() -> None:
    data = effective()
    out = {}
    for key, (path, default) in FIELDS.items():
        value = _get(data, path, default)
        if isinstance(default, bool):
            value = bool(value)
        elif isinstance(default, int):
            try:
                value = int(round(float(value)))
            except Exception:
                value = default
        else:
            value = str(value)
        out[key] = value
    # Shell layer override: last matching rule with an explicit blur or
    # blur_optimized. blur is auto-managed by the shell (off while the shell
    # is opaque, see UmbrielService.shellBlurWanted).
    shell_opt = True
    shell_blur = True
    rules = data.get("layer_rule", [])
    if isinstance(rules, list):
        for rule in rules:
            if not isinstance(rule, dict):
                continue
            match = rule.get("match", {})
            if (isinstance(match, dict)
                    and match.get("namespace") == SHELL_NS):
                if "blur_optimized" in rule:
                    shell_opt = bool(rule["blur_optimized"])
                if "blur" in rule:
                    shell_blur = bool(rule["blur"])
    out["shellBlurOptimized"] = shell_opt
    out["shellBlur"] = shell_blur
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")


def _coerce(key: str, value, default):
    if isinstance(default, bool):
        return bool(value)
    if isinstance(default, int):
        try:
            ival = int(round(float(value)))
        except Exception:
            return default
        lo, hi = INT_RANGES.get(key, (None, None))
        if lo is not None:
            ival = max(lo, min(hi, ival))
        return ival
    text = str(value)
    if key == "layout":
        return text if text in LAYOUTS else default
    if key == "animOpen":
        return text if text in OPEN_STYLES else default
    if key == "animClose":
        return text if text in CLOSE_STYLES else default
    return text


def _toml_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return '"' + str(value).replace("\\", "").replace('"', "") + '"'


def apply(payload: str) -> int:
    try:
        raw = json.loads(payload)
    except Exception:
        return 2
    values = {}
    for key, (_path, default) in FIELDS.items():
        values[key] = _coerce(key, raw.get(key, default), default)
    shell_blur_optimized = bool(raw.get("shellBlurOptimized", True))
    # Auto-managed: Transparency < 5% means an opaque shell, so the layer
    # blur only costs GPU time (UmbrielService rewrites this when it crosses
    # the threshold). Window blur is not affected.
    shell_blur = bool(raw.get("shellBlur", True))

    text = "\n".join([
        "# solstice settings — generated by Appearance > Umbriel.",
        "# Do not edit manually; the settings app overwrites this file.",
        "",
        "[layout]",
        "mode = " + _toml_value(values["layout"]),
        "gap = " + _toml_value(values["gap"]),
        "",
        "[appearance]",
        "border_width = " + _toml_value(values["borderWidth"]),
        "corner_radius = " + _toml_value(values["cornerRadius"]),
        "",
        "[appearance.blur]",
        "enabled = " + _toml_value(values["blur"]),
        "optimized = " + _toml_value(values["blurOptimized"]),
        "",
        "[appearance.shadow]",
        "enabled = " + _toml_value(values["shadows"]),
        "",
        "[animation]",
        "enabled = " + _toml_value(values["animations"]),
        "",
        "[animation.windows_in]",
        "style = " + _toml_value(values["animOpen"]),
        "duration_ms = " + _toml_value(values["animDurOpen"]),
        "",
        "[animation.windows_out]",
        "style = " + _toml_value(values["animClose"]),
        "duration_ms = " + _toml_value(values["animDurClose"]),
        "",
        "[animation.windows_move]",
        "duration_ms = " + _toml_value(values["animDurMove"]),
        "",
        "[animation.workspaces]",
        "duration_ms = " + _toml_value(values["animDurWorkspace"]),
        "",
        "# Shell layer override: shared cached backdrop for the bar and panels.",
        "# Off = each surface blurs its own backdrop (may show an edge along the",
        "# fused bar/panel joint). blur=false is written automatically while the",
        "# shell is opaque (Transparency < 5%).",
        "[[layer_rule]]",
        "match.namespace = " + _toml_value(SHELL_NS),
        "blur = " + _toml_value(shell_blur),
        "blur_optimized = " + _toml_value(shell_blur_optimized),
        "",
    ])
    os.makedirs(os.path.dirname(SHELL_TOML), exist_ok=True)
    tmp = SHELL_TOML + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, SHELL_TOML)

    # The file watcher applies this on its own; the explicit reload makes the
    # slider release land immediately even if the watch missed the rename.
    try:
        subprocess.run(["umbriel", "msg", "config-reload"], timeout=2,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    mode = sys.argv[1]
    if mode == "dump":
        dump()
        sys.exit(0)
    if mode == "apply" and len(sys.argv) >= 3:
        sys.exit(apply(sys.argv[2]))
    print(__doc__)
    sys.exit(1)
