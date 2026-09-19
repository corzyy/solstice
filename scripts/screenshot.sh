#!/usr/bin/env bash
# screenshot.sh — capture backend for the screenshot UI
# (overlays/ScreenshotUI.qml, PRINT keybind).
#
# Usage: screenshot.sh <region|window|fullscreen> [geometry]
#   region      interactive selection via slurp (geometry ignored)
#   window      geometry "X,Y WxH" from umbriel's window list; falls back
#               to the full desktop when empty
#   fullscreen  all outputs
#
# Options (environment, set by the UI from config/screenshot.json):
#   JHQS_SHOT_DIR       save folder override (~ is expanded; empty = default)
#   JHQS_SHOT_CURSOR    1 = include the cursor (grim -c)
#   JHQS_SHOT_CLIPBOARD 0 = don't copy to the clipboard
#   JHQS_SHOT_NOTIFY    0 = don't post a notification
#
# The shot is saved to $JHQS_SHOT_DIR, else $XDG_PICTURES_DIR/Screenshots,
# else ~/Pictures/Screenshots. Exit codes: 0 ok, 3 region cancelled,
# 2 grim failed, 127 missing dependency. stdout prints the saved path.
set -u

mode="${1:-fullscreen}"
geo="${2:-}"

cursor="${JHQS_SHOT_CURSOR:-0}"
copy="${JHQS_SHOT_CLIPBOARD:-1}"
toast="${JHQS_SHOT_NOTIFY:-1}"

notify() {
    [[ "$toast" == "1" ]] || return 0
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a Screenshot "$1" "$2" 2>/dev/null || true
}

if ! command -v grim >/dev/null 2>&1; then
    notify "Screenshot failed" "grim is not installed"
    exit 127
fi

dir="${JHQS_SHOT_DIR:-}"
if [[ -z "$dir" ]]; then
    dir="${XDG_PICTURES_DIR:-}"
    if [[ -z "$dir" ]]; then
        dir="$(xdg-user-dir PICTURES 2>/dev/null || true)"
    fi
    [[ -n "$dir" ]] || dir="$HOME/Pictures"
    dir="$dir/Screenshots"
fi
# Stored paths are portable ("~/Pictures/..."), expand before use.
dir="${dir/#\~/$HOME}"
mkdir -p "$dir" || exit 1
file="$dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

grim_flags=()
[[ "$cursor" == "1" ]] && grim_flags+=(-c)

case "$mode" in
    region)
        if ! command -v slurp >/dev/null 2>&1; then
            notify "Screenshot failed" "slurp is not installed"
            exit 127
        fi
        # stdin MUST be /dev/null: slurp 1.5+ reads boxes from stdin when it
        # is a pipe, and processes spawned by the shell inherit an unread
        # stdin pipe — slurp would block forever and never map its selection
        # overlay (region mode looked completely dead).
        sel="$(slurp </dev/null 2>/dev/null)" || exit 3
        [[ -n "$sel" ]] || exit 3
        grim "${grim_flags[@]}" -g "$sel" "$file" || exit 2
        ;;
    window)
        if [[ -n "$geo" ]]; then
            grim "${grim_flags[@]}" -g "$geo" "$file" || exit 2
        else
            grim "${grim_flags[@]}" "$file" || exit 2
        fi
        ;;
    *)
        grim "${grim_flags[@]}" "$file" || exit 2
        ;;
esac

# Clipboard + toast are best-effort: a missing helper must never lose the file.
if [[ "$copy" == "1" ]] && command -v wl-copy >/dev/null 2>&1; then
    wl-copy -t image/png < "$file" 2>/dev/null || true
fi
if [[ "$toast" == "1" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send -a Screenshot -i "$file" \
        -h string:x-canonical-private-synchronous:screenshot \
        "Screenshot saved" "$(basename "$file")" 2>/dev/null || true
fi

printf '%s\n' "$file"
