#!/bin/bash
set -uo pipefail

usage() {
    echo "Usage: $(basename "$0") <url> [extra-browser-args...]" >&2
}

url="${1:-}"
if [[ -z "$url" || "$url" == "-h" || "$url" == "--help" ]]; then
    usage
    exit 2
fi
shift || true
if [[ ! "$url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]]; then
    url="https://$url"
fi
scheme="${url%%:*}"
if [[ "$scheme" != "http" && "$scheme" != "https" ]]; then
    exec xdg-open "$url" >/dev/null 2>&1 || exit 3
fi

exec_of_desktop() {
    local id="$1" d f line bin
    for d in "$HOME/.local/share/applications" "$HOME/.nix-profile/share/applications" \
             "/usr/local/share/applications" "/usr/share/applications" \
             "/var/lib/flatpak/exports/share/applications"; do
        f="$d/$id"
        [[ -f "$f" ]] || continue
        line="$(grep -m1 -E '^Exec=' "$f" 2>/dev/null | cut -d= -f2- || true)"
        [[ -n "$line" ]] || continue
        line="$(sed -E 's/%[a-zA-Z]//g' <<<"$line")"
        bin="$(awk '{print $1}' <<<"$line")"
        bin="${bin%\"}"; bin="${bin#\"}"
        bin="${bin%\'}"; bin="${bin#\'}"
        if [[ -n "$bin" ]]; then
            if [[ "$bin" == */* ]]; then
                [[ -x "$bin" ]] && { echo "$bin"; return 0; }
            else
                command -v "$bin" >/dev/null 2>&1 && { command -v "$bin"; return 0; }
            fi
        fi
    done
    return 1
}

supports_app_mode() {
    case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
        *chrom*|*brave*|*edge*|*opera*|*vivaldi*|*helium*|*chrome*) return 0 ;;
    esac
    return 1
}

pick_browser() {
    local def bin
    if command -v xdg-settings >/dev/null 2>&1; then
        def="$(xdg-settings get default-web-browser 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ -n "$def" ]]; then
            if bin="$(exec_of_desktop "$def" 2>/dev/null)"; then
                if supports_app_mode "$bin"; then
                    echo "$bin"
                    return 0
                fi
                NON_CHROMIUM_DEFAULT="$bin"
            fi
        fi
    fi
    local c
    for c in chromium chromium-browser google-chrome google-chrome-stable \
             brave brave-browser brave-bin microsoft-edge microsoft-edge-stable \
             opera opera-browser vivaldi vivaldi-stable helium chrome chrome-browser; do
        if bin="$(command -v "$c" 2>/dev/null)"; then
            echo "$bin"
            return 0
        fi
    done
    if command -v flatpak >/dev/null 2>&1; then
        local app
        for app in org.chromium.Chromium com.google.Chrome com.brave.Browser \
                   com.microsoft.Edge com.opera.Opera org.vivaldi.Vivaldi; do
            if flatpak info "$app" >/dev/null 2>&1; then
                echo "flatpak run $app"
                return 0
            fi
        done
    fi
    if [[ -n "${NON_CHROMIUM_DEFAULT:-}" ]]; then
        echo "$NON_CHROMIUM_DEFAULT"
        return 0
    fi
    return 1
}

NON_CHROMIUM_DEFAULT=""
browser="$(pick_browser || true)"

if [[ -z "$browser" ]]; then
    exec xdg-open "$url" >/dev/null 2>&1 || {
        echo "webapp-launch: no browser found for $url" >&2
        exit 3
    }
fi

if [[ "$browser" == "flatpak run "* ]]; then
    if supports_app_mode "$browser"; then
        exec setsid $browser --app="$url" "$@" >/dev/null 2>&1
    else
        exec setsid $browser "$url" "$@" >/dev/null 2>&1
    fi
elif supports_app_mode "$browser"; then
    if command -v uwsm-app >/dev/null 2>&1; then
        exec setsid uwsm-app -- "$browser" --app="$url" "$@" >/dev/null 2>&1
    else
        exec setsid "$browser" --app="$url" "$@" >/dev/null 2>&1
    fi
else
    if command -v uwsm-app >/dev/null 2>&1; then
        exec setsid uwsm-app -- "$browser" "$url" "$@" >/dev/null 2>&1
    else
        exec setsid "$browser" "$url" "$@" >/dev/null 2>&1
    fi
fi
