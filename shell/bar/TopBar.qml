pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./widgets" as Bar

import "../../backend/services"
import "../../style/themes"

Scope {
    id: topBarScope
    signal toggleNotificationCenter()
    signal toggleSystemTray()
    signal toggleControlCenter()
    signal toggleLauncher()
    signal closePanel(string moduleId)

    property bool notificationCenterOpen: false
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
            clock: "notificationCenterOpen",
            systemtray: "trayOpen",
            controlcenter: "controlCenterOpen",
            launcher: "launcherOpen"
        }[id]
        return flag !== undefined ? !!topBarScope[flag] : false
    }

    IpcHandler {
        target: "updates"
        function check(): string { UpdateService.checkNow(); return "checking system+flatpak..." }
        function status(): string { return UpdateService.status() }
        function debug(arg: string): string { return UpdateService.setDebug(arg) }
        function debugCount(n: int): string { UpdateService.debugCount = n; UpdateService.debugForce = true; return "debugCount=" + n }
    }

    // The bar always reserves its strip; on outputs where a fullscreen window
    // is visible it collapses to the hidden strip (fullscreenSuppressed in the
    // window below) so it can never paint over the game, while the reserved
    // zone is kept so exiting fullscreen does not shift tiled windows.

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
            onBarHeightChanged: { Theme.barEffectiveHeight = barHeight; Theme.barEffectiveWidth = barHeight }
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
            onEdgeDistChanged: requestPublishWindowRect()
            onTopDistChanged: requestPublishWindowRect()
            // Monitor switch: the newly primary bar publishes its geometry so
            // popouts settle against the right screen immediately.
            onVisibleChanged: if (visible) requestPublishWindowRect()
            property int edgeDist: Theme.barEdgeDistance
            property int topDist: Theme.barTopDistance
            // Auto-hide (Caelestia bar.persistent/showOnHover/dragThreshold):
            // non-persistent bars collapse to a 2px input strip that paints
            // nothing (revealProgress 0) and reveal on hover (when enabled)
            // or on an edge drag past the threshold.
            readonly property bool autoHide: !Theme.barPersistent
            property bool barRevealed: false
            // A fullscreen window on this output collapses the bar to the
            // hidden strip: the compositor normally stacks the view above the
            // Top layer, but some fullscreen paths leave it below (or in the
            // tiled layer during transitions), where the bar would otherwise
            // paint over the game. `revealed` still drives the exclusive zone,
            // so the reserved strip is kept and tiled windows do not shift
            // when fullscreen is exited.
            readonly property bool fullscreenSuppressed: HyprlandService.isOutputFullscreen(modelData.name)
            onFullscreenSuppressedChanged: if (fullscreenSuppressed) barRevealed = false
            readonly property bool revealed: !autoHide || barRevealed || topBarScope.anyPanelOpen
            readonly property int hiddenThickness: 2
            // 1 when fully expanded, 0 when collapsed: drives content opacity
            // so a hidden bar is completely invisible while its surface stays
            // mapped for hover/drag reveal.
            readonly property real revealProgress: {
                const span = Math.max(1, barHeight - hiddenThickness)
                return Math.max(0, Math.min(1, (topBarWindow.height - hiddenThickness) / span))
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
            exclusiveZone: Theme.isPrimaryScreen(modelData) ? (revealed ? barHeight + topDist : 0) : 0
            anchors { top: true; bottom: false; left: true; right: true }
            margins {
                top: topBarWindow.topDist
                bottom: 0
                left: topBarWindow.edgeDist
                right: topBarWindow.edgeDist
            }
            implicitHeight: revealed && !fullscreenSuppressed ? barHeight : hiddenThickness
            implicitWidth: 0
            Behavior on implicitHeight { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            color: "transparent"

            // Hover reveals (bar.showOnHover) and, once revealed, leaving hides.
            HoverHandler {
                enabled: topBarWindow.autoHide && !topBarWindow.fullscreenSuppressed
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
                enabled: topBarWindow.autoHide && !topBarWindow.revealed && !topBarWindow.fullscreenSuppressed
                acceptedButtons: Qt.LeftButton
                property real pressY: 0
                onPressed: mouse => {
                    pressY = mouse.y
                }
                onPositionChanged: mouse => {
                    const d = mouse.y - pressY
                    if (d >= Math.max(1, Theme.barDragThreshold)) topBarWindow.barRevealed = true
                }
            }
            // Scroll actions: top half volume, bottom half brightness.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                enabled: topBarWindow.revealed && !topBarWindow.fullscreenSuppressed
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

            // Concave coves carved into the bar's underside where it meets
            // the side screen edges — like the fillets joining panels to
            // the bar. The bar stays full-bleed everywhere else; Display
            // Radius sets the cove size (0 = plain square bar, always
            // opaque). Floating bars keep the convex Appearance Rounding.
            Shape {
                id: barBgShape
                anchors.fill: parent
                opacity: topBarWindow.revealProgress
                visible: topBarWindow.edgeDist <= 0 && topBarWindow.topDist <= 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.panelWindowBg
                    strokeWidth: 0
                    strokeColor: "transparent"
                    PathSvg { path: barBgShape.barPath() }
                }
                function barPath(): string {
                    const W = barBgShape.width
                    const H = barBgShape.height
                    const d = Theme.barDisplayRadius
                    const r = Math.max(0, Math.min(d, H, W / 2))
                    const n = v => "" + (Math.round(v * 100) / 100)
                    const w = n(W), h = n(H), rr = n(r)
                    const wr = n(W - r), hr = n(H - r)
                    if (r <= 0.01) return "M 0 0 H " + w + " V " + h + " H 0 Z"
                    return "M 0 0 H " + w + " V " + hr + " A " + rr + " " + rr + " 0 0 0 " + wr + " " + h + " H " + rr + " A " + rr + " " + rr + " 0 0 0 0 " + hr + " Z"
                }
            }

            Rectangle {
                antialiasing: Theme.shapesAa
                anchors.fill: parent
                opacity: topBarWindow.revealProgress
                visible: topBarWindow.edgeDist > 0 || topBarWindow.topDist > 0
                radius: Theme.cornerRadius
                color: Theme.panelWindowBg
            }

            Component.onCompleted: { Theme.barEffectiveWidth = barHeight; Theme.barEffectiveHeight = barHeight; publishWindowRect(); Qt.callLater(publishWindowRect); HyprlandService.registerBarWindow(topBarWindow) }
            Component.onDestruction: HyprlandService.unregisterBarWindow(topBarWindow)

            function publishWindowRect(): void {
                if (!Theme.isPrimaryScreen(modelData)) return
                // Suppressed bars are collapsed to the hidden strip; keep the
                // last full-bar rect so panels still anchor to the right place.
                if (fullscreenSuppressed) return
                try {
                    let mL = 0, mT = 0
                    try { let m = margins; if (m) { mL = m.left || 0; mT = m.top || 0 } } catch (e3) { }
                    Theme.setBarWindowRect(mL, mT, width, height)
                } catch (e) { }
            }
            Item {
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
                            model: Theme.barLayoutLeft
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    monitor: topBarWindow.modelData
                                    barWindow: topBarWindow

                                    onRequestNotificationCenter: topBarScope.toggleNotificationCenter()
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
                            model: Theme.barLayoutTwoFifths
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    monitor: topBarWindow.modelData
                                    barWindow: topBarWindow

                                    onRequestNotificationCenter: topBarScope.toggleNotificationCenter()
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
                            model: Theme.barLayoutCenter
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    monitor: topBarWindow.modelData
                                    barWindow: topBarWindow

                                    onRequestNotificationCenter: topBarScope.toggleNotificationCenter()
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
                            model: Theme.barLayoutFourFifths
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    monitor: topBarWindow.modelData
                                    barWindow: topBarWindow

                                    onRequestNotificationCenter: topBarScope.toggleNotificationCenter()
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
                            model: Theme.barLayoutRight
                                Bar.BarSlot {
                                    required property var modelData
                                    required property int index
                                    mergeState: topBarScope.mergeState
                                    moduleId: modelData
                                    active: topBarScope.moduleActive(modelData)
                                    Layout.alignment: Qt.AlignVCenter
                                    monitor: topBarWindow.modelData
                                    barWindow: topBarWindow

                                    onRequestNotificationCenter: topBarScope.toggleNotificationCenter()
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
