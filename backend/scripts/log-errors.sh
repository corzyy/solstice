#!/usr/bin/env bash
# log-errors.sh — persist the running shell's errors to logs/errors.log.
#
# Quickshell only keeps its log in the (ephemeral) runtime dir. This script
# follows the shell's own log (`quickshell log -f`), strips formatting,
# and appends every ERROR / WARN / CRITICAL / FATAL line with a timestamp
# to the output file, so errors are saved while the shell is running.
#
# Started by services/LogService.qml; safe to run manually:
#   log-errors.sh <shell-pid> <marker> <output-file>
#   log-errors.sh --stop <log-dir>
#
# <marker> is a one-time string LogService emits into the shell log with
# console.info(). Everything decoded before that marker is stale history
# (e.g. from before a config reload) and is skipped, so a reload never
# duplicates entries. Pass an empty marker to log the whole history.
#
# Only one follower runs at a time: the newcomer terminates the previous
# one (a reload leaves it alive — QProcess children are not killed) via
# the pidfile, then replays up to its own marker — no gaps, no duplicates.

set -euo pipefail

# Terminate the follower started by the previous shell config, if any.
stop_previous() {
    local pidfile="$1/.errors.pid" prev="" tries=0
    [ -f "$pidfile" ] && prev="$(tr -cd '0-9' < "$pidfile" 2>/dev/null)"
    if [ -n "$prev" ] && [ "$prev" != "$$" ] && kill -0 "$prev" 2>/dev/null; then
        # PID-reuse guard: only signal our own follower.
        if tr '\0' ' ' < "/proc/$prev/cmdline" 2>/dev/null | grep -q "log-errors.sh"; then
            kill "$prev" 2>/dev/null
            while kill -0 "$prev" 2>/dev/null && [ "$tries" -lt 20 ]; do
                sleep 0.1
                tries=$((tries + 1))
            done
            kill -9 "$prev" 2>/dev/null
        fi
    fi
}

if [ "${1:-}" = "--stop" ]; then
    [ -n "${2:-}" ] || { echo "log-errors.sh: --stop needs <log-dir>" >&2; exit 2; }
    stop_previous "$2"
    exit 0
fi

PID="${1:-}"
MARKER="${2:-}"
OUT="${3:-}"

[ -n "$PID" ] || { echo "log-errors.sh: missing <shell-pid>" >&2; exit 2; }
[ -n "$OUT" ] || { echo "log-errors.sh: missing <output-file>" >&2; exit 2; }

LOG_DIR="$(dirname "$OUT")"
mkdir -p "$LOG_DIR"

# Take over from any previous follower before replaying: it must be gone
# before our marker goes out, otherwise lines between the marker and its
# death would be logged twice.
stop_previous "$LOG_DIR"

# Serialize against a racing starter.
exec 9>"$LOG_DIR/.errors.lock"
flock 9
echo "$$" > "$LOG_DIR/.errors.pid"

# Rotate at 1 MiB so the file can never grow without bound.
if [ -f "$OUT" ] && [ "$(stat -c%s "$OUT" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$OUT" "$OUT.1"
fi

QS="${SOLSTICE_QS:-}"
if [ -z "$QS" ]; then
    if command -v quickshell >/dev/null 2>&1; then
        QS=quickshell
    elif command -v qs >/dev/null 2>&1; then
        QS=qs
    else
        echo "log-errors.sh: quickshell binary not found (set SOLSTICE_QS)" >&2
        exit 127
    fi
fi

coproc LOGTAIL { "$QS" --no-color log -f --pid "$PID" 2>/dev/null; }
TAIL_PID="$LOGTAIL_PID"
trap 'kill "$TAIL_PID" 2>/dev/null' EXIT TERM INT HUP

SEEN_MARKER=0
[ -z "$MARKER" ] && SEEN_MARKER=1

while IFS= read -r line <&"${LOGTAIL[0]}"; do
    clean="$(printf '%s' "$line" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')"

    if [ "$SEEN_MARKER" -eq 0 ]; then
        case "$clean" in
            *"$MARKER"*) SEEN_MARKER=1 ;;
        esac
        continue
    fi

    case "$clean" in
        *ERROR*|*WARN*|*CRITICAL*|*FATAL*)
            printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$clean" >> "$OUT" ;;
    esac
done
