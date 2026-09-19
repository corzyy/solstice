pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

// M3 expressive slider (horizontal XS size). Used by the control-center
// CcSlider (thick variant) — the vertical/compact/ticks/label variants of
// the original port were never instantiated and have been removed.
// Geometry (dp = px 1:1): 16 track (pill, 2dp inner corners facing the
// handle), 6dp handle↔track gap, 4x44 pill handle (shrinks to 2 wide while
// pressed), 4dp stop dot at the inactive end, 40dp state layer (hover 8% /
// focus+pressed 12%), floating pill value bubble.
// Colors: active/handle primary, inactive surface-container-highest,
// disabled on-surface at 38% (tracks 12% inactive) with no stop dot.
Item {
    id: root
    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 0
    property bool showValueLabel: true
    property string valueText: ""
    property int decimals: 0
    property color activeTrackColor: Theme.primary
    property color inactiveTrackColor: Theme.surface_container_highest
    property color handleColor: Theme.primary
    property color stateLayerColor: Theme.primary
    property color valueIndicatorColor: Theme.primary
    property color valueIndicatorTextColor: Theme.on_primary
    property color disabledActiveColor: Theme.on_surface
    property color disabledInactiveColor: Theme.on_surface
    property color stopDotColor: Theme.primary

    property int trackHeight: 16
    property int trackRadius: trackHeight / 2
    // Corner radius of the track ends facing the handle gap (2 = M3 stock,
    // 0 = squared/slot look).
    property int trackInnerRadius: 2
    property int handleWidth: 4
    property int handleHeight: 44
    // -1 keeps the M3 pill handle; >= 0 squares it off.
    property real handleRadius: -1
    property int indicatorRadius: 16
    property int stateLayerSize: 40
    property int trackGap: 6
    property int stopDotSize: 4
    property bool showStopDot: true
    property bool wheelEnabled: true

    readonly property real _range: Math.max(0.0001, to - from)
    readonly property real _ratio: Math.max(0, Math.min(1, (value - from) / _range))
    readonly property bool _isDiscrete: stepSize > 0
    // M3 floating label: steady while hovered, keyboard-focused or pressed.
    readonly property bool _showIndicator: showValueLabel && (dragging || hovered || activeFocus) && enabled
    // Handle shrinks in width while pressed (M3 press feedback).
    readonly property int _thinSide: handlePressed && enabled ? 2 : handleWidth

    signal moved(real newValue)

    implicitHeight: 48
    implicitWidth: 120
    height: implicitHeight
    width: parent ? parent.width : implicitWidth
    focus: enabled
    Keys.enabled: enabled
    activeFocusOnTab: enabled

    property bool dragging: false
    property bool hovered: false
    property bool handlePressed: false
    property bool handleHovered: false

    function _snap(v: real): real {
        if (!_isDiscrete || stepSize <= 0) return Math.max(from, Math.min(to, v))
        let steps = Math.round((v - from) / stepSize)
        let snapped = from + steps * stepSize
        snapped = Math.max(from, Math.min(to, snapped))
        return Math.round(snapped * _snapFactor) / _snapFactor
    }
    function _stepDecimals(): int {
        if (decimals > 0) return decimals
        if (_isDiscrete && stepSize > 0 && stepSize < 1) {
            let dot = stepSize.toString().indexOf(".")
            if (dot !== -1) return stepSize.toString().length - dot - 1
        }
        return 0
    }
    readonly property real _snapFactor: Math.pow(10, _stepDecimals())
    function _valueText(): string {
        if (valueText.length > 0) return valueText
        const d = _stepDecimals()
        if (d > 0) return value.toFixed(d)
        return Math.round(value).toString()
    }
    function _commit(v: real): void {
        v = _snap(v)
        if (v !== value) {
            root.value = v
            root.moved(v)
        }
    }
    function _nudge(steps: real): void {
        const step = _isDiscrete ? stepSize : Math.max(1, Math.round(_range * 0.02))
        _commit(value + steps * step)
    }
    function setValueFromRatio(r: real) {
        if (!enabled) return
        _commit(from + r * _range)
    }

    Item {
        id: sliderArea
        anchors.top: parent.top
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 48
        width: parent.width

        readonly property int hPad: 2
        readonly property int trackLeft: hPad
        readonly property int trackW: width - hPad * 2
        readonly property real handleCenterX: trackLeft + trackW * root._ratio
        // Track segments stop at the 6dp gap around the handle.
        readonly property real activeW: Math.max(0, handleCenterX - root._thinSide / 2 - root.trackGap - trackLeft)
        readonly property real inactiveX: handleCenterX + root._thinSide / 2 + root.trackGap
        readonly property real inactiveW: Math.max(0, trackLeft + trackW - inactiveX)

        Rectangle {
            antialiasing: Theme.shapesAa
            id: activeTrack
            visible: sliderArea.activeW > 0.5
            x: sliderArea.trackLeft
            width: sliderArea.activeW
            anchors.verticalCenter: parent.verticalCenter
            height: root.trackHeight
            topLeftRadius: Math.min(root.trackRadius, height / 2)
            bottomLeftRadius: Math.min(root.trackRadius, height / 2)
            topRightRadius: root.trackInnerRadius
            bottomRightRadius: root.trackInnerRadius
            color: root.enabled ? root.activeTrackColor : Theme.withAlpha(root.disabledActiveColor, 0.38)
            // Drags track the finger instantly; clicks/keys glide.
            Behavior on width { enabled: Theme.animationsEnabled && !root.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
        }
        Rectangle {
            antialiasing: Theme.shapesAa
            id: inactiveTrack
            visible: sliderArea.inactiveW > 0.5
            x: sliderArea.inactiveX
            width: sliderArea.inactiveW
            anchors.verticalCenter: parent.verticalCenter
            height: root.trackHeight
            topLeftRadius: root.trackInnerRadius
            bottomLeftRadius: root.trackInnerRadius
            topRightRadius: Math.min(root.trackRadius, height / 2)
            bottomRightRadius: Math.min(root.trackRadius, height / 2)
            color: root.enabled ? root.inactiveTrackColor : Theme.withAlpha(root.disabledInactiveColor, 0.12)
            Behavior on width { enabled: Theme.animationsEnabled && !root.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            Behavior on x { enabled: Theme.animationsEnabled && !root.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
            Rectangle {
                antialiasing: Theme.shapesAa
                visible: root.showStopDot && root.enabled && sliderArea.inactiveW > 12
                width: root.stopDotSize; height: root.stopDotSize; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right; anchors.rightMargin: 6
                color: root.stopDotColor
            }
        }

        Rectangle {
            antialiasing: Theme.shapesAa
            id: stateLayer
            width: root.stateLayerSize; height: root.stateLayerSize; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sliderArea.handleCenterX - width / 2
            color: {
                if (!root.enabled) return "transparent"
                if (root.handlePressed) return Theme.withAlpha(root.stateLayerColor, 0.12)
                if (root.activeFocus) return Theme.withAlpha(root.stateLayerColor, 0.12)
                if (root.handleHovered) return Theme.withAlpha(root.stateLayerColor, 0.08)
                return "transparent"
            }
            Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
        }

        Item {
            id: handleWrap
            width: root._thinSide; height: root.handleHeight
            anchors.verticalCenter: parent.verticalCenter
            x: sliderArea.handleCenterX - width / 2
            // Clicks/keys glide the handle on the expressive spatial curve.
            Behavior on x { enabled: Theme.animationsEnabled && !root.dragging; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
            Behavior on width { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }

            Rectangle {
                antialiasing: Theme.shapesAa
                id: handleRect
                anchors.fill: parent
                radius: root.handleRadius >= 0 ? root.handleRadius : Math.min(width, height) / 2
                color: root.enabled ? root.handleColor : Theme.withAlpha(Theme.on_surface, 0.38)
                Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
            }

            Loader {
                active: root._showIndicator
                asynchronous: true
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.top; anchors.bottomMargin: 8
                width: item ? item.width : 48; height: item ? item.height : 32
                sourceComponent: Item {
                    width: Math.max(48, indicatorText.implicitWidth + 24); height: 32
                    opacity: 0; scale: 0.7
                    transformOrigin: Item.Bottom
                    Component.onCompleted: { opacity = 1; scale = 1 }
                    Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                    Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
                    Rectangle {
                        antialiasing: Theme.shapesAa
                        anchors.fill: parent
                        radius: root.indicatorRadius
                        color: root.valueIndicatorColor
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            id: indicatorText; anchors.centerIn: parent; text: root._valueText()
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.Medium; color: root.valueIndicatorTextColor
                        }
                    }
                }
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent; hoverEnabled: true
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
            enabled: root.enabled; preventStealing: true; acceptedButtons: Qt.LeftButton
            onEntered: root.hovered = true
            onExited: { root.hovered = false; root.handleHovered = false }
            onPositionChanged: mouse => {
                root.handleHovered = Math.abs(mouse.x - sliderArea.handleCenterX) < root.stateLayerSize / 2
                if (pressed) updateFromMouse(mouse.x)
            }
            onPressed: mouse => { root.dragging = true; root.handlePressed = true; root.forceActiveFocus(); updateFromMouse(mouse.x) }
            onReleased: { root.dragging = false; root.handlePressed = false }
            onClicked: updateFromMouse(mouse.x)
            onWheel: wheel => {
                if (!root.wheelEnabled) return
                let dir = wheel.angleDelta.y > 0 ? 1 : -1
                if (root._isDiscrete) root._nudge(dir)
                else root._commit(root.value + dir * root._range * 0.05)
                wheel.accepted = true
            }
            function updateFromMouse(m) {
                root.setValueFromRatio(Math.max(0, Math.min(1, (m - sliderArea.trackLeft) / sliderArea.trackW)))
            }
        }
        Keys.onPressed: event => {
            if (!root.enabled) return
            let handled = true
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) root._nudge(-1)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) root._nudge(1)
            else if (event.key === Qt.Key_PageDown) root._nudge(-5)
            else if (event.key === Qt.Key_PageUp) root._nudge(5)
            else if (event.key === Qt.Key_Home) root._commit(root.from)
            else if (event.key === Qt.Key_End) root._commit(root.to)
            else handled = false
            if (handled) event.accepted = true
        }
    }
}
