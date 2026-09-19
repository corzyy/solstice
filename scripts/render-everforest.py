#!/usr/bin/env python3
"""Render all matugen templates with Everforest Soft palette (dark/light)"""
import json, os, re, sys, subprocess
from pathlib import Path

HOME = os.path.expanduser("~")
MODE = "dark"
SRC = None
if len(sys.argv) > 1:
    if Path(sys.argv[1]).exists() and sys.argv[1].endswith(".json"):
        SRC = Path(sys.argv[1])
        if len(sys.argv) > 2 and sys.argv[2] in ("dark","light"):
            MODE = sys.argv[2]
    elif sys.argv[1] in ("dark","light"):
        MODE = sys.argv[1]
        if len(sys.argv) > 2 and Path(sys.argv[2]).exists():
            SRC = Path(sys.argv[2])
if SRC is None:
    SRC = Path(f"{HOME}/.config/quickshell/solstice/themes/everforest-soft-{MODE}.json")
CONFIG = Path(f"{HOME}/.config/matugen/config.toml")

if not SRC.exists():
    print(f"missing {SRC}", file=sys.stderr); sys.exit(1)

data = json.loads(SRC.read_text())
def get_hex(name):
    return data.get(name, "#000000")

def render_template(inp: Path, out: Path):
    text = inp.read_text()
    def repl(m):
        expr = m.group(1).strip()
        base = re.search(r'colors\.([a-z_0-9]+)', expr)
        if not base:
            return m.group(0)
        name = base.group(1)
        hx = get_hex(name)
        if "hex_stripped" in expr:
            return hx.lstrip("#")
        return hx
    rendered = re.sub(r'\{\{\s*(.*?)\s*\}\}', repl, text)
    img_name = SRC.stem if SRC else f"everforest-soft-{MODE}"
    rendered = rendered.replace("{{image}}", img_name).replace("{{mode}}", MODE)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(rendered)
    print(f"rendered {inp} -> {out}")

import re as regex
cfg = CONFIG.read_text() if CONFIG.exists() else ""
pattern = regex.compile(r'\[templates\.([^\]]+)\]\s*input_path\s*=\s*"([^"]+)"\s*output_path\s*=\s*"([^"]+)"', re.MULTILINE)
for m in pattern.finditer(cfg):
    name, inp, outp = m.groups()
    inp_p = Path(inp.replace("~", HOME))
    out_p = Path(outp.replace("~", HOME))
    if "quickshell" in name:
        continue
    if not inp_p.exists():
        print(f"skip {name} missing input {inp_p}", file=sys.stderr)
        continue
    try:
        render_template(inp_p, out_p)
    except Exception as e:
        print(f"error {name}: {e}", file=sys.stderr)

print("Running post_hooks...")
subprocess.run(["bash","-c","killall -USR1 kitty 2>/dev/null || pkill -USR1 kitty 2>/dev/null || true"])
# Umbriel renders colors.toml from the same palette above (templates.umbriel).
# matugen's own post_hook only fires on wallpaper runs, so preset theme
# switches must reload the compositor here, otherwise Umbriel keeps stale
# window colors until a manual config reload.
subprocess.run(["bash","-c","umbriel msg config-reload >/dev/null 2>&1 || true"])
gtk_theme = "adw-gtk3-dark" if MODE=="dark" else "adw-gtk3"
subprocess.run(["bash","-c", f"gsettings set org.gnome.desktop.interface gtk-theme '' 2>/dev/null; gsettings set org.gnome.desktop.interface gtk-theme '{gtk_theme}' 2>/dev/null || true"])
hook = Path(f"{HOME}/.config/matugen/post-hook-scripts/gtk-themes-reload.sh")
if hook.exists():
    subprocess.run(["bash", str(hook)])
pap = Path(f"{HOME}/.cache/matugen/papirus-folders.sh")
if pap.exists():
    subprocess.run(["bash", str(pap)])
subprocess.run(["bash","-c","sed -i -E 's/^color_theme *= *\\\".*\\\"/color_theme = \\\"matugen\\\"/; s/^theme_background *= *.*/theme_background = False/' \"$HOME/.config/btop/btop.conf\" 2>/dev/null; pkill -USR2 btop 2>/dev/null || true"])
print("done")
