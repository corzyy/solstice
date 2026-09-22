pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

// EdgeFade — dark gradient caps at the top/bottom (and left/right) of a
// scrollable list, so cut-off rows dissolve into the panel instead of
// clipping hard. A cheaper, theme-aware alternative to a masked layer +
// shader: four overlay gradients that only show while there is more content
// in that direction.
//
// Usage (sibling of the flickable, never inside a layout — same contract as
// ScrollIndicator, which anchors itself to the flickable):
//   ListView { id: appList; ... }
//   EdgeFade { flick: appList }
//   ScrollIndicator { flick: appList }
//
// `fadeColor` must match the surface behind the list (the card fill), so the
// rows fade into the background. Defaults to the panel window fill; inner
// cards (panelCard, cardBg, ...) override it at the call site.
Item {
    id: root

    required property Flickable flick
    property color fadeColor: Theme.panelWindowBg
    property real fadeSize: 28
    property bool fadeTop: true
    property bool fadeBottom: true
    property bool fadeLeft: true
    property bool fadeRight: true

    anchors.top: flick.top
    anchors.bottom: flick.bottom
    anchors.left: flick.left
    anchors.right: flick.right
    // No z: declaration order decides stacking. Declare the fade after the
    // list (so rows dissolve under it) and before the ScrollIndicator (so
    // the indicator stays on top).
    // Overlay only: never steal clicks/wheel from the list underneath.
    enabled: false

    readonly property color _clear: Qt.rgba(fadeColor.r, fadeColor.g, fadeColor.b, 0)
    readonly property bool _canV: flick.contentHeight > flick.height + 1
    readonly property bool _canH: flick.contentWidth > flick.width + 1
    readonly property bool _showTop: fadeTop && _canV && flick.contentY > 1
    readonly property bool _showBottom: fadeBottom && _canV && flick.contentY < flick.contentHeight - flick.height - 1
    readonly property bool _showLeft: fadeLeft && _canH && flick.contentX > 1
    readonly property bool _showRight: fadeRight && _canH && flick.contentX < flick.contentWidth - flick.width - 1

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(root.fadeSize, root.height / 2)
        opacity: root._showTop ? 1 : 0
        visible: opacity > 0.01
        gradient: Gradient {
            GradientStop { position: 0; color: root.fadeColor }
            GradientStop { position: 1; color: root._clear }
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(root.fadeSize, root.height / 2)
        opacity: root._showBottom ? 1 : 0
        visible: opacity > 0.01
        gradient: Gradient {
            GradientStop { position: 0; color: root._clear }
            GradientStop { position: 1; color: root.fadeColor }
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(root.fadeSize, root.width / 2)
        opacity: root._showLeft ? 1 : 0
        visible: opacity > 0.01
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.fadeColor }
            GradientStop { position: 1; color: root._clear }
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(root.fadeSize, root.width / 2)
        opacity: root._showRight ? 1 : 0
        visible: opacity > 0.01
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root._clear }
            GradientStop { position: 1; color: root.fadeColor }
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
        }
    }
}
