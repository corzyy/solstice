pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

// CarouselCard — reusable ListView delegate shell for centered carousels
// (wallpaper pickers, recent rows, any cover-flow list).
//
// Ports the scrolling effect from the wallpaper-carousel prototype:
//  - width steps with the distance to the current index (focused /
//    neighbour / distant, see CarouselEffect.widthForOffset), animated on
//    the standard curve over Theme.durLarge (the prototype's 600ms);
//  - centerNorm tracks the card centre against the viewport centre in
//    [-1, 1] every frame while scrolling — feed it into
//    CarouselParallaxImage for the parallax pan.
//
// Usage (any ListView with StrictlyEnforceRange + a centred highlight):
//   delegate: Ui.CarouselCard {
//       id: card
//       view: myListView
//       focusedWidth: 356; neighbourWidth: 200; distantWidth: 113
//       cardHeight: 200; centerRange: 286
//       Ui.ClipRect {
//           anchors.fill: parent
//           radius: 20
//           Ui.CarouselParallaxImage {
//               height: parent.height
//               fullWidth: 356 + 2 * 71
//               parallaxPad: 71
//               centerNorm: card.centerNorm
//               source: ...
//           }
//       }
//   }
Item {
    id: root

    required property ListView view
    required property int index
    // Auto-filled from the delegate context for array/number models (same
    // convention as every other delegate in the shell). Consumers read it
    // back via the card id (card.modelData).
    required property var modelData

    // Prototype geometry: 356 focused (16:9), 200 neighbour (1:1),
    // 113 distant (9:16) at height 200, centre travel 286px -> ±1.
    property real focusedWidth: 356
    property real neighbourWidth: 200
    property real distantWidth: 113
    property real cardHeight: 200
    property real centerRange: 286

    readonly property bool isCurrent: ListView.isCurrentItem
    readonly property int indexOffset: index - view.currentIndex
    readonly property real centerNorm: centerRange > 0
        ? Math.max(-1, Math.min(1, (x - view.contentX + width / 2 - view.width / 2) / centerRange))
        : 0

    width: indexOffset === 0 ? focusedWidth : (indexOffset === 1 || indexOffset === -1) ? neighbourWidth : distantWidth
    height: cardHeight
    z: isCurrent ? 2 : 1

    Behavior on width {
        enabled: Theme.animationsEnabled
        NumberAnimation {
            duration: Theme.durLarge
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveStandard
        }
    }
}
