pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../style/themes"
import "../../backend/services"
import "../../style/ui"

Scope {
    id: root
    property bool showNotifications: false
    signal dismissed()
    property var notifServer: null
    property bool _winVisible: showNotifications
    Timer { id: hideTimer; interval: Theme.panelHideDelay; repeat: false; onTriggered: if (!root.showNotifications) root._winVisible = false }
    onShowNotificationsChanged: {
        if (showNotifications) { _winVisible = true; hideTimer.stop() } else hideTimer.restart()
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

    // --- M3 expressive icon toggle: round state-layer target whose tonal
    // background morphs into a random M3E shape while `checked` (same shape
    // pool/contract as PowerAction and the settings nav badge). The shape is
    // re-rolled on every toggle-on; toggling off morphs back to the circle.
    component M3ShapeIconToggle: Item {
        id: shapeToggle
        property string glyph: ""
        property string checkedGlyph: ""
        property bool checked: false
        property int size: 36
        property int glyphSize: 15
        property int pickedShape: MaterialShape.Circle
        readonly property var shapeChoices: [
            MaterialShape.Square, MaterialShape.Slanted, MaterialShape.Pill,
            MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny,
            MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
            MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided,
            MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf,
            MaterialShape.Clover8Leaf
        ]
        signal toggled(bool next)

        function pickShape(): void {
            const list = shapeToggle.shapeChoices
            if (list.length === 0) return
            let next = list[Math.floor(Math.random() * list.length)]
            if (list.length > 1 && next === shapeToggle.pickedShape)
                next = list[(list.indexOf(next) + 1) % list.length]
            shapeToggle.pickedShape = next
        }
        onCheckedChanged: if (checked) pickShape()

        implicitWidth: size
        implicitHeight: size
        Layout.preferredWidth: size
        Layout.preferredHeight: size
        activeFocusOnTab: true
        Keys.onSpacePressed: event => { shapeToggle.toggled(!shapeToggle.checked); event.accepted = true }
        Keys.onEnterPressed: event => { shapeToggle.toggled(!shapeToggle.checked); event.accepted = true }
        Keys.onReturnPressed: event => { shapeToggle.toggled(!shapeToggle.checked); event.accepted = true }
        scale: shapeToggleLayer.pressed ? Theme.pressScale : 1
        transformOrigin: Item.Center
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }

        MaterialShape {
            anchors.centerIn: parent
            implicitSize: shapeToggle.size
            shape: shapeToggle.checked ? shapeToggle.pickedShape : MaterialShape.Circle
            color: shapeToggle.checked ? Theme.primary : Theme.surface_container_highest
            animationDuration: Theme.durDefaultSpatial
            animationEasing.type: Easing.BezierSpline
            animationEasing.bezierCurve: Theme.curveDefaultSpatial
            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
            Text {
                anchors.centerIn: parent
                text: shapeToggle.checked && shapeToggle.checkedGlyph.length > 0 ? shapeToggle.checkedGlyph : shapeToggle.glyph
                color: shapeToggle.checked ? Theme.on_primary : Theme.textPrimary
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(shapeToggle.glyphSize)
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }
            StateLayer {
                id: shapeToggleLayer
                radius: Math.round(shapeToggle.size / 2)
                color: shapeToggle.checked ? Theme.on_primary : Theme.textPrimary
                onClicked: shapeToggle.toggled(!shapeToggle.checked)
            }
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
            // Leading app avatar: real app icon clipped into a tonal circle;
            // urgency glyph as fallback (critical = alert, else bell).
            Rectangle {
                id: notifAvatar
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: width / 2
                antialiasing: Theme.shapesAa
                clip: true
                readonly property bool isCritical: cardRoot.entry.urgency === 2
                color: isCritical ? Theme.error : Theme.surface_container_highest
                readonly property string iconSource: {
                    let ic = cardRoot.entry.appIcon ? String(cardRoot.entry.appIcon) : ""
                    if (ic === "") return ""
                    if (ic.startsWith("/") || ic.startsWith("file://") || ic.startsWith("image://")) return ic
                    if (Quickshell.hasThemeIcon(ic)) return Quickshell.iconPath(ic)
                    let lc = ic.toLowerCase()
                    if (Quickshell.hasThemeIcon(lc)) return Quickshell.iconPath(lc)
                    return Quickshell.iconPath(ic)
                }
                property bool iconFailed: false
                onIconSourceChanged: iconFailed = false
                Image {
                    anchors.fill: parent
                    source: notifAvatar.iconSource
                    sourceSize.width: 64
                    sourceSize.height: 64
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    visible: !notifAvatar.iconFailed && notifAvatar.iconSource !== ""
                    onStatusChanged: if (status === Image.Error) notifAvatar.iconFailed = true
                }
                Text {
                    anchors.centerIn: parent
                    visible: notifAvatar.iconFailed || notifAvatar.iconSource === ""
                    text: notifAvatar.isCritical ? "󰅚" : "󰂚"
                    color: notifAvatar.isCritical ? Theme.on_error : Theme.textSecondary
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(15)
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                // Header line: app name · relative time (screenshot layout).
                Row {
                    Layout.fillWidth: true
                    spacing: 5
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        width: Math.min(implicitWidth, Math.max(0, parent.width - calAppDot.implicitWidth - calAppTime.implicitWidth - 10))
                        text: cardRoot.entry.appName || "Notification"
                        color: (cardRoot.entry.urgency === 2) ? Theme.on_error_container : Theme.textPrimary
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                    }
                    Text {
                        id: calAppDot
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        text: "·"
                        color: (cardRoot.entry.urgency === 2) ? Theme.withAlpha(Theme.on_error_container, 0.7) : Theme.textMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12)
                    }
                    Text {
                        id: calAppTime
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        text: cardRoot.scope.timeAgo(cardRoot.entry.time)
                        color: (cardRoot.entry.urgency === 2) ? Theme.withAlpha(Theme.on_error_container, 0.72) : Theme.textMuted
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium
                    }
                }
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
                M3ShapeIconToggle {
                    glyph: "󰂚"
                    checkedGlyph: "󰂛"
                    checked: Theme.dndEnabled
                    onToggled: n => Theme.setDndEnabled(n)
                }
                M3Button {
                    visible: notifRoot.scope.notifList.length > 0
                    label: "Clear"
                    filled: false
                    onClicked: notifRoot.scope.clearAllNotifications()
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
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    boundsMovement: Flickable.FollowBoundsBehavior
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
                            // Cards stay built once a group was opened: the
                            // collapse morph needs them while the body shrinks.
                            // Groups never opened keep only the 2-card peek.
                            property bool everExpanded: !isCollapsed
                            onIsCollapsedChanged: if (!isCollapsed) everExpanded = true
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
                            // Expand/minimize morph: one clipped body animates
                            // its height between the minimized deck and the
                            // full card flow while the two stacks crossfade
                            // (spatial height + effects fade, same split as
                            // the toast overlay). The peek sits underneath so
                            // it is revealed as the flow fades/shrinks away.
                            Item {
                                id: groupBody
                                width: parent.width
                                height: groupCol.isCollapsed ? peekStack.height : flowStack.implicitHeight
                                clip: true
                                Behavior on height {
                                    enabled: Theme.animationsEnabled
                                    NumberAnimation { duration: Theme.durMotionSharedAxis; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
                                }

                                // Collapsed stack (minimized): the 2 latest
                                // notifications as real cards in a deck — newest
                                // on top, second peeking out beneath it. Opaque
                                // backing keeps the translucent card fills from
                                // showing through.
                                Item {
                                    id: peekStack
                                    width: parent.width
                                    readonly property var firstEntry: (modelData.entries && modelData.entries.length > 0) ? modelData.entries[0] : null
                                    readonly property var secondEntry: (modelData.entries && modelData.entries.length > 1) ? modelData.entries[1] : null
                                    height: Math.max(topCard.height, secondCard.visible ? secondCard.y + secondCard.height : 0)
                                    clip: true
                                    visible: opacity > 0.01
                                    opacity: groupCol.isCollapsed ? 1 : 0
                                    Behavior on opacity {
                                        enabled: Theme.animationsEnabled
                                        NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
                                    }
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

                                // Full flow (expanded). Stays instantiated while
                                // collapsing (everExpanded), then empties.
                                Column {
                                    id: flowStack
                                    width: parent.width
                                    spacing: 6
                                    visible: opacity > 0.01
                                    opacity: groupCol.isCollapsed ? 0 : 1
                                    Behavior on opacity {
                                        enabled: Theme.animationsEnabled
                                        NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
                                    }
                                    Repeater {
                                        model: (!groupCol.isCollapsed || groupCol.everExpanded) ? modelData.entries : []
                                        delegate: NotifCard {
                                            required property var modelData
                                            scope: notifRoot.scope
                                            entry: modelData
                                            width: notifListCol.width
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                }
                EdgeFade { flick: notifFlick; fadeColor: Theme.panelCard }
                ScrollIndicator { flick: notifFlick }
                OverscrollSpring { flick: notifFlick }
            }
        }
    }

    readonly property int barT: Theme.barThickness
    // Attached-bar morph: tuck under the bar edge (see Theme.panelAttachOverlap)
    // instead of floating detached below it.
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)

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
                        appIcon: String(e.appIcon || "").slice(0, 300),
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

    // M3 Expressive geometry: the notification pane is a 24dp-rounded
    // surface card on the panel surface.
    readonly property int notifPaneWidth: 360
    readonly property int notifPaneHeight: 440
    readonly property int contentMargin: 16
    readonly property int panelWidth: contentMargin * 2 + notifPaneWidth

    IpcHandler {
        target: "notificationcenter"
        function toggle(): void { }
        function open(): void { }
        function close(): void { }
        function state(): string { return "notificationcenter=" + root.showNotifications }
    }
    // Compat alias: the panel used to be called "calendar".
    IpcHandler {
        target: "calendar"
        function toggle(): void { }
        function open(): void { }
        function close(): void { }
        function state(): string { return "notificationcenter=" + root.showNotifications }
    }

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
            WlrLayershell.namespace: "notificationcenter"
            // Hyprland: OnDemand + focus grab (see HyprlandService) so the
            // taskbar stays clickable while the panel is open.
            WlrLayershell.keyboardFocus: HyprlandService.isHyprland ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
            Component.onCompleted: HyprlandService.registerPanelWindow(this)
            Component.onDestruction: HyprlandService.unregisterPanelWindow(this)
            // Disabled while the panel is closing: during a morph handoff
            // the outgoing window stays mapped for panelHideDelay and must
            // not eat the click that belongs to the panel now on top.
            MouseArea { anchors.fill: parent; enabled: root.showNotifications; onClicked: root.dismissed() }

            // Caelestia popout (style/ui/CaelestiaPopout): curtain reveal from
            // behind the bar edge + slide + nested fades off one offsetScale
            // driver (1:1 with caelestia-dots/shell).
            CaelestiaPopout {
                id: centerPopout
                shown: root.showNotifications
                morphId: "clock"
                morphActive: Theme.isPrimaryScreen(modelData)
                // Open geometry: the loaded notification card spans panelWidth
                // and reports its natural height through the loader's
                // implicit size (reading the loader's own size would loop,
                // since the loader is now sized by the popout).
                fullWidth: root.panelWidth
                fullHeight: contentLoader.implicitHeight
                anchorCenter: centerAnchor.cx
                edge: centerAnchor.panelY
                screenSize: centerAnchor.screenWidth
                margin: centerAnchor.margin

                // Frame: stretched by the popout (near edge pinned at the
                // bar) exactly like every other panel, with the clamped
                // radius while short.
                Rectangle {
                    id: centerCard
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
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: centerPopout.frameRadius
                    bottomRightRadius: centerPopout.frameRadius
                    clip: false
                    // Seam strip: erases the collar outline along the fused edge.
                    Rectangle {
                        antialiasing: Theme.shapesAa
                        visible: Theme.panelAccentBorder
                        x: 0
                        y: 0
                        width: centerCard.width
                        height: 2
                        color: Theme.panelWindowBg
                    }

                    Loader {
                        id: contentLoader
                        // Content travels on the popout's own driver (frame
                        // stretches first, content settles after) and keeps
                        // the full panel size so nothing reflows mid-stretch.
                        // contentFade hides it while the card morphs over to
                        // another panel's pose.
                        opacity: centerPopout.contentFade
                        x: centerPopout.contentX
                        y: centerPopout.contentY
                        width: centerPopout.fullWidth
                        height: centerPopout.fullHeight
                        BarAnchor {
                            id: centerAnchor
                            moduleId: "clock"
                                        panelWidth: centerPopout.fullWidth
                            panelHeight: centerPopout.fullHeight
                            // Screen dims come from the popout's parent (the
                            // full-screen layer item).
                            screenWidth: centerPopout.parent.width
                            screenHeight: centerPopout.parent.height
                            gap: root.panelGap
                            fallbackX: (centerPopout.parent.width - centerPopout.fullWidth) / 2
                            fallbackY: centerPopout.parent.height - centerPopout.fullHeight - root.panelGap
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
                        }
                        Component.onCompleted: forceActiveFocus()
                        Connections {
                            target: root
                            function onShowNotificationsChanged() {
                                if (root.showNotifications) {
                                    Qt.callLater(function() { popupRoot.forceActiveFocus() })
                                }
                            }
                        }

                        // Frame visuals live in centerCard (the popout frame);
                        // this item only carries the layout height.
                        Item {
                            antialiasing: Theme.shapesAa
                            id: outerRect
                            anchors.fill: parent
                            implicitHeight: centerPane.height + root.contentMargin * 2
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.AllButtons
                            // Off while closing: the window outlives the card
                            // (morph/close hold) and must not steal input.
                            enabled: root.showNotifications
                            onClicked: mouse => mouse.accepted = true
                            onPressed: mouse => mouse.accepted = true
                            onWheel: wheel => wheel.accepted = true
                        }

                        // Notification pane — M3 surface card.
                        NotifCenter {
                            id: centerPane
                            scope: root
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: root.contentMargin
                            height: root.notifPaneHeight
                        }
                    }
                }
                }
            }
        }
    }
}
