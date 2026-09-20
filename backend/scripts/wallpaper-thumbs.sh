#!/usr/bin/env bash
# wallpaper-thumbs.sh — thumbnail cache for the wallpaper pickers.
#
# Qt decodes the full-resolution image for every `sourceSize` (the JPEG/PNG
# handlers ignore scaled reads here), so a 10-20 MB wallpaper costs 150-450ms
# per tile. This script renders one small JPEG per wallpaper, mirroring the
# source tree under the cache dir, and prints "path<TAB>thumb" for every
# thumbnail that exists (or was just generated). WallpaperService streams
# those lines into its path -> thumb map; tiles then decode a ~30-80 KB JPEG
# (~5-20ms) instead of the original.
#
# Usage: wallpaper-thumbs.sh <wallpaper-dir> <cache-dir>
#
# Best-effort: silently does nothing when no image tool (ffmpeg/ImageMagick)
# is installed — the shell falls back to the original files unchanged.

set -u

DIR="${1:-}"
CACHE="${2:-}"
[ -n "$DIR" ] && [ -n "$CACHE" ] && [ -d "$DIR" ] || exit 0

TOOL=""
if command -v ffmpeg >/dev/null 2>&1; then
    TOOL="ffmpeg"
elif command -v magick >/dev/null 2>&1; then
    TOOL="magick"
elif command -v convert >/dev/null 2>&1; then
    TOOL="convert"
else
    exit 0
fi

mkdir -p "$CACHE" 2>/dev/null || exit 0

# Thumbnail long edge. 768px covers the settings preview (<=520 logical px)
# and every tile/carousel slot with headroom; the file stays small.
MAX_EDGE=768

gen_thumb() {
    local src="$1" out="$2"
    case "$TOOL" in
    ffmpeg)
        ffmpeg -nostdin -y -loglevel error -i "$src" \
            -vf "scale='min(${MAX_EDGE},iw)':-2" -frames:v 1 -q:v 5 \
            "$out" </dev/null >/dev/null 2>&1
        ;;
    magick|convert)
        "$TOOL" "${src}[0]" -resize "${MAX_EDGE}x${MAX_EDGE}>" -quality 82 \
            "$out" </dev/null >/dev/null 2>&1
        ;;
    esac
}

find "$DIR" -mindepth 1 -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
    -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tiff' \) -print0 2>/dev/null |
    sort -z |
    head -z -n 500 |
    while IFS= read -r -d '' src; do
        rel="${src#"$DIR"/}"
        # Tab/newline in a name would break the line protocol to QML.
        case "$rel" in
        *$'\t'* | *$'\n'*) continue ;;
        esac
        out="$CACHE/$rel.jpg"
        if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
            mkdir -p "$(dirname "$out")" 2>/dev/null || continue
            rm -f "$out" 2>/dev/null
            gen_thumb "$src" "$out"
            # Only announce what this run produced: already-cached thumbs are
            # resolved by the QML scan itself, so a warm cache prints nothing.
            [ -s "$out" ] && printf '%s\t%s\n' "$src" "$out"
        fi
    done
