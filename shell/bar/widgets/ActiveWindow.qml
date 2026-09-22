pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import M3Shapes
import "../../../style/themes"
import "../../../backend/services"

Item {
    id: root
    signal clicked()
    property bool vertical: false
    // Label-toggle convention (see BarModule): right-click calls this when
    // present. Uses the generic Theme label store so future modules can copy
    // this pattern with zero BarModule changes.
    function toggleLabel(): void { Theme.toggleBarLabel("activewindow") }
    implicitWidth: vertical ? col.implicitWidth + 12 : row.implicitWidth + 16
    implicitHeight: vertical ? col.implicitHeight + 10 : row.implicitHeight + 10

    readonly property string winAppId: {
        try { return HyprlandService.focusedAppId || "" } catch (e) { return "" }
    }
    readonly property bool glyphIcons: Theme.glyphWindowIcons
    readonly property bool iconBgVisible: Theme.iconBackground
    readonly property real iconBgSize: Math.max(18, Math.min(28, Theme.barThickness - 6))
    // M3 expressive shape pool for the icon background. Circle is not in the
    // pool: it is the resting shape, so a pick landing on it would read as
    // no shape at all.
    readonly property var shapeChoices: [
        MaterialShape.Square, MaterialShape.Slanted, MaterialShape.Pill,
        MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny,
        MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
        MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided,
        MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf,
        MaterialShape.Clover8Leaf
    ]
    property int iconShape: MaterialShape.Circle
    // Random shape per focused app, never the same pick twice in a row.
    function pickShape(): void {
        const list = root.shapeChoices
        if (list.length === 0) return
        let next = list[Math.floor(Math.random() * list.length)]
        if (list.length > 1 && next === root.iconShape)
            next = list[(list.indexOf(next) + 1) % list.length]
        root.iconShape = next
    }
    // PERF/STABILITY: resolved imperatively (same pattern as
    // Workspaces.WindowIcon and MediaPlayerCard): Theme.appIconFor() and
    // Theme.desktopEntryFor() memoise into Theme's caches, so calling them
    // from a binding would write a property the binding reads and trip a
    // binding loop.
    property string winIcon: ""
    property string winGlyph: ""
    property string winAppName: ""
    function resolveWindowMeta(): void {
        const id = winAppId
        let icon = ""
        let glyph = ""
        let name = id
        try {
            if (root.glyphIcons) {
                glyph = Theme.appGlyphFor(id, "desktop_windows")
            } else if (id.length > 0) {
                let p = Theme.appIconFor(id)
                if (p && p.length > 0 && p !== Quickshell.iconPath("application-x-executable")) icon = p
            }
        } catch (e) { }
        try {
            if (id.length > 0) {
                let e = Theme.desktopEntryFor(id)
                if (e && e.name && ("" + e.name).trim().length > 0) name = "" + e.name
            }
        } catch (e) { }
        if (winIcon !== icon) winIcon = icon
        if (winGlyph !== glyph) winGlyph = glyph
        if (winAppName !== name) winAppName = name
    }
    onWinAppIdChanged: {
        resolveWindowMeta()
        pickShape()
    }
    Component.onCompleted: {
        resolveWindowMeta()
        pickShape()
    }
    Connections {
        target: Theme
        function onAppsRevChanged() { root.resolveWindowMeta() }
        function onGlyphWindowIconsChanged() { root.resolveWindowMeta() }
    }
    // Title -> app name -> "Desktop". Newlines/tabs are collapsed because
    // xdg-toplevel titles may contain them and the bar label is one line.
    readonly property string winTitle: {
        try {
            let t = ("" + (HyprlandService.focusedTitle || "")).replace(/[\r\n\t]+/g, " ").trim()
            if (t.length > 0) return t
        } catch (e) { }
        if (winAppName.length > 0) return winAppName
        return "Desktop"
    }
    // PERF: single hover color shared by the icon and the title.
    readonly property color _fg: mouse.containsMouse ? Theme.primary : Theme.textPrimary

    // Window icon with an optional random M3 expressive shape behind it.
    component IconBox: Item {
        id: iconBox

        implicitWidth: root.iconBgVisible ? root.iconBgSize : 18
        implicitHeight: implicitWidth

        MaterialShape {
            anchors.centerIn: parent
            visible: root.iconBgVisible
            width: root.iconBgSize
            height: root.iconBgSize
            implicitSize: root.iconBgSize
            color: Theme.accent
            shape: root.iconShape
            animationDuration: Theme.durDefaultSpatial
            animationEasing.type: Easing.BezierSpline
            animationEasing.bezierCurve: Theme.curveDefaultSpatial

            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
        }
        IconImage {
            anchors.centerIn: parent
            visible: !root.glyphIcons && root.winIcon !== ""
            source: root.winIcon
            width: 18
            height: 18
            asynchronous: true
            implicitSize: Qt.size(18, 18)
        }
        Text {
            anchors.centerIn: parent
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            visible: root.glyphIcons
            text: root.winGlyph
            font.family: Theme.glyphFontFamily
            font.pixelSize: Theme.fs(18)
            color: root.iconBgVisible ? Theme.onAccent : root._fg
        }
        Text {
            anchors.centerIn: parent
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            visible: !root.glyphIcons && root.winIcon === ""
            text: "󰍹"
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(15)
            font.weight: Theme.textBold ? Font.Bold : Font.Normal
            color: root.iconBgVisible ? Theme.onAccent : root._fg
        }
    }

    RowLayout {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        IconBox {
            Layout.alignment: Qt.AlignVCenter
        }
        Text {
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            readonly property bool labelVisible: Theme.barLabelVisible("activewindow")
            opacity: labelVisible ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                enabled: Theme.animationsEnabled
                NumberAnimation { duration: Theme.durSmall; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
            }
            text: root.winTitle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.weight: Theme.barTextWeight
            color: mouse.containsMouse ? Theme.primary : Theme.textSecondary
            elide: Text.ElideRight
            Layout.maximumWidth: 180
            Layout.alignment: Qt.AlignVCenter
        }
    }
    ColumnLayout {
        id: col
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 9
        IconBox {
            Layout.alignment: Qt.AlignHCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) root.toggleLabel()
            else root.clicked()
        }
    }
}
