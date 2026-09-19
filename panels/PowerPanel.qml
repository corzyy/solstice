pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../themes"
import "../services"
import "../ui"

// Android-style power menu: a standalone full-screen modal (NOT a control
// center drill-in). The backdrop is dimmed by a scrim and blurred by the
// compositor (layer rule for the "powerpanel" namespace); the action card
// sits centred on screen. Opened from the control center power button or
// the `solstice` IPC (togglePower/showPower), closed by the backdrop, Escape,
// a session action or the IPC.
Scope {
    id: scope

    property bool showPower: false
    // Window-local rect of the open card, published here so shell.qml can
    // hand it to the lockscreen when Lock starts the merge morph.
    property var cardRect: null
    signal dismissed()
    // Lock lives in overlays/Lockscreen.qml; the host (shell.qml) raises
    // the overlay after closing the menu run.
    signal lockRequested()

    // Window lingers through the exit run so the FadeThrough fade-out stays
    // visible (same pattern as the OSD).
    property bool _winVisible: showPower
    Timer {
        id: hideTimer
        interval: Theme.durMotionFadeThrough
        repeat: false
        onTriggered: if (!scope.showPower) scope._winVisible = false
    }
    onShowPowerChanged: {
        if (showPower) {
            _winVisible = true
            hideTimer.stop()
        } else {
            hideTimer.restart()
        }
    }

    // ---- session actions ----
    // Poweroff/reboot go through systemd; logout quits the Umbriel session
    // (native path first, logind fallback so other compositors still work).
    // The menu stays mapped while an action runs: destroying the panel would
    // take its Process children with it.
    function runLogout(): void {
        if (logoutProc.running) return
        logoutProc.command = ["bash", "-c",
            "umbriel msg session-quit:skip-confirmation 2>/dev/null"
            + " || umbriel msg session-quit skip-confirmation 2>/dev/null"
            + " || loginctl terminate-session \"$XDG_SESSION_ID\""]
        logoutProc.running = true
    }
    function runRestart(): void {
        if (restartProc.running) return
        restartProc.command = ["systemctl", "reboot"]
        restartProc.running = true
    }
    function runShutdown(): void {
        if (shutdownProc.running) return
        shutdownProc.command = ["systemctl", "poweroff"]
        shutdownProc.running = true
    }

    Process { id: logoutProc; onExited: (code) => scope.reportFailure("logout", code) }
    Process { id: restartProc; onExited: (code) => scope.reportFailure("restart", code) }
    Process { id: shutdownProc; onExited: (code) => scope.reportFailure("shutdown", code) }
    function reportFailure(action: string, code: int): void {
        if (code !== 0) LogService.record("error", action + " failed (exit " + code + ")", "power")
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: scope._winVisible && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "powerpanel"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // Android power-menu run: fade + settle (FadeThrough) for the
            // card, scrim fades with it. The async PanelLoader creates the
            // delegate with showPower already true (no active change fires),
            // so a cold open replays the enter run explicitly.
            Motion {
                id: menuMotion
                active: scope.showPower
                pattern: Motion.FadeThrough
            }
            Component.onCompleted: if (scope.showPower) menuMotion.replay()

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        scope.dismissed()
                        event.accepted = true
                    }
                }
                Component.onCompleted: forceActiveFocus()

                // Dimmed backdrop. Alpha stays above the compositor rule's
                // blur_ignore_alpha so the "powerpanel" layer blur applies
                // to the whole screen behind the menu.
                Rectangle {
                    anchors.fill: parent
                    color: Theme.scrim
                    opacity: 0.5 * menuMotion.opacity
                }

                // Backdrop click dismisses (disabled while closing so the
                // lingering window cannot eat the next click).
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    enabled: scope.showPower
                    onClicked: scope.dismissed()
                }

                // Centred action card.
                Rectangle {
                    id: card

                    anchors.centerIn: parent
                    width: Math.min(400, parent.width - 48)
                    height: cardContent.implicitHeight + 56
                    // Publish the pose for the lockscreen merge (primary
                    // screen only; the lockscreen card lives there).
                    function publishRect(): void {
                        if (!Theme.isPrimaryScreen(modelData)) return
                        let p = card.mapToItem(null, 0, 0)
                        scope.cardRect = { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(card.width), h: Math.round(card.height) }
                    }
                    onXChanged: publishRect()
                    onYChanged: publishRect()
                    onWidthChanged: publishRect()
                    onHeightChanged: publishRect()
                    Component.onCompleted: publishRect()

                    radius: Theme.cornerRadius
                    antialiasing: Theme.shapesAa
                    color: Theme.panelWindowBg
                    border.color: Theme.panelBorderColor
                    border.width: 2
                    opacity: menuMotion.opacity
                    scale: menuMotion.scale
                    transformOrigin: Item.Center

                    // Drop shadow for depth over the blurred backdrop
                    // (gated on visibility, same as the lockscreen card).
                    layer.enabled: scope._winVisible
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.withAlpha(Theme.scrim, 0.45)
                        shadowBlur: 0.8
                        shadowOpacity: 0.4
                        shadowVerticalOffset: 8
                    }

                    // Swallow clicks/wheel on the card: only the action
                    // buttons react, the backdrop MouseArea stays under.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        enabled: scope.showPower
                        onClicked: mouse => mouse.accepted = true
                        onPressed: mouse => mouse.accepted = true
                        onWheel: wheel => wheel.accepted = true
                    }

                    GridLayout {
                        id: cardContent

                        anchors.fill: parent
                        anchors.margins: 28
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 16

                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            glyph: "󰌾"
                            label: "Lock"
                            onTriggered: scope.lockRequested()
                        }
                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            glyph: "󰍃"
                            label: "Logout"
                            onTriggered: scope.runLogout()
                        }
                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            glyph: "󰜉"
                            label: "Restart"
                            onTriggered: scope.runRestart()
                        }
                        PowerAction {
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            glyph: "󰐥"
                            label: "Shutdown"
                            // Hover is always red (matugen's error pair) so
                            // the destructive action reads as such.
                            hoverColor: Theme.error
                            hoverContentColor: Theme.on_error
                            onTriggered: scope.runShutdown()
                        }
                    }
                }
            }
        }
    }
}
