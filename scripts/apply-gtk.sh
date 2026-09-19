#!/usr/bin/env bash
# apply-gtk.sh — point GTK3/4 at the matugen-generated colors (jhqs).
#
# Fast + idempotent: every write is skipped when the target state already
# holds, so repeated wallpaper applies cost ~nothing here. matugen's own
# post_hooks (gtk3 theme set, gtk4 color-scheme toggle) already force a GTK
# reload — this script only ensures the final values, it does NOT repeat the
# toggle dance (that double reload caused visible flicker + ~0.5s D-Bus time).
set -u

MODE="${1:-}"
if [ "$MODE" != "dark" ] && [ "$MODE" != "light" ]; then
  MODE="$(jq -r '.mode // "dark"' "$HOME/.config/quickshell/jhqs/themes/matugen_settings.json" 2>/dev/null || echo dark)"
fi
if [ "$MODE" != "dark" ] && [ "$MODE" != "light" ]; then MODE="dark"; fi

if [ "$MODE" = "dark" ]; then
  GTK_THEME="adw-gtk3-dark"
  PREF_DARK="1"
  COLOR_SCHEME="prefer-dark"
else
  GTK_THEME="adw-gtk3"
  PREF_DARK="0"
  COLOR_SCHEME="prefer-light"
fi

GTK3_DIR="$HOME/.config/gtk-3.0"
GTK4_DIR="$HOME/.config/gtk-4.0"
mkdir -p "$GTK3_DIR" "$GTK4_DIR" 2>/dev/null || true

ensure_import() {
  # $1 = file, $2 = header line to prepend when creating/extending
  local f="$1" header="$2" tmp
  if [ -L "$f" ]; then rm -f "$f"; fi
  if [ -f "$f" ]; then
    grep -q "colors.css" "$f" 2>/dev/null && return 0
    tmp="$(mktemp /tmp/jhqs-gtk.XXXXXX.css)"
    { printf '%b' "$header"; cat "$f"; } > "$tmp" 2>/dev/null && mv -f "$tmp" "$f"
    rm -f "$tmp"
  else
    printf '%b' "$header" > "$f"
  fi
}

ensure_import "$GTK3_DIR/gtk.css" '/* jhqs matugen GTK3 (managed by Style, do not hand-edit) */\n@import url("colors.css");\n'
GTK4_HEADER='/* jhqs matugen GTK4/libadwaita (managed by Style, do not hand-edit) */\n@import url("colors.css");\n'
ensure_import "$GTK4_DIR/gtk.css" "$GTK4_HEADER"
ensure_import "$GTK4_DIR/gtk-dark.css" "$GTK4_HEADER"

# settings.ini: rewrite only when values actually differ (avoids mtime churn
# that would re-trigger file watchers on every wallpaper change).
for f in "$GTK3_DIR/settings.ini" "$GTK4_DIR/settings.ini"; do
  GTK_THEME="$GTK_THEME" PREF_DARK="$PREF_DARK" FILE="$f" python3 - "$f" <<'EOF' 2>/dev/null || true
import os, sys
p = sys.argv[1]
theme = os.environ.get("GTK_THEME", "adw-gtk3-dark")
pref = os.environ.get("PREF_DARK", "1")
try:
    with open(p) as fh: lines = fh.read().splitlines()
except OSError:
    lines = []
orig = list(lines)
out, seen_theme, seen_pref = [], False, False
for l in lines:
    if l.startswith("gtk-theme-name="):
        out.append("gtk-theme-name=" + theme); seen_theme = True
    elif l.startswith("gtk-application-prefer-dark-theme="):
        out.append("gtk-application-prefer-dark-theme=" + pref); seen_pref = True
    else:
        out.append(l)
if "[Settings]" not in out and not any(l.strip() == "[Settings]" for l in out):
    out.insert(0, "[Settings]")
if not seen_theme:
    out.append("gtk-theme-name=" + theme)
if not seen_pref:
    out.append("gtk-application-prefer-dark-theme=" + pref)
if out != orig:
    os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
    with open(p, "w") as fh: fh.write("\n".join(out) + "\n")
EOF
done

# gsettings: read current values once; skip D-Bus writes when already correct.
CUR_THEME="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "")"
CUR_SCHEME="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "")"
WANT_THEME="'$GTK_THEME'"
WANT_SCHEME="'$COLOR_SCHEME'"

# jhqs Application Theming → "Sync Mode with Portal": when disabled, leave the
# portal color-scheme alone (mirrors DMS syncModeWithPortal).
SYNC="$(jq -r '.syncModeWithPortal // true' "$HOME/.config/quickshell/jhqs/config/theming_settings.json" 2>/dev/null || echo true)"

THEME_CHANGED=false
if [ "$CUR_THEME" != "$WANT_THEME" ]; then
  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
  THEME_CHANGED=true
fi
SCHEME_CHANGED=false
if [ "$SYNC" != "false" ] && [ "$CUR_SCHEME" != "$WANT_SCHEME" ]; then
  gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" 2>/dev/null || true
  SCHEME_CHANGED=true
fi

# Reload running GTK apps only when something actually changed — and only
# once (matugen's post_hooks already reloaded for the template outputs).
if $THEME_CHANGED || $SCHEME_CHANGED; then
  HOOK="$HOME/.config/matugen/post-hook-scripts/gtk-themes-reload.sh"
  if [ -x "$HOOK" ]; then
    bash "$HOOK" 2>/dev/null || true
    # The hook toggles color-scheme; restore the wanted value afterwards
    # (unless portal sync is disabled, in which case restore what was there).
    if [ "$SYNC" != "false" ]; then
      gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" 2>/dev/null || true
    else
      gsettings set org.gnome.desktop.interface color-scheme "$(echo "$CUR_SCHEME" | tr -d "'")" 2>/dev/null || true
    fi
  else
    # No hook: single toggle pair forces already-running GTK apps to reload.
    if [ "$CUR_SCHEME" = "'prefer-dark'" ]; then
      gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null || true
      gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    else
      gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
      gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null || true
    fi
    if [ "$SYNC" != "false" ]; then
      gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" 2>/dev/null || true
    elif [ -n "$CUR_SCHEME" ]; then
      gsettings set org.gnome.desktop.interface color-scheme "$(echo "$CUR_SCHEME" | tr -d "'")" 2>/dev/null || true
    fi
  fi
fi

echo "gtk applied: $MODE ($GTK_THEME)"
