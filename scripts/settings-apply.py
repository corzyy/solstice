#!/usr/bin/env python3
"""settings-apply.py — persistent writers for the jhqs Settings panel.

Usage: settings-apply.py <domain> <key=value>...
Domains: kitty | fish | brightness

All writers are atomic (tmp + replace) and idempotent. Called from QML
Process so the UI never blocks.
"""
import pathlib
import re
import subprocess
import sys

HOME = pathlib.Path.home()
KITTY = HOME / ".config/kitty/kitty.conf"
FISH_PROMPT = HOME / ".config/fish/functions/fish_prompt.fish"

def atomic_write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)

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
    for k, v in pairs.items():
        if k == "padding":
            sed_int_key(KITTY, "window_padding_width", max(0, min(40, int(float(v)))))
        elif k == "font_size":
            sed_float_key(KITTY, "font_size", max(6.0, min(32.0, float(v))))
        elif k == "opacity":
            sed_float_key(KITTY, "background_opacity", max(0.3, min(1.0, float(v))))
        elif k in ("family", "font_family"):
            fam = re.sub(r"[\r\n\t]", "", (v + "").strip())
            if not fam:
                continue
            t = KITTY.read_text() if KITTY.exists() else ""
            t2, n = re.subn(r"^(\s*font_family\s+).*$", r"\g<1>" + fam, t, flags=re.M)
            if n == 0:
                t2 = t.rstrip() + "\nfont_family " + fam + "\n"
            atomic_write(KITTY, t2)
    subprocess.run(["bash", "-c", "pkill -USR1 kitty 2>/dev/null || true"], check=False)

def fish(pairs: dict) -> None:
    style = re.sub(r"[^a-z0-9_-]", "", pairs.get("prompt", "minimal").lower()) or "minimal"
    src = HOME / f".config/fish/prompts/{style}.fish"
    if src.exists():
        FISH_PROMPT.parent.mkdir(parents=True, exist_ok=True)
        if FISH_PROMPT.is_symlink() or FISH_PROMPT.exists():
            FISH_PROMPT.unlink()
        FISH_PROMPT.symlink_to(src)
    else:
        subprocess.run(
            ["bash", "-c", f"fish -c 'set -U jhqs_prompt {style}' 2>/dev/null || true"],
            check=False,
        )

def brightness(pairs: dict) -> None:
    v = max(5, min(100, int(float(pairs.get("level", 100)))))
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
