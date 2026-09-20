pragma ComponentBehavior: Bound
import QtQuick
import "../../themes"
import "../../ui"

// BarSlot — one bar module slot: anchor publishing, hover forwarding and
// click/wheel routing. Placement and visibility are managed from
// Settings → Panels (or the `bar` IPC); the bar itself is not draggable.
Item {
    id: root
    required property string moduleId
    property bool vertical: false
    property var monitor: null
    property bool active: false
    property string barPos: "top"
    property var barWindow: null
    property bool anchorActive: true
    // Merge support (Settings -> Panels -> Taskbar > Merge background): a
    // shared revision object (one per bar) bumped whenever any slot's
    // visibility flips, so the sibling scans below re-run even though
    // Item.children is not a notifiable property.
    property var mergeState: null

    signal requestCalendar()
    signal requestSystemTray()
    signal requestControlCenter()
    signal requestLauncher()
    signal hideRequest()

    QtObject {
        id: internal
        property bool dirty: false
    }

    function requestPublishAnchor(): void {
        if (!internal.dirty) {
            internal.dirty = true
            Qt.callLater(publishBarAnchor)
        }
    }

    function publishBarAnchor(): void {
        internal.dirty = false
        if (!anchorActive) return
        // Bar anchors are published from the primary screen only (DP-1 when
        // present, else the Theme fallback screen).
        try { if (monitor && monitor.name && !Theme.isPrimaryScreen(monitor)) return } catch (e) { }
        if (!visible || width <= 0 || height <= 0) return
        try {
            let p = mapToItem(null, 0, 0)
            let sx = p.x, sy = p.y
            let win = barWindow
            if (win) {
                let sw = 0, sh = 0
                try { if (win.screen) { sw = win.screen.width; sh = win.screen.height } } catch (e1) { }
                if (!sw || !sh) { try { sw = Screen.width; sh = Screen.height } catch (e2) { } }
                let mL = 0, mT = 0, mR = 0, mB = 0
                try { let m = win.margins; if (m) { mL = m.left || 0; mT = m.top || 0; mR = m.right || 0; mB = m.bottom || 0 } } catch (e3) { }
                if (barPos === "bottom" && sh > 0) { sx += mL; sy += Math.max(0, sh - win.height - mB) }
                else if (barPos === "right" && sw > 0) { sx += Math.max(0, sw - win.width - mR); sy += mT }
                else { sx += mL; sy += mT }
            }
            Theme.setBarAnchor(moduleId, sx, sy, width, height)
        } catch (e) { }
    }

    onXChanged: requestPublishAnchor()
    onYChanged: requestPublishAnchor()
    onWidthChanged: requestPublishAnchor()
    onHeightChanged: requestPublishAnchor()
    onVisibleChanged: {
        requestPublishAnchor()
        if (root.mergeState) root.mergeState.revision++
    }
    onBarPosChanged: requestPublishAnchor()
    onBarWindowChanged: requestPublishAnchor()
    onAnchorActiveChanged: requestPublishAnchor()
    Component.onCompleted: {
        requestPublishAnchor()
        Qt.callLater(requestPublishAnchor)
        if (root.mergeState) root.mergeState.revision++
    }
    Connections {
        target: Theme
        function onAnchorRefreshTriggerChanged() { requestPublishAnchor() }
        function onBarEdgeDistanceChanged() { requestPublishAnchor() }
        function onBarTopDistanceChanged() { requestPublishAnchor() }
    }

    implicitWidth: moduleLoader.implicitWidth
    implicitHeight: moduleLoader.implicitHeight
    visible: moduleLoader.activeVisible

    // Optional per-module card (Settings -> Panels -> Taskbar ->
    // <component> > Background). Workspaces owns its own pill (see
    // Workspaces.qml) and is excluded here so it never paints twice.
    //
    // Merge mode (Settings -> Panels -> Taskbar > Merge background): a carded
    // slot drops the corner(s) facing a carded neighbour and grows into the
    // inter-module gap by ~1px, so a run reads as one seamless card. Sibling
    // slots are the live visible slots of the same layout zone (a collapsed
    // tray disappears and its neighbours then merge across the gap). In merge
    // mode workspaces' own pill is suppressed and painted here instead, so
    // every module follows the same corner logic.
    readonly property bool mergeOn: Theme.barBackgroundMerge
    readonly property bool carded: Theme.barBackgroundEnabled(root.moduleId)
    // Visible sibling slots of this slot's zone, in module order.
    readonly property var mergeSiblings: {
        if (root.mergeState) root.mergeState.revision
        let out = []
        let zone = root.parent
        if (zone && zone.children) {
            for (let i = 0; i < zone.children.length; i++) {
                let ch = zone.children[i]
                if (ch && ch.moduleId !== undefined && ch.visible) out.push(ch)
            }
        }
        return out
    }
    readonly property int mergeIndex: root.mergeSiblings.indexOf(root)
    readonly property bool mergeBefore: {
        if (!root.mergeOn || !root.carded || root.mergeIndex <= 0) return false
        let prev = root.mergeSiblings[root.mergeIndex - 1]
        return !!prev && Theme.barBackgroundEnabled(prev.moduleId)
    }
    readonly property bool mergeAfter: {
        if (!root.mergeOn || !root.carded || root.mergeIndex < 0) return false
        let next = root.mergeSiblings[root.mergeIndex + 1]
        return !!next && Theme.barBackgroundEnabled(next.moduleId)
    }
    // Bleed into the inter-module gap so two flat edges overlap (covers
    // positive spacing; negative spacing already overlaps by definition).
    readonly property real mergeGrow: Math.max(1, Math.ceil(Theme.barModuleSpacing / 2) + 1)
    // Workspaces used to paint its own content-sized pill; it now goes
    // through the same card as every other module so all backgrounds share
    // one cross-axis extent (Theme.barCardExtent).
    readonly property bool paintsCard: root.carded

    Rectangle {
        id: slotBackground
        visible: root.paintsCard
        color: Theme.surface_container
        antialiasing: Theme.shapesAa
        z: -1
        // Uniform card size: the cross axis always spans the bar card extent
        // (not the module content), centered on the module, so every card is
        // exactly the same height regardless of the widget's own metrics.
        readonly property real cardExtent: Math.max(12, Theme.barCardExtent)
        readonly property real alongStart: root.vertical ? moduleLoader.y : moduleLoader.x
        readonly property real alongSize: root.vertical ? moduleLoader.height : moduleLoader.width
        readonly property real alongBleed: (root.mergeBefore ? root.mergeGrow : 0) + (root.mergeAfter ? root.mergeGrow : 0)
        readonly property real pillR: Math.round(cardExtent / 2)
        x: root.vertical ? (root.width - cardExtent) / 2 : alongStart - (root.mergeBefore ? root.mergeGrow : 0)
        y: root.vertical ? alongStart - (root.mergeBefore ? root.mergeGrow : 0) : (root.height - cardExtent) / 2
        width: root.vertical ? cardExtent : alongSize + alongBleed
        height: root.vertical ? alongSize + alongBleed : cardExtent
        topLeftRadius: root.mergeBefore ? 0 : pillR
        bottomLeftRadius: (root.vertical ? root.mergeAfter : root.mergeBefore) ? 0 : pillR
        topRightRadius: (root.vertical ? root.mergeBefore : root.mergeAfter) ? 0 : pillR
        bottomRightRadius: root.mergeAfter ? 0 : pillR
    }

    BarModule {
        id: moduleLoader
        anchors.centerIn: parent
        moduleId: root.moduleId
        vertical: root.vertical
        monitor: root.monitor
        slotHovered: slotPointer.containsMouse
        onRequestCalendar: root.requestCalendar()
        onRequestSystemTray: root.requestSystemTray()
        onRequestControlCenter: root.requestControlCenter()
        onRequestLauncher: root.requestLauncher()
    }

    // Ripple: painted above the module content but driven manually from
    // slotPointer, so the click logic and the widget MouseAreas stay
    // untouched (disabled StateLayer never takes input itself).
    StateLayer {
        id: slotRipple
        disabled: true
        showHoverBackground: false
        radius: Math.round(Math.min(width, height) / 2)
        color: Theme.textPrimary
    }

    MouseArea {
        id: slotPointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        enabled: root.visible && root.width > 0 && root.height > 0
        propagateComposedEvents: true
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property real _lastHoverX: -1000
        property real _lastHoverY: -1000

        onPressed: mouse => slotRipple.press(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (mouse.buttons & Qt.LeftButton) return
            // PERF: hover scan does mapFromItem + child loop per pixel.
            // Skip sub-3px jitter moves (same delegate still hovered).
            let dx = mouse.x - slotPointer._lastHoverX
            let dy = mouse.y - slotPointer._lastHoverY
            if (dx * dx + dy * dy < 9) return
            slotPointer._lastHoverX = mouse.x
            slotPointer._lastHoverY = mouse.y
            let bp = moduleLoader.mapFromItem(slotPointer, mouse.x, mouse.y)
            moduleLoader.hoverAt(bp.x, bp.y)
        }
        onContainsMouseChanged: {
            if (!slotPointer.containsMouse) moduleLoader.hoverLeft()
        }
        onClicked: mouse => {
            if (root.active && mouse.button === Qt.LeftButton) {
                root.hideRequest()
                mouse.accepted = true
                return
            }
            let bp = moduleLoader.mapFromItem(slotPointer, mouse.x, mouse.y)
            moduleLoader.click(mouse.button, bp.x, bp.y)
            mouse.accepted = true
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (moduleLoader.wheel(event.angleDelta.y)) event.accepted = true
        }
    }
}
