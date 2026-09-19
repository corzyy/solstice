#!/usr/bin/env bash
set -u
FAM="${1:-}"
SIZE="${2:-11}"
FAM="$(printf '%s' "$FAM" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [ -z "$FAM" ]; then echo "apply-font.sh: empty family" >&2; exit 1; fi
case "$FAM" in
  *$'\n'*|*$'\r'*|*$'\t'*) echo "apply-font.sh: invalid family" >&2; exit 1 ;;
esac
case "$SIZE" in
  ''|*[!0-9]*) SIZE=11 ;;
esac
[ "$SIZE" -lt 8 ] && SIZE=8
[ "$SIZE" -gt 16 ] && SIZE=16
IFACE="${FAM} ${SIZE}"
DOC="${FAM} $((SIZE + 1))"
TITLE="${FAM} Bold ${SIZE}"

# Monospace picks (JetBrains Mono, Geist Mono, ...) also drive the monospace
# contexts; proportional picks (Inter, Google Sans Flex, ...) must NOT — a
# proportional font as monospace breaks terminals and editors.
IS_MONO=0
case "$FAM" in
  *[Mm][Oo][Nn][Oo]*) IS_MONO=1 ;;
esac
MONO_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/jhqs/last-mono-font"
if [ "$IS_MONO" = 1 ]; then
  mkdir -p "$(dirname "$MONO_STATE")" 2>/dev/null || true
  printf '%s\n' "$FAM" > "$MONO_STATE" 2>/dev/null || true
  MONO_FAM="$FAM"
elif [ -f "$MONO_STATE" ]; then
  MONO_FAM="$(head -n 1 "$MONO_STATE" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$MONO_FAM" ] && MONO_FAM=""
else
  MONO_FAM=""
fi
MONO_IFACE="${MONO_FAM} ${SIZE}"

gsettings set org.gnome.desktop.interface font-name "$IFACE" 2>/dev/null || true
gsettings set org.gnome.desktop.interface document-font-name "$DOC" 2>/dev/null || true
gsettings set org.gnome.desktop.wm.preferences titlebar-font "$TITLE" 2>/dev/null || true
if [ "$IS_MONO" = 1 ]; then
  gsettings set org.gnome.desktop.interface monospace-font-name "$MONO_IFACE" 2>/dev/null || true
fi

for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
  [ -e "$f" ] || continue
  if grep -q '^gtk-font-name=' "$f" 2>/dev/null; then
    IFACE="$IFACE" FILE="$f" python3 - "$f" <<'EOF' 2>/dev/null || true
import os, sys
p = sys.argv[1]
v = os.environ.get("IFACE", "")
try:
    with open(p) as fh: lines = fh.read().splitlines()
except OSError:
    sys.exit(1)
out = [("gtk-font-name=" + v) if l.startswith("gtk-font-name=") else l for l in lines]
with open(p, "w") as fh: fh.write("\n".join(out) + "\n")
EOF
  else
    grep -q '^\[Settings\]' "$f" 2>/dev/null || printf '[Settings]\n' >> "$f"
    printf 'gtk-font-name=%s\n' "$IFACE" >> "$f"
  fi
  if [ "$IS_MONO" = 1 ] && grep -q '^gtk-monospace-font-name=' "$f" 2>/dev/null; then
    MONO_IFACE="$MONO_IFACE" python3 - "$f" <<'EOF' 2>/dev/null || true
import os, sys
p = sys.argv[1]
v = os.environ.get("MONO_IFACE", "")
try:
    with open(p) as fh: lines = fh.read().splitlines()
except OSError:
    sys.exit(1)
out = [("gtk-monospace-font-name=" + v) if l.startswith("gtk-monospace-font-name=") else l for l in lines]
with open(p, "w") as fh: fh.write("\n".join(out) + "\n")
EOF
  fi
done

for f in "$HOME/.config/qt6ct/qt6ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"; do
  [ -f "$f" ] || continue
  FAM_QT="$FAM" FILE_QT="$f" python3 - "$f" <<'EOF' 2>/dev/null || true
import os, re, sys
p = sys.argv[1]
fam = os.environ.get("FAM_QT", "")
try:
    with open(p) as fh: txt = fh.read()
except OSError:
    sys.exit(1)
txt2 = re.sub(r'^general="[^,"]*', 'general="' + fam.replace('\\', '\\\\').replace('"', ''), txt, count=1, flags=re.M)
if txt2 != txt:
    with open(p, "w") as fh: fh.write(txt2)
EOF
done

# fontconfig: managed fragment instead of overwriting fonts.conf, so hand-made
# user customizations (emoji fallback, hinting, ...) survive font switches.
mkdir -p "$HOME/.config/fontconfig/conf.d" 2>/dev/null || true
LEGACY="$HOME/.config/fontconfig/fonts.conf"
if [ -f "$LEGACY" ] && grep -q 'jhqs system font' "$LEGACY" 2>/dev/null; then
  rm -f "$LEGACY" 2>/dev/null || true
fi
FAM="$FAM" MONO_FAM="${MONO_FAM:-}" python3 <<'EOF' 2>/dev/null || true
import os
from xml.sax.saxutils import escape
fam = escape(os.environ.get("FAM", ""))
mono = escape(os.environ.get("MONO_FAM", "").strip())
aliases = [
    ("sans-serif", fam),
    ("sans", fam),
]
if mono:
    aliases.append(("monospace", mono))
blocks = "\n".join(
    """  <alias>
    <family>{A}</family>
    <prefer>
      <family>{F}</family>
    </prefer>
  </alias>""".format(A=a, F=f) for a, f in aliases
)
xml = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- jhqs system font (managed by Style -> Font, do not hand-edit) -->
{blocks}
</fontconfig>
""".format(blocks=blocks)
with open(os.path.expanduser("~/.config/fontconfig/conf.d/10-jhqs-system-font.conf"), "w") as fh:
    fh.write(xml)
EOF
fc-cache -f "$HOME/.local/share/fonts" "$HOME/.fonts" 2>/dev/null || fc-cache 2>/dev/null || true

XSET="$HOME/.config/xsettingsd/xsettingsd.conf"
if [ -f "$XSET" ]; then
  grep -v '^Gtk/FontName' "$XSET" > /tmp/jhqs-xsettingsd.conf 2>/dev/null && mv /tmp/jhqs-xsettingsd.conf "$XSET"
  printf 'Gtk/FontName "%s"\n' "$IFACE" >> "$XSET"
  pkill -HUP -x xsettingsd 2>/dev/null || true
fi
KITTY_CONF="$HOME/.config/kitty/kitty.conf"
if [ -f "$KITTY_CONF" ]; then
  FAM_KITTY="$FAM" FILE_KITTY="$KITTY_CONF" python3 - "$KITTY_CONF" <<'EOF' 2>/dev/null || true
import os, re, sys
p = sys.argv[1]
fam = os.environ.get("FAM_KITTY", "").strip()
if not fam:
    sys.exit(1)
fam = re.sub(r'[\r\n\t]', '', fam)
try:
    with open(p) as fh: txt = fh.read()
except OSError:
    sys.exit(1)
pat = r'^(?P<indent>\s*font_family\s+).*$'
txt2, n = re.subn(pat, r'\g<indent>' + fam, txt, flags=re.M)
if n == 0:
    txt2 = txt.rstrip() + "\nfont_family " + fam + "\n"
if txt2 != txt:
    with open(p, "w") as fh: fh.write(txt2)
EOF
  pkill -USR1 kitty 2>/dev/null || true
fi
FOOT_INI="$HOME/.config/foot/foot.ini"
if [ -f "$FOOT_INI" ]; then
  FAM_FOOT="$FAM" SIZE_FOOT="$SIZE" python3 - "$FOOT_INI" <<'EOF' 2>/dev/null || true
import os, re, sys
p = sys.argv[1]
fam = re.sub(r'[\r\n\t]', '', os.environ.get("FAM_FOOT", "").strip())
size = os.environ.get("SIZE_FOOT", "11").strip() or "11"
if not fam:
    sys.exit(1)
try:
    with open(p) as fh: txt = fh.read()
except OSError:
    sys.exit(1)
val = "{},size={}".format(fam, size)
txt2, n = re.subn(r'^\s*font\s*=.*$', "font=" + val, txt, flags=re.M)
if n == 0:
    if re.search(r'^\[main\]', txt, flags=re.M):
        txt2 = re.sub(r'^(\[main\].*)$', r'\1' + "\nfont=" + val, txt, count=1, flags=re.M)
    else:
        txt2 = "[main]\nfont=" + val + "\n" + txt
if txt2 != txt:
    with open(p, "w") as fh: fh.write(txt2)
EOF
fi
GHOSTTY_CONF="$HOME/.config/ghostty/config"
if [ -f "$GHOSTTY_CONF" ]; then
  FAM_GHOSTTY="$FAM" SIZE_GHOSTTY="$SIZE" python3 - "$GHOSTTY_CONF" <<'EOF' 2>/dev/null || true
import os, re, sys
p = sys.argv[1]
fam = re.sub(r'[\r\n\t]', '', os.environ.get("FAM_GHOSTTY", "").strip())
size = os.environ.get("SIZE_GHOSTTY", "11").strip() or "11"
if not fam:
    sys.exit(1)
try:
    with open(p) as fh: txt = fh.read()
except OSError:
    sys.exit(1)
txt2, n = re.subn(r'^\s*font-family\s*=.*$', "font-family = " + fam, txt, flags=re.M)
if n == 0:
    txt2 = txt.rstrip() + "\nfont-family = " + fam + "\n"
txt3, m = re.subn(r'^\s*font-size\s*=.*$', "font-size = " + size, txt2, flags=re.M)
if m == 0:
    txt3 = txt2.rstrip() + "\nfont-size = " + size + "\n"
if txt3 != txt:
    with open(p, "w") as fh: fh.write(txt3)
EOF
fi

# Flatpak sandbox: expose host fontconfig + user fonts so sandboxed apps
# (Sober, Spotifast, ...) resolve the same families. Idempotent.
if command -v flatpak >/dev/null 2>&1; then
  flatpak override --user --filesystem=xdg-config/fontconfig:ro >/dev/null 2>&1 || true
  flatpak override --user --filesystem=xdg-data/fonts:ro >/dev/null 2>&1 || true
fi

if [ "$IS_MONO" = 1 ]; then
  echo "font applied: $FAM (sans + monospace)"
else
  echo "font applied: $FAM (sans; monospace kept at ${MONO_FAM:-default})"
fi
