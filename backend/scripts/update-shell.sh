#!/bin/bash
# Update the solstice quickshell from GitHub:
#   git clone the repo, install it over the live checkout (keeping the user's
#   backend/config/ and style/themes/snapshots/), then restart the shell.
set -u

REPO="${SOLSTICE_REPO:-https://github.com/corzyy/solstice}"
DEST="${SOLSTICE_DEST:-$HOME/.config/quickshell/solstice}"
NO_RELOAD=0

usage() {
    echo "Usage: update-shell.sh [-y|--yes|--unattended] [--no-reload]"
    echo ""
    echo "Clones $REPO and installs it over $DEST,"
    echo "preserving backend/config/ and style/themes/snapshots/, then restarts the shell."
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
# STABILITY: serialize concurrent install/update runs — two runs swapping the
# same $DEST can leave a partial install behind.
if command -v flock >/dev/null 2>&1; then
    exec 9>"$PARENT/.solstice-install.lock"
    if ! flock -n 9; then
        echo "Another solstice install/update is already running — aborting." >&2
        exit 1
    fi
fi
TMP="$(mktemp -d "$PARENT/.solstice-update.XXXXXX")"
cleanup() {
    # STABILITY: an interrupt between the two swap renames leaves the previous
    # install in $TMP/old with $DEST missing. Restore it before removing the
    # staging dir — the old install is otherwise unrecoverable.
    if [[ -n "${TMP:-}" && -d "$TMP/old" && ! -e "$DEST" ]]; then
        mv "$TMP/old" "$DEST" 2>/dev/null || true
    fi
    [[ -n "${TMP:-}" ]] && rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

echo "Cloning $REPO ..."
if ! timeout 300 git clone --depth 1 "$REPO" "$TMP/repo"; then
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
if [[ -d "$DEST/backend/config" ]]; then
    cp -a "$DEST/backend/config" "$KEEP/backend/config"
fi
if [[ -d "$DEST/style/themes/snapshots" ]]; then
    mkdir -p "$KEEP/style/themes"
    cp -a "$DEST/style/themes/snapshots" "$KEEP/style/themes/snapshots"
fi
# Install brand-new default configs without overwriting user settings.
if [[ -d "$TMP/repo/backend/config" && -d "$KEEP/backend/config" ]]; then
    for src in "$TMP/repo/backend/config/"*; do
        [[ -e "$src" ]] || continue
        base="$(basename "$src")"
        if [[ ! -e "$KEEP/backend/config/$base" ]]; then
            echo "New default config: $base"
            cp -a "$src" "$KEEP/backend/config/$base"
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
echo "Installing to $DEST (keeping backend/config/ and style/themes/snapshots/) ..."
if [[ -d "$DEST" ]]; then
    mv "$DEST" "$TMP/old"
fi
if ! mv "$TMP/repo" "$DEST"; then
    echo "Install failed — restoring the previous version." >&2
    [[ -d "$TMP/old" ]] && mv "$TMP/old" "$DEST"
    exit 1
fi

# STABILITY: copy into a sibling, then rename. The old `rm -rf` + copy lost
# the user's config if the script died in between.
if [[ -d "$KEEP/backend/config" ]]; then
    rm -rf "$DEST/backend/config.new"
    cp -a "$KEEP/backend/config" "$DEST/backend/config.new"
    rm -rf "$DEST/backend/config.old"
    [[ -d "$DEST/backend/config" ]] && mv "$DEST/backend/config" "$DEST/backend/config.old"
    mv "$DEST/backend/config.new" "$DEST/backend/config"
    rm -rf "$DEST/backend/config.old"
fi
if [[ -d "$KEEP/style/themes/snapshots" ]]; then
    mkdir -p "$DEST/style/themes"
    rm -rf "$DEST/style/themes/snapshots.new"
    cp -a "$KEEP/style/themes/snapshots" "$DEST/style/themes/snapshots.new"
    rm -rf "$DEST/style/themes/snapshots.old"
    [[ -d "$DEST/style/themes/snapshots" ]] && mv "$DEST/style/themes/snapshots" "$DEST/style/themes/snapshots.old"
    mv "$DEST/style/themes/snapshots.new" "$DEST/style/themes/snapshots"
    rm -rf "$DEST/style/themes/snapshots.old"
fi

chmod +x "$DEST/backend/scripts/"*.sh "$DEST/backend/scripts/solstice" 2>/dev/null || true

# Keep the `solstice` CLI in PATH pointing at the live install: Hyprland's
# autostart and all shell keybinds spawn through it. Skipped for test installs.
if [[ -z "${SOLSTICE_DEST:-}" ]]; then
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    ln -sf "$DEST/backend/scripts/solstice" "$BIN_DIR/solstice"
fi

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
    if timeout 10 quickshell ipc -c solstice call solstice reload >/dev/null 2>&1; then
        echo "Done."
    else
        echo "Update installed, but the automatic restart failed."
        echo "Restart quickshell manually (e.g. qs kill; qs run, or reboot the session)."
    fi
else
    echo ""
    echo "Done. (quickshell binary not found — restart the shell manually to apply the update.)"
fi
