#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LAUNCHER="$SCRIPT_DIR/webapp-launch.sh"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="$DESKTOP_DIR/icons"

desk_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

slugify() {
    local s="$1"
    s="$(tr '[:upper:]' '[:lower:]' <<<"$s" | sed -E 's/[^a-z0-9._-]+/_/g; s/_+/_/g; s/^_+//; s/_+$//')"
    [[ -z "$s" ]] && s="webapp"
    printf '%s' "${s:0:64}"
}

download() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 20 -o "$dest" "$url" 2>/dev/null && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O "$dest" "$url" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$url" "$dest" 2>/dev/null <<'EOF' && return 0
import sys, urllib.request
try:
    req = urllib.request.Request(sys.argv[1], headers={"User-Agent": "jhqs-webapp/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r, open(sys.argv[2], "wb") as f:
        f.write(r.read(2 * 1024 * 1024))
except Exception:
    sys.exit(1)
EOF
    fi
    return 1
}

is_image() {
    local f="$1"
    [[ -s "$f" ]] || return 1
    if command -v file >/dev/null 2>&1; then
        local mime
        mime="$(file -b --mime-type "$f" 2>/dev/null || true)"
        [[ "$mime" == image/* ]] && return 0
        [[ "$mime" == application/octet-stream ]] && return 0
        return 1
    fi
    return 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,16p' "$0"
    exit 0
fi

if [[ "${1:-}" == "--repair" ]]; then
    [[ -x "$LAUNCHER" ]] || LAUNCHER="$HOME/.config/quickshell/jhqs/scripts/webapp-launch.sh"
    repaired=0
    if [[ -d "$DESKTOP_DIR" ]]; then
        while IFS= read -r -d '' f; do
            exec_line="$(grep -m1 -E '^Exec=' "$f" 2>/dev/null | cut -d= -f2- || true)"
            [[ "$exec_line" == *"webapp-launch.sh"* ]] && continue
            [[ "$exec_line" == *launch-webapp* || "$exec_line" == *webapp-handler* ]] || continue
            app_url="$(grep -o -E 'https?://[^ "]*' <<<"$exec_line" | tail -n1 || true)"
            [[ -z "$app_url" ]] && app_url="$(grep -o -E -- '--app=[^ "]*' <<<"$exec_line" | tail -n1 | sed 's/^--app=//' || true)"
            [[ -n "$app_url" ]] || continue
            tmp="$(mktemp "${TMPDIR:-/tmp}/jhqs-repair.XXXXXX")" || continue
            sed -E "s|^Exec=.*|Exec=\"$(desk_escape "$LAUNCHER")\" \"$(desk_escape "$app_url")\"|" "$f" >"$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
            chmod +x "$tmp" 2>/dev/null || true
            mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; continue; }
            echo "Repaired: $(basename "$f" .desktop)"
            repaired=$((repaired + 1))
        done < <(find "$DESKTOP_DIR" -maxdepth 3 -name '*.desktop' -print0 2>/dev/null)
    fi
    echo "Repair done ($repaired launcher(s) fixed)."
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi
    exit 0
fi

APP_NAME="${1:-}"
APP_URL="${2:-}"
ICON_REF="${3:-}"

APP_NAME="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$APP_NAME")"
APP_URL="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$APP_URL")"
ICON_REF="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$ICON_REF")"

if [[ -z "$APP_NAME" || -z "$APP_URL" ]]; then
    echo "Error: app name and URL are required." >&2
    echo "Usage: $(basename "$0") <name> <url> [iconRef]" >&2
    exit 1
fi
if [[ "$APP_NAME" == *"/"* ]]; then
    echo "Error: name must not contain '/'." >&2
    exit 1
fi
if [[ "$APP_NAME" == "." || "$APP_NAME" == ".." ]]; then
    echo "Error: invalid name." >&2
    exit 1
fi
if [[ ${#APP_NAME} -gt 64 ]]; then
    echo "Error: name too long (max 64 chars)." >&2
    exit 1
fi
if [[ "$APP_NAME" == *$'\n'* || "$APP_NAME" == *$'\r'* || "$APP_NAME" == *$'\t'* ]]; then
    echo "Error: name must not contain control characters." >&2
    exit 1
fi

if [[ ! "$APP_URL" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]]; then
    APP_URL="https://$APP_URL"
fi
if [[ ! "$APP_URL" =~ ^https?:// ]]; then
    echo "Error: only http(s) URLs are supported (got '${APP_URL%%:*}:')." >&2
    exit 1
fi

if [[ ! -x "$LAUNCHER" ]]; then
    echo "Error: launcher missing: $LAUNCHER" >&2
    exit 2
fi

mkdir -p "$DESKTOP_DIR" "$ICON_DIR" 2>/dev/null || {
    echo "Error: cannot create $DESKTOP_DIR" >&2
    exit 2
}

ICON_VALUE="web-browser"
slug="$(slugify "$APP_NAME")"

resolve_icon() {
    local ref="$1" tmp ext target
    if [[ -z "$ref" ]]; then
        ref="https://www.google.com/s2/favicons?domain=${APP_URL}&sz=128"
        echo "Fetching site icon…"
    fi
    if [[ "$ref" =~ ^https?:// ]]; then
        tmp="$(mktemp "${TMPDIR:-/tmp}/jhqs-icon.XXXXXX")" || return 1
        if download "$ref" "$tmp" && is_image "$tmp"; then
            ext="png"
            case "$ref" in
                *.jpg|*.jpeg|*format=jpg*|*format=jpeg*) ext="jpg" ;;
                *.svg*) ext="svg" ;;
                *.ico*) ext="ico" ;;
            esac
            if [[ "$ext" == "png" ]] && command -v file >/dev/null 2>&1; then
                case "$(file -b --mime-type "$tmp" 2>/dev/null)" in
                    image/jpeg) ext="jpg" ;;
                    image/svg+xml) ext="svg" ;;
                    image/x-icon|image/vnd.microsoft.icon) ext="ico" ;;
                esac
            fi
            target="$ICON_DIR/$slug.$ext"
            if mv -f "$tmp" "$target" 2>/dev/null; then
                chmod 644 "$target" 2>/dev/null || true
                echo "Icon saved."
                ICON_VALUE="$target"
                return 0
            fi
        fi
        rm -f "$tmp" 2>/dev/null || true
        echo "Note: icon download failed — using generic icon."
        return 1
    fi
    local expanded="$ref"
    if [[ "$expanded" == "~" || "$expanded" == "~/"* ]]; then
        expanded="$HOME${expanded:1}"
    fi
    if [[ -f "$expanded" ]]; then
        if is_image "$expanded"; then
            ext="${expanded##*.}"
            case "$ext" in
                png|jpg|jpeg|svg|ico|webp) ;;
                *) ext="png" ;;
            esac
            target="$ICON_DIR/$slug.$ext"
            if cp -f "$expanded" "$target" 2>/dev/null; then
                chmod 644 "$target" 2>/dev/null || true
                echo "Icon saved."
                ICON_VALUE="$target"
                return 0
            fi
        fi
        echo "Note: '$ref' is not a readable image — using generic icon."
        return 1
    fi
    if [[ "$ref" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Using system icon '$ref'."
        ICON_VALUE="$ref"
        return 0
    fi
    echo "Note: ignoring unrecognized icon reference — using generic icon."
    return 1
}

resolve_icon "$ICON_REF" || true

DESKTOP_FILE="$DESKTOP_DIR/$APP_NAME.desktop"
EXEC_LINE="\"$(desk_escape "$LAUNCHER")\" \"$(desk_escape "$APP_URL")\""
tmp_desktop="$(mktemp "${TMPDIR:-/tmp}/jhqs-desktop.XXXXXX")" || {
    echo "Error: cannot create temp file." >&2
    exit 2
}

{
    echo "[Desktop Entry]"
    echo "Version=1.0"
    echo "Type=Application"
    echo "Name=$APP_NAME"
    echo "Comment=$APP_NAME ($APP_URL)"
    echo "Exec=$EXEC_LINE"
    echo "Icon=$ICON_VALUE"
    echo "Terminal=false"
    echo "StartupNotify=true"
    echo "Categories=Network;WebBrowser;"
    echo "X-jhqs-WebApp=true"
    echo "X-jhqs-WebApp-URL=$APP_URL"
} >"$tmp_desktop" || {
    echo "Error: cannot write desktop entry." >&2
    rm -f "$tmp_desktop"
    exit 2
}

chmod +x "$tmp_desktop" 2>/dev/null || true
mv -f "$tmp_desktop" "$DESKTOP_FILE" 2>/dev/null || {
    echo "Error: cannot install to $DESKTOP_FILE" >&2
    rm -f "$tmp_desktop"
    exit 2
}
chmod +x "$DESKTOP_FILE" 2>/dev/null || true

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "Created $APP_NAME ($DESKTOP_FILE)"
exit 0
