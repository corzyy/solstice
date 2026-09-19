// PowerAction — session-action button shared by the power menu
// (panels/PowerPanel.qml) and the lockscreen's merge replica
// (overlays/Lockscreen.qml).
//
// Idle: round MaterialShape background with a glyph, label underneath.
// Hover (interactive only): the circle morphs into a random M3 expressive
// shape from a fixed pool and the palette swaps to the accent; actions can
// pin their own pair (Shutdown hovers the always-red error colors).
// `interactive: false` renders the same visual without input handling, used
// while the lockscreen morphs the power grid into the clock+PIN box.
import QtQuick
import M3Shapes
import "../themes"

Item {
    id: action

    required property string glyph
    required property string label
    property color idleColor: Theme.withAlpha(Theme.on_surface, 0.08)
    property color idleContentColor: Theme.textPrimary
    property color hoverColor: Theme.primary
    property color hoverContentColor: Theme.onAccent
    property bool interactive: true
    property int hoverShape: MaterialShape.Oval
    readonly property int circleSize: 112
    readonly property bool hovered: action.interactive && pressArea.containsMouse

    signal triggered()

    implicitWidth: 152
    implicitHeight: 142
    activeFocusOnTab: action.interactive

    function activate(): void {
        if (action.interactive) action.triggered()
    }
    onHoveredChanged: if (hovered) action.pickShape()

    // M3 expressive shape pool for the hover morph. Circle is not in the
    // pool: it is the idle shape, so a pick landing on it would read as no
    // shape at all.
    readonly property var shapeChoices: [
        MaterialShape.Square, MaterialShape.Slanted, MaterialShape.Pill,
        MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny,
        MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
        MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided,
        MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf,
        MaterialShape.Clover8Leaf
    ]
    // Random hover shape, never the same pick twice in a row.
    function pickShape(): void {
        const list = action.shapeChoices
        if (list.length === 0) return
        let next = list[Math.floor(Math.random() * list.length)]
        if (list.length > 1 && next === action.hoverShape)
            next = list[(list.indexOf(next) + 1) % list.length]
        action.hoverShape = next
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            action.activate()
            event.accepted = true
        }
    }

    MaterialShape {
        id: circle

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: action.circleSize
        height: action.circleSize
        implicitSize: action.circleSize
        color: action.hovered ? action.hoverColor : action.idleColor
        // Idle circle <-> random expressive shape on hover; M3Shapes
        // morphs the swap itself on the shared spatial curve.
        shape: action.hovered ? action.hoverShape : MaterialShape.Circle
        animationDuration: Theme.durDefaultSpatial
        animationEasing.type: Easing.BezierSpline
        animationEasing.bezierCurve: Theme.curveDefaultSpatial
        strokeWidth: action.activeFocus ? 2 : 0
        strokeColor: Theme.primary
        scale: pressArea.pressed ? Theme.pressScale : (action.hovered ? 1.03 : 1.0)
        transformOrigin: Item.Center

        Behavior on color {
            enabled: Theme.animationsEnabled
            ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
        }
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }

        Text {
            anchors.centerIn: parent
            text: action.glyph
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(38)
            color: action.hovered ? action.hoverContentColor : action.idleContentColor
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType

            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
        }

        StateLayer {
            id: pressArea
            anchors.fill: parent
            radius: Math.round(action.circleSize / 2)
            color: action.hoverContentColor
            disabled: !action.interactive
            onClicked: {
                action.forceActiveFocus()
                action.activate()
            }
        }
    }

    Text {
        anchors.top: circle.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        text: action.label
        color: action.activeFocus ? Theme.primary : Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(13)
        font.weight: Font.Medium
        horizontalAlignment: Text.AlignHCenter
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
