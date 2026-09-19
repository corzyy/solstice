#!/usr/bin/env bash
# solstice installer.
#
# One-liner (fresh install):
#   curl -fsSL https://raw.githubusercontent.com/corzyy/solstice/main/install.sh | bash
#
# Or run from a checkout:  ./install.sh
#
# Installs the solstice quickshell to ${SOLSTICE_DEST:-$HOME/.config/quickshell/solstice},
# preserving any existing config/ and themes/snapshots/.
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
    cleanup_src() { [[ -n "$SRC" && "$SRC" == /tmp/* ]] && rm -rf "$SRC"; }
    trap cleanup_src EXIT INT TERM
    if ! git clone --depth 1 --branch "$REF" "$REPO" "$SRC"; then
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
    if ! confirm "Reinstall/update it (keeping config/ and themes/snapshots/)?"; then
        echo "Aborted." >&2
        exit 1
    fi
fi

PARENT="$(dirname "$DEST")"
mkdir -p "$PARENT"
TMP="$(mktemp -d "$PARENT/.solstice-install.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

# Preserve user-owned state across (re)installs.
KEEP="$TMP/keep"
mkdir -p "$KEEP"
if [[ -d "$DEST/config" ]]; then
    cp -a "$DEST/config" "$KEEP/config"
fi
if [[ -d "$DEST/themes/snapshots" ]]; then
    mkdir -p "$KEEP/themes"
    cp -a "$DEST/themes/snapshots" "$KEEP/themes/snapshots"
fi

# Ship new default configs without overwriting existing user settings.
if [[ -d "$SRC/config" && -d "$KEEP/config" ]]; then
    for f in "$SRC/config/"*; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        if [[ ! -e "$KEEP/config/$base" ]]; then
            echo "New default config: $base"
            cp -a "$f" "$KEEP/config/$base"
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

# Launcher emoji picker needs a colour emoji font; user-level, best-effort.
if command -v fc-list >/dev/null 2>&1 && ! fc-list 2>/dev/null | grep -qi "Noto Color Emoji"; then
    echo "Installing Noto Color Emoji (user font) ..."
    bash "$DEST/scripts/ensure-emoji-font.sh" || true
fi

echo ""
echo "solstice installed to $DEST"

if ((NO_START)); then
    echo "Start it with:  solstice start   (or: qs -d -c solstice)"
elif [[ -n "${SOLSTICE_DEST:-}" ]]; then
    echo "Done. (Test install — shell not started.)"
elif command -v quickshell >/dev/null 2>&1; then
    if quickshell ipc -c solstice call solstice reload >/dev/null 2>&1 \
       || "$DEST/scripts/solstice" start >/dev/null 2>&1; then
        echo "Shell started."
    else
        echo "Installed. Start it manually with:  solstice start"
    fi
else
    echo "Installed. Install quickshell, then run:  solstice start"
fi
