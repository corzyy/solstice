pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../style/themes"
import "../../backend/services"
import "../../style/ui"

Scope {
    id: scope
    property bool showUpdates: false
    signal dismissed()
    // CC drill-in mode: the view leads with a back header and the card
    // settles under the control-center anchor, growing out of / shrinking
    // back into the clicked updates tile via the container transform
    // (shell.qml updatesmenu panel). The standalone bar panel keeps the
    // close button.
    property bool showBack: false
    signal backRequested()
    property string panelModuleId: "updates"
    property string anchorModuleId: "updates"
    property bool _winVisible: showUpdates
    Timer { id: hideTimer; interval: Theme.panelHideDelay; repeat: false; onTriggered: if (!scope.showUpdates) scope._winVisible = false }
    onShowUpdatesChanged: {
        if (showUpdates) { _winVisible = true; hideTimer.stop() } else hideTimer.restart()
    }
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)

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
            WlrLayershell.namespace: "updatecenter"
            // Hyprland: OnDemand + focus grab (see HyprlandService) so the
            // taskbar stays clickable while the panel is open.
            WlrLayershell.keyboardFocus: HyprlandService.isHyprland ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
            Component.onCompleted: HyprlandService.registerPanelWindow(this)
            Component.onDestruction: HyprlandService.unregisterPanelWindow(this)
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { scope.dismissed(); event.accepted = true }
                }
                Component.onCompleted: forceActiveFocus()
            }
            // Disabled while the panel is closing: during a morph handoff
            // the outgoing window stays mapped for panelHideDelay and must
            // not eat the click that belongs to the panel now on top.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                enabled: scope.showUpdates
                onClicked: scope.dismissed()
            }
            PanelShell {
                moduleId: scope.panelModuleId
                anchorModuleId: scope.anchorModuleId
                // Container transform: the tile replica glides into the view
                // header while the card grows out of the tile.
                morphTarget: updateView.headerItem
                // Drill-in mode settles below the CC header/tile row: the CC
                // stays open and dimmed behind this card.
                edgeInset: scope.showBack ? Theme.panelDrillInInset : 0
                screenActive: Theme.isPrimaryScreen(modelData)
                panelGap: scope.panelGap
                shown: scope.showUpdates
                boxWidth: scope.showBack ? 360 : 410
                contentMargins: scope.showBack ? 12 : 16
                contentSpacing: 12
                heightPadding: 32

                UpdateCenterView {
                    id: updateView
                    active: scope.showUpdates
                    showBack: scope.showBack
                    onCloseRequested: scope.dismissed()
                    onBackRequested: scope.backRequested()
                }
            }
        }
    }
}
