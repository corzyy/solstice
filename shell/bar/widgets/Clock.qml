import QtQuick
import Quickshell
import M3Shapes
import "../../../style/themes"
import "../../../backend/services"

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

    // Circle is not in the pool: it is the resting shape, so a pick landing
    // on it would read as no shape at all. Declared before iconBgVisible so
    // the init-time onIconBgVisibleChanged pick already sees the list.
    readonly property var shapeChoices: [
        MaterialShape.Square, MaterialShape.Slanted, MaterialShape.Pill,
        MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny,
        MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
        MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided,
        MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf,
        MaterialShape.Clover8Leaf
    ]
    // Optional M3 expressive shape behind the clock icon: same treatment as
    // the active window's icon box (random pick from the expressive pool,
    // accent fill, on-accent glyph).
    readonly property bool iconBgVisible: Theme.clockIcon && Theme.clockIconBackground
    // Same formula as ActiveWindow, capped to the clock's 24px content row.
    readonly property real iconBgSize: Math.max(18, Math.min(24, Theme.barThickness - 6))
    property int iconShape: MaterialShape.Circle
    // Random shape, never the same pick twice in a row.
    function pickShape(): void {
        const list = root.shapeChoices
        if (list.length === 0) return
        let next = list[Math.floor(Math.random() * list.length)]
        if (list.length > 1 && next === root.iconShape)
            next = list[(list.indexOf(next) + 1) % list.length]
        root.iconShape = next
    }
    Component.onCompleted: if (iconBgVisible) pickShape()
    onIconBgVisibleChanged: if (iconBgVisible) pickShape()

    // Geteilte Text-Basis (ein Pfad für alle 5 Labels statt kopiertem Boilerplate).
    component ClockLabel: Text {
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        font.family: Theme.fontFamily
    }

    // Clock icon (Caelestia's Material Symbols calendar_month) with an
    // optional expressive shape background, mirroring ActiveWindow.IconBox.
    component ClockIcon: Item {
        id: iconBox
        implicitWidth: root.iconBgVisible ? root.iconBgSize : iconGlyph.implicitWidth
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
        ClockLabel {
            id: iconGlyph
            anchors.centerIn: parent
            text: "calendar_month"
            color: root.iconBgVisible ? Theme.onAccent : root._hoverColor
            font.family: Theme.glyphFontFamily
            font.pixelSize: root.iconBgVisible ? Theme.fs(18) : Theme.fs(14)
        }
    }

    // DND indicator (moved here from the control center bar module): sits at
    // the trailing edge of the module and only shows while Do Not Disturb
    // is on.
    component DndIcon: ClockLabel {
        text: "󰂛"
        visible: Theme.dndEnabled
        color: root._hoverColor
        font.family: Theme.iconFontFamily
        font.pixelSize: Theme.fs(14)
    }

    Row {
        id: row
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: 8
        ClockIcon {
            visible: Theme.clockIcon
            anchors.verticalCenter: parent.verticalCenter
        }
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
        DndIcon { anchors.verticalCenter: parent.verticalCenter }
    }
    Column {
        id: vCol
        visible: root.vertical
        anchors.centerIn: parent
        spacing: 2
        ClockIcon {
            visible: Theme.clockIcon
            anchors.horizontalCenter: parent.horizontalCenter
        }
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
        DndIcon { anchors.horizontalCenter: parent.horizontalCenter }
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
