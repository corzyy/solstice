pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import M3Shapes
import "../../themes"
import "../../services"
import "../../ui"
import "./pages" as Pages

// Settings window — 1:1 Caelestia Nexus port (caelestia-dots/shell):
//   - window: height = 70% screen, 16:9, radius = Theme.cornerRadius
//   - nav pane: margins 16, width min(600, width/3), SearchBar +
//     NavLocations list (filled cards, circle icon, 32/28/4 radii, press 12)
//   - pages: margins 28, content capped at 800, StackView push/pop animation
//     (exit fade 200ms; enter holds 200ms then fades 300ms while sliding
//     from ±96px)
// Backends stay solstice (Theme, SettingsService, NetworkService, …).
// Unlike the other shell surfaces this is a regular toplevel window
// (FloatingWindow), managed by the compositor like any other app window:
// it shows up in task switchers, can be moved/resized freely and closed by
// the WM (closed() -> dismissed()).
Scope {
    id: settingsScope
    property bool showSettings: false
    property string section: "wallpaper"
    property string filterText: ""
    signal dismissed()

    property bool _winVisible: showSettings
    // Unmap delay after close. This is a regular toplevel whose only close
    // run is the settingsBox FadeThrough (Theme.durMotionFadeThrough; the
    // outgoing half reaches alpha 0 after ~15% of the run). Theme
    // .panelHideDelay is sized for bar-panel morph handoffs and kept the
    // mapped window — compositor border/shadow and input region included —
    // on screen far too long after pressing X.
    readonly property int hideDelay: Theme.animMs(150)
    Timer { id: hideTimer; interval: settingsScope.hideDelay; repeat: false; onTriggered: if (!settingsScope.showSettings) settingsScope._winVisible = false }

    // Adaptive layout: below this width the nav rail and the pages no longer
    // fit side by side, so the panel collapses to a single pane (category
    // list <-> page with a back button), like Material's expanded breakpoint.
    // The nav needs ~280 and a readable slider/toggle card ~500 plus gaps.
    readonly property int compactBreakpoint: 840
    readonly property bool compact: settingsBox.width > 0 && settingsBox.width < compactBreakpoint
    // Compact-only pane state: false = category list, true = page.
    property bool pagePane: false

    // Page registry (id + title + description + category). Categories only
    // create the group gaps / corner treatment in the nav list, like Nexus.
    readonly property var navEntries: [
        {id: "wallpaper", title: "Wallpaper & style", icon: "󰋩", desc: "Wallpaper, fonts, colours", category: "appearance"},
        {id: "network", title: "Network & internet", icon: "󰖩", desc: "Wi-Fi, Ethernet, DNS", category: "connectivity"},
        {id: "bluetooth", title: "Bluetooth", icon: "󰂯", desc: "Devices, pairing, power", category: "connectivity"},
        {id: "audio", title: "Sound", icon: "󰕾", desc: "Volume, output & input devices", category: "connectivity"},
        {id: "global", title: "Appearance", icon: "󰔎", desc: "Rounding, animations, fonts", category: "device"},
        {id: "umbriel", title: "Compositor", icon: "󰖔", desc: "Layout, gaps, borders", category: "device"},
        {id: "panels", title: "Panels", icon: "󰍹", desc: "Taskbar and shell surfaces", category: "shell"},
        {id: "apps", title: "Apps", icon: "󰀻", desc: "Terminal, shell prompt", category: "system"},
        {id: "setup", title: "Setup", icon: "󰒓", desc: "Date & time, language, keybinds, updates", category: "system"},
        {id: "about", title: "About", icon: "󰋼", desc: "System information", category: "system"}
    ]
    // M3 expressive shape pool for the current entry's icon container, same
    // pool as the power menu (PowerAction.shapeChoices). Each entry re-rolls
    // (never twice in a row) when it becomes the current page; MaterialShape
    // morphs circle <-> pick on the shared spatial token. Circle is not in
    // the pool: it is the idle badge shape, so a pick landing on it would
    // read as no shape at all.
    readonly property var navIconShapes: [
        MaterialShape.Square, MaterialShape.Slanted, MaterialShape.Pill,
        MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny,
        MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
        MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided,
        MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf,
        MaterialShape.Clover8Leaf
    ]
    readonly property var sectionIds: navEntries.map(e => e.id)
    readonly property bool searching: (filterText || "").trim().length > 0
    readonly property var filteredEntries: {
        let q = (settingsScope.filterText || "").toLowerCase().trim()
        if (q.length === 0) return settingsScope.navEntries
        return settingsScope.navEntries.filter(e => ((e.title + " " + e.desc).toLowerCase().includes(q)))
    }
    function entryFor(id: string): var {
        for (let i = 0; i < navEntries.length; i++) if (navEntries[i].id === id) return navEntries[i]
        return navEntries[0]
    }
    function sectionTitle(id: string): string { return entryFor(id).title }
    // Mouse-wheel travel per notch for the settings lists. Qt's Flickable
    // moves wheelScrollLines * 24 (≈72px) per notch plus velocity
    // acceleration; this fixed step travels further in a single notch.
    // Touchpads are untouched (WheelHandler defaults to mouse devices only)
    // and deeper scrollables (sliders, wallpaper grid) still handle the wheel
    // first because they sit closer to the cursor in the delivery chain.
    readonly property real wheelNotchPixels: 180
    function wheelScroll(flick, event): void {
        const angle = event.angleDelta.y
        const pixel = event.pixelDelta.y
        let dy = 0
        if (angle !== 0) dy = angle / 120 * settingsScope.wheelNotchPixels
        else if (pixel !== 0) dy = pixel
        else return
        flick.contentY -= dy
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY))
        event.accepted = true
    }
    function selectSection(id: string): void {
        // Legacy ids: "bar" was the pre-Panels id, "notif" now lives as a
        // Panels sub-page.
        let nid = (id === "bar" || id === "notif") ? "panels" : id
        section = sectionIds.indexOf(nid) >= 0 ? nid : "wallpaper"
        // In compact mode selecting opens the page pane (back button returns
        // to the list); in wide mode both panes stay visible so this is inert.
        pagePane = true
    }

    function pageFor(s: string): Component {
        switch (s) {
        case "wallpaper": return wallpaperStylesComp
        case "network": return networkComp
        case "bluetooth": return bluetoothComp
        case "umbriel": return umbrielComp
        case "audio": return audioComp
        case "apps": return appsComp
        case "panels": return panelsComp
        case "workspaces": return workspacesComp
        case "about": return aboutComp
        case "setup": return setupComp
        default: return globalComp
        }
    }
    function sectionIndex(id: string): int {
        let i = sectionIds.indexOf(id)
        return i >= 0 ? i : 0
    }

    onShowSettingsChanged: {
        if (showSettings) {
            _winVisible = true
            hideTimer.stop()
            // Fresh open starts on the category list when compact.
            pagePane = false
            SettingsService.refresh()
            try { UmbrielService.refresh() } catch (e) {}
        } else {
            filterText = ""
            hideTimer.restart()
        }
    }

    IpcHandler {
        target: "settings"
        function state(): string { return "visible=" + settingsScope.showSettings + " section=" + settingsScope.section }
    }

    // Regular toplevel window instead of a layer-shell surface. `screen` is
    // deliberately left unbound: it would snap the window back on every
    // manual move to another output. The initial size still follows the
    // primary screen (Nexus: 70% height, 16:9); afterwards the size is
    // owned by the user/compositor.
    FloatingWindow {
        id: win
        title: "Settings"
        visible: settingsScope._winVisible
        color: "transparent"
        readonly property var bootScreen: {
            try {
                const vals = Quickshell.screens.values
                for (let i = 0; i < vals.length; i++) if (Theme.isPrimaryScreen(vals[i])) return vals[i]
                if (vals.length > 0) return vals[0]
            } catch (e) {}
            return null
        }
        implicitHeight: Math.round((bootScreen ? bootScreen.height : 900) * 0.7)
        implicitWidth: Math.min(Math.round(implicitHeight * (16 / 9)), (bootScreen ? bootScreen.width : 1600) - 64)
        minimumSize: Qt.size(720, 480)
        // WM close (titlebar/taskbar shortcut): keep the shell state in sync.
        // Not emitted for visible:false, so our own hide path is unaffected.
        // Flip _winVisible too: the compositor already unmapped the window,
        // and this lets the `visible:` binding re-fire if the item survives
        // (reopened within the loader's hold window).
        onClosed: {
            settingsScope._winVisible = false
            settingsScope.dismissed()
        }
        // Re-assert keyboard focus once the backing window exists: unlike a
        // layer surface the compositor may map us unfocused.
        onWindowConnected: Qt.callLater(() => focusItem.forceActiveFocus())
        property string shownSection: ""
        property int lastIdx: 0
        property int animDir: 1
        function showPage(section: string): void {
            if (!pageWrap.slot(pageWrap.frontSlot)) {
                Qt.callLater(() => win.showPage(section))
                return
            }
            win.shownSection = section
            win.lastIdx = settingsScope.sectionIndex(section)
            pageWrap.reset(section)
        }
        Component.onCompleted: if (settingsScope.showSettings) win.showPage(settingsScope.section)
        Connections {
            target: settingsScope
            function onShowSettingsChanged() {
                if (settingsScope.showSettings) {
                    win.showPage(settingsScope.section)
                } else {
                    pageWrap.leave()
                }
            }
            function onSectionChanged() {
                if (!settingsScope.showSettings) {
                    win.shownSection = settingsScope.section
                    win.lastIdx = settingsScope.sectionIndex(settingsScope.section)
                    return
                }
                pageWrap.switchTo(settingsScope.section)
            }
            // Hiding a pane (compact list <-> page) drops the active focus
            // item, which would kill the window-level Escape/shortcut Keys.
            // Only reclaim it when a pane actually got hidden — the wide
            // layout keeps the current focus (e.g. the search field).
            function onPagePaneChanged() { if (settingsScope.compact) focusItem.forceActiveFocus() }
            function onCompactChanged() {
                if (!settingsScope.compact) return
                if (settingsScope.pagePane) { focusItem.forceActiveFocus(); return }
                if (!navSearch.activeFocus) focusItem.forceActiveFocus()
            }
        }
        Item {
            id: focusItem
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (settingsScope.compact && settingsScope.pagePane) settingsScope.pagePane = false
                    else if (settingsScope.filterText.length > 0) settingsScope.filterText = ""
                    else settingsScope.dismissed()
                    event.accepted = true
                } else if (event.modifiers === Qt.NoModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    let i = event.key - Qt.Key_1
                    if (i >= 0 && i < settingsScope.sectionIds.length) settingsScope.selectSection(settingsScope.sectionIds[i])
                    event.accepted = true
                } else if (event.modifiers === Qt.NoModifier && event.key === Qt.Key_0) {
                    if (settingsScope.sectionIds.length > 9) settingsScope.selectSection(settingsScope.sectionIds[9])
                    event.accepted = true
                }
            }
            Component.onCompleted: forceActiveFocus()
        }
        Rectangle {
            antialiasing: Theme.shapesAa
            id: settingsBox
            // The window itself is the Nexus box now: no scrim, no
            // outside-click dismissal (nothing lives behind a regular
            // window), and clicks on empty space simply do nothing.
            anchors.fill: parent
            color: Theme.panelWindowSurface
            radius: Theme.cornerRadius
            clip: true
            Motion {
                id: boxMotion
                active: settingsScope.showSettings
                pattern: Motion.FadeThrough
            }
            opacity: boxMotion.opacity
            scale: boxMotion.scale
            transformOrigin: Item.Center
            // Window button (Nexus windowBtn): rounded, error on hover.
            // Compact page pane: align with the page's own back button row.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: settingsScope.compact && settingsScope.pagePane ? 16 : 8
                width: 36; height: 36
                radius: closeMouse.pressed ? 8 : 18
                z: 10
                color: Theme.panelCardHigh
                antialiasing: Theme.shapesAa
                Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: Theme.fs(14)
                    color: closeMouse.containsMouse ? Theme.error : Theme.textSecondary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                StateLayer { id: closeMouse; radius: 18; color: Theme.error; onClicked: settingsScope.dismissed() }
            }
            Item {
                anchors.fill: parent
                anchors.margins: 16
                // ---- nav pane -------------------------------------------------
                Column {
                    id: navCol
                    anchors.left: parent.left
                    // Compact: one centered column. Wide: the Nexus rail
                    // (min(600, width/3)) pinned to the left.
                    anchors.leftMargin: settingsScope.compact ? (parent.width - width) / 2 : 0
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: settingsScope.compact ? Math.min(600, parent.width) : Math.min(600, Math.round(settingsBox.width / 3))
                    spacing: 16
                    // Crossfade to the page pane (and back) in compact mode.
                    opacity: settingsScope.compact && settingsScope.pagePane ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                    NexusControls.SearchBar {
                        id: navSearch
                        width: parent.width
                        text: settingsScope.filterText
                        onTextChanged2: t => settingsScope.filterText = t
                    }
                    Flickable {
                        id: navFlick
                        width: parent.width
                        height: navCol.height - navSearch.height - navCol.spacing
                        clip: true
                        contentHeight: navList.implicitHeight
                        contentWidth: width
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        WheelHandler {
                            onWheel: event => settingsScope.wheelScroll(navFlick, event)
                        }
                        Column {
                            id: navList
                            width: navFlick.width
                            spacing: 4
                            Repeater {
                                model: settingsScope.filteredEntries
                                delegate: Column {
                                    id: navEntryWrap
                                    required property var modelData
                                    required property int index
                                    readonly property bool catStart: index === 0 || settingsScope.filteredEntries[index - 1].category !== modelData.category
                                    width: navList.width
                                    spacing: 0
                                    Item {
                                        width: 1
                                        height: navEntryWrap.catStart && navEntryWrap.index !== 0 ? 12 : 0
                                    }
                                    Rectangle {
                                        id: navEntry
                                        width: navEntryWrap.width
                                        readonly property bool isCurrent: navEntryWrap.modelData.id === settingsScope.section
                                        readonly property bool catEnd: navEntryWrap.index === settingsScope.filteredEntries.length - 1 || settingsScope.filteredEntries[navEntryWrap.index + 1].category !== navEntryWrap.modelData.category
                                        // Icon container shape while this entry is
                                        // current: re-rolled per focus, circle
                                        // otherwise (MaterialShape morphs).
                                        property int iconShape: MaterialShape.Circle
                                        function pickIconShape(): void {
                                            const list = settingsScope.navIconShapes
                                            if (list.length === 0) return
                                            let next = list[Math.floor(Math.random() * list.length)]
                                            if (list.length > 1 && next === iconShape)
                                                next = list[(list.indexOf(next) + 1) % list.length]
                                            iconShape = next
                                        }
                                        onIsCurrentChanged: if (isCurrent) pickIconShape()
                                        Component.onCompleted: if (isCurrent) pickIconShape()
                                        height: {
                                            const h = Math.max(30, navColText.implicitHeight) + 32
                                            return h % 2 === 0 ? h : h + 1
                                        }
                                        color: navEntry.isCurrent ? Theme.secondary_container : Theme.panelCardHigh
                                        topLeftRadius: navMouse.pressed ? 12 : navEntry.isCurrent ? 32 : navEntryWrap.catStart ? 28 : 4
                                        topRightRadius: navMouse.pressed ? 12 : navEntry.isCurrent ? 32 : navEntryWrap.catStart ? 28 : 4
                                        bottomLeftRadius: navMouse.pressed ? 12 : navEntry.isCurrent ? 32 : navEntry.catEnd ? 28 : 4
                                        bottomRightRadius: navMouse.pressed ? 12 : navEntry.isCurrent ? 32 : navEntry.catEnd ? 28 : 4
                                        antialiasing: Theme.shapesAa
                                        Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                                        Behavior on topLeftRadius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                                        Behavior on topRightRadius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                                        Behavior on bottomLeftRadius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                                        Behavior on bottomRightRadius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                                        Item {
                                            id: layout
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            MaterialShape {
                                                id: navIconBg
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                implicitSize: Math.max(30, navColText.implicitHeight)
                                                color: navEntry.isCurrent ? Theme.accent : Theme.secondary_container
                                                shape: navEntry.isCurrent ? navEntry.iconShape : MaterialShape.Circle
                                                animationDuration: Theme.durDefaultSpatial
                                                animationEasing.type: Easing.BezierSpline
                                                animationEasing.bezierCurve: Theme.curveDefaultSpatial
                                                Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    // Nerd-font glyphs hang on the baseline inside a much
                                                    // taller line box (JetBrainsMono NF carries ~6px of
                                                    // descent at fs(20) that icon ink never uses), so
                                                    // centering the line box leaves the ink ~1px high once
                                                    // NativeRendering quantises it. Nudge the ink centre
                                                    // onto the badge centre.
                                                    anchors.verticalCenterOffset: 1
                                                    text: navEntryWrap.modelData.icon
                                                    font.family: Theme.iconFontFamily
                                                    font.pixelSize: Theme.fs(20)
                                                    color: navEntry.isCurrent ? Theme.onAccent : Theme.on_secondary_container
                                                    antialiasing: Theme.textAa
                                                    renderType: Theme.textRenderType
                                                    Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                                                }
                                            }
                                            Column {
                                                id: navColText
                                                anchors.left: navIconBg.right
                                                anchors.leftMargin: 12
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0
                                                Text {
                                                    width: parent.width
                                                    text: navEntryWrap.modelData.title
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(14)
                                                    color: navEntry.isCurrent ? Theme.on_secondary_container : Theme.textPrimary
                                                    elide: Text.ElideRight
                                                    antialiasing: Theme.textAa
                                                    renderType: Theme.textRenderType
                                                }
                                                Text {
                                                    width: parent.width
                                                    text: navEntryWrap.modelData.desc
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: Theme.fs(11)
                                                    color: navEntry.isCurrent ? Qt.alpha(Theme.on_secondary_container, 0.8) : Theme.textSecondary
                                                    elide: Text.ElideRight
                                                    antialiasing: Theme.textAa
                                                    renderType: Theme.textRenderType
                                                }
                                            }
                                        }
                                        StateLayer {
                                            id: navMouse
                                            showHoverBackground: false
                                            color: navEntry.isCurrent ? Theme.on_secondary_container : Theme.textPrimary
                                            onClicked: settingsScope.selectSection(navEntryWrap.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // ---- pages ----------------------------------------------------
                Item {
                    id: pageWrap
                    anchors.left: parent.left
                    // Wide: sit right of the nav rail. Compact: own the whole
                    // window (the list is hidden behind the crossfade).
                    anchors.leftMargin: settingsScope.compact ? 0 : navCol.width + 12
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    opacity: settingsScope.compact && !settingsScope.pagePane ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                    property int frontSlot: 0
                    function slot(idx: int): var { return pageSlots.itemAt(idx) }
                    function snap(): void {
                        for (let i = 0; i < pageSlots.count; i++) {
                            const s = pageSlots.itemAt(i)
                            if (s) s.snap()
                        }
                    }
                    function reset(section: string): void {
                        const front = pageWrap.slot(pageWrap.frontSlot)
                        const back = pageWrap.slot(1 - pageWrap.frontSlot)
                        if (back) back.clear()
                        if (front) front.showInstant(section)
                        Qt.callLater(() => pageWrap.snap())
                    }
                    function switchTo(section: string): void {
                        if (win.shownSection === section) return
                        const backIdx = 1 - pageWrap.frontSlot
                        const back = pageWrap.slot(backIdx)
                        const front = pageWrap.slot(pageWrap.frontSlot)
                        if (!back) {
                            Qt.callLater(() => pageWrap.switchTo(section))
                            return
                        }
                        const idx = settingsScope.sectionIndex(section)
                        win.animDir = idx >= win.lastIdx ? 1 : -1
                        win.lastIdx = idx
                        if (front) front.notifyHidden()
                        if (front) front.startExit()
                        back.startEnter(section, win.animDir)
                        win.shownSection = section
                        pageWrap.frontSlot = backIdx
                    }
                    function leave(): void {
                        const front = pageWrap.slot(pageWrap.frontSlot)
                        if (front) front.notifyHidden()
                    }
                    Repeater {
                        id: pageSlots
                        model: 2
                        delegate: Item {
                            id: slot
                            required property int index
                            anchors.fill: parent
                            property Component sectionComp: null
                            // Nexus StackView push/pop: opacity + x slide.
                            property real stackOpacity: 0
                            property real stackX: 0
                            property bool enterPending: false
                            opacity: stackOpacity
                            x: stackX
                            visible: stackOpacity > 0.01

                            NumberAnimation { id: exitAnim; target: slot; property: "stackOpacity"; to: 0; duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
                            NumberAnimation { id: enterFade; target: slot; property: "stackOpacity"; to: 1; duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                            NumberAnimation { id: enterSlide; target: slot; property: "stackX"; to: 0; duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                            Timer {
                                id: enterTimer
                                interval: Theme.durDefaultEffects
                                repeat: false
                                onTriggered: {
                                    if (!slot.enterPending) return
                                    slot.enterPending = false
                                    enterFade.start()
                                    enterSlide.start()
                                }
                            }

                            function showInstant(sec: string): void {
                                slot.enterPending = false
                                exitAnim.stop(); enterFade.stop(); enterSlide.stop(); enterTimer.stop()
                                slot.sectionComp = settingsScope.pageFor(sec)
                                slot.stackOpacity = 1
                                slot.stackX = 0
                                Qt.callLater(() => {
                                    slot.notifyShown()
                                    pageFlick.contentY = 0
                                })
                            }
                            function startEnter(sec: string, dir: int): void {
                                exitAnim.stop(); enterFade.stop(); enterSlide.stop(); enterTimer.stop()
                                slot.sectionComp = settingsScope.pageFor(sec)
                                if (!Theme.animationsEnabled) {
                                    slot.enterPending = false
                                    slot.stackOpacity = 1
                                    slot.stackX = 0
                                    Qt.callLater(() => {
                                        slot.notifyShown()
                                        pageFlick.contentY = 0
                                    })
                                    return
                                }
                                slot.stackOpacity = 0
                                slot.stackX = dir * 96
                                slot.enterPending = true
                                enterTimer.restart()
                                Qt.callLater(() => {
                                    slot.notifyShown()
                                    pageFlick.contentY = 0
                                })
                            }
                            function startExit(): void {
                                slot.enterPending = false
                                enterTimer.stop(); enterFade.stop(); enterSlide.stop()
                                if (!Theme.animationsEnabled) slot.stackOpacity = 0
                                else exitAnim.start()
                            }
                            function clear(): void {
                                slot.notifyHidden()
                                slot.sectionComp = null
                                slot.enterPending = false
                                exitAnim.stop(); enterFade.stop(); enterSlide.stop(); enterTimer.stop()
                                slot.stackOpacity = 0
                                slot.stackX = 0
                            }
                            function notifyShown(): void {
                                if (pageLoader.item && pageLoader.item.notifyShown) pageLoader.item.notifyShown()
                            }
                            function notifyHidden(): void {
                                if (pageLoader.item && pageLoader.item.notifyHidden) pageLoader.item.notifyHidden()
                            }
                            function snap(): void {
                                exitAnim.stop(); enterFade.stop(); enterSlide.stop(); enterTimer.stop()
                                slot.enterPending = false
                                slot.stackOpacity = pageWrap.frontSlot === slot.index ? 1 : 0
                                slot.stackX = 0
                            }
                            Flickable {
                                id: pageFlick
                                anchors.fill: parent
                                anchors.rightMargin: 12
                                clip: true
                                contentHeight: pageCol.implicitHeight + 28
                                contentWidth: width
                                boundsBehavior: Flickable.StopAtBounds
                                flickableDirection: Flickable.VerticalFlick
                                WheelHandler {
                                    onWheel: event => settingsScope.wheelScroll(pageFlick, event)
                                }
                                Column {
                                    id: pageCol
                                    width: Math.min(800, pageFlick.width)
                                    x: (pageFlick.width - width) / 2
                                    spacing: 0
                                    Loader {
                                        id: pageLoader
                                        width: parent.width
                                        active: settingsScope._winVisible
                                        asynchronous: false
                                        sourceComponent: slot.sectionComp
                                    }
                                    Item { width: 1; height: 28 }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Pages derive from NexusControls.PageBase, whose header can host a back
    // button. In compact mode it returns to the category list; in wide mode
    // both panes are visible so the button stays hidden.
    // The default landing page also owns sub-views (wallpapers/colours/fonts):
    // the header back only returns to the category list from the main view,
    // sub-views use their own in-page back row.
    Component {
        id: wallpaperStylesComp
        Pages.WallpaperStylesPage {
            id: wallpaperStylesPage
            showBack: settingsScope.compact && wallpaperStylesPage.view === ""
            onBackRequested: settingsScope.pagePane = false
        }
    }
    Component { id: networkComp; Pages.NetworkPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    Component { id: bluetoothComp; Pages.BluetoothPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    Component { id: globalComp; Pages.GlobalPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    Component { id: umbrielComp; Pages.UmbrielPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    Component { id: audioComp; Pages.AudioPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    Component { id: appsComp; Pages.AppsPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    // PanelsPage drills into its own sub-pages: while drilled in, its single
    // in-page back row (both layouts) steps out of the panel; only at the
    // picker does the compact back return to the category list, so PageBase's
    // header back must stay hidden there to avoid a second button.
    Component {
        id: panelsComp
        Pages.PanelsPage {
            id: panelsPage
            showBack: settingsScope.compact && panelsPage.panelId === ""
            onBackRequested: settingsScope.pagePane = false
        }
    }
    Component { id: workspacesComp; Pages.WorkspacesPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    Component { id: aboutComp; Pages.AboutPage { showBack: settingsScope.compact; onBackRequested: settingsScope.pagePane = false } }
    // SetupPage drills into its own Date & Time / Language & Region / Keybinds / Update
    // sub-pages: while drilled in the in-page back row steps back to the main view; only at
    // the main view does the compact back return to the category list, so
    // PageBase's header back must stay hidden in a sub-view to avoid a
    // second button.
    Component {
        id: setupComp
        Pages.SetupPage {
            id: setupPage
            hostWindow: win
            showBack: settingsScope.compact && setupPage.view === ""
            onBackRequested: settingsScope.pagePane = false
        }
    }
}
