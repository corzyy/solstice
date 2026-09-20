pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

// Minimal square scroll indicator for menu Flickables (0px design language).
// Overlays the flickable's right edge; only visible when content overflows.
// Usage: ScrollIndicator { flick: someFlickable } — anchors itself to the
// flickable, so it can sit anywhere outside layouts (never inside one).
Item {
    id: root
    required property Flickable flick
    property bool show: true
    anchors.top: flick.top
    anchors.bottom: flick.bottom
    anchors.right: flick.right
    width: 2
    visible: show && flick.visibleArea.heightRatio < 1 - 0.001
    Rectangle {
        width: 2
        y: root.flick.visibleArea.yPosition * root.height
        height: Math.min(root.height, Math.max(24, root.flick.visibleArea.heightRatio * root.height))
        color: Theme.withAlpha(Theme.textPrimary, 0.28)
    }
}
