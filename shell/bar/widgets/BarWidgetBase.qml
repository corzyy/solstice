// BarWidgetBase — shared shell for all single-icon bar widgets.
// DRY: 10/12 bar widgets duplicated this exact block (hover scale, dual
// Row/Column layouts, mouse handling). Centralizing it removes ~400 lines
// and guarantees consistent padding/behavior. It also avoids the old
// pattern of instantiating BOTH Row and Column trees: only the active
// orientation's content slot is loaded via Loader.
//
// LABEL-TOGGLE CONVENTION (future-proof):
// Any widget with a text label next to its icon gets right-click label
// toggling for free by defining:
//   function toggleLabel(): void { ... }
// BarModule.click() calls toggleLabel() on right-click when present (checked
// via duck-typing), and this base MouseArea does the same for standalone
// use. New modules: bind label visibility to a setting, add toggleLabel(),
// no BarModule changes needed. Icon-only widgets simply omit toggleLabel()
// and right-click falls through to rightClicked()/legacy actions.
import QtQuick
import QtQuick.Layouts
import "../../../style/themes"

Item {
    id: root
    signal clicked()
    signal rightClicked()
    signal middleClicked()

    // Content providers supply one component each; only the active one loads.
    property Component rowContent
    property Component colContent
    property bool vertical: false
    // Padding convention: horizontal +16/+10, vertical +12/+10.
    property int hPad: 16
    property int vPad: 12
    property int rowPadV: 10

    implicitWidth: (vertical ? colLoader.implicitWidth + vPad : rowLoader.implicitWidth + hPad)
    implicitHeight: (vertical ? colLoader.implicitHeight + rowPadV : rowLoader.implicitHeight + rowPadV)

    // CPU: scale animation only; no implicitWidth Behavior here (the old
    // per-widget `Behavior on implicitWidth` re-animated the whole bar on
    // every temp/volume string change — layout thrash).

    // Caelestia button feel: content breathes on hover, squashes on press.
    // Scale lives on a wrapper so Loader layout (implicitWidth/Height) never
    // animates — only the painted content does (no bar layout thrash).
    Item {
        id: contentScale
        anchors.centerIn: parent
        width: Math.max(rowLoader.implicitWidth, colLoader.implicitWidth)
        height: Math.max(rowLoader.implicitHeight, colLoader.implicitHeight)
        scale: mouse.pressed ? Theme.pressScale : mouse.containsMouse ? Theme.hoverScale : 1
        transformOrigin: Item.Center
        Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
    }

    Loader {
        id: rowLoader
        anchors.centerIn: contentScale
        active: !root.vertical && root.rowContent !== null
        asynchronous: false
        sourceComponent: root.rowContent
    }
    Loader {
        id: colLoader
        anchors.centerIn: contentScale
        active: root.vertical && root.colContent !== null
        asynchronous: false
        sourceComponent: root.colContent
    }

    // Exposed so icon delegates can tint on hover without adding their own
    // MouseArea (one hover listener per widget, not two).
    readonly property bool hovered: mouse.containsMouse

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: m => {
            if (m.button === Qt.RightButton) {
                // Future-proof: label-capable widgets define toggleLabel().
                try {
                    if (typeof root.toggleLabel === "function") { root.toggleLabel(); return }
                } catch (e) {}
                root.rightClicked()
            } else if (m.button === Qt.MiddleButton) root.middleClicked()
            else root.clicked()
        }
    }
}
