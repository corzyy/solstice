pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import M3Shapes
import "../../../style/themes"
import "../../../backend/services"

// Caelestia workspace bar item, ported onto Umbriel.
//
// Source: caelestia-dots/shell modules/bar/components/workspaces/*
// (Workspaces.qml, Workspace.qml, OccupiedBg.qml, GapMarkers.qml,
// ActiveIndicator.qml). The port keeps the visual language:
//   - MaterialShape indicators (focused 2/3, occupied 1/3, free 1/4 of the
//     slot) from the M3Shapes plugin
//   - occupied background strip connecting adjacent occupied workspaces
//   - gap markers between non-consecutive workspaces (showUnoccupied off)
//   - an accent pill that slides behind the active workspace, with an
//     asymmetric leading/trailing duration (activeTrail) and a trailing cap
//     that tapers with the stretch while moving, round again once settled
//   - displayType shapes/numbers (workspace ordinals as labels)
//   - window icons per workspace (maxWindowIcons)
// Differences forced by Umbriel/horizontal bars:
//   - workspaces are numbered (group window of `shown` around the active one)
//     and synthesised when they do not exist yet
//   - in a horizontal bar the window icons sit next to the shape (Caelestia's
//     vertical bar stacks them below; vertical bars keep that layout here)
//   - no special workspaces / blur-on-special (not an Umbriel concept)
Rectangle {
    id: root

    // Compatibility with BarModule: monitor is the ShellScreen of the bar,
    // vertical selects the bar orientation.
    property var monitor: null
    property bool vertical: false

    // ---- settings (Theme -> backend/config/topbar_settings.json) ----
    readonly property string displayType: Theme.workspaceDisplayType
    readonly property bool shapesMode: displayType === "shapes"
    readonly property real uiScale: Theme.workspaceScale
    readonly property real spacing: Math.round(Theme.workspaceSpacing * uiScale)
    readonly property int maxIcons: Theme.workspaceMaxWindowIcons
    readonly property bool iconsOn: Theme.workspaceShowWindows && maxIcons > 0
    readonly property real iconSize: Math.max(7, Math.min(14, Math.round(9 * (0.6 + 0.4 * uiScale))))
    readonly property real iconSpacing: Math.max(0, Math.round(3 * uiScale))
    readonly property real pad: Math.max(2, Math.round(2 * uiScale))
    readonly property real slot: {
        const ideal = Math.max(12, (Theme.barThickness - 10) * uiScale)
        const cap = Math.max(12, Theme.barThickness - 2 * pad)
        return Math.round(Math.max(10, Math.min(ideal, cap)))
    }

    // ---- container ----
    // Optional pill (Settings -> Panels -> Taskbar -> Workspaces >
    // Background) is painted by BarSlot's uniform card like every other
    // module, so this rectangle stays transparent and only keeps the
    // container clipping for the delegates. No double-paint.
    color: "transparent"
    radius: Math.min(width, height) / 2
    clip: true
    antialiasing: Theme.shapesAa

    implicitWidth: vertical ? slot + 2 * pad : Math.max(10, hRow.implicitWidth + 2 * pad)
    implicitHeight: vertical ? Math.max(10, vCol.implicitHeight + 2 * pad) : slot + 2 * pad

    // ---- output resolution (single bar mirrors the focused screen) ----
    readonly property string screenName: resolveScreenName()

    function resolveScreenName(): string {
        try {
            const focused = UmbrielService.focusedMonitor
            if (focused && ("" + focused).length > 0)
                return "" + focused
        } catch (e) {}
        try {
            if (monitor && monitor.name)
                return "" + monitor.name
            if (typeof monitor === "string" && ("" + monitor).length > 0)
                return "" + monitor
        } catch (e) {}
        try {
            return Theme.primaryScreenName
        } catch (e2) {
            return "DP-1"
        }
    }

    // ---- workspace model ----
    // Umbriel reports ui ordinals (index/name 1..N) per output; the widget
    // shows a group window of Theme.workspaceShown ordinals around the active
    // one (showUnoccupied) or only occupied/active workspaces.
    function blankEntry(index: int, output: string): var {
        return {
            index: index,
            name: "" + index,
            output: output,
            active: false,
            occupied: false,
            urgent: false,
            foreign: false,
            shown: false,
            gapBefore: false,
            prevActive: false
        }
    }

    function collectReal(): var {
        const mm = UmbrielService.monitors || {}
        const perMonitor = Theme.workspacePerMonitor
        const screen = root.screenName
        const byIdx = {}
        const onScreen = {}
        for (let outName in mm) {
            if (perMonitor && outName !== screen)
                continue
            const tl = (mm[outName] && mm[outName].tags) || []
            for (let i = 0; i < tl.length; i++) {
                const w = tl[i]
                if (!w)
                    continue
                const idx = parseInt(w.index)
                if (isNaN(idx))
                    continue
                let e = byIdx[idx]
                if (!e) {
                    e = root.blankEntry(idx, outName)
                    byIdx[idx] = e
                }
                if (outName === screen)
                    onScreen[idx] = true
                if (w.active && outName === screen)
                    e.active = true
                if (w.occupied)
                    e.occupied = true
                const nm = ("" + (w.name || "")).trim()
                if (nm.length > 0)
                    e.name = nm
                if (outName === screen)
                    e.output = outName
            }
        }
        const out = []
        for (let k in byIdx) {
            const e = byIdx[k]
            e.foreign = !perMonitor && onScreen[e.index] !== true
            e.urgent = UmbrielService.workspaceUrgent(perMonitor ? screen : "", e.index, Theme.workspaceIgnoredTags)
            out.push(e)
        }
        out.sort((a, b) => a.index - b.index)
        return out
    }

    function buildModel(): var {
        const real = collectReal()
        const byIdx = {}
        for (let i = 0; i < real.length; i++)
            byIdx[real[i].index] = real[i]
        let activeIdx = -1
        for (let i = 0; i < real.length; i++) {
            if (real[i].active)
                activeIdx = real[i].index
        }
        if (activeIdx < 0)
            activeIdx = real.length > 0 ? real[0].index : 1

        let result = []
        if (Theme.workspaceShowUnoccupied) {
            // Caelestia: always show `shown` slots, offset to the active group.
            const count = Theme.workspaceShown
            const groupOffset = Math.floor((Math.max(1, activeIdx) - 1) / count) * count
            for (let i = groupOffset + 1; i <= groupOffset + count; i++) {
                const e = byIdx[i] || root.blankEntry(i, root.screenName)
                e.shown = true
                result.push(e)
            }
        } else {
            // Only occupied/active/urgent workspaces, windowed around active.
            const vis = []
            for (let i = 0; i < real.length; i++) {
                const e = real[i]
                if (e.occupied || e.active || e.urgent)
                    vis.push(e)
            }
            if (vis.length === 0)
                vis.push(byIdx[activeIdx] || root.blankEntry(activeIdx, root.screenName))
            const len = vis.length
            let cur = 0
            for (let i = 0; i < vis.length; i++) {
                if (vis[i].active) {
                    cur = i
                    break
                }
            }
            const count = Theme.workspaceShown
            const end = Math.max(Math.min(count, len), Math.min(cur + 1, len))
            const start = Math.max(0, end - count)
            const inSlice = {}
            for (let i = start; i < end; i++)
                inSlice[vis[i].index] = true
            for (let i = 0; i < real.length; i++)
                real[i].shown = inSlice[real[i].index] === true
            result = real
        }

        // Gap markers between non-consecutive slots (showUnoccupied off).
        let prevShown = null
        for (let i = 0; i < result.length; i++) {
            const e = result[i]
            e.gapBefore = false
            e.prevActive = false
            if (!e.shown)
                continue
            if (prevShown) {
                if (!Theme.workspaceShowUnoccupied && prevShown.index !== e.index - 1)
                    e.gapBefore = true
                e.prevActive = prevShown.active
            }
            prevShown = e
        }
        return result
    }

    readonly property var workspaceModel: buildModel()
    readonly property bool hasActive: {
        const m = workspaceModel
        for (let i = 0; i < m.length; i++) {
            if (m[i].active && m[i].shown)
                return true
        }
        return false
    }

    // Repeaters bind to the constant length and read through this accessor so
    // content changes (focus/occupancy/windows) only update bindings instead
    // of destroying delegates.
    function workspaceAt(index: int): var {
        const m = workspaceModel
        return (index >= 0 && index < m.length) ? m[index] : null
    }

    // ---- window icon order ----
    // The compositor's window list is z-order: the focused window moves to
    // the front, which used to make the strip icons swap places on every
    // focus change. Rank each window id on first sight instead and sort the
    // per-workspace strips by that rank, so icons keep their slot while a
    // window lives and new windows append at the end.
    property var _winRank: ({})
    property int winRankRev: 0
    function reindexWindows(): void {
        const list = UmbrielService.windows || []
        const rank = _winRank
        let next = 0
        for (let k in rank)
            next = Math.max(next, rank[k] + 1)
        const seen = {}
        let dirty = false
        for (let i = 0; i < list.length; i++) {
            const w = list[i]
            const id = w ? ("" + w.id) : ""
            if (id.length === 0)
                continue
            seen[id] = true
            if (rank[id] === undefined) {
                rank[id] = next++
                dirty = true
            }
        }
        // Forget closed windows so the map cannot grow forever.
        const stale = []
        for (let k in rank) {
            if (seen[k] !== true)
                stale.push(k)
        }
        for (let i = 0; i < stale.length; i++)
            delete rank[stale[i]]
        if (stale.length > 0)
            dirty = true
        if (dirty) {
            _winRank = rank
            winRankRev++
        }
    }
    function windowRank(win: var): real {
        winRankRev // dependency: re-sort when new windows get ranked
        const id = win ? ("" + win.id) : ""
        const rank = _winRank[id]
        return rank === undefined ? Number.MAX_SAFE_INTEGER : rank
    }
    Connections {
        target: UmbrielService
        // Rank fresh windows before the delegates sort by rank.
        function onWindowsChanged() { root.reindexWindows() }
    }

    // ---- active indicator (Caelestia ActiveIndicator) ----
    property real indStart: 0
    property real indEnd: 0
    // Resting span of the active delegate. The pill is only tapered by the
    // extra length it gains while the trailing edge lags, so it settles back
    // into a round shape and longer travels taper further.
    property real indTargetSpan: 0
    property real _startDur: Theme.durDefaultSpatial
    property real _endDur: Theme.durDefaultSpatial
    property bool _indicatorDirty: false
    // True for a short window after the tracked output changes (the bar
    // mirrors the focused monitor). The strip then belongs to a different
    // monitor: the old layout is unrelated to the new one, so trailing the
    // pill across it while the delegates re-laid out with their own width
    // animations made the whole strip wobble. Delegate and indicator
    // animations are suppressed in that window, so the swap snaps.
    property bool _outputSnap: false
    // Which end carries the smaller trailing cap: while the pill travels
    // up/left the end edge lags, otherwise the start edge does.
    property bool trailAtEnd: true
    // Rounded rects behind runs of adjacent occupied workspaces (Caelestia
    // OccupiedBg). Computed from live delegate geometry so they follow the
    // collapse/expand animations.
    property var occBands: []

    function activeDelegate(): var {
        const container = root.vertical ? vCol : hRow
        for (let i = 0; i < container.children.length; i++) {
            const ch = container.children[i]
            if (!ch || ch.workspace === undefined || ch.delegateIndex === undefined)
                continue
            const ws = ch.workspace
            if (!ws || !ws.active || !ws.shown)
                continue
            return ch
        }
        return null
    }

    function requestIndicatorUpdate(): void {
        if (_indicatorDirty)
            return
        _indicatorDirty = true
        Qt.callLater(updateIndicator)
    }

    function sameBands(a: var, b: var): bool {
        if (!a || !b || a.length !== b.length)
            return false
        for (let i = 0; i < a.length; i++) {
            const x = a[i], y = b[i]
            if (!x || !y)
                return false
            if (Math.abs(x.x - y.x) > 0.5 || Math.abs(x.y - y.y) > 0.5
                || Math.abs(x.w - y.w) > 0.5 || Math.abs(x.h - y.h) > 0.5)
                return false
        }
        return true
    }

    function updateIndicator(): void {
        _indicatorDirty = false
        const container = vertical ? vCol : hRow
        const originX = (width - container.width) / 2
        const originY = (height - container.height) / 2

        const d = activeDelegate()
        if (!d) {
            indStart = 0
            indEnd = 0
            indTargetSpan = 0
        } else {
            const s = vertical ? d.y : d.x
            const e = s + (vertical ? d.height : d.width)
            indTargetSpan = vertical ? d.height : d.width
            if (Math.abs(s - indStart) >= 0.5 || Math.abs(e - indEnd) >= 0.5) {
                const lead = Theme.durDefaultSpatial
                const trail = Theme.workspaceActiveTrail ? Math.round(lead * 3) : lead
                const up = s < indStart
                _startDur = up ? lead : trail
                _endDur = up ? trail : lead
                trailAtEnd = up
                indStart = s
                indEnd = e
            }
        }

        // Occupied background runs: one rect per contiguous occupied group,
        // trailing spacing trimmed off the end so bands sit flush.
        const bands = []
        let run = null
        const kids = container.children
        for (let i = 0; i < kids.length; i++) {
            const ch = kids[i]
            if (!ch || ch.workspace === undefined) {
                run = null
                continue
            }
            const ws = ch.workspace
            if (!ws || !ws.shown || !ws.occupied || ch.reveal < 0.01) {
                run = null
                continue
            }
            const x1 = originX + ch.x
            const y1 = originY + ch.y
            const x2 = x1 + ch.width
            const y2 = y1 + ch.height
            if (!run) {
                run = { x1: x1, y1: y1, x2: x2, y2: y2 }
                bands.push(run)
            } else {
                run.x2 = Math.max(run.x2, x2)
                run.y2 = Math.max(run.y2, y2)
            }
        }
        const rects = []
        for (let i = 0; i < bands.length; i++) {
            const b = bands[i]
            if (vertical)
                rects.push({ x: b.x1 - 1, y: b.y1 - 1, w: b.x2 - b.x1 + 2, h: Math.max(0, b.y2 - b.y1 + 2 - spacing) })
            else
                rects.push({ x: b.x1 - 1, y: b.y1 - 1, w: Math.max(0, b.x2 - b.x1 + 2 - spacing), h: b.y2 - b.y1 + 2 })
        }
        if (!sameBands(occBands, rects))
            occBands = rects
    }

    // Output swaps snap (see _outputSnap). Keep the flag up long enough to
    // cover both umbriel streams (workspaces then windows land ~1 ms apart)
    // before trusting animations again.
    Timer {
        id: outputSnapTimer
        interval: 60
        repeat: false
        onTriggered: {
            root._outputSnap = false
            root.requestIndicatorUpdate()
        }
    }
    onScreenNameChanged: {
        _outputSnap = true
        requestIndicatorUpdate()
        outputSnapTimer.restart()
    }

    // Re-layouts (model swap, collapse animations, bar moves) can finish after
    // the first update, so keep a short follow-up sync around transitions.
    Timer {
        id: indicatorSync
        interval: 32
        repeat: false
        onTriggered: root.requestIndicatorUpdate()
    }
    onWorkspaceModelChanged: {
        hoveredIndex = -1
        requestIndicatorUpdate()
        indicatorSync.restart()
    }
    onVerticalChanged: {
        requestIndicatorUpdate()
        indicatorSync.restart()
    }
    onWidthChanged: requestIndicatorUpdate()
    onHeightChanged: requestIndicatorUpdate()
    Component.onCompleted: {
        reindexWindows()
        requestIndicatorUpdate()
        indicatorSync.restart()
    }

    Behavior on indStart { enabled: Theme.animationsEnabled && !root._outputSnap; NumberAnimation { duration: root._startDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
    Behavior on indEnd { enabled: Theme.animationsEnabled && !root._outputSnap; NumberAnimation { duration: root._endDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }

    // Occupied background (below the indicator and the delegates).
    Repeater {
        model: Theme.workspaceOccupiedBg ? root.occBands.length : 0
        delegate: Rectangle {
            required property int index
            readonly property var band: root.occBands[index]
            visible: band !== undefined
            x: band ? band.x : 0
            y: band ? band.y : 0
            width: band ? band.w : 0
            height: band ? band.h : 0
            radius: Math.min(width, height) / 2
            color: Theme.surface_container_highest
            antialiasing: Theme.shapesAa
        }
    }

    Item {
        id: activeIndicator

        visible: Theme.workspaceActiveIndicator && root.hasActive
        x: root.vertical ? (root.width - root.slot) / 2 : (root.width - hRow.width) / 2 + root.indStart
        y: root.vertical ? (root.height - vCol.height) / 2 + root.indStart : (root.height - root.slot) / 2
        width: root.vertical ? root.slot : Math.max(0, root.indEnd - root.indStart)
        height: root.vertical ? Math.max(0, root.indEnd - root.indStart) : root.slot

        Item {
            id: activeShape

            // Canonical local frame: length along x, thickness along y. Vertical
            // bars rotate the whole shape so the taper follows the slide axis;
            // the inner mirror flips the small cap onto the trailing end.
            width: root.vertical ? activeIndicator.height : activeIndicator.width
            height: root.vertical ? activeIndicator.width : activeIndicator.height
            x: (activeIndicator.width - width) / 2
            y: (activeIndicator.height - height) / 2
            rotation: root.vertical ? 90 : 0

            // Resting span of the active delegate, forwarded from the
            // indicator geometry.
            property real targetSpan: root.indTargetSpan

            readonly property real headR: height / 2
            // Stretch = how far the pill is longer than its resting span,
            // i.e. how much room the trailing edge has to lag. The taper
            // scales with it and disappears at rest, so a settled pill is
            // round and a long travel gets a longer tail.
            readonly property real stretch: Math.max(0, width - targetSpan)
            readonly property real taper: Theme.workspaceActiveTrail
                ? 0.4 * Math.min(1, stretch / Math.max(1, targetSpan))
                : 0
            readonly property real tailR: headR * (1 - taper)
            // Keep the two caps from crossing while the pill collapses.
            readonly property real span: Math.max(width, headR + tailR)
            readonly property real spanOffset: (width - span) / 2
            readonly property real cy: height / 2

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                antialiasing: Theme.shapesAa

                transform: Scale {
                    xScale: root.trailAtEnd ? 1 : -1
                    origin.x: activeShape.width / 2
                    origin.y: activeShape.height / 2
                }

                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: Theme.accent

                    Behavior on fillColor { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }

                    startX: activeShape.spanOffset + activeShape.headR
                    startY: activeShape.cy - activeShape.headR
                    PathLine { x: activeShape.spanOffset + activeShape.span - activeShape.tailR; y: activeShape.cy - activeShape.tailR }
                    PathArc {
                        x: activeShape.spanOffset + activeShape.span - activeShape.tailR
                        y: activeShape.cy + activeShape.tailR
                        radiusX: activeShape.tailR
                        radiusY: activeShape.tailR
                    }
                    PathLine { x: activeShape.spanOffset + activeShape.headR; y: activeShape.cy + activeShape.headR }
                    PathArc {
                        x: activeShape.spanOffset + activeShape.headR
                        y: activeShape.cy - activeShape.headR
                        radiusX: activeShape.headR
                        radiusY: activeShape.headR
                    }
                }
            }
        }
    }

    // ---- delegates ----
    Row {
        id: hRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 0
        Repeater {
            // PERF: inactive orientation keeps zero delegates.
            model: root.vertical ? 0 : root.workspaceModel.length
            delegate: WorkspaceDelegate {
                required property int index
                workspace: root.workspaceAt(index)
                delegateIndex: index
            }
        }
    }

    Column {
        id: vCol
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 0
        Repeater {
            model: root.vertical ? root.workspaceModel.length : 0
            delegate: WorkspaceDelegate {
                required property int index
                workspace: root.workspaceAt(index)
                delegateIndex: index
            }
        }
    }

    component WorkspaceIndicator: Item {
        id: indicator

        required property var workspace
        property bool focused: false
        property bool occupied: false
        property color fg: Theme.textPrimary

        width: root.slot
        height: root.slot

        readonly property int mode: root.shapesMode ? 0 : 1
        readonly property string label: workspace ? ("" + workspace.index) : ""

        // Caelestia picks a random material shape on every focus change.
        readonly property var shapeChoices: [
            MaterialShape.Slanted, MaterialShape.Oval, MaterialShape.Pill,
            MaterialShape.Triangle, MaterialShape.Arrow, MaterialShape.Diamond,
            MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.VerySunny,
            MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
            MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided,
            MaterialShape.Clover4Leaf, MaterialShape.SoftBurst, MaterialShape.Ghostish
        ]
        property int focusedShape: MaterialShape.Oval

        function pickShape(): void {
            const list = shapeChoices
            if (list.length === 0)
                return
            let next = list[Math.floor(Math.random() * list.length)]
            if (list.length > 1 && next === focusedShape)
                next = list[(list.indexOf(next) + 1) % list.length]
            focusedShape = next
        }
        onFocusedChanged: if (focused) pickShape()
        Component.onCompleted: if (focused) pickShape()

        Loader {
            id: shapeLoader
            anchors.centerIn: parent
            active: indicator.mode === 0
            sourceComponent: MaterialShape {
                implicitSize: Math.max(8, root.slot - 2)
                color: indicator.fg
                shape: indicator.focused ? indicator.focusedShape : (indicator.occupied ? MaterialShape.Square : MaterialShape.Circle)
                scale: indicator.focused ? 2 / 3 : indicator.occupied ? 1 / 3 : 1 / 4
                animationDuration: Theme.durDefaultSpatial
                animationEasing.type: Easing.BezierSpline
                animationEasing.bezierCurve: Theme.curveDefaultSpatial
                Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: indicator.mode !== 0
            text: indicator.label
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(10, Math.round(root.slot * 0.56))
            color: indicator.fg
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
        }
    }

    component WindowIcon: Item {
        id: winIcon

        required property var win
        // Normal glyphs use the on-surface variant; the active workspace's
        // glyphs sit on the accent pill and switch to on-accent, foreign
        // windows dim to the divider colour.
        property color tint: Theme.textSecondary

        // Generic window glyph for windows with no resolvable identity
        // (empty/undefined app id) or a lookup that returns nothing.
        readonly property string placeholderGlyph: "desktop_windows"

        // The settings app is a regular toplevel of this shell (app id
        // org.quickshell, title Settings). Its strip icon follows the page
        // currently open in the app (Theme.settingsAppIcon, published by
        // SettingsPanel) instead of the window class. Falls back to the
        // class lookup until the app has reported a page.
        readonly property bool isSettingsApp: {
            if (!win)
                return false
            return ("" + win.appId) === "org.quickshell" && ("" + win.title) === "Settings"
        }
        readonly property string settingsGlyph: isSettingsApp ? Theme.settingsAppIcon : ""

        // Resolved outside the bindings: Theme.appGlyphFor() / appIconFor()
        // memoise into Theme's caches, so calling them from a binding would
        // write a property the binding reads and trip a binding loop.
        property string glyph: ""
        property string iconSource: ""

        // JS undefined and the literal strings "undefined"/"null" (some
        // clients report those as app ids) count as missing, not as a name.
        function usableIconValue(value: var): string {
            if (value === undefined || value === null)
                return ""
            const s = ("" + value).trim()
            const low = s.toLowerCase()
            if (low === "undefined" || low === "null")
                return ""
            return s
        }

        function resolveMeta(): void {
            const id = usableIconValue(win ? win.appId : "")
            let g = ""
            let p = ""
            try {
                if (Theme.glyphWindowIcons)
                    g = id.length > 0 ? Theme.appGlyphFor(id) : ""
                else
                    p = id.length > 0 ? Theme.appIconFor(id) : ""
            } catch (e) {}
            g = usableIconValue(g)
            p = usableIconValue(p)
            if (glyph !== g)
                glyph = g
            if (iconSource !== p)
                iconSource = p
        }
        Component.onCompleted: resolveMeta()
        Connections {
            target: Theme
            function onAppsRevChanged() { winIcon.resolveMeta() }
            function onGlyphWindowIconsChanged() { winIcon.resolveMeta() }
        }

        // What the glyph Text draws: the settings page glyph first, then the
        // app glyph, then the placeholder. In image mode the Text only takes
        // over for the settings glyph or when there is no image at all.
        readonly property string textGlyph: {
            if (winIcon.settingsGlyph.length > 0)
                return winIcon.settingsGlyph
            if (Theme.glyphWindowIcons)
                return winIcon.glyph.length > 0 ? winIcon.glyph : winIcon.placeholderGlyph
            return winIcon.iconSource.length === 0 ? winIcon.placeholderGlyph : ""
        }
        readonly property bool nerdGlyph: winIcon.settingsGlyph.length > 0

        width: root.iconSize
        height: root.iconSize

        Text {
            anchors.fill: parent
            visible: winIcon.textGlyph.length > 0
            text: winIcon.textGlyph
            color: winIcon.tint
            font.family: winIcon.nerdGlyph ? Theme.iconFontFamily : Theme.glyphFontFamily
            font.pixelSize: Math.round(winIcon.height * (winIcon.nerdGlyph ? 1.05 : 1.2))
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        IconImage {
            anchors.fill: parent
            visible: !Theme.glyphWindowIcons && winIcon.textGlyph.length === 0
            source: winIcon.iconSource
            asynchronous: true
        }
    }

    component WorkspaceDelegate: Item {
        id: delegate

        required property var workspace
        required property int delegateIndex

        readonly property bool isActive: workspace ? !!workspace.active : false
        readonly property bool occupied: workspace ? !!workspace.occupied : false
        readonly property bool expanded: workspace ? workspace.shown !== false : false

        property bool ready: false
        readonly property real reveal: ready && expanded ? 1 : 0

        // Newly created delegates only get their final x/y after layout, so
        // notify the indicator once on completion as well.
        Component.onCompleted: {
            ready = true
            root.requestIndicatorUpdate()
        }

        readonly property var wsWindows: {
            UmbrielService.windows
            const ws = workspace
            if (!ws || !root.iconsOn)
                return []
            const target = Theme.workspacePerMonitor ? ("" + ws.output) : ""
            const list = UmbrielService.windowsOn(target, ws.index, Theme.workspaceIgnoredTags)
            // Stable icon slots: first-seen rank, not the compositor's
            // focus-ordered list (windowsOn returns a fresh array).
            list.sort((a, b) => root.windowRank(a) - root.windowRank(b))
            return list
        }
        readonly property var visibleWindows: wsWindows.slice(0, root.maxIcons)
        readonly property int winCount: visibleWindows.length

        readonly property real iconStack: (!root.vertical || winCount === 0) ? 0 : winCount * (root.iconSize + root.iconSpacing) + 2
        readonly property real iconStrip: (root.vertical || winCount === 0) ? 0 : root.iconSpacing + winCount * (root.iconSize + root.iconSpacing)

        implicitWidth: reveal * (root.vertical ? root.slot : root.slot + root.spacing + iconStrip)
        implicitHeight: reveal * (root.vertical ? root.slot + root.spacing + iconStack : root.slot)

        opacity: reveal
        scale: (0.45 + 0.55 * reveal) * (root.hoveredIndex === delegate.delegateIndex ? 1.06 : 1)

        readonly property color fgColour: {
            const ws = workspace
            if (!ws)
                return Theme.textMuted
            if (ws.foreign)
                return Theme.divider
            if (delegate.isActive && Theme.workspaceActiveIndicator)
                return Theme.onAccent
            if (delegate.isActive || delegate.occupied || Theme.workspaceOccupiedBg)
                return Theme.textPrimary
            return Theme.textMuted
        }
        readonly property color winIconColour: {
            const ws = workspace
            if (!ws)
                return Theme.textSecondary
            if (ws.foreign)
                return Theme.divider
            if (delegate.isActive && Theme.workspaceActiveIndicator)
                return Theme.onAccent
            return Theme.textSecondary
        }

        onXChanged: root.requestIndicatorUpdate()
        onYChanged: root.requestIndicatorUpdate()
        onWidthChanged: root.requestIndicatorUpdate()
        onHeightChanged: root.requestIndicatorUpdate()

        Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
        Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
        Behavior on implicitWidth { enabled: Theme.animationsEnabled && !root._outputSnap; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
        Behavior on implicitHeight { enabled: Theme.animationsEnabled && !root._outputSnap; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }

        // Gap marker between non-consecutive workspaces (Caelestia GapMarkers,
        // only when showUnoccupied is off).
        Rectangle {
            id: gapMarker
            visible: !Theme.workspaceShowUnoccupied && delegate.workspace && delegate.workspace.gapBefore && delegate.reveal > 0.5
            color: Theme.outline
            antialiasing: Theme.shapesAa
            readonly property real shift: {
                const ws = delegate.workspace
                if (!ws)
                    return 0
                if (ws.active)
                    return -root.spacing / 2 - 1
                if (ws.prevActive)
                    return root.spacing / 2
                return 0
            }
            x: root.vertical ? root.pad : (-root.spacing / 2 + shift)
            y: root.vertical ? (-root.spacing / 2 + shift) : root.pad
            width: root.vertical ? Math.max(0, parent.width - 2 * root.pad) : 1
            height: root.vertical ? 1 : Math.max(0, parent.height - 2 * root.pad)
            Behavior on x { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
            Behavior on y { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
        }

        // Horizontal bar: shape + window icons side by side.
        Row {
            visible: !root.vertical
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.iconSpacing
            WorkspaceIndicator {
                workspace: delegate.workspace
                focused: delegate.isActive
                occupied: delegate.occupied
                fg: delegate.fgColour
            }
            Row {
                visible: delegate.winCount > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.iconSpacing
                Repeater {
                    model: delegate.visibleWindows
                    delegate: WindowIcon {
                        required property var modelData
                        win: modelData
                        tint: delegate.winIconColour
                    }
                }
            }
        }

        // Vertical bar: Caelestia stacks window icons below the shape.
        Column {
            visible: root.vertical
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            spacing: root.iconSpacing
            WorkspaceIndicator {
                workspace: delegate.workspace
                focused: delegate.isActive
                occupied: delegate.occupied
                fg: delegate.fgColour
            }
            Column {
                visible: delegate.winCount > 0
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.iconSpacing
                Repeater {
                    model: delegate.visibleWindows
                    delegate: WindowIcon {
                        required property var modelData
                        win: modelData
                        tint: delegate.winIconColour
                    }
                }
            }
        }
    }

    // Placeholder while the first Umbriel poll is in flight.
    Text {
        anchors.centerIn: parent
        visible: root.workspaceModel.length === 0
        text: "—"
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(13)
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }

    // ---- input (BarModule forwards hover/click as root-local pixels) ----
    property int hoveredIndex: -1

    function pickDelegateAt(px: real, py: real): var {
        const container = root.vertical ? vCol : hRow
        for (let i = 0; i < container.children.length; i++) {
            const ch = container.children[i]
            if (!ch || ch.workspace === undefined || ch.delegateIndex === undefined || !ch.visible)
                continue
            if (ch.reveal !== undefined && ch.reveal < 0.5)
                continue
            const lp = ch.mapFromItem(root, px, py)
            if (lp.x >= 0 && lp.x <= ch.width && lp.y >= 0 && lp.y <= ch.height)
                return ch
        }
        return null
    }

    function setHoverAt(px: real, py: real): void {
        const hit = pickDelegateAt(px, py)
        hoveredIndex = hit ? hit.delegateIndex : -1
    }

    function clearHover(): void {
        hoveredIndex = -1
    }

    function activateWorkspace(workspace: var): void {
        if (!workspace)
            return
        UmbrielService.activateTag(workspace.index, workspace.output)
    }

    function activateAt(px: real, py: real): bool {
        const hit = pickDelegateAt(px, py)
        if (!hit)
            return false
        activateWorkspace(hit.workspace)
        return true
    }

    function cycleWorkspace(down: bool): void {
        if (down)
            UmbrielService.prevTag(root.screenName)
        else
            UmbrielService.nextTag(root.screenName)
    }
}
