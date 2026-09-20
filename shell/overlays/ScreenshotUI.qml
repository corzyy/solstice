// ScreenshotUI — M3 Expressive bottom pill for region / window / fullscreen
// screenshots. There is no separate shutter button: picking a mode runs the
// capture on the selection gesture itself.
//
//   Region      pill unmaps, slurp draws the selection; releasing the drag
//               captures the region (Esc in slurp cancels and reopens the
//               pill).
//   Window      pill unmaps, a full-screen picker dims the desktop and
//               highlights the window under the pointer; releasing the mouse
//               over a window captures it (Esc/right click cancels).
//   Fullscreen  pill unmaps and the whole desktop is grabbed.
//
// Opened by the PRINT keybind (`solstice module screenshot toggle`), dismissed
// by Escape, the close button, the toggle again, a lock or an opening bar
// panel. The backend is scripts/screenshot.sh: the shot lands in the
// configured folder (default ~/Pictures/Screenshots), on the clipboard and
// as a notification — all three controlled by Settings > Panels >
// Screenshot UI (config/screenshot.json).
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
import "../themes"
import "../services"
import "../ui"

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
                scope.mode = id
                return
            }
        }
    }
    function cycleMode(dir: int): void {
        const n = scope.modes.length
        scope.mode = scope.modes[((scope.modeIndex + dir) % n + n) % n].id
    }
    // Segment click: select the mode and start its capture right away.
    function activateMode(id: string): void {
        scope.setMode(id)
        scope.capture()
    }

    // ---- visibility ----
    property bool capturing: false
    // Window mode's picker surface (see the second Variants below).
    property bool pickingWindow: false
    readonly property bool pillVisible: scope.showScreenshot && !scope.capturing && !scope.pickingWindow
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
        } else if (!scope.capturing && !scope.pickingWindow) {
            hideTimer.restart()
            scope.revealExit()
        }
    }
    // Capture and picking remove the pill surface immediately (no fade
    // linger): the compositor needs a clean frame before grim grabs it and
    // the picker must not sit under a ghost pill.
    onCapturingChanged: {
        if (scope.capturing) {
            hideTimer.stop()
            scope._winVisible = false
        }
    }
    onPickingWindowChanged: {
        if (scope.pickingWindow) {
            hideTimer.stop()
            scope._winVisible = false
        }
    }
    onShowScreenshotChanged: {
        if (scope.showScreenshot) {
            // Every open starts on the configured default mode (Settings >
            // Panels > Screenshot UI).
            scope.mode = Theme.screenshotDefaultMode
        } else {
            scope.capturing = false
            scope.pickingWindow = false
            scope.hoveredGeometry = null
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
    property string pickedGeometry: ""

    function capture(): void {
        if (scope.capturing || scope.pickingWindow || !scope.showScreenshot) return
        if (scope.mode === "window") {
            scope.beginWindowPick()
            return
        }
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
        const geo = scope.mode === "window" ? scope.pickedGeometry : ""
        captureProc.command = ["bash", Quickshell.shellDir + "/scripts/screenshot.sh", scope.mode, geo]
        captureProc.running = true
    }
    Process {
        id: captureProc
        // Output options come from Settings > Panels > Screenshot UI
        // (config/screenshot.json).
        environment: ({
            SOLSTICE_SHOT_DIR: Theme.screenshotSaveDir,
            SOLSTICE_SHOT_CURSOR: Theme.screenshotIncludeCursor ? "1" : "0",
            SOLSTICE_SHOT_CLIPBOARD: Theme.screenshotCopyToClipboard ? "1" : "0",
            SOLSTICE_SHOT_NOTIFY: Theme.screenshotNotify ? "1" : "0"
        })
        onExited: (code, status) => {
            // slurp cancelled (Escape / empty selection): bring the pill
            // back so another mode can be picked instead of dropping the
            // tool.
            if (code !== 0 && scope.mode === "region") {
                scope.capturing = false
                return
            }
            scope.dismissed()
        }
    }

    // ---- window picker ----
    // Hovered toplevel from UmbrielService, {id,x,y,w,h,appId,title} or null.
    property var hoveredGeometry: null

    function beginWindowPick(): void {
        if (!scope.showScreenshot || scope.capturing) return
        scope.pickedGeometry = ""
        scope.hoveredGeometry = null
        scope.pickingWindow = true
    }
    function cancelWindowPick(): void {
        scope.pickingWindow = false
        scope.hoveredGeometry = null
    }
    function updateHover(screenObj: var, lx: real, ly: real): void {
        if (!screenObj) return
        scope.hoveredGeometry = UmbrielService.windowGeometryAt(lx + screenObj.x, ly + screenObj.y)
    }
    function pickWindow(win: var): void {
        if (!win) return
        scope.pickedGeometry = Math.round(win.x) + "," + Math.round(win.y) + " "
            + Math.round(win.w) + "x" + Math.round(win.h)
        scope.pickingWindow = false
        scope.hoveredGeometry = null
        scope.capturing = true
        captureTimer.restart()
    }

    IpcHandler {
        target: "screenshot"
        function mode(m: string): string {
            scope.setMode(m)
            return "mode=" + scope.mode
        }
        // Runs the current mode: region/fullscreen capture, window picker.
        function capture(): void { scope.capture() }
        // Capture the window at a compositor-layout point (script/debug
        // entry point for what the picker does on release).
        function pickAt(x: real, y: real): string {
            const w = UmbrielService.windowGeometryAt(x, y)
            if (!w) return "none"
            scope.pickWindow(w)
            return "picked=" + w.id
        }
        function status(): string {
            return "visible=" + scope.showScreenshot + " mode=" + scope.mode
                + " capturing=" + scope.capturing + " picking=" + scope.pickingWindow
        }
    }

    // Pill sits above a bottom bar when one is configured.
    readonly property int bottomMargin: 44 + (Theme.barPosition === "bottom" ? Theme.barThickness : 0)

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
                        scope.dismissed()
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

    // ---- window picker surface (all screens) ----
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: pickWin
            required property var modelData
            screen: modelData
            visible: scope.showScreenshot && scope.pickingWindow
            color: "transparent"
            exclusiveZone: 0
            // Cover the whole screen including the bar's exclusive zone:
            // the bar itself stays visible through the scrim's hole (and
            // the program indicator stacks above it).
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "screenshotpicker"
            // Only the primary screen owns the keyboard (Esc); the others
            // are pointer-only dim surfaces.
            WlrLayershell.keyboardFocus: Theme.isPrimaryScreen(modelData) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Hovered window in this screen's local coordinates.
            readonly property var hovered: scope.hoveredGeometry
            readonly property real hx: hovered ? hovered.x - modelData.x : 0
            readonly property real hy: hovered ? hovered.y - modelData.y : 0
            readonly property real hw: hovered ? hovered.w : 0
            readonly property real hh: hovered ? hovered.h : 0
            // The hovered window lives on exactly one screen; only that
            // delegate draws the program indicator (the hole math is
            // harmless on the others, the label would not be).
            readonly property bool ownsHover: {
                if (!hovered) return false
                const cx = hovered.x + hovered.w / 2
                const cy = hovered.y + hovered.h / 2
                return cx >= modelData.x && cx < modelData.x + modelData.width
                    && cy >= modelData.y && cy < modelData.y + modelData.height
            }


            Item {
                id: pickRoot
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        scope.cancelWindowPick()
                        event.accepted = true
                    }
                }
                Component.onCompleted: if (scope.pickingWindow) forceActiveFocus()
                Connections {
                    target: scope
                    function onPickingWindowChanged() {
                        if (scope.pickingWindow) Qt.callLater(() => pickRoot.forceActiveFocus())
                    }
                }

                // Dim everything except the hovered window and the top bar:
                // two holes in an odd-even filled screen rect. Keeping the
                // bar out of the scrim is what stops it from reading as
                // "gone" while picking.
                Shape {
                    id: dimShape
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    readonly property rect barHole: {
                        if (!Theme.barPersistent) return Qt.rect(0, 0, 0, 0)
                        if (!Theme.isPrimaryScreen(pickWin.modelData)) return Qt.rect(0, 0, 0, 0)
                        const r = Theme.barWindowRect
                        if (!r || r.w <= 0 || r.h <= 0) return Qt.rect(0, 0, 0, 0)
                        return Qt.rect(r.x, r.y, r.w, r.h)
                    }
                    readonly property rect winHole: (pickWin.hw > 0 && pickWin.hh > 0)
                        ? Qt.rect(pickWin.hx, pickWin.hy, pickWin.hw, pickWin.hh)
                        : Qt.rect(0, 0, 0, 0)

                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Theme.withAlpha(Theme.scrim, 0.35)
                        fillRule: ShapePath.OddEvenFill
                        // Outer: the whole screen.
                        startX: 0
                        startY: 0
                        PathLine { x: dimShape.width; y: 0 }
                        PathLine { x: dimShape.width; y: dimShape.height }
                        PathLine { x: 0; y: dimShape.height }
                        PathLine { x: 0; y: 0 }
                        // Hole: top bar (counter-clockwise so the hole also
                        // works under WindingFill).
                        PathMove { x: dimShape.barHole.x; y: dimShape.barHole.y }
                        PathLine { x: dimShape.barHole.x; y: dimShape.barHole.y + dimShape.barHole.height }
                        PathLine { x: dimShape.barHole.x + dimShape.barHole.width; y: dimShape.barHole.y + dimShape.barHole.height }
                        PathLine { x: dimShape.barHole.x + dimShape.barHole.width; y: dimShape.barHole.y }
                        PathLine { x: dimShape.barHole.x; y: dimShape.barHole.y }
                        // Hole: hovered window.
                        PathMove { x: dimShape.winHole.x; y: dimShape.winHole.y }
                        PathLine { x: dimShape.winHole.x; y: dimShape.winHole.y + dimShape.winHole.height }
                        PathLine { x: dimShape.winHole.x + dimShape.winHole.width; y: dimShape.winHole.y + dimShape.winHole.height }
                        PathLine { x: dimShape.winHole.x + dimShape.winHole.width; y: dimShape.winHole.y }
                        PathLine { x: dimShape.winHole.x; y: dimShape.winHole.y }
                    }
                }
                Rectangle {
                    visible: pickWin.hw > 0 && pickWin.hh > 0
                    x: pickWin.hx
                    y: pickWin.hy
                    width: pickWin.hw
                    height: pickWin.hh
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: 2
                    radius: Theme.cornerRadiusSmall
                    antialiasing: Theme.shapesAa
                }

                // Hovered program indicator: a pill centred over the top bar
                // (the top edge on screens without one). This picker is an
                // overlay surface, so the indicator always stacks above the
                // bar, which itself stays un-dimmed behind it.
                Rectangle {
                    id: programLabel
                    visible: pickWin.ownsHover
                    readonly property rect barRect: Theme.isPrimaryScreen(pickWin.modelData)
                        ? Theme.barWindowRect : Qt.rect(0, 0, 0, 0)
                    readonly property real barH: barRect.height > 0 ? barRect.height : Theme.barThickness
                    width: Math.min(labelText.implicitWidth + 36, pickWin.width - 32)
                    height: 30
                    radius: height / 2
                    x: Math.round((pickWin.width - width) / 2)
                    y: Math.round(Math.max(2, barRect.y + (barH - height) / 2))
                    color: Theme.panelWindowBg
                    border.color: Theme.accent
                    border.width: 2
                    antialiasing: Theme.shapesAa

                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        width: parent.width - 24
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: pickWin.hovered
                            ? (pickWin.hovered.appId + (pickWin.hovered.title.length > 0 ? " — " + pickWin.hovered.title : ""))
                            : ""
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.DemiBold
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }

                // Bottom hint while nothing is hovered, same shape language
                // as the pill.
                Rectangle {
                    id: pickHint
                    visible: pickWin.hovered === null
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: scope.bottomMargin
                    width: hintText.implicitWidth + 40
                    height: 48
                    radius: height / 2
                    color: Theme.panelWindowBg
                    border.color: Theme.panelBorderColor
                    border.width: 2
                    antialiasing: Theme.shapesAa
                    Text {
                        id: hintText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, pickHint.parent.width - 80)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: "Release over a window to capture · Esc to cancel"
                        color: Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.Medium
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    cursorShape: Qt.CrossCursor
                    // Seed the highlight when the pointer lands on the freshly
                    // mapped surface (it can appear under a stationary
                    // pointer; wl_pointer.enter still arrives).
                    onContainsMouseChanged: if (containsMouse) scope.updateHover(pickWin.modelData, mouseX, mouseY)
                    onPositionChanged: mouse => scope.updateHover(pickWin.modelData, mouse.x, mouse.y)
                    onPressed: mouse => scope.updateHover(pickWin.modelData, mouse.x, mouse.y)
                    onReleased: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            scope.cancelWindowPick()
                            return
                        }
                        if (mouse.button !== Qt.LeftButton) return
                        scope.updateHover(pickWin.modelData, mouse.x, mouse.y)
                        scope.pickWindow(scope.hoveredGeometry)
                    }
                }
            }
        }
    }
}
