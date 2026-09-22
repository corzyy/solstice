#!/usr/bin/env python3
"""settings-apply.py — persistent writers for the solstice Settings panel.

Usage: settings-apply.py <domain> <key=value>...
Domains: kitty | fish | brightness

All writers are atomic (tmp + replace) and idempotent. Called from QML
Process so the UI never blocks.
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HOME = pathlib.Path.home()
KITTY = HOME / ".config/kitty/kitty.conf"
FISH_PROMPT = HOME / ".config/fish/functions/fish_prompt.fish"

def atomic_write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # STABILITY: unique temp file — a fixed `<file>.tmp` collides when two
    # invocations (UI + CLI) overlap.
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise

def _num(value, cast, default):
    """STABILITY: malformed key=value input must not crash the writer."""
    try:
        return cast(float(value))
    except (TypeError, ValueError):
        return default

def sed_int_key(path: pathlib.Path, key: str, value: int) -> None:
    t = path.read_text() if path.exists() else ""
    pat = r"^(\s*" + re.escape(key) + r"\s+).*$"
    t2, n = re.subn(pat, r"\g<1>" + str(value), t, flags=re.M)
    if n == 0:
        t2 = t.rstrip() + "\n" + key + " " + str(value) + "\n"
    atomic_write(path, t2)

def fmt_num(value: float) -> str:
    s = "%g" % float(value)
    return s

def sed_float_key(path: pathlib.Path, key: str, value: float) -> None:
    t = path.read_text() if path.exists() else ""
    pat = r"^(\s*" + re.escape(key) + r"\s+).*$"
    t2, n = re.subn(pat, r"\g<1>" + fmt_num(value), t, flags=re.M)
    if n == 0:
        t2 = t.rstrip() + "\n" + key + " " + fmt_num(value) + "\n"
    atomic_write(path, t2)

def kitty(pairs: dict) -> None:
    changed = False
    for k, v in pairs.items():
        if k == "padding":
            sed_int_key(KITTY, "window_padding_width", max(0, min(40, _num(v, int, 10))))
            changed = True
        elif k == "font_size":
            sed_float_key(KITTY, "font_size", max(6.0, min(32.0, _num(v, float, 12.0))))
            changed = True
        elif k == "opacity":
            sed_float_key(KITTY, "background_opacity", max(0.3, min(1.0, _num(v, float, 1.0))))
            changed = True
        elif k in ("family", "font_family"):
            fam = re.sub(r"[\r\n\t]", "", (v + "").strip())
            if not fam:
                continue
            t = KITTY.read_text() if KITTY.exists() else ""
            # STABILITY: a lambda replacement keeps regex metacharacters and
            # backslashes in the family name literal (a `\1` in the name used
            # to raise "invalid group reference").
            t2, n = re.subn(r"^(\s*font_family\s+).*$",
                            lambda m: m.group(1) + fam, t, flags=re.M)
            if n == 0:
                t2 = t.rstrip() + "\nfont_family " + fam + "\n"
            atomic_write(KITTY, t2)
            changed = True
    if changed:
        # PERF: only reload kitty when its config actually changed, and skip
        # the extra bash fork.
        subprocess.run(["pkill", "-USR1", "kitty"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

def fish(pairs: dict) -> None:
    style = re.sub(r"[^a-z0-9_-]", "", pairs.get("prompt", "minimal").lower()) or "minimal"
    src = HOME / f".config/fish/prompts/{style}.fish"
    if src.exists():
        FISH_PROMPT.parent.mkdir(parents=True, exist_ok=True)
        # STABILITY: symlink into a temp name, then rename — the old
        # unlink+symlink lost fish_prompt.fish if the script died in between.
        tmp = FISH_PROMPT.with_name(FISH_PROMPT.name + ".tmp")
        try:
            tmp.unlink()
        except OSError:
            pass
        tmp.symlink_to(src)
        os.replace(tmp, FISH_PROMPT)
    else:
        subprocess.run(
            ["bash", "-c", f"fish -c 'set -U solstice_prompt {style}' 2>/dev/null || true"],
            check=False,
        )

def brightness(pairs: dict) -> None:
    v = max(5, min(100, _num(pairs.get("level", 100), int, 100)))
    subprocess.run(
        ["bash", "-c", f"brightnessctl set {v}% >/dev/null 2>&1 || brightnessctl -q set {v}% >/dev/null 2>&1 || true"],
        check=False,
    )

DOMAINS = {"kitty": kitty, "fish": fish, "brightness": brightness}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in DOMAINS:
        print(f"usage: {sys.argv[0]} {{{'|'.join(DOMAINS)}}} key=value...", file=sys.stderr)
        sys.exit(1)
    domain = sys.argv[1]
    pairs = dict(a.split("=", 1) for a in sys.argv[2:] if "=" in a)
    DOMAINS[domain](pairs)
