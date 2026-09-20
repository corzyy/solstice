pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../style/ui"

// WallpaperService — shared wallpaper backend for the Settings "Wallpaper &
// style" page. Owns the wallpaper settings file
// (backend/config/wallpaper_settings.json), the wallpaper directory scan, the
// display-only switch (swaybg + current pointers) and the recent-wallpapers
// ring used by the page's carousel. Theming stays with ThemeEngine: callers
// remember the wallpaper and kick monet after a successful display switch.
Singleton {
    id: root

    // ---- settings (backend/config/wallpaper_settings.json) ----
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/config/wallpaper_settings.json"
        watchChanges: true; onFileChanged: reload(); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property string transitionType: "grow"
            property real transitionDuration: 1.5
            property int transitionFps: 60
            property string mode: "fill"
            property string directory: ""
        }
    }
    function expandDir(p) {
        let s = ("" + (p || "")).trim()
        if (s === "~" || s.startsWith("~/")) {
            try { s = Quickshell.env("HOME") + s.slice(1) } catch (e) { }
        }
        return s
    }
    readonly property string directoryConfigured: {
        try { return expandDir(settingsFile.adapter.directory) } catch (e) { return "" }
    }
    function setDirectory(path) {
        let s = ("" + (path || "")).trim()
        if (s.includes("\n") || s.includes("\r")) return
        if (s !== "" && !(s.startsWith("/") || s.startsWith("~/") || s === "~")) return
        if (s.length > 1 && s.endsWith("/")) s = s.slice(0, -1)
        try {
            if ((settingsFile.adapter.directory || "") === s) return
            settingsFile.adapter.directory = s
            settingsFile.writeAdapter()
        } catch (e) { }
        refresh()
    }
    readonly property var modes: ["stretch", "fit", "fill", "center", "tile"]
    readonly property string mode: {
        try { let v = settingsFile.adapter.mode; return modes.indexOf(v) !== -1 ? v : "fill" } catch (e) { return "fill" }
    }
    function setMode(m) {
        if (modes.indexOf(m) === -1) return
        settingsFile.adapter.mode = m
        settingsFile.writeAdapter()
    }
    readonly property var transTypes: ["none", "simple", "fade", "left", "right", "top", "bottom", "wipe", "grow", "center", "outer", "wave", "random"]
    readonly property var transFpsOptions: [30, 48, 60, 72, 120]
    readonly property string transType: {
        try { let v = settingsFile.adapter.transitionType; return transTypes.indexOf(v) !== -1 ? v : "grow" } catch (e) { return "grow" }
    }
    readonly property real transDuration: {
        try { let v = settingsFile.adapter.transitionDuration; if (v === undefined || isNaN(v)) return 1.5; return Math.round(Math.max(0.2, Math.min(3.0, v)) * 10) / 10 } catch (e) { return 1.5 }
    }
    readonly property int transFps: {
        try { let v = settingsFile.adapter.transitionFps; return transFpsOptions.indexOf(v) !== -1 ? v : 60 } catch (e) { return 60 }
    }

    // ---- directory scan ----
    property var files: []
    property string resolvedDir: ""
    readonly property string dirDisplay: {
        let d = resolvedDir !== "" ? resolvedDir : directoryConfigured
        if (d === "") d = "~/Bilder/wallpapers"
        try {
            let h = Quickshell.env("HOME")
            if (h && d.startsWith(h)) d = "~" + d.slice(h.length)
        } catch (e) { }
        return d
    }
    Process {
        id: listProc
        command: ["bash", "-c", "echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (text || "").trim()
                if (out.length === 0) {
                    if (!root.sameFileList(root.files, [])) root.files = []
                    root.resolvedDir = ""
                    return
                }
                let lines = out.split("\n")
                if (lines.length > 0 && lines[0].startsWith("#DIR=")) {
                    root.resolvedDir = lines[0].slice(5).trim()
                    lines = lines.slice(1)
                }
                // Lines carry "path" or "path<TAB>cached thumb" (see refresh):
                // the scan resolves existing thumbnails in the same pass, so
                // the very first open already paints from the small cache
                // files instead of decoding full-resolution originals.
                let files = []
                let thumbs = {}
                for (let i = 0; i < lines.length; i++) {
                    let l = lines[i]
                    if (l.length === 0) continue
                    let tab = l.indexOf("\t")
                    if (tab > 0) {
                        let p = l.substring(0, tab)
                        files.push(p)
                        let t = l.substring(tab + 1)
                        if (t.length > 0) thumbs[p] = t
                    } else {
                        files.push(l)
                    }
                }
                // A rescan usually returns the exact same list (the carousel
                // refreshes on every open). Reassigning `files` would hand the
                // pickers a new model identity and rebuild every tile/image
                // mid-animation, so only publish an actual change.
                if (!root.sameFileList(root.files, files)) root.files = files
                root._thumbMap = thumbs
                root.thumbsRev++
                root.maybeGenerateThumbs()
            }
        }
    }
    function sameFileList(a, b): bool {
        if (!a || !b || a.length !== b.length) return false
        for (let i = 0; i < a.length; i++)
            if (a[i] !== b[i]) return false
        return true
    }
    function refresh(): void {
        if (listProc.running) return
        let cmd = "CFG=\"" + Util.shellEscapeDq(directoryConfigured) + "\"; D=\"\";"
        cmd += " if [ -n \"$CFG\" ]; then D=\"$CFG\";"
        cmd += " else for c in \"$HOME/Bilder/wallpapers\" \"$HOME/Pictures/wallpapers\" \"$HOME/Wallpapers\" \"${XDG_PICTURES_DIR:-$HOME/Pictures}/wallpapers\" \"$HOME/wallpapers\"; do if [ -d \"$c\" ]; then D=\"$c\"; break; fi; done; fi;"
        cmd += " CACHE=\"" + Util.shellEscapeDq(thumbCacheDir) + "\";"
        cmd += " echo \"#DIR=$D\";"
        // Existing thumbnails are emitted as "path<TAB>thumb" with builtin
        // tests only (no forks per file): the mirrored cache path is derived
        // from the path relative to the wallpaper root. Missing thumbs are
        // generated afterwards by backend/scripts/wallpaper-thumbs.sh, which streams
        // the same path<TAB>thumb lines as they appear.
        cmd += " if [ -n \"$D\" ] && [ -d \"$D\" ]; then"
        cmd += " find \"$D\" -mindepth 1 -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tiff' \\) 2>/dev/null"
        cmd += " | sort | head -n 500"
        cmd += " | while IFS= read -r f; do rel=\"${f#\"$D\"/}\"; out=\"$CACHE/$rel.jpg\";"
        cmd += " if [ -f \"$out\" ]; then printf '%s\\t%s\\n' \"$f\" \"$out\"; else printf '%s\\n' \"$f\"; fi; done;"
        cmd += " fi"
        listProc.command = ["bash", "-c", cmd]
        listProc.running = true
    }

    // ---- thumbnail cache (backend/scripts/wallpaper-thumbs.sh) ----
    // Qt Quick decodes the FULL-resolution image for every `sourceSize` (the
    // JPEG/PNG handlers ignore scaled reads here): measured 130-460ms for
    // this library's large wallpapers, which is exactly the settings/carousel
    // load delay. A background pass caches one ~40KB JPEG per wallpaper
    // (measured ~2ms to decode) and streams "path<TAB>thumb" lines for every
    // thumbnail that exists; the pickers bind their images through
    // thumbFor()/imageUrl() and fall back to the original path unchanged when
    // no image tool (ffmpeg/ImageMagick) is installed.
    property var _thumbMap: ({})
    property int thumbsRev: 0
    property var _thumbBatch: null
    property bool _thumbFlushScheduled: false
    readonly property string thumbCacheDir: Quickshell.env("HOME") + "/.cache/solstice/wallpaper-thumbs"

    function noteThumb(line: string): void {
        try {
            let s = "" + line
            let tab = s.indexOf("\t")
            if (tab <= 0) return
            let p = s.substring(0, tab)
            let thumb = s.substring(tab + 1)
            if (thumb.length === 0) return
            // Cached thumbs normally arrive with the scan; only report a
            // change when a freshly generated thumbnail differs.
            if (_thumbMap[p] === thumb) return
            if (_thumbBatch === null) _thumbBatch = ({})
            _thumbBatch[p] = thumb
            if (_thumbFlushScheduled) return
            _thumbFlushScheduled = true
            // Batch streamed lines into one revision bump per event loop, so a
            // cold cache (hundreds of lines) does not re-evaluate every
            // image binding per line.
            Qt.callLater(() => {
                _thumbFlushScheduled = false
                if (_thumbBatch === null) return
                let next = {}
                for (let k in _thumbMap) next[k] = _thumbMap[k]
                for (let k2 in _thumbBatch) next[k2] = _thumbBatch[k2]
                _thumbBatch = null
                _thumbMap = next
                thumbsRev++
            })
        } catch (e) { }
    }
    Process {
        id: thumbsProc
        command: ["bash", "-c", "true"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.noteThumb(data)
        }
    }
    function maybeGenerateThumbs(): void {
        let dir = resolvedDir !== "" ? resolvedDir : directoryConfigured
        if (dir === "" || files.length === 0) return
        if (thumbsProc.running) return
        thumbsProc.command = ["bash", Quickshell.shellDir + "/backend/scripts/wallpaper-thumbs.sh", dir, thumbCacheDir]
        thumbsProc.running = true
    }
    function thumbFor(path: string): string {
        root.thumbsRev
        let p = "" + (path || "")
        let t = root._thumbMap[p]
        return (t && t.length > 0) ? t : p
    }
    function imageUrl(path: string): string {
        return Util.fileUrl(root.thumbFor(path))
    }
    // Original-file URL for the Image error fallback: if a cached thumbnail
    // was deleted out from under the running shell (cache wiped, partial
    // generation), the tile must still show the wallpaper.
    function originalUrl(path: string): string {
        return Util.fileUrl("" + (path || ""))
    }

    // ---- current wallpaper ----
    FileView {
        id: currentFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/config/current_wallpaper.txt"
        watchChanges: true; onFileChanged: reload(); blockLoading: true; printErrors: false
    }
    readonly property string current: {
        try { return ("" + currentFile.text()).trim() } catch (e) { return "" }
    }

    // ---- recent wallpapers (carousel) ----
    FileView {
        id: recentFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/config/recent_wallpapers.json"
        blockLoading: true; printErrors: false
        adapter: JsonAdapter { property var wallpapers: [] }
    }
    readonly property int recentLimit: 12
    readonly property var recents: {
        // Adapter arrays arrive as QVariantList: normalize to plain strings so
        // Array.isArray-style usage and JSON.stringify behave in QML.
        try {
            let a = recentFile.adapter.wallpapers
            if (!a || a.length === undefined) return []
            let out = []
            for (let i = 0; i < a.length; i++) out.push("" + a[i])
            return out
        } catch (e) { return [] }
    }
    function pushRecent(path: string): void {
        if (!path || path.length === 0) return
        if (path.includes("\n") || path.includes("\r")) return
        let arr = []
        let cur = recents
        for (let i = 0; i < cur.length; i++) {
            let p = "" + cur[i]
            if (p.length > 0 && p !== path) arr.push(p)
        }
        arr.unshift(path)
        if (arr.length > recentLimit) arr = arr.slice(0, recentLimit)
        try {
            recentFile.adapter.wallpapers = arr
            recentFile.writeAdapter()
        } catch (e) { }
    }
    function clearRecents(): void {
        try {
            recentFile.adapter.wallpapers = []
            recentFile.writeAdapter()
        } catch (e) { }
    }

    // ---- theme folders ----
    function normThemeName(s: string): string {
        try { return ("" + (s || "")).toLowerCase().replace(/[^a-z0-9]/g, "") } catch (e) { return "" }
    }
    // Theme folder of a wallpaper path: first path segment below the wallpaper
    // root, else the parent directory name.
    function themeFolderFor(p: string): string {
        try {
            let s = "" + p
            let r = resolvedDir
            if (r !== "" && s.startsWith(r + "/")) {
                let rest = s.slice(r.length + 1)
                let slash = rest.indexOf("/")
                if (slash === -1) return ""
                return rest.slice(0, slash)
            }
            let parts = s.split("/")
            if (parts.length >= 3) return parts[parts.length - 2]
            return ""
        } catch (e) { return "" }
    }
    // Monet folder aliases: "monet" is the current name, "nonthemed" the
    // legacy one; a folder named like the engine id ("wallpaper") counts too.
    readonly property var monetFolders: ["monet", "nonthemed", "wallpaper"]
    function isMonetFolder(norm: string): bool { return monetFolders.indexOf(norm) !== -1 }
    // First wallpaper belonging to a theme, same folder rules as the menu:
    // root files count for every theme, monet folders only for wallpaper/monet.
    function firstForTheme(id: string): string {
        try {
            let eng = normThemeName(id)
            for (let i = 0; i < files.length; i++) {
                let p = files[i]
                let folder = themeFolderFor(p)
                if (folder === "") return p
                let n = normThemeName(folder)
                if (n === "") continue
                if (isMonetFolder(n) && eng !== "wallpaper") continue
                if (eng === "wallpaper" || n === eng) return p
            }
        } catch (e) { }
        return ""
    }

    // ---- display-only switch (never triggers theming) ----
    // swaybg (re)start helper shared by the commit path and the launcher's
    // live preview: start-then-reap so a broken image never kills the working
    // wallpaper. Path travels as argv ($1): spaces/quotes/$/` in filenames
    // are safe.
    function spawnSwaybg(path: string): void {
        let cmd = "WALL=\"$1\"; MODE=\"$2\";"
        cmd += "if command -v swaybg >/dev/null 2>&1 && [ -f \"$WALL\" ]; then nohup swaybg -i \"$WALL\" -m \"$MODE\" >/dev/null 2>&1 < /dev/null & NEW=$!; sleep 0.5;"
        cmd += " if kill -0 \"$NEW\" 2>/dev/null; then for p in $(pgrep -x swaybg 2>/dev/null); do [ \"$p\" = \"$NEW\" ] || kill \"$p\" 2>/dev/null || true; done;"
        cmd += " else echo \"[solstice] swaybg start failed, keeping current wallpaper\" >&2; fi; "
        cmd += "else echo \"[solstice] swaybg missing or wallpaper invalid — wallpaper unchanged\" >&2; fi; "
        Quickshell.execDetached(["bash", "-c", cmd, "solstice-wallpaper", path, mode])
    }
    // Commit: display + current-file pointers + recents ring.
    function setWallpaperDisplay(path: string): bool {
        if (!path || path.length === 0) return false
        if (path.includes("\n") || path.includes("\r")) return false
        spawnSwaybg(path)
        previewPath = ""
        let cmd = "WALL=\"$1\"; mkdir -p ~/.cache/swaybg ~/.cache/awww ~/.config/quickshell/solstice/backend/config 2>/dev/null; printf '%s' \"$WALL\" > ~/.cache/swaybg/current 2>/dev/null; printf '%s' \"$WALL\" > ~/.cache/awww/current 2>/dev/null; printf '%s' \"$WALL\" > ~/.config/quickshell/solstice/backend/config/current_wallpaper.txt 2>/dev/null"
        Quickshell.execDetached(["bash", "-c", cmd, "solstice-wallpaper-state", path])
        pushRecent(path)
        return true
    }

    // ---- live preview (launcher wallpaper picker) ----
    // Displays a wallpaper without committing anything: no current-file
    // writes and no recents, so browsing the carousel can be reverted with
    // endWallpaperPreview(). Previewing the committed wallpaper is a no-op;
    // committing through setWallpaperDisplay() clears a pending preview.
    property string previewPath: ""
    function previewWallpaper(path: string): void {
        if (!path || path.length === 0) return
        if (path.includes("\n") || path.includes("\r")) return
        if (path === current) {
            endWallpaperPreview()
            return
        }
        if (path === previewPath) return
        previewPath = path
        spawnSwaybg(path)
    }
    function endWallpaperPreview(): void {
        if (previewPath === "") return
        previewPath = ""
        if (current !== "") spawnSwaybg(current)
    }
}
