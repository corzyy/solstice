pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "../../style/themes"
import Quickshell.Wayland
import Quickshell.Services.Notifications

Scope {
    id: notifScope
    property var notifServer

    readonly property int barT: Theme.barThickness
    readonly property string barPos: Theme.barPosition
    // Preferred display for toasts: DP-1 when present, else the first
    // available screen (see Theme.primaryScreenName).
    property var targetScreen: {
        let vals = []
        try {
            let v = Quickshell.screens.values
            vals = typeof v === "function" ? v() : v
        } catch(e) { vals = [] }
        if (!vals || vals.length === 0) return null
        let want = "DP-1"
        try { want = Theme.primaryScreenName } catch(e2) { }
        for (let i = 0; i < vals.length; i++) {
            if (vals[i] && vals[i].name === want) return vals[i]
        }
        return vals[0]
    }

    // Kachel-Position als ein String (eine Quelle statt 5x kopierter
    // Theme.notifPosition-Vergleiche in notifTop/Left/Center/slideDir/isBottom).
    readonly property string notifPos: {
        try { return String(Theme.notifPosition || "top-right") } catch (e) { return "top-right" }
    }
    readonly property bool notifTop: notifPos.startsWith("top")
    readonly property bool notifLeft: notifPos.endsWith("left")
    readonly property bool notifCenter: notifPos.endsWith("center")
    readonly property int cardWidth: 380
    readonly property int edgeGap: 12

    // Close-button cookie ring: outline samples of MaterialShapes
    // Cookie9Sided (sampled from the M3Shapes plugin at implicitSize 100,
    // normalized to the unit square). One 40° period is enough — the shape
    // is 9-fold rotationally symmetric; the full 72-point outline is
    // rebuilt by rotating the period at runtime.
    readonly property int closeCookieSize: 28
    readonly property var cookiePeriod: [
        [0.50000, 0.01415],
        [0.54193, 0.02069],
        [0.58143, 0.03817],
        [0.61669, 0.06450],
        [0.65159, 0.08352],
        [0.69046, 0.09157],
        [0.73437, 0.09406],
        [0.77540, 0.10669],
        [0.81237, 0.12773]
    ]
    function cookieRingPoints(scale: real, size: real): var {
        const pts = []
        const cx = size / 2
        const cy = size / 2
        const n = cookiePeriod.length - 1
        for (let i = 0; i < n * 9; i++) {
            const base = cookiePeriod[i % n]
            const th = Math.floor(i / n) * 40 * Math.PI / 180
            const dx = (base[0] - 0.5) * size
            const dy = (base[1] - 0.5) * size
            pts.push(Qt.point(cx + (dx * Math.cos(th) - dy * Math.sin(th)) * scale,
                              cy + (dx * Math.sin(th) + dy * Math.cos(th)) * scale))
        }
        return pts
    }
    readonly property var cookieOuter: cookieRingPoints(1.0, closeCookieSize)
    readonly property var cookieInner: cookieRingPoints(0.82, closeCookieSize)

    // Toast close button: the ✕ sits in a Material 3 Cookie9Sided ring whose
    // accent arc is the toast's remaining display time — it drains clockwise
    // from 12 o'clock as progressAnim advances and freezes while the toast is
    // hovered or dragged (progressAnim pauses), so it always shows the time
    // the toast will actually stay on screen.
    component CloseCookie: Item {
        id: cookieBtn
        property real remaining: 1
        property bool critical: false
        property bool showProgress: true
        signal clicked

        readonly property bool hovered: closeMa.containsMouse
        readonly property color tint: critical ? Theme.on_error_container : Theme.textPrimary
        readonly property color ringColor: critical ? Theme.on_error_container : Theme.accent
        readonly property color trackColor: Theme.withAlpha(critical ? Theme.on_error_container : Theme.textPrimary,
                                                              critical ? (hovered ? 0.45 : 0.28) : (hovered ? 0.34 : 0.18))

        implicitWidth: notifScope.closeCookieSize
        implicitHeight: notifScope.closeCookieSize

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            antialiasing: Theme.shapesAa

            // Hover state layer (M3): subtle cookie-shaped wash.
            ShapePath {
                strokeWidth: 0
                fillColor: Theme.withAlpha(cookieBtn.tint, cookieBtn.hovered ? 0.12 : 0)
                Behavior on fillColor {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durFastEffects }
                }
                PathPolyline { path: notifScope.cookieOuter }
            }

            // Track: full cookie ring, always visible.
            ShapePath {
                strokeWidth: 0
                fillColor: cookieBtn.trackColor
                fillRule: ShapePath.OddEvenFill
                PathPolyline { path: notifScope.cookieOuter }
                PathPolyline { path: notifScope.cookieInner }
            }

            // Remaining time: accent arc anchored at 12 o'clock, consumed
            // clockwise (angle 90 puts the conical gradient's origin at the
            // top; the arc then extends counter-clockwise for `remaining`).
            ShapePath {
                strokeWidth: 0
                fillRule: ShapePath.OddEvenFill
                fillGradient: ConicalGradient {
                    centerX: cookieBtn.width / 2
                    centerY: cookieBtn.height / 2
                    angle: 90
                    GradientStop { position: 0; color: cookieBtn.showProgress ? cookieBtn.ringColor : Theme.withAlpha(cookieBtn.ringColor, 0) }
                    GradientStop { position: cookieBtn.remaining; color: cookieBtn.showProgress ? cookieBtn.ringColor : Theme.withAlpha(cookieBtn.ringColor, 0) }
                    GradientStop { position: cookieBtn.remaining; color: Theme.withAlpha(cookieBtn.ringColor, 0) }
                    GradientStop { position: 1; color: Theme.withAlpha(cookieBtn.ringColor, 0) }
                }
                PathPolyline { path: notifScope.cookieOuter }
                PathPolyline { path: notifScope.cookieInner }
            }
        }

        Text {
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            anchors.centerIn: parent
            text: "✖"
            color: cookieBtn.hovered ? cookieBtn.tint : (cookieBtn.critical ? Theme.on_error_container : Theme.textSecondary)
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(13)
            font.weight: Font.Bold
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cookieBtn.clicked()
        }
    }

    // Merged from notifications/NotificationCard.qml — toast delegate.
    component NotifCard: Item {
    id: delegateRoot
    required property var modelData
    property real listWidth: 340
    property var n: null
    width: listWidth
    readonly property bool singleLineToast: cachedBody.length === 0
    property real cachedDelegateHeight: 0
    height: isDismissing ? cachedDelegateHeight : childrenRect.height
    clip: true

    property int timeoutMs: 5000
    readonly property int slideDir: notifScope.notifPos.endsWith("left") ? -1 : 1
    property int cachedUrgency: 1
    property string cachedSummary: ""
    property string cachedBody: ""
    property string cachedAppName: "Notification"
    property string cachedAppIcon: ""
    property string cachedImage: ""
    property real cachedTimeMs: 0
    property string cachedTimeLabel: "now"
    property var cachedActions: []
    property bool cachedHasInlineReply: false
    property string cachedInlinePlaceholder: ""
    property bool cachedResident: false
    Component.onCompleted: {
        try {
            n = modelData
            try { exitDir = slideDir } catch(e2) { }
            let t = n ? n.expireTimeout : -1
            let u = n ? n.urgency : NotificationUrgency.Normal
            cachedUrgency = u
            if (t > 0) {
                if (t >= 100) timeoutMs = t
                else timeoutMs = Math.round(t * 1000)
            } else if (t === 0) timeoutMs = 0
            else {
                if (u === NotificationUrgency.Critical) timeoutMs = 0
                else {
                    let dflt = 5000
                    try { dflt = Math.max(0, Math.min(30, Math.round(Theme.notifTimeout))) * 1000 } catch(e) { }
                    timeoutMs = dflt
                }
            }
            cachedSummary = n && n.summary ? n.summary : ""
            cachedBody = n && n.body ? n.body : ""
            cachedAppName = n && n.appName ? n.appName : "Notification"
            cachedAppIcon = n && n.appIcon ? n.appIcon : ""
            cachedImage = n && n.image ? n.image : ""
            cachedTimeMs = Date.now()
            cachedTimeLabel = "now"
            cachedActions = n && n.actions ? n.actions : []
            cachedHasInlineReply = n ? n.hasInlineReply : false
            cachedInlinePlaceholder = n ? n.inlineReplyPlaceholder : ""
            cachedResident = n ? n.resident : false
            if (timeoutMs > 0) { progressAnim.duration = timeoutMs; progressAnim.start() }
            Qt.callLater(() => { try { cachedDelegateHeight = childrenRect.height } catch(e) { } })
        } catch(e) { }
    }
    readonly property bool isBottom: notifScope.notifPos.startsWith("bottom")
    property bool entered: false
    property bool leaving: false
    property int exitDir: 1
    readonly property real targetOpacity: leaving ? 0 : entered ? 1 : 0
    readonly property real targetScale: leaving ? 0.94 : entered ? 1.0 : 0.92
    readonly property real baseSlideX: leaving ? 56 * exitDir : entered ? 0 : 32 * slideDir
    readonly property real baseSlideY: leaving ? 0 : entered ? 0 : (isBottom ? 14 : -14)
    readonly property real dragFade: {
        let d = Math.abs(dragProxy.x)
        if (d <= 0.5) return 1.0
        return Math.max(0.35, 1.0 - (d / Math.max(1, delegateRoot.width)) * 0.9)
    }
    property bool isDismissing: false
    // Caelestia toast motion (Notification.qml / Toasts.qml idioms):
    //  - enter/exit slides on the emphasized-decelerate curve (DefaultSpatial
    //    duration), fades on the effects curve, scale on the spatial curve
    //  - dismiss collapses the height on the spatial curve so the stack below
    //    closes the gap instead of jumping
    //  - stack siblings glide to their new row (Column re-layout) on the
    //    spatial curve — the ListView move/displaced equivalent
    Behavior on height { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
    Behavior on y { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial } }
    onIsDismissingChanged: {
        try { progressAnim.stop() } catch(e) { }
        if (isDismissing && cachedDelegateHeight === 0) {
            try { cachedDelegateHeight = childrenRect.height } catch(e) { }
        }
    }
    function armEntrance(): void {
        // Entrance stagger removed with the animation system
        // (delay was stackIndex * 0 = always 0). Instant by design.
        delegateRoot.entered = true
    }
    function requestDismiss(toExpire: bool, dir: int): void {
        if (delegateRoot.isDismissing || delegateRoot.leaving) return
        delegateRoot.exitDir = (dir === -1 || dir === 1) ? dir : delegateRoot.slideDir
        delegateRoot.leaving = true
        delegateRoot.isDismissing = true
        collapseTimer.toExpire = !!toExpire
        // Exit choreography: fade/slide out first (FastEffects), then
        // collapse the height (FastSpatial, same as the height Behavior
        // below). Durations collapse to 0 with animations off, preserving
        // the old instant dismiss.
        collapseTimer.interval = Theme.durFastEffects
        collapseTimer.restart()
    }
    Timer {
        id: collapseTimer
        repeat: false
        property bool toExpire: false
        onTriggered: {
            try { delegateRoot.cachedDelegateHeight = 0 } catch(e) { }
            finishTimer.toExpire = toExpire
            finishTimer.interval = Theme.durFastSpatial
            finishTimer.restart()
        }
    }
    Timer {
        id: finishTimer
        repeat: false
        property bool toExpire: false
        onTriggered: delegateRoot.safeClose(toExpire)
    }
    property real progress: 0

    function safeClose(expire) {
        if (!delegateRoot.n) return
        try {
            if (!delegateRoot.n.tracked) return
        } catch(e) { return }
        try {
            if (expire) delegateRoot.n.expire()
            else delegateRoot.n.dismiss()
        } catch(e) { }
    }

    function relativeTime(ms: real): string {
        try {
            let diff = Date.now() - ms
            if (diff < 0) diff = 0
            let m = Math.floor(diff / 60000)
            if (m < 1) return "now"
            if (m < 60) return m + "m ago"
            let h = Math.floor(m / 60)
            if (h < 24) return h + "h ago"
            let days = Math.floor(h / 24)
            if (days === 1) return "Yesterday"
            if (days < 7) return days + "d ago"
            return new Date(ms).toLocaleDateString()
        } catch (e) { return "now" }
    }
    // Resident/critical toasts can outlive a minute: keep the header
    // timestamp honest while the card is on screen.
    Timer {
        interval: 30000
        repeat: true
        running: delegateRoot.visible
        onTriggered: delegateRoot.cachedTimeLabel = delegateRoot.relativeTime(delegateRoot.cachedTimeMs)
    }

    Item {
        id: dragProxy
        x: 0
        y: 0
    }

    Rectangle {
        antialiasing: Theme.shapesAa
        id: card
        width: parent.width
        property real cachedHeight: 0
        readonly property bool isCritical: delegateRoot.cachedUrgency === NotificationUrgency.Critical
        implicitHeight: delegateRoot.isDismissing && cachedHeight > 0 ? cachedHeight : inner.implicitHeight + 26
        color: isCritical ? Theme.error_container : (Theme.bg)
        Connections {
            target: delegateRoot
            function onIsDismissingChanged() {
                if (delegateRoot.isDismissing && card.cachedHeight === 0) {
                    try { card.cachedHeight = inner.implicitHeight + 26 } catch(e) { }
                }
            }
        }
        border.color: isCritical ? Theme.errorColor : Theme.panelBorderColor
        border.width: 2
        radius: Theme.cornerRadius
        clip: true
        scale: entranceScale
        opacity: delegateRoot.targetOpacity * delegateRoot.dragFade
        transformOrigin: delegateRoot.slideDir < 0 ? Item.Left : Item.Right

        property real entranceScale: delegateRoot.targetScale
        readonly property real slideX: baseSlideX + dragProxy.x
        property real baseSlideX: delegateRoot.baseSlideX
        property real baseSlideY: delegateRoot.baseSlideY
        transform: Translate { x: card.slideX; y: card.baseSlideY }
        // Caelestia enter/exit motion, split by direction per M3 (enter:
        // emphasized decelerate + effects fade in; exit: emphasized
        // accelerate + fast effects fade out). Drag stays direct
        // (dragProxy.x has no Behavior); only the enter/exit offsets glide.
        Behavior on opacity {
            enabled: Theme.animationsEnabled
            NumberAnimation {
                duration: delegateRoot.leaving ? Theme.durFastEffects : Theme.durDefaultEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: delegateRoot.leaving ? Theme.curveFastEffects : Theme.curveDefaultEffects
            }
        }
        Behavior on scale { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
        Behavior on baseSlideX {
            enabled: Theme.animationsEnabled
            NumberAnimation {
                duration: delegateRoot.leaving ? Theme.durFastEffects : Theme.durDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: delegateRoot.leaving ? Theme.curveEmphasizedAccelerate : Theme.curveEmphasizedDecelerate
            }
        }
        Behavior on baseSlideY { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }

        HoverHandler { id: hover }
        property bool isHovered: hover.hovered
        onIsHoveredChanged: {
            if (card.isHovered) { if (progressAnim.running) progressAnim.pause() }
            else if (progressAnim.paused && !delegateRoot.isDismissing && !bgMouse.drag.active) progressAnim.resume()
        }

        NumberAnimation {
            id: progressAnim
            target: delegateRoot
            property: "progress"
            from: 0
            to: 1
            onFinished: delegateRoot.requestDismiss(true, delegateRoot.slideDir)
        }

        Component.onCompleted: {
            delegateRoot.armEntrance()
            Qt.callLater(() => { try { cachedHeight = inner.implicitHeight + 26 } catch(e) { } })
        }

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: delegateRoot.singleLineToast ? 7 : 10
            anchors.bottomMargin: delegateRoot.singleLineToast ? 7 : (10)
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                // Circular app avatar: icon clipped into a tonal circle,
                // first letter as fallback. Top-aligned with the app line.
                Rectangle {
                    id: iconSlot
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignTop
                    radius: width / 2
                    antialiasing: Theme.shapesAa
                    clip: true
                    color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, 0.16) : Theme.surface_container_highest
                    readonly property string slotSource: {
                        if (delegateRoot.cachedImage !== "") return delegateRoot.cachedImage
                        let ic = delegateRoot.cachedAppIcon
                        if (!ic || ic === "") return ""
                        if (ic.startsWith("/") || ic.startsWith("file://") || ic.startsWith("image://")) return ic
                        if (Quickshell.hasThemeIcon(ic)) return Quickshell.iconPath(ic)
                        let lc = ic.toLowerCase()
                        if (Quickshell.hasThemeIcon(lc)) return Quickshell.iconPath(lc)
                        return Quickshell.iconPath(ic)
                    }
                    property bool iconFailed: false
                    onSlotSourceChanged: iconFailed = false
                    Image {
                        anchors.fill: parent
                        source: iconSlot.slotSource
                        sourceSize.width: 80
                        sourceSize.height: 80
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: true
                        visible: !iconSlot.iconFailed && iconSlot.slotSource !== ""
                        onStatusChanged: if (status === Image.Error) iconSlot.iconFailed = true
                    }
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        anchors.centerIn: parent
                        visible: iconSlot.iconFailed || iconSlot.slotSource === ""
                        text: (delegateRoot.cachedAppName || "?").charAt(0).toUpperCase()
                        color: card.isCritical ? Theme.on_error_container : Theme.textSecondary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(16)
                        font.weight: Font.Medium
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    // Reserve the top-right corner for the close cookie.
                    Layout.rightMargin: 24
                    spacing: 2
                    // Header line: app name · relative time (screenshot).
                    Row {
                        Layout.fillWidth: true
                        spacing: 5
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            width: Math.min(implicitWidth, Math.max(0, parent.width - appDot.implicitWidth - appTime.implicitWidth - 10))
                            text: delegateRoot.cachedAppName
                            color: card.isCritical ? Theme.on_error_container : Theme.textPrimary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }
                        Text {
                            id: appDot
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            text: "·"
                            color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, 0.7) : Theme.textMuted
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(12)
                        }
                        Text {
                            id: appTime
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            text: delegateRoot.cachedTimeLabel
                            color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, 0.7) : Theme.textMuted
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.Medium
                        }
                    }
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        visible: delegateRoot.cachedSummary.length > 0
                        Layout.fillWidth: true
                        text: delegateRoot.cachedSummary
                        color: card.isCritical ? Theme.on_error_container : Theme.textPrimary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(14)
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        Layout.fillWidth: true
                        visible: delegateRoot.cachedBody.length > 0
                        text: delegateRoot.cachedBody
                        color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, 0.85) : Theme.textSecondary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(13)
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        // STABILITY: untrusted notification bodies must not
                        // parse as markup (was RichText when body contained
                        // angle brackets — layout crash/XSS vector).
                        textFormat: Text.PlainText
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: delegateRoot.cachedActions.length > 0

                Repeater {
                    model: delegateRoot.cachedActions
                    delegate: Rectangle {
                        id: actBtn
                        required property var modelData
                        property var act: modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, actMouse.containsMouse ? 0.28 : 0.18)
                                              : actMouse.containsMouse ? Theme.withAlpha(Theme.textPrimary, 0.14) : Theme.withAlpha(Theme.textPrimary, 0.08)
                        border.color: Theme.divider
                        border.width: 1
                        radius: Theme.cornerRadiusSmall

                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            anchors.centerIn: parent
                            text: actBtn.act ? actBtn.act.text : ""
                            color: card.isCritical ? Theme.on_error_container : Theme.textPrimary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                            width: parent.width - 16
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                try {
                                    if (actBtn.act) actBtn.act.invoke()
                                } catch(e) { console.error(e) }
                                if (!delegateRoot.cachedResident) {
                                    delegateRoot.requestDismiss(false, delegateRoot.slideDir)
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                visible: delegateRoot.cachedHasInlineReply
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    antialiasing: Theme.shapesAa
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, 0.12) : Theme.withAlpha(Theme.textPrimary, 0.08)
                    border.color: replyInput.activeFocus ? (card.isCritical ? Theme.on_error_container : Theme.accent) : Theme.divider
                    border.width: 1
                    radius: Theme.cornerRadiusSmall

                    TextInput {
                        id: replyInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        color: card.isCritical ? Theme.on_error_container : Theme.textPrimary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(12)
                        clip: true
                        selectByMouse: true
                        property string placeholder: delegateRoot.cachedInlinePlaceholder
                        Keys.onReturnPressed: {
                            if (text.length > 0 && delegateRoot.n) {
                                try { delegateRoot.n.sendInlineReply(text) } catch(e) { }
                                delegateRoot.requestDismiss(false, delegateRoot.slideDir)
                            }
                        }
                    }
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: replyInput.placeholder.length > 0 ? replyInput.placeholder : "Antworten…"
                        color: card.isCritical ? Theme.withAlpha(Theme.on_error_container, 0.7) : Theme.textMuted
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(12)
                        visible: replyInput.text.length === 0 && !replyInput.activeFocus
                    }
                }
                Rectangle {
                    antialiasing: Theme.shapesAa
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: Theme.cornerRadiusSmall
                    color: card.isCritical ? Theme.on_error_container : Theme.textPrimary
                    Text {
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                        anchors.centerIn: parent
                        text: "↩"
                        color: card.isCritical ? Theme.error_container : Theme.bg
                        font.pixelSize: Theme.fs(14)
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (replyInput.text.length > 0 && delegateRoot.n) {
                                try { delegateRoot.n.sendInlineReply(replyInput.text) } catch(e) { }
                                delegateRoot.requestDismiss(false, delegateRoot.slideDir)
                            }
                        }
                    }
                }
            }
        }

        CloseCookie {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 5
            anchors.rightMargin: 5
            critical: card.isCritical
            showProgress: delegateRoot.timeoutMs > 0
            remaining: delegateRoot.timeoutMs > 0 ? Math.max(0, Math.min(1, 1 - delegateRoot.progress)) : 1
            onClicked: {
                if (delegateRoot.isDismissing) return
                delegateRoot.requestDismiss(false, delegateRoot.slideDir)
            }
        }


        MouseArea {
            id: bgMouse
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            enabled: !delegateRoot.leaving
            drag.target: dragProxy
            drag.axis: Drag.XAxis
            drag.minimumX: -delegateRoot.width
            drag.maximumX: delegateRoot.width
            drag.smoothed: false
            hoverEnabled: false
            onPressed: {
                if ((mouse.buttons & Qt.LeftButton) || (mouse.buttons & Qt.RightButton)) {
                    if (progressAnim.running) progressAnim.pause()
                }
            }
            onReleased: {
                let dx = 0
                try { dx = dragProxy.x } catch(e) { dx = 0 }
                if (Math.abs(dx) > 90) {
                    delegateRoot.requestDismiss(false, dx >= 0 ? 1 : -1)
                } else {
                    try { dragProxy.x = 0 } catch(e) { }
                    if (!delegateRoot.isDismissing && !card.isHovered && delegateRoot.timeoutMs > 0 && progressAnim.paused) progressAnim.resume()
                }
            }
            onCanceled: {
                try { dragProxy.x = 0 } catch(e) { }
                if (!delegateRoot.isDismissing && !card.isHovered && delegateRoot.timeoutMs > 0 && progressAnim.paused) progressAnim.resume()
            }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    delegateRoot.requestDismiss(false, delegateRoot.slideDir)
                    return
                }
                try { if (Math.abs(dragProxy.x) > 8) return } catch(e) { }
                delegateRoot.requestDismiss(false, delegateRoot.slideDir)
            }
        }
    }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: modelData.name === (notifScope.targetScreen ? notifScope.targetScreen.name : Theme.primaryScreenName)

            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "notifications"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"

            anchors { top: true; left: true; right: true; bottom: true }

            mask: Region { item: listCol }

            Column {
                id: listCol
                width: notifScope.cardWidth
                x: notifScope.notifLeft
                    ? notifScope.edgeGap + (notifScope.barPos === "left" ? notifScope.barT : 0)
                    : notifScope.notifCenter
                    ? (parent.width - notifScope.cardWidth) / 2
                    : parent.width - notifScope.cardWidth - notifScope.edgeGap - (notifScope.barPos === "right" ? notifScope.barT : 0)
                y: notifScope.notifTop
                    ? notifScope.edgeGap + (notifScope.barPos === "top" ? notifScope.barT : 0)
                    : parent.height - height - notifScope.edgeGap - (notifScope.barPos === "bottom" ? notifScope.barT : 0)
                spacing: 8


                Repeater {
                    model: notifScope.notifServer ? notifScope.notifServer.trackedNotifications : []
                    delegate: NotifCard {
                        listWidth: listCol.width
                    }
                }

            }
        }
    }
}
