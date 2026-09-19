#!/usr/bin/env python3
"""theming-apply.py — persistent writers for Application Theming (jhqs).

Ported from DankMaterialShell's ThemeColorsTab functionality
(Applications / Cursor / Icon / Matugen Templates / System App Theming),
adapted to jhqs: matugen runs directly, qt via qt*ct.

Usage: theming-apply.py <domain> <key=value>...
Domains: icon | cursor | gtk | qt | template | portal | terminals
"""
import json
import os
import pathlib
import re
import subprocess
import sys

HOME = pathlib.Path.home()
JHQS_CFG = HOME / ".config/quickshell/jhqs/config"
JHQS_SCRIPTS = HOME / ".config/quickshell/jhqs/scripts"
THEMING_JSON = JHQS_CFG / "theming_settings.json"
MATUGEN_SETTINGS = HOME / ".config/quickshell/jhqs/themes/matugen_settings.json"
MATUGEN_CONFIG = HOME / ".config/matugen/config.toml"
GTK3_INI = HOME / ".config/gtk-3.0/settings.ini"
GTK4_INI = HOME / ".config/gtk-4.0/settings.ini"
XRES = HOME / ".Xresources"


def atomic_write(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def read_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def sh(cmd: str) -> None:
    subprocess.run(["bash", "-c", cmd + " >/dev/null 2>&1 || true"], check=False)


def sh_out(cmd: str) -> str:
    try:
        r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=20)
        return (r.stdout or "").strip()
    except Exception:
        return ""


def matugen_mode() -> str:
    m = read_json(MATUGEN_SETTINGS).get("mode", "dark")
    return "light" if m == "light" else "dark"


def theming() -> dict:
    return read_json(THEMING_JSON)


# ---------------------------------------------------------------- icon ---
def _set_ini_key(path: pathlib.Path, key: str, value: str) -> None:
    try:
        lines = path.read_text().splitlines() if path.exists() else []
    except OSError:
        lines = []
    out, seen = [], False
    for line in lines:
        if line.startswith(key + "="):
            out.append(key + "=" + value)
            seen = True
        else:
            out.append(line)
    if "[Settings]" not in out and not any(l.strip() == "[Settings]" for l in out):
        out.insert(0, "[Settings]")
    if not seen:
        out.append(key + "=" + value)
    atomic_write(path, "\n".join(out) + "\n")


def _resolve_icon(pairs: dict) -> str:
    t = theming()
    if "theme" in pairs:
        t["iconTheme"] = pairs["theme"]
    if "theme_light" in pairs:
        t["iconThemeLight"] = pairs["theme_light"]
    if "per_mode" in pairs:
        t["iconThemePerMode"] = pairs["per_mode"].lower() == "true"
    atomic_write(THEMING_JSON, json.dumps(t, indent=4, sort_keys=True) + "\n")
    if t.get("iconThemePerMode"):
        return t.get("iconThemeLight" if matugen_mode() == "light" else "iconTheme", "System Default") or "System Default"
    return t.get("iconTheme", "System Default") or "System Default"


def icon(pairs: dict) -> None:
    theme = _resolve_icon(pairs)
    if theme == "System Default" or not theme:
        return
    _set_ini_key(GTK3_INI, "gtk-icon-theme-name", theme)
    _set_ini_key(GTK4_INI, "gtk-icon-theme-name", theme)
    sh(f"gsettings set org.gnome.desktop.interface icon-theme '{theme}'")
    # qt6ct icon theme (best effort, mirrors DMS updateQtIconTheme)
    for conf in (HOME / ".config/qt5ct/qt5ct.conf", HOME / ".config/qt6ct/qt6ct.conf"):
        if not conf.exists():
            continue
        try:
            txt = conf.read_text()
        except OSError:
            continue
        if re.search(r"^icon_theme=", txt, re.M):
            txt = re.sub(r"^icon_theme=.*$", f"icon_theme={theme}", txt, flags=re.M)
        elif "[Appearance]" in txt:
            txt = txt.replace("[Appearance]", "[Appearance]\nicon_theme=" + theme, 1)
        else:
            txt = "[Appearance]\nicon_theme=" + theme + "\n" + txt
        atomic_write(conf, txt)
    sh(f"notify-send -u low 'Theming' 'Icon theme: {theme}' 2>/dev/null")


# --------------------------------------------------------------- cursor ---


def cursor(pairs: dict) -> None:
    t = theming()
    theme = pairs.get("theme", t.get("cursorTheme", "System Default")).strip() or "System Default"
    try:
        size = max(12, min(128, int(float(pairs.get("size", t.get("cursorSize", 24))))))
    except ValueError:
        size = 24
    t["cursorTheme"] = theme
    t["cursorSize"] = size
    atomic_write(THEMING_JSON, json.dumps(t, indent=4, sort_keys=True) + "\n")
    if theme == "System Default" or not theme:
        return
    _set_ini_key(GTK3_INI, "gtk-cursor-theme-name", theme)
    _set_ini_key(GTK4_INI, "gtk-cursor-theme-name", theme)
    _set_ini_key(GTK3_INI, "gtk-cursor-theme-size", str(size))
    _set_ini_key(GTK4_INI, "gtk-cursor-theme-size", str(size))
    sh(f"gsettings set org.gnome.desktop.interface cursor-theme '{theme}'")
    sh(f"gsettings set org.gnome.desktop.interface cursor-size {size}")
    # XWayland fallback (mirrors DMS updateXResources)
    try:
        cur = XRES.read_text() if XRES.exists() else ""
        cur = re.sub(r"(?m)^\s*Xcursor\.theme:.*$", "", cur)
        cur = re.sub(r"(?m)^\s*Xcursor\.size:.*$", "", cur).rstrip() + "\n"
        cur += f"Xcursor.theme: {theme}\nXcursor.size: {size}\n"
        atomic_write(XRES, cur)
    except OSError:
        pass
    sh("xrdb -merge ~/.Xresources")
    sh(f"notify-send -u low 'Theming' 'Cursor: {theme} {size}px' 2>/dev/null")


# ------------------------------------------------------------------ gtk ---
def gtk(pairs: dict) -> None:
    mode = matugen_mode()
    script = JHQS_SCRIPTS / "apply-gtk.sh"
    subprocess.run(["bash", str(script), mode], check=False)
    if theming().get("syncModeWithPortal", True):
        scheme = "prefer-dark" if mode == "dark" else "prefer-light"
        sh(f"gsettings set org.gnome.desktop.interface color-scheme '{scheme}'")


# ------------------------------------------------------------------- qt ---
def qt(pairs: dict) -> None:
    script = JHQS_SCRIPTS / "apply-qt.sh"
    subprocess.run(["bash", str(script)], check=False)


# --------------------------------------------------------------- portal ---
def portal(pairs: dict) -> None:
    enabled = pairs.get("enabled", "true").lower() == "true"
    t = theming()
    t["syncModeWithPortal"] = enabled
    atomic_write(THEMING_JSON, json.dumps(t, indent=4, sort_keys=True) + "\n")
    if enabled:
        mode = matugen_mode()
        scheme = "prefer-dark" if mode == "dark" else "prefer-light"
        sh(f"gsettings set org.gnome.desktop.interface color-scheme '{scheme}'")


# ------------------------------------------------------------ terminals ---
def terminals(pairs: dict) -> None:
    want = pairs.get("always_dark", "false").lower() == "true"
    t = theming()
    t["terminalsAlwaysDark"] = want
    atomic_write(THEMING_JSON, json.dumps(t, indent=4, sort_keys=True) + "\n")
    if not want:
        return
    # Re-render terminal outputs with the dark variant when the shell is light,
    # mirroring DMS "Terminals - Always use Dark Theme" (.default -> .dark).
    # matugen-run.sh does the dark kitty replay itself (detached), so a plain
    # light apply here is enough to converge everything.
    if matugen_mode() != "light":
        return
    wall = sh_out("cat ~/.config/quickshell/jhqs/config/current_wallpaper.txt 2>/dev/null | tr -d '\\r\\n'")
    if not wall:
        wall = sh_out("cat ~/.cache/swaybg/current 2>/dev/null | tr -d '\\r\\n'")
    if not wall or "\n" in wall:
        return
    mtype = read_json(MATUGEN_SETTINGS).get("type", "scheme-tonal-spot")
    if not re.fullmatch(r"scheme-[a-z-]+", mtype or ""):
        mtype = "scheme-tonal-spot"
    runner = JHQS_SCRIPTS / "matugen-run.sh"
    if runner.exists() and os.access(runner, os.X_OK):
        subprocess.run(["bash", str(runner), "image", wall,
                        "-t", mtype, "-m", "light", "--prefer", "saturation"],
                       check=False)
    else:
        sh(f"matugen image \"{wall}\" -t '{mtype}' -m light --prefer saturation")


# -------------------------------------------------------------- template --
# jhqs template name -> matugen [templates.*] block ids
TEMPLATE_GROUPS = {
    "gtk3": ["gtk3"],
    "gtk4": ["gtk4"],
    "qt5ct": ["qt5ct"],
    "qt6ct": ["qt6ct"],
    "qt-colorscheme": ["qt-colorscheme"],
    "kitty": ["kitty"],
    "ghostty": ["ghostty"],
    "fcitx5": ["fcitx5"],
    "firefox": ["firefox"],
    "vscode": ["vscode-raw", "vscode-json"],
    "neovim": ["neovim"],
    "btop": ["btop"],
    "vesktop": ["vesktop-midnight", "vesktop-system24"],
    "obs": ["obs", "obs-native"],
    "opencode": ["opencode"],
    "papirus": ["papirus"],
    "prismlauncher": ["prismlauncher"],
}

# Minimal block definitions so a disabled template can be re-added.
# Paths mirror the user's current matugen config.
TEMPLATE_DEFAULTS = {
    "gtk3": ('[templates.gtk3]\ninput_path = "{H}/.config/matugen/templates/gtk-colors.css"\noutput_path = "{H}/.config/gtk-3.0/colors.css"\n',),
    "gtk4": ('[templates.gtk4]\ninput_path = "{H}/.config/matugen/templates/gtk-colors.css"\noutput_path = "{H}/.config/gtk-4.0/colors.css"\npost_hook = "{H}/.config/matugen/post-hook-scripts/gtk-themes-reload.sh"\n',),
    "qt5ct": ('[templates.qt5ct]\ninput_path = "{H}/.config/matugen/templates/qtct-colors.conf"\noutput_path = "{H}/.config/qt5ct/colors/matugen.conf"\n',),
    "qt6ct": ('[templates.qt6ct]\ninput_path = "{H}/.config/matugen/templates/qtct-colors.conf"\noutput_path = "{H}/.config/qt6ct/colors/matugen.conf"\n',),
    "qt-colorscheme": ('[templates.qt-colorscheme]\ninput_path = "{H}/.config/matugen/templates/Matugen.colors"\noutput_path = "{H}/.local/share/color-schemes/Matugen.colors"\n',),
    "kitty": ('[templates.kitty]\ninput_path = "{H}/.config/matugen/templates/kitty-colors.conf"\noutput_path = "{H}/.config/kitty/current-theme.conf"\npost_hook = "killall -USR1 kitty 2>/dev/null || pkill -USR1 kitty 2>/dev/null || true"\n',),
    "ghostty": ('[templates.ghostty]\ninput_path = "{H}/.config/matugen/templates/ghostty-colors"\noutput_path = "{H}/.config/ghostty/themes/matugen"\n',),
    "fcitx5": ('[templates.fcitx5]\ninput_path = "{H}/.config/matugen/templates/fcitx5.conf"\noutput_path = "{H}/.config/fcitx5/conf/classic.conf"\n',),
    "firefox": ('[templates.firefox]\ninput_path = "{H}/.config/matugen/templates/firefox.css"\noutput_path = "{H}/.mozilla/firefox/default/chrome/matugen.css"\n',),
    "vscode-raw": ('[templates.vscode-raw]\ninput_path = "{H}/.config/matugen/templates/vscode-colors"\noutput_path = "{H}/.cache/matugen/vscode-colors"\n',),
    "vscode-json": ('[templates.vscode-json]\ninput_path = "{H}/.config/matugen/templates/vscode-colors.json"\noutput_path = "{H}/.cache/matugen/vscode-colors.json"\n',),
    "neovim": ('[templates.neovim]\ninput_path = "{H}/.config/matugen/templates/neovim.lua"\noutput_path = "{H}/.config/nvim/lua/matugen.lua"\n',),
    "btop": ('[templates.btop]\ninput_path = "{H}/.config/matugen/templates/btop.theme"\noutput_path = "{H}/.config/btop/themes/matugen.theme"\npost_hook = "sed -i -E \'s/^color_theme *= *\\".*\\"/color_theme = \\"matugen\\"/; s/^theme_background *= *.*/theme_background = False/\' {H}/.config/btop/btop.conf 2>/dev/null; pkill -USR2 btop 2>/dev/null || true"\n',),
    "vesktop-midnight": ('[templates.vesktop-midnight]\ninput_path = "{H}/.config/matugen/templates/midnight-discord.css"\noutput_path = "{H}/.config/vesktop/themes/midnight-discord.css"\n',),
    "vesktop-system24": ('[templates.vesktop-system24]\ninput_path = "{H}/.config/matugen/templates/system24.css"\noutput_path = "{H}/.config/vesktop/themes/system24.css"\n',),
    "obs": ('[templates.obs]\ninput_path = "{H}/.config/matugen/templates/matugen.obt"\noutput_path = "{H}/.var/app/com.obsproject.Studio/config/obs-studio/themes/matugen.obt"\n',),
    "obs-native": ('[templates.obs-native]\ninput_path = "{H}/.config/matugen/templates/matugen.obt"\noutput_path = "{H}/.config/obs-studio/themes/matugen.obt"\n',),
    "opencode": ('[templates.opencode]\ninput_path = "{H}/.config/matugen/templates/opencode.json"\noutput_path = "{H}/.config/opencode/themes/matugen.json"\n',),
    "papirus": ('[templates.papirus]\ninput_path = "{H}/.config/matugen/templates/papirus-folders.sh"\noutput_path = "{H}/.cache/matugen/papirus-folders.sh"\npost_hook = "bash {H}/.cache/matugen/papirus-folders.sh"\n',),
    "prismlauncher": ('[templates.prismlauncher]\ninput_path = "{H}/.config/matugen/templates/prismlauncher.json"\noutput_path = "{H}/.local/share/PrismLauncher/themes/Matugen/theme.json"\n',),
}


def _extract_blocks(config_text: str, keep: set) -> str:
    """Return only the [templates.X] blocks whose id is in keep."""
    out, cur_id, cur = [], None, []
    def flush():
        if cur_id in keep and cur:
            out.append("".join(cur))
    for line in config_text.splitlines(keepends=True):
        m = re.match(r"\[templates\.([^\]]+)\]", line.strip())
        if m:
            flush()
            cur_id, cur = m.group(1), [line]
        elif cur_id is not None:
            if line.startswith("[") and not line.startswith("[templates."):
                flush()
                cur_id, cur = None, []
            else:
                cur.append(line)
    flush()
    return "".join(out)


def _remove_blocks(config_text: str, drop: set) -> str:
    out, cur_id, cur = [], None, []
    def flush():
        if cur_id not in drop and cur:
            out.append("".join(cur))
    for line in config_text.splitlines(keepends=True):
        m = re.match(r"\[templates\.([^\]]+)\]", line.strip())
        if m:
            flush()
            cur_id, cur = m.group(1), [line]
        elif cur_id is not None:
            if line.startswith("[") and not line.startswith("[templates."):
                flush()
                cur_id, cur = None, []
                out.append(line)
            else:
                cur.append(line)
        else:
            out.append(line)
    flush()
    return "".join(out)


def template(pairs: dict) -> None:
    key = re.sub(r"[^a-z0-9-]", "", pairs.get("key", "").lower())
    if key not in TEMPLATE_GROUPS:
        return
    enabled = pairs.get("enabled", "true").lower() == "true"
    ids = set(TEMPLATE_GROUPS[key])
    cfg = MATUGEN_CONFIG.read_text() if MATUGEN_CONFIG.exists() else '[config]\nprefer = "saturation"\n'
    if enabled:
        have = set(re.findall(r"\[templates\.([^\]]+)\]", cfg))
        missing = [i for i in ids if i not in have]
        if missing:
            add = "".join(
                TEMPLATE_DEFAULTS[i][0].replace("{H}", str(HOME)) + "\n"
                for i in missing if i in TEMPLATE_DEFAULTS
            )
            cfg = cfg.rstrip() + "\n\n" + add
            atomic_write(MATUGEN_CONFIG, cfg)
    else:
        cfg2 = _remove_blocks(cfg, ids)
        if cfg2 != cfg:
            atomic_write(MATUGEN_CONFIG, cfg2)


DOMAINS = {
    "icon": icon,
    "cursor": cursor,
    "gtk": gtk,
    "qt": qt,
    "template": template,
    "portal": portal,
    "terminals": terminals,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in DOMAINS:
        print(f"usage: {sys.argv[0]} {{{'|'.join(DOMAINS)}}} key=value...", file=sys.stderr)
        sys.exit(1)
    domain = sys.argv[1]
    pairs = dict(a.split("=", 1) for a in sys.argv[2:] if "=" in a)
    DOMAINS[domain](pairs)
