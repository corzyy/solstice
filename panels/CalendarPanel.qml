pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../themes"
import "../services"
import "../ui"
import "../ui" as Ui
import "./CalendarModel.js" as Cal

Scope {
    id: root
    property bool showCalendar: false
    signal dismissed()
    property var notifServer: null
    property bool _winVisible: showCalendar
    Timer { id: calHideTimer; interval: Theme.panelHideDelay; repeat: false; onTriggered: if (!root.showCalendar) root._winVisible = false }
    // PERF: shared debounce for wheel + arrow-key month navigation.
    Timer { id: _monthNavDebounce; interval: 100; repeat: false }
    onShowCalendarChanged: {
        if (showCalendar) { _winVisible = true; calHideTimer.stop() } else calHideTimer.restart()
    }

    // --- M3 icon button: circular state-layer target for toolbars and
    // inline card actions. `active` renders the filled (primary) variant.
    component M3IconButton: Item {
        id: iconButton
        property string glyph: ""
        property bool active: false
        property int size: 40
        property int glyphSize: 18
        signal clicked()

        implicitWidth: iconButton.size
        implicitHeight: iconButton.size
        Layout.preferredWidth: iconButton.size
        Layout.preferredHeight: iconButton.size
        scale: iconButtonLayer.pressed ? Theme.pressScale : 1
        transformOrigin: Item.Center
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: Theme.shapesAa
            color: iconButton.active ? Theme.primary : "transparent"
            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
        }
        Text {
            anchors.centerIn: parent
            text: iconButton.glyph
            color: iconButton.active ? Theme.on_primary : Theme.textPrimary
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(iconButton.glyphSize)
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        StateLayer {
            id: iconButtonLayer
            radius: Math.round(iconButton.size / 2)
            color: iconButton.active ? Theme.on_primary : Theme.textPrimary
            onClicked: iconButton.clicked()
        }
    }

    // --- M3 button: filled (primary) or tonal (surface_container_highest,
    // which stays visible when a palette maps secondary_container onto the
    // pane color — e.g. monochrome wallpapers).
    component M3Button: Item {
        id: m3Button
        property string label: ""
        property string glyph: ""
        property bool filled: true
        signal clicked()

        implicitWidth: m3ButtonRow.implicitWidth + 34
        implicitHeight: 36
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        scale: m3ButtonLayer.pressed ? Theme.pressScale : 1
        transformOrigin: Item.Center
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            antialiasing: Theme.shapesAa
            // Tonal = surface_container_highest, not secondary_container:
            // monochrome palettes map secondary_container onto the pane
            // color, which would make the button invisible.
            color: m3Button.filled ? Theme.primary : Theme.surface_container_highest
            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
        }
        Row {
            id: m3ButtonRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: m3Button.glyph.length > 0
                text: m3Button.glyph
                color: m3Button.filled ? Theme.on_primary : Theme.textPrimary
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(15)
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: m3Button.label
                color: m3Button.filled ? Theme.on_primary : Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.Medium
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
        StateLayer {
            id: m3ButtonLayer
            radius: Math.round(m3Button.height / 2)
            color: m3Button.filled ? Theme.on_primary : Theme.textPrimary
            onClicked: m3Button.clicked()
        }
    }

    // --- M3 switch (copied from the settings app NexusControls.M3Switch):
    // 1.7:1 track, handle widens while pressed, animated check/X icon, and
    // Space/Enter support. The owning row still toggles from its StateLayer.
    component M3Switch: Item {
        id: m3Switch
        property bool checked: false
        property bool disabled: false
        signal toggled(bool next)
        // Tokens.font.body.medium.pointSize + Tokens.padding.small * 2
        readonly property int trackHeight: Theme.fs(14) + 16
        // StyledSwitch: implicitWidth = implicitHeight * 1.7
        readonly property int trackWidth: Math.round(trackHeight * 1.7)
        readonly property int handleSize: trackHeight - 4
        implicitWidth: trackWidth
        implicitHeight: trackHeight
        activeFocusOnTab: !disabled
        Keys.onSpacePressed: event => { if (!m3Switch.disabled) m3Switch.toggled(!m3Switch.checked); event.accepted = true }
        Keys.onEnterPressed: event => { if (!m3Switch.disabled) m3Switch.toggled(!m3Switch.checked); event.accepted = true }
        Keys.onReturnPressed: event => { if (!m3Switch.disabled) m3Switch.toggled(!m3Switch.checked); event.accepted = true }

        Rectangle {
            anchors.centerIn: parent
            width: m3Switch.trackWidth
            height: m3Switch.trackHeight
            radius: height / 2
            antialiasing: Theme.shapesAa
            color: {
                if (m3Switch.disabled)
                    return m3Switch.checked ? Qt.alpha(Theme.on_surface, 0.12) : Qt.alpha(Theme.surface_container_highest, 0.38)
                return m3Switch.checked ? Theme.accent : Theme.surface_container_highest
            }

            Rectangle {
                // StyledSwitch: pressed handle widens to implicitHeight * 1.2
                readonly property real nonAnimWidth: swMouse.pressed ? m3Switch.handleSize * 1.2 : m3Switch.handleSize

                implicitWidth: nonAnimWidth
                implicitHeight: m3Switch.handleSize
                radius: Math.min(width, height) / 2
                antialiasing: Theme.shapesAa
                color: {
                    if (m3Switch.disabled)
                        return m3Switch.checked ? Theme.surface : Qt.alpha(Theme.on_surface, 0.12)
                    return m3Switch.checked ? Theme.onAccent : Theme.outline
                }

                x: m3Switch.checked ? m3Switch.trackWidth - nonAnimWidth - 2 : 2
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    antialiasing: Theme.shapesAa

                    color: m3Switch.checked ? Theme.accent : Theme.on_surface
                    opacity: swMouse.pressed ? 0.1 : swMouse.containsMouse ? 0.08 : 0

                    Behavior on opacity {
                        Ui.Anim {
                            type: Ui.Anim.DefaultEffects
                        }
                    }
                }

                Shape {
                    id: icon
                    // Scalar morph (0 = cross, 1 = check). Keep in sync with
                    // NexusControls.M3Switch: animating QPointF breaks the
                    // icon update (Qt "QQmlPointFValueType" warnings).
                    property real morph: m3Switch.checked ? 1 : 0
                    Behavior on morph {
                        enabled: Theme.animationsEnabled
                        NumberAnimation {
                            duration: Theme.durFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveFastSpatial
                        }
                    }

                    anchors.centerIn: parent
                    width: height
                    height: m3Switch.handleSize - 12
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: Theme.fs(16) * 0.15
                        strokeColor: {
                            if (m3Switch.disabled)
                                return m3Switch.checked ? Theme.outline : Theme.surface_container
                            return m3Switch.checked ? Theme.accent : Theme.surface_container_highest
                        }
                        fillColor: "transparent"
                        capStyle: Theme.cornerRadius === 0 ? ShapePath.SquareCap : ShapePath.RoundCap

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

                        Behavior on strokeColor {
                            Ui.Anim.CAnim {}
                        }
                    }
                }

                Behavior on x {
                    Ui.Anim {
                        type: Ui.Anim.FastSpatial
                    }
                }

                Behavior on implicitWidth {
                    Ui.Anim {
                        type: Ui.Anim.FastSpatial
                    }
                }
            }
        }

        Ui.StateLayer {
            id: swMouse
            showHoverBackground: false
            disabled: m3Switch.disabled
            radius: Math.round(height / 2)
            color: m3Switch.checked ? Theme.onAccent : Theme.textPrimary
            onClicked: mouse => { if (!m3Switch.disabled) m3Switch.toggled(!m3Switch.checked); mouse.accepted = true }
        }
    }

    // --- Month navigation header: M3 expressive (title-large month label,
    // filled Today button + circular icon buttons at the trailing edge).
    component CalHeader: RowLayout {
        id: calHeaderRoot
        required property var scope
        property bool showNav: true

        Layout.fillWidth: true
        Layout.preferredHeight: 44
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 44

            Text {
                id: monthLabel
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: calHeaderRoot.scope.viewDate.toLocaleDateString(I18n.formatLocale, "MMMM yyyy")
                color: monthTitleMouse.containsMouse && !calHeaderRoot.scope.viewingCurrentMonth ? Theme.primary : Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(20)
                font.weight: Font.DemiBold
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }
            StateLayer {
                id: monthTitleMouse
                disabled: calHeaderRoot.scope.viewingCurrentMonth
                showHoverBackground: false
                radius: 12
                color: Theme.textPrimary
                onClicked: calHeaderRoot.scope.goToToday()
            }
        }
        // Today — only when drifted away from the current month.
        M3Button {
            visible: calHeaderRoot.showNav && !calHeaderRoot.scope.viewingCurrentMonth
            label: "Today"
            glyph: "󰃭"
            onClicked: calHeaderRoot.scope.goToToday()
        }
        M3IconButton {
            visible: calHeaderRoot.showNav
            glyph: "‹"
            glyphSize: 22
            onClicked: calHeaderRoot.scope.moveMonth(-1)
        }
        M3IconButton {
            visible: calHeaderRoot.showNav
            glyph: "›"
            glyphSize: 22
            onClicked: calHeaderRoot.scope.moveMonth(1)
        }
    }

    // --- Selected-day hero: M3 headline date on a primary-container card.
    component CalHero: Rectangle {
        id: heroRoot
        required property var scope
        Layout.fillWidth: true
        Layout.preferredHeight: 84
        radius: 24
        color: Theme.primary_container
        antialiasing: Theme.shapesAa

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 16
            spacing: 14
            Text {
                id: heroDayNum
                Layout.alignment: Qt.AlignVCenter
                text: heroRoot.scope.selectedDate.getDate()
                color: Theme.on_primary_container
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(40)
                font.weight: Font.Bold
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: heroRoot.scope.selectedDate.toLocaleDateString(I18n.formatLocale, "dddd")
                    color: Theme.on_primary_container
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(15)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    Layout.fillWidth: true
                    text: heroRoot.scope.selectedDate.toLocaleDateString(I18n.formatLocale, "MMMM yyyy")
                    color: Theme.withAlpha(Theme.on_primary_container, 0.72)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
        }
        // Click = back to today (same contract as before, just a state layer
        // instead of a hand-rolled hover tint).
        StateLayer {
            radius: 24
            color: Theme.on_primary_container
            disabled: heroRoot.scope.selectedKey === heroRoot.scope.todayKey && heroRoot.scope.viewingCurrentMonth
            onClicked: heroRoot.scope.goToToday()
        }
    }

    // --- Month grid: circular M3 day cells (today filled primary, selected
    // primary container), weekday header, shared-axis month change.
    component CalGrid: ColumnLayout {
        id: calGridRoot
        required property var scope

        Layout.fillWidth: true
        spacing: 4
        // Month changes are lateral navigation: the new grid slides 30dp in
        // from the direction of travel and fades in (M3 shared axis X).
        Motion {
            id: monthMotion
            active: true
            pattern: Motion.SharedAxisX
            direction: calGridRoot.scope._monthDir
        }
        opacity: monthMotion.opacity
        // Translate (not x) so the layout keeps owning the position.
        transform: Translate { x: monthMotion.x }
        Connections {
            target: calGridRoot.scope
            function onMonthRevChanged() { monthMotion.replay() }
        }

        Row {
            id: headerRow
            Layout.alignment: Qt.AlignHCenter
            spacing: calGridRoot.scope.cellSpacing
            Repeater {
                model: calGridRoot.scope.weekdays
                delegate: Text {
                    required property var modelData
                    width: calGridRoot.scope.cellWidth; height: 22
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: calGridRoot.scope.weekdayLabel(modelData)
                    color: Theme.textMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium; font.letterSpacing: 0.5
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
        }

        Repeater {
            model: calGridRoot.scope.weeks
            delegate: Row {
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                spacing: calGridRoot.scope.cellSpacing
                Repeater {
                    model: modelData.days
                    delegate: Item {
                        id: dayCell
                        required property var modelData
                        readonly property bool isToday: modelData.key === calGridRoot.scope.todayKey
                        readonly property bool isSelected: modelData.key === calGridRoot.scope.selectedKey
                        readonly property bool filled: dayCell.isToday || dayCell.isSelected
                        width: calGridRoot.scope.cellWidth
                        height: calGridRoot.scope.cellHeight

                        Rectangle {
                            id: dayCircle
                            anchors.centerIn: parent
                            width: parent.height
                            height: parent.height
                            radius: width / 2
                            antialiasing: Theme.shapesAa
                            color: dayCell.isToday ? Theme.primary
                                : dayCell.isSelected ? Theme.primary_container
                                : "transparent"
                            scale: dayLayer.pressed ? Theme.pressScale : 1
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
                                text: String(dayCell.modelData.day)
                                color: {
                                    if (dayCell.isToday) return Theme.on_primary
                                    if (dayCell.isSelected) return Theme.on_primary_container
                                    if (!dayCell.modelData.inMonth) return Theme.withAlpha(Theme.textPrimary, 0.38)
                                    if (dayCell.modelData.weekend) return Theme.textSecondary
                                    return Theme.textPrimary
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(14)
                                font.weight: dayCell.filled ? Font.DemiBold : Font.Medium
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            StateLayer {
                                id: dayLayer
                                radius: Math.round(dayCircle.width / 2)
                                color: dayCell.isToday ? Theme.on_primary : dayCell.isSelected ? Theme.on_primary_container : Theme.textPrimary
                                onClicked: calGridRoot.scope.selectDay(dayCell.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Footer: M3 linear year progress with an expressive stop dot.
    component CalFooter: RowLayout {
        id: calFooterRoot
        required property var scope

        Layout.fillWidth: true
        Layout.preferredHeight: 24
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: String(calFooterRoot.scope.today.getFullYear())
            color: Theme.textSecondary
            font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        Rectangle {
            id: yearTrack
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 6
            height: 6
            radius: height / 2
            color: Theme.surface_container_highest
            antialiasing: Theme.shapesAa
            Rectangle {
                antialiasing: Theme.shapesAa
                width: Math.round(parent.width * calFooterRoot.scope.yearDone)
                height: parent.height
                radius: parent.radius
                color: Theme.primary
                Behavior on width {
                    enabled: Theme.animationsEnabled
                    NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial }
                }
            }
            Rectangle {
                antialiasing: Theme.shapesAa
                width: 4; height: 4; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                color: Theme.textMuted
            }
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: calFooterRoot.scope.yearDonePercent + "%"
            color: Theme.textPrimary
            font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
    }

    // --- Single notification card (swipe-to-dismiss). Instantiated per
    // entry inside the app groups below.
    component NotifCard: Rectangle {
        id: cardRoot
        required property var scope
        required property var entry
        property bool leaving: false
        // Minimized stacks set this: tapping the card expands its group
        // instead of doing nothing (swipe still dismisses).
        property bool expandOnClick: false
        signal expandRequested()
        implicitHeight: notifInner.implicitHeight + 24
        height: leaving ? 0 : implicitHeight
        // Caelestia dismiss morph: height collapses on the spatial curve,
        // fade on the effects curve (were hardcoded 180/160 InOutQuad).
        Behavior on height { enabled: cardRoot.leaving && Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
        opacity: leaving ? 0 : 1.0 - Math.min(0.5, Math.abs(swipeProxy.x) / Math.max(1, width) * 0.7)
        Behavior on opacity { enabled: cardRoot.leaving && Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
        transform: Translate { x: swipeProxy.x }
        clip: true
        radius: 20
        color: (entry.urgency === 2) ? Theme.error_container : Theme.panelCardHigh
        antialiasing: Theme.shapesAa
        Item { id: swipeProxy; x: 0 }
        // Swipe snap-back / fly-out on the expressive curves.
        NumberAnimation { id: snapBack; target: swipeProxy; property: "x"; to: 0; duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEmphasizedDecelerate }
        NumberAnimation {
            id: flyOut
            target: swipeProxy; property: "x"; duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandardAccel
            onFinished: { cardRoot.leaving = true; byeTimer.restart() }
        }
        Timer { id: byeTimer; interval: Theme.durDefaultSpatial + Theme.durFastEffects; repeat: false; onTriggered: cardRoot.scope.dismissHistoryEntry(cardRoot.entry) }
        MouseArea {
            id: swipeMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: !cardRoot.leaving
            hoverEnabled: true
            cursorShape: cardRoot.expandOnClick ? Qt.PointingHandCursor : Qt.ArrowCursor
            drag.target: swipeProxy
            drag.axis: Drag.XAxis
            drag.minimumX: -cardRoot.width
            drag.maximumX: cardRoot.width
            drag.smoothed: false
            onPressed: mouse => { snapBack.stop(); flyOut.stop() }
            onReleased: {
                let dx = swipeProxy.x
                if (Math.abs(dx) > 90) {
                    flyOut.to = (dx >= 0 ? 1 : -1) * (cardRoot.width + 40)
                    flyOut.start()
                } else {
                    snapBack.start()
                }
            }
            onCanceled: snapBack.start()
            onClicked: {
                // Tap (not drag) on a minimized-stack card expands its group.
                try { if (Math.abs(swipeProxy.x) > 8) return } catch (e) { }
                if (cardRoot.expandOnClick) cardRoot.expandRequested()
            }
        }
        RowLayout {
            id: notifInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10
            // Leading urgency badge (M3 avatar slot).
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: width / 2
                antialiasing: Theme.shapesAa
                color: (cardRoot.entry.urgency === 2) ? Theme.error : Theme.surface_container_highest
                Text {
                    anchors.centerIn: parent
                    text: (cardRoot.entry.urgency === 2) ? "󰅚" : "󰂚"
                    color: (cardRoot.entry.urgency === 2) ? Theme.on_error : Theme.textSecondary
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(15)
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        Layout.fillWidth: true
                        visible: (cardRoot.entry.summary || "").length > 0
                        text: cardRoot.entry.summary || ""
                        color: (cardRoot.entry.urgency === 2) ? Theme.on_error_container : Theme.textPrimary
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        Layout.alignment: Qt.AlignTop
                        text: cardRoot.scope.timeAgo(cardRoot.entry.time)
                        color: (cardRoot.entry.urgency === 2) ? Theme.withAlpha(Theme.on_error_container, 0.72) : Theme.textMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Medium
                    }
                }
                Text {
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                    Layout.fillWidth: true
                    visible: (cardRoot.entry.body || "").length > 0
                    text: cardRoot.entry.body || ""
                    color: (cardRoot.entry.urgency === 2) ? Theme.withAlpha(Theme.on_error_container, 0.85) : Theme.textSecondary
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }
        M3IconButton {
            glyph: "✕"
            size: 26
            glyphSize: 11
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            visible: parentHover.hovered
            onClicked: cardRoot.scope.dismissHistoryEntry(cardRoot.entry)
        }
        HoverHandler { id: parentHover }
    }

    // --- GNOME-style notification center (M3 surface card).
    component NotifCenter: Rectangle {
        id: notifRoot
        required property var scope

        radius: 24
        color: Theme.panelCard
        antialiasing: Theme.shapesAa

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            // Panes pin LTR back so a right-side notification pane only mirrors
            // child order, never text (same contract as the old ColumnLayout).
            layoutDirection: Qt.LeftToRight

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8
                Text {
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                    text: "Notifications"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(15); font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }
                M3Button {
                    visible: notifRoot.scope.notifList.length > 0
                    label: "Clear"
                    filled: false
                    onClicked: notifRoot.scope.clearAllNotifications()
                }
            }

            // DND as an M3 list item: tonal card, whole row toggles, switch is
            // the trailing control.
            Rectangle {
                id: dndRow
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 20
                color: Theme.panelCardHigh
                antialiasing: Theme.shapesAa

                // Declared before the row content (settings ToggleRow pattern):
                // the switch keeps its own press feedback, clicks on the label
                // or empty space fall through here.
                StateLayer {
                    id: dndLayer
                    radius: 20
                    color: Theme.textPrimary
                    onClicked: Theme.setDndEnabled(!Theme.dndEnabled)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: width / 2
                        antialiasing: Theme.shapesAa
                        color: Theme.dndEnabled ? Theme.primary : Theme.surface_container_highest
                        Behavior on color {
                            enabled: Theme.animationsEnabled
                            ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                        }
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            anchors.centerIn: parent
                            text: "󰂛"
                            color: Theme.dndEnabled ? Theme.on_primary : Theme.textSecondary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(15)
                            Behavior on color {
                                enabled: Theme.animationsEnabled
                                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                            }
                        }
                    }
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        text: "Do Not Disturb"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Font.Medium
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    M3Switch {
                        checked: Theme.dndEnabled
                        onToggled: n => Theme.setDndEnabled(n)
                    }
                }
            }

            // Empty state — same flexible height as the list, so the popup
            // never resizes when notifications come and go.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: notifRoot.scope.notifList.length === 0
                spacing: 6
                Item { Layout.fillWidth: true; Layout.fillHeight: true }
                Rectangle {
                    antialiasing: Theme.shapesAa
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: width / 2
                    color: Theme.panelCardHigh
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        anchors.centerIn: parent
                        text: "󰂚"
                        color: Theme.textMuted
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(30)
                    }
                }
                Text {
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                    Layout.alignment: Qt.AlignHCenter
                    text: "No Notifications"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); font.weight: Font.DemiBold
                }
                Text {
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                    Layout.alignment: Qt.AlignHCenter
                    text: "You're all caught up"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
                }
                Item { Layout.fillWidth: true; Layout.fillHeight: true }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: notifRoot.scope.notifList.length > 0
                Flickable {
                    id: notifFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: notifListCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                    id: notifListCol
                    width: notifFlick.width
                    spacing: 8
                    Repeater {
                        model: notifRoot.scope.notifGroups
                        delegate: Column {
                            id: groupCol
                            required property var modelData
                            readonly property bool isCollapsed: notifRoot.scope.isGroupCollapsed(modelData.appName)
                            width: notifListCol.width
                            spacing: 6
                            RowLayout {
                                width: parent.width
                                spacing: 6
                                // Chevron + app label. The chevron rotates on an
                                // M3 fast-spatial curve instead of swapping the
                                // ▸/▾ glyphs (Google Sans Flex lacks them and
                                // the fallback renders off-baseline).
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    Row {
                                        id: groupToggleRow
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 5
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰅀"
                                            color: groupToggleMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                            font.family: Theme.iconFontFamily
                                            font.pixelSize: Theme.fs(14)
                                            rotation: groupCol.isCollapsed ? -90 : 0
                                            antialiasing: Theme.textAa
                                            renderType: Theme.textRenderType
                                            Behavior on rotation {
                                                enabled: Theme.animationsEnabled
                                                NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                                            }
                                            Behavior on color {
                                                enabled: Theme.animationsEnabled
                                                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (modelData.appName || "Notification").toUpperCase()
                                            color: groupToggleMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.DemiBold; font.letterSpacing: 0.6
                                            Behavior on color {
                                                enabled: Theme.animationsEnabled
                                                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                                            }
                                        }
                                    }
                                    StateLayer { id: groupToggleMouse; showHoverBackground: false; radius: 8; color: Theme.textPrimary; onClicked: notifRoot.scope.toggleGroupCollapsed(modelData.appName) }
                                }
                                // Count badge (M3 secondary-container pill).
                                Rectangle {
                                    antialiasing: Theme.shapesAa
                                    visible: (modelData.entries ? modelData.entries.length : 0) > 1
                                    Layout.preferredWidth: groupCount.implicitWidth + 12
                                    Layout.preferredHeight: 18
                                    radius: height / 2
                                    color: Theme.secondary_container
                                    Text {
                                        id: groupCount
                                        antialiasing: Theme.textAa
                                        renderType: Theme.textRenderType
                                        anchors.centerIn: parent
                                        text: "×" + modelData.entries.length
                                        color: Theme.on_secondary_container
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold
                                    }
                                }
                                M3IconButton {
                                    glyph: "✕"
                                    size: 26
                                    glyphSize: 11
                                    onClicked: notifRoot.scope.clearGroupNotifications(groupCol.modelData)
                                }
                            }
                            Column {
                                id: flowStack
                                width: parent.width
                                spacing: 6
                                visible: !groupCol.isCollapsed
                                Repeater {
                                    model: groupCol.isCollapsed ? [] : modelData.entries
                                    delegate: NotifCard {
                                        required property var modelData
                                        scope: notifRoot.scope
                                        entry: modelData
                                        width: notifListCol.width
                                    }
                                }
                            }
                            // Collapsed stack (minimized): the 2 latest notifications
                            // as real cards in a deck — newest on top, second
                            // peeking out beneath it. Opaque backing keeps the
                            // translucent card fills from showing through.
                            Item {
                                id: peekStack
                                width: parent.width
                                readonly property var firstEntry: (modelData.entries && modelData.entries.length > 0) ? modelData.entries[0] : null
                                readonly property var secondEntry: (modelData.entries && modelData.entries.length > 1) ? modelData.entries[1] : null
                                height: Math.max(topCard.height, secondCard.visible ? secondCard.y + secondCard.height : 0)
                                clip: true
                                visible: groupCol.isCollapsed && firstEntry !== null
                                NotifCard {
                                    id: secondCard
                                    scope: notifRoot.scope
                                    entry: peekStack.secondEntry ? peekStack.secondEntry : ({})
                                    visible: peekStack.secondEntry !== null
                                    expandOnClick: true
                                    onExpandRequested: notifRoot.scope.toggleGroupCollapsed(modelData.appName)
                                    x: 12
                                    y: 12
                                    width: parent.width - 24
                                }
                                // Opaque backing for the top card.
                                Rectangle {
                                    width: parent.width
                                    height: topCard.height
                                    color: Theme.panelCard
                                }
                                NotifCard {
                                    id: topCard
                                    scope: notifRoot.scope
                                    entry: peekStack.firstEntry ? peekStack.firstEntry : ({})
                                    width: parent.width
                                    expandOnClick: true
                                    onExpandRequested: notifRoot.scope.toggleGroupCollapsed(modelData.appName)
                                }
                            }
                        }
                    }
                    }
                }
                ScrollIndicator { flick: notifFlick }
            }
        }
    }

    readonly property int barT: Theme.barThickness
    readonly property string barPos: Theme.barPosition
    // Attached-bar morph: tuck under the bar edge (see Theme.panelAttachOverlap)
    // instead of floating detached below it.
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)

    FileView {
        id: calendarSettingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/calendar.json"
        watchChanges: true
        onFileChanged: reload()
        blockLoading: true
        printErrors: false
        adapter: JsonAdapter {
            property string weekStartDay: "sunday"
            // Read by Theme.calendarNotifLeft — declared here only so
            // week-start writes never drop it from the file.
            property string notifSide: "left"
        }
    }
    Process { id: calendarSettingsInitProc; command: ["bash", "-c", "echo"] }
    Timer {
        id: calendarSettingsInitTimer
        interval: 700
        running: true
        repeat: false
        onTriggered: {
            if (!calendarSettingsInitProc.running) {
                calendarSettingsInitProc.command = ["bash", "-c", "mkdir -p ~/.config/quickshell/solstice; if [ ! -f ~/.config/quickshell/solstice/config/calendar.json ]; then echo '{\"weekStartDay\":\"sunday\"}' > ~/.config/quickshell/solstice/config/calendar.json; fi; echo done"]
                calendarSettingsInitProc.running = true
            }
        }
    }

    property date today: new Date()
    readonly property string todayKey: Cal.keyForDate(today)
    property date selectedDate: new Date()
    readonly property string selectedKey: Cal.keyForDate(selectedDate)
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    readonly property date viewDate: new Date(viewYear, viewMonth, 1)
    readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

    readonly property real yearDone: Cal.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
    readonly property int yearDonePercent: Cal.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

    readonly property int weekStart: Cal.normalizedWeekStart(calendarSettingsFile.adapter.weekStartDay, 0)
    readonly property var labelLocale: I18n.formatLocale
    readonly property var weekdays: Cal.weekdayOrder(weekStart)
    readonly property var weeks: Cal.monthGrid(viewYear, viewMonth, weekStart, todayKey)

    // Notification center model: newest first.
    // CRASH FIX: rebuild plain snapshots here. History may still hold
    // legacy entries with QObjects (actions/image) from before the
    // HistoryService sanitizer — passing those raw maps into Repeaters
    // segfaults Qt (QV4::fromData/fromQVariantMap). Only id/appName/
    // summary/body/urgency/time (numbers+strings) ever reach the UI.
    readonly property var notifList: {
        try {
            let h = HistoryService.history
            if (!h || h.length === 0) return []
            let out = []
            for (let i = h.length - 1; i >= 0; i--) {
                try {
                    let e = h[i]
                    if (!e) continue
                    let t = e.time
                    let tMs = Date.now()
                    try {
                        if (typeof t === "number" && isFinite(t)) tMs = Math.round(t)
                        else if (t instanceof Date && !isNaN(t.getTime())) tMs = t.getTime()
                        else if (t !== undefined && t !== null) {
                            let d = new Date(t)
                            tMs = isNaN(d.getTime()) ? Date.now() : d.getTime()
                        }
                    } catch (e2) { tMs = Date.now() }
                    let urg = Number(e.urgency)
                    if (!isFinite(urg)) urg = 1
                    out.push({
                        id: (e.id !== undefined && isFinite(Number(e.id))) ? Math.round(Number(e.id)) : -1,
                        appName: String(e.appName || "Notification").slice(0, 120),
                        summary: String(e.summary || "").slice(0, 300),
                        body: String(e.body || "").slice(0, 500),
                        urgency: Math.round(urg),
                        time: Math.round(tMs)
                    })
                } catch (e3) { continue }
            }
            return out
        } catch (e) { return [] }
    }
    // Grouped by application (GNOME-style), newest group first.
    readonly property var notifGroups: {
        try {
            let list = root.notifList
            let groups = []
            let byApp = {}
            for (let i = 0; i < list.length; i++) {
                let e = list[i]
                if (!e) continue
                let app = (e && e.appName) ? String(e.appName).slice(0, 120) : "Notification"
                if (!byApp[app]) { byApp[app] = { appName: app, entries: [] }; groups.push(byApp[app]) }
                byApp[app].entries.push(e)
            }
            return groups
        } catch (e) { return [] }
    }
    // Collapsed groups (by app name) — minimized stack is the default;
    // header click expands a group, click again to minimize.
    // `collapsedApps` stores explicit opt-outs: absent/true = collapsed,
    // false = expanded.
    property var collapsedApps: ({})
    function groupKey(app) { return (app) ? String(app) : "Notification" }
    function isGroupCollapsed(app) {
        try { return collapsedApps[groupKey(app)] !== false } catch (e) { return true }
    }
    function toggleGroupCollapsed(app) {
        try {
            let k = groupKey(app)
            let next = {}
            try { for (let key in collapsedApps) next[key] = collapsedApps[key] } catch (e2) { }
            if (isGroupCollapsed(app)) next[k] = false
            else delete next[k]
            collapsedApps = next
        } catch (e) { }
    }

    // M3 Expressive geometry: 44dp day cells carry 36dp circular targets,
    // each pane is a 24dp-rounded surface card on the panel surface.
    readonly property int cellWidth: 54
    readonly property int cellHeight: 36
    readonly property int cellSpacing: 4
    readonly property int minimalGridWidth: 7 * cellWidth + 6 * cellSpacing
    readonly property int calPanePadding: 12
    readonly property int calPaneWidth: minimalGridWidth + calPanePadding * 2
    readonly property int notifPaneWidth: 330
    readonly property int paneGap: 16
    readonly property int contentMargin: 16
    readonly property int panelWidth: contentMargin * 2 + notifPaneWidth + paneGap + calPaneWidth

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
        onDateChanged: {
            if (Cal.keyForDate(date) === root.todayKey) return
            var followToday = root.viewingCurrentMonth
            root.today = date
            if (followToday) goToToday()
        }
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { }
        function open(): void { }
        function close(): void { }
        function nextMonth(): void { root.moveMonth(1) }
        function prevMonth(): void { root.moveMonth(-1) }
        function state(): string { return "calendar=" + root.showCalendar + " view=" + root.viewYear + "-" + (root.viewMonth+1) }
    }

    function goToToday() {
        viewYear = today.getFullYear(); viewMonth = today.getMonth()
        selectedDate = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    }
    function selectDay(cell) {
        try {
            selectedDate = new Date(cell.year, cell.month, cell.day)
            if (cell.year !== viewYear || cell.month !== viewMonth) {
                _monthDir = (cell.year > viewYear || (cell.year === viewYear && cell.month > viewMonth)) ? 1 : -1
                viewYear = cell.year; viewMonth = cell.month
            }
        } catch (e) { }
    }
    property int _monthDir: 0
    // Bumped whenever the displayed month/year changes so the grid can replay
    // its shared-axis enter (once per change, not once per changed property).
    // Public name so the Connections handler resolves (on_monthRevChanged
    // never matched).
    property int monthRev: 0
    onViewMonthChanged: monthRev++
    onViewYearChanged: monthRev++
    function moveMonth(delta) {
        _monthDir = delta
        var nxt = Cal.stepMonth(viewYear, viewMonth, delta)
        viewYear = nxt.year; viewMonth = nxt.month
    }
    function moveYear(delta) { moveMonth(delta * 12) }
    function persistWeekStart(day) {
        var next = Cal.normalizedWeekStart(day, root.weekStart)
        if (next === root.weekStart) return
        calendarSettingsFile.adapter.weekStartDay = Cal.weekStartSettingName(next)
        calendarSettingsFile.writeAdapter()
    }
    function toggleWeekStart() { persistWeekStart(Cal.toggledWeekStart(root.weekStart)) }
    function weekdayLabel(weekday) { return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase() }

    function timeAgo(t) {
        try {
            let d = (t instanceof Date) ? t : new Date(t)
            if (isNaN(d.getTime())) return ""
            let diff = Date.now() - d.getTime()
            if (diff < 0) diff = 0
            let m = Math.floor(diff / 60000)
            if (m < 1) return "now"
            if (m < 60) return m + "m ago"
            let h = Math.floor(m / 60)
            if (h < 24) return h + "h ago"
            let days = Math.floor(h / 24)
            if (days === 1) return "Yesterday"
            if (days < 7) return days + "d ago"
            return d.toLocaleDateString(I18n.formatLocale, I18n.monthDayFormat)
        } catch (e) { return "" }
    }
    function dismissHistoryEntry(entry) {
        try {
            let id = entry ? entry.id : undefined
            if (id !== undefined) {
                try { HistoryService.remove(id) } catch (e) { }
                // Also drop a still-visible toast with the same id.
                try {
                    let srv = root.notifServer
                    let m = srv ? srv.trackedNotifications : null
                    let vals = m ? (m.values !== undefined ? m.values : m) : []
                    let n = vals ? vals.length : 0
                    for (let i = 0; i < n; i++) {
                        try { if (vals[i] && vals[i].id === id) vals[i].dismiss() } catch (e2) { }
                    }
                } catch (e3) { }
            }
        } catch (e) { }
    }
    function clearAllNotifications() {
        try { HistoryService.clear() } catch (e) { }
        try {
            let srv = root.notifServer
            let m = srv ? srv.trackedNotifications : null
            let vals = m ? (m.values !== undefined ? m.values : m) : []
            let n = vals ? vals.length : 0
            for (let i = 0; i < n; i++) {
                try { if (vals[i]) vals[i].dismiss() } catch (e2) { }
            }
        } catch (e) { }
    }
    function clearGroupNotifications(group) {
        try {
            let es = (group && group.entries) ? group.entries.slice() : []
            for (let i = 0; i < es.length; i++) dismissHistoryEntry(es[i])
        } catch (e) { }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root._winVisible && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "calendar"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            // Disabled while the panel is closing: during a morph handoff
            // the outgoing window stays mapped for panelHideDelay and must
            // not eat the click that belongs to the panel now on top.
            MouseArea { anchors.fill: parent; enabled: root.showCalendar; onClicked: root.dismissed() }

            // Caelestia popout (ui/CaelestiaPopout): curtain reveal from
            // behind the bar edge + slide + nested fades off one offsetScale
            // driver (1:1 with caelestia-dots/shell).
            CaelestiaPopout {
                id: calPopout
                shown: root.showCalendar
                morphId: "clock"
                morphActive: Theme.isPrimaryScreen(modelData)
                barPos: root.barPos
                // Open geometry: the loaded calendar card spans panelWidth
                // and reports its natural height through the loader's
                // implicit size (reading the loader's own size would loop,
                // since the loader is now sized by the popout).
                fullWidth: root.panelWidth
                fullHeight: calLoader.implicitHeight
                anchorCenter: calAnchor.isVertical ? calAnchor.cy : calAnchor.cx
                edge: root.barPos === "bottom" ? calAnchor.panelY + calPopout.fullHeight : root.barPos === "right" ? calAnchor.panelX + calPopout.fullWidth : root.barPos === "left" ? calAnchor.panelX : calAnchor.panelY
                screenSize: calAnchor.isVertical ? calAnchor.screenHeight : calAnchor.screenWidth
                margin: calAnchor.margin

                // Frame: stretched by the popout (near edge pinned at the
                // bar) exactly like every other panel, with the clamped
                // radius while short.
                Rectangle {
                    id: calCard
                    width: parent.width
                    height: parent.height
                    antialiasing: Theme.shapesAa
                    // Fill comes from the popout's shadow layer (see
                    // CaelestiaPopout shadowSource): it paints the same
                    // rounded silhouette behind this card, so the shadow
                    // silhouette is only composited once.
                    color: "transparent"
                    border.color: Theme.panelBorderColor
                    border.width: 2
                    // Bar-side corners square, free corners rounded (fused joint).
                    topLeftRadius: root.barPos === "top" || root.barPos === "left" ? 0 : calPopout.frameRadius
                    topRightRadius: root.barPos === "top" || root.barPos === "right" ? 0 : calPopout.frameRadius
                    bottomLeftRadius: root.barPos === "bottom" || root.barPos === "left" ? 0 : calPopout.frameRadius
                    bottomRightRadius: root.barPos === "bottom" || root.barPos === "right" ? 0 : calPopout.frameRadius
                    clip: false
                    // Seam strip: erases the collar outline along the fused edge.
                    Rectangle {
                        antialiasing: Theme.shapesAa
                        visible: Theme.panelAccentBorder
                        x: 0
                        y: root.barPos === "bottom" ? calCard.height - 2 : 0
                        width: calCard.width
                        height: 2
                        color: Theme.panelWindowBg
                    }

                    Loader {
                        id: calLoader
                        // Content travels on the popout's own driver (frame
                        // stretches first, content settles after) and keeps
                        // the full panel size so nothing reflows mid-stretch.
                        // contentFade hides it while the card morphs over to
                        // another panel's pose.
                        opacity: calPopout.contentFade
                        x: calPopout.contentX
                        y: calPopout.contentY
                        width: calPopout.fullWidth
                        height: calPopout.fullHeight
                        BarAnchor {
                            id: calAnchor
                            moduleId: "clock"
                            barPos: root.barPos
                            panelWidth: calPopout.fullWidth
                            panelHeight: calPopout.fullHeight
                            // Screen dims come from the popout's parent (the
                            // full-screen layer item).
                            screenWidth: calPopout.parent.width
                            screenHeight: calPopout.parent.height
                            gap: root.panelGap
                            fallbackX: (calPopout.parent.width - calPopout.fullWidth) / 2
                            fallbackY: calPopout.parent.height - calPopout.fullHeight - root.panelGap
                        }
                    sourceComponent: Item {
                        id: popupRoot
                        width: root.panelWidth
                        implicitHeight: outerRect.implicitHeight
                        height: outerRect.implicitHeight
                        focus: true
                        // Island morph progress, forwarded from the loader scope
                        // (separate component: outer ids are not visible here).
                        // 1 = fully open; defaults open for standalone contexts.
                        property real islandGrow: 1
                        property real islandT: Math.max(0, Math.min(1, islandGrow))

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) { root.dismissed(); event.accepted = true }
                            else if (!event.isAutoRepeat && (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                                if (root._monthNavDebounce.running) { event.accepted = true; return }
                                root._monthNavDebounce.start()
                                if (event.key === Qt.Key_Left) root.moveMonth(-1)
                                else if (event.key === Qt.Key_Right) root.moveMonth(1)
                                else if (event.key === Qt.Key_Up) root.moveYear(-1)
                                else root.moveYear(1)
                                event.accepted = true
                            }
                            else if (event.key === Qt.Key_Home || event.text === "t" || event.text === "T") { root.goToToday(); event.accepted = true }
                            else if (event.text === "w" || event.text === "W") { root.toggleWeekStart(); event.accepted = true }
                        }
                        Component.onCompleted: forceActiveFocus()
                        Connections {
                            target: root
                            function onShowCalendarChanged() {
                                if (root.showCalendar) {
                                    root.today = new Date(); root.goToToday()
                                    Qt.callLater(function() { popupRoot.forceActiveFocus() })
                                }
                            }
                        }

                        // Frame visuals live in calCard (the popout frame);
                        // this item only carries the layout height.
                        Item {
                            antialiasing: Theme.shapesAa
                            id: outerRect
                            anchors.fill: parent
                            implicitHeight: contentRow.implicitHeight + root.contentMargin * 2
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.AllButtons
                            // Off while closing: the window outlives the card
                            // (morph/close hold) and must not steal input.
                            enabled: root.showCalendar
                            onClicked: mouse => mouse.accepted = true
                            onPressed: mouse => mouse.accepted = true
                            onWheel: wheel => wheel.accepted = true
                        }

                        RowLayout {
                            id: contentRow
                            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                            anchors.margins: root.contentMargin
                            spacing: root.paneGap
                            // Pane swap: RTL mirrors child order. Both panes pin
                            // LTR back so only the order flips, never the text.
                            layoutDirection: Theme.calendarNotifLeft ? Qt.LeftToRight : Qt.RightToLeft

                            // Notification pane — M3 surface card (the gap
                            // replaces the old divider + spacers).
                            NotifCenter {
                                scope: root
                                Layout.preferredWidth: root.notifPaneWidth
                                Layout.fillHeight: true
                            }

                            // Calendar pane — M3 surface card.
                            Rectangle {
                                id: calPane
                                antialiasing: Theme.shapesAa
                                Layout.preferredWidth: root.calPaneWidth
                                Layout.preferredHeight: calCol.implicitHeight + root.calPanePadding * 2
                                implicitHeight: calCol.implicitHeight + root.calPanePadding * 2
                                radius: 24
                                color: Theme.panelCard

                                ColumnLayout {
                                    id: calCol
                                    anchors.fill: parent
                                    anchors.margins: root.calPanePadding
                                    layoutDirection: Qt.LeftToRight
                                    spacing: 8
                                    CalHeader { scope: root; showNav: true }
                                    CalHero { scope: root }
                                    CalGrid { scope: root }
                                    CalFooter { scope: root }
                                    WheelHandler {
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                        // PERF: fast scroll/key-repeat rebuilt the 42-cell
                                        // grid per tick. Debounce to one nav per 100ms.
                                        onWheel: event => {
                                            if (event.angleDelta.y === 0) return
                                            if (root._monthNavDebounce.running) { event.accepted = true; return }
                                            root._monthNavDebounce.start()
                                            root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }
}
