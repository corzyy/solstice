// StateLayer — Material-3 hover + press ripple for buttons/rows.
//
// Port of caelestia-dots/shell components/StateLayer.qml to solstice Theme:
//  - hover washes the surface at 8% (animated, DefaultEffects)
//  - press spawns an expanding radial ripple from the press point
//    (Standard curve, 2x SlowEffects ≈ 600ms, always runs to end)
//  - release fades the ripple out (SlowEffects)
// Fills its parent; drop inside any Rectangle/Item with a radius.
import QtQuick
import QtQuick.Shapes
import "../themes"

MouseArea {
    id: root

    property bool disabled: false
    property bool showHoverBackground: true
    property bool manualPressOverride: false
    property bool manualHoverOverride: false
    readonly property alias rect: base

    property bool shapeMorph: false
    property real stateOpacity: (containsMouse || manualHoverOverride) && showHoverBackground ? 0.08 : 0

    property real pressX: width / 2
    property real pressY: height / 2
    property real circleRadius: 0

    property alias color: base.color
    property real radius: 0

    readonly property real endRadius: {
        const d1 = distSq(0, 0)
        const d2 = distSq(width, 0)
        const d3 = distSq(0, height)
        const d4 = distSq(width, height)
        return (Math.sqrt(Math.max(d1, d2, d3, d4)) + (shapeMorph ? 24 : 0)) * 1.3
    }
    property real endRadiusAtPress: 0

    function distSq(x: real, y: real): real {
        return (pressX - x) * (pressX - x) + (pressY - y) * (pressY - y)
    }
    function clampR(r: real): real {
        return Math.max(0, Math.min(r, width / 2, height / 2))
    }
    function press(x: real, y: real): void {
        pressX = x
        pressY = y
        fadeAnim.complete()
        circleRadius = 0
        circle.opacity = 0.1
        rippleAnim.restart()
        endRadiusAtPress = endRadius
    }

    anchors.fill: parent
    enabled: !disabled
    cursorShape: disabled ? undefined : Qt.PointingHandCursor
    hoverEnabled: true

    onPressed: e => press(e.x, e.y)
    onPressedChanged: {
        if (!(pressed || manualPressOverride) && !rippleAnim.running && circle.opacity > 0)
            fadeAnim.start()
    }
    onManualPressOverrideChanged: {
        if (!(pressed || manualPressOverride) && circleRadius > endRadiusAtPress * 0.99 && !fadeAnim.running)
            fadeAnim.start()
    }
    onCircleRadiusChanged: {
        if (!(pressed || manualPressOverride) && circleRadius > endRadiusAtPress * 0.99 && !fadeAnim.running)
            fadeAnim.start()
    }

    // Ripple expand: Standard curve, 2x slow-effects (matches Caelestia).
    NumberAnimation {
        id: rippleAnim
        target: root
        property: "circleRadius"
        to: root.endRadius
        duration: Theme.durSlowEffects * 2
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveStandard
    }
    NumberAnimation {
        id: fadeAnim
        target: circle
        property: "opacity"
        to: 0
        duration: Theme.durSlowEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveSlowEffects
    }

    Rectangle {
        id: base
        anchors.fill: parent
        radius: root.radius
        opacity: root.stateOpacity
        color: Theme.textPrimary
    }

    Shape {
        id: circle
        anchors.fill: parent
        opacity: 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: base.color
            fillGradient: RadialGradient {
                centerX: root.pressX
                centerY: root.pressY
                centerRadius: Math.max(1, root.circleRadius)
                focalX: centerX
                focalY: centerY
                GradientStop {
                    position: 0
                    color: Qt.alpha(base.color, 1)
                }
                GradientStop {
                    position: Math.max(0.01, Math.min(0.99, 1 - 0.2 * root.endRadius / Math.max(1, root.circleRadius)))
                    color: Qt.alpha(base.color, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(base.color, Math.max(0, Math.min(1, (root.circleRadius / Math.max(1, root.endRadius) - 0.9) / 0.1)))
                }
            }

            startX: root.clampR(root.radius)
            startY: 0
            PathLine { x: root.width - root.clampR(root.radius); y: 0 }
            PathArc {
                relativeX: root.clampR(root.radius)
                relativeY: root.clampR(root.radius)
                radiusX: root.clampR(root.radius)
                radiusY: root.clampR(root.radius)
            }
            PathLine { x: root.width; y: root.height - root.clampR(root.radius) }
            PathArc {
                relativeX: -root.clampR(root.radius)
                relativeY: root.clampR(root.radius)
                radiusX: root.clampR(root.radius)
                radiusY: root.clampR(root.radius)
            }
            PathLine { x: root.clampR(root.radius); y: root.height }
            PathArc {
                relativeX: -root.clampR(root.radius)
                relativeY: -root.clampR(root.radius)
                radiusX: root.clampR(root.radius)
                radiusY: root.clampR(root.radius)
            }
            PathLine { x: 0; y: root.clampR(root.radius) }
            PathArc {
                x: root.clampR(root.radius)
                y: 0
                radiusX: root.clampR(root.radius)
                radiusY: root.clampR(root.radius)
            }
        }
    }

    Behavior on stateOpacity {
        enabled: Theme.animationsEnabled
        NumberAnimation {
            duration: Theme.durDefaultEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveDefaultEffects
        }
    }
}
