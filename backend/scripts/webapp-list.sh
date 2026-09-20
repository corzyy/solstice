#!/bin/bash
set -uo pipefail

DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
[[ -d "$DESKTOP_DIR" ]] || exit 0

find "$DESKTOP_DIR" -maxdepth 3 -name '*.desktop' -print0 2>/dev/null |
while IFS= read -r -d '' f; do
    grep -q -E '^Exec=.*(launch-webapp|webapp-handler|webapp-launch|solstice-webapp|--app=)' "$f" 2>/dev/null || continue
    base="$(basename "$f" .desktop)"
    dname="$(grep -m1 -E '^Name=' "$f" 2>/dev/null | cut -d= -f2- || true)"
    exec_line="$(grep -m1 -E '^Exec=' "$f" 2>/dev/null | cut -d= -f2- || true)"
    icon="$(grep -m1 -E '^Icon=' "$f" 2>/dev/null | cut -d= -f2- || true)"
    base="${base//$'\t'/ }"; base="${base//$'\n'/ }"
    dname="${dname//$'\t'/ }"; dname="${dname//$'\n'/ }"
    exec_line="${exec_line//$'\t'/ }"; exec_line="${exec_line//$'\n'/ }"
    icon="${icon//$'\t'/ }"; icon="${icon//$'\n'/ }"
    [[ -n "$base" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$base" "$f" "$dname" "$exec_line" "$icon"
done

exit 0
