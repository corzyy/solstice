#!/usr/bin/env bash
# instance-check.sh — decide whether this shell is the primary instance of
# its config.
#
# Usage: instance-check.sh <config-path> <self-pid>
#
# Prints "primary" if this process is the oldest live quickshell instance for
# <config-path>, "duplicate" if another (older) live instance exists.
#
# A second instance of the same config would fight the first over the
# notification server and polkit agent DBus names (and stack a second bar on
# screen). quickshell's own `--no-duplicate` flag only covers launches
# through backend/scripts/solstice, so the shell runs this check itself.
#
# If anything goes wrong the check reports "primary": a failed guard must not
# prevent the shell from starting.
set -u

CFG="${1:-}"
SELF="${2:-}"
[ -n "$CFG" ] || { echo primary; exit 0; }

# The quickshell binary running this shell is our parent process.
# SOLSTICE_QS_BIN overrides it (tests).
QS_BIN="${SOLSTICE_QS_BIN:-}"
if [ -z "$QS_BIN" ]; then
    QS_BIN="$(readlink -f "/proc/$PPID/exe" 2>/dev/null || true)"
    if [ -z "$QS_BIN" ] || [ ! -x "$QS_BIN" ]; then
        QS_BIN="$(command -v quickshell || command -v qs || true)"
    fi
fi
[ -n "$QS_BIN" ] || { echo primary; exit 0; }

"$QS_BIN" list --all 2>/dev/null | awk -v cfg="$CFG" -v self="$SELF" '
# Evaluate the block collected so far.
function consider() {
    if (path != cfg || pid == "") return
    if (best_pid == "" || stamp < best_stamp || (stamp == best_stamp && pid < best_pid)) {
        best_stamp = stamp
        best_pid = pid
    }
}
/^Instance /       { consider(); path = ""; pid = ""; stamp = "" }
/^  Process ID: /  { pid = $0; sub(/^  Process ID: /, "", pid) }
/^  Config path: / { path = $0; sub(/^  Config path: /, "", path) }
/^  Launch time: / { stamp = $0; sub(/^  Launch time: /, "", stamp); stamp = substr(stamp, 1, 19) }
END {
    consider()
    # Another (older) live instance of this config wins; no match at all
    # means the registry could not be read, so assume primary.
    if (best_pid != "" && best_pid != self) print "duplicate"
    else print "primary"
}
'
