#!/bin/bash
set -uo pipefail

DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="$DESKTOP_DIR/icons"

usage() {
    echo "Usage: $(basename "$0") <name> [name...] [--force]" >&2
}

is_webapp_desktop() {
    grep -q -E '^Exec=.*(launch-webapp|webapp-handler|webapp-launch|solstice-webapp|--app=)' "$1" 2>/dev/null
}

FORCE=0
NAMES=()
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --force) FORCE=1 ;;
        *) NAMES+=("$arg") ;;
    esac
done

if [[ ${#NAMES[@]} -eq 0 ]]; then
    usage
    exit 1
fi

fail=0
for raw in "${NAMES[@]}"; do
    name="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$raw")"
    name="${name%.desktop}"
    if [[ -z "$name" ]]; then
        echo "Skip: empty name." >&2
        fail=1
        continue
    fi
    if [[ "$name" == *"/"* || "$name" == "." || "$name" == ".." ]]; then
        echo "Skip: invalid name '$raw'." >&2
        fail=1
        continue
    fi
    if [[ "$name" == *$'\n'* || "$name" == *$'\r'* ]]; then
        echo "Skip: invalid name." >&2
        fail=1
        continue
    fi
    target="$DESKTOP_DIR/$name.desktop"
    if [[ ! -e "$target" ]]; then
        echo "Removed $name (already gone)."
        rm -f "$ICON_DIR/$name.png" "$ICON_DIR/$name.jpg" "$ICON_DIR/$name.svg" "$ICON_DIR/$name.ico" 2>/dev/null || true
        continue
    fi
    real="$(readlink -m "$target" 2>/dev/null || printf '%s' "$target")"
    case "$real" in
        "$DESKTOP_DIR"/*) ;;
        *) echo "Skip: '$name' escapes app dir." >&2; fail=1; continue ;;
    esac
    if [[ $FORCE -eq 0 ]] && ! is_webapp_desktop "$target"; then
        echo "Skip: '$name' is not a web app (use --force to override)." >&2
        fail=1
        continue
    fi
    icon_ref="$(grep -m1 -E '^Icon=' "$target" 2>/dev/null | cut -d= -f2- || true)"
    rm -f "$target" 2>/dev/null || { echo "Error: cannot remove '$name'." >&2; fail=1; continue; }
    if [[ "$icon_ref" == "$ICON_DIR"/* ]]; then
        icon_real="$(readlink -m "$icon_ref" 2>/dev/null || printf '%s' "$icon_ref")"
        case "$icon_real" in
            "$ICON_DIR"/*) rm -f "$icon_real" 2>/dev/null || true ;;
        esac
    fi
    rm -f "$ICON_DIR/$name.png" "$ICON_DIR/$name.jpg" "$ICON_DIR/$name.svg" "$ICON_DIR/$name.ico" 2>/dev/null || true
    echo "Removed $name"
done

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

exit "$fail"
