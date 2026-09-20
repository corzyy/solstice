pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../style/themes"

// Debug overlay (Settings > Setup > Experimental > FPS overlay): a small
// always-on-top readout of the frame rate this shell surface achieves. A
// running FrameAnimation keeps the card's surface on the compositor frame
// clock and reports smoothFrameTime/frameTime per frame, so GUI-thread stalls
// show up as dropped frames. The Scope itself is resident like the OSDs, but
// the window renders nothing (and the ticker does not run) while the toggle
// is off. Fully input-transparent (empty Region mask) so it never eats
// clicks.
Scope {
    id: debugScope

    readonly property bool active: Theme.debugFpsEnabled
    readonly property int cornerMargin: 16

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: debugScope.active && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "debugfps"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }
            mask: Region { width: 0; height: 0 }

            // Per-frame ticker: only runs while the card is on screen.
            FrameAnimation {
                id: ticker
                running: debugScope.active
            }

            Rectangle {
                id: card
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: debugScope.cornerMargin
                    + (Theme.barPosition === "right" ? Theme.barThickness : 0)
                anchors.bottomMargin: debugScope.cornerMargin
                    + (Theme.barPosition === "bottom" ? Theme.barThickness : 0)
                width: content.implicitWidth + 28
                height: content.implicitHeight + 20
                radius: Theme.cornerRadiusSmall
                color: Theme.panelWindowBg
                border.color: Theme.panelBorderColor
                border.width: 2
                antialiasing: Theme.shapesAa

                Column {
                    id: content
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ticker.smoothFrameTime > 0
                            ? (1.0 / ticker.smoothFrameTime).toFixed(0) : "—"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(22)
                        font.weight: Font.Medium
                        color: Theme.textPrimary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (ticker.frameTime * 1000).toFixed(1) + " ms  ·  FPS"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.textSecondary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
            }
        }
    }
}
