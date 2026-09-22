pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../style/themes"

// HyprlandService — Hyprland integration for the bar's Workspaces and
// ActiveWindow widgets plus the shell's compositor-aware features
// (fullscreen collapse, keyboard/tiling-layout OSD, appearance settings).
//
// Data/actions used here (all through Quickshell's Hyprland IPC module):
//   Hyprland.workspaces / Hyprland.toplevels / Hyprland.focusedWorkspace /
//   Hyprland.focusedMonitor / Hyprland.activeToplevel  -> live state
//   Hyprland.dispatch("workspace <idx|name>")          -> focus workspace
//   Hyprland.dispatch("workspace m+1|m-1")             -> cycle workspaces
//
// The IPC module pushes every change (no per-widget polling); a slow safety
// poll resynchronises the local model if an event is ever missed. Hyprland
// exposes window geometry over IPC, so the screenshot window mode can use
// slurp + grim like region capture.
//
// Canonical model (same shape as the old backend, so bar widgets behave the
// same): tags / monitors / windows, focusedMonitor, focusedAppId/Title.
Singleton {
    id: root

    // ---- compositor detection (env only, no process spawn) ----
    readonly property bool isHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "").length > 0
        || (((Quickshell.env("XDG_CURRENT_DESKTOP") || "") + " "
            + (Quickshell.env("XDG_SESSION_DESKTOP") || "") + " "
            + (Quickshell.env("DESKTOP_SESSION") || "")).toLowerCase().indexOf("hyprland") !== -1)
    readonly property string compositor: isHyprland ? "hyprland" : "unknown"

    // ---- bar/panel layer focus (Hyprland: taskbar stays clickable) ----
    // Hyprland routes ALL pointer input to the topmost Exclusive layer
    // surface: with Exclusive panels the bar never sees clicks while a
    // panel is open — no toggle, no switch. Panels therefore use OnDemand
    // on Hyprland and shell.qml holds a hyprland_focus_grab_v1 grab over
    // the bar + panel windows: bar clicks land on the bar (one-click
    // toggle/switch), clicks anywhere else clear the grab and dismiss.
    // Other compositors keep Exclusive + the fullscreen dismiss MouseArea.
    // Both registries feed HyprlandService.grabWindows (shell.qml's
    // HyprlandFocusGrab); entries are actual PanelWindow objects.
    property var barWindows: []
    property var panelWindows: []
    readonly property var grabWindows: barWindows.concat(panelWindows)
    function registerBarWindow(w: var): void {
        if (!w || barWindows.indexOf(w) >= 0) return
        barWindows = barWindows.concat([w])
    }
    function unregisterBarWindow(w: var): void {
        const out = []
        for (let i = 0; i < barWindows.length; i++)
            if (barWindows[i] !== w) out.push(barWindows[i])
        barWindows = out
    }
    function registerPanelWindow(w: var): void {
        if (!w || panelWindows.indexOf(w) >= 0) return
        panelWindows = panelWindows.concat([w])
    }
    function unregisterPanelWindow(w: var): void {
        const out = []
        for (let i = 0; i < panelWindows.length; i++)
            if (panelWindows[i] !== w) out.push(panelWindows[i])
        panelWindows = out
    }

    // ---- live state ----
    // Canonical workspaces: [{id, index, name, output, active, focused,
    // urgent, occupied, activeWindowId}] sorted by output then index.
    property var tags: []
    // output -> {tags: [canonical workspace entries]}
    property var monitors: ({})
    // Canonical windows: [{id, appId, title, output, wsId, index, active,
    // focused, urgent, floating}]
    property var windows: []
    // Output of the focused workspace.
    property string focusedMonitor: preferredMonitorName()
    // Focused window identity, used by the bar's ActiveWindow widget.
    property string focusedAppId: ""
    property string focusedTitle: ""
    property bool focusedFloating: false
    property string focusedWindowId: ""
    property string lastError: ""
    property bool dynamicTags: false

    function status(): string {
        return "compositor=" + compositor + " isHyprland=" + isHyprland
            + " monitor=" + focusedMonitor + " tags=" + tags.length
            + " windows=" + windows.length
    }
    function refresh(): void {
        try { Hyprland.refreshWorkspaces() } catch (e) {}
        try { Hyprland.refreshToplevels() } catch (e2) {}
        try { Hyprland.refreshMonitors() } catch (e3) {}
        scheduleRebuild()
        if (!dumpProc.running && !applyProc.running) syncAppearance()
    }

    // Preferred display: DP-1 when present, else the first Quickshell screen
    // so machines without DP-1 start on a real display.
    function preferredMonitorName(): string {
        try {
            let v = Quickshell.screens.values
            let vals = (v && typeof v.length === "number") ? v : []
            for (let i = 0; i < vals.length; i++) {
                if (vals[i] && vals[i].name === "DP-1") return "DP-1"
            }
            if (vals.length > 0 && vals[0] && vals[0].name) return "" + vals[0].name
        } catch (e) {}
        return "DP-1"
    }

    // ---- live IPC sources (rebinding these re-runs the projection) ----
    readonly property var hlWorkspaces: Hyprland.workspaces.values
    readonly property var hlToplevels: Hyprland.toplevels.values
    readonly property var hlFocusedWorkspace: Hyprland.focusedWorkspace
    readonly property var hlFocusedMonitor: Hyprland.focusedMonitor
    readonly property var hlActiveToplevel: Hyprland.activeToplevel

    onHlWorkspacesChanged: scheduleRebuild()
    onHlToplevelsChanged: scheduleRebuild()
    onHlFocusedWorkspaceChanged: scheduleRebuild()
    onHlFocusedMonitorChanged: scheduleRebuild()
    onHlActiveToplevelChanged: scheduleRebuild()

    Timer {
        id: rebuildDebounce
        interval: 50; repeat: false
        onTriggered: root.rebuild()
    }
    function scheduleRebuild(): void {
        if (!rebuildDebounce.running) rebuildDebounce.restart()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            try {
                let name = event ? ("" + (event.name || "")) : ""
                let data = event ? ("" + (event.data || "")) : ""
                if (name === "activelayout") {
                    // "keyboardName,layoutName" — surface it through the
                    // shared layout OSD (VolumeOSD listens on Theme).
                    let parts = data.split(",")
                    let layout = parts.length > 1 ? parts.slice(1).join(",").trim() : data.trim()
                    if (layout.length > 0) Theme.triggerLayoutOsd(layout)
                }
            } catch (e) {}
            root.scheduleRebuild()
        }
    }

    // ---- tiling layout watcher (general:layout -> Layout OSD) ----
    // Hyprland emits no socket event for tiling-layout changes, so poll
    // `hyprctl getoption general:layout`. The first successful read only
    // primes the cache (no OSD at boot); later changes surface through
    // the shared layout OSD (VolumeOSD listens on Theme) and are persisted
    // to configs/layout-state.lua for restart survival. Explicit
    // toggles (`solstice layout …`) persist in the CLI and report through
    // noteTilingLayout for instant feedback and cache sync, so the poll
    // never double-fires.
    property string tilingLayout: ""
    property bool tilingLayoutReady: false
    function noteTilingLayout(name: string): void {
        let l = ("" + (name || "")).trim()
        if (l.length === 0) return
        tilingLayout = l
        tilingLayoutReady = true
        Theme.triggerLayoutOsd(l)
    }
    Process {
        id: tilingLayoutProc
        command: ["bash", "-c", "hyprctl getoption general:layout 2>/dev/null | sed -n 's/^str:[[:space:]]*//p' | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = ((text || "").trim())
                if (l.length === 0) return
                if (!root.tilingLayoutReady) {
                    root.tilingLayout = l
                    root.tilingLayoutReady = true
                    return
                }
                if (l !== root.tilingLayout) {
                    root.tilingLayout = l
                    Theme.triggerLayoutOsd(l)
                    // Changed outside `solstice layout` (raw hyprctl): persist
                    // so restarts still come back into this layout. Explicit
                    // toggles persist synchronously in the CLI and sync the
                    // cache via noteTilingLayout, so this never double-fires.
                    root.persistTilingLayout(l)
                }
            }
        }
    }
    Timer {
        id: tilingLayoutTimer
        interval: 1500; running: root.isHyprland; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (!root.isHyprland || tilingLayoutProc.running) return
            tilingLayoutProc.running = true
        }
    }
    // State-file write for layouts changed outside `solstice layout`
    // (see configs/layout-state.lua). Command is stamped per change; the
    // CLI validates the name, and the array form avoids any shell.
    Process { id: tilingLayoutPersistProc }
    function persistTilingLayout(name: string): void {
        if (tilingLayoutPersistProc.running) return
        tilingLayoutPersistProc.command = ["solstice", "layout", "persist", ("" + (name || "")).trim()]
        tilingLayoutPersistProc.running = true
    }

    // ---- safety poll: one-shot resync, no steady-state per-frame work ----
    Timer {
        id: pollTimer
        interval: 30000; running: root.isHyprland; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (!root.isHyprland) return
            try { Hyprland.refreshWorkspaces() } catch (e) {}
            try { Hyprland.refreshToplevels() } catch (e2) {}
            try { Hyprland.refreshMonitors() } catch (e3) {}
            root.scheduleRebuild()
        }
    }

    // ---- model projection (Hyprland IPC objects -> canonical entries) ----
    function wsIndex(ws: var): int {
        try {
            let n = parseInt(ws.id)
            if (!isNaN(n)) return n
        } catch (e) {}
        try {
            let m = parseInt(ws.name)
            if (!isNaN(m)) return m
        } catch (e2) {}
        return 0
    }
    function wsOutput(ws: var): string {
        try { if (ws.monitor && ws.monitor.name) return "" + ws.monitor.name } catch (e) {}
        try {
            let ipc = ws.lastIpcObject
            if (ipc && ipc.monitor) return "" + ipc.monitor
        } catch (e2) {}
        return ""
    }
    function topAddress(t: var): string {
        try { if (t.address && ("" + t.address).length > 0) return "" + t.address } catch (e) {}
        try {
            let ipc = t.lastIpcObject
            if (ipc && ipc.address) return "" + ipc.address
        } catch (e2) {}
        return ""
    }
    function topAppId(t: var): string {
        try {
            let w = t.wayland
            if (w && w.appId && ("" + w.appId).length > 0) return "" + w.appId
        } catch (e) {}
        try { if (t.handle && t.handle.appId) return "" + t.handle.appId } catch (e2) {}
        try {
            let ipc = t.lastIpcObject
            if (ipc) {
                if (ipc.class && ("" + ipc.class).length > 0) return "" + ipc.class
                if (ipc.initialClass && ("" + ipc.initialClass).length > 0) return "" + ipc.initialClass
            }
        } catch (e3) {}
        return ""
    }
    function topTitle(t: var): string {
        try { if (t.title && ("" + t.title).length > 0) return "" + t.title } catch (e) {}
        try {
            let w = t.wayland
            if (w && w.title) return "" + w.title
        } catch (e2) {}
        try {
            let ipc = t.lastIpcObject
            if (ipc && ipc.title) return "" + ipc.title
        } catch (e3) {}
        return ""
    }
    function topFloating(t: var): bool {
        try {
            let ipc = t.lastIpcObject
            if (ipc && ipc.floating !== undefined) return !!ipc.floating
        } catch (e) {}
        return false
    }
    function topOutput(t: var): string {
        try { if (t.monitor && t.monitor.name) return "" + t.monitor.name } catch (e) {}
        try { if (t.workspace) return wsOutput(t.workspace) } catch (e2) {}
        try {
            let ipc = t.lastIpcObject
            if (ipc && ipc.monitor !== undefined) {
                let mons = Hyprland.monitors.values
                for (let i = 0; i < (mons || []).length; i++) {
                    if (mons[i] && mons[i].id === ipc.monitor && mons[i].name) return "" + mons[i].name
                }
            }
        } catch (e3) {}
        return ""
    }
    function topWsId(t: var): string {
        try { if (t.workspace && t.workspace.id !== undefined) return "" + t.workspace.id } catch (e) {}
        try {
            let ipc = t.lastIpcObject
            if (ipc && ipc.workspace && ipc.workspace.id !== undefined) return "" + ipc.workspace.id
        } catch (e2) {}
        return ""
    }

    // ---- shell windows (never shown in the taskbar) ----
    // The shell's own toplevels (settings app = org.quickshell, helper
    // terminals like solstice-shell-update) are regular Hyprland clients.
    // Showing them in Workspaces/Dock would put quickshell icons in the
    // taskbar; they are dropped from the canonical window list so they
    // never create icons, occupancy or urgency.
    function isShellWindow(appId: string, title: string): bool {
        let id = ("" + (appId || "")).trim().toLowerCase()
        if (id === "org.quickshell" || id === "quickshell")
            return true
        if (id.indexOf("solstice-shell-") === 0)
            return true
        return false
    }

    function rebuild(): void {
        let wsList = []
        try { wsList = Hyprland.workspaces.values || [] } catch (e) { wsList = [] }
        let topList = []
        try { topList = Hyprland.toplevels.values || [] } catch (e2) { topList = [] }

        // Canonical windows first (workspace entries derive occupancy from
        // them, same as the old backend).
        let wins = []
        let activeByWs = {}
        for (let i = 0; i < topList.length; i++) {
            let t = topList[i]
            if (!t) continue
            let addr = topAddress(t)
            if (addr.length === 0) continue
            let wsId = topWsId(t)
            let out = topOutput(t)
            let idx = 0
            try { if (t.workspace) idx = wsIndex(t.workspace) } catch (e3) {}
            let activated = false
            try { activated = !!t.activated } catch (e4) {}
            let _appId = topAppId(t)
            let _title = topTitle(t)
            if (isShellWindow(_appId, _title)) continue
            wins.push({
                id: addr,
                appId: _appId,
                title: _title,
                output: out,
                wsId: wsId,
                index: idx,
                active: activated,
                focused: activated,
                urgent: !!(function() { try { return t.urgent } catch (e5) { return false } })(),
                floating: topFloating(t)
            })
            if (activated && wsId.length > 0 && !activeByWs[wsId]) activeByWs[wsId] = addr
        }

        let byWs = {}
        for (let k = 0; k < wins.length; k++) {
            let w = wins[k]
            if (!w || w.wsId.length === 0) continue
            if (!byWs[w.wsId]) byWs[w.wsId] = []
            byWs[w.wsId].push(w)
        }

        let flat = []
        let mmap = {}
        let focused = root.focusedMonitor
        try {
            let fm = Hyprland.focusedMonitor
            if (fm && fm.name) focused = "" + fm.name
            else {
                let fw = Hyprland.focusedWorkspace
                if (fw) {
                    let fo = wsOutput(fw)
                    if (fo.length > 0) focused = fo
                }
            }
        } catch (e6) {}

        for (let j = 0; j < wsList.length; j++) {
            let ws = wsList[j]
            if (!ws) continue
            let id = ""
            try { id = "" + ws.id } catch (e7) {}
            if (id.length === 0) continue
            let idx = wsIndex(ws)
            let nm = ""
            try { nm = "" + (ws.name || "") } catch (e8) {}
            if (nm.length === 0) nm = "" + idx
            let out = wsOutput(ws)
            let active = false
            try { active = !!ws.active } catch (e9) {}
            let foc = false
            try { foc = !!ws.focused } catch (e10) {}
            let urg = false
            try { urg = !!ws.urgent } catch (e11) {}
            let members = byWs[id] || []
            let entry = {
                id: id,
                index: idx,
                name: nm,
                output: out,
                active: active,
                focused: foc,
                urgent: urg,
                occupied: members.length > 0,
                activeWindowId: activeByWs[id] || (members.length > 0 ? members[0].id : null)
            }
            flat.push(entry)
            if (out.length > 0) {
                if (!mmap[out]) mmap[out] = { tags: [] }
                mmap[out].tags.push(entry)
            }
            if (foc && out.length > 0) focused = out
        }
        for (let key in mmap) mmap[key].tags.sort((a, b) => a.index - b.index)

        // Re-resolve window output/index against the workspace table (a
        // toplevel that reports no monitor still lands on its workspace's
        // output).
        let wsById = {}
        for (let f = 0; f < flat.length; f++) wsById[flat[f].id] = flat[f]
        for (let g = 0; g < wins.length; g++) {
            let w = wins[g]
            let ws = wsById[w.wsId]
            if (ws) {
                if (w.output.length === 0) w.output = ws.output
                w.index = ws.index
            }
        }

        if (!mmap[focused]) {
            let pref = preferredMonitorName()
            if (mmap[pref]) focused = pref
            else for (let kk in mmap) { focused = kk; break }
        }
        monitors = mmap
        if (focusedMonitor !== focused) focusedMonitor = focused
        let nflat = []
        let fm2 = mmap[focused]
        if (fm2) nflat = fm2.tags
        tags = nflat
        windows = wins.slice()
        publishFocusedWindow()
    }

    function publishFocusedWindow(): void {
        // Identity comes from the HyprlandToplevel scan: t.title is always
        // present, the app id via the bound Wayland handle with the IPC
        // class as fallback. (Hyprland.activeToplevel does not forward the
        // app id, so it is only a change trigger, not an identity source.)
        // Shell toplevels are skipped: focusing the settings app must not
        // push a quickshell icon into the taskbar.
        let na = "", nt = "", nf = false, nid = ""
        try {
            let tops = Hyprland.toplevels.values || []
            for (let i = 0; i < tops.length; i++) {
                let t = tops[i]
                if (t && t.activated) {
                    let aid = topAppId(t)
                    let ttl = topTitle(t)
                    if (isShellWindow(aid, ttl)) continue
                    na = aid
                    nt = ttl
                    nf = topFloating(t)
                    nid = topAddress(t)
                    break
                }
            }
        } catch (e) {}
        if (focusedAppId !== na) focusedAppId = na
        if (focusedTitle !== nt) focusedTitle = nt
        if (focusedFloating !== nf) focusedFloating = nf
        if (focusedWindowId !== nid) focusedWindowId = nid
    }

    // ---- window queries ----
    // Is the window on its output's active workspace? Windows on hidden
    // workspaces keep existing; a hit test must not see them.
    function windowVisible(w: var): bool {
        if (!w) return false
        try {
            const m = monitors[w.output]
            const tl = m ? (m.tags || []) : []
            if (tl.length === 0) return true
            for (let i = 0; i < tl.length; i++) {
                if (tl[i].index === w.index) return !!tl[i].active
            }
        } catch (e) {}
        return true
    }

    // Output -> true while a fullscreen window on its active workspace is
    // visible there. Fullscreen comes from Hyprland's own workspace state
    // (hasFullscreen) plus the wlr-foreign-toplevel protocol via Quickshell's
    // ToplevelManager (live, no polling); a toplevel is only counted when its
    // (appId, title) matches a window the IPC layer reports as visible — a
    // game left fullscreen on a hidden workspace must not keep the bar
    // collapsed on the workspace the user switched to.
    readonly property var fullscreenOutputs: {
        const out = {}
        try {
            const wsList = Hyprland.workspaces.values || []
            for (let i = 0; i < wsList.length; i++) {
                const ws = wsList[i]
                if (ws && ws.hasFullscreen && ws.active) {
                    const o = wsOutput(ws)
                    if (o.length > 0) out[o] = true
                }
            }
        } catch (e) {}
        try {
            const tops = ToplevelManager.toplevels.values
            const list = windows || []
            for (let i = 0; i < (tops || []).length; i++) {
                const t = tops[i]
                if (!t || !t.fullscreen) continue
                for (let k = 0; k < list.length; k++) {
                    const w = list[k]
                    if (!w || w.appId !== t.appId || w.title !== t.title) continue
                    if (windowVisible(w)) out[w.output] = true
                }
            }
        } catch (e2) {}
        return out
    }
    function isOutputFullscreen(name: string): bool {
        try { return !!(fullscreenOutputs || {})[("" + (name || ""))] } catch (e) { return false }
    }

    // Windows on one workspace. `screenName` empty = every output (used when
    // the workspace widget merges monitors). `ignoreTags` drops windows whose
    // app id is in the list (caelestia bar.workspaces.ignoredTags equivalent).
    // Shell windows are always dropped, even if the user cleared the ignore
    // list, so quickshell icons never appear in the taskbar.
    function windowsOn(screenName: string, index: int, ignoreTags: var): var {
        const out = []
        const target = ((screenName || "") + "").trim()
        const ignore = Array.isArray(ignoreTags) ? ignoreTags : []
        const ws = windows || []
        for (let i = 0; i < ws.length; i++) {
            const w = ws[i]
            if (!w) continue
            if (target.length > 0 && w.output !== target) continue
            if (w.index !== index) continue
            if (ignore.indexOf(w.appId) !== -1) continue
            if (isShellWindow(w.appId, w.title)) continue
            out.push(w)
        }
        return out
    }

    function workspaceUrgent(screenName: string, index: int, ignoreTags: var): bool {
        const ws = windowsOn(screenName, index, ignoreTags)
        for (let i = 0; i < ws.length; i++) if (ws[i].urgent) return true
        return false
    }

    // Index of the focused output's active (visible) workspace, or -1.
    function activeWorkspaceIndex(): int {
        try {
            for (let i = 0; i < tags.length; i++) {
                if (tags[i] && tags[i].active) return parseInt(tags[i].index)
            }
        } catch (e) {}
        return -1
    }

    // ---- dispatch helpers ----
    // The compositor runs in Lua mode (see Hyprland.usingLua): dispatcher
    // payloads are Lua expressions (hl.dsp.*), not classic `hyprctl`
    // syntax — `hyprctl dispatch workspace 2` is rejected there.
    function dispatchIpc(classic: string, lua: string): void {
        if (!isHyprland) return
        let request = classic
        try {
            if (Hyprland.usingLua && (lua || "").length > 0) request = lua
        } catch (e) {}
        if (!request || request.length === 0) return
        try { Hyprland.dispatch(request) } catch (e2) { lastError = "dispatch: " + e2 }
    }
    // Optimistic local echo so the highlight moves on click, not on the next
    // event. The event stream corrects it right after.
    function optimisticView(idx: int, screenName: string): void {
        try {
            let i = Math.max(1, Math.min(64, Math.round(idx)))
            let target = ((screenName || "") + "").trim() || focusedMonitor
            let m = monitors[target]
            if (!m) return
            let ntl = []
            let tl = m.tags || []
            for (let ti = 0; ti < tl.length; ti++) {
                let w = tl[ti]
                ntl.push({
                    id: w.id, index: w.index, name: w.name, output: w.output,
                    active: parseInt(w.index) === i, focused: false,
                    urgent: !!w.urgent, occupied: !!w.occupied,
                    activeWindowId: w.activeWindowId
                })
            }
            let nmm = {}
            for (let k in monitors) nmm[k] = monitors[k]
            nmm[target] = { tags: ntl }
            monitors = nmm
            if (target === focusedMonitor) tags = ntl
        } catch (e) {}
    }
    // `workspace <idx>` focuses that workspace (on the focused monitor when
    // the workspace is not yet bound to one, which is also the output the
    // bar mirrors — see Workspaces.resolveScreenName).
    function activateTag(idx: int, screenName: string): void {
        let i = Math.max(1, Math.min(64, Math.round(idx)))
        optimisticView(i, screenName)
        dispatchIpc("workspace " + i, "hl.dsp.focus({workspace=" + i + "})")
    }
    function nextTag(screenName: string): void {
        dispatchIpc("workspace m+1", "hl.dsp.focus({workspace=\"m+1\"})")
    }
    function prevTag(screenName: string): void {
        dispatchIpc("workspace m-1", "hl.dsp.focus({workspace=\"m-1\"})")
    }
    function isPinned(idx: int): bool {
        return false
    }

    // ---- appearance settings (shell-managed configs/solstice.lua) ----
    // The Appearance > Compositor settings page edits these. Persistence goes
    // through backend/scripts/hyprland-apply.py, which rewrites the managed
    // include configs/solstice.lua and applies the values live with
    // `hyprctl keyword`. Values are read back from the managed file on load.
    // Window rounding is not managed here: it mirrors Appearance > Rounding
    // (Theme.cornerRadius), which pushes to the compositor on every change.
    property bool hyprLoaded: false
    property int hyprGapsIn: 1
    property int hyprGapsOut: 20
    readonly property int hyprRounding: Theme.cornerRadius
    property int hyprBorderSize: 2
    property bool hyprShadow: true
    property int hyprShadowRange: 4
    property bool hyprAnimations: true
    // Panel blur (Hyprland > Panel blur): frosted bar + panels through one
    // blur layer rule per shell namespace (see backend/scripts/
    // hyprland-apply.py PANEL_BLUR_NAMESPACES). Theme.panelBlur (0..1) is the
    // single source of truth; hyprPanelBlur* below only mirror the managed
    // file so startup can converge it. Threshold mapping verified live:
    // 0.3 blurs just the translucent card, 0.95 blurs the whole screen.
    property bool hyprPanelBlur: true
    property real hyprPanelBlurAlpha: 0.38
    readonly property bool panelBlurEnabled: isHyprland && Theme.panelBlur > 0.005
    readonly property real panelBlurAlpha: Math.round((0.2 + 0.3 * Math.max(0, Math.min(1, Theme.panelBlur))) * 100) / 100
    function panelBlurStatus(): string {
        return "enabled=" + panelBlurEnabled + " strength=" + Theme.panelBlur + " ignoreAlpha=" + panelBlurAlpha
    }

    readonly property string _applyScript: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/scripts/hyprland-apply.py"

    function _clampInt(v: var, lo: int, hi: int, fb: int): int {
        let n = Math.round(Number(v))
        if (!isFinite(n)) return fb
        return Math.max(lo, Math.min(hi, n))
    }

    function syncAppearance(): void {
        if (!isHyprland || dumpProc.running) return
        dumpProc.running = true
    }
    Process {
        id: dumpProc
        command: ["python3", root._applyScript, "dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let j = JSON.parse((text || "").trim() || "{}")
                    root.hyprGapsIn = root._clampInt(j.gapsIn, 0, 100, root.hyprGapsIn)
                    root.hyprGapsOut = root._clampInt(j.gapsOut, 0, 100, root.hyprGapsOut)
                    root.hyprBorderSize = root._clampInt(j.borderSize, 0, 16, root.hyprBorderSize)
                    root.hyprShadow = j.shadow !== false
                    root.hyprShadowRange = root._clampInt(j.shadowRange, 0, 100, root.hyprShadowRange)
                    root.hyprAnimations = j.animations !== false
                    root.hyprLoaded = true
                    // Panel blur: mirror the managed file, then converge it
                    // to Theme.panelBlur (the source of truth) when it holds
                    // another value — same pattern as rounding above.
                    try {
                        root.hyprPanelBlur = j.panelBlur !== false
                        let pa = Number(j.panelBlurAlpha)
                        if (isFinite(pa)) root.hyprPanelBlurAlpha = Math.max(0, Math.min(1, Math.round(pa * 100) / 100))
                    } catch (e2) {}
                    if (root.hyprPanelBlur !== root.panelBlurEnabled
                            || Math.abs(root.hyprPanelBlurAlpha - root.panelBlurAlpha) > 0.005)
                        persistDebounce.restart()
                    // Rounding follows Appearance: converge the managed file
                    // (and the live compositor) when it holds another value.
                    if (root._clampInt(j.rounding, 0, 64, root.hyprRounding) !== root.hyprRounding)
                        root.persist()
                } catch (e) { root.lastError = "appearance: " + e }
            }
        }
    }

    Timer { id: persistDebounce; interval: 200; repeat: false; onTriggered: root.persist() }
    // Window rounding mirrors Appearance > Rounding: every change pushes
    // through the managed file + live keyword (debounced, like slider drags).
    Connections {
        target: Theme
        function onCornerRadiusChanged() {
            if (root.isHyprland && root.hyprLoaded) persistDebounce.restart()
        }
        // Panel blur strength drives the managed layer rules (file + live
        // eval through persist()), same debounced path as rounding drags.
        function onPanelBlurChanged() {
            if (root.isHyprland && root.hyprLoaded) persistDebounce.restart()
        }
    }
    property string _pendingPayload: ""
    Process {
        id: applyProc
        onExited: (code, status) => {
            if (root._pendingPayload.length > 0) {
                let p = root._pendingPayload
                root._pendingPayload = ""
                root._runApply(p)
            }
        }
    }
    function _runApply(payload: string): void {
        applyProc.command = ["python3", root._applyScript, "apply", payload]
        applyProc.running = true
    }
    function persist(): void {
        // Never write before the managed file has been read back (dumpProc
        // sets hyprLoaded). At boot Theme replays the stored panelBlur /
        // cornerRadius values, which fires the Connections below; without
        // this guard the QML defaults (shadow=true, gapsIn=1, gapsOut=20,
        // …) would overwrite the user's saved configs/solstice.lua before
        // the dump ever loads it — so every reboot reset the Compositor
        // page to defaults.
        if (!isHyprland || !hyprLoaded) return
        let payload = JSON.stringify({
            gapsIn: hyprGapsIn,
            gapsOut: hyprGapsOut,
            rounding: hyprRounding,
            borderSize: hyprBorderSize,
            shadow: hyprShadow,
            shadowRange: hyprShadowRange,
            animations: hyprAnimations,
            panelBlur: panelBlurEnabled,
            panelBlurAlpha: panelBlurAlpha
        })
        if (applyProc.running) { _pendingPayload = payload; return }
        _runApply(payload)
    }
    function _flushPersist(): void { persistDebounce.stop(); persist() }

    // Slider drags preview through here (debounced write); apply* flushes.
    function preview(key: string, value: var): void {
        if (!isHyprland) return
        switch (key) {
        case "gapsIn": hyprGapsIn = _clampInt(value, 0, 100, hyprGapsIn); break
        case "gapsOut": hyprGapsOut = _clampInt(value, 0, 100, hyprGapsOut); break
        case "borderSize": hyprBorderSize = _clampInt(value, 0, 16, hyprBorderSize); break
        case "shadowRange": hyprShadowRange = _clampInt(value, 0, 100, hyprShadowRange); break
        default: return
        }
        persistDebounce.restart()
    }
    function applyGapsIn(v: var): void { hyprGapsIn = _clampInt(v, 0, 100, hyprGapsIn); _flushPersist() }
    function applyGapsOut(v: var): void { hyprGapsOut = _clampInt(v, 0, 100, hyprGapsOut); _flushPersist() }
    function applyBorderSize(v: var): void { hyprBorderSize = _clampInt(v, 0, 16, hyprBorderSize); _flushPersist() }
    function applyShadow(on: bool): void { hyprShadow = !!on; _flushPersist() }
    function applyShadowRange(v: var): void { hyprShadowRange = _clampInt(v, 0, 100, hyprShadowRange); _flushPersist() }
    function applyAnimations(on: bool): void { hyprAnimations = !!on; _flushPersist() }

    Component.onCompleted: {
        scheduleRebuild()
        // Wayland handles / IPC payloads bind a beat after the toplevel
        // list itself: re-project twice more so the first paint already
        // has app ids and workspace bindings.
        settleTimer.restart()
        syncAppearance()
    }
    Timer {
        id: settleTimer
        interval: 2000; repeat: false
        property int round: 0
        onTriggered: {
            root.rebuild()
            if (round < 1) { round++; interval = 8000; restart() }
        }
    }

    IpcHandler {
        target: "hyprland"
        function status(): string { return root.status() }
        function refresh(): string { root.refresh(); return root.status() }
        function view(tag: int): string { root.activateTag(tag, ""); return "view=" + tag }
        function layout(): string { return root.tilingLayout }
        function noteTilingLayout(name: string): string { root.noteTilingLayout(name); return "layout=" + root.tilingLayout }
        function focused(): string {
            return JSON.stringify({
                id: root.focusedWindowId,
                appId: root.focusedAppId,
                title: root.focusedTitle,
                floating: root.focusedFloating
            })
        }
        function appearance(): string {
            return JSON.stringify({
                loaded: root.hyprLoaded,
                gapsIn: root.hyprGapsIn,
                gapsOut: root.hyprGapsOut,
                rounding: root.hyprRounding,
                borderSize: root.hyprBorderSize,
                shadow: root.hyprShadow,
                shadowRange: root.hyprShadowRange,
                animations: root.hyprAnimations,
                panelBlur: root.hyprPanelBlur,
                panelBlurAlpha: root.hyprPanelBlurAlpha,
                panelBlurEffective: root.panelBlurEnabled,
                panelBlurEffectiveAlpha: root.panelBlurAlpha
            })
        }
        function blur(): string { return root.panelBlurStatus() }
    }
}
