import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../themes"
import "../../services"

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
        try { return UmbrielService.focusedAppId || "" } catch (e) { return "" }
    }
    readonly property string winIcon: {
        Theme.appsRev
        try {
            if (winAppId.length > 0) {
                let p = Theme.appIconFor(winAppId)
                if (p && p.length > 0 && p !== Quickshell.iconPath("application-x-executable")) return p
            }
        } catch (e) { }
        return ""
    }
    readonly property string winAppName: {
        Theme.appsRev
        try {
            if (winAppId.length > 0) {
                let e = Theme.desktopEntryFor(winAppId)
                if (e && e.name && ("" + e.name).trim().length > 0) return "" + e.name
            }
        } catch (e) { }
        return winAppId
    }
    // Title -> app name -> "Desktop". Newlines/tabs are collapsed because
    // xdg-toplevel titles may contain them and the bar label is one line.
    readonly property string winTitle: {
        try {
            let t = ("" + (UmbrielService.focusedTitle || "")).replace(/[\r\n\t]+/g, " ").trim()
            if (t.length > 0) return t
        } catch (e) { }
        if (winAppName.length > 0) return winAppName
        return "Desktop"
    }
    // PERF: single hover color + orientation-gated icon source (hidden
    // IconImage was still fetching/decoding). Fixed 18px decode (was 36px
    // for 18px display = 4x pixels per icon).
    readonly property color _fg: mouse.containsMouse ? Theme.primary : Theme.textPrimary
    readonly property string _rowIcon: vertical ? "" : winIcon
    readonly property string _colIcon: vertical ? winIcon : ""

    RowLayout {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        IconImage {
            visible: root._rowIcon !== ""
            source: root._rowIcon
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
            implicitSize: Qt.size(18, 18)
        }
        Text {
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            visible: root.winIcon === ""
            text: "󰍹"
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(15)
            font.weight: Theme.textBold ? Font.Bold : Font.Normal
            color: root._fg
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
            font.pixelSize: Theme.fs(12)
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
        IconImage {
            visible: root._colIcon !== ""
            source: root._colIcon
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignHCenter
            asynchronous: true
            implicitSize: Qt.size(18, 18)
        }
        Text {
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            visible: root.winIcon === ""
            text: "󰍹"
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(14)
            font.weight: Theme.textBold ? Font.Bold : Font.Normal
            color: mouse.containsMouse ? Theme.primary : Theme.textPrimary
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
