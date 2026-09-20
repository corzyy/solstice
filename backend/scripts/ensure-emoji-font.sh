#!/usr/bin/env bash
# ensure-emoji-font.sh — user-level Noto Color Emoji install for the launcher
# emoji picker (and the rest of the desktop).
#
# The picker renders emoji through the colour font; systems without one show
# tofu. Installs into ~/.local/share/fonts (no root needed), then refreshes
# the fontconfig cache. Idempotent and best-effort: exits 0 when a colour
# emoji font is already present or when the download fails (the picker then
# falls back to whatever fontconfig resolves).
set -u

FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
FONT_FILE="$FONT_DIR/NotoColorEmoji.ttf"
URL="${SOLSTICE_EMOJI_FONT_URL:-https://raw.githubusercontent.com/googlefonts/noto-emoji/main/2D/fonts/NotoColorEmoji.ttf}"

if fc-list 2>/dev/null | grep -qi "Noto Color Emoji"; then
    echo "emoji font: already installed"
    exit 0
fi

mkdir -p "$FONT_DIR" 2>/dev/null || true
TMP="$(mktemp "${TMPDIR:-/tmp}/NotoColorEmoji.XXXXXX.ttf")" || exit 0
trap 'rm -f "$TMP"' EXIT INT TERM

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fLsS --retry 2 --connect-timeout 15 -o "$TMP" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TMP" "$URL"
    elif command -v python3 >/dev/null 2>&1; then
        URL="$URL" TMP="$TMP" python3 -c \
            'import os, urllib.request; urllib.request.urlretrieve(os.environ["URL"], os.environ["TMP"])'
    else
        return 1
    fi
}

if ! fetch; then
    echo "emoji font: download failed (picker will use installed fonts only)" >&2
    exit 0
fi
# Sanity: a font, not an error page (NotoColorEmoji.ttf is ~10 MiB).
size="$(wc -c < "$TMP" 2>/dev/null || echo 0)"
if [ "$size" -lt 1000000 ]; then
    echo "emoji font: download looked invalid, keeping fonts as-is" >&2
    exit 0
fi

mv -f "$TMP" "$FONT_FILE" || { echo "emoji font: install failed" >&2; exit 0; }
trap - EXIT INT TERM
if ! fc-cache -f "$FONT_DIR" >/dev/null 2>&1; then
    fc-cache -f >/dev/null 2>&1 || true
fi
echo "emoji font: installed $FONT_FILE"
