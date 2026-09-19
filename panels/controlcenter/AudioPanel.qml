pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../../themes"
import "../../services"
import "../../util"
import "../../ui"

// Audio drill-in of the control center. The volume block's chevron used to
// expand an accordion inside the CC card; it now opens this first-class
// panel instead. The panel shares the control-center bar anchor
// (anchorModuleId), so the cross-panel morph (ui/PanelMorph) glides the CC
// card into this one and back out of it on dismissal.
Scope {
    id: scope

    property bool showAudio: false
    signal dismissed()
    // Back button: morph into the control center (shell.qml reopens it;
    // beginPanelMorph turns the switch into the reverse handoff).
    signal backRequested()

    property bool _winVisible: showAudio
    Timer {
        id: hideTimer
        interval: Theme.panelHideDelay
        repeat: false
        onTriggered: if (!scope.showAudio) scope._winVisible = false
    }
    onShowAudioChanged: {
        if (showAudio) {
            _winVisible = true
            hideTimer.stop()
        } else {
            hideTimer.restart()
        }
    }

    readonly property string barPos: Theme.barPosition
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)

    // ---- PipeWire device model (carried over from the old inline menu) ----
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio !== null && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio !== null && !n.isSink && !n.isStream)

    // Binding the nodes makes audio.muted/audio.volume reactive (see
    // VolumeService for the unbind/ready caveat).
    PwObjectTracker { objects: scope.sinks.concat(scope.sources) }

    function defaultSinkId(): int {
        let d = Pipewire.defaultAudioSink
        return d !== null ? d.id : -1
    }
    function defaultSourceId(): int {
        let d = Pipewire.defaultAudioSource
        return d !== null ? d.id : -1
    }
    function deviceLabel(node: var): string {
        return Util.cleanAudioName(node.description || "", node.name || "")
    }
    function deviceVolume(node: var): int {
        try { return Math.round((node.audio.volume || 0) * 100) } catch (e) { return 0 }
    }
    function deviceMuted(node: var): bool {
        try { return node.audio.muted === true } catch (e) { return false }
    }
    function deviceGlyph(node: var): string {
        if (!node.isSink) return "󰍬"
        let d = ((node.description || "") + " " + (node.name || "")).toLowerCase()
        if (d.indexOf("headphone") !== -1 || d.indexOf("headset") !== -1 || d.indexOf("kopfhörer") !== -1) return "󰋋"
        if (d.indexOf("hdmi") !== -1 || d.indexOf("displayport") !== -1) return "󰍹"
        if (d.indexOf("bluetooth") !== -1 || d.indexOf("bluez") !== -1) return "󰂯"
        if (d.indexOf("usb") !== -1) return "󰓃"
        return "󰕾"
    }
    function pick(node: var): void {
        try {
            if (node.isSink) Pipewire.preferredDefaultAudioSink = node
            else Pipewire.preferredDefaultAudioSource = node
        } catch (e) {}
    }

    // Back into the control center: the card morphs back into the CC pose.
    component EmptyLabel: Text {
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(11)
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }

    component DeviceRow: Rectangle {
        id: row

        required property var node
        required property bool isActive
        signal picked()

        implicitHeight: 40
        radius: Theme.cornerRadiusSmall
        antialiasing: Theme.shapesAa
        color: row.isActive ? Theme.withAlpha(Theme.primary, 0.14) : "transparent"
        border.width: row.isActive ? 1 : 0
        border.color: Theme.withAlpha(Theme.primary, 0.55)

        Behavior on color {
            enabled: Theme.animationsEnabled
            ColorAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                Layout.alignment: Qt.AlignVCenter
                radius: 5
                antialiasing: Theme.shapesAa
                color: row.isActive ? Theme.primary : "transparent"
                border.color: row.isActive ? Theme.primary : Theme.textMuted
                border.width: row.isActive ? 0 : 1
            }
            Text {
                text: scope.deviceGlyph(row.node)
                color: row.isActive ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(16)
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignVCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: scope.deviceLabel(row.node)
                color: row.isActive ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: row.isActive ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                maximumLineCount: 1
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                visible: scope.deviceMuted(row.node)
                text: "󰝟"
                color: Theme.errorColor
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(13)
                Layout.alignment: Qt.AlignVCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                text: scope.deviceVolume(row.node) + "%"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignVCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }

        StateLayer {
            id: rowMouse
            radius: Theme.cornerRadiusSmall
            color: Theme.textPrimary
            onClicked: row.picked()
        }
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
            WlrLayershell.namespace: "audiopanel"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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
            }

            // Disabled while the panel is closing: during a morph handoff
            // the outgoing window stays mapped for panelHideDelay and must
            // not eat the click that belongs to the panel now on top.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                enabled: scope.showAudio
                onClicked: scope.dismissed()
            }

            PanelShell {
                moduleId: "audio"
                // The audio panel settles where the control center sits, so
                // the handoff only morphs the frame between the two card
                // heights (horizontal offset/size stay identical).
                anchorModuleId: "controlcenter"
                // Settles below the CC header/tile row: the CC stays open
                // and dimmed behind this card (Android-QS drill-in).
                edgeInset: Theme.panelDrillInInset
                screenActive: Theme.isPrimaryScreen(modelData)
                barPos: scope.barPos
                panelGap: scope.panelGap
                shown: scope.showAudio
                boxWidth: 360
                contentSpacing: 12

                // Header: back into the control center + master state.
                RowLayout {
                    width: parent.width
                    spacing: 6

                    PanelKit.BackButton {
                        onClicked: scope.backRequested()
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: "Audio"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.Bold
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: VolumeService.isMuted ? "Stumm" : VolumeService.pct + "%"
                        color: VolumeService.isMuted ? Theme.errorColor : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.Medium
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }

                // Master volume: the CC's slider, kept here so the drill-in
                // does not lose the control it morphs out of.
                CcSlider {
                    width: parent.width
                    muted: VolumeService.isMuted
                    value: Math.max(0, Math.min(1, VolumeService.pct / 100))
                    onUserMoved: v => VolumeService.setVolumeFrac(v)
                }

                // Output/input devices, same picking semantics as the old
                // inline menu.
                PanelKit.Card {
                    width: parent.width
                    implicitHeight: listCol.implicitHeight + 20

                    ColumnLayout {
                        id: listCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        PanelKit.SectionLabel { text: "AUSGABE"; visible: scope.sinks.length > 0 }
                        Repeater {
                            model: scope.sinks
                            delegate: DeviceRow {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                                isActive: scope.defaultSinkId() === modelData.id
                                onPicked: scope.pick(modelData)
                            }
                        }
                        EmptyLabel { visible: scope.sinks.length === 0; text: "Keine Ausgabegeräte" }

                        PanelKit.SectionLabel {
                            text: "EINGABE"
                            visible: scope.sources.length > 0
                            Layout.topMargin: 6
                        }
                        Repeater {
                            model: scope.sources
                            delegate: DeviceRow {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                                isActive: scope.defaultSourceId() === modelData.id
                                onPicked: scope.pick(modelData)
                            }
                        }
                        EmptyLabel { visible: scope.sources.length === 0; text: "Keine Eingabegeräte" }
                    }
                }
            }
        }
    }
}
