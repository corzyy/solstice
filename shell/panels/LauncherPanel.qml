pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import M3Shapes
import "../../style/themes"
import "../../style/ui"
import "../../backend/services"
import "./emoji_data.js" as EmojiData
import "settings" as SettingsEngine

// App launcher popup. One panel, two anchor modes:
//   - bar icon click: centered=false — hangs under the OS icon (left edge)
//   - SUPER + SPACE:  centered=true  — centred under the bar
// The visual shell is the shared Caelestia popout (curtain reveal from the
// bar edge, cross-panel morph via morphId "launcher"). Content is the app
// list with the search field at the bottom (no navigation hints).
Scope {
    id: launcherScope

    property bool showLauncher: false
    // Anchor mode of the current open (set by the shell before showing).
    property bool centered: false
    signal dismissed()
    // Action entries (the prefix menus) autocomplete into their picker prefix
    // instead of running; the field text lives in the item component, so it
    // is requested from here.
    signal autocompleteRequested(string text)
    // Built-in settings entries (see builtinEntries): the settings app is a
    // shell surface, not a launched process, so activation is handed to the
    // shell which opens the settings window on the requested section.
    signal settingsRequested(string section)

    property bool _winVisible: showLauncher
    Timer {
        id: launcherHideTimer
        interval: Theme.panelHideDelay
        repeat: false
        onTriggered: if (!launcherScope.showLauncher) launcherScope._winVisible = false
    }
    onShowLauncherChanged: {
        if (showLauncher) {
            _winVisible = true
            launcherHideTimer.stop()
            // Re-rolled every open so the badge never shows the previous
            // shape twice, even after the panel item was destroyed between
            // opens (the item tree is unloaded once closed).
            pickBadgeShape()
            resetState()
        } else {
            launcherHideTimer.restart()
            // Dismissing the wallpaper carousel without committing restores
            // the last committed wallpaper.
            WallpaperService.endWallpaperPreview()
        }
    }
    Component.onDestruction: WallpaperService.endWallpaperPreview()

    readonly property string barPos: Theme.barPosition
    // Attached-bar morph: tuck under the bar edge (see Theme.panelAttachOverlap).
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)
    readonly property int panelWidth: Theme.launcherWidth
    readonly property int panelHeight: Theme.launcherHeight

    property string filterText: ""
    property int selectedIndex: 0

    // ---- wallpaper picker (Caelestia launcher port) ----------------------
    // Picking the Wallpaper entry from the prefix menu autocompletes to
    // "<prefix>wallpaper " (Caelestia's ">wallpaper " action) and opens the
    // carousel; "<prefix>wallpaper " typed directly enters it too. There the
    // search bar hides and the card is owned by the cover-flow view:
    // left/right (and up/down, wheel) steer, Enter/click commits, Esc
    // dismisses. Highlighting
    // previews the wallpaper live (plus Monet when the wallpaper engine is
    // active on commit, same contract as Settings > Wallpaper & style).
    // Caelestia also previews the generated colour scheme while browsing —
    // our matugen pipeline re-themes every app, so colours apply on commit
    // only.
    // Menu prefix from Settings > Panels > Launcher (default "!").
    readonly property string menuPrefix: Theme.launcherMenuPrefix
    readonly property string wallpaperCommand: launcherScope.menuPrefix + "wallpaper"
    readonly property string wallpaperPrefix: launcherScope.wallpaperCommand + " "
    // Leading whitespace is ignored, the trailing space must survive: the
    // autocomplete fills in "<prefix>wallpaper " (and trimming would strip
    // exactly that space, keeping the picker closed). The bare prefix also
    // enters, so typing "<prefix>wallpaper" lands in the carousel directly.
    readonly property bool wallpaperMode: {
        const t = launcherScope.filterText.replace(/^\s+/, "")
        return t === launcherScope.wallpaperCommand || t.startsWith(launcherScope.wallpaperPrefix)
    }
    readonly property string wallpaperQuery: {
        const t = launcherScope.filterText.replace(/^\s+/, "")
        if (!t.startsWith(launcherScope.wallpaperPrefix)) return ""
        return t.substring(launcherScope.wallpaperPrefix.length).trim().toLowerCase()
    }
    readonly property int wallpaperItemWidth: 264
    // Carousel card height: thumbnail (135) + label + margins with a little
    // breathing room for the ring and hover ripple. Caelestia uses a shorter
    // launcher height for wallpapers than for the app list.
    readonly property int wallpaperPanelHeight: 220
    // Folder rules mirror WallpaperService.firstForTheme: root-level files
    // count for every engine, the monet folders ("monet", legacy
    // "nonthemed") belong to the wallpaper engine and every other folder
    // belongs to its preset theme. So monet colours only list the monet
    // wallpapers, while a preset engine lists that preset's folder (plus
    // root files).
    function wallpaperMatchesEngine(path: string): bool {
        let folder = ""
        try { folder = WallpaperService.themeFolderFor(path) } catch (e) { }
        if (folder === "") return true
        let n = ""
        try { n = WallpaperService.normThemeName(folder) } catch (e) { }
        if (n === "") return true
        let eng = "wallpaper"
        try { eng = wallpaperThemeEngine.currentEngine } catch (e) { }
        if (eng === "wallpaper") return WallpaperService.isMonetFolder(n)
        return n === WallpaperService.normThemeName(eng)
    }
    readonly property var wallpaperResults: {
        // Keep the list while the page is still on screen: leaving the mode
        // must not blank the outgoing page mid-slide (pageVisible stays true
        // for the whole exit run).
        if (!launcherScope.wallpaperMode && !launcherScope.pageVisible(launcherScope.pageWallpaper)) return []
        const q = launcherScope.wallpaperQuery
        const src = WallpaperService.files
        let out = []
        for (let i = 0; i < src.length; i++) {
            let p = "" + src[i]
            if (p.length === 0) continue
            if (!launcherScope.wallpaperMatchesEngine(p)) continue
            let name = launcherScope.wallpaperName(p)
            if (q.length === 0 || name.toLowerCase().indexOf(q) !== -1) out.push({ path: p, name: name })
        }
        return out
    }
    function wallpaperName(path: string): string {
        let p = "" + (path || "")
        let dir = ""
        try { dir = WallpaperService.resolvedDir } catch (e) { }
        if (dir !== "" && p.startsWith(dir + "/")) {
            p = p.slice(dir.length + 1)
        } else {
            let slash = p.lastIndexOf("/")
            if (slash >= 0) p = p.slice(slash + 1)
        }
        return p
    }
    onWallpaperModeChanged: {
        if (wallpaperMode) WallpaperService.refresh()
        else WallpaperService.endWallpaperPreview()
    }

    // Theming: the launcher only applies wallpapers, so the settings page's
    // boot re-sync stays off (see ThemeEngine.autoResync).
    SettingsEngine.ThemeEngine {
        id: wallpaperThemeEngine
        autoResync: false
    }
    function applyWallpaper(path: string): void {
        if (!path || path.length === 0) return
        if (!WallpaperService.setWallpaperDisplay(path)) return
        wallpaperThemeEngine.rememberWallpaper(wallpaperThemeEngine.currentEngine, path)
        if (wallpaperThemeEngine.currentEngine === "wallpaper") wallpaperThemeEngine.applyMonetFromPath(path)
        launcherScope.dismissed()
    }

    // ---- web app manager (prefix menu page) ------------------------------
    // Picking the Web App entry autocompletes to "<prefix>webapp " and opens
    // the manager; typing it directly lands there too. Add is a form that
    // writes a Chromium --app .desktop entry (backend/scripts/webapp-install.sh,
    // favicon fetched when no icon is given), Remove lists the installed web
    // apps (webapp-list.sh) and deletes them (webapp-remove.sh). The search
    // bar is hidden in the page; the page UI lives in WebAppPage.qml.
    readonly property string webAppCommand: launcherScope.menuPrefix + "webapp"
    readonly property string webAppPrefix: launcherScope.webAppCommand + " "
    readonly property bool webAppMode: {
        const t = launcherScope.filterText.replace(/^\s+/, "")
        return t === launcherScope.webAppCommand || t.startsWith(launcherScope.webAppPrefix)
    }
    property string webAppPageMode: "add"
    property var webAppList: []
    property bool webAppLoading: false
    property bool webAppBusy: false
    property bool webAppSuccess: false
    property string webAppStatus: ""
    property string webAppLog: ""
    property string webAppLastName: ""
    property bool webAppOpRemove: false
    property bool webAppListRetried: false
    onWebAppModeChanged: {
        if (launcherScope.webAppMode) launcherScope.refreshWebApps()
        else launcherScope.clearWebAppStatus()
    }
    function setWebAppPageMode(mode: string): void {
        const m = mode === "remove" ? "remove" : "add"
        if (launcherScope.webAppPageMode === m) return
        launcherScope.webAppPageMode = m
        launcherScope.clearWebAppStatus()
        // Remove doubles as the migration entry point: --repair rewrites
        // legacy Exec= lines to the local launcher before listing.
        if (launcherScope.webAppMode && m === "remove") launcherScope.repairWebApps()
    }
    // Empty unless the page shows the remove list: keeps the list model
    // stable while the add form owns the card.
    readonly property var filteredWebApps: {
        // Keep the list while the page is still on screen (see
        // wallpaperResults): the remove list must survive its exit slide.
        if ((!launcherScope.webAppMode && !launcherScope.pageVisible(launcherScope.pageWebApp))
                || launcherScope.webAppPageMode !== "remove") return []
        return launcherScope.webAppList
    }

    readonly property string webAppScriptsDir: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/scripts"
    function webAppBin(kind: string): string {
        if (kind === "remove") return launcherScope.webAppScriptsDir + "/webapp-remove.sh"
        if (kind === "list") return launcherScope.webAppScriptsDir + "/webapp-list.sh"
        return launcherScope.webAppScriptsDir + "/webapp-install.sh"
    }
    function refreshWebApps(): void {
        if (webAppListProc.running) return
        launcherScope.webAppLoading = true
        webAppListProc.command = [launcherScope.webAppBin("list")]
        webAppListProc.running = true
    }
    function repairWebApps(): void {
        if (webAppRepairProc.running || webAppListProc.running) { launcherScope.refreshWebApps(); return }
        launcherScope.webAppLoading = true
        webAppRepairProc.command = [launcherScope.webAppBin("install"), "--repair"]
        webAppRepairProc.running = true
    }
    function clearWebAppStatus(): void {
        launcherScope.webAppStatus = ""
        launcherScope.webAppLog = ""
        launcherScope.webAppSuccess = false
    }
    // Shared log sanitizing (ANSI/CR/control chars + 60 line cap) for the
    // streamed install/remove output.
    function sanitizeOpLines(text: string): var {
        const parts = ("" + (text || "")).split("\n")
        const lines = []
        for (let i = 0; i < parts.length; i++) {
            let s = parts[i]
            if (s.charAt(s.length - 1) === "\r") s = s.slice(0, -1)
            const ci = s.lastIndexOf("\r")
            if (ci !== -1) s = s.slice(ci + 1)
            s = s.replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
                .replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "")
                .replace(/\x1b[()][0-9A-B]/g, "")
                .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
                .replace(/\s+$/, "")
            if (s.length === 0) continue
            lines.push(s)
        }
        return lines
    }
    function webAppOpAppend(line): void {
        const lines = launcherScope.sanitizeOpLines(line)
        if (lines.length === 0) return
        const cur = launcherScope.webAppLog.length > 0 ? launcherScope.webAppLog.split("\n") : []
        const next = cur.concat(lines)
        launcherScope.webAppLog = (next.length > 60 ? next.slice(next.length - 60) : next).join("\n")
    }
    function installWebApp(name, url, iconRef): bool {
        let n = ("" + (name || "")).trim()
        let u = ("" + (url || "")).trim()
        const icon = ("" + (iconRef || "")).trim()
        if (launcherScope.webAppBusy) return false
        if (n.length === 0) { launcherScope.webAppStatus = "Name missing"; launcherScope.webAppSuccess = false; return false }
        if (n.indexOf("/") !== -1) { launcherScope.webAppStatus = "Name must not contain '/'"; launcherScope.webAppSuccess = false; return false }
        if (u.length === 0) { launcherScope.webAppStatus = "URL missing"; launcherScope.webAppSuccess = false; return false }
        if (!/^[a-zA-Z][a-zA-Z0-9+.\-]*:/.test(u)) u = "https://" + u
        launcherScope.webAppBusy = true
        launcherScope.webAppSuccess = false
        launcherScope.webAppStatus = "Installing '" + n + "'…"
        launcherScope.webAppLog = ""
        launcherScope.webAppLastName = n
        launcherScope.webAppOpRemove = false
        launcherScope.webAppOpAppend("Installing '" + n + "' (" + u + ")…")
        webAppOpProc.command = [launcherScope.webAppBin("install"), n, u, icon]
        if (!webAppOpProc.running) webAppOpProc.running = true
        return true
    }
    function removeWebApp(name): bool {
        const n = ("" + (name || "")).trim()
        if (launcherScope.webAppBusy) return false
        if (n.length === 0) { launcherScope.webAppStatus = "No selection"; launcherScope.webAppSuccess = false; return false }
        launcherScope.webAppBusy = true
        launcherScope.webAppSuccess = false
        launcherScope.webAppStatus = "Removing '" + n + "'…"
        launcherScope.webAppLastName = n
        launcherScope.webAppOpRemove = true
        launcherScope.webAppOpAppend("Removing '" + n + "'…")
        webAppOpProc.command = [launcherScope.webAppBin("remove"), n]
        if (!webAppOpProc.running) webAppOpProc.running = true
        return true
    }
    function finishWebAppOp(code): void {
        launcherScope.webAppBusy = false
        launcherScope.webAppSuccess = (code === 0)
        if (code === 0) {
            launcherScope.webAppOpAppend("✓ Done (code 0)")
            launcherScope.webAppStatus = launcherScope.webAppOpRemove
                ? "✓ Removed" : "✓ Installed — find it in the app launcher"
            if (!launcherScope.webAppOpRemove) {
                const name = launcherScope.webAppLastName !== "" ? launcherScope.webAppLastName : "The web app"
                webAppNotifyProc.command = ["notify-send", "Web App installed", name + " is in the app launcher"]
                if (!webAppNotifyProc.running) webAppNotifyProc.running = true
            }
        } else if (code === 127) {
            launcherScope.webAppOpAppend("✗ Install script not found (code 127)")
            launcherScope.webAppStatus = "✗ Script missing: check backend/scripts/webapp-install.sh"
        } else {
            launcherScope.webAppOpAppend("✗ Failed (code " + code + ")")
            if (launcherScope.webAppStatus === "" || launcherScope.webAppStatus.endsWith("…"))
                launcherScope.webAppStatus = "✗ Failed (code " + code + ")"
        }
        launcherScope.refreshWebApps()
        try { Theme.notifyAppsChanged() } catch (e) { }
    }
    Process {
        id: webAppListProc
        command: ["bash", "-c", "echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                launcherScope.webAppLoading = false
                const out = (text || "").trim()
                if (out.length === 0) { launcherScope.webAppList = []; return }
                const lines = out.split("\n")
                const arr = []
                for (let i = 0; i < lines.length; i++) {
                    const ln = lines[i]
                    if (ln.trim().length === 0) continue
                    const cols = ln.split("\t")
                    if (cols.length < 2) continue
                    const fname = (cols[0] || "").trim()
                    const file = (cols[1] || "").trim()
                    const dname = (cols[2] || "").trim()
                    const exec = (cols[3] || "").trim()
                    const icon = (cols[4] || "").trim()
                    if (fname.length === 0) continue
                    let url = ""
                    let m = exec.match(/launch-webapp\s+(\S+)/)
                    if (m) url = m[1]
                    else {
                        const q = exec.match(/webapp-launch\.sh"\s+"([^"]+)/)
                        if (q) url = q[1]
                        else {
                            const a = exec.match(/--app=("[^"]+"|\S+)/)
                            if (a) url = ("" + a[1]).replace(/^"|"$/g, "")
                            else {
                                const h = exec.match(/https?:\/\/[^\s"']+/)
                                if (h) url = h[0]
                            }
                        }
                    }
                    arr.push({ name: fname, displayName: dname !== "" ? dname : fname, file: file, exec: exec, icon: icon, url: url })
                }
                arr.sort((a, b) => ("" + a.name).toLowerCase() < ("" + b.name).toLowerCase() ? -1 : 1)
                launcherScope.webAppList = arr
            }
        }
        onExited: code => {
            if (code === 127 && !launcherScope.webAppListRetried) {
                launcherScope.webAppListRetried = true
                launcherScope.webAppLoading = true
                webAppListProc.command = ["bash", "-c", "DESKTOP_DIR=\"$HOME/.local/share/applications\"; find \"$DESKTOP_DIR\" -maxdepth 3 -name '*.desktop' -print0 2>/dev/null | while IFS= read -r -d '' f; do if grep -q -E '^Exec=.*(launch-webapp|webapp-handler|webapp-launch|solstice-webapp|--app=)' \"$f\" 2>/dev/null; then base=$(basename \"$f\" .desktop); dname=$(grep -m1 '^Name=' \"$f\" 2>/dev/null | cut -d= -f2-); exec=$(grep -m1 '^Exec=' \"$f\" 2>/dev/null | cut -d= -f2-); icon=$(grep -m1 '^Icon=' \"$f\" 2>/dev/null | cut -d= -f2-); printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$base\" \"$f\" \"$dname\" \"$exec\" \"$icon\"; fi; done"]
                if (!webAppListProc.running) webAppListProc.running = true
            } else {
                launcherScope.webAppListRetried = false
            }
        }
    }
    Process {
        id: webAppRepairProc
        command: ["bash", "-c", "echo"]
        onExited: () => launcherScope.refreshWebApps()
    }
    Process {
        id: webAppOpProc
        command: ["bash", "-c", "echo"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => launcherScope.webAppOpAppend(data)
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => launcherScope.webAppOpAppend(data)
        }
        onExited: code => launcherScope.finishWebAppOp(code)
    }
    Process { id: webAppNotifyProc; command: ["notify-send", "Web App", ""] }

    // ---- emoji picker (prefix menu page) ---------------------------------
    // Picking the Emoji entry autocompletes to "<prefix>emoji " and opens the
    // grid; typing it directly lands there too. The search bar stays visible:
    // the text after the prefix filters label + keywords (AND per word),
    // category chips switch between recents and the Unicode groups. Picking
    // an emoji copies it (wl-copy), bumps the persisted recents and dismisses.
    // The grid UI lives in EmojiPage.qml, the data in shell/panels/emoji_data.js.
    readonly property string emojiCommand: launcherScope.menuPrefix + "emoji"
    readonly property string emojiPrefix: launcherScope.emojiCommand + " "
    readonly property bool emojiMode: {
        const t = launcherScope.filterText.replace(/^\s+/, "")
        return t === launcherScope.emojiCommand || t.startsWith(launcherScope.emojiPrefix)
    }
    readonly property string emojiQuery: {
        const t = launcherScope.filterText.replace(/^\s+/, "")
        if (!t.startsWith(launcherScope.emojiPrefix)) return ""
        return t.substring(launcherScope.emojiPrefix.length).trim().toLowerCase()
    }
    // Index into EmojiPage.categories: 0 = recent, 1+n = EmojiData.groups[n].
    property int emojiCategory: 0
    readonly property var emojiEntries: {
        const src = EmojiData.emojis
        const out = []
        for (let i = 0; i < src.length; i++) {
            const e = src[i]
            out.push({
                char: "" + e[0],
                name: "" + e[1],
                group: e[3],
                search: (e[1] + " " + e[2] + " " + e[0]).toLowerCase()
            })
        }
        return out
    }
    readonly property var emojiByChar: {
        const all = launcherScope.emojiEntries
        const map = ({})
        for (let i = 0; i < all.length; i++) map[all[i].char] = all[i]
        return map
    }
    FileView {
        id: emojiRecentFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/config/emoji_recent.json"
        blockLoading: true; printErrors: false
        adapter: JsonAdapter { property var recent: [] }
    }
    readonly property var emojiRecent: {
        const raw = emojiRecentFile.adapter.recent
        const out = []
        if (raw && typeof raw.length === "number") {
            for (let i = 0; i < raw.length && out.length < 32; i++) {
                const s = "" + raw[i]
                if (s.length > 0 && out.indexOf(s) === -1) out.push(s)
            }
        }
        return out
    }
    readonly property var emojiResults: {
        const all = launcherScope.emojiEntries
        const q = launcherScope.emojiQuery
        let out = []
        if (q.length > 0) {
            // Every query word must match; label hits rank above tag hits,
            // ties keep the dataset order (group + Unicode order).
            const words = q.split(/\s+/).filter(w => w.length > 0)
            const hits = []
            for (let i = 0; i < all.length; i++) {
                const e = all[i]
                let ok = true
                for (let w = 0; w < words.length; w++) {
                    if (e.search.indexOf(words[w]) === -1) { ok = false; break }
                }
                if (!ok) continue
                let rank = 3
                const name = e.name.toLowerCase()
                if (name.startsWith(q)) rank = 0
                else if (name.indexOf(q) !== -1) rank = 1
                else if (e.search.indexOf(q) !== -1) rank = 2
                hits.push({ rank: rank, i: i, e: e })
            }
            hits.sort((a, b) => a.rank !== b.rank ? a.rank - b.rank : a.i - b.i)
            for (let i = 0; i < hits.length; i++) out.push(hits[i].e)
            return out
        }
        if (launcherScope.emojiCategory === 0) {
            const rec = launcherScope.emojiRecent
            const map = launcherScope.emojiByChar
            for (let i = 0; i < rec.length; i++) {
                const e = map[rec[i]]
                if (e) out.push(e)
            }
            return out
        }
        const g = launcherScope.emojiCategory - 1
        for (let i = 0; i < all.length; i++) {
            if (all[i].group === g) out.push(all[i])
        }
        return out
    }
    // First open without recents starts on Smileys instead of an empty grid.
    onEmojiModeChanged: {
        if (launcherScope.emojiMode)
            launcherScope.emojiCategory = launcherScope.emojiRecent.length > 0 ? 0 : 1
    }
    function setEmojiCategory(i: int): void {
        if (i === launcherScope.emojiCategory) return
        launcherScope.emojiCategory = i
    }
    function recordEmojiUse(char: string): void {
        if (char.length === 0) return
        let list = launcherScope.emojiRecent.slice()
        const idx = list.indexOf(char)
        if (idx !== -1) list.splice(idx, 1)
        list.unshift(char)
        if (list.length > 32) list = list.slice(0, 32)
        emojiRecentFile.adapter.recent = list
        emojiRecentFile.writeAdapter()
    }
    function copyEmoji(char: string): void {
        if (!char || char.length === 0) return
        Quickshell.execDetached(["wl-copy", char])
        launcherScope.recordEmojiUse(char)
        launcherScope.dismissed()
    }

    // ---- app model -------------------------------------------------------
    // Rebuilt on Theme.appsRev (desktop entries added/removed); sorted by
    // display name, hidden/no-display and helper entries dropped.
    readonly property var allApps: {
        Theme.appsRev
        Theme.hiddenAppsRev
        let out = []
        try {
            let model = DesktopEntries.applications
            if (!model) return out
            let vals = model.values
            if (typeof vals === "function") vals = vals()
            if (!vals) return out
            let seen = ({})
            for (let i = 0; i < vals.length; i++) {
                let e = vals[i]
                if (!e || e.noDisplay === true) continue
                let id = String(e.id || "")
                if (id.startsWith("avahi-") || id.indexOf("blueman") !== -1) continue
                if (Theme.isAppHidden(id)) continue
                if (id.length > 0) {
                    if (seen[id] === true) continue
                    seen[id] = true
                }
                out.push(e)
            }
            out.sort((a, b) => {
                let an = String(a.name || a.id || "").toLowerCase()
                let bn = String(b.name || b.id || "").toLowerCase()
                return an.localeCompare(bn)
            })
        } catch (e) { console.log("[Launcher] desktop entries error", e) }
        return out
    }
    // Empty query lists the first maxResults apps; otherwise every query
    // word must match the app name (AND).
    readonly property var filteredApps: {
        let q = launcherScope.filterText.trim().toLowerCase()
        let max = Theme.launcherMaxResults
        let src = launcherScope.allApps
        let out = []
        if (q.length === 0) {
            for (let i = 0; i < src.length && out.length < max; i++) out.push(src[i])
            return out
        }
        let words = q.split(/\s+/).filter(w => w.length > 0)
        for (let i = 0; i < src.length && out.length < max; i++) {
            let e = src[i]
            let hay = String(e.name || "").toLowerCase()
            let ok = true
            for (let w = 0; w < words.length; w++) {
                if (hay.indexOf(words[w]) === -1) { ok = false; break }
            }
            if (ok) out.push(e)
        }
        return out
    }
    // ---- built-in settings entries ---------------------------------------
    // The settings app is part of the shell (a FloatingWindow) and has no
    // .desktop entry, so it never shows in DesktopEntries.applications.
    // These pseudo entries carry the same {name, comment, icon} shape the app
    // delegate renders: a generic "Settings" row opens the window as a whole,
    // one row per settings page (SettingsRegistry) opens that section.
    // `settingsSection` marks them for activateCurrent; the shell maps the
    // settingsRequested signal to openSettings().
    readonly property var builtinEntries: {
        const out = [{
            id: "solstice-settings",
            name: "Settings",
            comment: "Solstice settings app",
            icon: "\udb81\udc93",
            keywords: "settings preferences configuration control panel solstice shell",
            settingsSection: ""
        }]
        const pages = SettingsRegistry.entries
        for (let i = 0; i < pages.length; i++) {
            const page = pages[i]
            out.push({
                id: "solstice-settings-" + page.id,
                name: page.title,
                comment: "Settings · " + page.desc,
                icon: page.icon,
                keywords: "settings " + page.keywords,
                settingsSection: page.id
            })
        }
        return out
    }
    // Empty query keeps the plain app list (the settings entries are search
    // only); otherwise every query word must match name/comment/keywords.
    // Matches split in two: a name hit for the query (`settings`, `network`)
    // ranks above the apps, a keyword-only hit (`wifi` -> Network) below
    // them, so short queries don't bury the app results behind the page list.
    readonly property var builtinMatches: {
        const q = launcherScope.filterText.trim().toLowerCase().replace(/\s+/g, " ")
        if (q.length === 0) return { named: [], keyword: [] }
        const words = q.split(" ").filter(w => w.length > 0)
        const src = launcherScope.builtinEntries
        const hits = []
        for (let i = 0; i < src.length; i++) {
            const e = src[i]
            const name = e.name.toLowerCase()
            const hay = (name + " " + e.comment + " " + e.keywords).toLowerCase()
            let ok = true
            for (let w = 0; w < words.length; w++) {
                if (hay.indexOf(words[w]) === -1) { ok = false; break }
            }
            if (!ok) continue
            let rank = 3
            if (name.startsWith(q)) rank = 0
            // Substring/name-word hits only count from two characters on:
            // a single letter otherwise ranks almost the whole page registry
            // above the app results.
            else if (q.length > 1 && name.indexOf(q) !== -1) rank = 1
            else if (q.length > 1) {
                let allInName = true
                for (let w = 0; w < words.length; w++) {
                    if (name.indexOf(words[w]) === -1) { allInName = false; break }
                }
                if (allInName) rank = 2
            }
            hits.push({ rank: rank, i: i, e: e })
        }
        hits.sort((a, b) => a.rank !== b.rank ? a.rank - b.rank : a.i - b.i)
        const named = []
        const keyword = []
        for (let i = 0; i < hits.length; i++)
            (hits[i].rank < 3 ? named : keyword).push(hits[i].e)
        return { named: named, keyword: keyword }
    }
    // ---- prefix menus ----------------------------------------------------
    // The configured prefix as the first character switches the result list
    // from apps to the extra menus; the text after it filters them
    // (`!wall` -> Wallpaper).
    // Entries are placeholders for now: picking one only dismisses the
    // launcher until the individual views land.
    readonly property bool menuMode: {
        const p = launcherScope.menuPrefix
        return p.length > 0 && launcherScope.filterText.trim().startsWith(p)
    }
    readonly property string menuQuery: {
        const t = launcherScope.filterText.trim()
        if (!launcherScope.menuMode) return ""
        return t.substring(launcherScope.menuPrefix.length).trim().toLowerCase()
    }
    readonly property var menuEntries: [
        { id: "wallpaper", name: "Wallpaper", comment: "Browse and set a wallpaper", icon: "\udb83\ude09", autocomplete: launcherScope.menuPrefix + "wallpaper " },
        { id: "webapp", name: "Web App", comment: "Install or remove web apps", icon: "\udb81\udd9f", autocomplete: launcherScope.menuPrefix + "webapp " },
        { id: "calculator", name: "Calculator", comment: "Quick maths in the launcher", icon: "\udb80\udcec" },
        { id: "clipboard", name: "Clipboard", comment: "Clipboard history", icon: "\udb80\udd4d" },
        { id: "emoji", name: "Emoji", comment: "Emoji picker", icon: "\udb83\udc68", autocomplete: launcherScope.menuPrefix + "emoji " }
    ]
    readonly property var filteredMenus: {
        let words = launcherScope.menuQuery.split(/\s+/).filter(w => w.length > 0)
        let src = launcherScope.menuEntries
        let out = []
        for (let i = 0; i < src.length; i++) {
            let m = src[i]
            let hay = (m.name + " " + m.comment + " " + m.id).toLowerCase()
            let ok = true
            for (let w = 0; w < words.length; w++) {
                if (hay.indexOf(words[w]) === -1) { ok = false; break }
            }
            if (ok) out.push(m)
        }
        return out
    }
    // Active list the ListView renders. Built-in settings matches sit around
    // the apps (name hits above, keyword-only hits below) so a matching
    // settings page is always reachable without hiding app results.
    readonly property var results: {
        if (launcherScope.menuMode) return launcherScope.filteredMenus
        const b = launcherScope.builtinMatches
        return b.named.concat(launcherScope.filteredApps).concat(b.keyword)
    }
    onResultsChanged: launcherScope.selectedIndex = launcherScope.results.length > 0 ? 0 : -1

    function moveSelection(delta: int): void {
        let n = launcherScope.results.length
        if (n === 0) return
        let i = launcherScope.selectedIndex
        if (i < 0 || i >= n) i = 0
        else i = (i + delta + n) % n
        launcherScope.selectedIndex = i
    }
    function activeEntry(): var {
        let list = launcherScope.results
        let i = launcherScope.selectedIndex
        return (i >= 0 && i < list.length) ? list[i] : null
    }
    function activateCurrent(): void {
        let e = launcherScope.activeEntry()
        if (!e) return
        // Built-in settings entries: hand the section to the shell (empty =
        // the settings window's last section) and dismiss.
        if (typeof e.settingsSection === "string") {
            launcherScope.settingsRequested(e.settingsSection)
            launcherScope.dismissed()
            return
        }
        // Action entries (Wallpaper, …) autocomplete into their picker
        // prefix instead of running; placeholders without any action dismiss.
        if (typeof e.autocomplete === "string" && e.autocomplete.length > 0) {
            launcherScope.autocompleteRequested(e.autocomplete)
            return
        }
        try { if (typeof e.execute === "function") e.execute() } catch (err) { console.log("[Launcher] execute failed", err) }
        launcherScope.dismissed()
    }
    function resetState(): void {
        launcherScope.filterText = ""
        launcherScope.selectedIndex = launcherScope.results.length > 0 ? 0 : -1
        launcherScope.snapPageSlide()
    }

    // ---- prefix page cycling (TAB) ---------------------------------------
    // TAB walks apps -> wallpaper -> emoji -> apps by autocompleting the
    // page prefix into the search field; the plain app list is the state
    // before the first page. The web app page is deliberately not part of
    // the cycle (it stays reachable by typing its prefix): TAB from it
    // steps to its page-order neighbours. Page-local TAB uses (web app
    // form fields, emoji category chips) are overridden: TAB is reserved
    // for page cycling.
    readonly property var pageOrder: ["wallpaper", "emoji"]
    function pagePrefix(id: string): string {
        if (id === "wallpaper") return launcherScope.wallpaperPrefix
        if (id === "webapp") return launcherScope.webAppPrefix
        if (id === "emoji") return launcherScope.emojiPrefix
        return ""
    }
    // Position in pageOrder (wallpaper 0, emoji 1); -1 = app list (and the
    // web app page, which cyclePage handles separately).
    function pageIndex(): int {
        if (launcherScope.wallpaperMode) return 0
        if (launcherScope.emojiMode) return 1
        return -1
    }
    function cyclePage(dir: int): void {
        if (launcherScope.webAppMode) {
            // Skipped by the cycle: step to its page-order neighbours.
            launcherScope.autocompleteRequested(dir > 0 ? launcherScope.emojiPrefix : launcherScope.wallpaperPrefix)
            return
        }
        const n = launcherScope.pageOrder.length
        let i = launcherScope.pageIndex()
        i = i < 0 ? (dir > 0 ? 0 : n - 1) : i + dir
        if (i < 0 || i >= n) i = -1
        launcherScope.autocompleteRequested(i === -1 ? "" : launcherScope.pagePrefix(launcherScope.pageOrder[i]))
    }
    // Shared TAB/Shift+TAB entry point: also called by the web app form
    // fields so the page cycle wins over their KeyNavigation field hopping.
    function handlePageTab(event): bool {
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) return false
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) !== 0
        launcherScope.cyclePage(back ? -1 : 1)
        return true
    }

    // ---- page slide transition -------------------------------------------
    // Every page switch is one horizontal push, always in the same
    // direction: the incoming page enters from the left while the outgoing
    // page leaves to the right (left-to-right motion), whichever way TAB
    // walked. `pageOffset(slot)` is a page's x in card widths (-1 parked
    // left, 0 on screen, +1 parked right); a run interpolates the snapshot
    // taken at switch time to its targets, so an interrupted run hands its
    // mid-flight page over as the next outgoing instead of snapping, and
    // typing over a page (e.g. the web app page the cycle skips) is still
    // one push. The run shares the popout's size curve/duration, so the
    // slide and the card resize land together.
    readonly property int pageApps: 0
    readonly property int pageWallpaper: 1
    readonly property int pageWebApp: 2
    readonly property int pageEmoji: 3
    readonly property int pageCurrent: launcherScope.wallpaperMode ? launcherScope.pageWallpaper
        : launcherScope.webAppMode ? launcherScope.pageWebApp
        : launcherScope.emojiMode ? launcherScope.pageEmoji
        : launcherScope.pageApps
    // Incoming page of the run in progress (the visible page at rest).
    property int pageTo: 0
    // Offsets (card widths) each slot started the current run at.
    property var pageStart: ({})
    property real pageProgress: 1
    // Search bar is chrome of the app and emoji pages only; the wallpaper
    // carousel and the web app page own the whole card.
    readonly property bool barPage: launcherScope.pageCurrent === launcherScope.pageApps
        || launcherScope.pageCurrent === launcherScope.pageEmoji

    function pageOffset(slot: int): real {
        if (launcherScope.pageProgress >= 1)
            return slot === launcherScope.pageTo ? 0 : -1
        const s = launcherScope.pageStart[slot] !== undefined ? launcherScope.pageStart[slot] : -1
        // The incoming page settles at 0; anything still on the card keeps
        // moving right and exits at +1; parked pages stay parked left.
        const target = slot === launcherScope.pageTo ? 0 : (s > -0.999 ? 1 : -1)
        return s + (target - s) * launcherScope.pageProgress
    }
    function pageVisible(slot: int): bool {
        const o = launcherScope.pageOffset(slot)
        return o > -0.999 && o < 0.999
    }
    function pageX(slot: int, cardWidth: real): real {
        return launcherScope.pageOffset(slot) * cardWidth
    }
    function snapPageSlide(): void {
        pageSlideAnim.stop()
        launcherScope.pageStart = ({})
        launcherScope.pageProgress = 1
        launcherScope.pageTo = launcherScope.pageCurrent
    }
    onPageCurrentChanged: {
        // Every page switch re-rolls the search badge shape alongside the
        // slide, so the accent shape changes with the page (on top of the
        // per-open roll in onShowLauncherChanged).
        launcherScope.pickBadgeShape()
        const to = launcherScope.pageCurrent
        if (to === launcherScope.pageTo) return
        // Snapshot the current poses from the OLD run state (pageOffset
        // still reads pageTo): a page caught mid-entry becomes the next
        // outgoing from exactly where it is, a page still exiting keeps
        // going, parked pages stay parked. The incoming page starts parked
        // left unless it is already on screen (quick reversal), in which
        // case it glides back from where it is.
        const slots = [launcherScope.pageApps, launcherScope.pageWallpaper, launcherScope.pageWebApp, launcherScope.pageEmoji]
        const snap = ({})
        for (let i = 0; i < slots.length; i++)
            snap[slots[i]] = launcherScope.pageOffset(slots[i])
        if (snap[to] <= -0.999)
            snap[to] = -1
        launcherScope.pageStart = snap
        launcherScope.pageTo = to
        pageSlideAnim.stop()
        launcherScope.pageProgress = 0
        pageSlideAnim.restart()
    }
    NumberAnimation {
        id: pageSlideAnim
        target: launcherScope
        property: "pageProgress"
        from: 0
        to: 1
        duration: Theme.durDefaultSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curvePanelOpen
    }

    // Search-badge background shape: a random Material 3 expressive shape,
    // re-rolled on every open (never twice in a row). Same idea as the
    // workspaces focus shape (shell/bar/widgets/Workspaces.qml); M3Shapes morphs
    // between picks with the shared spatial token.
    readonly property var badgeShapes: [
        MaterialShape.Circle, MaterialShape.Square, MaterialShape.Slanted,
        MaterialShape.Arch, MaterialShape.Fan, MaterialShape.Arrow,
        MaterialShape.SemiCircle, MaterialShape.Oval, MaterialShape.Pill,
        MaterialShape.Triangle, MaterialShape.Diamond, MaterialShape.ClamShell,
        MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny,
        MaterialShape.VerySunny, MaterialShape.Cookie4Sided,
        MaterialShape.Cookie6Sided, MaterialShape.Cookie7Sided,
        MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided,
        MaterialShape.Ghostish, MaterialShape.Clover4Leaf,
        MaterialShape.Clover8Leaf, MaterialShape.Burst, MaterialShape.SoftBurst,
        MaterialShape.Boom, MaterialShape.SoftBoom, MaterialShape.Flower,
        MaterialShape.Puffy, MaterialShape.PuffyDiamond, MaterialShape.Bun,
        MaterialShape.Heart
    ]
    property int badgeShape: MaterialShape.Circle
    function pickBadgeShape(): void {
        const list = launcherScope.badgeShapes
        if (list.length === 0) return
        let next = list[Math.floor(Math.random() * list.length)]
        if (list.length > 1 && next === launcherScope.badgeShape)
            next = list[(list.indexOf(next) + 1) % list.length]
        launcherScope.badgeShape = next
    }
    Component.onCompleted: {
        resetState()
        pickBadgeShape()
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: launcherWindow
            required property var modelData
            screen: modelData
            visible: launcherScope._winVisible && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "launcher"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            // Wallpaper carousel width: as many 264px slots as fit the
            // screen, forced odd so the current wallpaper sits centred
            // (Caelestia's WallpaperList numItems, capped at maxWallpapers).
            readonly property int wallpaperVisible: {
                let n = Math.floor(Math.max(launcherScope.wallpaperItemWidth, width - 48) / launcherScope.wallpaperItemWidth)
                n = Math.max(1, Math.min(5, n))
                if (n > 1 && n % 2 === 0) n--
                return n
            }
            readonly property real wallpaperWidth: wallpaperVisible * launcherScope.wallpaperItemWidth + 24
            // Disabled while closing: during a morph handoff the outgoing
            // window stays mapped for panelHideDelay and must not eat the
            // click that belongs to the panel now on top.
            MouseArea {
                anchors.fill: parent
                enabled: launcherScope.showLauncher
                onClicked: launcherScope.dismissed()
            }

            CaelestiaPopout {
                id: launcherPopout
                shown: launcherScope.showLauncher
                morphId: "launcher"
                morphActive: Theme.isPrimaryScreen(modelData)
                barPos: launcherScope.barPos
                // The carousel widens and flattens the card while browsing
                // wallpapers; the popout glides between the two sizes.
                fullWidth: launcherScope.wallpaperMode ? launcherWindow.wallpaperWidth : launcherScope.panelWidth
                fullHeight: launcherScope.wallpaperMode ? launcherScope.wallpaperPanelHeight : launcherScope.panelHeight
                anchorCenter: launcherAnchor.isVertical ? launcherAnchor.cy : launcherAnchor.cx
                edge: launcherScope.barPos === "bottom" ? launcherAnchor.panelY + launcherPopout.fullHeight
                    : launcherScope.barPos === "right" ? launcherAnchor.panelX + launcherPopout.fullWidth
                    : launcherScope.barPos === "left" ? launcherAnchor.panelX
                    : launcherAnchor.panelY
                screenSize: launcherAnchor.isVertical ? launcherAnchor.screenHeight : launcherAnchor.screenWidth
                margin: launcherAnchor.margin

                BarAnchor {
                    id: launcherAnchor
                    // Empty id while centred: BarAnchor falls back to the
                    // screen middle. Icon clicks anchor to the bar module.
                    moduleId: launcherScope.centered ? "" : "launcher"
                    barPos: launcherScope.barPos
                    panelWidth: launcherPopout.fullWidth
                    panelHeight: launcherPopout.fullHeight
                    screenWidth: launcherPopout.parent.width
                    screenHeight: launcherPopout.parent.height
                    gap: launcherScope.panelGap
                    fallbackX: (launcherPopout.parent.width - launcherPopout.fullWidth) / 2
                    fallbackY: launcherPopout.parent.height - launcherPopout.fullHeight - launcherScope.panelGap
                }

                Rectangle {
                    id: launcherCard
                    width: parent.width
                    height: parent.height
                    antialiasing: Theme.shapesAa
                    // Fill comes from the popout's shadow layer (see
                    // CaelestiaPopout shadowSource).
                    color: "transparent"
                    border.color: Theme.panelBorderColor
                    border.width: 2
                    // Bar-side corners square, free corners rounded (fused joint).
                    topLeftRadius: launcherScope.barPos === "top" || launcherScope.barPos === "left" ? 0 : launcherPopout.frameRadius
                    topRightRadius: launcherScope.barPos === "top" || launcherScope.barPos === "right" ? 0 : launcherPopout.frameRadius
                    bottomLeftRadius: launcherScope.barPos === "bottom" || launcherScope.barPos === "left" ? 0 : launcherPopout.frameRadius
                    bottomRightRadius: launcherScope.barPos === "bottom" || launcherScope.barPos === "right" ? 0 : launcherPopout.frameRadius
                    clip: false
                    // Seam strip: erases the collar outline along the fused edge.
                    Rectangle {
                        antialiasing: Theme.shapesAa
                        visible: Theme.panelAccentBorder
                        x: 0
                        y: launcherScope.barPos === "bottom" ? launcherCard.height - 2 : 0
                        width: launcherCard.width
                        height: 2
                        color: Theme.panelWindowBg
                    }

                    Item {
                        id: contentRoot
                        // Content travels on the popout's own driver and
                        // follows the animated card size. contentFade hides
                        // it while the card morphs over to another panel's
                        // pose. Clipped at the card so the page strip's
                        // sliding pages never paint into the popout's shadow
                        // padding (see pageOffset).
                        opacity: launcherPopout.contentFade
                        x: launcherPopout.contentX
                        y: launcherPopout.contentY
                        width: launcherPopout.fullWidth
                        height: launcherPopout.fullHeight
                        clip: true
                        focus: true

                        Keys.onPressed: event => {
                            // TAB always cycles the prefix pages, ahead of any
                            // page-local key handling.
                            if (launcherScope.handlePageTab(event)) {
                                event.accepted = true
                                return
                            }
                            // The web app page owns Up/Down/Enter while open.
                            if (launcherScope.webAppMode && webAppPage.handleKey(event)) {
                                event.accepted = true
                                return
                            }
                            // While the search field is focused the emoji grid
                            // gets its keys from the field's handler; this
                            // path covers the result area holding focus.
                            if (launcherScope.emojiMode && emojiPage.handleKey(event)) {
                                event.accepted = true
                                return
                            }
                            const wp = launcherScope.wallpaperMode
                            if (event.key === Qt.Key_Escape) {
                                launcherScope.dismissed()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                if (wp) wallpaperView.incrementCurrentIndex()
                                else launcherScope.moveSelection(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                if (wp) wallpaperView.decrementCurrentIndex()
                                else launcherScope.moveSelection(-1)
                                event.accepted = true
                            } else if (wp && event.key === Qt.Key_Left) {
                                wallpaperView.decrementCurrentIndex()
                                event.accepted = true
                            } else if (wp && event.key === Qt.Key_Right) {
                                wallpaperView.incrementCurrentIndex()
                                event.accepted = true
                            } else if (wp && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                // Search bar is hidden in the carousel, so
                                // Enter commits from here (Caelestia accepts
                                // on the carousel itself).
                                let it = wallpaperView.currentItem
                                if (it && it.wpPath !== undefined && ("" + it.wpPath).length > 0)
                                    launcherScope.applyWallpaper("" + it.wpPath)
                                event.accepted = true
                            }
                        }
                        Component.onCompleted: if (launcherScope.showLauncher) searchInput.forceActiveFocus()
                        Connections {
                            target: launcherScope
                            function onShowLauncherChanged() {
                                if (launcherScope.showLauncher) {
                                    // Scope handler already re-rolled the badge
                                    // shape and reset filter/selection; this
                                    // only clears a held field's leftover text
                                    // and hands focus to the input.
                                    searchInput.text = ""
                                    searchInput.cursorPosition = 0
                                    Qt.callLater(() => searchInput.forceActiveFocus())
                                }
                            }
                            function onSelectedIndexChanged() {
                                if (launcherScope.selectedIndex >= 0)
                                    appList.positionViewAtIndex(launcherScope.selectedIndex, ListView.Contain)
                            }
                            function onAutocompleteRequested(text) {
                                searchInput.text = text
                                searchInput.cursorPosition = text.length
                                // The carousel hides the field; focus follows
                                // the view there so arrows/Enter reach the
                                // result area.
                                if (!launcherScope.wallpaperMode) searchInput.forceActiveFocus()
                            }
                            function onWallpaperModeChanged() {
                                if (launcherScope.wallpaperMode) contentRoot.forceActiveFocus()
                                else Qt.callLater(() => searchInput.forceActiveFocus())
                            }
                            function onWebAppModeChanged() {
                                if (launcherScope.webAppMode) {
                                    webAppPage.focusInitial()
                                    // Add moves focus into the form
                                    // (focusInitial); remove hands it to the
                                    // result area (arrows and Enter are
                                    // handled there).
                                    if (launcherScope.webAppPageMode === "remove")
                                        Qt.callLater(() => contentRoot.forceActiveFocus())
                                } else {
                                    Qt.callLater(() => searchInput.forceActiveFocus())
                                }
                            }
                            function onWebAppPageModeChanged() {
                                if (launcherScope.webAppMode && launcherScope.webAppPageMode === "remove")
                                    Qt.callLater(() => contentRoot.forceActiveFocus())
                            }
                        }

                        ListView {
                            id: appList
                            // Page strip slot 0: slides with the prefix pages
                            // (see pageOffset). Off-window pages are hidden,
                            // so the wallpaper/web app/emoji owners still win
                            // the result area.
                            visible: launcherScope.pageVisible(launcherScope.pageApps)
                            transform: Translate { x: launcherScope.pageX(launcherScope.pageApps, appList.width) }
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: searchBar.top
                            anchors.margins: 12
                            anchors.bottomMargin: 10
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            reuseItems: true
                            cacheBuffer: 400
                            model: launcherScope.results
                            currentIndex: launcherScope.selectedIndex
                            // Caelestia AppList motion: fade on add/remove.
                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
                            }
                            remove: Transition {
                                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
                            }
                            delegate: Rectangle {
                                id: appRow
                                required property var modelData
                                required property int index
                                readonly property var entry: appRow.modelData
                                readonly property bool isCurrent: appList.currentIndex === appRow.index
                                // Menu entries carry a Nerd Font glyph instead
                                // of a desktop icon (Util.isGlyphIcon: PUA).
                                readonly property string iconValue: appRow.entry ? String(appRow.entry.icon || "") : ""
                                readonly property bool glyphIcon: Util.isGlyphIcon(appRow.iconValue)
                                width: appList.width
                                height: 56
                                radius: 12
                                antialiasing: Theme.shapesAa
                                color: appRow.isCurrent
                                    ? Theme.withAlpha(Theme.textPrimary, 0.10)
                                    : rowMouse.containsMouse ? Theme.withAlpha(Theme.textPrimary, 0.06) : "transparent"
                                Behavior on color {
                                    enabled: Theme.animationsEnabled
                                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 14
                                    Item {
                                        Layout.preferredWidth: 34
                                        Layout.preferredHeight: 34
                                        Layout.alignment: Qt.AlignVCenter
                                        IconImage {
                                            anchors.centerIn: parent
                                            visible: !appRow.glyphIcon
                                            width: 30
                                            height: 30
                                            source: appRow.glyphIcon ? "" : Util.iconSource(appRow.iconValue, "")
                                            asynchronous: true
                                            implicitSize: Qt.size(60, 60)
                                            mipmap: Theme.imageMipmap
                                            smooth: Theme.imageSmooth
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: appRow.glyphIcon
                                            text: appRow.glyphIcon ? appRow.iconValue : ""
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: Theme.fs(20)
                                            color: appRow.isCurrent ? Theme.accent : Theme.textPrimary
                                            antialiasing: Theme.textAa
                                            renderType: Theme.textRenderType
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1
                                        Text {
                                            Layout.fillWidth: true
                                            text: (appRow.entry && (appRow.entry.name || appRow.entry.id)) || "—"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(14)
                                            font.weight: Font.Medium
                                            color: appRow.isCurrent ? Theme.accent : Theme.textPrimary
                                            elide: Text.ElideRight
                                            antialiasing: Theme.textAa
                                            renderType: Theme.textRenderType
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: Theme.launcherShowDescriptions && text.length > 0
                                            text: appRow.entry ? String(appRow.entry.comment || "") : ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(11)
                                            color: Theme.textMuted
                                            elide: Text.ElideRight
                                            antialiasing: Theme.textAa
                                            renderType: Theme.textRenderType
                                        }
                                    }
                                }
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        appList.currentIndex = appRow.index
                                        launcherScope.selectedIndex = appRow.index
                                        launcherScope.activateCurrent()
                                    }
                                }
                            }
                        }
                        ScrollIndicator {
                            flick: appList
                            show: launcherScope.pageVisible(launcherScope.pageApps)
                            transform: Translate { x: launcherScope.pageX(launcherScope.pageApps, appList.width) }
                        }

                        // ---- web app manager (prefix menu page) ----------
                        // Add writes a Chromium --app .desktop entry, Remove
                        // lists and deletes the installed ones. The search bar
                        // is hidden, so the page uses the whole card.
                        WebAppPage {
                            id: webAppPage
                            scope: launcherScope
                            anchors.fill: parent
                            anchors.margins: 12
                        }

                        // ---- emoji picker (prefix menu page) --------------
                        // Grid + category chips above the visible search bar.
                        EmojiPage {
                            id: emojiPage
                            scope: launcherScope
                            anchors.fill: appList
                        }

                        // Empty state.
                        Column {
                            anchors.centerIn: appList
                            visible: launcherScope.pageVisible(launcherScope.pageApps) && appList.count === 0
                            transform: Translate { x: launcherScope.pageX(launcherScope.pageApps, appList.width) }
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰀻"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(28)
                                color: Theme.textMuted
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: launcherScope.menuMode
                                    ? "No menus found"
                                    : launcherScope.filterText.length > 0 ? "No applications found" : "No applications"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(13)
                                color: Theme.textMuted
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }

                        // ---- wallpaper carousel (Caelestia WallpaperList) ---
                        // Cover-flow PathView over the scanned wallpapers: the
                        // current item is centred and scaled up, neighbours
                        // fall back/forward along the path. Highlighting
                        // previews the wallpaper live (WallpaperService
                        // preview, reverted when the view is left without a
                        // pick); Enter or a click commits it.
                        Item {
                            id: wallpaperStage
                            // Page strip slot 1: slides with the rest.
                            visible: launcherScope.pageVisible(launcherScope.pageWallpaper)
                            transform: Translate { x: launcherScope.pageX(launcherScope.pageWallpaper, wallpaperStage.width) }
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            // The search bar is hidden in the carousel, so
                            // the stage uses the whole card.
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            clip: true

                            PathView {
                                id: wallpaperView
                                anchors.fill: parent
                                clip: true
                                model: launcherScope.wallpaperResults
                                pathItemCount: launcherWindow.wallpaperVisible
                                cacheItemCount: 4
                                snapMode: PathView.SnapToItem
                                preferredHighlightBegin: 0.5
                                preferredHighlightEnd: 0.5
                                highlightRangeMode: PathView.StrictlyEnforceRange
                                // Auto repositions (entry, model/query changes)
                                // snap: the built-in highlight glide would play
                                // on top of the page slide as a second, slower
                                // horizontal run and read as the carousel
                                // catching up with itself. Steering still
                                // glides. syncToCurrent() raises `_snapSync`
                                // for its currentIndex write.
                                property bool _snapSync: false
                                highlightMoveDuration: _snapSync ? 0 : Theme.durNormal

                                path: Path {
                                    startY: wallpaperView.height / 2
                                    PathAttribute { name: "z"; value: 0 }
                                    PathLine { x: wallpaperView.width / 2; relativeY: 0 }
                                    PathAttribute { name: "z"; value: 1 }
                                    PathLine { x: wallpaperView.width; relativeY: 0 }
                                }

                                onCurrentItemChanged: {
                                    if (!launcherScope.wallpaperMode) return
                                    let it = wallpaperView.currentItem
                                    if (it && it.wpPath !== undefined && ("" + it.wpPath).length > 0)
                                        WallpaperService.previewWallpaper("" + it.wpPath)
                                }
                                onCountChanged: syncToCurrent()
                                Connections {
                                    target: launcherScope
                                    function onWallpaperResultsChanged() { wallpaperView.syncToCurrent() }
                                }
                                // Empty query resumes at the committed
                                // wallpaper; a query restarts at the first
                                // match (Caelestia WallpaperList onValuesChanged).
                                function syncToCurrent(): void {
                                    if (!launcherScope.wallpaperMode) return
                                    let arr = launcherScope.wallpaperResults
                                    // Snap the reposition (see _snapSync): the
                                    // glide would fight the page slide.
                                    _snapSync = true
                                    if (arr.length === 0) {
                                        currentIndex = -1
                                    } else if (launcherScope.wallpaperQuery.length > 0) {
                                        currentIndex = 0
                                    } else {
                                        let cur = "" + WallpaperService.current
                                        let idx = 0
                                        for (let i = 0; i < arr.length; i++) {
                                            if (("" + arr[i].path) === cur) { idx = i; break }
                                        }
                                        currentIndex = idx
                                    }
                                    Qt.callLater(() => _snapSync = false)
                                }

                                delegate: Item {
                                    id: wpItem
                                    required property var modelData
                                    required property int index
                                    readonly property string wpPath: wpItem.modelData ? String(wpItem.modelData.path || "") : ""
                                    readonly property string wpName: wpItem.modelData ? String(wpItem.modelData.name || "") : ""
                                    readonly property bool current: PathView.isCurrentItem
                                    width: launcherScope.wallpaperItemWidth
                                    implicitHeight: wpContent.implicitHeight
                                    height: implicitHeight
                                    scale: wpItem.current ? 1 : PathView.onPath ? 0.82 : 0.5
                                    opacity: PathView.onPath ? 1 : 0
                                    z: PathView.z ?? 0
                                    Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
                                    Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }

                                    Column {
                                        id: wpContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Item {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 240
                                            height: 135

                                            Rectangle {
                                                id: wpThumb
                                                anchors.fill: parent
                                                radius: 16
                                                color: Theme.panelCardHighest
                                                clip: true
                                                antialiasing: Theme.shapesAa
                                                Image {
                                                    id: wpImage
                                                    // Binding-safe thumb fallback (see WallpaperStylesPage).
                                                    property string brokenThumb: ""
                                                    anchors.fill: parent
                                                    source: brokenThumb === wpItem.wpPath
                                                        ? WallpaperService.originalUrl(wpItem.wpPath)
                                                        : WallpaperService.imageUrl(wpItem.wpPath)
                                                    sourceSize: Qt.size(Math.round(width * 1.5), Math.round(height * 1.5))
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    smooth: !wallpaperView.moving
                                                    mipmap: Theme.imageMipmap
                                                    onStatusChanged: if (status === Image.Error && brokenThumb !== wpItem.wpPath) brokenThumb = wpItem.wpPath
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: wpImage.status !== Image.Ready
                                                    text: "󰸉"
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: Theme.fs(28)
                                                    color: Theme.textMuted
                                                    antialiasing: Theme.textAa
                                                    renderType: Theme.textRenderType
                                                }
                                            }
                                            // Ring on the centred item.
                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: -3
                                                radius: 19
                                                color: "transparent"
                                                border.width: 2
                                                border.color: wpItem.current ? Theme.accent : "transparent"
                                                antialiasing: Theme.shapesAa
                                            }
                                        }

                                        Text {
                                            width: parent.width - 24
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: wpItem.wpName
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            font.weight: wpItem.current ? Font.Medium : Font.Normal
                                            color: wpItem.current ? Theme.textPrimary : Theme.textMuted
                                            antialiasing: Theme.textAa
                                            renderType: Theme.textRenderType
                                        }
                                    }

                                    StateLayer {
                                        anchors.fill: parent
                                        radius: 20
                                        color: Theme.textPrimary
                                        onClicked: launcherScope.applyWallpaper(wpItem.wpPath)
                                    }
                                }
                            }

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: event => {
                                    if (event.angleDelta.y > 0) wallpaperView.decrementCurrentIndex()
                                    else if (event.angleDelta.y < 0) wallpaperView.incrementCurrentIndex()
                                    event.accepted = true
                                }
                            }

                            // Empty state (Caelestia "No wallpapers found").
                            Column {
                                anchors.centerIn: parent
                                visible: wallpaperView.count === 0
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰸉"
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: Theme.fs(28)
                                    color: Theme.textMuted
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No wallpapers found"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    color: Theme.textMuted
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Put images in " + WallpaperService.dirDisplay
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    color: Theme.textMuted
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                            }
                        }

                        // Search field (screenshot: bottom, round badge + input).
                        // Chrome of the app/emoji pages only: the wallpaper
                        // carousel and the web app page own the whole card
                        // and arrows/Enter are the controls. Fades with the
                        // slide instead of popping (barPage tracks the
                        // incoming page; geometry stays for appList's anchor).
                        Rectangle {
                            id: searchBar
                            visible: opacity > 0.01
                            opacity: launcherScope.barPage ? 1 : 0
                            Behavior on opacity {
                                enabled: Theme.animationsEnabled
                                NumberAnimation {
                                    duration: Theme.durDefaultEffects
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.curveDefaultEffects
                                }
                            }
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            height: 56
                            radius: height / 2
                            color: Theme.panelCardLowest
                            border.color: Theme.divider
                            border.width: 1
                            antialiasing: Theme.shapesAa

                            Item {
                                id: searchBadge
                                width: 38
                                height: 38
                                anchors.left: parent.left
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                // Material 3 expressive badge: the shape is
                                // re-rolled per open and morphs on the shared
                                // spatial curve (MaterialShape animates the
                                // shape swap itself).
                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: Math.min(searchBadge.width, searchBadge.height)
                                    color: Theme.withAlpha(Theme.accent, 0.18)
                                    shape: launcherScope.badgeShape
                                    animationDuration: Theme.durDefaultSpatial
                                    animationEasing.type: Easing.BezierSpline
                                    animationEasing.bezierCurve: Theme.curveDefaultSpatial
                                    Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰍉"
                                    color: Theme.accent
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: Theme.fs(18)
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                            }
                            TextField {
                                id: searchInput
                                anchors.left: searchBadge.right
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                background: null
                                placeholderText: launcherScope.emojiMode ? "Search emoji..."
                                    : launcherScope.menuMode ? "Search menus..." : "Search applications..."
                                placeholderTextColor: Theme.textMuted
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(15)
                                selectByMouse: true
                                cursorDelegate: Rectangle {
                                    width: 2
                                    color: Theme.accent
                                    antialiasing: Theme.shapesAa
                                }
                                // Grid movement and page cycling must win over
                                // the field's own key handling (single-line
                                // fields otherwise keep Up/Down/Tab); typing
                                // and cursor moves stay untouched.
                                Keys.priority: Keys.BeforeItem
                                Keys.onPressed: event => {
                                    if (launcherScope.handlePageTab(event)) {
                                        event.accepted = true
                                        return
                                    }
                                    if (launcherScope.emojiMode && emojiPage.handleFieldKey(event))
                                        event.accepted = true
                                }
                                onTextChanged: launcherScope.filterText = text
                                onAccepted: {
                                    if (launcherScope.wallpaperMode) {
                                        let it = wallpaperView.currentItem
                                        if (it && it.wpPath !== undefined && ("" + it.wpPath).length > 0)
                                            launcherScope.applyWallpaper("" + it.wpPath)
                                        return
                                    }
                                    if (launcherScope.emojiMode) {
                                        emojiPage.activateCurrent()
                                        return
                                    }
                                    launcherScope.activateCurrent()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
