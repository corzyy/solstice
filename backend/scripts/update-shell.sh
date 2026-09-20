#!/bin/bash
# Update the solstice quickshell from GitHub:
#   git clone the repo, install it over the live checkout (keeping the user's
#   config/ and themes/snapshots/), then restart the shell.
set -u

REPO="${SOLSTICE_REPO:-https://github.com/corzyy/solstice}"
DEST="${SOLSTICE_DEST:-$HOME/.config/quickshell/solstice}"
NO_RELOAD=0

usage() {
    echo "Usage: update-shell.sh [-y|--yes|--unattended] [--no-reload]"
    echo ""
    echo "Clones $REPO and installs it over $DEST,"
    echo "preserving config/ and themes/snapshots/, then restarts the shell."
    echo "Override with SOLSTICE_REPO / SOLSTICE_DEST env vars."
    echo "Set SOLSTICE_NO_RELOAD=1 or pass --no-reload to skip the restart."
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--unattended) ;; # no prompts, accepted for consistency with update.sh
        --no-reload) NO_RELOAD=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done
[[ -n "${SOLSTICE_NO_RELOAD:-}" ]] && NO_RELOAD=1

if ! command -v git >/dev/null 2>&1; then
    echo "git is not installed — cannot update the shell." >&2
    exit 1
fi

# Work on the same filesystem as DEST so the swap below is a fast rename.
PARENT="$(dirname "$DEST")"
mkdir -p "$PARENT"
TMP="$(mktemp -d "$PARENT/.solstice-update.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

echo "Cloning $REPO ..."
if ! git clone --depth 1 "$REPO" "$TMP/repo"; then
    echo "git clone failed." >&2
    exit 1
fi

if [[ ! -f "$TMP/repo/shell.qml" ]]; then
    echo "Clone looks invalid (shell.qml missing) — aborting, nothing was changed." >&2
    exit 1
fi

# Preserve user-owned state that must survive the update.
KEEP="$TMP/keep"
mkdir -p "$KEEP"
if [[ -d "$DEST/config" ]]; then
    cp -a "$DEST/config" "$KEEP/config"
fi
if [[ -d "$DEST/themes/snapshots" ]]; then
    mkdir -p "$KEEP/themes"
    cp -a "$DEST/themes/snapshots" "$KEEP/themes/snapshots"
fi
# Install brand-new default configs without overwriting user settings.
if [[ -d "$TMP/repo/config" && -d "$KEEP/config" ]]; then
    for src in "$TMP/repo/config/"*; do
        [[ -e "$src" ]] || continue
        base="$(basename "$src")"
        if [[ ! -e "$KEEP/config/$base" ]]; then
            echo "New default config: $base"
            cp -a "$src" "$KEEP/config/$base"
        fi
    done
fi

if [[ -d "$DEST/.git" ]] && [[ -z "${SOLSTICE_DEST:-}" ]]; then
    if [[ -n "$(git -C "$DEST" status --porcelain 2>/dev/null)" ]]; then
        echo "Note: local changes in $DEST — they will be replaced by the clone."
        echo ""
    fi
fi

# Swap the fresh clone into place (keeping the previous checkout until it
# succeeds, so a failed rename cannot leave the install missing).
echo "Installing to $DEST (keeping config/ and themes/snapshots/) ..."
if [[ -d "$DEST" ]]; then
    mv "$DEST" "$TMP/old"
fi
if ! mv "$TMP/repo" "$DEST"; then
    echo "Install failed — restoring the previous version." >&2
    [[ -d "$TMP/old" ]] && mv "$TMP/old" "$DEST"
    exit 1
fi

if [[ -d "$KEEP/config" ]]; then
    rm -rf "$DEST/config"
    cp -a "$KEEP/config" "$DEST/config"
fi
if [[ -d "$KEEP/themes/snapshots" ]]; then
    mkdir -p "$DEST/themes"
    rm -rf "$DEST/themes/snapshots"
    cp -a "$KEEP/themes/snapshots" "$DEST/themes/snapshots"
fi

chmod +x "$DEST/scripts/"*.sh "$DEST/scripts/solstice" 2>/dev/null || true

# Restart the shell so the new files take effect immediately.
# Skipped for test installs (SOLSTICE_DEST) unless explicitly allowed.
if ((NO_RELOAD)); then
    echo ""
    echo "Done. Restart skipped (--no-reload); restart quickshell manually to apply the update."
elif [[ -n "${SOLSTICE_DEST:-}" ]]; then
    echo ""
    echo "Done. (Test install — live shell not restarted.)"
elif command -v quickshell >/dev/null 2>&1; then
    echo ""
    echo "Restarting shell ..."
    if quickshell ipc -c solstice call solstice reload >/dev/null 2>&1; then
        echo "Done."
    else
        echo "Update installed, but the automatic restart failed."
        echo "Restart quickshell manually (e.g. qs kill; qs run, or reboot the session)."
    fi
else
    echo ""
    echo "Done. (quickshell binary not found — restart the shell manually to apply the update.)"
fi
