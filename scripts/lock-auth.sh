#!/usr/bin/env bash
set -uo pipefail
PASS="${1:-}"
PIN_FILE="$HOME/.config/quickshell/jhqs/config/pin"

if [ -f "$PIN_FILE" ]; then
    PIN=$(tr -d '\r\n' < "$PIN_FILE")
    if [ "$PASS" = "$PIN" ]; then
        exit 0
    fi
    if [ -n "$PASS" ]; then
        echo "$PASS" | sudo -S -k true 2>/dev/null && exit 0
    fi
    exit 1
else
    if [ -z "$PASS" ]; then exit 1; fi
    echo "$PASS" | sudo -S -k true 2>/dev/null
    exit $?
fi
