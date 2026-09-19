import QtQuick
import Quickshell
import "../../themes"
import "../../services"

Item {
    id: root
    signal clicked()
    property bool vertical: false
    implicitWidth: vertical ? 28 : row.implicitWidth + 14
    implicitHeight: vertical ? vCol.implicitHeight + 10 : 24
    // NOTE: `opacity: enabled ? ...` + its Behavior removed — `enabled` is
    // never set false, so this was a permanent 1.0 with a dead animation.

    readonly property string clockFmt: Theme.clockFormat
    readonly property bool isTimeOnly: clockFmt === "timeOnly"
    readonly property bool isDate: clockFmt === "date"

    // Ordinal suffix for the date format ("8th May"): 1st 2nd 3rd 21st…,
    // teens (11th 12th 13th) always "th".
    function ordinalSuffix(d: int): string {
        if (d % 100 >= 11 && d % 100 <= 13) return "th"
        switch (d % 10) {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    // Label-toggle convention: BarModule right-click calls this when present.
    // New label-capable modules just add an equivalent toggleLabel().
    function toggleLabel(): void { Theme.toggleClockFormat() }

    SystemClock { id: c; precision: SystemClock.Minutes }

    // PERF: 5x Qt.formatDateTime ran in BOTH orientations (hidden branch still
    // bound). Cache once per minute; hidden branch reads "" (no format call).
    readonly property bool _showDay: !isTimeOnly
    readonly property int _dayNum: c.date.getDate()
    readonly property string _dayStr: {
        if (vertical || !_showDay) return ""
        if (clockFmt === "short") return c.date.toLocaleDateString(I18n.formatLocale, "ddd")
        if (clockFmt === "date") return I18n.location === "DE"
            ? c.date.toLocaleDateString(I18n.formatLocale, I18n.monthDayFormat)
            : _dayNum + ordinalSuffix(_dayNum) + " " + c.date.toLocaleDateString(I18n.formatLocale, "MMM")
        return c.date.toLocaleDateString(I18n.formatLocale, "dddd")
    }
    readonly property string _timeStr: !vertical ? Qt.formatDateTime(c.date, "HH:mm") : ""
    readonly property string _hhStr: vertical ? Qt.formatDateTime(c.date, "HH") : ""
    readonly property string _mmStr: vertical ? Qt.formatDateTime(c.date, "mm") : ""
    readonly property string _dddStr: (vertical && _showDay && !isDate) ? c.date.toLocaleDateString(I18n.formatLocale, "ddd") : ""
    readonly property string _vDayStr: (vertical && isDate) ? (_dayNum + ordinalSuffix(_dayNum)) : ""
    readonly property string _vMonStr: (vertical && isDate) ? c.date.toLocaleDateString(I18n.formatLocale, "MMM") : ""
    readonly property color _hoverColor: mouse.containsMouse ? Theme.primary : Theme.textPrimary
    readonly property color _dimColor: mouse.containsMouse ? Theme.primary : Theme.textMuted

    // Geteilte Text-Basis (ein Pfad für alle 5 Labels statt kopiertem Boilerplate).
    component ClockLabel: Text {
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        font.family: Theme.fontFamily
    }

    Row {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        ClockLabel {
            visible: !root.isTimeOnly
            text: root._dayStr
            color: root._hoverColor
            font.pixelSize: Theme.fs(13); font.weight: Theme.textBold ? Font.DemiBold : Theme.barTextWeight
            anchors.verticalCenter: parent.verticalCenter
            opacity: visible ? 1 : 0
            width: visible ? implicitWidth : 0
        }
        ClockLabel {
            text: root._timeStr
            color: root._hoverColor
            font.pixelSize: Theme.fs(13); font.weight: Theme.textBold ? Font.DemiBold : Theme.barTextWeight
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Column {
        id: vCol
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 2
        ClockLabel {
            text: root._hhStr
            color: root._hoverColor
            font.pixelSize: Theme.fs(13); font.weight: Theme.textBold ? Font.DemiBold : Theme.barTextWeight
            anchors.horizontalCenter: parent.horizontalCenter
        }
        ClockLabel {
            text: root._mmStr
            color: root._hoverColor
            font.pixelSize: Theme.fs(13); font.weight: Theme.textBold ? Font.DemiBold : Theme.barTextWeight
            anchors.horizontalCenter: parent.horizontalCenter
        }
        ClockLabel {
            visible: !root.isTimeOnly && !root.isDate
            text: root._dddStr
            color: root._dimColor
            font.pixelSize: Theme.fs(10); font.weight: Theme.barTextWeight
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: visible ? 0.85 : 0
            height: visible ? implicitHeight : 0
        }
        ClockLabel {
            visible: root.isDate
            text: root._vDayStr
            color: root._dimColor
            font.pixelSize: Theme.fs(10); font.weight: Theme.barTextWeight
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: visible ? 0.85 : 0
            height: visible ? implicitHeight : 0
        }
        ClockLabel {
            visible: root.isDate
            text: root._vMonStr
            color: root._dimColor
            font.pixelSize: Theme.fs(10); font.weight: Theme.barTextWeight
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: visible ? 0.85 : 0
            height: visible ? implicitHeight : 0
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) root.toggleLabel()
            else root.clicked()
        }
    }
}
