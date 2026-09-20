#!/usr/bin/env bash
# set-renderer.sh — pin the Qt RHI backend for the solstice shell.
#
# Usage: set-renderer.sh <opengl|vulkan>
#
# Rewrites the QSG_RHI_BACKEND pin in backend/config/gpu.conf, the user config
# backend/scripts/solstice sources on every start (so the file survives shell
# updates). Takes effect on the next shell start; Settings > Setup >
# Experimental calls this and then restarts through the launcher.
set -eu

BACKEND="${1:-}"
case "$BACKEND" in
    opengl|vulkan) ;;
    *)  echo "set-renderer.sh: expected 'opengl' or 'vulkan', got '${BACKEND}'" >&2
        exit 2 ;;
esac

# Repo root: this file lives in backend/scripts/, two levels below it.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$ROOT/backend/config/gpu.conf"
LINE="QSG_RHI_BACKEND=$BACKEND"

if [[ ! -f "$CONF" ]]; then
    echo "set-renderer.sh: $CONF not found" >&2
    exit 1
fi

if grep -qE '^[[:space:]]*QSG_RHI_BACKEND=' "$CONF"; then
    # Replace the existing active pin (commented template lines do not match).
    sed -i -E "s|^[[:space:]]*QSG_RHI_BACKEND=.*$|$LINE|" "$CONF"
else
    printf '\n# Pinned by Settings > Setup > Experimental.\n%s\n' "$LINE" >>"$CONF"
fi

echo "$LINE"
