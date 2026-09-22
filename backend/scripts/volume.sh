#!/usr/bin/env bash

set -euo pipefail

SINK="@DEFAULT_AUDIO_SINK@"
# STABILITY: every wpctl/pactl call is bounded. A wedged PipeWire daemon would
# otherwise hang the shell's probe/step processes forever (the shell polls the
# `get` path while PipeWire is not ready).
WPCTL_TIMEOUT="${SOLSTICE_AUDIO_TIMEOUT:-2}"

has_wpctl() { command -v wpctl >/dev/null 2>&1; }
has_pactl() { command -v pactl >/dev/null 2>&1; }

get_volume_wpctl() {
    timeout "$WPCTL_TIMEOUT" wpctl get-volume "$SINK" 2>/dev/null | awk '{print $2*100}' | cut -d. -f1
}

get_volume_pactl() {
    timeout "$WPCTL_TIMEOUT" pactl get-sink-volume "$SINK" 2>/dev/null | grep -oP '\d+%' | head -1 || echo "0%"
}

case "${1:-}" in
    up)
        if has_wpctl; then
            timeout "$WPCTL_TIMEOUT" wpctl set-volume "$SINK" 5%+ -l 1.0
        elif has_pactl; then
            timeout "$WPCTL_TIMEOUT" pactl set-sink-volume "$SINK" +5%
        else
            echo "No wpctl/pactl found" >&2; exit 1
        fi
        ;;
    down)
        if has_wpctl; then
            timeout "$WPCTL_TIMEOUT" wpctl set-volume "$SINK" 5%-
        elif has_pactl; then
            timeout "$WPCTL_TIMEOUT" pactl set-sink-volume "$SINK" -5%
        else
            echo "No wpctl/pactl found" >&2; exit 1
        fi
        ;;
    mute)
        if has_wpctl; then
            timeout "$WPCTL_TIMEOUT" wpctl set-mute "$SINK" toggle
        elif has_pactl; then
            timeout "$WPCTL_TIMEOUT" pactl set-sink-mute "$SINK" toggle
        else
            echo "No wpctl/pactl found" >&2; exit 1
        fi
        ;;
    get)
        if has_wpctl; then
            if timeout "$WPCTL_TIMEOUT" wpctl get-volume "$SINK" 2>/dev/null | grep -q MUTED; then
                echo "muted"
            else
                echo "$(get_volume_wpctl)%"
            fi
        elif has_pactl; then
            if timeout "$WPCTL_TIMEOUT" pactl get-sink-mute "$SINK" 2>/dev/null | grep -q yes; then
                echo "muted"
            else
                echo "$(get_volume_pactl)"
            fi
        else
            echo "--%"
        fi
        ;;
    *)
        echo "Usage: $0 {up|down|mute|get}" >&2
        exit 1
        ;;
esac
