pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../../style/themes"
import "../../backend/services"

// Dock — solstice port of DankMaterialShell's dock core
// (AvengeMedia/DankMaterialShell, Modules/DankDock).
// Single dock on the primary screen: pinned launchers + running apps
// grouped by app id, launcher button, running indicators, auto-hide,
// overlay layer and per-edge position. DMS multi-dock configs, bar
// widgets, trash, smart-hide and connected-frame chrome are out of scope.
Scope {
    id: dockScope
    signal requestLauncher()

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData
            visible: Theme.dockEnabled && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            WlrLayershell.namespace: "solstice-dock"
            WlrLayershell.layer: Theme.dockOverlay ? WlrLayer.Overlay : WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            readonly property string screenName: {
                try { return "" + modelData.name } catch (e) { return "" }
            }
            readonly property bool vertical: Theme.dockVertical
            readonly property string edge: Theme.dockPosition
            readonly property int iconSize: Theme.dockIconSize
            readonly property int pad: Theme.dockSpacing
            readonly property int gap: Theme.dockItemSpacing
            readonly property int margin: Theme.dockMargin
            readonly property int lane: 6
            readonly property int thickness: iconSize + pad * 2 + lane + 4
            readonly property bool autoHide: Theme.dockAutoHide
            // Fullscreen collapse mirrors the top bar: a fullscreen window on
            // this output hides the dock unless "Show on fullscreen" is on.
            readonly property bool fullscreenHere: HyprlandService.isOutputFullscreen(screenName)
            readonly property bool hiddenForFullscreen: fullscreenHere && !Theme.dockShowFullscreen
            // Reserve the strip so tiled windows don't slide under the dock
            // (auto-hide and fullscreen-hidden docks reserve nothing).
            exclusiveZone: (!Theme.dockEnabled || autoHide || hiddenForFullscreen) ? 0 : (thickness + margin)
            mask: Region { item: hitArea }
            // Stay clickable while a bar panel is open (same grab the
            // taskbar uses): otherwise the first dock click would only
            // dismiss the panel.
            Component.onCompleted: HyprlandService.registerBarWindow(dockWindow)
            Component.onDestruction: HyprlandService.unregisterBarWindow(dockWindow)

            // ---- running windows, grouped by app id ----
            readonly property var runningWindows: {
                HyprlandService.windows
                let list = HyprlandService.windows || []
                if (Theme.dockCurrentWorkspaceOnly) {
                    const active = HyprlandService.activeWorkspaceIndex()
                    list = list.filter(w => w && parseInt(w.index) === active)
                }
                return list
            }
            readonly property string focusedWinId: HyprlandService.focusedWindowId
            readonly property string focusedApp: HyprlandService.focusedAppId
            readonly property var pinnedIds: Theme.dockPinnedApps()

            // One entry per pinned app + one per running app group.
            // { appId, name, running, active, pinned, wins }
            readonly property var dockItems: {
                runningWindows; focusedWinId; focusedApp; pinnedIds
                HyprlandService.monitors
                const pins = Array.isArray(pinnedIds) ? pinnedIds : []
                const runs = Array.isArray(runningWindows) ? runningWindows : []
                const grouped = Theme.dockGroupByApp
                const items = []
                const seen = {}
                const winsByApp = {}
                for (let i = 0; i < runs.length; i++) {
                    const w = runs[i]
                    if (!w) continue
                    const id = (w.appId || "").trim()
                    if (id.length === 0) continue
                    if (!winsByApp[id]) winsByApp[id] = []
                    winsByApp[id].push(w)
                }
                const isActiveWin = w => w && (("" + w.id) === ("" + focusedWinId) || !!w.focused)
                if (grouped) {
                    for (let p = 0; p < pins.length; p++) {
                        const id = (pins[p] || "").trim()
                        if (id.length === 0 || seen[id]) continue
                        seen[id] = true
                        const wins = winsByApp[id] || []
                        let active = false
                        for (let k = 0; k < wins.length; k++) if (isActiveWin(wins[k])) { active = true; break }
                        if (wins.length === 0 && ("" + focusedApp) === id) active = true
                        items.push({ appId: id, running: wins.length > 0, active: active, pinned: true, wins: wins })
                    }
                    for (const id in winsByApp) {
                        if (seen[id]) continue
                        seen[id] = true
                        const wins = winsByApp[id]
                        let active = false
                        for (let k = 0; k < wins.length; k++) if (isActiveWin(wins[k])) { active = true; break }
                        items.push({ appId: id, running: true, active: active, pinned: false, wins: wins })
                    }
                } else {
                    for (let p = 0; p < pins.length; p++) {
                        const id = (pins[p] || "").trim()
                        if (id.length === 0 || seen["pin:" + id]) continue
                        seen["pin:" + id] = true
                        const wins = winsByApp[id] || []
                        items.push({ appId: id, winId: "", title: "", running: wins.length > 0, active: wins.some(isActiveWin), pinned: true, wins: wins })
                    }
                    for (let i = 0; i < runs.length; i++) {
                        const w = runs[i]
                        if (!w) continue
                        const id = (w.appId || "").trim()
                        if (id.length === 0) continue
                        items.push({ appId: id, winId: "" + w.id, title: "" + (w.title || ""), running: true, active: isActiveWin(w), pinned: pins.indexOf(id) >= 0, wins: [w] })
                    }
                }
                return items
            }

            function toplevelByAddr(addr: string): var {
                try {
                    const list = Hyprland.toplevels.values || []
                    for (let i = 0; i < list.length; i++) {
                        const t = list[i]
                        if (!t) continue
                        try { if (t.address && ("" + t.address) === addr) return t } catch (e) {}
                        try {
                            const ipc = t.lastIpcObject
                            if (ipc && ipc.address && ("" + ipc.address) === addr) return t
                        } catch (e2) {}
                    }
                } catch (e3) {}
                return null
            }
            function activateWindow(win: var): void {
                if (!win) return
                const addr = "" + win.id
                const t = toplevelByAddr(addr)
                if (t) {
                    try { t.activate(); return } catch (e) {}
                }
                try { Hyprland.dispatch("focuswindow address:" + addr) } catch (e2) {}
            }
            function closeWindow(win: var): void {
                if (!win) return
                const addr = "" + win.id
                const t = toplevelByAddr(addr)
                if (t) {
                    try { t.close(); return } catch (e) {}
                }
                try { Hyprland.dispatch("closewindow address:" + addr) } catch (e2) {}
            }
            function launchApp(appId: string): void {
                const id = (appId || "").trim()
                if (id.length === 0) return
                try {
                    const e = Theme.desktopEntryFor(id)
                    if (e && typeof e.execute === "function") { e.execute(); return }
                } catch (err) {}
                try {
                    const e2 = Theme.desktopEntryFor(id.replace(/\.desktop$/, ""))
                    if (e2 && typeof e2.execute === "function") { e2.execute(); return }
                } catch (err2) {}
            }
            function activateItem(item: var): void {
                if (!item) return
                const wins = item.wins || []
                if (wins.length === 1) {
                    // Focus the window (already-focused stays focused;
                    // Hyprland has no minimise, so no toggle-away).
                    activateWindow(wins[0])
                    return
                }
                if (wins.length > 1) {
                    // Cycle focus through the group's windows.
                    let idx = -1
                    for (let i = 0; i < wins.length; i++) {
                        if (("" + wins[i].id) === ("" + focusedWinId)) { idx = i; break }
                    }
                    activateWindow(wins[(idx + 1) % wins.length])
                    return
                }
                launchApp(item.appId)
            }

            property string menuAppId: ""
            property bool menuOpen: false
            function openMenu(appId: string): void {
                menuAppId = appId
                menuOpen = true
            }
            function closeMenu(): void { menuOpen = false }

            // Auto-hide reveal: the box collapses to a 2px strip that keeps
            // the window mapped for hover, like the top bar.
            property bool hovered: false
            readonly property bool revealed: !autoHide || hovered || menuOpen

            Item {
                id: hitArea
                // Centred floating box on the dock edge.
                anchors.bottom: dockWindow.edge === "bottom" ? parent.bottom : undefined
                anchors.top: dockWindow.edge === "top" ? parent.top : undefined
                anchors.left: dockWindow.edge === "left" ? parent.left : undefined
                anchors.right: dockWindow.edge === "right" ? parent.right : undefined
                anchors.horizontalCenter: dockWindow.vertical ? undefined : parent.horizontalCenter
                anchors.verticalCenter: dockWindow.vertical ? parent.verticalCenter : undefined
                anchors.bottomMargin: dockWindow.edge === "bottom" ? dockWindow.margin : 0
                anchors.topMargin: dockWindow.edge === "top" ? dockWindow.margin : 0
                anchors.leftMargin: dockWindow.edge === "left" ? dockWindow.margin : 0
                anchors.rightMargin: dockWindow.edge === "right" ? dockWindow.margin : 0
                readonly property real contentW: dockWindow.vertical ? dockWindow.thickness : Math.min(dockBox.width, parent.width - 16)
                readonly property real contentH: dockWindow.vertical ? Math.min(dockBox.height, parent.height - 16) : dockWindow.thickness
                // Auto-hide collapses the input area to a 3px edge strip so
                // the invisible dock never eats clicks meant for windows.
                width: (dockWindow.autoHide && !dockWindow.revealed) ? 3 : contentW
                height: (dockWindow.autoHide && !dockWindow.revealed) ? 3 : contentH
                visible: dockWindow.visible && !dockWindow.hiddenForFullscreen

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: dockWindow.hovered = containsMouse
                }

                Rectangle {
                    id: dockBox
                    anchors.centerIn: parent
                    width: dockWindow.vertical ? dockWindow.thickness : dockRow.implicitWidth + dockWindow.pad * 2
                    height: dockWindow.vertical ? dockCol.implicitHeight + dockWindow.pad * 2 : dockWindow.thickness
                    radius: Math.min(Theme.cornerRadius, 24)
                    color: Theme.withAlpha(Theme.bg, Math.max(0.35, Theme.dockOpacity))
                    border.color: Theme.panelBorderColor
                    border.width: Theme.dockBorderEnabled ? 2 : 0
                    antialiasing: Theme.shapesAa
                    opacity: dockWindow.revealed ? 1 : (dockWindow.autoHide ? 0 : 1)
                    visible: opacity > 0.01
                    Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }

                    Row {
                        id: dockRow
                        visible: !dockWindow.vertical
                        anchors.centerIn: parent
                        spacing: dockWindow.gap
                        // Launcher button (DMS dockLauncher widget).
                        Item {
                            visible: Theme.dockLauncherEnabled
                            width: dockWindow.iconSize + 8
                            height: dockWindow.iconSize + dockWindow.lane
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -3
                                text: "󰍉"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Math.round(dockWindow.iconSize * 0.62)
                                color: launchMouse.containsMouse ? Theme.accent : Theme.textPrimary
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            MouseArea {
                                id: launchMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dockScope.requestLauncher()
                            }
                        }
                        Repeater {
                            model: dockWindow.dockItems
                            delegate: DockButton { isVertical: false }
                        }
                    }
                    Column {
                        id: dockCol
                        visible: dockWindow.vertical
                        anchors.centerIn: parent
                        spacing: dockWindow.gap
                        Item {
                            visible: Theme.dockLauncherEnabled
                            width: dockWindow.iconSize + dockWindow.lane
                            height: dockWindow.iconSize + 8
                            Text {
                                anchors.centerIn: parent
                                text: "󰍉"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Math.round(dockWindow.iconSize * 0.62)
                                color: launchMouseV.containsMouse ? Theme.accent : Theme.textPrimary
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            MouseArea {
                                id: launchMouseV
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dockScope.requestLauncher()
                            }
                        }
                        Repeater {
                            model: dockWindow.dockItems
                            delegate: DockButton { isVertical: true }
                        }
                    }

                    // Inline context menu (custom rect; Popup would need an
                    // owning window per delegate and fights the layer mask).
                    Rectangle {
                        id: ctxMenu
                        visible: dockWindow.menuOpen
                        width: 200
                        height: ctxCol.implicitHeight + 16
                        radius: 12
                        color: Theme.panelCardHighest
                        border.color: Theme.divider
                        border.width: 1
                        antialiasing: Theme.shapesAa
                        x: dockWindow.vertical ? (dockWindow.edge === "left" ? parent.width + 8 : -width - 8) : Math.max(8, Math.min(parent.width - width - 8, dockBox.width / 2 - width / 2))
                        y: dockWindow.vertical ? Math.max(8, Math.min(parent.height - height - 8, parent.height / 2 - height / 2)) : (dockWindow.edge === "bottom" ? -height - 8 : parent.height + 8)
                        Column {
                            id: ctxCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            Text {
                                width: parent.width
                                text: dockWindow.menuAppId
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            Repeater {
                                model: ctxActions
                                delegate: Rectangle {
                                    required property var modelData
                                    width: ctxCol.width
                                    height: 32
                                    radius: 8
                                    color: ctxMouse.containsMouse ? Theme.panelCardHigh : "transparent"
                                    antialiasing: Theme.shapesAa
                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(13)
                                        color: Theme.textPrimary
                                        antialiasing: Theme.textAa
                                        renderType: Theme.textRenderType
                                    }
                                    MouseArea {
                                        id: ctxMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            modelData.run()
                                            dockWindow.closeMenu()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    readonly property var ctxActions: {
                        const id = dockWindow.menuAppId
                        if (!id) return []
                        const pinned = Theme.isDockPinned(id)
                        const item = dockWindow.dockItems.find(e => e && e.appId === id)
                        const wins = item ? (item.wins || []) : []
                        const out = []
                        if (wins.length > 0) out.push({ label: wins.length > 1 ? "Focus next window" : "Focus window", run: () => dockWindow.activateItem(item) })
                        else out.push({ label: "Launch", run: () => dockWindow.launchApp(id) })
                        out.push({ label: pinned ? "Unpin from dock" : "Pin to dock", run: () => Theme.toggleDockPinned(id) })
                        if (wins.length > 0) out.push({ label: wins.length > 1 ? "Close all windows" : "Close window", run: () => { for (let i = 0; i < wins.length; i++) dockWindow.closeWindow(wins[i]) } })
                        out.push({ label: "Dismiss", run: () => {} })
                        return out
                    }
                }
            }

            component DockButton: Item {
                id: btn
                required property var modelData
                property bool isVertical: false
                readonly property string appId: (modelData && modelData.appId) ? ("" + modelData.appId) : ""
                readonly property bool running: modelData ? !!modelData.running : false
                readonly property bool active: modelData ? !!modelData.active : false
                readonly property int winCount: modelData && modelData.wins ? modelData.wins.length : 0
                width: isVertical ? dockWindow.iconSize + dockWindow.lane : dockWindow.iconSize + 8
                height: isVertical ? dockWindow.iconSize + 8 : dockWindow.iconSize + dockWindow.lane
                scale: hoverMouse.containsMouse && Theme.dockMagnify ? 1.18 : 1
                Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }

                // Resolved imperatively: Theme.appIconFor() memoises into
                // Theme's cache, so calling it from a binding writes a
                // property the binding reads (binding loop). Same pattern
                // as the workspace window icons.
                property string iconSource: ""
                function resolveIcon(): void {
                    let s = ""
                    try { s = Theme.appIconFor(btn.appId) } catch (e) {}
                    if (iconSource !== s) iconSource = s
                }
                Component.onCompleted: resolveIcon()
                onAppIdChanged: resolveIcon()
                Connections {
                    target: Theme
                    function onAppsRevChanged() { btn.resolveIcon() }
                }
                IconImage {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: btn.isVertical ? 0 : -3
                    anchors.horizontalCenterOffset: btn.isVertical ? (dockWindow.edge === "left" ? -3 : 3) : 0
                    implicitSize: dockWindow.iconSize
                    source: btn.iconSource
                    asynchronous: true
                }
                // Running indicator (DMS indicatorStyle circle/line).
                Rectangle {
                    visible: Theme.dockShowIndicators && btn.running
                    color: btn.active ? Theme.accent : Theme.textSecondary
                    antialiasing: Theme.shapesAa
                    width: Theme.dockIndicatorStyle === "circle" ? 5 : (btn.isVertical ? 3 : Math.min(20, dockWindow.iconSize * 0.45))
                    height: Theme.dockIndicatorStyle === "circle" ? 5 : (btn.isVertical ? Math.min(20, dockWindow.iconSize * 0.45) : 3)
                    radius: width / 2
                    x: {
                        if (btn.isVertical) return dockWindow.edge === "left" ? parent.width - width - 1 : 1
                        return (parent.width - width) / 2
                    }
                    y: {
                        if (btn.isVertical) return (parent.height - height) / 2
                        return dockWindow.edge === "top" ? 1 : parent.height - height - 1
                    }
                }
                // Multi-window count badge.
                Rectangle {
                    visible: btn.winCount > 1
                    width: 16; height: 16; radius: 8
                    color: Theme.accent
                    antialiasing: Theme.shapesAa
                    anchors.right: parent.right
                    anchors.top: parent.top
                    Text {
                        anchors.centerIn: parent
                        text: btn.winCount > 9 ? "9+" : "" + btn.winCount
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Theme.onAccent
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                MouseArea {
                    id: hoverMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (dockWindow.menuOpen && dockWindow.menuAppId === btn.appId) dockWindow.closeMenu()
                            else dockWindow.openMenu(btn.appId)
                            return
                        }
                        if (mouse.button === Qt.MiddleButton) {
                            const wins = (btn.modelData && btn.modelData.wins) || []
                            if (wins.length > 0) dockWindow.closeWindow(wins[0])
                            else dockWindow.launchApp(btn.appId)
                            return
                        }
                        dockWindow.closeMenu()
                        dockWindow.activateItem(btn.modelData)
                    }
                }
            }
        }
    }
}
