import QtQuick
import "../../../style/themes"
import "../../../style/ui"

// Round chevron button at the right end of the control center volume row.
// Extracted so the audio drill-in's container transform (PanelShell
// container transform) renders the exact same button it grew out of.
Item {
    id: root

    signal clicked()
    // False while the control center edits its layout: the button greys out
    // and ignores input.
    property bool interactive: true

    implicitWidth: 48
    implicitHeight: 48

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        antialiasing: Theme.shapesAa
        color: Theme.panelCardHighest
        scale: layer.pressed ? Theme.pressScale : 1

        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }

        Text {
            anchors.centerIn: parent
            text: "󰅀"
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(22)
            color: Theme.textPrimary
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
    }

    StateLayer {
        id: layer
        radius: Math.round(width / 2)
        color: Theme.textPrimary
        disabled: !root.interactive
        onClicked: root.clicked()
    }
}
