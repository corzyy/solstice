pragma ComponentBehavior: Unbound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Templates
import "../../../style/themes"
import "../../../style/ui" as Ui

// NexusControls — 1:1 port of the Caelestia Nexus settings kit
// (caelestia-dots/shell modules/nexus/common + components/controls) onto the
// solstice Theme. Token values are copied verbatim from
// plugin/src/Caelestia/Config/tokens.hpp:
//   rounding/spacing/padding: 4 / 8 / 12 / 16 / 20 / 28 / 32 / 48
//   fontSize: label.small 11, label.medium 12, body.small 13, body.medium 14,
//             body.large 16, title.large 22;  icon.medium 20
//   animations: existing Theme.dur*/curve* tokens match AnimCurves/Durations
//               exactly (expressive fast/default/slow spatial + effects).
//
// Mapping onto Theme:
//   surfaceContainer(Lowest/High/Highest) -> panelCard(Lowest/High/Highest)
//   m3primary/onPrimary                   -> accent/onAccent
//   m3secondaryContainer/on…              -> secondary_container/on_secondary_container
//   m3onSurface(Variant)                  -> textPrimary(textSecondary)
//   m3outline(Variant)                    -> textMuted / divider
//   m3error                               -> error
QtObject {
    id: __nexusControls

    // ---- tokens ----------------------------------------------------------
    readonly property int rExtraSmall: 4
    readonly property int rSmall: 8
    readonly property int rMedium: 12
    readonly property int rLarge: 16
    readonly property int rExtraLarge: 28
    readonly property int rExtraLargeInc: 32
    readonly property int padSmall: 8
    readonly property int padMedium: 12
    readonly property int padLarge: 16
    readonly property int padLargeInc: 20
    readonly property int iconMedium: 20

    function fs11(): int { return Theme.fs(11) }
    function fs12(): int { return Theme.fs(12) }
    function fs13(): int { return Theme.fs(13) }
    function fs14(): int { return Theme.fs(14) }
    function fs16(): int { return Theme.fs(16) }
    function fs22(): int { return Theme.fs(22) }

    // ---- primitives ------------------------------------------------------

    // ConnectedRect: the grouped-list card. Inner rows keep 4px corners so
    // adjacent rows form the Nexus "pinched seam" instead of a divider.
    component ConnectedRect: Rectangle {
        id: root
        property bool first: false
        property bool last: false
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
    }

    // Section label: label.medium, onSurfaceVariant, 8px left inset.
    component SectionHeader: Text {
        id: root
        property bool first: false
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        font.weight: Font.Medium
        color: Theme.textSecondary
        elide: Text.ElideRight
        leftPadding: 8
        rightPadding: 8
        topPadding: first ? 0 : 20
        bottomPadding: 4
    }

    component Note: Text {
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        width: parent ? parent.width : 300
        leftPadding: 8
        rightPadding: 8
        topPadding: 16
        bottomPadding: 4
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(11)
        color: Theme.textMuted
    }

    // Kept for page compatibility; Nexus rows use plain glyphs.
    component IconBadge: Text {
        property string glyph: ""
        property color tint: Theme.textSecondary
        property int size: 40
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        text: glyph
        color: tint
        font.family: Theme.iconFontFamily
        font.pixelSize: Theme.fs(18)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Nexus rows have no separators; kept so pages compile unchanged.
    component RowDivider: Item {
        visible: false
        height: 0
    }

    // StyledSwitch port (components/controls/StyledSwitch.qml):
    // track 30x51, thumb 26 (31.2 pressed), check when on / cross when off.
    component M3Switch: Item {
        id: root
        property bool checked: false
        property bool disabled: false
        signal toggled(bool next)
        readonly property int trackHeight: Theme.fs(14) + 16
        readonly property int trackWidth: Math.round(trackHeight * 1.7)
        property bool pressed: false
        property bool hovered: false
        implicitWidth: trackWidth
        implicitHeight: trackHeight
        activeFocusOnTab: !disabled
        Keys.onSpacePressed: event => { if (!root.disabled) root.toggled(!root.checked); event.accepted = true }
        Keys.onEnterPressed: event => { if (!root.disabled) root.toggled(!root.checked); event.accepted = true }
        Keys.onReturnPressed: event => { if (!root.disabled) root.toggled(!root.checked); event.accepted = true }

        Rectangle {
            id: track
            anchors.centerIn: parent
            width: root.trackWidth
            height: root.trackHeight
            radius: height / 2
            antialiasing: Theme.shapesAa
            color: {
                if (root.disabled)
                    return root.checked ? Qt.alpha(Theme.on_surface, 0.12) : Qt.alpha(Theme.panelCardHighest, 0.38)
                return root.checked ? Theme.accent : Theme.panelCardHighest
            }
            Behavior on color { enabled: Theme.animationsEnabled; Ui.Anim.CAnim {} }

            Rectangle {
                readonly property real nonAnimWidth: root.pressed ? implicitHeight * 1.2 : implicitHeight

                implicitWidth: nonAnimWidth
                implicitHeight: root.trackHeight - 4
                radius: Math.min(width, height) / 2
                antialiasing: Theme.shapesAa
                color: {
                    if (root.disabled)
                        return root.checked ? Theme.surface : Qt.alpha(Theme.on_surface, 0.12)
                    return root.checked ? Theme.onAccent : Theme.outline
                }

                x: root.checked ? root.trackWidth - nonAnimWidth - 2 : 2
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    antialiasing: Theme.shapesAa
                    color: root.checked ? Theme.accent : Theme.on_surface
                    opacity: root.pressed ? 0.1 : root.hovered ? 0.08 : 0
                    Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                }

                Shape {
                    id: icon
                    // Scalar morph (0 = cross, 1 = check) instead of four
                    // animated point props. Animating QPointF is fragile —
                    // when any animation writes a double Qt logs
                    // "Could not find any constructor for value type
                    // QQmlPointFValueType" every frame and the knob icon stays
                    // stuck. One real + NumberAnimation is exact interpolation
                    // and survives renderer/async quirks.
                    property real morph: root.checked ? 1 : 0
                    Behavior on morph {
                        enabled: Theme.animationsEnabled
                        NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                    }
                    anchors.centerIn: parent
                    width: height
                    height: parent.implicitHeight - 12
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: Theme.fs(16) * 0.15
                        strokeColor: {
                            if (root.disabled)
                                return root.checked ? Theme.outline : Theme.panelCard
                            return root.checked ? Theme.accent : Theme.panelCardHighest
                        }
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        // Cross: (0.15,0.15)->(0.85,0.85) + (0.15,0.85)->(0.85,0.15)
                        // Check: (0.15,0.5)->(0.4,0.7) + (0.4,0.7)->(0.85,0.2)
                        startX: icon.width * 0.15
                        startY: icon.height * (0.15 + 0.35 * icon.morph)
                        PathLine {
                            x: icon.width * (0.85 - 0.45 * icon.morph)
                            y: icon.height * (0.85 - 0.15 * icon.morph)
                        }
                        PathMove {
                            x: icon.width * (0.15 + 0.25 * icon.morph)
                            y: icon.height * (0.85 - 0.15 * icon.morph)
                        }
                        PathLine {
                            x: icon.width * 0.85
                            y: icon.height * (0.15 + 0.05 * icon.morph)
                        }
                        Behavior on strokeColor { enabled: Theme.animationsEnabled; Ui.Anim.CAnim {} }
                    }
                }

                Behavior on x { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
                Behavior on implicitWidth { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
            }
        }

        Ui.StateLayer {
            id: swMouse
            showHoverBackground: false
            disabled: root.disabled
            radius: Math.round(height / 2)
            color: root.checked ? Theme.onAccent : Theme.textPrimary
            onPressedChanged: root.pressed = pressed
            onContainsMouseChanged: root.hovered = containsMouse
            onClicked: mouse => { if (!root.disabled) root.toggled(!root.checked); mouse.accepted = true }
        }
    }

    // ToggleRow = StyledSwitch row: content 20px in, label body.small (13),
    // subtext label.small (11) outline, vertical padding 12.
    component ToggleRow: Rectangle {
        id: root
        property string text: ""
        property string subtext: ""
        property string icon: ""
        property color tint: Theme.accent
        property bool checked: false
        property bool disabled: false
        property bool first: false
        property bool last: false
        signal toggled(bool next)
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: Math.max(col.implicitHeight, sw.trackHeight) + 24
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        Ui.StateLayer {
            id: rowMouse
            showHoverBackground: false
            disabled: root.disabled
            radius: 28
            color: Theme.textPrimary
            onClicked: root.toggled(!root.checked)
        }
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            Column {
                id: col
                width: Math.max(0, parent.width - sw.trackWidth - 12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: root.text
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: root.subtext.length > 0
                    text: root.subtext
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            M3Switch {
                id: sw
                anchors.verticalCenter: parent.verticalCenter
                checked: root.checked
                disabled: root.disabled
                onToggled: n => root.toggled(n)
            }
        }
    }

    // SliderRow = Nexus SliderRow: 20px horizontal insets, 16px top inset,
    // 24px slider band, tall thin handle (FastSpatial height morph).
    component SliderRow: Rectangle {
        id: root
        property string icon: ""
        property color tint: Theme.accent
        property string label: ""
        property string valueLabel: ""
        property real from: 0
        property real to: 100
        property real value: 0
        property real stepSize: 1
        property string unit: ""
        property bool first: false
        property bool last: false
        signal moved(real v)
        signal applied(real v)
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: row.implicitHeight + 36
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        function dispDecimals(): int {
            let s = root.stepSize.toString()
            let i = s.indexOf(".")
            if (i === -1) return 0
            return Math.max(0, Math.min(3, s.length - i - 1))
        }
        function autoText(live: real): string {
            return (root.stepSize < 1 ? Number(live).toFixed(root.dispDecimals()) : Math.round(live)) + root.unit
        }
        Row {
            id: row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 16
            spacing: 12
            Text {
                visible: root.icon.length > 0
                text: root.icon
                font.family: Theme.iconFontFamily; font.pixelSize: Theme.fs(20)
                color: Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Column {
                width: Math.max(0, parent.width - (root.icon.length > 0 ? 32 : 0))
                spacing: 12
                Row {
                    width: parent.width
                    Text {
                        width: Math.max(0, parent.width - valText.width)
                        text: root.label
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        id: valText
                        text: root.valueLabel.length > 0 ? root.valueLabel : root.autoText(sliderBody.liveValue)
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                        color: Theme.textMuted
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                Item {
                    id: sliderBody
                    width: parent.width
                    height: 24
                    property real liveValue: root.value
                    property real extValue: root.value
                    onExtValueChanged: if (!sliderMouse.dragging) liveValue = extValue
                    onVisibleChanged: if (visible) liveValue = root.value
                    readonly property real range: Math.max(0.0001, root.to - root.from)
                    readonly property real progress: Math.max(0, Math.min(1, (liveValue - root.from) / range))
                    readonly property real handleCX: 2 + (width - 4) * progress
                    readonly property real handleW: 4
                    readonly property real handleH: sliderMouse.pressed ? height * 2.0 : height * 1.65
                    readonly property real filledW: Math.max(0, handleCX - handleW / 2 - 4)

                    // Remaining track (24px pill fading in once it's wide).
                    Rectangle {
                        id: trackI
                        anchors.verticalCenter: parent.verticalCenter
                        x: sliderBody.handleCX + sliderBody.handleW / 2 + 4
                        width: Math.max(0, sliderBody.width - x)
                        height: parent.height * (parent.height <= 12 ? opacity : Math.min(opacity * 2, 1))
                        opacity: Math.min(width, 12) / 12
                        radius: 12
                        topLeftRadius: 2
                        bottomLeftRadius: 2
                        color: Theme.secondary_container
                        antialiasing: Theme.shapesAa
                        Behavior on width { enabled: Theme.animationsEnabled && !sliderMouse.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
                        Behavior on x { enabled: Theme.animationsEnabled && !sliderMouse.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
                        Rectangle {
                            visible: parent.width > 16
                            width: 4; height: 4; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right; anchors.rightMargin: 4
                            color: Theme.accent
                            antialiasing: Theme.shapesAa
                        }
                    }
                    // Filled track.
                    Rectangle {
                        id: trackA
                        anchors.verticalCenter: parent.verticalCenter
                        x: 0
                        width: sliderBody.filledW
                        height: parent.height
                        radius: 12
                        topRightRadius: 2
                        bottomRightRadius: 2
                        color: Theme.accent
                        antialiasing: Theme.shapesAa
                        Behavior on width { enabled: Theme.animationsEnabled && !sliderMouse.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
                    }
                    // Handle: 4px wide, tall pill.
                    Rectangle {
                        width: sliderBody.handleW
                        height: sliderBody.handleH
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: sliderBody.handleCX - width / 2
                        color: Theme.accent
                        antialiasing: Theme.shapesAa
                        Behavior on height { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
                        Behavior on x { enabled: Theme.animationsEnabled && !sliderMouse.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
                    }
                    MouseArea {
                        id: sliderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        property bool dragging: false
                        function valueFromX(px: real): real {
                            let c = Math.max(0, Math.min(sliderBody.width - 4, px - 2))
                            return Math.max(root.from, Math.min(root.to, root.from + (c / (sliderBody.width - 4)) * sliderBody.range))
                        }
                        function snap(v: real): real {
                            if (root.stepSize > 0) v = Math.round(v / root.stepSize) * root.stepSize
                            return Math.max(root.from, Math.min(root.to, v))
                        }
                        onPressed: mouse => {
                            sliderMouse.dragging = true
                            let v = snap(valueFromX(mouse.x))
                            sliderBody.liveValue = v
                            root.moved(v)
                        }
                        onPositionChanged: mouse => {
                            if (!sliderMouse.dragging) return
                            let v = snap(valueFromX(mouse.x))
                            sliderBody.liveValue = v
                            root.moved(v)
                        }
                        onReleased: {
                            sliderMouse.dragging = false
                            root.applied(sliderBody.liveValue)
                            sliderBody.liveValue = root.value
                        }
                    }
                }
            }
        }
    }

    // StepperRow = Nexus StepperRow + StyledSpinBox: 65px center field
    // (radius 4) with round −/+ buttons that morph to 8px radius on press.
    component StepperRow: Rectangle {
        id: root
        property string label: ""
        property string subtext: ""
        property int value: 0
        property int from: 0
        property int to: 100
        property int stepSize: 1
        property bool first: false
        property bool last: false
        signal moved(int v)
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: Math.max(col.implicitHeight, spin.implicitHeight) + 24
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        function step(delta: int): void {
            let v = Math.max(root.from, Math.min(root.to, root.value + delta * root.stepSize))
            if (v !== root.value) root.moved(v)
        }
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            Column {
                id: col
                width: Math.max(0, parent.width - spin.width - 12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: root.label
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: root.subtext.length > 0
                    text: root.subtext
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Row {
                id: spin
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle {
                    width: 28; height: 28; radius: minusMouse.pressed ? 8 : 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.panelCardHighest
                    antialiasing: Theme.shapesAa
                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        font.pixelSize: Theme.fs(16)
                        color: root.value <= root.from ? Qt.alpha(Theme.panelCardHighest, 0.4) : Theme.textPrimary
                        antialiasing: Theme.textAa
                    }
                    Ui.StateLayer { id: minusMouse; radius: 8; color: Theme.textPrimary; disabled: root.value <= root.from; onClicked: root.step(-1) }
                    Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                }
                Rectangle {
                    width: 65; height: 28; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.panelCardHighest
                    antialiasing: Theme.shapesAa
                    Text {
                        anchors.centerIn: parent
                        text: root.value
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                        color: Theme.textPrimary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                Rectangle {
                    width: 28; height: 28; radius: plusMouse.pressed ? 8 : 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.panelCardHighest
                    antialiasing: Theme.shapesAa
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: Theme.fs(16)
                        color: root.value >= root.to ? Qt.alpha(Theme.panelCardHighest, 0.4) : Theme.textPrimary
                        antialiasing: Theme.textAa
                    }
                    Ui.StateLayer { id: plusMouse; radius: 8; color: Theme.textPrimary; disabled: root.value >= root.to; onClicked: root.step(1) }
                    Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                }
            }
        }
    }

    // DropdownRow = Nexus SelectRow: label/sub left, tonal pill right.
    // Picking opens a floating menu instead of expanding the list inline:
    // the options live in a Popup anchored to the row, so they render above
    // the page (and outside the page Flickable's clip) without reflowing the
    // settings list. Outside press / Escape close it via closePolicy; the
    // menu flips above the row when it would run past the window bottom.
    component DropdownRow: Column {
        id: root
        property string icon: ""
        property color tint: Theme.accent
        property string label: ""
        property string subtext: ""
        property var options: []
        property string current: ""
        property bool first: false
        property bool last: false
        property bool open: false
        signal picked(string value)
        width: parent ? parent.width : 300
        spacing: 0
        readonly property int menuPad: 8
        readonly property int optionHeight: 44
        readonly property int menuMaxHeight: 328
        readonly property int menuWidth: Math.min(root.width, 320)
        readonly property int menuHeight: Math.min((root.options ? root.options.length : 0) * root.optionHeight + root.menuPad * 2, root.menuMaxHeight)
        readonly property bool menuAbove: {
            let winH = 0
            try { winH = Window.window ? Window.window.height : 0 } catch (e) {}
            if (winH <= 0) return false
            const top = btn.mapToItem(null, 0, 0).y
            const belowFits = top + btn.height + 4 + root.menuHeight <= winH - 8
            const aboveFits = top - 4 - root.menuHeight >= 8
            return !belowFits && aboveFits
        }
        Rectangle {
            id: btn
            antialiasing: Theme.shapesAa
            width: parent.width
            implicitHeight: btnCol.implicitHeight + 24
            height: implicitHeight
            color: Theme.panelCard
            topLeftRadius: root.first ? 28 : 4
            topRightRadius: root.first ? 28 : 4
            bottomLeftRadius: root.last ? 28 : 4
            bottomRightRadius: root.last ? 28 : 4
            Row {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 12
                Column {
                    id: btnCol
                    width: Math.max(0, parent.width - pill.width - 12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        width: parent.width
                        text: root.label
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        width: parent.width
                        visible: root.subtext.length > 0
                        text: root.subtext
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                        color: Theme.textMuted
                        elide: Text.ElideRight
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                Rectangle {
                    id: pill
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(pillRow.implicitWidth + 28, 220)
                    height: 30
                    radius: 15
                    color: Theme.secondary_container
                    antialiasing: Theme.shapesAa
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: root.current
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                            font.weight: Font.Medium
                            color: Theme.on_secondary_container
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 160)
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        Text {
                            text: root.open ? "▴" : "▾"
                            font.pixelSize: Theme.fs(12)
                            color: Theme.on_secondary_container
                            antialiasing: Theme.textAa
                        }
                    }
                    Ui.StateLayer { id: btnMouse; showHoverBackground: false; radius: 15; color: Theme.on_secondary_container; onClicked: root.open = !root.open }
                }
            }
            Ui.StateLayer { id: bgMouse; showHoverBackground: false; radius: 28; color: Theme.textPrimary; onClicked: root.open = !root.open }
        }
        Popup {
            id: menu
            parent: btn
            width: root.menuWidth
            height: root.menuHeight
            // Right edges of menu and pill line up (pill inset is 20).
            x: btn.width - 20 - width
            y: root.menuAbove ? -height - 4 : btn.height + 4
            transformOrigin: root.menuAbove ? Popup.BottomRight : Popup.TopRight
            visible: root.open
            focus: true
            padding: root.menuPad
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            onClosed: root.open = false
            background: Rectangle {
                antialiasing: Theme.shapesAa
                color: Theme.panelCardHighest
                radius: 16
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Theme.withAlpha(Theme.shadow, 0.5)
                    shadowBlur: 0.9
                    shadowOpacity: 0.4
                    shadowVerticalOffset: root.menuAbove ? -8 : 8
                    shadowHorizontalOffset: 0
                }
            }
            contentItem: Flickable {
                id: menuFlick
                implicitHeight: menuCol.implicitHeight
                contentHeight: menuCol.implicitHeight
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                Column {
                    id: menuCol
                    width: menuFlick.width
                    Repeater {
                        model: root.options
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: modelData + "" === root.current
                            width: menuCol.width
                            height: root.optionHeight
                            radius: 8
                            color: isCurrent ? Theme.secondary_container : "transparent"
                            antialiasing: Theme.shapesAa
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8
                                Text {
                                    width: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: isCurrent ? "✓" : ""
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Theme.fs(14)
                                    color: Theme.on_secondary_container
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                                Text {
                                    width: Math.max(0, parent.width - 18 - 8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData + ""
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                                    font.weight: isCurrent ? Font.Medium : Font.Normal
                                    color: isCurrent ? Theme.on_secondary_container : Theme.textPrimary
                                    elide: Text.ElideRight
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                            }
                            Ui.StateLayer { id: optMouse; radius: 8; color: Theme.textPrimary; onClicked: { root.picked(modelData + ""); root.open = false } }
                        }
                    }
                }
            }
            enter: Transition {
                Ui.Anim { property: "opacity"; from: 0; to: 1; type: Ui.Anim.FastEffects }
                Ui.Anim { property: "scale"; from: 0.95; to: 1; type: Ui.Anim.FastSpatial }
            }
            exit: Transition {
                Ui.Anim { property: "opacity"; to: 0; type: Ui.Anim.FastEffects }
            }
        }
    }

    // TextFieldRow = Nexus TextFieldRow: label/sub left, pill field right.
    component TextFieldRow: Rectangle {
        id: root
        property string icon: ""
        property color tint: Theme.accent
        property string label: ""
        property string subtext: ""
        property string value: ""
        property string placeholder: ""
        property bool first: false
        property bool last: false
        signal valueEdited(string value)
        signal editingFinished(string value)
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: Math.max(col.implicitHeight, fieldBox.height) + 24
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        onValueChanged: if (!fieldInput.activeFocus) fieldInput.text = root.value
        Component.onCompleted: fieldInput.text = root.value
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            Column {
                id: col
                width: Math.max(0, parent.width - fieldBox.width - 12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: root.label
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: root.subtext.length > 0
                    text: root.subtext
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Rectangle {
                id: fieldBox
                anchors.verticalCenter: parent.verticalCenter
                width: 200; height: 36
                radius: 18
                color: Theme.panelCardHighest
                border.color: fieldInput.activeFocus ? Theme.accent : "transparent"
                border.width: fieldInput.activeFocus ? 2 : 0
                antialiasing: Theme.shapesAa
                Text {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    visible: fieldInput.displayText.length === 0
                    text: root.placeholder
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                TextInput {
                    id: fieldInput
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    selectionColor: Theme.accent
                    clip: true
                    onTextEdited: root.valueEdited(text)
                    onAccepted: { root.editingFinished(text); focus = false }
                    onActiveFocusChanged: if (!activeFocus && text !== root.value) root.editingFinished(text)
                }
            }
        }
    }

    // InfoRow = Nexus InfoRow: optional leading glyph, label/sub, right value.
    component InfoRow: Rectangle {
        id: root
        property string icon: ""
        property color tint: Theme.textSecondary
        property string label: ""
        property string subtext: ""
        property string value: ""
        property real valueMaxWidth: 0
        property bool first: false
        property bool last: false
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: Math.max(col.implicitHeight, valText.implicitHeight) + 24
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            Text {
                visible: root.icon.length > 0
                text: root.icon
                font.family: Theme.iconFontFamily; font.pixelSize: Theme.fs(16)
                color: Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Column {
                id: col
                width: Math.max(0, parent.width - (root.icon.length > 0 ? 28 : 0) - valText.width - 12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: root.label
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: root.subtext.length > 0
                    text: root.subtext
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Text {
                id: valText
                width: root.valueMaxWidth > 0 ? root.valueMaxWidth : Math.min(implicitWidth, parent.width / 2)
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: root.value
                font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                color: Theme.textSecondary
                elide: Text.ElideRight
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    // NavRow = Nexus RowButton + NavRow: plain glyph, label/sub, chevron.
    component NavRow: Rectangle {
        id: root
        property string icon: ""
        property color tint: Theme.textSecondary
        property string text: ""
        property string subtext: ""
        property bool showChevron: true
        property bool disabled: false
        property bool first: false
        property bool last: false
        signal clicked(var event)
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: Math.max(iconText.implicitHeight, col.implicitHeight) + 24
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            opacity: root.disabled ? 0.5 : 1
            Text {
                id: iconText
                visible: root.icon.length > 0
                text: root.icon
                font.family: Theme.iconFontFamily; font.pixelSize: Theme.fs(18)
                color: Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Column {
                id: col
                width: Math.max(0, parent.width - (root.icon.length > 0 ? 30 : 0) - (root.showChevron ? 24 : 0))
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: root.text
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: root.subtext.length > 0
                    text: root.subtext
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Text {
                visible: root.showChevron
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                font.pixelSize: Theme.fs(18)
                color: Theme.textSecondary
                antialiasing: Theme.textAa
            }
        }
        Ui.StateLayer { id: navMouse; showHoverBackground: false; disabled: root.disabled; radius: 28; color: Theme.textPrimary; onClicked: e => root.clicked(e) }
    }

    // Nexus ButtonBase.Text: tonal pill with radius morph + shapeMorph ripple.
    component TextButton: Rectangle {
        id: root
        property string text: ""
        property bool enabled2: true
        signal clicked()
        implicitWidth: label.implicitWidth + 24
        implicitHeight: 32
        radius: btnMouse.pressed ? 8 : 16
        color: btnMouse.containsMouse ? Qt.alpha(Theme.accent, 0.08) : "transparent"
        antialiasing: Theme.shapesAa
        opacity: root.enabled2 ? 1 : 0.5
        Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.weight: Font.Medium
            color: Theme.accent
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        Ui.StateLayer {
            id: btnMouse
            showHoverBackground: false
            disabled: !root.enabled2
            radius: 16
            color: Theme.accent
            onClicked: root.clicked()
        }
    }

    // SearchBar = Nexus SearchBar: full radius, surfaceContainerLowest,
    // outlineVariant border, body.large (16) text, 16px vertical padding.
    component SearchBar: Rectangle {
        id: root
        property string text: ""
        property string placeholder: "Search settings"
        signal textChanged2(string text)
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        height: Math.round(Theme.fs(16) * 1.4) + 32
        radius: height / 2
        color: Theme.panelCardLowest
        border.color: Theme.divider
        border.width: 1
        Behavior on border.color { enabled: Theme.animationsEnabled; Ui.Anim.CAnim {} }
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 12
            spacing: 12
            Text {
                text: "󰍉"
                font.family: Theme.iconFontFamily; font.pixelSize: Theme.fs(18)
                color: Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            TextInput {
                id: searchInput
                width: Math.max(0, parent.width - 30 - (clearBtn.visible ? 28 : 0))
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                font.family: Theme.fontFamily; font.pixelSize: Theme.fs(16)
                color: Theme.textPrimary
                selectionColor: Theme.accent
                clip: true
                onTextChanged: root.textChanged2(text)
            }
            Text {
                id: clearBtn
                visible: (root.text || "").length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                font.pixelSize: Theme.fs(14)
                color: Theme.textSecondary
                antialiasing: Theme.textAa
                Ui.StateLayer {
                    anchors.fill: parent
                    anchors.margins: -8
                    radius: 14
                    color: Theme.textPrimary
                    onClicked: { searchInput.text = ""; searchInput.focus = false; root.textChanged2("") }
                }
            }
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 50
            anchors.verticalCenter: parent.verticalCenter
            visible: (root.text || "").length === 0 && !searchInput.activeFocus
            text: root.placeholder
            font.family: Theme.fontFamily; font.pixelSize: Theme.fs(16)
            color: Theme.textMuted
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
    }

    // PageBase = Nexus PageBase: header (back + title.large 22) + content.
    component PageBase: Column {
        id: root
        property string title: ""
        property bool showTitle: true
        property bool showBack: false
        signal backRequested()
        signal pageEntered()
        signal pageLeft()
        function notifyShown(): void { root.pageEntered() }
        function notifyHidden(): void { root.pageLeft() }
        default property alias content: body.data
        width: parent ? parent.width : 400
        spacing: 28
        Item {
            width: parent.width
            implicitHeight: headerRow.implicitHeight
            visible: root.showTitle || root.showBack
            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20
                Rectangle {
                    visible: root.showBack
                    width: 40; height: 40
                    // M3E shape morph: circle at rest, rounded square while hovered.
                    radius: backMouse.containsMouse ? 12 : 20
                    color: Theme.panelCardHigh
                    antialiasing: Theme.shapesAa
                    Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        font.pixelSize: Theme.fs(20)
                        color: Theme.textSecondary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Ui.StateLayer { id: backMouse; radius: parent.radius; color: Theme.textPrimary; onClicked: root.backRequested() }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(22)
                    font.weight: Font.Medium
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
        }
        Column {
            id: body
            width: parent.width
            spacing: 0
        }
    }

    component PreviewTile: Rectangle {
        id: tile
        property bool selected: false
        property string label: ""
        property int contentSpacing: 6
        property bool interactionEnabled: true
        default property alias content: body.data
        signal clicked()
        radius: 16
        antialiasing: Theme.shapesAa
        color: tile.selected ? Theme.secondary_container : Theme.panelCard
        border.color: tile.selected ? Theme.accent : "transparent"
        border.width: tile.selected ? 2 : 0
        Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
        Column {
            anchors.centerIn: parent
            spacing: tile.contentSpacing
            Column {
                id: body
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: tile.contentSpacing
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: tile.selected ? Font.Medium : Font.Normal
                color: tile.selected ? Theme.on_secondary_container : Theme.textSecondary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
        Ui.StateLayer {
            id: hover
            showHoverBackground: false
            disabled: !tile.interactionEnabled
            radius: 16
            color: Theme.accent
            onClicked: tile.clicked()
        }
    }
}
