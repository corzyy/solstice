pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../../../themes"
import ".."

NexusControls.PageBase {
    id: root
    title: "Calendar"

    NexusControls.SectionHeader { first: true; text: "Notifications Side" }
    Row {
        width: parent.width
        spacing: 8
        Repeater {
            model: [
                { id: "left", label: "Left" },
                { id: "right", label: "Right" }
            ]
            delegate: NexusControls.PreviewTile {
                required property var modelData
                readonly property string sideId: modelData.id
                readonly property bool isCurrent: (Theme.calendarNotifLeft ? "left" : "right") === sideId
                // First mini-pane shows notifications when sideId is left.
                readonly property bool notifFirst: sideId === "left"
                width: (parent.width - 8) / 2
                height: 88
                selected: isCurrent
                label: modelData.label
                onClicked: Theme.setCalendarNotifSide(sideId)
                Rectangle {
                        antialiasing: Theme.shapesAa
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 66
                        height: 38
                        radius: 2
                        color: "transparent"
                        border.color: isCurrent ? Theme.accent : Theme.divider
                        border.width: 1
                        Row {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4
                            Rectangle {
                                antialiasing: Theme.shapesAa
                                width: (parent.width - 4) / 2
                                height: parent.height
                                color: Theme.withAlpha(Theme.textPrimary, 0.06)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    visible: notifFirst
                                    Repeater {
                                        model: [14, 10, 12]
                                        delegate: Rectangle {
                                            required property var modelData
                                            antialiasing: Theme.shapesAa
                                            width: modelData
                                            height: 2
                                            color: Theme.textMuted
                                        }
                                    }
                                }
                                Grid {
                                    anchors.centerIn: parent
                                    columns: 3
                                    spacing: 2
                                    visible: !notifFirst
                                    Repeater {
                                        model: [0, 0, 0, 0, 1, 0]
                                        delegate: Rectangle {
                                            required property var modelData
                                            antialiasing: Theme.shapesAa
                                            width: 4
                                            height: 4
                                            color: modelData === 1 ? Theme.accent : Theme.textMuted
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                antialiasing: Theme.shapesAa
                                width: (parent.width - 4) / 2
                                height: parent.height
                                color: Theme.withAlpha(Theme.textPrimary, 0.06)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    visible: !notifFirst
                                    Repeater {
                                        model: [12, 14, 10]
                                        delegate: Rectangle {
                                            required property var modelData
                                            antialiasing: Theme.shapesAa
                                            width: modelData
                                            height: 2
                                            color: Theme.textMuted
                                        }
                                    }
                                }
                                Grid {
                                    anchors.centerIn: parent
                                    columns: 3
                                    spacing: 2
                                    visible: notifFirst
                                    Repeater {
                                        model: [0, 0, 0, 0, 1, 0]
                                        delegate: Rectangle {
                                            required property var modelData
                                            antialiasing: Theme.shapesAa
                                            width: 4
                                            height: 4
                                            color: modelData === 1 ? Theme.accent : Theme.textMuted
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    NexusControls.SectionHeader { text: "Calendar" }
    NexusControls.DropdownRow {
        first: true
        last: true
        label: "Week Starts"
        options: ["sunday", "monday"]
        current: calWeekStart.currentName
        onPicked: v => calWeekStart.setStart(v)
    }

    Process { id: calProc; command: ["bash", "-c", "echo"]; stdout: StdioCollector { } }
    QtObject {
        id: calWeekStart
        property string currentName: "sunday"
        function setStart(v) {
            if (v !== "sunday" && v !== "monday") return
            currentName = v
            calProc.command = ["bash", "-c", "f=~/.config/quickshell/jhqs/config/calendar.json; mkdir -p \"$(dirname \"$f\")\"; [ -f \"$f\" ] || echo '{ }' > \"$f\"; jq '.weekStartDay = \"" + v + "\"' \"$f\" > /tmp/jhqs-cal.json && mv /tmp/jhqs-cal.json \"$f\""]
            if (!calProc.running) calProc.running = true
        }
    }
    Process {
        id: calFetchProc
        command: ["bash", "-c", "jq -r '.weekStartDay // \"sunday\"' ~/.config/quickshell/jhqs/config/calendar.json 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = ((text || "").trim().toLowerCase())
                calWeekStart.currentName = (o === "monday") ? "monday" : "sunday"
            }
        }
    }
    Component.onCompleted: Qt.callLater(() => { if (!calFetchProc.running) calFetchProc.running = true })
}
