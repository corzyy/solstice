#!/bin/bash
set -u

TARGETS=()
UNATTENDED=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        system|flatpak|all) TARGETS+=("$arg") ;;
        -y|--yes|--unattended) UNATTENDED=1 ;;
        -h|--help)
            echo "Usage: update.sh [system|flatpak|all]... [-y|--yes|--unattended]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: update.sh [system|flatpak|all]... [-y|--yes|--unattended]" >&2
            exit 2
            ;;
    esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=("all")
fi

KEEPALIVE_PID=""

stop_keepalive() {
    if [[ -n $KEEPALIVE_PID ]]; then
        kill "$KEEPALIVE_PID" 2>/dev/null || true
        KEEPALIVE_PID=""
    fi
}
trap stop_keepalive EXIT INT TERM

ensure_sudo() {
    [[ -n $KEEPALIVE_PID ]] && return 0
    if ! sudo -v; then
        echo "Elevation cancelled — nothing was changed." >&2
        exit 1
    fi
    while true; do sudo -n true 2>/dev/null || true; sleep 50; done &
    KEEPALIVE_PID=$!
}

update_system() {
    echo "Update system packages (DNF)"
    echo ""
    sudo dnf upgrade -y
}

update_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "flatpak not installed — skipping Flatpak updates."
        return 0
    fi
    echo "Update Flatpak apps and runtimes"
    echo ""
    flatpak update -y --noninteractive
}

prune_orphans() {
    if ! command -v dnf >/dev/null 2>&1; then
        return 0
    fi
    echo "Autoremove unneeded packages (DNF)"
    echo ""
    ensure_sudo
    sudo dnf autoremove -y
}

pending_sources() {
    bash "$SCRIPT_DIR/check-updates.sh" --sources
}

for target in "${TARGETS[@]}"; do
    case "$target" in
        system)
            ensure_sudo
            update_system
            echo ""
            prune_orphans
            echo ""
            ;;
        flatpak)
            update_flatpak
            echo ""
            ;;
        all)
            mapfile -t sources < <(pending_sources)
            if [[ ${#sources[@]} -eq 0 ]]; then
                echo "Nothing scanned to update — everything is up to date."
                echo ""
                continue
            fi
            for source in "${sources[@]}"; do
                case "$source" in
                    system)
                        ensure_sudo
                        update_system
                        echo ""
                        ;;
                    flatpak)
                        update_flatpak
                        echo ""
                        ;;
                esac
            done
            prune_orphans
            echo ""
            ;;
    esac
done

echo "Done."
