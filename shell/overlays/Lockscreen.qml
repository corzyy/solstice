pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../themes"
import "../services"
import "../ui"

// Lockscreen — fullscreen overlay per monitor. Background is the current
// wallpaper blurred (GPU, MultiEffect) under a dim scrim; the clock and the
// PIN field live in one centered card (same surface/rounding as the power
// menu card). Locking from the power menu runs a merge morph: shell.qml
// hands over the power card's window-local rect (lockFrom), the card starts
// at exactly that pose with a visual replica of the power grid, then morphs
// into the settled clock+PIN pose while the grid fades out and the card
// content fades in.
Scope {
    id: lockScope
    property bool locked: false
    property string pinInput: ""
    property bool failed: false
    property string errorText: ""
    property string wallpaperPath: ""
    readonly property string wallpaperSource: wallpaperPath !== "" ? "file://" + wallpaperPath : ""

    // Merge state: null = plain FadeThrough lock (IPC/keybind), else the
    // power card rect handed over by shell.qml.
    property var mergeRect: null
    property real mergePhase: 0
    readonly property int clockFontSize: Theme.fs(96)

    // Einziger Reset-Pfad für den PIN-Zustand (war 3x kopiert).
    function resetPinState(): void {
        pinInput = ""
        failed = false
        errorText = ""
    }
    function lock(): void { lockFrom(null) }
    function lockFrom(rect: var): void {
        if (locked) return
        mergeRect = (rect && rect.w > 0 && rect.h > 0) ? rect : null
        resetPinState()
        refreshWallpaper()
        mergeAnim.stop()
        if (!Theme.animationsEnabled) {
            mergePhase = 1
        } else {
            mergePhase = 0
            mergeAnim.restart()
        }
        locked = true
    }
    function unlock(): void {
        locked = false
        mergeRect = null
        resetPinState()
    }
    function refreshWallpaper(): void {
        if (!wallpaperResolveProc.running) wallpaperResolveProc.running = true
    }
    function submitPin(): void {
        if (pinInput.length === 0) return
        clearPinError()
        authProc.command = [Quickshell.shellDir + "/scripts/lock-auth.sh", pinInput]
        if (!authProc.running) authProc.running = true
    }

    // Fehler-Reset ohne die gerade eingegebene PIN zu löschen.
    function clearPinError(): void {
        failed = false
        errorText = ""
    }

    // Merge run: power pose -> settled lock box, M3 emphasized (the same
    // curve the panel morph system uses).
    NumberAnimation {
        id: mergeAnim
        target: lockScope
        property: "mergePhase"
        to: 1
        duration: Theme.durMotionSharedAxis
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveMotion
    }

    Process {
        id: wallpaperResolveProc
        command: ["bash", "-c", "for f in \"$(cat ~/.config/quickshell/solstice/config/current_wallpaper.txt 2>/dev/null)\" \"$(cat ~/.cache/swaybg/current 2>/dev/null)\" \"$(cat ~/.cache/awww/current 2>/dev/null)\"; do f=\"${f#file://}\"; if [ -n \"$f\" ] && [ -f \"$f\" ]; then printf '%s' \"$f\"; exit 0; fi; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: lockScope.wallpaperPath = String(text || "").trim()
        }
    }
    Component.onCompleted: refreshWallpaper()

    Process {
        id: authProc
        stdout: StdioCollector { }
        stderr: StdioCollector { }
        onExited: (code) => {
            if (code === 0) {
                lockScope.unlock()
            } else {
                lockScope.failed = true
                lockScope.errorText = "Wrong PIN"
                lockScope.pinInput = ""
                failTimer.restart()
            }
        }
    }
    Timer {
        id: failTimer
        interval: 1500
        onTriggered: lockScope.clearPinError()
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            // Always mapped: a fresh lock surface takes long enough to map
            // that the merge run would lose its first frames. While unlocked
            // the window is fully transparent AND masked to a 0x0 input
            // region, so clicks pass through to the shell/desktop.
            visible: true
            color: "transparent"
            exclusiveZone: 0
            mask: Region { item: lockScope.locked ? contentRoot : hitShield }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "lockscreen"
            WlrLayershell.keyboardFocus: Theme.isPrimaryScreen(modelData) && lockScope.locked ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            Item { id: hitShield; width: 0; height: 0 }
            SystemClock { id: lockClock; enabled: lockScope.locked && Theme.isPrimaryScreen(modelData); precision: SystemClock.Minutes }

            Item {
                id: contentRoot
                anchors.fill: parent
                clip: false
                // Lock-in/out: M3 fade through (fade + settle) for the
                // backdrop; a merge lock brings its own timing (the card is
                // already on screen, the wallpaper catches up quickly).
                Motion {
                    id: lockMotion
                    active: lockScope.locked
                    pattern: Motion.FadeThrough
                }
                readonly property real bgFade: lockScope.mergeRect !== null
                    ? Math.min(1, lockScope.mergePhase * 3)
                    : lockMotion.opacity

                // Wallpaper: rendered as the blur source (hidden), the
                // visible layer is the MultiEffect below.
                Image {
                    id: bgImage
                    anchors.fill: parent
                    source: lockScope.wallpaperSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: false
                }
                Rectangle {
                    id: fallbackBg
                    anchors.fill: parent
                    color: Theme.bg
                    visible: contentRoot.bgFade > 0.001 && (bgImage.status !== Image.Ready || bgImage.source === "")
                }
                MultiEffect {
                    source: bgImage
                    anchors.fill: bgImage
                    blurEnabled: true
                    blur: 0.85
                    blurMax: 64
                    opacity: contentRoot.bgFade
                    visible: contentRoot.bgFade > 0.001 && bgImage.status === Image.Ready && bgImage.source !== ""
                }
                Rectangle {
                    anchors.fill: parent
                    color: Theme.scrim
                    opacity: 0.30 * contentRoot.bgFade
                }

                // Clock + PIN card. During a power-menu merge its pose is
                // interpolated from the handed-over power card rect into the
                // centered settled box.
                Rectangle {
                    id: lockCard
                    visible: lockScope.locked && Theme.isPrimaryScreen(modelData)

                    readonly property var from: lockScope.mergeRect
                    readonly property real p: lockScope.mergePhase
                    // Settled box is deliberately larger than the power
                    // card (400x~356) so the merge run has room to morph.
                    readonly property real targetW: 440
                    readonly property real targetH: lockCol.implicitHeight + 64
                    // Power card content width (400 - 2*28): the merge
                    // replica must keep the power grid geometry, not the
                    // larger settled one.
                    readonly property real powerContentW: 344
                    readonly property real targetX: Math.round((parent.width - targetW) / 2)
                    readonly property real targetY: Math.round((parent.height - targetH) / 2)

                    x: from ? from.x + (targetX - from.x) * p : targetX
                    y: from ? from.y + (targetY - from.y) * p : targetY
                    width: from ? from.w + (targetW - from.w) * p : targetW
                    height: from ? from.h + (targetH - from.h) * p : targetH
                    // Merge: the box is already on screen (it IS the power
                    // card), so it starts opaque. Plain lock: part of the
                    // FadeThrough run.
                    opacity: from ? 1 : lockMotion.opacity
                    scale: from ? 1 : (0.96 + 0.04 * lockMotion.opacity)
                    radius: Theme.cornerRadius
                    antialiasing: Theme.shapesAa
                    color: Theme.panelWindowBg
                    border.color: lockScope.failed ? Theme.errorColor : Theme.panelBorderColor
                    border.width: 2

                    // Settled-state resizes (error line appearing, font
                    // scale) glide; during the merge the phase drives the
                    // geometry directly.
                    Behavior on height {
                        enabled: lockScope.mergePhase >= 1 && Theme.animationsEnabled
                        NumberAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                    }

                    // Drop shadow for depth over the blurred wallpaper.
                    layer.enabled: lockScope.locked
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.withAlpha(Theme.scrim, 0.45)
                        shadowBlur: 0.8
                        shadowOpacity: 0.4
                        shadowVerticalOffset: 8
                    }

                    property real shakeOffset: 0
                    transform: Translate { x: lockCard.shakeOffset }
                    // Denied PIN: short standard-easing shake (collapses when
                    // animations are off).
                    readonly property int shakeStep: Theme.animationsEnabled ? 60 : 0
                    Connections {
                        target: lockScope
                        function onFailedChanged() { if (lockScope.failed) shakeAnim.restart() }
                    }
                    SequentialAnimation {
                        id: shakeAnim
                        NumberAnimation { target: lockCard; property: "shakeOffset"; to: -12; duration: lockCard.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandardAccel }
                        NumberAnimation { target: lockCard; property: "shakeOffset"; to: 10; duration: lockCard.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandard }
                        NumberAnimation { target: lockCard; property: "shakeOffset"; to: -6; duration: lockCard.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandard }
                        NumberAnimation { target: lockCard; property: "shakeOffset"; to: 4; duration: lockCard.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandard }
                        NumberAnimation { target: lockCard; property: "shakeOffset"; to: 0; duration: lockCard.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandardDecel }
                    }

                    // Power-menu merge replica: same grid/geometry as the
                    // power card, fades out while the lock content fades in.
                    GridLayout {
                        id: powerReplica
                        anchors.centerIn: parent
                        width: lockCard.powerContentW
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 16
                        visible: lockCard.from !== null && lockCard.p < 0.999
                        opacity: lockCard.from ? Math.max(0, 1 - lockCard.p / 0.55) : 0
                        scale: 1 - 0.04 * lockCard.p

                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            interactive: false
                            glyph: "󰌾"
                            label: "Lock"
                        }
                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            interactive: false
                            glyph: "󰍃"
                            label: "Logout"
                        }
                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            interactive: false
                            glyph: "󰜉"
                            label: "Restart"
                        }
                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            interactive: false
                            glyph: "󰐥"
                            label: "Shutdown"
                            hoverColor: Theme.error
                            hoverContentColor: Theme.on_error
                        }
                    }

                    // Settled content: stacked clock, date, PIN box, hints.
                    ColumnLayout {
                        id: lockCol
                        anchors.centerIn: parent
                        width: lockCard.targetW - 56
                        spacing: 16
                        opacity: lockCard.from ? Math.max(0, (lockCard.p - 0.35) / 0.65) : lockMotion.opacity

                        // iOS-style stacked clock: rounded variable-font
                        // digits (Google Sans Flex, ROND axis), hours over
                        // minutes with tight leading.
                        Column {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: -Math.round(lockScope.clockFontSize * 0.26)
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(lockClock.date, "HH")
                                color: Theme.textPrimary
                                font.family: "Google Sans Flex"
                                font.pixelSize: lockScope.clockFontSize
                                font.weight: Font.Light
                                font.variableAxes: ({ "ROND": 100, "wght": 300 })
                                font.letterSpacing: -lockScope.clockFontSize * 0.02
                                horizontalAlignment: Text.AlignHCenter
                                opacity: 0.97
                            }
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(lockClock.date, "mm")
                                color: Theme.textPrimary
                                font.family: "Google Sans Flex"
                                font.pixelSize: lockScope.clockFontSize
                                font.weight: Font.Light
                                font.variableAxes: ({ "ROND": 100, "wght": 300 })
                                font.letterSpacing: -lockScope.clockFontSize * 0.02
                                horizontalAlignment: Text.AlignHCenter
                                opacity: 0.97
                            }
                        }
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            Layout.alignment: Qt.AlignHCenter
                            text: lockClock.date.toLocaleDateString(I18n.formatLocale, I18n.weekdayMonthDayFormat)
                            color: Theme.textPrimary
                            font.family: "Google Sans Flex"
                            font.pixelSize: Theme.fs(17)
                            font.weight: Font.DemiBold
                            opacity: 0.9
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            antialiasing: Theme.shapesAa
                            id: pinBox
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 360
                            Layout.preferredHeight: 60
                            Layout.topMargin: 4
                            radius: Theme.cornerRadius
                            color: lockScope.failed ? Theme.withAlpha(Theme.error, 0.18) : Theme.withAlpha(Theme.surface2, 0.62)
                            border.color: lockScope.failed ? Theme.errorColor : (pinField.activeFocus ? Theme.primary : Theme.withAlpha(Theme.outline, 0.22))
                            border.width: lockScope.failed || pinField.activeFocus ? 1.6 : 1
                            Row {
                                id: dotRow
                                anchors.centerIn: parent
                                spacing: 14
                                visible: lockScope.pinInput.length > 0
                                // PERF: fixed 12 dots (was model: pinInput.length,
                                // creating/destroying delegates per keystroke).
                                Repeater {
                                    model: 12
                                    delegate: Rectangle {
                                        required property int index
                                        width: 12; height: 12; radius: Theme.cornerRadiusSmall
                                        color: lockScope.failed ? Theme.errorColor : Theme.textPrimary
                                        opacity: 0.95
                                        visible: index < lockScope.pinInput.length
                                    }
                                }
                            }
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                anchors.centerIn: parent
                                visible: lockScope.pinInput.length === 0
                                text: lockScope.failed ? lockScope.errorText : "Enter PIN  •  Enter"
                                color: lockScope.failed ? Theme.errorColor : Theme.withAlpha(Theme.textPrimary, 0.62)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(13)
                                font.weight: Font.Medium
                                font.letterSpacing: 0.4
                                horizontalAlignment: Text.AlignHCenter
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: pinField.forceActiveFocus() }
                        }
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            Layout.alignment: Qt.AlignHCenter
                            visible: lockScope.failed
                            text: lockScope.errorText
                            color: Theme.errorColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.Medium
                            opacity: 0.95
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            Layout.alignment: Qt.AlignHCenter
                            visible: !lockScope.failed && lockScope.pinInput.length === 0
                            text: "Unlock with PIN or system password"
                            color: Theme.withAlpha(Theme.textPrimary, 0.42)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.letterSpacing: 0.2
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                TextInput {
                    id: pinField
                    anchors.fill: parent
                    visible: false
                    focus: lockScope.locked && Theme.isPrimaryScreen(modelData)
                    activeFocusOnTab: Theme.isPrimaryScreen(modelData)
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    text: lockScope.pinInput
                    onTextChanged: if (text !== lockScope.pinInput) lockScope.pinInput = text
                    Connections {
                        target: lockScope
                        function onPinInputChanged() { if (pinField.text !== lockScope.pinInput) pinField.text = lockScope.pinInput }
                    }
                    onAccepted: lockScope.submitPin()
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            lockScope.pinInput = ""
                            pinField.text = ""
                            event.accepted = true
                        }
                    }
                }
                MouseArea { anchors.fill: parent; enabled: lockScope.locked; onClicked: pinField.forceActiveFocus() }
                onVisibleChanged: if (visible) Qt.callLater(() => pinField.forceActiveFocus())
                Connections {
                    target: lockScope
                    function onLockedChanged() { if (lockScope.locked) Qt.callLater(() => pinField.forceActiveFocus()) }
                }
            }
        }
    }

    IpcHandler {
        target: "lockscreen"
        function lock(): void { lockScope.lock() }
        function unlock(): void { lockScope.unlock() }
        function toggle(): void { if (lockScope.locked) lockScope.unlock(); else lockScope.lock() }
        function isLocked(): string { return lockScope.locked ? "true" : "false" }
    }
}
