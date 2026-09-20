pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import "../../../services"
import "../../../ui"
import ".."

// Android 17 Settings — Bluetooth.
// Power switch, connected / paired / available device cards with battery,
// pin-for-auto-reconnect and forget, discovery driven by the service.
NexusControls.PageBase {
    id: root
    title: "Bluetooth"

    property bool pageVisible: false
    // Discovery only runs while this page is the shown one.
    onPageEntered: {
        root.pageVisible = true
        BluetoothService.setScanning(true)
    }
    onPageLeft: {
        root.pageVisible = false
        BluetoothService.setScanning(false)
    }

    readonly property var connectedDevs: BluetoothService.connectedDevs
    readonly property var pairedDevs: BluetoothService.pairedDevs
    readonly property var availDevs: BluetoothService.availDevs
    readonly property bool availVisible: BluetoothService.btScanning && root.availDevs.length > 0
    readonly property bool anyDevices: root.connectedDevs.length > 0 || root.pairedDevs.length > 0 || root.availVisible
    readonly property string statusText: {
        if (!BluetoothService.btReady) return "Loading…"
        if (!BluetoothService.btAvailable) return "No adapter"
        if (!BluetoothService.btActive) return "Off"
        if (BluetoothService.btScanning) return "Scanning…"
        if (root.connectedDevs.length > 0) return root.connectedDevs.length + (root.connectedDevs.length === 1 ? " device connected" : " devices connected")
        return "On"
    }
    readonly property string emptyText: {
        if (!BluetoothService.btReady) return "Loading Bluetooth…"
        if (!BluetoothService.btAvailable) return "No Bluetooth adapter found."
        if (!BluetoothService.btActive) return "Turn Bluetooth on to scan for devices."
        if (BluetoothService.btScanning) return "Scanning for devices…"
        return "No devices found — scan again to refresh."
    }

    // ---- Power -----------------------------------------------------------
    NexusControls.SectionHeader { first: true; text: "Bluetooth" }
    NexusControls.ToggleRow {
        icon: !BluetoothService.btActive ? "󰂲" : (root.connectedDevs.length > 0 ? "󰂱" : "󰂯")
        tint: BluetoothService.btActive ? Theme.primary : Theme.textMuted
        text: "Bluetooth"
        subtext: root.statusText
        checked: BluetoothService.btActive
        first: true
        last: true
        onToggled: BluetoothService.togglePower()
    }
    Text {
        visible: BluetoothService.btLastError !== ""
        width: parent.width
        leftPadding: 8
        rightPadding: 8
        topPadding: 10
        wrapMode: Text.WordWrap
        text: BluetoothService.btLastError
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        color: Theme.errorColor
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }

    // ---- Connected -------------------------------------------------------
    NexusControls.SectionHeader { visible: root.connectedDevs.length > 0; text: "Connected devices" }
    Repeater {
        model: root.connectedDevs
        delegate: BtRow {
            required property var modelData
            required property int index
            dev: modelData
            first: index === 0
            last: index === root.connectedDevs.length - 1
        }
    }

    // ---- Paired ----------------------------------------------------------
    NexusControls.SectionHeader { visible: root.pairedDevs.length > 0; text: "Paired devices" }
    Repeater {
        model: root.pairedDevs
        delegate: BtRow {
            required property var modelData
            required property int index
            dev: modelData
            first: index === 0
            last: index === root.pairedDevs.length - 1
        }
    }

    // ---- Available -------------------------------------------------------
    NexusControls.SectionHeader { visible: root.availVisible; text: "Available devices" }
    Repeater {
        model: root.availVisible ? root.availDevs : []
        delegate: BtRow {
            required property var modelData
            required property int index
            dev: modelData
            first: index === 0
            last: index === root.availDevs.length - 1
        }
    }

    NexusControls.Note {
        visible: BluetoothService.btActive && !root.anyDevices
        text: root.emptyText
    }

    // ---- Scan ------------------------------------------------------------
    NexusControls.SectionHeader { visible: BluetoothService.btActive; text: "Scan" }
    NexusControls.NavRow {
        visible: BluetoothService.btActive
        icon: "↻"
        text: BluetoothService.btScanning ? "Scanning…" : "Scan for devices"
        subtext: "Make the device discoverable, then scan"
        showChevron: false
        first: true
        last: true
        onClicked: BluetoothService.setScanning(true)
    }

    component BtRow: Rectangle {
        id: rowRect
        required property var dev
        property bool first: false
        property bool last: false
        readonly property bool connected: !!(rowRect.dev && rowRect.dev.connected)
        readonly property bool remembered: !!rowRect.dev && (!!rowRect.dev.paired || !!rowRect.dev.bonded || !!rowRect.dev.trusted)
        readonly property string pend: (rowRect.dev && rowRect.dev.address) ? BluetoothService.actionFor(rowRect.dev.address) : ""
        readonly property bool pinned: (rowRect.dev && rowRect.dev.address) ? BluetoothService.isPinned(rowRect.dev.address) : false
        readonly property bool pinVisible: rowRect.remembered || rowRect.connected
        readonly property string status: {
            if (rowRect.pend === "connecting" || (rowRect.dev && (rowRect.dev.state === 3 || rowRect.dev.pairing === true))) return "Connecting…"
            if (rowRect.pend === "disconnecting" || (rowRect.dev && rowRect.dev.state === 2)) return "Disconnecting…"
            if (rowRect.connected) return rowRect.dev.batteryAvailable ? Math.round(rowRect.dev.battery * 100) + "%" : "Connected"
            if (rowRect.remembered) return "Paired"
            return "Tap to pair"
        }
        width: parent ? parent.width : 300
        height: 64
        color: rowRect.connected ? Theme.withAlpha(Theme.accent, 0.10)
            : rowMouse.containsMouse ? Theme.panelCardHigh : Theme.panelCard
        topLeftRadius: rowRect.first ? 28 : 0
        topRightRadius: rowRect.first ? 28 : 0
        bottomLeftRadius: rowRect.last ? 28 : 0
        bottomRightRadius: rowRect.last ? 28 : 0
        antialiasing: Theme.shapesAa
        NexusControls.RowDivider {}
        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 16
            NexusControls.IconBadge {
                anchors.verticalCenter: parent.verticalCenter
                glyph: rowRect.connected ? "󰂱" : "󰂯"
                tint: rowRect.connected ? Theme.accent : Theme.primary
            }
            Column {
                width: Math.max(0, parent.width - 56 - actions.width - 16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: (rowRect.dev && (rowRect.dev.label || rowRect.dev.name)) || "Device"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(15)
                    color: (rowRect.dev && rowRect.dev.stale) ? Theme.textMuted : Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: rowRect.status
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: (rowRect.connected || rowRect.pend !== "") ? Theme.accent : Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Row {
                id: actions
                anchors.verticalCenter: parent.verticalCenter
                z: 2
                spacing: 4
                Item {
                    width: 32; height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowRect.pinVisible
                    Text {
                        anchors.centerIn: parent
                        text: rowRect.pinned ? "󰓎" : "󰓒"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(15)
                        color: rowRect.pinned ? Theme.accent : Theme.textSecondary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    StateLayer {
                        radius: 16
                        color: rowRect.pinned ? Theme.accent : Theme.textPrimary
                        onClicked: mouse => {
                            mouse.accepted = true
                            if (rowRect.dev && rowRect.dev.address) BluetoothService.togglePin(rowRect.dev.address)
                        }
                    }
                }
                Item {
                    width: 32; height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowRect.remembered && rowMouse.containsMouse
                    Text {
                        anchors.centerIn: parent
                        text: "󰅙"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(14)
                        color: Theme.errorColor
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    StateLayer {
                        radius: 16
                        color: Theme.errorColor
                        onClicked: mouse => {
                            mouse.accepted = true
                            if (rowRect.dev && rowRect.dev.address) BluetoothService.forgetDevice(rowRect.dev.address)
                        }
                    }
                }
            }
        }
        StateLayer {
            id: rowMouse
            radius: (rowRect.first || rowRect.last) ? 28 : 0
            color: Theme.textPrimary
            onClicked: {
                if (!rowRect.dev || !rowRect.dev.address) return
                if (rowRect.connected) BluetoothService.disconnectDevice(rowRect.dev.address)
                else BluetoothService.connectDevice(rowRect.dev.address)
            }
        }
    }
}
