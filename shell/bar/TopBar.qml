pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./widgets" as Bar

import "../../backend/services"
import "../../style/themes"

Scope {
    id: topBarScope
    signal toggleCalendar()
    signal toggleSystemTray()
    signal toggleControlCenter()
    signal toggleLauncher()
    signal closePanel(string moduleId)

    property bool calendarOpen: false
    property bool trayOpen: false
    property bool controlCenterOpen: false
    property bool launcherOpen: false
    // Set by the shell: any popout open keeps an auto-hidden bar revealed.
    property bool anyPanelOpen: false
    // Merge-background sibling scans depend on Item.children, which is not a
    // notifiable property; every BarSlot bumps `revision` when it appears or
    // disappears so the other slots re-evaluate their neighbours.
    property QtObject mergeState: QtObject {
        property int revision: 0
    }
    // Modul -> Sichtbarkeitsflag (Tabelle statt if-Kette; neue Panels nur hier).
    function moduleActive(id: string): bool {
        const flag = {
            clock: "calendarOpen",
            systemtray: "trayOpen",
            controlcenter: "controlCenterOpen",
            launcher: "launcherOpen"
        }[id]
        return flag !== undefined ? !!topBarScope[flag] : false
    }

    IpcHandler {
        target: "vitals"
        function status(): string { return VitalsService.status() }
        function refresh(): string { VitalsService.refresh(); return "refreshing " + VitalsService.status() }
    }
    IpcHandler {
        target: "updates"
        function check(): string { UpdateService.checkNow(); return "checking system+flatpak..." }
        function status(): string { return UpdateService.status() }
        function debug(arg: string): string { return UpdateService.setDebug(arg) }
        function debugCount(n: int): string { UpdateService.debugCount = n; UpdateService.debugForce = true; return "debugCount=" + n }
    }

    // The bar always reserves its strip: Umbriel does not expose per-output
    // fullscreen state through its CLI, and fullscreen windows cover the
    // Top-layer bar anyway.

    IpcHandler {
        target: "bar"
        function layout(): string { return Theme.barLayoutString() }
        function move(id: string, section: string, index: int): string { return Theme.moveBarWidget(id, section, index) }
        function reset(): string { Theme.resetBarLayout(); return "reset: " + Theme.barLayoutString() }
        function hide(id: string): string { return Theme.hideBarModule(id) }
        function show(id: string): string { return Theme.showBarModule(id) }
        function trayAnchor(): string { try { return "systemtray=" + JSON.stringify(Theme.barAnchor("systemtray")) + " bar=" + JSON.stringify(Theme.barWindowRect) } catch (e) { return "err " + e } }
    }

    // Monitor switch (Settings > Panels > Taskbar > Monitors): the new
    // primary bar window republishes its rect (onVisibleChanged below) and
    // every slot re-publishes its anchor for the new screen.
    Connections {
        target: Theme
        function onPrimaryScreenNameChanged() { Theme.refreshBarAnchors() }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: topBarWindow
            required property var modelData
            screen: modelData
            readonly property int cfgThickness: Theme.barThickness
            property int barHeight: Math.max(20, Math.min(64, topBarWindow.cfgThickness))
            property int barWidth: Math.max(20, Math.min(64, topBarWindow.cfgThickness))
            onBarWidthChanged: Theme.barEffectiveWidth = barWidth
            onBarHeightChanged: Theme.barEffectiveHeight = barHeight
            // PERF: 7 onChanged handlers called publishWindowRect() synchronously
            // per frame (geometry storm during resize/drag). Coalesce to one
            // deferred publish per event-loop tick.
            property bool _rectDirty: false
            function requestPublishWindowRect(): void {
                if (_rectDirty) return
                _rectDirty = true
                Qt.callLater(() => {
                    _rectDirty = false
                    publishWindowRect()
                })
            }
            onWidthChanged: requestPublishWindowRect()
            onHeightChanged: requestPublishWindowRect()
            onBarPosChanged: requestPublishWindowRect()
            onEdgeDistChanged: requestPublishWindowRect()
            onTopDistChanged: requestPublishWindowRect()
            // Monitor switch: the newly primary bar publishes its geometry so
            // popouts settle against the right screen immediately.
            onVisibleChanged: if (visible) requestPublishWindowRect()
            property string barPos: Theme.barPosition
            property real barOpacity: Theme.barOpacity
            property bool isVertical: barPos === "left" || barPos === "right"
            property bool isHorizontal: !isVertical
            property int edgeDist: Theme.barEdgeDistance
            property int topDist: Theme.barTopDistance
            // Auto-hide (Caelestia bar.persistent/showOnHover/dragThreshold):
            // non-persistent bars collapse to a 2px input strip that paints
            // nothing (revealProgress 0) and reveal on hover (when enabled)
            // or on an edge drag past the threshold.
            readonly property bool autoHide: !Theme.barPersistent
            property bool barRevealed: false
            readonly property bool revealed: !autoHide || barRevealed || topBarScope.anyPanelOpen
            readonly property int hiddenThickness: 2
            // 1 when fully expanded, 0 when collapsed: drives content opacity
            // so a hidden bar is completely invisible while its surface stays
            // mapped for hover/drag reveal.
            readonly property real revealProgress: {
                const span = Math.max(1, (isVertical ? barWidth : barHeight) - hiddenThickness)
                const extent = isVertical ? topBarWindow.width : topBarWindow.height
                return Math.max(0, Math.min(1, (extent - hiddenThickness) / span))
            }
            visible: Theme.isPrimaryScreen(modelData)
            WlrLayershell.namespace: "bar"
            // Top (not Overlay) so a fullscreen window covers the bar instead
            // of the bar painting over it. The bar stays mapped the whole
            // time, so the compositor uncovers it automatically on exit /
            // workspace switch — no unmap/remap state to get stuck.
            WlrLayershell.layer: WlrLayer.Top
            // Always reserve the strip so tiled windows don't slide under it
            // (auto-hidden bars reserve nothing).
            exclusiveZone: Theme.isPrimaryScreen(modelData) ? (revealed ? (isVertical ? barWidth + topDist : barHeight + topDist) : 0) : 0
            anchors { top: barPos === "top" || isVertical; bottom: barPos === "bottom" || isVertical; left: barPos === "left" || isHorizontal; right: barPos === "right" || isHorizontal }
            margins {
                top: topBarWindow.isVertical ? topBarWindow.edgeDist : (topBarWindow.barPos === "top" ? topBarWindow.topDist : 0)
                bottom: topBarWindow.isVertical ? topBarWindow.edgeDist : (topBarWindow.barPos === "bottom" ? topBarWindow.topDist : 0)
                left: topBarWindow.isVertical ? (topBarWindow.barPos === "left" ? topBarWindow.topDist : 0) : topBarWindow.edgeDist
                right: topBarWindow.isVertical ? (topBarWindow.barPos === "right" ? topBarWindow.topDist : 0) : topBarWindow.edgeDist
            }
            implicitHeight: isVertical ? 0 : (revealed ? barHeight : hiddenThickness)
            implicitWidth: isVertical ? (revealed ? barWidth : hiddenThickness) : 0
            Behavior on implicitHeight { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            Behavior on implicitWidth { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            color: "transparent"

            // Hover reveals (bar.showOnHover) and, once revealed, leaving hides.
            HoverHandler {
                enabled: topBarWindow.autoHide
                onHoveredChanged: {
                    if (hovered) {
                        if (Theme.barShowOnHover) topBarWindow.barRevealed = true
                    } else {
                        topBarWindow.barRevealed = false
                    }
                }
            }
            // Edge drag reveals (bar.dragThreshold pixels toward the screen).
            MouseArea {
                anchors.fill: parent
                enabled: topBarWindow.autoHide && !topBarWindow.revealed
                acceptedButtons: Qt.LeftButton
                property real pressX: 0
                property real pressY: 0
                onPressed: mouse => {
                    pressX = mouse.x
                    pressY = mouse.y
                }
                onPositionChanged: mouse => {
                    let d = 0
                    if (topBarWindow.barPos === "top") d = mouse.y - pressY
                    else if (topBarWindow.barPos === "bottom") d = pressY - mouse.y
                    else if (topBarWindow.barPos === "left") d = mouse.x - pressX
                    else d = pressX - mouse.x
                    if (d >= Math.max(1, Theme.barDragThreshold)) topBarWindow.barRevealed = true
                }
            }
            // Scroll actions: top half volume, bottom half brightness.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                enabled: topBarWindow.revealed
                onWheel: event => {
                    let py = topBarWindow.height / 2 - 1
                    try { py = event.point.position.y } catch (e) { }
                    const up = event.angleDelta.y > 0
                    if (py < topBarWindow.height / 2) {
                        if (!Theme.barScrollVolume) return
                        if (up) VolumeService.stepUp()
                        else VolumeService.stepDown()
                        event.accepted = true
                    } else {
                        if (!Theme.barScrollBrightness) return
                        SettingsService.applyBrightness(SettingsService.brightness + (up ? 5 : -5))
                        event.accepted = true
                    }
                }
            }

            Rectangle {
                antialiasing: Theme.shapesAa
                anchors.fill: parent
                opacity: topBarWindow.revealProgress
                radius: (topBarWindow.edgeDist > 0 || topBarWindow.topDist > 0) ? Theme.cornerRadius : 0
                color: topBarWindow.barOpacity >= 0.999 ? Theme.panelBg : Theme.withAlpha(Theme.bg, Math.max(0, Math.min(1, topBarWindow.barOpacity * Theme.panelBgAlpha)))
            }

            Component.onCompleted: { Theme.barEffectiveWidth = barWidth; Theme.barEffectiveHeight = barHeight; publishWindowRect(); Qt.callLater(publishWindowRect) }

            function publishWindowRect(): void {
                if (!Theme.isPrimaryScreen(modelData)) return
                try {
                    let sw = 0, sh = 0
                    try { if (screen) { sw = screen.width; sh = screen.height } } catch (e1) { }
                    if (!sw || !sh) { try { sw = Screen.width; sh = Screen.height } catch (e2) { } }
                    let mL = 0, mT = 0, mR = 0, mB = 0
                    try { let m = margins; if (m) { mL = m.left || 0; mT = m.top || 0; mR = m.right || 0; mB = m.bottom || 0 } } catch (e3) { }
                    let rx = mL, ry = mT
                    if (barPos === "bottom" && sh > 0) { rx = mL; ry = Math.max(0, sh - height - mB) }
                    else if (barPos === "right" && sw > 0) { rx = Math.max(0, sw - width - mR); ry = mT }
                    else if (barPos === "left") { rx = mL; ry = mT }
                    Theme.setBarWindowRect(rx, ry, width, height)
                } catch (e) { }
            }
            Item {
                visible: topBarWindow.isHorizontal
                anchors.fill: parent; anchors.leftMargin: Theme.barContentPadding; anchors.rightMargin: Theme.barContentPadding
                opacity: topBarWindow.revealProgress

                Item {
                    id: leftZoneWrap
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: leftZoneRow.implicitWidth + (Theme.barContentPadding > 0 ? 14 : 0)
                    height: Math.max(0, Math.min(leftZoneRow.implicitHeight + 8, parent.height - 4))
                    RowLayout {
                        id: leftZoneRow
                        anchors.centerIn: parent
                        spacing: Theme.barModuleSpacing
                        Repeater {
                            // PERF: hidden orientation keeps zero delegates
                            // (was 2x full bar trees alive, ~20 BarSlots).
                            model: topBarWindow.isHorizontal ? Theme.barLayoutLeft : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    vertical: false
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isHorizontal

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                        }

                    }
                }

                Item {
                    id: twoFifthsZoneWrap
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: parent.width * -0.25
                    anchors.verticalCenter: parent.verticalCenter
                    width: twoFifthsZoneRow.implicitWidth + (Theme.barContentPadding > 0 ? 14 : 0)
                    height: Math.max(0, Math.min(twoFifthsZoneRow.implicitHeight + 8, parent.height - 4))
                    RowLayout {
                        id: twoFifthsZoneRow
                        anchors.centerIn: parent
                        spacing: Theme.barModuleSpacing
                        Repeater {
                            model: topBarWindow.isHorizontal ? Theme.barLayoutTwoFifths : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    vertical: false
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isHorizontal

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                        }

                    }
                }

                Item {
                    id: centerZoneWrap
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
                    width: centerZoneRow.implicitWidth + (Theme.barContentPadding > 0 ? 14 : 0)
                    height: Math.max(0, Math.min(centerZoneRow.implicitHeight + 8, parent.height - 4))
                    RowLayout {
                        id: centerZoneRow
                        anchors.centerIn: parent
                        spacing: Theme.barModuleSpacing
                        Repeater {
                            model: topBarWindow.isHorizontal ? Theme.barLayoutCenter : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    vertical: false
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isHorizontal

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                        }

                    }
                }

                Item {
                    id: fourFifthsZoneWrap
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: parent.width * 0.25
                    anchors.verticalCenter: parent.verticalCenter
                    width: fourFifthsZoneRow.implicitWidth + (Theme.barContentPadding > 0 ? 14 : 0)
                    height: Math.max(0, Math.min(fourFifthsZoneRow.implicitHeight + 8, parent.height - 4))
                    RowLayout {
                        id: fourFifthsZoneRow
                        anchors.centerIn: parent
                        spacing: Theme.barModuleSpacing
                        Repeater {
                            model: topBarWindow.isHorizontal ? Theme.barLayoutFourFifths : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    vertical: false
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isHorizontal

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                        }

                    }
                }

                Item {
                    id: rightZoneWrap
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: rightZoneRow.implicitWidth + (Theme.barContentPadding > 0 ? 14 : 0)
                    height: Math.max(0, Math.min(rightZoneRow.implicitHeight + 8, parent.height - 4))
                    RowLayout {
                        id: rightZoneRow
                        anchors.centerIn: parent
                        spacing: Theme.barModuleSpacing
                        Repeater {
                            model: topBarWindow.isHorizontal ? Theme.barLayoutRight : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    vertical: false
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isHorizontal

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                        }

                    }
                }
            }

            Item {
                visible: topBarWindow.isVertical
                anchors.fill: parent; anchors.topMargin: Theme.barContentPadding; anchors.bottomMargin: Theme.barContentPadding; anchors.leftMargin: 4; anchors.rightMargin: 4
                clip: true
                opacity: topBarWindow.revealProgress

                ColumnLayout {
                    id: vCol; anchors.fill: parent; spacing: 10
                    Item {
                        id: vTopWrap
                        Layout.fillWidth: true
                        implicitHeight: vTopCol.implicitHeight + (Theme.barContentPadding > 0 ? 14 : 0)
                        ColumnLayout {
                            id: vTopCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.barModuleSpacing
                            Repeater {
                                model: topBarWindow.isVertical ? Theme.barLayoutLeft : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    Layout.fillWidth: true
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    vertical: true
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isVertical

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                            }

                        }
                    }
                    Item { Layout.fillHeight: true }
                    Item {
                        id: vTwoFifthsWrap
                        Layout.fillWidth: true
                        implicitHeight: vTwoFifthsCol.implicitHeight + (Theme.barContentPadding > 0 ? 14 : 0)
                        ColumnLayout {
                            id: vTwoFifthsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.barModuleSpacing
                            Repeater {
                                model: topBarWindow.isVertical ? Theme.barLayoutTwoFifths : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    Layout.fillWidth: true
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    vertical: true
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isVertical

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                            }

                        }
                    }
                    Item { Layout.fillHeight: true }
                    Item {
                        id: vMidWrap
                        Layout.fillWidth: true
                        implicitHeight: vMidCol.implicitHeight + (Theme.barContentPadding > 0 ? 14 : 0)
                        ColumnLayout {
                            id: vMidCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.barModuleSpacing
                            Repeater {
                                model: topBarWindow.isVertical ? Theme.barLayoutCenter : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    Layout.fillWidth: true
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    vertical: true
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isVertical

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                            }

                        }
                    }
                    Item { Layout.fillHeight: true }
                    Item {
                        id: vFourFifthsWrap
                        Layout.fillWidth: true
                        implicitHeight: vFourFifthsCol.implicitHeight + (Theme.barContentPadding > 0 ? 14 : 0)
                        ColumnLayout {
                            id: vFourFifthsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.barModuleSpacing
                            Repeater {
                                model: topBarWindow.isVertical ? Theme.barLayoutFourFifths : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    Layout.fillWidth: true
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    vertical: true
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isVertical

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                            }

                        }
                    }
                    Item { Layout.fillHeight: true }
                    Item {
                        id: vBottomWrap
                        Layout.fillWidth: true
                        implicitHeight: vBottomCol.implicitHeight + (Theme.barContentPadding > 0 ? 14 : 0)
                        ColumnLayout {
                            id: vBottomCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.barModuleSpacing
                            Repeater {
                                model: topBarWindow.isVertical ? Theme.barLayoutRight : []
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    Layout.fillWidth: true
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    vertical: true
                                    monitor: topBarWindow.modelData
                                    barPos: topBarWindow.barPos
                                    barWindow: topBarWindow
                                    anchorActive: topBarWindow.isVertical

                                    onRequestCalendar: topBarScope.toggleCalendar()
                                    onRequestSystemTray: topBarScope.toggleSystemTray()
                                    onRequestControlCenter: topBarScope.toggleControlCenter()
                                    onRequestLauncher: topBarScope.toggleLauncher()
                                    onHideRequest: topBarScope.closePanel(modelData)
                                }
                            }

                        }
                    }
                }
            }

        }
    }

}
