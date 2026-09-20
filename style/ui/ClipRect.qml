pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

// ClipRect — local rounded-corner clipping rectangle.
//
// Copy of Quickshell.Widgets.ClippingRectangle with one change: the default
// property alias is named `content` instead of `data`. Upstream aliases
// `data`, which overrides Item.data and makes Qt print
//   "Member data of the object ClippingRectangle ... overrides a member of
//    the base object"
// for every generation that instantiates it. The implementation (hidden
// Rectangle + ShaderEffectSource + the upstream clip shader) is unchanged.
Item {
    id: root

    /// If content should be displayed underneath the border.
    ///
    /// Defaults to false, does nothing if the border is opaque.
    property bool contentUnderBorder: false
    /// If the content item should be resized to fit inside the border.
    ///
    /// Defaults to `!contentUnderBorder`.
    property bool contentInsideBorder: !root.contentUnderBorder
    /// If the rectangle should be antialiased.
    property alias antialiasing: rectangle.antialiasing
    /// The background color of the rectangle, which goes under its content.
    property alias color: shader.backgroundColor
    /// See QtQuick.Rectangle.border.
    property clippingRectangleBorder border
    /// Radius of all corners. Defaults to 0.
    property alias radius: rectangle.radius
    /// Radius of the top left corner. Defaults to @@radius.
    property alias topLeftRadius: rectangle.topLeftRadius
    /// Radius of the top right corner. Defaults to @@radius.
    property alias topRightRadius: rectangle.topRightRadius
    /// Radius of the bottom left corner. Defaults to @@radius.
    property alias bottomLeftRadius: rectangle.bottomLeftRadius
    /// Radius of the bottom right corner. Defaults to @@radius.
    property alias bottomRightRadius: rectangle.bottomRightRadius

    /// Visual children. Equivalent to upstream ClippingRectangle's `data`.
    default property alias content: contentItem.data
    /// The item containing the rectangle's content.
    readonly property alias contentItem: contentItem

    Rectangle {
        id: rectangle
        anchors.fill: root
        color: "#ffff0000"
        border.color: "#ff00ff00"
        border.pixelAligned: root.border.pixelAligned
        border.width: root.border.width
        layer.enabled: true
        visible: false
    }

    Item {
        id: contentItemContainer
        anchors.fill: root

        Item {
            id: contentItem
            anchors.fill: parent
            anchors.margins: root.contentInsideBorder ? root.border.width : 0
        }
    }

    ShaderEffectSource {
        id: shaderSource
        hideSource: true
        sourceItem: contentItemContainer
    }

    ShaderEffect {
        id: shader
        anchors.fill: root
        fragmentShader: `qrc:/Quickshell/Widgets/shaders/cliprect${root.contentUnderBorder ? "-ub" : ""}.frag.qsb`
        property Rectangle rect: rectangle
        property color backgroundColor: "white"
        property color borderColor: root.border.color
        property ShaderEffectSource content: shaderSource
    }
}
