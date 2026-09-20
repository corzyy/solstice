pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    FileView {
        id: colorFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/themes/matugen.json"
        printErrors: false; watchChanges: true; blockLoading: true
        onFileChanged: colorReloadDebounce.restart()
        adapter: JsonAdapter {
            property color background: "#1E2132"
            property color error: "#ffb4ab"
            property color error_container: "#93000a"
            property color inverse_on_surface: "#303036"
            property color inverse_primary: "#585992"
            property color inverse_surface: "#e4e1e9"
            property color on_background: "#e4e1e9"
            property color on_error: "#690005"
            property color on_error_container: "#ffdad6"
            property color on_primary: "#542202"
            property color on_primary_container: "#e1e0ff"
            property color on_primary_fixed: "#13144a"
            property color on_primary_fixed_variant: "#404178"
            property color on_secondary: "#432b1e"
            property color on_secondary_container: "#e2e0f9"
            property color on_secondary_fixed: "#1a1a2c"
            property color on_secondary_fixed_variant: "#454559"
            property color on_surface: "#ECEEFF"
            property color on_surface_variant: "#A0A6C8"
            property color on_tertiary: "#46263a"
            property color on_tertiary_container: "#ffd8ec"
            property color on_tertiary_fixed: "#2e1125"
            property color on_tertiary_fixed_variant: "#5f3c51"
            property color outline: "#6E7391"
            property color outline_variant: "#34395E"
            property color primary: "#7AA2F7"
            property color primary_container: "#3B3F6E"
            property color primary_fixed: "#e1e0ff"
            property color primary_fixed_dim: "#c1c1ff"
            property color scrim: "#000000"
            property color secondary: "#8E93B3"
            property color secondary_container: "#454559"
            property color secondary_fixed: "#e2e0f9"
            property color secondary_fixed_dim: "#c6c4dd"
            property color shadow: "#000000"
            property color source_color: "#5456c0"
            property color surface: "#1E2132"
            property color surface_bright: "#39383f"
            property color surface_container: "#252A40"
            property color surface_container_high: "#2B2F4A"
            property color surface_container_highest: "#2E334E"
            property color surface_container_low: "#1b1b21"
            property color surface_container_lowest: "#0e0e13"
            property color surface_dim: "#131318"
            property color surface_tint: "#c1c1ff"
            property color surface_variant: "#52443d"
            property color tertiary: "#e9b9d3"
            property color tertiary_container: "#5f3c51"
            property color tertiary_fixed: "#ffd8ec"
            property color tertiary_fixed_dim: "#e9b9d3"
        }
    }
    Timer {
        id: colorReloadDebounce
        // Short guard against reading a half-written matugen.json; the shell
        // recolors as soon as the file settles.
        interval: 80; repeat: false
        onTriggered: colorFile.reload()
    }
    Timer {
        id: fileReloadDebounce
        interval: 250; repeat: false
        property var queue: []
        onTriggered: {
            let q = queue
            queue = []
            for (let i = 0; i < q.length; i++) {
                try { q[i].reload() } catch (e) { }
            }
        }
    }
    function debouncedReload(fv: var): void {
        try {
            if (fileReloadDebounce.queue.indexOf(fv) < 0) fileReloadDebounce.queue.push(fv)
            fileReloadDebounce.restart()
        } catch (e) {
            try { fv.reload() } catch (e2) { }
        }
    }

    readonly property color background: colorFile.adapter.background
    readonly property color error: colorFile.adapter.error
    readonly property color error_container: colorFile.adapter.error_container
    readonly property color inverse_on_surface: colorFile.adapter.inverse_on_surface
    readonly property color inverse_primary: colorFile.adapter.inverse_primary
    readonly property color inverse_surface: colorFile.adapter.inverse_surface
    readonly property color on_background: colorFile.adapter.on_background
    readonly property color on_error: colorFile.adapter.on_error
    readonly property color on_error_container: colorFile.adapter.on_error_container
    readonly property color on_primary: colorFile.adapter.on_primary
    readonly property color on_primary_container: colorFile.adapter.on_primary_container
    readonly property color on_primary_fixed: colorFile.adapter.on_primary_fixed
    readonly property color on_primary_fixed_variant: colorFile.adapter.on_primary_fixed_variant
    readonly property color on_secondary: colorFile.adapter.on_secondary
    readonly property color on_secondary_container: colorFile.adapter.on_secondary_container
    readonly property color on_secondary_fixed: colorFile.adapter.on_secondary_fixed
    readonly property color on_secondary_fixed_variant: colorFile.adapter.on_secondary_fixed_variant
    readonly property color on_surface: colorFile.adapter.on_surface
    readonly property color on_surface_variant: colorFile.adapter.on_surface_variant
    readonly property color on_tertiary: colorFile.adapter.on_tertiary
    readonly property color on_tertiary_container: colorFile.adapter.on_tertiary_container
    readonly property color on_tertiary_fixed: colorFile.adapter.on_tertiary_fixed
    readonly property color on_tertiary_fixed_variant: colorFile.adapter.on_tertiary_fixed_variant
    readonly property color outline: colorFile.adapter.outline
    readonly property color outline_variant: colorFile.adapter.outline_variant
    readonly property color primary: colorFile.adapter.primary
    readonly property color primary_container: colorFile.adapter.primary_container
    readonly property color primary_fixed: colorFile.adapter.primary_fixed
    readonly property color primary_fixed_dim: colorFile.adapter.primary_fixed_dim
    readonly property color scrim: colorFile.adapter.scrim
    readonly property color secondary: colorFile.adapter.secondary
    readonly property color secondary_container: colorFile.adapter.secondary_container
    readonly property color secondary_fixed: colorFile.adapter.secondary_fixed
    readonly property color secondary_fixed_dim: colorFile.adapter.secondary_fixed_dim
    readonly property color shadow: colorFile.adapter.shadow
    readonly property color source_color: colorFile.adapter.source_color
    readonly property color surface: colorFile.adapter.surface
    readonly property color surface_bright: colorFile.adapter.surface_bright
    readonly property color surface_container: colorFile.adapter.surface_container
    readonly property color surface_container_high: colorFile.adapter.surface_container_high
    readonly property color surface_container_highest: colorFile.adapter.surface_container_highest
    readonly property color surface_container_low: colorFile.adapter.surface_container_low
    readonly property color surface_container_lowest: colorFile.adapter.surface_container_lowest
    readonly property color surface_dim: colorFile.adapter.surface_dim
    readonly property color surface_tint: colorFile.adapter.surface_tint
    readonly property color surface_variant: colorFile.adapter.surface_variant
    readonly property color tertiary: colorFile.adapter.tertiary
    readonly property color tertiary_container: colorFile.adapter.tertiary_container
    readonly property color tertiary_fixed: colorFile.adapter.tertiary_fixed
    readonly property color tertiary_fixed_dim: colorFile.adapter.tertiary_fixed_dim

    readonly property color bg: surface
    readonly property color surface2: frostFill(surface_container_high, 0.18, 0.84)
    readonly property color bgHover: frostFill(surface_container_highest, 0.14, 0.88)
    readonly property color bgSelected: frostFill(primary_container, 0.08, 0.92)
    readonly property color cardBg: panelFill(surface_container_high)
    readonly property color borderColor: outline_variant
    readonly property color textPrimary: on_surface
    readonly property color textSecondary: on_surface_variant
    readonly property color textMuted: outline
    readonly property color iconColor: secondary
    readonly property color iconBg: frostFill(surface_container_high, 0.16, 0.86)
    readonly property color iconBgSelected: primary
    readonly property color iconColorSelected: on_primary
    readonly property color onAccent: on_primary
    readonly property color accent: primary
    readonly property color divider: outline_variant
    readonly property color errorColor: error

    FileView {
        id: fontFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/font_settings.json"
        watchChanges: true; onFileChanged: debouncedReload(fontFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter { property string fontFamily: "Adwaita Sans"; property int fontSize: 11 }
    }
    readonly property string fontFamily: (fontFile.adapter.fontFamily && fontFile.adapter.fontFamily.length > 0) ? fontFile.adapter.fontFamily : "Adwaita Sans"
    readonly property string iconFontFamily: "JetBrainsMono Nerd Font"
    // Colour emoji for the launcher emoji picker (installed user-level by
    // scripts/ensure-emoji-font.sh). Named explicitly so glyphs never fall
    // back to a monochrome face; Qt's fontconfig fallback covers systems
    // with a different colour emoji font.
    readonly property string emojiFontFamily: "Noto Color Emoji"
    readonly property int fontSize: Math.max(8, Math.min(16, Math.round(fontFile.adapter.fontSize || 11)))
    Process { id: fontApplyProc; command: ["bash", "-c", "echo"]; onExited: pumpFontApply() }
    property var _fontApplyPending: null
    function runFontApply(): void {
        // STABILITY: coalesce bursts (font picker drags). Old code dropped
        // ticks silently when running; now the latest always lands.
        _fontApplyPending = { family: fontFamily, size: String(fontSize) }
        if (!fontApplyProc.running) pumpFontApply()
    }
    function pumpFontApply(): void {
        if (_fontApplyPending === null || _fontApplyPending === undefined) return
        if (fontApplyProc.running) return
        let p = _fontApplyPending
        _fontApplyPending = null
        let script = Quickshell.env("HOME") + "/.config/quickshell/solstice/scripts/apply-font.sh"
        fontApplyProc.command = ["bash", script, p.family, p.size]
        fontApplyProc.running = true
    }
    function setSystemFont(family: string): void {
        let f = (family || "").trim()
        if (f.length === 0 || f.indexOf("\n") !== -1 || f.indexOf("\r") !== -1) return
        if (fontFile.adapter.fontFamily !== f) {
            fontFile.adapter.fontFamily = f
            fontFile.writeAdapter()
        }
        runFontApply()
    }
    function setFontSize(v: real): void {
        let c = Math.max(8, Math.min(16, Math.round(v)))
        if (Math.round(fontFile.adapter.fontSize || 11) === c) return
        fontFile.adapter.fontSize = c
        fontFile.writeAdapter()
        runFontApply()
    }

    FileView {
        id: shellFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/topbar_settings.json"
        watchChanges: true; onFileChanged: debouncedReload(shellFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property int radius: 0
            property bool animationsEnabled: true
            property real animationSpeed: 1.0
            property string clockPosition: "center"
            property string clockFormat: "full"
            property string workspacesPosition: "left"
            // Caelestia bar.workspaces settings (ported 1:1 where Umbriel
            // allows). displayType replaces the old workspaceStyle.
            property string workspaceDisplayType: "shapes"
            property int workspaceShown: 5
            property bool workspaceActiveIndicator: true
            property bool workspaceActiveTrail: true
            property bool workspaceOccupiedBg: false
            property bool workspaceShowUnoccupied: true
            property bool workspacePerMonitor: true
            property bool workspaceShowWindows: true
            property int workspaceMaxWindowIcons: 5
            property var workspaceIgnoredTags: ["hide_in_bar", "xwl_popup"]
            property int workspaceSpacing: 4
            property real workspaceScale: 1.0
            property int thickness: 30
            property real opacity: 1.0
            property string position: "top"
            property bool textBold: false
            property bool antialiasing: true
            property bool aaShapes: true
            property bool aaText: true
            property bool aaTextNative: true
            property bool aaImageSmooth: true
            property bool aaImageMipmap: false
            property real fontScale: 1.0
            property bool panelAccentBorder: false
            property real panelBlur: 0.6
            property int moduleSpacing: 8
            property int edgeDistance: 0
            property int topDistance: 0
            property int contentPadding: 12
            property bool persistent: true
            property bool showOnHover: true
            property int dragThreshold: 10
            property bool scrollWorkspaces: true
            property bool scrollVolume: true
            property bool scrollBrightness: true
        }
    }
    // Minimal is the only shell theme: former Modern branches deleted.

    // Einzige Schreibpfade für Adapter-Settings (ein Guard statt ~20x
    // kopierter clamp/compare/write-Blöcke). Alle Adapter deklarieren
    // Defaults, daher ist adapter[key] nie undefined.
    function setAdapterBool(fileView: var, key: string, v: bool): void {
        const nv = !!v
        if (!!fileView.adapter[key] === nv) return
        fileView.adapter[key] = nv
        fileView.writeAdapter()
    }
    function setAdapterInt(fileView: var, key: string, v: var, lo: int, hi: int): void {
        const c = Math.max(lo, Math.min(hi, Math.round(Number(v))))
        if (isNaN(c)) return // statt NaN in die Config zu schreiben, ignorieren
        if (Math.round(Number(fileView.adapter[key])) === c) return
        fileView.adapter[key] = c
        fileView.writeAdapter()
    }
    function setAdapterReal(fileView: var, key: string, v: var, lo: real, hi: real): void {
        let c = Math.max(lo, Math.min(hi, Number(v)))
        if (isNaN(c)) return
        c = Math.round(c * 100) / 100
        if (Math.abs(Number(fileView.adapter[key]) - c) < 0.001) return
        fileView.adapter[key] = c
        fileView.writeAdapter()
    }
    // Shell rounding (Global > Rounding). Single source for all shell
    // radii; synced to Umbriel window rounding by the Global slider.
    readonly property int cornerRadius: Math.max(0, Math.min(40, Math.round(shellFile.adapter.radius ?? 0)))
    readonly property int cornerRadiusSmall: Math.max(0, Math.min(12, Math.round(cornerRadius * 0.6)))
    function setCornerRadius(v: int): void { setAdapterInt(shellFile, "radius", v, 0, 40) }
    readonly property int barThickness: Math.max(20, Math.min(48, Math.round(shellFile.adapter.thickness !== undefined ? shellFile.adapter.thickness : 30)))
    readonly property string barPosition: {
        let p = shellFile.adapter.position
        if (p === "bottom" || p === "left" || p === "right" || p === "top") return p
        return "top"
    }
    readonly property real barOpacity: {
        let o = shellFile.adapter.opacity
        if (o === undefined || o === null || isNaN(o)) return 1.0
        return Math.max(0.0, Math.min(1.0, o))
    }
    function setBarThickness(v: int): void { setAdapterInt(shellFile, "thickness", v, 20, 48) }
    function setBarOpacity(v: real): void { setAdapterReal(shellFile, "opacity", v, 0.0, 1.0) }
    function setBarPosition(pos: string): void {
        if (pos !== "top" && pos !== "bottom" && pos !== "left" && pos !== "right") return
        if (shellFile.adapter.position === pos) return
        shellFile.adapter.position = pos
        shellFile.writeAdapter()
    }
    readonly property bool animationsEnabled: shellFile.adapter.animationsEnabled
    function setAnimationsEnabled(v: bool): void { setAdapterBool(shellFile, "animationsEnabled", v) }
    // Global animation speed multiplier (Global > Animations). 1.0 = token
    // durations as specified; 2.0 plays them twice as fast. All duration
    // tokens below route through animMs() so one value drives every
    // animation in the shell. Clamped to 0.5x-2x.
    readonly property real animationSpeed: Math.max(0.5, Math.min(2.0, shellFile.adapter.animationSpeed ?? 1.0))
    function setAnimationSpeed(v: real): void { setAdapterReal(shellFile, "animationSpeed", v, 0.5, 2.0) }
    function animMs(ms: real): int {
        if (!animationsEnabled) return 0
        return Math.max(1, Math.round(ms / animationSpeed))
    }
    readonly property string clockPosition: (shellFile.adapter.clockPosition === "left" || shellFile.adapter.clockPosition === "right") ? shellFile.adapter.clockPosition : "center"
    // Clock label formats (right-click the clock to cycle):
    // full: "Monday 20:15" | short: "Mon 20:15" | date: "8th May 20:15" | timeOnly: "20:15"
    readonly property var clockFormats: ["full", "short", "date", "timeOnly"]
    readonly property string clockFormat: {
        let v = shellFile.adapter.clockFormat
        return clockFormats.indexOf(v) !== -1 ? v : "full"
    }
    function setClockFormat(v: string): void {
        let nv = clockFormats.indexOf(v) !== -1 ? v : "full"
        if ((shellFile.adapter.clockFormat || "full") === nv) return
        shellFile.adapter.clockFormat = nv
        shellFile.writeAdapter()
    }
    function toggleClockFormat(): void {
        let i = clockFormats.indexOf(clockFormat)
        setClockFormat(clockFormats[(i + 1) % clockFormats.length])
    }
    readonly property string workspacesPosition: (shellFile.adapter.workspacesPosition === "center" || shellFile.adapter.workspacesPosition === "right") ? shellFile.adapter.workspacesPosition : "left"

    // ---- Workspaces (Caelestia bar.workspaces port) ----
    // displayType replaces the old "workspaceStyle" (default/default2/m3):
    // shapes = MaterialShape indicators, numbers = workspace ordinals.
    readonly property var workspaceDisplayTypes: ["shapes", "numbers"]
    readonly property string workspaceDisplayType: workspaceDisplayTypes.indexOf(shellFile.adapter.workspaceDisplayType) !== -1 ? shellFile.adapter.workspaceDisplayType : "shapes"
    function setWorkspaceDisplayType(v: string): void {
        let nv = workspaceDisplayTypes.indexOf(v) !== -1 ? v : "shapes"
        if ((shellFile.adapter.workspaceDisplayType || "shapes") === nv) return
        shellFile.adapter.workspaceDisplayType = nv
        shellFile.writeAdapter()
    }
    readonly property int workspaceShown: Math.max(1, Math.min(20, Math.round(shellFile.adapter.workspaceShown !== undefined ? shellFile.adapter.workspaceShown : 5)))
    function setWorkspaceShown(v: int): void { setAdapterInt(shellFile, "workspaceShown", v, 1, 20) }
    readonly property bool workspaceActiveIndicator: shellFile.adapter.workspaceActiveIndicator !== false
    function setWorkspaceActiveIndicator(v: bool): void { setAdapterBool(shellFile, "workspaceActiveIndicator", v) }
    readonly property bool workspaceActiveTrail: shellFile.adapter.workspaceActiveTrail !== false
    function setWorkspaceActiveTrail(v: bool): void { setAdapterBool(shellFile, "workspaceActiveTrail", v) }
    readonly property bool workspaceOccupiedBg: shellFile.adapter.workspaceOccupiedBg === true
    function setWorkspaceOccupiedBg(v: bool): void { setAdapterBool(shellFile, "workspaceOccupiedBg", v) }
    readonly property bool workspaceShowUnoccupied: shellFile.adapter.workspaceShowUnoccupied !== false
    function setWorkspaceShowUnoccupied(v: bool): void { setAdapterBool(shellFile, "workspaceShowUnoccupied", v) }
    readonly property bool workspacePerMonitor: shellFile.adapter.workspacePerMonitor !== false
    function setWorkspacePerMonitor(v: bool): void { setAdapterBool(shellFile, "workspacePerMonitor", v) }
    readonly property bool workspaceShowWindows: shellFile.adapter.workspaceShowWindows !== false
    function setWorkspaceShowWindows(v: bool): void { setAdapterBool(shellFile, "workspaceShowWindows", v) }
    readonly property int workspaceMaxWindowIcons: Math.max(0, Math.min(20, Math.round(shellFile.adapter.workspaceMaxWindowIcons !== undefined ? shellFile.adapter.workspaceMaxWindowIcons : 5)))
    function setWorkspaceMaxWindowIcons(v: int): void { setAdapterInt(shellFile, "workspaceMaxWindowIcons", v, 0, 20) }
    readonly property var workspaceIgnoredTags: {
        let v = shellFile.adapter.workspaceIgnoredTags
        if (Array.isArray(v)) return v
        try {
            if (v && typeof v.length === "number") {
                let out = []
                for (let i = 0; i < v.length; i++) out.push("" + v[i])
                return out
            }
        } catch (e) {}
        return ["hide_in_bar", "xwl_popup"]
    }

    readonly property int workspaceSpacing: Math.max(0, Math.min(24, Math.round(shellFile.adapter.workspaceSpacing !== undefined ? shellFile.adapter.workspaceSpacing : 4)))
    function setWorkspaceSpacing(v: int): void { setAdapterInt(shellFile, "workspaceSpacing", v, 0, 24) }
    readonly property real workspaceScale: Math.max(0.5, Math.min(2.0, shellFile.adapter.workspaceScale ?? 1.0))
    function setWorkspaceScale(v: real): void { setAdapterReal(shellFile, "workspaceScale", v, 0.5, 2.0) }
    readonly property bool textBold: !!shellFile.adapter.textBold
    function setTextBold(v: bool): void { setAdapterBool(shellFile, "textBold", v) }
    // Bar labels sit one step above Normal (Google Sans Flex reads better
    // slightly heavier at bar sizes); the Bold Text toggle lifts them to Bold.
    readonly property int barTextWeight: textBold ? Font.Bold : Font.Medium
    // Focused/hovered bar items one step above the bar baseline.
    readonly property int barTextWeightEmphasis: textBold ? Font.Bold : Font.DemiBold
    readonly property real fontScale: Math.max(0.85, Math.min(1.25, shellFile.adapter.fontScale ?? 1.0))
    function setFontScale(v: real): void { setAdapterReal(shellFile, "fontScale", v, 0.85, 1.25) }
    function fs(px: real): int { return Math.max(1, Math.round(px * fontScale)) }
    // PERF: one-shot AA migration runs synchronously at startup (was an
    // 800ms Timer waking the event loop after boot for a file default).
    Component.onCompleted: {
        try {
            if (!shellFile.adapter.antialiasing
                    && shellFile.adapter.aaShapes
                    && shellFile.adapter.aaText
                    && shellFile.adapter.aaImageSmooth) {
                shellFile.adapter.aaShapes = false
                shellFile.adapter.aaText = false
                shellFile.adapter.aaImageSmooth = false
                shellFile.writeAdapter()
            }
        } catch (e) {}
    }
    readonly property bool shapesAa: shellFile.adapter.aaShapes !== undefined ? !!shellFile.adapter.aaShapes : true
    readonly property bool textAa: shellFile.adapter.aaText !== undefined ? !!shellFile.adapter.aaText : true
    readonly property bool textNative: shellFile.adapter.aaTextNative !== undefined ? !!shellFile.adapter.aaTextNative : true
    readonly property bool imageSmooth: shellFile.adapter.aaImageSmooth !== undefined ? !!shellFile.adapter.aaImageSmooth : true
    readonly property bool imageMipmap: shellFile.adapter.aaImageMipmap !== undefined ? !!shellFile.adapter.aaImageMipmap : false
    readonly property int textRenderType: textNative ? Text.NativeRendering : Text.QtRendering
    property int barEffectiveWidth: 30
    property int barEffectiveHeight: 30
    // Uniform taskbar module-card extent (2px inset per bar side): every
    // Background card renders at this cross-axis size regardless of module
    // content metrics, so the bar reads as one row of identical pills.
    readonly property int barCardExtent: Math.max(12, Math.round(Math.min(barEffectiveWidth, barEffectiveHeight) - 4))
    property var barAnchors: ({})
    property var _pendingAnchors: ({})
    property bool _anchorFlushScheduled: false
    function setBarAnchor(id: string, x: real, y: real, w: real, h: real): void {
        let key = (id || "").trim()
        if (key.length === 0) return
        let nx = Math.round(x); let ny = Math.round(y)
        let nw = Math.max(1, Math.round(w)); let nh = Math.max(1, Math.round(h))
        let cur = _pendingAnchors[key]
        if (cur === undefined) cur = barAnchors[key]
        if (cur && cur.x === nx && cur.y === ny && cur.w === nw && cur.h === nh) return
        _pendingAnchors[key] = {x: nx, y: ny, w: nw, h: nh}
        if (_anchorFlushScheduled) return
        _anchorFlushScheduled = true
        Qt.callLater(() => {
            _anchorFlushScheduled = false
            let pend = _pendingAnchors
            _pendingAnchors = ({})
            let next = {}
            for (let k in barAnchors) next[k] = barAnchors[k]
            let changed = false
            for (let k in pend) {
                let n = pend[k], c = next[k]
                if (!c || c.x !== n.x || c.y !== n.y || c.w !== n.w || c.h !== n.h) {
                    next[k] = n
                    changed = true
                }
            }
            if (changed) barAnchors = next
        })
    }
    function barAnchor(id: string): var {
        let a = barAnchors[(id || "").trim()]
        return a ? a : null
    }
    property int anchorRefreshTrigger: 0
    Timer {
        id: anchorRefreshDebounce
        interval: 80; repeat: false
        onTriggered: anchorRefreshTrigger++
    }
    // PERF: openPanel/toggleExclusive called refreshBarAnchors() synchronously
    // per toggle, invalidating every anchor consumer. Debounce to one bump.
    function refreshBarAnchors(): void { anchorRefreshDebounce.restart() }
    property bool polkitReady: false
    function setPolkitReady(v: bool): void {
        let nv = !!v
        if (polkitReady === nv) return
        polkitReady = nv
    }
    // ---- primary display (with fallback) ----
    // Shell windows (bar, menus, dialogs, OSD) live on ONE screen. Prefer
    // DP-1 so multi-head setups stay put, but fall back to the first
    // available screen so the shell still shows up when DP-1 doesn't
    // exist (single laptop display, renamed outputs, …).
    readonly property string preferredScreenName: "DP-1"
    readonly property string primaryScreenName: {
        try {
            let v = Quickshell.screens.values
            let vals = (v && typeof v.length === "number") ? v : []
            for (let i = 0; i < vals.length; i++) {
                if (vals[i] && vals[i].name === preferredScreenName) return preferredScreenName
            }
            if (vals.length > 0 && vals[0] && vals[0].name) return "" + vals[0].name
        } catch (e) {}
        return preferredScreenName
    }
    function isPrimaryScreen(screenObj: var): bool {
        try { return !!screenObj && ("" + screenObj.name) === primaryScreenName } catch (e) { return false }
    }
    property var barWindowRect: ({x: 0, y: 0, w: 0, h: 0})
    function setBarWindowRect(x: real, y: real, w: real, h: real): void {
        let nx = Math.round(x); let ny = Math.round(y)
        let nw = Math.max(0, Math.round(w)); let nh = Math.max(0, Math.round(h))
        let cur = barWindowRect
        if (cur && cur.x === nx && cur.y === ny && cur.w === nw && cur.h === nh) return
        barWindowRect = {x: nx, y: ny, w: nw, h: nh}
    }
    readonly property int barModuleSpacing: Math.max(-12, Math.min(24, shellFile.adapter.moduleSpacing !== undefined ? shellFile.adapter.moduleSpacing : 8))
    function setBarModuleSpacing(v: int): void { setAdapterInt(shellFile, "moduleSpacing", v, -12, 24) }
    readonly property int barEdgeDistance: Math.max(0, Math.min(600, shellFile.adapter.edgeDistance !== undefined ? shellFile.adapter.edgeDistance : 0))
    function setBarEdgeDistance(v: int): void { setAdapterInt(shellFile, "edgeDistance", v, 0, 600) }
    readonly property int barTopDistance: Math.max(0, Math.min(32, shellFile.adapter.topDistance !== undefined ? shellFile.adapter.topDistance : 0))
    function setBarTopDistance(v: int): void { setAdapterInt(shellFile, "topDistance", v, 0, 32) }
    readonly property int barContentPadding: Math.max(0, Math.min(32, shellFile.adapter.contentPadding !== undefined ? shellFile.adapter.contentPadding : 12))
    function setBarContentPadding(v: int): void { setAdapterInt(shellFile, "contentPadding", v, 0, 32) }
    // Taskbar behaviour (Caelestia Nexus bar.* mapping).
    readonly property bool barPersistent: shellFile.adapter.persistent !== false
    function setBarPersistent(v: bool): void { setAdapterBool(shellFile, "persistent", v) }
    readonly property bool barShowOnHover: shellFile.adapter.showOnHover !== false
    function setBarShowOnHover(v: bool): void { setAdapterBool(shellFile, "showOnHover", v) }
    readonly property int barDragThreshold: Math.max(0, Math.min(200, Math.round(shellFile.adapter.dragThreshold !== undefined ? shellFile.adapter.dragThreshold : 10)))
    function setBarDragThreshold(v: int): void { setAdapterInt(shellFile, "dragThreshold", v, 0, 200) }
    readonly property bool barScrollWorkspaces: shellFile.adapter.scrollWorkspaces !== false
    function setBarScrollWorkspaces(v: bool): void { setAdapterBool(shellFile, "scrollWorkspaces", v) }
    readonly property bool barScrollVolume: shellFile.adapter.scrollVolume !== false
    function setBarScrollVolume(v: bool): void { setAdapterBool(shellFile, "scrollVolume", v) }
    readonly property bool barScrollBrightness: shellFile.adapter.scrollBrightness !== false
    function setBarScrollBrightness(v: bool): void { setAdapterBool(shellFile, "scrollBrightness", v) }
    readonly property bool panelAccentBorder: !!shellFile.adapter.panelAccentBorder
    // Accent border on: accent outline. Off: no outline at all (fully
    // fused borderless panels, tray-menu style) — not even divider.
    readonly property color panelBorderColor: panelAccentBorder ? accent : "transparent"
    function setPanelAccentBorder(v: bool): void { setAdapterBool(shellFile, "panelAccentBorder", v) }
    readonly property real panelBlur: 0.0
    readonly property real panelBgAlpha: 1.0 - panelBlur * 0.48
    readonly property color panelBg: frostFill(bg, 0.48, 0.52)
    readonly property color panelSurface: frostFill(surface, 0.22, 0.80)
    function frostFill(c: color, strength: real, floorA: real): color {
        if (panelBlur <= 0.001) return c
        let a = 1.0 - panelBlur * strength
        if (a < floorA) a = floorA
        return withAlpha(c, a)
    }
    // Shell transparency: the Global > Transparency slider writes the
    // `opacity` value, so the bar and every panel window stay in sync. The
    // floor keeps panels readable while Umbriel's layer blur provides the
    // frosted backdrop.
    readonly property real panelTransparency: Math.max(0.0, Math.min(1.0, 1.0 - barOpacity))
    function setPanelTransparency(v: real): void {
        let t = Math.max(0.0, Math.min(1.0, Number(v)))
        if (isNaN(t)) return
        setBarOpacity(1.0 - t)
    }
    readonly property real panelWindowAlpha: Math.max(0.35, barOpacity)
    readonly property color panelWindowBg: withAlpha(bg, panelWindowAlpha)
    readonly property color panelWindowSurface: withAlpha(surface, panelWindowAlpha)
    // Panel content: follows the same transparency slider with a higher floor
    // so text and controls stay readable while the compositor blur shows
    // through the cards.
    readonly property real panelContentAlpha: Math.max(0.55, 1.0 - panelTransparency * 0.45)
    function panelFill(c: color): color { return withAlpha(c, panelContentAlpha) }
    readonly property color panelCard: panelFill(surface_container)
    readonly property color panelCardHigh: panelFill(surface_container_high)
    readonly property color panelCardHighest: panelFill(surface_container_highest)
    readonly property color panelCardLow: panelFill(surface_container_low)
    readonly property color panelCardLowest: panelFill(surface_container_lowest)

    property int volumeOsdTrigger: 0
    function triggerVolumeOsd(): void { volumeOsdTrigger++ }
    // Layout-switch OSD: the name is stored right before the trigger bump so
    // the OSD reads the fresh value in the same turn (trigger-counter pattern
    // like volumeOsdTrigger, with a payload since layouts aren't numeric).
    property int layoutOsdTrigger: 0
    property string layoutOsdName: ""
    function triggerLayoutOsd(name: string): void {
        layoutOsdName = ("" + (name || "")).trim()
        layoutOsdTrigger++
    }
    // Theme-switch OSD (preset/monet applies): label + detail, error marks a
    // failed apply. Same trigger-counter pattern as layoutOsdTrigger.
    property int themeOsdTrigger: 0
    property string themeOsdLabel: ""
    property string themeOsdDetail: ""
    property bool themeOsdError: false
    function triggerThemeOsd(label: string, detail: string, isError: bool): void {
        themeOsdLabel = ("" + (label || "")).trim()
        themeOsdDetail = ("" + (detail || "")).trim()
        themeOsdError = !!isError
        themeOsdTrigger++
    }

    property int appsRev: 0
    Timer {
        id: appsRevDebounce
        interval: 800; repeat: false
        onTriggered: root.appsRev++
    }
    function notifyAppsChanged(): void { appsRevDebounce.restart() }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { root.notifyAppsChanged() }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.notifyAppsChanged() }
        function onObjectInsertedPost() { root.notifyAppsChanged() }
        function onObjectRemovedPost() { root.notifyAppsChanged() }
    }
    // PERF: memoize desktop lookups per appsRev. desktopEntryFor() does
    // byId + heuristicLookup + hasThemeIcon per call; bar delegates called it
    // per delegate per appsRev change. Cache keyed on (rev + id).
    property var _desktopEntryCache: ({})
    property string _desktopEntryCacheRev: ""
    function desktopEntryFor(appId: string): var {
        let needle = (appId || "").trim()
        if (needle.length === 0) return null
        let revKey = appsRev + "|" + needle
        try {
            if (_desktopEntryCacheRev !== String(appsRev)) {
                _desktopEntryCache = ({})
                _desktopEntryCacheRev = String(appsRev)
            } else if (_desktopEntryCache[revKey] !== undefined) {
                return _desktopEntryCache[revKey]
            }
        } catch (e) {}
        let found = null
        try {
            let e = DesktopEntries.byId(needle)
            if (e) found = e
            else {
                let nodot = needle.replace(/\.desktop$/, "")
                if (nodot !== needle) { e = DesktopEntries.byId(nodot); if (e) found = e }
                if (!found) { e = DesktopEntries.heuristicLookup(needle); if (e) found = e }
            }
        } catch (err) {}
        try { _desktopEntryCache[revKey] = found } catch (e2) {}
        return found
    }
    property var _appIconCache: ({})
    property string _appIconCacheRev: ""
    function appIconFor(appId: string): string {
        let low = (appId || "").toLowerCase().trim()
        if (low.length === 0) return Quickshell.iconPath("application-x-executable")
        try {
            if (_appIconCacheRev !== String(appsRev)) {
                _appIconCache = ({})
                _appIconCacheRev = String(appsRev)
            } else if (_appIconCache[low] !== undefined) {
                return _appIconCache[low]
            }
        } catch (e) {}
        let out = ""
        try {
            let e = desktopEntryFor(low)
            if (e && e.icon) out = Quickshell.iconPath(e.icon)
        } catch (err) {}
        if (out === "") {
            try {
                if (Quickshell.hasThemeIcon(low)) out = Quickshell.iconPath(low)
            } catch (err2) {}
        }
        if (out === "") out = Quickshell.iconPath("application-x-executable")
        try { _appIconCache[low] = out } catch (e3) {}
        return out
    }

    FileView {
        id: dndFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/dnd.json"
        watchChanges: true; onFileChanged: debouncedReload(dndFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter { property bool enabled: false }
    }
    readonly property bool dndEnabled: !!dndFile.adapter.enabled
    function setDndEnabled(v: bool): void { setAdapterBool(dndFile, "enabled", v) }
    function toggleDnd(): void { setDndEnabled(!dndEnabled) }

    FileView {
        id: gamemodeFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/gamemode.json"
        watchChanges: true; onFileChanged: debouncedReload(gamemodeFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter { property bool enabled: false }
    }
    readonly property bool gamemodeEnabled: !!gamemodeFile.adapter.enabled
    function setGamemodeEnabled(v: bool): void { setAdapterBool(gamemodeFile, "enabled", v) }
    function toggleGamemode(): void { setGamemodeEnabled(!gamemodeEnabled) }

    FileView {
        id: notifFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/notifications.json"
        watchChanges: true; onFileChanged: debouncedReload(notifFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter { property int timeout: 5; property string position: "top-right" }
    }
    readonly property int notifTimeout: Math.max(0, Math.min(30, Math.round(notifFile.adapter.timeout !== undefined ? notifFile.adapter.timeout : 5)))
    readonly property string notifPosition: {
        let p = notifFile.adapter.position
        if (p === "top-left" || p === "top-center" || p === "top-right" || p === "bottom-left" || p === "bottom-center" || p === "bottom-right") return p
        return "top-right"
    }
    function setNotifTimeout(v: int): void {
        let c = Math.max(0, Math.min(30, Math.round(v)))
        if (Math.round(notifFile.adapter.timeout) === c) return
        notifFile.adapter.timeout = c
        notifFile.writeAdapter()
    }
    function setNotifPosition(pos: string): void {
        if (pos !== "top-left" && pos !== "top-center" && pos !== "top-right" && pos !== "bottom-left" && pos !== "bottom-center" && pos !== "bottom-right") return
        if (notifFile.adapter.position === pos) return
        notifFile.adapter.position = pos
        notifFile.writeAdapter()
    }

    // OSD screens (Volume + compositor layout switches + theme applies) share
    // one card and one duration; defaults match the previously hardcoded
    // 1200 ms.
    FileView {
        id: osdFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/osd.json"
        watchChanges: true; onFileChanged: debouncedReload(osdFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property bool volumeEnabled: true
            property bool layoutEnabled: true
            property bool themeEnabled: true
            property int duration: 1200
        }
    }
    readonly property bool osdVolumeEnabled: osdFile.adapter.volumeEnabled !== undefined ? !!osdFile.adapter.volumeEnabled : true
    readonly property bool osdLayoutEnabled: osdFile.adapter.layoutEnabled !== undefined ? !!osdFile.adapter.layoutEnabled : true
    readonly property bool osdThemeEnabled: osdFile.adapter.themeEnabled !== undefined ? !!osdFile.adapter.themeEnabled : true
    readonly property int osdDuration: Math.max(500, Math.min(5000, Math.round(osdFile.adapter.duration !== undefined ? osdFile.adapter.duration : 1200)))
    function setOsdVolumeEnabled(v: bool): void { setAdapterBool(osdFile, "volumeEnabled", v) }
    function setOsdLayoutEnabled(v: bool): void { setAdapterBool(osdFile, "layoutEnabled", v) }
    function setOsdThemeEnabled(v: bool): void { setAdapterBool(osdFile, "themeEnabled", v) }
    function setOsdDuration(v: int): void { setAdapterInt(osdFile, "duration", v, 500, 5000) }

    FileView {
        id: calendarFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/calendar.json"
        watchChanges: true; onFileChanged: debouncedReload(calendarFile); blockLoading: true; printErrors: false
        // NOTE: weekStartDay is owned by CalendarPanel — it is
        // declared here only so layout writes never drop it from the file.
        adapter: JsonAdapter { property string weekStartDay: "sunday"; property string notifSide: "left" }
    }
    // Which side of the calendar popup holds notifications ("left"|"right").
    readonly property bool calendarNotifLeft: calendarFile.adapter.notifSide !== "right"

    // ---- Launcher (Panels > Launcher; bar OS icon + app search popup) ----
    FileView {
        id: launcherFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/launcher.json"
        watchChanges: true; onFileChanged: debouncedReload(launcherFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property int width: 520
            property int height: 480
            property int maxResults: 50
            property bool showDescriptions: true
            property string menuPrefix: "!"
        }
    }
    readonly property int launcherWidth: Math.max(360, Math.min(900, Math.round(launcherFile.adapter.width !== undefined ? launcherFile.adapter.width : 520)))
    function setLauncherWidth(v: int): void { setAdapterInt(launcherFile, "width", v, 360, 900) }
    readonly property int launcherHeight: Math.max(280, Math.min(900, Math.round(launcherFile.adapter.height !== undefined ? launcherFile.adapter.height : 480)))
    function setLauncherHeight(v: int): void { setAdapterInt(launcherFile, "height", v, 280, 900) }
    readonly property int launcherMaxResults: Math.max(5, Math.min(200, Math.round(launcherFile.adapter.maxResults !== undefined ? launcherFile.adapter.maxResults : 50)))
    function setLauncherMaxResults(v: int): void { setAdapterInt(launcherFile, "maxResults", v, 5, 200) }
    readonly property bool launcherShowDescriptions: launcherFile.adapter.showDescriptions !== false
    function setLauncherShowDescriptions(v: bool): void { setAdapterBool(launcherFile, "showDescriptions", v) }
    // Leading token that switches the launcher into the extra-menu list
    // (`!` by default: `!wall` -> Wallpaper). Free-form, but it must work as
    // a typed prefix: no whitespace, 1-4 characters.
    readonly property string launcherMenuPrefix: {
        let p = launcherFile.adapter.menuPrefix
        if (typeof p !== "string") return "!"
        p = p.trim()
        if (p.length === 0 || p.length > 4 || /\s/.test(p)) return "!"
        return p
    }
    function setLauncherMenuPrefix(v: string): void {
        let p = ("" + (v === undefined || v === null ? "" : v)).trim()
        if (p.length === 0 || p.length > 4 || /\s/.test(p)) return
        if (launcherFile.adapter.menuPrefix === p) return
        launcherFile.adapter.menuPrefix = p
        launcherFile.writeAdapter()
    }

    // ---- Screenshot UI (Panels > Screenshot UI; overlays/ScreenshotUI.qml) --
    FileView {
        id: screenshotFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/screenshot.json"
        watchChanges: true; onFileChanged: debouncedReload(screenshotFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property string defaultMode: "region"
            property bool includeCursor: false
            property bool copyToClipboard: true
            property bool notify: true
            property string saveDir: ""
        }
    }
    readonly property var screenshotModes: ["region", "window", "fullscreen"]
    readonly property string screenshotDefaultMode: {
        let m = screenshotFile.adapter.defaultMode
        return screenshotModes.indexOf(m) !== -1 ? m : "region"
    }
    function setScreenshotDefaultMode(m: string): void {
        if (screenshotModes.indexOf(m) === -1) return
        if (screenshotFile.adapter.defaultMode === m) return
        screenshotFile.adapter.defaultMode = m
        screenshotFile.writeAdapter()
    }
    readonly property bool screenshotIncludeCursor: screenshotFile.adapter.includeCursor === true
    function setScreenshotIncludeCursor(v: bool): void { setAdapterBool(screenshotFile, "includeCursor", v) }
    readonly property bool screenshotCopyToClipboard: screenshotFile.adapter.copyToClipboard !== false
    function setScreenshotCopyToClipboard(v: bool): void { setAdapterBool(screenshotFile, "copyToClipboard", v) }
    readonly property bool screenshotNotify: screenshotFile.adapter.notify !== false
    function setScreenshotNotify(v: bool): void { setAdapterBool(screenshotFile, "notify", v) }
    // Empty = the default (~/Pictures/Screenshots). `~` is expanded by
    // scripts/screenshot.sh, not here, so the stored value stays portable.
    readonly property string screenshotSaveDir: {
        let d = screenshotFile.adapter.saveDir
        if (typeof d !== "string") return ""
        d = d.trim()
        return d.length > 256 ? "" : d
    }
    function setScreenshotSaveDir(v: string): void {
        let d = ("" + (v === undefined || v === null ? "" : v)).trim()
        if (d.length > 256 || /[\r\n]/.test(d)) return
        if (screenshotFile.adapter.saveDir === d) return
        screenshotFile.adapter.saveDir = d
        screenshotFile.writeAdapter()
    }

    readonly property var barModuleIds: ["launcher", "workspaces", "activewindow", "clock", "systemtray", "controlcenter"]
    function barNormalizeSection(s: string): string {
        let v = (s || "").trim().toLowerCase()
        if (v === "left") return "left"
        if (v === "center") return "center"
        if (v === "right") return "right"
        if (v === "twofifths" || v === "2/5" || v === "two-fifths" || v === "two_fifths"
                || v === "leftcenter" || v === "left-center" || v === "left_center"
                || v === "centerleft" || v === "center-left" || v === "center_left") return "twofifths"
        if (v === "fourfifths" || v === "4/5" || v === "four-fifths" || v === "four_fifths"
                || v === "rightcenter" || v === "right-center" || v === "right_center"
                || v === "centerright" || v === "center-right" || v === "center_right") return "fourfifths"
        return ""
    }
    FileView {
        id: barLayoutFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/bar_layout.json"
        watchChanges: true; onFileChanged: debouncedReload(barLayoutFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property var left: ["workspaces"]
            property var twofifths: []
            property var center: ["clock", "updates"]
            property var fourfifths: []
            property var right: []
            property var hidden: []
            property int version: 0
        }
        Component.onCompleted: barMigrateTimer.restart()
    }
    // PERF: one-shot migration fires once at 250ms (was 2s + re-arm = 2
    // wakeups for a version check). No repeat cost after first boot.
    Timer {
        id: barMigrateTimer
        interval: 250
        repeat: false
        onTriggered: {
            if ((barLayoutFile.adapter.version || 0) >= 2) return
            root.migrateBarLayout()
        }
    }
    function barDefaultLayout(): var {
        return { left: ["launcher", "workspaces", "activewindow"], twofifths: [], center: ["clock"], fourfifths: [], right: ["controlcenter", "systemtray"] }
    }
    function toStrArray(v: var): var {
        let out = []
        try {
            if (v === null || v === undefined) return out
            if (Array.isArray(v)) {
                for (let i = 0; i < v.length; i++) if (typeof v[i] === "string") out.push(v[i])
                return out
            }
            if (typeof v.length === "number") {
                for (let i = 0; i < v.length; i++) { let e = v[i]; if (typeof e === "string") out.push(e) }
            }
        } catch (e) {}
        return out
    }
    function cleanBarIds(arr: var): var {
        let out = []
        try {
            let ids = toStrArray(arr)
            for (let i = 0; i < ids.length; i++) {
                let id = ids[i]
                if (barModuleIds.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
            }
        } catch (e) {}
        return out
    }
    function barHiddenIds(): var {
        let out = []
        try {
            let ids = toStrArray(barLayoutFile.adapter.hidden)
            for (let i = 0; i < ids.length; i++) {
                let id = ids[i]
                if (barModuleIds.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
            }
        } catch (e) {}
        return out
    }
    function isBarModuleHidden(id: string): bool { return barHiddenIds().indexOf(id) >= 0 }
    function barVisibleIds(): var {
        let l = barLayout()
        return l.left.concat(l.twofifths, l.center, l.fourfifths, l.right)
    }
    function hideBarModule(id: string): string {
        if (barModuleIds.indexOf(id) < 0) return "err: unknown id " + id
        if (isBarModuleHidden(id)) return "ok: " + id + " already hidden"
        let vis = barVisibleIds()
        if (vis.indexOf(id) >= 0 && vis.length <= 1) return "err: cannot hide last module"
        let h = barHiddenIds()
        h.push(id)
        barLayoutFile.adapter.hidden = h
        barLayoutFile.writeAdapter()
        return "ok: hidden " + id
    }
    function showBarModule(id: string): string {
        if (barModuleIds.indexOf(id) < 0) return "err: unknown id " + id
        let h = barHiddenIds()
        let i = h.indexOf(id)
        if (i < 0) return "ok: " + id + " already visible"
        h.splice(i, 1)
        barLayoutFile.adapter.hidden = h
        barLayoutFile.writeAdapter()
        return "ok: visible " + id
    }
    function barLayout(): var {
        let hidden = barHiddenIds()
        let notHidden = (arr) => arr.filter(id => hidden.indexOf(id) < 0)
        let l = notHidden(cleanBarIds(barLayoutFile.adapter.left))
        let t = notHidden(cleanBarIds(barLayoutFile.adapter.twofifths))
        let c = notHidden(cleanBarIds(barLayoutFile.adapter.center))
        let f = notHidden(cleanBarIds(barLayoutFile.adapter.fourfifths))
        let r = notHidden(cleanBarIds(barLayoutFile.adapter.right))
        let seen = {}
        let dup = (arr) => arr.filter(id => { if (seen[id]) return false; seen[id] = true; return true })
        l = dup(l); t = dup(t); c = dup(c); f = dup(f); r = dup(r)
        let d = barDefaultLayout()
        for (let i = 0; i < barModuleIds.length; i++) {
            let id = barModuleIds[i]
            if (!seen[id] && hidden.indexOf(id) < 0) {
                if (d.left.indexOf(id) >= 0) l.push(id)
                else if (d.center.indexOf(id) >= 0) c.push(id)
                else r.push(id)
                seen[id] = true
            }
        }
        return { left: l, twofifths: t, center: c, fourfifths: f, right: r }
    }
    function barLayoutString(): string {
        let l = barLayout()
        return "left=" + l.left.join(",") + " twofifths=" + l.twofifths.join(",") + " center=" + l.center.join(",") + " fourfifths=" + l.fourfifths.join(",") + " right=" + l.right.join(",")
    }
    readonly property var barLayoutCached: barLayout()
    readonly property var barLayoutLeft: barLayoutCached.left
    readonly property var barLayoutTwoFifths: barLayoutCached.twofifths
    readonly property var barLayoutCenter: barLayoutCached.center
    readonly property var barLayoutFourFifths: barLayoutCached.fourfifths
    readonly property var barLayoutRight: barLayoutCached.right
    readonly property var barModuleMetaList: [
        {id: "launcher", title: "Launcher", icon: "󰍉"},
        {id: "workspaces", title: "Workspaces", icon: ""},
        {id: "activewindow", title: "Active Window", icon: "󰍹"},
        {id: "clock", title: "Clock", icon: ""},
        {id: "systemtray", title: "System Tray", icon: "󰆍"},
        {id: "controlcenter", title: "Control Center", icon: "󰘮"}
    ]
    function setBarLayout(left: var, twofifths: var, center: var, fourfifths: var, right: var): void {
        if (right === undefined && fourfifths === undefined) {
            let legacyR = center
            let legacyC = twofifths
            let l0 = cleanBarIds(left), c0 = cleanBarIds(legacyC), r0 = cleanBarIds(legacyR)
            let t0 = cleanBarIds(barLayoutFile.adapter.twofifths)
            let f0 = cleanBarIds(barLayoutFile.adapter.fourfifths)
            setBarLayout(l0, t0, c0, f0, r0)
            return
        }
        let l = cleanBarIds(left), t = cleanBarIds(twofifths), c = cleanBarIds(center), f = cleanBarIds(fourfifths), r = cleanBarIds(right)
        let hidden = barHiddenIds()
        let seen = {}
        let all = [l, t, c, f, r]
        for (let s = 0; s < 5; s++) all[s] = all[s].filter(id => { if (seen[id] || hidden.indexOf(id) >= 0) return false; seen[id] = true; return true })
        for (let i = 0; i < barModuleIds.length; i++) {
            let id = barModuleIds[i]
            if (!seen[id] && hidden.indexOf(id) < 0) { l.push(id); seen[id] = true }
        }
        if (hidden.length > 0) {
            let old = [cleanBarIds(barLayoutFile.adapter.left), cleanBarIds(barLayoutFile.adapter.twofifths), cleanBarIds(barLayoutFile.adapter.center), cleanBarIds(barLayoutFile.adapter.fourfifths), cleanBarIds(barLayoutFile.adapter.right)]
            let fresh = [l, t, c, f, r]
            for (let h = 0; h < hidden.length; h++) {
                let id = hidden[h]
                for (let s = 0; s < 5; s++) {
                    let oi = old[s].indexOf(id)
                    if (oi >= 0) { fresh[s].splice(Math.max(0, Math.min(oi, fresh[s].length)), 0, id); break }
                }
            }
        }
        barLayoutFile.adapter.left = l
        barLayoutFile.adapter.twofifths = t
        barLayoutFile.adapter.center = c
        barLayoutFile.adapter.fourfifths = f
        barLayoutFile.adapter.right = r
        if ((barLayoutFile.adapter.version || 0) < 1) barLayoutFile.adapter.version = 1
        barLayoutFile.writeAdapter()
    }
    function barSectionOf(id: string): string {
        let l = barLayout()
        if (l.left.indexOf(id) >= 0) return "left"
        if (l.twofifths.indexOf(id) >= 0) return "twofifths"
        if (l.center.indexOf(id) >= 0) return "center"
        if (l.fourfifths.indexOf(id) >= 0) return "fourfifths"
        if (l.right.indexOf(id) >= 0) return "right"
        return ""
    }
    function barSectionArray(l: var, section: string): var {
        let s = barNormalizeSection(section)
        if (s === "left") return l.left
        if (s === "twofifths") return l.twofifths
        if (s === "center") return l.center
        if (s === "fourfifths") return l.fourfifths
        return l.right
    }
    function moveBarWidget(id: string, section: string, index: int): string {
        if (barModuleIds.indexOf(id) < 0) return "err: unknown id " + id
        let sec = barNormalizeSection(section)
        if (sec === "") return "err: section must be left|twofifths|center|fourfifths|right (aliases 2/5, 4/5)"
        if (isBarModuleHidden(id)) showBarModule(id)
        let l = barLayout()
        let from = barSectionOf(id)
        if (from.length > 0) {
            let arr = barSectionArray(l, from)
            let fi = arr.indexOf(id)
            if (fi >= 0) arr.splice(fi, 1)
        }
        let dst = barSectionArray(l, sec)
        let idx = Math.max(0, Math.min(dst.length, Math.round(index)))
        dst.splice(idx, 0, id)
        setBarLayout(l.left, l.twofifths, l.center, l.fourfifths, l.right)
        return "ok: " + id + " -> " + sec + "[" + idx + "] (" + barLayoutString() + ")"
    }
    function resetBarLayout(): void {
        barLayoutFile.adapter.hidden = []
        let d = barDefaultLayout()
        setBarLayout(d.left, d.twofifths, d.center, d.fourfifths, d.right)
    }
    function migrateBarLayout(): void {
        try {
            let v = barLayoutFile.adapter.version || 0
            if (v < 1) {
                let l = { left: [], twofifths: [], center: [], fourfifths: [], right: [] }
                let ws = workspacesPosition
                if (ws === "center") l.center.push("workspaces")
                else if (ws === "right") l.right.push("workspaces")
                else l.left.push("workspaces")
                let cp = clockPosition
                if (cp === "left") l.left.push("clock")
                else if (cp === "right") l.right.push("clock")
                else l.center.push("clock")
                if (l.right.indexOf("systemtray") < 0) l.right.unshift("systemtray")
                barLayoutFile.adapter.left = l.left
                barLayoutFile.adapter.twofifths = l.twofifths
                barLayoutFile.adapter.center = l.center
                barLayoutFile.adapter.fourfifths = l.fourfifths
                barLayoutFile.adapter.right = l.right
                barLayoutFile.adapter.version = 1
                barLayoutFile.writeAdapter()
                v = 1
            }
            // v1 -> v2: the OS launcher icon joins at the left end, unless the
            // id is already placed (or deliberately hidden) somewhere.
            if (v < 2) {
                let l = cleanBarIds(barLayoutFile.adapter.left)
                let t = cleanBarIds(barLayoutFile.adapter.twofifths)
                let c = cleanBarIds(barLayoutFile.adapter.center)
                let f = cleanBarIds(barLayoutFile.adapter.fourfifths)
                let r = cleanBarIds(barLayoutFile.adapter.right)
                let present = l.concat(t, c, f, r).indexOf("launcher") >= 0 || barHiddenIds().indexOf("launcher") >= 0
                if (!present) l.unshift("launcher")
                barLayoutFile.adapter.left = l
                barLayoutFile.adapter.version = 2
                barLayoutFile.writeAdapter()
            }
        } catch (e) {}
    }

    // Generic per-module label visibility (future-proof).
    // Modules with their own service storage (volume/showPct,
    // vitals/showLabels, clock/clockFormat) keep it for backwards
    // compat. Everything else — updates count, activewindow title, and any
    // future module with a text label — uses this central map so a new
    // widget only needs:
    //   visible: Theme.barLabelVisible("<moduleId>") && <hasLabelData>
    //   function toggleLabel(): void { Theme.toggleBarLabel("<moduleId>") }
    // and right-click toggling works with zero BarModule changes.
    FileView {
        id: barLabelFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/bar_labels.json"
        watchChanges: true; onFileChanged: debouncedReload(barLabelFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property var labels: ({})
        }
    }
    function barLabelVisible(id: string): bool {
        try {
            let key = (id || "").trim()
            if (key.length === 0) return false
            let m = barLabelFile.adapter.labels
            if (m && m[key] !== undefined) return m[key] !== false
            return true
        } catch (e) { return true }
    }
    function setBarLabelVisible(id: string, v: bool): void {
        let key = (id || "").trim()
        if (key.length === 0) return
        let nv = !!v
        if (barLabelVisible(key) === nv) {
            // Still persist explicit false so the choice survives restarts
            // even when the default would also be visible.
            try {
                let cur = barLabelFile.adapter.labels
                if (cur && cur[key] !== undefined) return
            } catch (e) {}
            if (nv) return
        }
        let m = {}
        try {
            let cur = barLabelFile.adapter.labels
            if (cur && typeof cur === "object") {
                for (let k in cur) m[k] = cur[k]
            }
        } catch (e) {}
        m[key] = nv
        barLabelFile.adapter.labels = m
        barLabelFile.writeAdapter()
    }
    function toggleBarLabel(id: string): void {
        let key = (id || "").trim()
        if (key.length === 0) return
        setBarLabelVisible(key, !barLabelVisible(key))
    }

    // Per-module taskbar backgrounds (Settings -> Panels -> Taskbar ->
    // <component> > Background). Same keyed-map pattern as bar_labels, but
    // opt-in: an unset module renders without its own card. Workspaces is
    // the exception — its pill predates the option and stays the default so
    // the bar keeps its familiar look until the user turns it off.
    FileView {
        id: barBackgroundFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/bar_backgrounds.json"
        watchChanges: true; onFileChanged: debouncedReload(barBackgroundFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property var backgrounds: ({})
            property bool merge: false
        }
    }
    // Merge adjacent module cards into one seamless run (Settings -> Panels ->
    // Taskbar > Components > Merge background). Only meaningful while at
    // least one module background is on.
    readonly property bool barBackgroundMerge: barBackgroundFile.adapter.merge === true
    function setBarBackgroundMerge(v: bool): void {
        setAdapterBool(barBackgroundFile, "merge", v)
    }
    function barBackgroundEnabled(id: string): bool {
        try {
            let key = (id || "").trim()
            if (key.length === 0) return false
            // The launcher (OS icon) card is synced to the workspaces card:
            // one background setting drives both, and merge mode joins the
            // two adjacent left-zone modules into one run automatically.
            if (key === "launcher") key = "workspaces"
            let m = barBackgroundFile.adapter.backgrounds
            if (m && m[key] !== undefined) return m[key] !== false
            return key === "workspaces"
        } catch (e) { return ("" + (id || "")).trim() === "workspaces" }
    }
    function setBarBackgroundEnabled(id: string, v: bool): void {
        let key = (id || "").trim()
        if (key.length === 0) return
        let nv = !!v
        // Persist explicit true/false so the choice survives restarts.
        try {
            let cur = barBackgroundFile.adapter.backgrounds
            if (cur && cur[key] !== undefined && (cur[key] !== false) === nv) return
        } catch (e) {}
        let m = {}
        try {
            let cur = barBackgroundFile.adapter.backgrounds
            if (cur && typeof cur === "object") {
                for (let k in cur) m[k] = cur[k]
            }
        } catch (e) {}
        m[key] = nv
        barBackgroundFile.adapter.backgrounds = m
        barBackgroundFile.writeAdapter()
    }

    FileView {
        id: trayFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/tray.json"
        watchChanges: true; onFileChanged: debouncedReload(trayFile); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property var pinned: []
            property var hidden: []
        }
    }
    function trayPinnedIds(): var { return toStrArray(trayFile.adapter.pinned) }
    function trayHiddenIds(): var { return toStrArray(trayFile.adapter.hidden) }
    function isTrayPinned(id: string): bool { return trayPinnedIds().indexOf((id || "").toString()) >= 0 }
    function isTrayHidden(id: string): bool { return trayHiddenIds().indexOf((id || "").toString()) >= 0 }
    function setTrayPinned(id: string, pinned: bool): void {
        let key = (id || "").toString()
        if (key.length === 0) return
        let p = trayPinnedIds()
        let i = p.indexOf(key)
        if (pinned && i < 0) p.push(key)
        else if (!pinned && i >= 0) p.splice(i, 1)
        else return
        trayFile.adapter.pinned = p
        if (pinned) setTrayHidden(key, false)
        trayFile.writeAdapter()
    }
    function setTrayHidden(id: string, hidden: bool): void {
        let key = (id || "").toString()
        if (key.length === 0) return
        let h = trayHiddenIds()
        let i = h.indexOf(key)
        if (hidden && i < 0) h.push(key)
        else if (!hidden && i >= 0) h.splice(i, 1)
        else return
        trayFile.adapter.hidden = h
        if (hidden) {
            let p = trayPinnedIds()
            let pi = p.indexOf(key)
            if (pi >= 0) { p.splice(pi, 1); trayFile.adapter.pinned = p }
        }
        trayFile.writeAdapter()
    }
    function toggleTrayPinned(id: string): void { setTrayPinned(id, !isTrayPinned(id)) }
    function toggleTrayHidden(id: string): void { setTrayHidden(id, !isTrayHidden(id)) }

    function withAlpha(c: color, a: real): color { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property int animFast: animMs(150)
    readonly property int animNormal: animMs(200)
    readonly property int animSlow: animMs(300)
    readonly property int animEmph: animMs(400)
    readonly property int animStagger: animMs(30)
    readonly property var curveEmphasized: [0.2, 0, 0, 1, 1, 1]
    readonly property var curveEmphasizedDecelerate: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var curveEmphasizedAccelerate: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property real hoverScale: 1.06
    readonly property real pressScale: 0.94

    // ---- Caelestia-expressive motion tokens (caelestia-dots/shell) ----
    // Durations match AnimDurationTokens; curves match AnimCurves. Kept
    // separate from the legacy animFast/animNormal aliases so existing
    // call-sites keep working while new ui/Anim primitives bind here.
    // All durations collapse to 0 when animations are disabled.
    readonly property int durSmall: animMs(200)
    readonly property int durNormal: animMs(400)
    readonly property int durLarge: animMs(600)
    readonly property int durExtraLarge: animMs(1000)
    readonly property int durFastSpatial: animMs(350)
    readonly property int durDefaultSpatial: animMs(500)
    readonly property int durSlowSpatial: animMs(650)
    readonly property int durFastEffects: animMs(150)
    readonly property int durDefaultEffects: animMs(200)
    readonly property int durSlowEffects: animMs(300)
    // BezierSpline control points (6 values per cubic segment). The
    // emphasized curve is two segments (12 values), everything else one.
    readonly property var curveStandard: [0.2, 0, 0, 1, 1, 1]
    readonly property var curveStandardAccel: [0.3, 0, 1, 1, 1, 1]
    readonly property var curveStandardDecel: [0, 0, 0, 1, 1, 1]
    readonly property var curveEmphasizedFull: [0.05, 0, 0.133333, 0.06, 0.166667, 0.4, 0.208333, 0.82, 0.25, 1, 1, 1]
    readonly property var curveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
    readonly property var curveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
    readonly property var curveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
    readonly property var curveFastEffects: [0.31, 0.94, 0.34, 1, 1, 1]
    readonly property var curveDefaultEffects: [0.34, 0.8, 0.34, 1, 1, 1]
    readonly property var curveSlowEffects: [0.34, 0.88, 0.34, 1, 1, 1]
    // Type ids mirror Caelestia Anim.Type so ports read 1:1.
    readonly property int animTypeStandardSmall: 0
    readonly property int animTypeStandard: 1
    readonly property int animTypeStandardLarge: 2
    readonly property int animTypeStandardExtraLarge: 3
    readonly property int animTypeEmphasizedSmall: 4
    readonly property int animTypeEmphasized: 5
    readonly property int animTypeEmphasizedLarge: 6
    readonly property int animTypeEmphasizedExtraLarge: 7
    readonly property int animTypeFastSpatial: 8
    readonly property int animTypeDefaultSpatial: 9
    readonly property int animTypeSlowSpatial: 10
    readonly property int animTypeFastEffects: 11
    readonly property int animTypeDefaultEffects: 12
    readonly property int animTypeSlowEffects: 13
    function animDurationFor(type: int): int {
        switch (type) {
        case animTypeStandardSmall: return durSmall
        case animTypeStandard: return durNormal
        case animTypeStandardLarge: return durLarge
        case animTypeStandardExtraLarge: return durExtraLarge
        case animTypeEmphasizedSmall: return durSmall
        case animTypeEmphasized: return durNormal
        case animTypeEmphasizedLarge: return durLarge
        case animTypeEmphasizedExtraLarge: return durExtraLarge
        case animTypeFastSpatial: return durFastSpatial
        case animTypeDefaultSpatial: return durDefaultSpatial
        case animTypeSlowSpatial: return durSlowSpatial
        case animTypeFastEffects: return durFastEffects
        case animTypeDefaultEffects: return durDefaultEffects
        case animTypeSlowEffects: return durSlowEffects
        default: return durNormal
        }
    }
    function animCurveFor(type: int): var {
        switch (type) {
        case animTypeFastSpatial: return curveFastSpatial
        case animTypeDefaultSpatial: return curveDefaultSpatial
        case animTypeSlowSpatial: return curveSlowSpatial
        case animTypeFastEffects: return curveFastEffects
        case animTypeDefaultEffects: return curveDefaultEffects
        case animTypeSlowEffects: return curveSlowEffects
        case animTypeEmphasizedSmall:
        case animTypeEmphasized:
        case animTypeEmphasizedLarge:
        case animTypeEmphasizedExtraLarge: return curveEmphasizedFull
        default: return curveStandard
        }
    }

    // ---- M3 transition patterns (m3.material.io/styles/motion/transitions) --
    // Fade through: 300ms emphasized, outgoing fades over the first 35% of
    // the run, incoming over the last 65% and scales 92% -> 100%.
    // Shared axis: 400ms emphasized, 30dp slide on X/Y or 80%/110% scale on
    // Z (forward: in 0.8->1, out 1->1.1; backward mirrored).
    // The curve is the M3 emphasized token: cubic-bezier(0.2, 0, 0, 1).
    readonly property int durMotionFadeThrough: animMs(300)
    readonly property int durMotionSharedAxis: animMs(400)
    readonly property var curveMotion: curveEmphasized
    readonly property real motionSlideDistance: 30
    readonly property real motionFadeThroughScale: 0.92
    readonly property real motionAxisZScaleIn: 0.8
    readonly property real motionAxisZScaleOut: 1.1
    // Fade-through thresholds (Material FadeThroughProvider: 0.35).
    readonly property real motionFadeThroughExit: 0.35
    readonly property real motionFadeThroughEnter: 0.65
    // Indeterminate progress (ambient motion; period never collapses — the
    // animator itself is gated on animationsEnabled instead). Speed-scaled
    // so the spinner matches the rest of the shell.
    readonly property int durSpinner: Math.max(1, Math.round(1200 / animationSpeed))

    readonly property int panelAnimFade: durDefaultEffects
    // Panel slide rides DefaultSpatial (500ms): panels travel their full
    // height out from behind the bar edge (Caelestia drawer offsetScale
    // timing) — FastSpatial would rush the ~400px emerge.
    readonly property int panelAnimSlide: durDefaultSpatial
    readonly property int panelAnimScale: durNormal
    readonly property int panelAnimExit: durFastEffects
    // Panel open (bar drawers + menu island + cross-panel glide): the
    // DefaultSpatial attack with the overshoot cut back (control y 1.21 ->
    // 1.12, ~1.4% -> ~0.4% past target). Full-height panel travel made the
    // expressive overshoot read as a bounce; this lets the drawer settle.
    // For no overshoot at all use [0.38, 1, 0.22, 1, 1, 1].
    readonly property var curvePanelOpen: [0.38, 1.12, 0.22, 1, 1, 1]
    // Panel close (CaelestiaPopout curtain): shorter than the open run and
    // non-overshooting (the open curve's y > 1 would drive frameAxis
    // negative past the bar edge). Emphasized-decelerate leaves immediately
    // and lands gently, so dismissal reads as a snap back instead of a
    // second full-length run. Must stay below panelHideDelay.
    readonly property int panelAnimClose: durFastSpatial
    readonly property var curvePanelClose: curveEmphasizedDecelerate
    // Windows/loaders stay mapped until the popout close run has finished.
    // A plain close lands in panelAnimClose; a morph handoff can hold the
    // outgoing card for durPanelMorphHold before it fades out over
    // durDefaultEffects (the content lead runs inside that hold on the
    // shared departure clock). Cover the worst case or the surface would be
    // torn down mid-run.
    readonly property int panelHideDelay: animationsEnabled
        ? Math.max(panelAnimClose, durPanelMorphHold + durDefaultEffects) + 20
        : 0
    // Cross-panel morph (ui/PanelMorph + ui/CaelestiaPopout): opening a bar
    // panel while another is open hands the outgoing card's pose to the
    // incoming popout, which glides from there to its own settled pose.
    // Hold = how long the outgoing card waits for the incoming surface to
    // render before it falls back to its normal close run; it must stay
    // well below panelHideDelay, because the outgoing window unmaps then.
    readonly property int durPanelMorph: animationsEnabled ? durDefaultSpatial : 0
    readonly property var curvePanelMorph: curvePanelOpen
    readonly property int durPanelMorphHold: animMs(300)
    // Content choreography of a morph (CaelestiaPopout). The cards never
    // blend (two translucent layer surfaces wash out over the desktop and
    // flicker): the incoming card stays hidden while the outgoing content
    // leads — it fades/shifts out over panelMorphContentOut — then the
    // incoming card is swapped in at the exact outgoing pose (invisible,
    // the cards match there) and the glide starts. Its content arrives
    // after panelMorphContentDelay over panelMorphContentIn. Shift/scale
    // are the shared-axis travel of the content for drill-in/out switches.
    // The outgoing content starts leaving the instant the switch begins
    // (PanelMorph.leftAt); the incoming side waits out only the remainder of
    // panelMorphLead, so surface-map latency never stacks a full pause.
    readonly property int panelMorphLead: durFastEffects
    readonly property int panelMorphContentOut: durFastEffects
    readonly property int panelMorphContentDelay: panelMorphLead
    readonly property int panelMorphContentIn: durDefaultEffects
    readonly property real panelMorphShift: 14
    readonly property real panelMorphScale: 0.04
    // Attached-bar morph: dropdown boxes sit flush with the bar edge
    // instead of floating detached below it. Must stay 0: the panel
    // windows are placed on the compositor's remaining area (bar bottom =
    // window top), so any overlap is clipped and only wastes the border.
    // The rounded top corners still merge into the bar for the morph look.
    readonly property int panelAttachOverlap: 0
    readonly property int panelSlideOffset: 18
    // Overlay drill-ins (control center sub-panels: audio/bluetooth/updates)
    // settle this far below the CC card's top edge. The CC stays mapped and
    // dimmed behind them, so its header + first tile row (10 margin + 42
    // header + 12 spacing + 72 tile = 136) remain visible above the card.
    readonly property int panelDrillInInset: 140
}
