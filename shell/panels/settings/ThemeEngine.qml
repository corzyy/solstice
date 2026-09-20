pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../themes"

Item {
    id: engine

    // Settings re-syncs the active theme ~1s after the page is created so a
    // reopened page reflects the persisted engine. Other hosts (launcher
    // wallpaper picker) only instantiate the engine to apply a wallpaper and
    // disable that boot pass: the resync would re-render preset themes on
    // every launcher load for nothing.
    property bool autoResync: true

    // PERF: mkdir+jq init used to run 650ms after every menu open
    // (ThemeEngine lived in the menu Loader, re-created per open). Adapter
    // defaults already cover a missing file; the file is created on first
    // writeAdapter. No boot fork needed.
    FileView {
        id: themeEngineFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/themes/theme_engine.json"
        watchChanges: true; onFileChanged: engineReloadDebounce.restart(); blockLoading: true; printErrors: false
        adapter: JsonAdapter { property string engine: "wallpaper" }
    }
    Timer {
        id: engineReloadDebounce
        interval: 250; repeat: false
        onTriggered: {
            try { themeEngineFile.reload() } catch (e) { }
            try { matugenSettingsFile.reload() } catch (e2) { }
            try { currentWallpaperFile.reload() } catch (e3) { }
        }
    }
    readonly property string currentEngine: {
        let e = themeEngineFile.adapter.engine
        if (e === "everforest" || e === "tokyonight" || e === "petrichor" || e === "monochrome" || e === "catppuccin" || e === "gruvbox") return e
        return "wallpaper"
    }

    FileView {
        id: matugenSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/themes/matugen_settings.json"
        watchChanges: true; onFileChanged: engineReloadDebounce.restart(); blockLoading: true; printErrors: false
        adapter: JsonAdapter { property string type: "scheme-tonal-spot"; property string mode: "dark"; property real contrast: 0.0 }
    }
    readonly property var matugenTypes: ["scheme-tonal-spot", "scheme-content", "scheme-expressive", "scheme-fidelity", "scheme-fruit-salad", "scheme-monochrome", "scheme-neutral", "scheme-rainbow", "scheme-vibrant", "scheme-smart"]
    readonly property var matugenTypeLabels: ({"scheme-tonal-spot": "Tonal Spot", "scheme-content": "Content", "scheme-expressive": "Expressive", "scheme-fidelity": "Fidelity", "scheme-fruit-salad": "Fruit Salad", "scheme-monochrome": "Monochrome", "scheme-neutral": "Neutral", "scheme-rainbow": "Rainbow", "scheme-vibrant": "Vibrant", "scheme-smart": "Smart (Auto)"})
    readonly property string monetType: { try { let v = matugenSettingsFile.adapter.type; if (v && v.length>0) return v; return "scheme-tonal-spot" } catch(e) { return "scheme-tonal-spot" } }
    readonly property string monetMode: { try { let m = matugenSettingsFile.adapter.mode; if (m==="light"||m==="dark") return m; return "dark" } catch(e){ return "dark" } }

    property bool themeBusy: false
    property string _pendingSpec: ""
    property bool _pendingSilent: false
    // OSD payload of the run the serial proc is currently executing; the
    // trigger fires in finishThemeApply so errors can win over the label.
    property string _osdKind: ""
    property string _osdLabel: ""
    property string _osdDetail: ""
    property bool _osdSilent: true
    Process {
        id: themeSerialProc
        command: ["bash", "-c", "echo"]
        onExited: (code) => engine.finishThemeApply(code)
    }
    Timer {
        id: themeNextTimer
        // Minimal gap between a finished apply and a coalesced pending one:
        // lets file watchers settle so the next run reads fresh inputs.
        interval: 100; repeat: false
        onTriggered: engine.tryRunPending()
    }
    function enqueueThemeApply(spec: string, silent: bool) {
        if (themeBusy || themeSerialProc.running) { _pendingSpec = spec; _pendingSilent = !!silent; return }
        runThemeSpec(spec, !!silent)
    }
    function runThemeSpec(spec: string, silent: bool) {
        if (spec.indexOf("preset:") === 0) runPresetApply(spec.substring(7), !!silent)
        else if (spec.indexOf("monet:") === 0) runMonetApply(spec.substring(6))
        else if (spec === "monetCurrent") runMonetApply("")
        else return
        themeBusy = true
    }
    function tryRunPending() {
        if (themeBusy || themeSerialProc.running) return
        if (_pendingSpec === "") return
        let s = _pendingSpec
        let sl = _pendingSilent
        _pendingSpec = ""
        _pendingSilent = false
        runThemeSpec(s, sl)
    }
    function finishThemeApply(code) {
        themeBusy = false
        if (code !== 0) console.log("[ThemeEngine] apply exited with code", code)
        // Theme applies used to notify through notify-send; the shell's OSD
        // card now carries the same feedback (label + mode/variant, error
        // color on a failed apply). Silent runs (page-open re-sync) stay quiet.
        if (!_osdSilent && _osdLabel !== "") {
            if (code !== 0) {
                let msg = _osdKind === "monet" ? "No wallpaper found" : "Theme source missing"
                Theme.triggerThemeOsd(_osdLabel, msg, true)
            } else {
                Theme.triggerThemeOsd(_osdLabel, _osdDetail, false)
            }
        }
        _osdKind = ""
        _osdLabel = ""
        _osdDetail = ""
        _osdSilent = true
        if (_pendingSpec !== "") themeNextTimer.restart()
    }

    FileView {
        id: currentWallpaperFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/current_wallpaper.txt"
        watchChanges: true; onFileChanged: engineReloadDebounce.restart(); blockLoading: true; printErrors: false
    }
    function currentWallpaperText(): string {
        try { return currentWallpaperFile.text().trim() } catch(e) { return "" }
    }

    // Per-theme wallpaper memory: the wallpaper/monet engine and every color
    // preset remember the last wallpaper they were used with, so switching
    // themes restores the wallpaper belonging to that theme.
    FileView {
        id: themeWallpapersFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/themes/theme_wallpapers.json"
        blockLoading: true; printErrors: false
        adapter: JsonAdapter { property var wallpapers: ({}) }
    }
    function wallpaperForTheme(id: string): string {
        try {
            if (!id || id.length === 0) return ""
            let map = themeWallpapersFile.adapter.wallpapers
            if (map && typeof map === "object" && typeof map[id] === "string") return map[id]
        } catch (e) { }
        return ""
    }
    function rememberWallpaper(id: string, path: string) {
        if (!id || !path || path.length === 0) return
        if (path.indexOf("\n") >= 0 || path.indexOf("\r") >= 0) return
        try {
            let map = themeWallpapersFile.adapter.wallpapers
            let obj = {}
            if (map && typeof map === "object") { for (let k in map) obj[k] = map[k] }
            if (obj[id] === path) return
            obj[id] = path
            themeWallpapersFile.adapter.wallpapers = obj
            themeWallpapersFile.writeAdapter()
        } catch (e) { }
    }
    // Emitted when a theme switch should also change the displayed wallpaper.
    signal wallpaperDisplayRequested(string path)

    Timer {
        id: themeEngineApplyTimer
        interval: 950; running: engine.autoResync; repeat: false
        // Re-sync apply: ThemeEngine is re-created whenever the settings
        // panel loads, so this must stay silent — otherwise a "Theme"
        // notification pops up ~1s after opening the page whenever it stays
        // open past this timer (e.g. while scrolling).
        onTriggered: {
            if (engine.currentEngine === "everforest") applyPreset("everforest", true)
            else if (engine.currentEngine === "tokyonight") applyPreset("tokyonight", true)
            else if (engine.currentEngine === "petrichor") applyPreset("petrichor", true)
            else if (engine.currentEngine === "monochrome") applyPreset("monochrome", true)
            else if (engine.currentEngine === "catppuccin") applyPreset("catppuccin", true)
            else if (engine.currentEngine === "gruvbox") applyPreset("gruvbox", true)
        }
    }

    function resolveWallpaper(overridePath: string, fallbackPath: string): string {
        let w = (overridePath && overridePath.length > 0) ? overridePath : ""
        if (w === "") w = currentWallpaperText()
        if (w === "") w = (fallbackPath && fallbackPath.length > 0) ? fallbackPath : ""
        return w
    }

    function applyMonetScheme(type, mode) {
        if (!type || type.length === 0) type = matugenSettingsFile.adapter.type
        if (!mode || mode.length === 0) mode = matugenSettingsFile.adapter.mode
        if (type.indexOf("scheme-") !== 0) type = "scheme-tonal-spot"
        if (mode !== "dark" && mode !== "light") mode = "dark"
        matugenSettingsFile.adapter.type = type
        matugenSettingsFile.adapter.mode = mode
        matugenSettingsFile.writeAdapter()
        if (currentEngine !== "wallpaper") {
            // Switching from a preset to the wallpaper engine: run the normal
            // theme switch so the wallpaper engine's remembered wallpaper is
            // restored together with the new scheme.
            setThemeEngine("wallpaper")
        } else {
            enqueueThemeApply("monetCurrent")
        }
    }

    function matugenBin(): string {
        // solstice Application Theming: route through matugen-run.sh so template
        // toggles (theming_settings.json) + terminals-always-dark are honored.
        // Provides a "${MATUGEN[@]}" argv array: [bash matugen-run.sh] when
        // executable, else the plain matugen binary.
        return "RUN=\"$HOME/.config/quickshell/solstice/scripts/matugen-run.sh\"; if [ -x \"$RUN\" ]; then MATUGEN=(bash \"$RUN\"); else [ -x \"$HOME/.cargo/bin/matugen\" ] && MATUGEN=(\"$HOME/.cargo/bin/matugen\") || MATUGEN=(matugen); fi;"
    }

    function runMonetApply(wallPath: string) {
        // Fast path: TYPE/MODE come straight from the QML adapter (no jq
        // subprocesses) and WALL travels as argv $1 (no shell escaping, no
        // find(1) directory scan). matugen-run.sh keeps the synchronous part
        // to ~0.3s (papirus icons + gtk re-apply run detached).
        let type = "scheme-tonal-spot", mode = "dark"
        try {
            let t = matugenSettingsFile.adapter.type
            if (t && matugenTypes.indexOf(t) >= 0) type = t
            let m = matugenSettingsFile.adapter.mode
            if (m === "light" || m === "dark") mode = m
        } catch (e) {}
        let wall = (wallPath && wallPath.length > 0) ? wallPath : ""
        if (wall === "") wall = resolveWallpaper("", "")
        let cmd = matugenBin()
        cmd += "WALL=\"$1\"; TYPE=\"$2\"; MODE=\"$3\";"
        cmd += " [ -f \"$WALL\" ] || WALL=\"$(cat ~/.cache/swaybg/current 2>/dev/null | tr -d '\\r\\n')\";"
        cmd += " [ -f \"$WALL\" ] || WALL=\"$(cat ~/.config/quickshell/solstice/config/current_wallpaper.txt 2>/dev/null | tr -d '\\r\\n')\";"
        cmd += " case \"$TYPE\" in scheme-*) ;; *) TYPE=\"scheme-tonal-spot\";; esac; [ \"$MODE\" = \"light\" ] || MODE=\"dark\";"
        cmd += " if [ -f \"$WALL\" ]; then"
        cmd += " \"${MATUGEN[@]}\" image \"$WALL\" -t \"$TYPE\" -m \"$MODE\" --prefer saturation 2>&1 | logger -t matugen;"
        // btop/kitty/gtk reloads are matugen post_hooks — no duplicate sed here.
        // GTK settings.ini/css catch-up runs detached: the serial proc
        // returns as soon as matugen is done (~0.3s).
        cmd += " (bash \"$HOME/.config/quickshell/solstice/scripts/apply-gtk.sh\" \"$MODE\" 2>&1 | logger -t gtk) >/dev/null 2>&1 < /dev/null &"
        cmd += " else echo \"[ThemeEngine] no wallpaper found, Monet skipped\" | logger -t monet; exit 1; fi; echo done"
        if (themeSerialProc.running) { _pendingSpec = "monet:" + wall; return }
        _osdKind = "monet"
        _osdLabel = "Monet"
        // Mode first (the common toggle), variant appended when non-default.
        _osdDetail = mode + (type !== "scheme-tonal-spot" ? " · " + (matugenTypeLabels[type] || type) : "")
        _osdSilent = false
        themeSerialProc.command = ["bash", "-c", cmd, "solstice-monet", wall, type, mode]
        themeSerialProc.running = true
    }

    function runPresetApply(id: string, silent: bool) {
        let mode = "dark"
        try { let m = matugenSettingsFile.adapter.mode; if (m === "light" || m === "dark") mode = m } catch(e) { mode = "dark" }
        let nameMap = { everforest: "everforest-soft", tokyonight: "tokyonight", petrichor: "petrichor", monochrome: "monochrome", catppuccin: "catppuccin-mocha", gruvbox: "gruvbox" }
        let key = nameMap[id] || id
        // SRC/DST/RENDER travel as argv ($1..$3): no quote-escaping bugs with
        // exotic $HOME values. The shell colors update instantly via the
        // atomic DST swap; the slow per-app render runs detached.
        let src = Quickshell.env("HOME") + "/.config/quickshell/solstice/themes/" + key + "-" + mode + ".json"
        let dst = Quickshell.env("HOME") + "/.config/quickshell/solstice/themes/matugen.json"
        let render = Quickshell.env("HOME") + "/.config/quickshell/solstice/scripts/render-everforest.py"
        let label = id.charAt(0).toUpperCase() + id.slice(1)
        label = label.replace(/[^A-Za-z0-9 -]/g, "")
        if (label.length === 0) label = "Theme"
        let cmd = "SRC=\"$1\"; DST=\"$2\"; RENDER=\"$3\"; MODE=\"$4\"; TAG=\"" + id.replace(/[^a-z0-9-]/g, "") + "\"; LBL=\"" + label + "\";"
        cmd += " if [ -f \"$SRC\" ]; then if cmp -s \"$SRC\" \"$DST\" 2>/dev/null; then echo \"[$LBL] $MODE already active, skip\" | logger -t \"$TAG\";"
        cmd += " else TMP=\"$DST.tmp.$$\"; cp -f \"$SRC\" \"$TMP\" && mv -f \"$TMP\" \"$DST\"; rm -f \"$TMP\";"
        cmd += " (python3 \"$RENDER\" \"$MODE\" \"$SRC\" 2>&1 | logger -t \"$TAG\"; bash \"$HOME/.config/quickshell/solstice/scripts/apply-gtk.sh\" \"$MODE\" 2>&1 | logger -t gtk) >/dev/null 2>&1 < /dev/null &"
        cmd += " echo \"[$LBL] $MODE applied from $SRC (shell instant, apps in background)\" | logger -t \"$TAG\"; fi;"
        cmd += " else echo \"[$LBL] source missing $SRC\" | logger -t \"$TAG\"; exit 1; fi;"
        cmd += " echo done"
        if (themeSerialProc.running) { _pendingSpec = "preset:" + id; _pendingSilent = !!silent; return }
        _osdKind = "preset"
        _osdLabel = label
        _osdDetail = mode
        _osdSilent = !!silent
        themeSerialProc.command = ["bash", "-c", cmd, "solstice-preset", src, dst, render, mode]
        themeSerialProc.running = true
    }

    function applyPreset(id: string, silent: bool) { enqueueThemeApply("preset:" + id, !!silent) }

    function setThemeEngine(id: string) {
        let nid = "wallpaper"
        if (id === "everforest" || id === "tokyonight" || id === "petrichor" || id === "monochrome" || id === "catppuccin" || id === "gruvbox") nid = id
        // Remember the wallpaper of the theme we are leaving, then restore the
        // one the target theme was last used with (empty => keep current).
        let outgoing = currentEngine
        let current = currentWallpaperText()
        if (current !== "") rememberWallpaper(outgoing, current)
        let targetWall = wallpaperForTheme(nid)
        if (themeEngineFile.adapter.engine === nid) {
            applyEngine(nid, targetWall)
        } else {
            themeEngineFile.adapter.engine = nid
            themeEngineFile.writeAdapter()
            applyEngine(nid, targetWall)
        }
        if (targetWall !== "" && targetWall !== current) wallpaperDisplayRequested(targetWall)
    }
    function applyEngine(nid: string, wallpaper: string) {
        if (nid === "wallpaper") applyThemeFromWallpaper(wallpaper, "")
        else applyPreset(nid)
    }

    function abortMonet() { if (_pendingSpec.indexOf("monet:") === 0 || _pendingSpec === "monetCurrent") _pendingSpec = "" }
    function applyMonetFromPath(rawPath: string) {
        enqueueThemeApply("monet:" + (rawPath || ""))
    }

    function applyThemeFromWallpaper(overridePath: string, fallbackPath: string) {
        let wallpaper = resolveWallpaper(overridePath, fallbackPath)
        enqueueThemeApply("monet:" + wallpaper)
    }
}
