// ScreenshotUI — M3 Expressive bottom pill for region / window / fullscreen
// screenshots. There is no separate shutter button: picking a mode runs the
// capture on the selection gesture itself.
//
//   Region      native QML selector: dim + crosshair on every output, drag
//               to select — the pill stays mapped and usable (mode switch,
//               close) while selecting; releasing the drag captures the
//               region via `grim -g` (Esc/right-click cancels the drag).
//   Window      pill unmaps and the focused window is grabbed by geometry
//               (`hyprctl activewindow` + `grim -g`; Esc before the grab
//               reopens the pill).
//   Fullscreen  pill unmaps and the whole desktop is grabbed.
//
// Opened by the PRINT keybind (`solstice module screenshot toggle`), dismissed
// by Escape, the close button, the toggle again, a lock or an opening bar
// panel. The backend is backend/scripts/screenshot.sh: the shot lands in the
// configured folder (default ~/Pictures/Screenshots), on the clipboard and
// as a notification — all three controlled by Settings > Panels >
// Screenshot UI (backend/config/screenshot.json).
//
// Expressive vocabulary: pill container, connected segmented mode switch
// with a sliding accent indicator and a springy overshoot open run
// (Theme.curvePanelOpen).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../style/themes"
import "../../backend/services"
import "../../style/ui"

Scope {
    id: scope

    property bool showScreenshot: false
    signal dismissed()

    // ---- modes ----
    readonly property var modes: [
        { id: "region", label: "Region", glyph: "󰆟" },
        { id: "window", label: "Window", glyph: "󰖯" },
        { id: "fullscreen", label: "Fullscreen", glyph: "󰊓" }
    ]
    property string mode: "region"
    readonly property int modeIndex: {
        for (let i = 0; i < scope.modes.length; i++) {
            if (scope.modes[i].id === scope.mode) return i
        }
        return 0
    }
    function setMode(id: string): void {
        for (let i = 0; i < scope.modes.length; i++) {
            if (scope.modes[i].id === id) {
                if (scope.mode !== id) {
                    scope.mode = id
                    // Switching modes aborts any in-progress drag rect.
                    scope.clearSelection()
                }
                return
            }
        }
    }
    function cycleMode(dir: int): void {
        const n = scope.modes.length
        scope.mode = scope.modes[((scope.modeIndex + dir) % n + n) % n].id
    }
    // Segment click: select the mode and start its capture right away.
    // Region is armed by the selection overlay itself, so activating it
    // just (re-)arms the selector instead of capturing.
    function activateMode(id: string): void {
        scope.setMode(id)
        scope.capture()
    }

    // ---- region selection (native, pill stays live) ----
    // `selecting` is true while the drag overlays are mapped. The pill
    // stays visible during it (pillVisible does not exclude selecting);
    // only the final grim grab hides everything via `capturing`.
    readonly property bool selecting: scope.showScreenshot && scope.mode === "region" && !scope.capturing
    // Geometry produced by the overlay drag, in grim layout coordinates
    // ("x,y WxH"), plus the output it was drawn on for `grim -o`.
    property string pendingRegionGeo: ""
    property string pendingRegionOutput: ""
    // Bumped to reset every per-screen drag rect (open / mode switch).
    property int selectionEpoch: 0
    // True while any output has a drag in progress (set by the overlay).
    property bool anyDragging: false
    function clearSelection(): void {
        scope.pendingRegionGeo = ""
        scope.pendingRegionOutput = ""
        scope.selectionEpoch++
    }
    // Called by the selection overlay on mouse release: hide everything
    // first (clean frame for grim), then grab after `captureDelay`.
    function finishRegionSelection(geo: string, outputName: string): void {
        if (!scope.selecting || scope.capturing) return
        if (geo === "") return
        scope.pendingRegionGeo = geo
        scope.pendingRegionOutput = outputName
        scope.capturing = true
        captureTimer.restart()
    }

    // ---- visibility ----
    property bool capturing: false
    readonly property bool pillVisible: scope.showScreenshot && !scope.capturing
    property bool _winVisible: scope.pillVisible
    Timer {
        id: hideTimer
        interval: Theme.durMotionFadeThrough
        repeat: false
        onTriggered: if (!scope.pillVisible) scope._winVisible = false
    }
    onPillVisibleChanged: {
        if (scope.pillVisible) {
            scope._winVisible = true
            hideTimer.stop()
            scope.revealEnter()
        } else if (!scope.capturing) {
            hideTimer.restart()
            scope.revealExit()
        }
    }
    // Capture removes the pill surface immediately (no fade
    // linger): the compositor needs a clean frame before grim grabs it.
    onCapturingChanged: {
        if (scope.capturing) {
            hideTimer.stop()
            scope._winVisible = false
        }
    }
    onShowScreenshotChanged: {
        if (scope.showScreenshot) {
            // Every open starts on the configured default mode (Settings >
            // Panels > Screenshot UI). Region opens pre-armed: the
            // selection overlay maps immediately, the pill stays usable.
            scope.mode = Theme.screenshotDefaultMode
            scope.pendingRegionGeo = ""
            scope.pendingRegionOutput = ""
            scope.selectionEpoch++
        } else {
            scope.capturing = false
            scope.pendingRegionGeo = ""
            scope.pendingRegionOutput = ""
            scope.selectionEpoch++
            captureTimer.stop()
            // Hidden via capture (no exit run played): reset so the next
            // open animates from the hidden pose again.
            if (!scope._winVisible) scope.reveal = 0
        }
    }

    // ---- open/close run: fade + springy rise (expressive overshoot) ----
    property real reveal: 0
    property bool _ready: false
    NumberAnimation {
        id: revealIn
        target: scope
        property: "reveal"
        to: 1
        duration: Theme.panelAnimScale
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curvePanelOpen
    }
    NumberAnimation {
        id: revealOut
        target: scope
        property: "reveal"
        to: 0
        duration: Theme.panelAnimExit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveEmphasizedAccelerate
    }
    function revealEnter(): void {
        if (!scope._ready) return
        revealOut.stop()
        if (!Theme.animationsEnabled) {
            scope.reveal = 1
            return
        }
        revealIn.start()
    }
    function revealExit(): void {
        if (!scope._ready) return
        revealIn.stop()
        if (!Theme.animationsEnabled) {
            scope.reveal = 0
            return
        }
        revealOut.start()
    }
    Component.onCompleted: {
        scope._ready = true
        scope.reveal = scope.pillVisible ? 1 : 0
    }

    // ---- capture ----
    // The unmap has to reach the compositor before grim grabs the frame;
    // give it a beat to repaint.
    readonly property int captureDelay: Math.max(150, Theme.durFastEffects + 80)

    function capture(): void {
        if (scope.capturing || !scope.showScreenshot) return
        if (scope.mode === "region") {
            // Region is driven by the selection-overlay drag (which calls
            // finishRegionSelection on release). Enter/Space with no drag
            // just re-arms the selector.
            scope.clearSelection()
            return
        }
        // Window grabs the focused window by geometry, fullscreen the whole
        // desktop: both unmap the pill first and grab after `captureDelay`.
        scope.capturing = true
        captureTimer.restart()
    }
    Timer {
        id: captureTimer
        interval: scope.captureDelay
        repeat: false
        onTriggered: scope.runCapture()
    }
    function runCapture(): void {
        if (captureProc.running) return
        if (scope.mode === "window") {
            captureProc.command = ["bash", Quickshell.shellDir + "/backend/scripts/screenshot.sh", "window", ""]
        } else if (scope.mode === "region") {
            // Drag released without a valid rect (or IPC capture with no
            // selection): stay open instead of grabbing the desktop.
            if (scope.pendingRegionGeo === "") {
                scope.capturing = false
                return
            }
            captureProc.command = ["bash", Quickshell.shellDir + "/backend/scripts/screenshot.sh", "region-geom", scope.pendingRegionGeo, scope.pendingRegionOutput]
        } else {
            captureProc.command = ["bash", Quickshell.shellDir + "/backend/scripts/screenshot.sh", "fullscreen", ""]
        }
        captureProc.running = true
    }
    Process {
        id: captureProc
        // Output options come from Settings > Panels > Screenshot UI
        // (backend/config/screenshot.json).
        environment: ({
            SOLSTICE_SHOT_DIR: Theme.screenshotSaveDir,
            SOLSTICE_SHOT_CURSOR: Theme.screenshotIncludeCursor ? "1" : "0",
            SOLSTICE_SHOT_CLIPBOARD: Theme.screenshotCopyToClipboard ? "1" : "0",
            SOLSTICE_SHOT_NOTIFY: Theme.screenshotNotify ? "1" : "0"
        })
        onExited: (code, status) => {
            // Region grab failed (bad geometry / grim error): stay open so
            // another rect can be drawn instead of dropping the tool.
            if (code !== 0 && scope.mode === "region") {
                scope.pendingRegionGeo = ""
                scope.pendingRegionOutput = ""
                scope.capturing = false
                return
            }
            scope.dismissed()
        }
    }

    IpcHandler {
        target: "screenshot"
        function mode(m: string): string {
            scope.setMode(m)
            return "mode=" + scope.mode
        }
        // Runs the current mode: window/fullscreen capture.
        // Region is drag-driven; capture() just re-arms the selector.
        function capture(): void { scope.capture() }
        function status(): string {
            return "visible=" + scope.showScreenshot + " mode=" + scope.mode
                + " capturing=" + scope.capturing
                + " selecting=" + scope.selecting
        }
    }

    // Pill sits centered at the bottom of the screen.
    readonly property int bottomMargin: 44

    // ---- region selection overlay ----
    // Native drag surfaces, one per output on Top (below the Overlay pill,
    // which keeps its Exclusive keyboard focus + clicks). No slurp: the
    // pill stays mapped and usable while selecting; both surfaces unmap
    // only for the final grim grab via `capturing`.
    // NOTE: a drag cannot span outputs — release on the output where the
    // press started. Geometry is converted to grim layout coordinates via
    // screen.x/screen.y.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: selWin
            required property var modelData
            screen: modelData
            visible: scope.selecting
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "screenshot-selector"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Local drag state (window-local logical pixels).
            property real pressX: 0
            property real pressY: 0
            property real curX: 0
            property real curY: 0
            property bool dragging: false
            readonly property real selX: Math.min(selWin.pressX, selWin.curX)
            readonly property real selY: Math.min(selWin.pressY, selWin.curY)
            readonly property real selW: Math.abs(selWin.curX - selWin.pressX)
            readonly property real selH: Math.abs(selWin.curY - selWin.pressY)
            readonly property bool hasSel: selWin.dragging && selWin.selW >= 4 && selWin.selH >= 4

            // Epoch bump (open / mode switch / Esc) aborts any drag.
            property int epoch: scope.selectionEpoch
            onEpochChanged: {
                if (selWin.dragging) {
                    selWin.dragging = false
                    scope.anyDragging = false
                }
            }

            function abortDrag(): void {
                if (selWin.dragging) {
                    selWin.dragging = false
                    scope.anyDragging = false
                }
            }

            MouseArea {
                id: selMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.CrossCursor
                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        selWin.abortDrag()
                        return
                    }
                    selWin.pressX = mouse.x
                    selWin.pressY = mouse.y
                    selWin.curX = mouse.x
                    selWin.curY = mouse.y
                    selWin.dragging = true
                    scope.anyDragging = true
                }
                onPositionChanged: mouse => {
                    if (selWin.dragging) {
                        selWin.curX = mouse.x
                        selWin.curY = mouse.y
                    }
                }
                onReleased: mouse => {
                    if (mouse.button === Qt.RightButton || !selWin.dragging) return
                    selWin.curX = mouse.x
                    selWin.curY = mouse.y
                    const wasValid = selWin.hasSel
                    const gx = Math.round(selWin.modelData.x + selWin.selX)
                    const gy = Math.round(selWin.modelData.y + selWin.selY)
                    const gw = Math.round(selWin.selW)
                    const gh = Math.round(selWin.selH)
                    selWin.dragging = false
                    scope.anyDragging = false
                    // Click without drag: stay armed. Valid drag: capture.
                    if (wasValid && gw >= 4 && gh >= 4) {
                        scope.finishRegionSelection(gx + "," + gy + " " + gw + "x" + gh, "" + selWin.modelData.name)
                    }
                }
                onCanceled: selWin.abortDrag()
            }

            // Full dim when idle; cut into 4 bands around the rect while
            // dragging so the selection shows undimmed.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: 0.45
                visible: !selWin.hasSel
            }
            Rectangle { // top band
                x: 0; y: 0; width: parent.width; height: selWin.selY
                color: "black"; opacity: 0.45; visible: selWin.hasSel
            }
            Rectangle { // bottom band
                x: 0; y: selWin.selY + selWin.selH; width: parent.width; height: parent.height - (selWin.selY + selWin.selH)
                color: "black"; opacity: 0.45; visible: selWin.hasSel
            }
            Rectangle { // left band
                x: 0; y: selWin.selY; width: selWin.selX; height: selWin.selH
                color: "black"; opacity: 0.45; visible: selWin.hasSel
            }
            Rectangle { // right band
                x: selWin.selX + selWin.selW; y: selWin.selY
                width: parent.width - (selWin.selX + selWin.selW); height: selWin.selH
                color: "black"; opacity: 0.45; visible: selWin.hasSel
            }

            // Selection frame + corner handles + size badge.
            Rectangle {
                x: selWin.selX; y: selWin.selY; width: selWin.selW; height: selWin.selH
                color: "transparent"
                border.color: Theme.accent
                border.width: 2
                visible: selWin.hasSel
            }
            Repeater {
                model: selWin.hasSel ? 4 : 0
                delegate: Rectangle {
                    required property int index
                    readonly property real hs: 8
                    x: selWin.selX - hs / 2 + [0, selWin.selW, 0, selWin.selW][index]
                    y: selWin.selY - hs / 2 + [0, 0, selWin.selH, selWin.selH][index]
                    width: hs; height: hs; radius: 2
                    color: Theme.accent
                }
            }
            Rectangle {
                id: sizeBadge
                visible: selWin.hasSel
                x: Math.min(Math.max(selWin.selX, 8), parent.width - width - 8)
                y: (selWin.selY + selWin.selH + 8 + height <= parent.height) ? (selWin.selY + selWin.selH + 8) : Math.max(selWin.selY - height - 8, 8)
                width: sizeLabel.implicitWidth + 16
                height: 26
                radius: 13
                color: Theme.panelWindowBg
                border.color: Theme.panelBorderColor
                border.width: 1
                Text {
                    id: sizeLabel
                    anchors.centerIn: parent
                    text: Math.round(selWin.selW) + " × " + Math.round(selWin.selH)
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Medium
                }
            }

            // Idle hint (primary screen only to avoid repetition).
            Rectangle {
                visible: !selWin.dragging && Theme.isPrimaryScreen(selWin.modelData)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 48
                width: hintLabel.implicitWidth + 28
                height: 36
                radius: 18
                color: Theme.panelWindowBg
                border.color: Theme.panelBorderColor
                border.width: 1
                opacity: 0.95
                Text {
                    id: hintLabel
                    anchors.centerIn: parent
                    text: "Drag to select  •  Right-click / Esc cancels"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Medium
                }
            }
        }
    }

    // ---- the pill ----
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: scope._winVisible && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "screenshotui"
            WlrLayershell.keyboardFocus: scope.pillVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region { item: pillWrapper }

            Item {
                id: pillWrapper
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: scope.bottomMargin
                width: pill.width
                height: pill.height
                focus: true
                opacity: scope.reveal
                scale: 0.86 + 0.14 * scope.reveal
                transformOrigin: Item.Bottom
                transform: Translate { y: (1 - scope.reveal) * 26 }

                Connections {
                    target: scope
                    function onPillVisibleChanged() {
                        if (scope.pillVisible) Qt.callLater(() => pillWrapper.forceActiveFocus())
                    }
                }
                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        // Mid-drag Esc aborts the rect, otherwise dismiss.
                        if (scope.selecting && scope.anyDragging) scope.clearSelection()
                        else scope.dismissed()
                        event.accepted = true
                        break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        scope.capture()
                        event.accepted = true
                        break
                    case Qt.Key_Left:
                        scope.cycleMode(-1)
                        event.accepted = true
                        break
                    case Qt.Key_Right:
                        scope.cycleMode(1)
                        event.accepted = true
                        break
                    }
                }

                Rectangle {
                    id: pill
                    width: content.implicitWidth + 20
                    height: 68
                    radius: height / 2
                    color: Theme.panelWindowBg
                    border.color: Theme.panelBorderColor
                    border.width: 2
                    antialiasing: Theme.shapesAa

                    layer.enabled: scope._winVisible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.withAlpha(Theme.scrim, 0.45)
                        shadowBlur: 0.8
                        shadowOpacity: 0.35
                        shadowVerticalOffset: 8
                    }

                    RowLayout {
                        id: content
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        // Connected segmented button group: tonal pill with
                        // a sliding accent indicator under the active mode.
                        // Clicking a segment starts that capture immediately.
                        Rectangle {
                            id: group
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: segRow.width + 8
                            Layout.preferredHeight: 48
                            radius: height / 2
                            color: Theme.withAlpha(Theme.textPrimary, 0.07)
                            antialiasing: Theme.shapesAa

                            // The active segment's delegate; count is read
                            // so the binding re-evaluates when the Repeater
                            // populates (itemAt alone is not notifiable).
                            readonly property Item currentSeg: {
                                const populated = segRepeater.count
                                return segRepeater.itemAt(scope.modeIndex)
                            }

                            Rectangle {
                                id: indicator
                                x: group.currentSeg ? segRow.x + group.currentSeg.x : segRow.x
                                y: 4
                                width: group.currentSeg ? group.currentSeg.width : 0
                                height: 40
                                radius: height / 2
                                color: Theme.accent
                                antialiasing: Theme.shapesAa
                                visible: width > 0
                                Behavior on x {
                                    enabled: Theme.animationsEnabled
                                    NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curvePanelOpen }
                                }
                                Behavior on width {
                                    enabled: Theme.animationsEnabled
                                    NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curvePanelOpen }
                                }
                            }

                            Row {
                                id: segRow
                                x: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                Repeater {
                                    id: segRepeater
                                    model: scope.modes

                                    delegate: Item {
                                        id: seg
                                        required property var modelData
                                        required property int index
                                        readonly property bool selected: scope.mode === seg.modelData.id
                                        implicitWidth: segIcon.implicitWidth + 8 + segLabel.implicitWidth + 32
                                        implicitHeight: 40

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                id: segIcon
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: seg.modelData.glyph
                                                color: seg.selected ? Theme.onAccent : Theme.textSecondary
                                                font.family: Theme.iconFontFamily
                                                font.pixelSize: Theme.fs(17)
                                                antialiasing: Theme.textAa
                                                renderType: Theme.textRenderType
                                                Behavior on color {
                                                    enabled: Theme.animationsEnabled
                                                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                                                }
                                            }
                                            Text {
                                                id: segLabel
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: seg.modelData.label
                                                color: seg.selected ? Theme.onAccent : Theme.textSecondary
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(13)
                                                font.weight: seg.selected ? Font.DemiBold : Font.Medium
                                                antialiasing: Theme.textAa
                                                renderType: Theme.textRenderType
                                                Behavior on color {
                                                    enabled: Theme.animationsEnabled
                                                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                                                }
                                            }
                                        }
                                        StateLayer {
                                            anchors.fill: parent
                                            radius: 20
                                            color: seg.selected ? Theme.onAccent : Theme.textPrimary
                                            onClicked: {
                                                pillWrapper.forceActiveFocus()
                                                scope.activateMode(seg.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 28
                            color: Theme.divider
                            antialiasing: Theme.shapesAa
                        }

                        Item {
                            id: closeBtn
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: closeLayer.containsMouse ? Theme.accent : Theme.textSecondary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(17)
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                Behavior on color {
                                    enabled: Theme.animationsEnabled
                                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                                }
                            }
                            StateLayer {
                                id: closeLayer
                                anchors.fill: parent
                                radius: 20
                                color: Theme.textPrimary
                                onClicked: scope.dismissed()
                            }
                        }
                    }
                }
            }
        }
    }
}
