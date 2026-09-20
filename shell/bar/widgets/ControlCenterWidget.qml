import QtQuick
import QtQuick.Layouts
import "../../themes"
import "../../services"

Item {
    id: root
    signal clicked()
    property bool vertical: false
    property bool slotHovered: false

    // Network/bluetooth/dnd icons are hidden while inactive; the volume icon
    // is always shown (its glyph already encodes level/mute). The tint only
    // distinguishes hover.
    readonly property color _netFg: slotHovered ? Theme.accent : Theme.textPrimary
    readonly property color _btFg: slotHovered ? Theme.accent : Theme.textPrimary
    readonly property color _volFg: slotHovered ? Theme.accent : Theme.textPrimary
    readonly property color _dndFg: Theme.textPrimary

    implicitWidth: vertical ? colRow.implicitWidth + 12 : rowRow.implicitWidth + 16
    implicitHeight: vertical ? colRow.implicitHeight + 10 : rowRow.implicitHeight + 10

    Item {
        id: contentScale
        anchors.centerIn: parent
        width: Math.max(rowRow.implicitWidth, colRow.implicitWidth)
        height: Math.max(rowRow.implicitHeight, colRow.implicitHeight)
        scale: root.slotHovered ? Theme.hoverScale : 1
        transformOrigin: Item.Center
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }

        RowLayout {
            id: rowRow
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: 7
            StatusIcon { glyph: NetworkService.icon; tint: root._netFg; visible: NetworkService.netActive }
            StatusIcon { glyph: BluetoothService.icon; tint: root._btFg; visible: BluetoothService.btActive }
            StatusIcon { glyph: VolumeService.icon; tint: root._volFg }
            StatusIcon { glyph: "󰂛"; tint: root._dndFg; visible: Theme.dndEnabled }
        }
        ColumnLayout {
            id: colRow
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 3
            StatusIcon { glyph: NetworkService.icon; tint: root._netFg; visible: NetworkService.netActive }
            StatusIcon { glyph: BluetoothService.icon; tint: root._btFg; visible: BluetoothService.btActive }
            StatusIcon { glyph: VolumeService.icon; tint: root._volFg }
            StatusIcon { glyph: "󰂛"; tint: root._dndFg; visible: Theme.dndEnabled }
        }
    }

    component StatusIcon: Text {
        required property string glyph
        required property color tint
        text: glyph
        color: tint
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        font.family: Theme.iconFontFamily
        font.pixelSize: Theme.fs(14)
        Layout.alignment: Qt.AlignVCenter
        Behavior on color {
            enabled: Theme.animationsEnabled
            ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
        }
    }

}
