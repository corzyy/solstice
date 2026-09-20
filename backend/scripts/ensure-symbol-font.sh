#!/usr/bin/env bash
# ensure-symbol-font.sh — user-level Material Symbols Rounded install for the
# bar's workspace window glyphs.
#
# The workspace widget renders window icons as ligature glyphs from this
# variable font; systems without it show the ligature names as plain text.
# Installs into ~/.local/share/fonts (no root needed), then refreshes the
# fontconfig cache. Idempotent and best-effort: exits 0 when the font is
# already present or when the download fails.
set -u

FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
FONT_FILE="$FONT_DIR/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"
URL="${SOLSTICE_SYMBOL_FONT_URL:-https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf}"

if fc-list 2>/dev/null | grep -qi "Material Symbols Rounded"; then
    echo "symbol font: already installed"
    exit 0
fi

mkdir -p "$FONT_DIR" 2>/dev/null || true
TMP="$(mktemp "${TMPDIR:-/tmp}/MaterialSymbolsRounded.XXXXXX.ttf")" || exit 0
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
    echo "symbol font: download failed (workspace glyphs will use fallback fonts)" >&2
    exit 0
fi
# Sanity: a font, not an error page (the variable font is ~15 MiB).
size="$(wc -c < "$TMP" 2>/dev/null || echo 0)"
if [ "$size" -lt 1000000 ]; then
    echo "symbol font: download looked invalid, keeping fonts as-is" >&2
    exit 0
fi

mv -f "$TMP" "$FONT_FILE" || { echo "symbol font: install failed" >&2; exit 0; }
trap - EXIT INT TERM
if ! fc-cache -f "$FONT_DIR" >/dev/null 2>&1; then
    fc-cache -f >/dev/null 2>&1 || true
fi
echo "symbol font: installed $FONT_FILE"
