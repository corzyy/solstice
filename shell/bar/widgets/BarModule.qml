import QtQuick
import Quickshell.Services.SystemTray as TrayService
import "../../../style/themes"
import "../../../backend/services"

Item {
    id: root
    signal requestCalendar()
    signal requestSystemTray()
    signal requestControlCenter()
    signal requestLauncher()
    required property string moduleId
    property bool vertical: false
    // Kept for interface compat (BarSlot assigns monitor:). Unused
    // internally — no widget reads it — but removing it would break the
    // assignment in BarSlot.qml:116.
    property var monitor: null
    property bool slotHovered: false
    // Workspace-Backend (siehe Workspaces.qml).
    readonly property var wsBackend: UmbrielService

    readonly property bool activeVisible: moduleId !== "systemtray" || trayCount > 0
    // PERF: only the systemtray instance scans tray items. Old code ran the
    // same O(n) scan in every BarSlot (~10x) on every tray change.
    readonly property int trayCount: {
        if (moduleId !== "systemtray") return 1
        let n = 0
        try {
            let vals = TrayService.SystemTray.items.values
            for (let i = 0; i < vals.length; i++) {
                let it = vals[i]
                if (it && it.status !== TrayService.Status.Passive) n++
            }
        } catch (e) { }
        return n
    }

    function hoverAt(mx: real, my: real): void {
        if (moduleId !== "workspaces") return
        try {
            let w = widgetLoader.item
            if (!w) return
            let inner = w.wsInnerItem ?? w
            let p = inner.mapFromItem(root, mx, my)
            if (w.setHoverAt) w.setHoverAt(p.x, p.y)
            else if (inner.setHoverAt) inner.setHoverAt(p.x, p.y)
        } catch (e) { }
    }
    function hoverLeft(): void {
        if (moduleId !== "workspaces") return
        try { widgetLoader.item?.clearHover?.() } catch (e) { }
    }

    function toggleModuleLabel(): bool {
        // Future-proof: any bar widget exposing toggleLabel() gets right-click
        // label toggling with zero per-module wiring. New modules just add:
        //   function toggleLabel(): void { ... }
        // Wrapper comps (e.g. clockComp Item->Clock) are covered by checking
        // direct children too, so forwarding boilerplate is optional.
        try {
            let w = widgetLoader.item
            if (!w) return false
            if (typeof w.toggleLabel === "function") { w.toggleLabel(); return true }
            try {
                if (w.wsInnerItem && typeof w.wsInnerItem.toggleLabel === "function") { w.wsInnerItem.toggleLabel(); return true }
            } catch (e1) {}
            try {
                let ch = w.children
                if (ch) {
                    for (let i = 0; i < ch.length; i++) {
                        let c = ch[i]
                        if (c && typeof c.toggleLabel === "function") { c.toggleLabel(); return true }
                    }
                }
            } catch (e2) {}
        } catch (e) {}
        return false
    }

    // Klick-Tabelle: (Modul, Taste) -> Aktion. Neue Module nur hier
    // eintragen statt die if/else-Kette zu verlängern. workspaces braucht
    // Koordinaten und bleibt eine eigene Funktion.
    function click(button: int, x: real, y: real): void {
        // Right-click toggles the module label when the widget supports it.
        // Icon-only modules (no toggleLabel) fall through to legacy actions.
        if (button === Qt.RightButton) {
            if (toggleModuleLabel()) return
        }
        const left = button === Qt.LeftButton
        const middle = button === Qt.MiddleButton
        const right = button === Qt.RightButton
        switch (moduleId) {
        case "clock":
            if (right) Theme.toggleClockFormat()
            else if (left) requestCalendar()
            break
        case "systemtray":
            // Pinned icons handle their own clicks; the grid button
            // (anything past them) opens the panel.
            if (clickSystemTray(button, x, y)) break
            if (left || right) requestSystemTray()
            break
        case "controlcenter":
            if (left) requestControlCenter()
            break
        case "launcher":
            if (left) requestLauncher()
            break
        case "workspaces":            if (left) clickWorkspaces(x, y)
            break
        }
    }

    function clickSystemTray(button: int, x: real, y: real): bool {
        try {
            let t = widgetLoader.item
            if (!t || !t.click) return false
            let p = t.mapFromItem(root, x, y)
            return t.click(button, p.x, p.y) === true
        } catch (e) { }
        return false
    }

    function clickWorkspaces(x: real, y: real): void {
        try {
            let w = widgetLoader.item
            if (!w) return
            let inner = w.wsInnerItem ?? w
            let p = inner.mapFromItem(root, x, y)
            if (w.activateAt) w.activateAt(p.x, p.y)
            else if (inner.activateAt) inner.activateAt(p.x, p.y)
        } catch (e) { }
    }

    function screenNameForWheel(): string {
        // Follow the focused monitor (matches Workspaces display).
        try {
            let f = wsBackend.focusedMonitor
            if (f && ("" + f).length > 0) return "" + f
        } catch (e) {}
        try {
            if (monitor && monitor.name) return "" + monitor.name
            if (typeof monitor === "string" && ("" + monitor).length > 0) return "" + monitor
        } catch (e2) {}
        return ""
    }
    function wheel(dy: real): bool {
        if (moduleId === "workspaces") {
            if (!Theme.barScrollWorkspaces) return false
            let sn = screenNameForWheel()
            if (dy > 0) wsBackend.prevTag(sn)
            else wsBackend.nextTag(sn)
            return true
        }
        if (moduleId === "systemtray") {
            try { return widgetLoader.item?.wheel?.(dy) ?? false } catch (e) { return false }
        }
        return false
    }

    implicitWidth: activeVisible ? widgetLoader.implicitWidth : 0
    implicitHeight: activeVisible ? widgetLoader.implicitHeight : 0

    Loader {
        id: widgetLoader
        anchors.centerIn: parent
        // PERF: async so one slow widget (tray icon fetch) can't stall bar layout.
        asynchronous: true
        // RAM: unload collapsed widgets instead of keeping them alive at
        // width 0 (empty tray). Destroying the item frees its bindings,
        // timers and images; it reloads on next show.
        active: root.activeVisible
        sourceComponent: {
            switch (root.moduleId) {
            case "workspaces": return wsComp
            case "clock": return clockComp
            case "systemtray": return trayComp
            case "activewindow": return activeComp
            case "controlcenter": return controlCenterComp
            case "launcher": return launcherComp
            }
            return null
        }
    }

    Component {
        id: wsComp
        Item {
            property alias wsInnerItem: wsInner
            // The ported widget draws its own rounded container/padding.
            implicitWidth: wsInner.implicitWidth
            implicitHeight: wsInner.implicitHeight
            Workspaces { id: wsInner; anchors.centerIn: parent; vertical: root.vertical; monitor: root.monitor }
            function setHoverAt(px: real, py: real): void { wsInner.setHoverAt(px, py) }
            function clearHover(): void { wsInner.clearHover() }
            function activateAt(px: real, py: real): bool { return wsInner.activateAt(px, py) }
        }
    }
    Component {
        id: clockComp
        Item {
            implicitWidth: clockInner.implicitWidth + 12
            implicitHeight: clockInner.implicitHeight + 8
            function toggleLabel(): void { clockInner.toggleLabel() }
            Clock { id: clockInner; anchors.centerIn: parent; vertical: root.vertical; onClicked: root.requestCalendar() }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
    Component {
        id: trayComp
        SystemTray { vertical: root.vertical; onClicked: root.requestSystemTray() }
    }
    Component { id: activeComp; ActiveWindow { vertical: root.vertical } }
    Component { id: controlCenterComp; ControlCenterWidget { vertical: root.vertical; slotHovered: root.slotHovered; onClicked: root.requestControlCenter() } }
    Component { id: launcherComp; LauncherIcon { vertical: root.vertical; slotHovered: root.slotHovered } }
}
