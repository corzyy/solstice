pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../themes"
import ".."

// Date & Time — system clock via systemd-timedated (timedatectl), reachable
// from Setup. Reads timezone/NTP state and applies changes directly as the
// user; the required polkit prompt is shown by the shell's resident agent
// (overlays/Polkit.qml). Where supported, only the date or the time field
// needs editing — Apply sends both.
NexusControls.PageBase {
    id: root
    title: "Date & Time"

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ---- state -----------------------------------------------------------
    property string zone: ""
    property bool ntp: false
    property bool ntpSynced: false
    property var zones: []
    property string dateField: ""
    property string timeField: ""
    property string message: ""
    readonly property string ntpSubtext: {
        if (!root.ntp) return "Off — the clock is set manually"
        return root.ntpSynced ? "Network time synchronization active"
                              : "Enabled — waiting for synchronization"
    }

    function refreshFields(): void {
        root.dateField = Qt.formatDate(clock.date, "yyyy-MM-dd")
        root.timeField = Qt.formatTime(clock.date, "HH:mm:ss")
    }
    function refreshStatus(): void {
        if (!statusProc.running) statusProc.running = true
    }
    function loadZones(): void {
        if (root.zones.length === 0 && !zonesProc.running) zonesProc.running = true
    }
    function setNtp(on: bool): void {
        root.ntp = on
        root.message = ""
        ntpProc.command = ["timedatectl", "set-ntp", on ? "true" : "false"]
        if (!ntpProc.running) ntpProc.running = true
    }
    function setZone(z: string): void {
        if (z.length === 0 || z === root.zone) return
        root.zone = z
        root.message = ""
        zoneProc.command = ["timedatectl", "set-timezone", z]
        if (!zoneProc.running) zoneProc.running = true
    }
    function applyDateTime(): void {
        let d = (root.dateField || "").trim()
        let t = (root.timeField || "").trim()
        if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) {
            root.message = "Date must be YYYY-MM-DD."
            return
        }
        if (!/^\d{2}:\d{2}(:\d{2})?$/.test(t)) {
            root.message = "Time must be HH:MM or HH:MM:SS."
            return
        }
        if (t.length === 5) t += ":00"
        root.message = ""
        // timedated rejects set-time while NTP is on, so drop it first.
        timeProc.command = ["bash", "-c",
            "timedatectl set-ntp false && timedatectl set-time \"" + d + " " + t + "\""]
        if (!timeProc.running) timeProc.running = true
    }

    Component.onCompleted: {
        root.refreshFields()
        root.refreshStatus()
    }
    onPageEntered: {
        root.refreshFields()
        root.refreshStatus()
    }

    // ---- processes -------------------------------------------------------
    Process {
        id: statusProc
        command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP", "-p", "NTPSynchronized", "--value"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = (text || "").split("\n").map(s => s.trim())
                if (lines.length < 3) return
                root.zone = lines[0]
                root.ntp = lines[1] === "yes"
                root.ntpSynced = lines[2] === "yes"
            }
        }
    }
    Process {
        id: zonesProc
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (text || "").trim()
                root.zones = out.length === 0 ? []
                    : out.split("\n").map(s => s.trim()).filter(s => s.length > 0)
            }
        }
    }
    Process {
        id: ntpProc
        command: ["timedatectl", "set-ntp", "false"]
        stderr: StdioCollector {
            onStreamFinished: {
                let e = (text || "").trim()
                if (e.length > 0) root.message = e
            }
        }
        onExited: (code, status) => root.refreshStatus()
    }
    Process {
        id: zoneProc
        command: ["timedatectl", "set-timezone", "UTC"]
        stderr: StdioCollector {
            onStreamFinished: {
                let e = (text || "").trim()
                if (e.length > 0) root.message = e
            }
        }
        onExited: (code, status) => root.refreshStatus()
    }
    Process {
        id: timeProc
        command: ["bash", "-c", "true"]
        stderr: StdioCollector {
            onStreamFinished: {
                let e = (text || "").trim()
                if (e.length > 0) root.message = e
            }
        }
        onExited: (code, status) => {
            if (code === 0) root.refreshFields()
            root.refreshStatus()
        }
    }

    // ---- clock -----------------------------------------------------------
    NexusControls.SectionHeader { first: true; text: "Clock" }
    NexusControls.ToggleRow {
        first: true
        text: "Automatic date & time"
        subtext: root.ntpSubtext
        checked: root.ntp
        onToggled: n => root.setNtp(n)
    }
    NexusControls.InfoRow {
        last: true
        icon: "󰃰"
        label: "Current date & time"
        value: Qt.formatDateTime(clock.date, "ddd, yyyy-MM-dd HH:mm:ss")
        valueMaxWidth: Math.round(width * 0.5)
    }

    // ---- set date & time -------------------------------------------------
    NexusControls.SectionHeader { text: "Set date & time" }
    NexusControls.TextFieldRow {
        first: true
        label: "Date"
        subtext: "YYYY-MM-DD"
        placeholder: "2026-09-19"
        value: root.dateField
        onValueEdited: v => root.dateField = v
        onEditingFinished: v => root.dateField = v
    }
    NexusControls.TextFieldRow {
        last: true
        label: "Time"
        subtext: "HH:MM:SS, 24-hour"
        placeholder: "16:30:00"
        value: root.timeField
        onValueEdited: v => root.timeField = v
        onEditingFinished: v => root.timeField = v
    }
    Item {
        width: parent.width
        implicitHeight: applyBtn.height + 8
        NexusControls.TextButton {
            id: applyBtn
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Set date & time"
            onClicked: root.applyDateTime()
        }
    }
    NexusControls.Note {
        visible: root.message.length > 0
        color: Theme.error
        text: root.message
    }
    NexusControls.Note {
        visible: root.message.length === 0
        text: "Setting the date or time turns automatic synchronization off; re-enable it once the clock is correct."
    }

    // ---- time zone -------------------------------------------------------
    NexusControls.SectionHeader { text: "Time zone" }
    NexusControls.DropdownRow {
        first: true
        last: true
        label: "Time zone"
        subtext: "IANA zone name, e.g. Europe/Berlin"
        options: root.zones
        current: root.zone
        onOpenChanged: if (open) root.loadZones()
        onPicked: v => root.setZone(v)
    }
}
