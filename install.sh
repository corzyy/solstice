#!/usr/bin/env bash
# solstice installer.
#
# One-liner (fresh install):
#   curl -fsSL https://raw.githubusercontent.com/corzyy/solstice/main/install.sh | bash
#
# Or run from a checkout:  ./install.sh
#
# Installs the solstice quickshell to ${SOLSTICE_DEST:-$HOME/.config/quickshell/solstice},
# preserving any existing backend/config/ and style/themes/snapshots/.
set -u

REPO="${SOLSTICE_REPO:-https://github.com/corzyy/solstice}"
REF="${SOLSTICE_REF:-main}"
DEST="${SOLSTICE_DEST:-$HOME/.config/quickshell/solstice}"
ASSUME_YES=0
NO_START="${SOLSTICE_NO_START:-0}"

usage() {
    cat <<EOF
solstice installer

Usage: install.sh [options]

Options:
  -y, --yes          Don't prompt (non-interactive)
      --no-start     Install only; do not start the shell
  -h, --help         Show this help

Environment:
  SOLSTICE_REPO          Git remote to install from (default: $REPO)
  SOLSTICE_REF           Branch/tag to install (default: $REF)
  SOLSTICE_DEST          Install directory (default: $DEST)
  SOLSTICE_NO_START=1    Same as --no-start
EOF
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--unattended) ASSUME_YES=1 ;;
        --no-start) NO_START=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Read prompts from the terminal even when the script arrives on stdin (curl | bash).
if ! { exec 3</dev/tty; } 2>/dev/null; then
    if [[ -t 0 ]]; then
        exec 3<&0
    else
        exec 3</dev/null
    fi
fi

confirm() {
    ((ASSUME_YES)) && return 0
    local reply
    printf '%s [y/N] ' "$1"
    read -r reply <&3 || reply=""
    case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

if ! command -v git >/dev/null 2>&1; then
    echo "git is required but was not found. Install git and retry." >&2
    exit 1
fi

if ! command -v quickshell >/dev/null 2>&1 && ! command -v qs >/dev/null 2>&1; then
    echo "Warning: quickshell was not found in PATH — install it before starting the shell." >&2
fi

# Prefer a local checkout when this script sits next to shell.qml.
SRC="${SOLSTICE_SRC:-}"
if [[ -z "$SRC" ]]; then
    SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" >/dev/null 2>&1 && pwd || true)"
    if [[ -n "$SELF_DIR" && -f "$SELF_DIR/shell.qml" ]]; then
        SRC="$SELF_DIR"
    fi
fi

if [[ -n "$SRC" && -f "$SRC/shell.qml" ]]; then
    echo "Installing from local checkout: $SRC"
else
    SRC=""
    echo "Cloning $REPO ($REF) ..."
    SRC="$(mktemp -d "${TMPDIR:-/tmp}/solstice-install.XXXXXX")"
    SRC_TMP="$SRC"
    if ! timeout 300 git clone --depth 1 --branch "$REF" "$REPO" "$SRC"; then
        echo "git clone failed." >&2
        exit 1
    fi
    if [[ ! -f "$SRC/shell.qml" ]]; then
        echo "Clone looks invalid (shell.qml missing) — aborting." >&2
        exit 1
    fi
fi

if [[ -e "$DEST" ]]; then
    echo "solstice already exists at $DEST."
    if ! confirm "Reinstall/update it (keeping backend/config/ and style/themes/snapshots/)?"; then
        echo "Aborted." >&2
        exit 1
    fi
fi

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
TMP="$(mktemp -d "$PARENT/.solstice-install.XXXXXX")"
cleanup() {
    # STABILITY: an interrupt between the two swap renames leaves the previous
    # install in $TMP/old with $DEST missing. Restore it before removing the
    # staging dir — the old install is otherwise unrecoverable.
    if [[ -n "${TMP:-}" && -d "$TMP/old" && ! -e "$DEST" ]]; then
        mv "$TMP/old" "$DEST" 2>/dev/null || true
    fi
    [[ -n "${TMP:-}" ]] && rm -rf "$TMP"
    [[ -n "${SRC_TMP:-}" ]] && rm -rf "$SRC_TMP"
}
trap cleanup EXIT INT TERM

# Preserve user-owned state across (re)installs.
KEEP="$TMP/keep"
mkdir -p "$KEEP"
if [[ -d "$DEST/backend/config" ]]; then
    cp -a "$DEST/backend/config" "$KEEP/backend/config"
fi
if [[ -d "$DEST/style/themes/snapshots" ]]; then
    mkdir -p "$KEEP/style/themes"
    cp -a "$DEST/style/themes/snapshots" "$KEEP/style/themes/snapshots"
fi

# Ship new default configs without overwriting existing user settings.
if [[ -d "$SRC/backend/config" && -d "$KEEP/backend/config" ]]; then
    for f in "$SRC/backend/config/"*; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        if [[ ! -e "$KEEP/backend/config/$base" ]]; then
            echo "New default config: $base"
            cp -a "$f" "$KEEP/backend/config/$base"
        fi
    done
fi

# Copy the checkout into the staging area, then swap it in atomically.
cp -a "$SRC/." "$TMP/repo"
rm -rf "$TMP/repo/.git"

echo "Installing to $DEST ..."
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

# Expose the CLI as `solstice` in PATH. Hyprland's autostart ("solstice start")
# and every shell keybind ("solstice module …") go through this
# symlink. Refreshed on every install so a moved script can never leave it
# dangling. Skipped for test installs (SOLSTICE_DEST), which must not repoint
# the live CLI.
if [[ -z "${SOLSTICE_DEST:-}" ]]; then
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    ln -sf "$DEST/backend/scripts/solstice" "$BIN_DIR/solstice"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) echo "Note: $BIN_DIR is not in PATH — add it so 'solstice' works in keybinds." ;;
    esac
fi

# Launcher emoji picker needs a colour emoji font; user-level, best-effort.
if command -v fc-list >/dev/null 2>&1 && ! fc-list 2>/dev/null | grep -qi "Noto Color Emoji"; then
    echo "Installing Noto Color Emoji (user font) ..."
    bash "$DEST/backend/scripts/ensure-emoji-font.sh" || true
fi

# Workspace window glyphs need the variable symbol font; user-level, best-effort.
if command -v fc-list >/dev/null 2>&1 && ! fc-list 2>/dev/null | grep -qi "Material Symbols Rounded"; then
    echo "Installing Material Symbols Rounded (user font) ..."
    bash "$DEST/backend/scripts/ensure-symbol-font.sh" || true
fi

echo ""
echo "solstice installed to $DEST"
echo "For autostart, add this to ~/.config/hypr/configs/autostart.lua:"
echo '  hl.exec_cmd("solstice start")'

if ((NO_START)); then
    echo "Start it with:  solstice start   (or: qs -d -c solstice)"
elif [[ -n "${SOLSTICE_DEST:-}" ]]; then
    echo "Done. (Test install — shell not started.)"
elif command -v quickshell >/dev/null 2>&1; then
    if timeout 10 quickshell ipc -c solstice call solstice reload >/dev/null 2>&1 \
       || timeout 15 "$DEST/backend/scripts/solstice" start >/dev/null 2>&1; then
        echo "Shell started."
    else
        echo "Installed. Start it manually with:  solstice start"
    fi
else
    echo "Installed. Install quickshell, then run:  solstice start"
fi
