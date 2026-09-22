import QtQuick
import "../../../style/themes"
import "../../../style/ui"

Item {
    id: root

    required property string glyph
    required property string title
    property string status: ""
    property bool active: false
    property bool editing: false
    property bool selected: true
    // 1x1 layout: circle tile, icon only, no label column.
    property bool compact: false
    property int cornerRadius: Theme.cornerRadius
    property color activeColor: Theme.primary
    property color activeContentColor: Theme.on_primary
    property color inactiveColor: Theme.panelCardHigh
    property color inactiveContentColor: Theme.on_surface

    signal toggled()
    signal editToggled()

    implicitWidth: 190
    implicitHeight: 72
    activeFocusOnTab: true

    // Container-transform replica (PanelShell.morphReplica): while the tile
    // is morphed toward a page header its height leaves the tile range, and
    // the icon column scales with it so the replica lands on the header's
    // geometry (title at ~38px, icon where the back button sits) instead of
    // keeping tile-sized furniture. Real tiles (72/154 tall) keep k = 1.
    readonly property real _replicaK: Math.max(0, Math.min(1, height / 72))

    function activate(): void {
        if (editing) editToggled()
        else toggled()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activate()
            event.accepted = true
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.cornerRadius
        antialiasing: Theme.shapesAa
        color: root.active ? root.activeColor : root.inactiveColor
        opacity: root.editing && !root.selected ? 0.45 : 1.0
        border.width: root.activeFocus ? 2 : (pressArea.containsMouse ? 1 : 0)
        border.color: root.active ? Theme.withAlpha(root.activeContentColor, 0.45) : Theme.outline
        scale: pressArea.pressed ? Theme.pressScale : (pressArea.containsMouse ? 1.02 : 1.0)
        transformOrigin: Item.Center

        Behavior on color {
            enabled: Theme.animationsEnabled
            ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        }
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }
        Behavior on border.color {
            enabled: Theme.animationsEnabled
            ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
        }

        Rectangle {
            id: iconCircle
            width: root.compact ? parent.width : 40 * root._replicaK
            height: root.compact ? parent.height : 40 * root._replicaK
            radius: width / 2
            antialiasing: Theme.shapesAa
            anchors.left: parent.left
            anchors.leftMargin: root.compact ? 0 : 14 * root._replicaK
            anchors.verticalCenter: parent.verticalCenter
            color: root.compact ? "transparent" : (root.active ? Theme.withAlpha(root.activeContentColor, 0.16) : Theme.withAlpha(root.inactiveContentColor, 0.08))

            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }

            Text {
                anchors.centerIn: parent
                text: root.glyph
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(20) * (root.compact ? 1 : root._replicaK)
                color: root.active ? root.activeContentColor : root.inactiveContentColor
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType

                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }
        }

        Column {
            visible: !root.compact
            anchors.left: iconCircle.right
            anchors.leftMargin: 12 * root._replicaK
            anchors.right: parent.right
            anchors.rightMargin: root.editing ? 32 : 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.title
                color: root.active ? root.activeContentColor : root.inactiveContentColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                font.weight: Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType

                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }

            Text {
                width: parent.width
                visible: root.status.length > 0
                text: root.status
                color: root.active ? Theme.withAlpha(root.activeContentColor, 0.72) : Theme.withAlpha(root.inactiveContentColor, 0.66)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight
                maximumLineCount: 1
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType

                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }
        }

        Rectangle {
            // Edit chrome: M3 fade in/out (enter decelerate, exit accelerate).
            opacity: root.editing ? 1 : 0
            visible: opacity > 0.01
            width: 22
            height: 22
            radius: width / 2
            antialiasing: Theme.shapesAa
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            color: root.selected ? (root.active ? root.activeContentColor : root.activeColor) : "transparent"
            border.width: root.selected ? 0 : 2
            border.color: root.active ? Theme.withAlpha(root.activeContentColor, 0.5) : Theme.outline

            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
            Behavior on opacity {
                enabled: Theme.animationsEnabled
                NumberAnimation {
                    duration: root.editing ? Theme.durSlowEffects : Theme.durFastEffects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.editing ? Theme.curveEmphasizedDecelerate : Theme.curveEmphasizedAccelerate
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.selected
                text: "󰄬"
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(13)
                color: root.active ? root.activeColor : root.activeContentColor
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    StateLayer {
        id: pressArea
        radius: root.cornerRadius
        color: root.active ? root.activeContentColor : root.inactiveContentColor
        onClicked: {
            root.forceActiveFocus()
            root.activate()
        }
    }
}
