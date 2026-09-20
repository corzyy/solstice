// PanelKit — design primitives shared by the bar panels (Network, Volume),
// the control-center audio menu and BluetoothPanel. Each was
// previously copy-pasted per panel; this is the single source of truth.
import QtQuick
import QtQuick.Layouts
import "../themes"

QtObject {
    id: __panelKit

    // Small uppercase group label above a section ("CONNECTED", "WI-FI", …).
    component SectionLabel: Text {
        // Bar widgets use the icon font + no tracking for the same look.
        property bool iconFont: false
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        color: Theme.textSecondary
        font.family: iconFont ? Theme.iconFontFamily : Theme.fontFamily
        font.pixelSize: Theme.fs(10)
        font.weight: Font.Bold
        font.letterSpacing: iconFont ? 0 : 1.2
    }

    // Rounded card surface.
    component Card: Rectangle {
        antialiasing: Theme.shapesAa
        radius: Theme.cornerRadiusSmall
        color: Theme.cardBg
        border.color: Theme.divider
        border.width: 1
    }

    // 28x28 bordered icon button with hover accent tint + press ripple.
    component IconButton: Rectangle {
        id: button
        required property string glyph
        property bool active: false
        signal clicked()
        width: 28; height: 28
        radius: Theme.cornerRadiusSmall
        antialiasing: Theme.shapesAa
        color: "transparent"
        border.color: (button.active || layer.containsMouse) ? Theme.divider : "transparent"
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: (button.active || layer.containsMouse) ? Theme.accent : Theme.textSecondary
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(13)
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        StateLayer {
            id: layer
            radius: Theme.cornerRadiusSmall
            color: Theme.accent
            onClicked: button.clicked()
        }
    }

    // Pill toggle (Wi-Fi, mute). `offColor` drives the inactive palette.
    component TogglePill: Rectangle {
        id: pill
        required property bool on
        property string onText: ""
        property string offText: ""
        property color onColor: Theme.accent
        property color offColor: Theme.textPrimary
        property color onTextColor: Theme.textPrimary
        property color offTextColor: Theme.textSecondary
        property color offBorderColor: offColor
        signal clicked()
        implicitWidth: pillLabel.implicitWidth + 24
        implicitHeight: 26
        radius: height / 2
        antialiasing: Theme.shapesAa
        color: pill.on ? Theme.withAlpha(pill.onColor, 0.16) : Theme.withAlpha(pill.offColor, 0.16)
        border.color: pill.on ? pill.onColor : pill.offBorderColor
        border.width: 1
        Text {
            id: pillLabel
            anchors.centerIn: parent
            text: pill.on ? pill.onText : pill.offText
            color: pill.on ? pill.onTextColor : pill.offTextColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(10)
            font.weight: Font.Bold
            font.letterSpacing: 0.6
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        StateLayer {
            radius: Math.round(height / 2)
            color: pill.on ? pill.onColor : pill.offColor
            onClicked: pill.clicked()
        }
    }

    // Back affordance for drill-in panels: chevron button that returns to
    // the parent panel (the host runs the reverse morph handoff).
    component BackButton: Item {
        id: backButton
        property int glyphSize: 22
        signal clicked()
        implicitWidth: 42
        implicitHeight: 42

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadiusSmall
            antialiasing: Theme.shapesAa
            color: "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰅃"
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(backButton.glyphSize)
                color: backMouse.containsMouse ? Theme.primary : Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType

                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }
        }

        StateLayer {
            id: backMouse
            radius: Theme.cornerRadiusSmall
            color: Theme.textPrimary
            onClicked: backButton.clicked()
        }
    }

    // Selectable device row: status dot, glyph, label/sub, optional mute
    // badge. Used by the network ethernet list and the volume device list.
    component DeviceRow: Rectangle {
        id: row
        required property string glyph
        required property string label
        required property bool isActive
        property string sub: ""
        property bool isMuted: false
        signal picked()
        implicitHeight: 40
        radius: Theme.cornerRadiusSmall
        antialiasing: Theme.shapesAa
        color: row.isActive ? Theme.withAlpha(Theme.accent, 0.14) : "transparent"
        border.color: row.isActive ? Theme.withAlpha(Theme.accent, 0.55) : "transparent"
        border.width: row.isActive ? 1 : 0
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 10
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 10; Layout.preferredHeight: 10
                Layout.alignment: Qt.AlignVCenter
                radius: 5
                color: row.isActive ? Theme.accent : "transparent"
                border.color: row.isActive ? Theme.accent : Theme.textMuted
                border.width: row.isActive ? 0 : 1
            }
            Text {
                text: row.glyph
                color: row.isActive ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(16)
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignVCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: row.label
                    color: row.isActive ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: row.isActive ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    visible: row.sub !== ""
                    Layout.fillWidth: true
                    text: row.sub
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Text {
                visible: row.isMuted
                text: "󰝟"
                color: Theme.errorColor
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(13)
                Layout.alignment: Qt.AlignVCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
        StateLayer {
            id: layer
            radius: Theme.cornerRadiusSmall
            color: Theme.textPrimary
            onClicked: row.picked()
        }
    }
}

