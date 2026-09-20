pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import "../../../../backend/services"
import "../../../../style/ui"
import ".."

// Android 17 Settings — Network & internet.
// Wi-Fi power + network list (inline password), Ethernet, Private DNS and
// connection details, all on the M3E card kit from NexusControls.
NexusControls.PageBase {
    id: root
    title: "Network & internet"

    property bool pageVisible: false
    property string pwSsid: ""
    property string busySsid: ""
    property bool scanning: false
    Timer { id: busyTimer; interval: 6000; repeat: false; onTriggered: root.busySsid = "" }
    Timer { id: scanTimer; interval: 6000; repeat: false; onTriggered: root.scanning = false }

    // Live sources only while the page is the shown one.
    onPageEntered: {
        root.pageVisible = true
        NetworkService.refreshLink()
        NetworkService.refreshLists()
        NetworkService.refreshStats()
        NetworkService.refreshDns()
        NetworkService.rescan()
        root.scanning = true
        scanTimer.restart()
    }
    onPageLeft: root.pageVisible = false

    Timer { interval: 5000; running: root.pageVisible; repeat: true; onTriggered: NetworkService.refreshStats() }
    Timer { interval: 10000; running: root.pageVisible; repeat: true; onTriggered: { NetworkService.refreshLink(); NetworkService.refreshLists(); NetworkService.refreshDns() } }

    readonly property bool wifiOn: NetworkService.wifiEnabled
    readonly property bool online: NetworkService.netActive
    readonly property bool wifiActive: NetworkService.activeType === "wifi"
    readonly property bool detailsVisible: root.online
    readonly property bool dnsVisible: root.online && NetworkService.activeConnUuid !== ""
    readonly property var nets: root.wifiOn ? NetworkService.wifiNetworks : []

    function wifiIcon(sig: int): string {
        if (sig >= 75) return "󰤨"
        if (sig >= 55) return "󰤥"
        if (sig >= 35) return "󰤢"
        if (sig > 0) return "󰤟"
        return "󰤯"
    }
    readonly property string wifiSummary: {
        if (!root.wifiOn) return "Off"
        if (root.wifiActive && NetworkService.ssid !== "") return "Connected to " + NetworkService.ssid + " · " + NetworkService.signal + "%"
        return "Not connected"
    }
    function dnsLabel(mode: string): string {
        if (mode === "cloudflare") return "Cloudflare"
        if (mode === "google") return "Google"
        if (mode === "custom") return "Custom (external)"
        return "Automatic"
    }
    function pickDns(label: string): void {
        if (label === "Cloudflare") NetworkService.setDnsPreset("cloudflare")
        else if (label === "Google") NetworkService.setDnsPreset("google")
        else if (label === "Automatic") NetworkService.setDnsPreset("auto")
    }

    // ---- Wi-Fi -----------------------------------------------------------
    NexusControls.SectionHeader { first: true; text: "Wireless" }
    NexusControls.ToggleRow {
        icon: root.wifiOn ? "󰖩" : "󰖪"
        text: "Wi-Fi"
        subtext: root.wifiSummary
        checked: root.wifiOn
        first: true
        last: root.nets.length === 0
        onToggled: n => NetworkService.setWifiEnabled(n)
    }
    Repeater {
        model: root.nets
        delegate: WifiRow {
            required property var modelData
            required property int index
            net: modelData
            rowIndex: index
        }
    }
    NexusControls.Note {
        visible: root.wifiOn && root.nets.length === 0
        text: root.scanning ? "Scanning for networks…" : "No networks found — use Rescan below."
    }

    // Inline password entry for the tapped secured network.
    component WifiRow: Column {
        id: wifiCol
        required property var net
        required property int rowIndex
        readonly property bool isLast: wifiCol.rowIndex === root.nets.length - 1
        readonly property bool active: !!wifiCol.net.active
        readonly property bool secured: wifiCol.net.security !== "--" && wifiCol.net.security !== ""
        readonly property bool busy: root.busySsid === wifiCol.net.ssid
        readonly property bool pwOpen: root.pwSsid === wifiCol.net.ssid
        readonly property string statusText: {
            if (wifiCol.busy) return "Connecting…"
            if (wifiCol.active) return "Connected"
            return ""
        }
        width: parent.width
        spacing: 0
        onPwOpenChanged: if (wifiCol.pwOpen) Qt.callLater(() => pwField.forceActiveFocus())

        Rectangle {
            id: rowRect
            width: parent.width
            height: 64
            bottomLeftRadius: (wifiCol.isLast && !wifiCol.pwOpen) ? 28 : 0
            bottomRightRadius: (wifiCol.isLast && !wifiCol.pwOpen) ? 28 : 0
            color: wifiCol.active ? Theme.withAlpha(Theme.accent, 0.10)
                : wifiMouse.containsMouse ? Theme.panelCardHigh : Theme.panelCard
            antialiasing: Theme.shapesAa
            NexusControls.RowDivider {}
            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 16
                NexusControls.IconBadge {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: root.wifiIcon(wifiCol.net.signal || 0)
                    tint: wifiCol.active ? Theme.accent : Theme.primary
                }
                Column {
                    width: Math.max(0, parent.width - 56 - trailing.width - 16)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: wifiCol.net.ssid
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(15)
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: wifiCol.statusText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        color: wifiCol.active ? Theme.accent : Theme.textMuted
                        elide: Text.ElideRight
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                Row {
                    id: trailing
                    anchors.verticalCenter: parent.verticalCenter
                    z: 2
                    spacing: 4
                    Text {
                        visible: wifiCol.secured
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰌾"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(14)
                        color: Theme.textMuted
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        visible: wifiCol.active
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰄬"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(18)
                        color: Theme.accent
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Item {
                        width: 32; height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !wifiCol.active && wifiMouse.containsMouse
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
                            id: forgetMouse
                            radius: 16
                            color: Theme.errorColor
                            onClicked: mouse => {
                                mouse.accepted = true
                                NetworkService.forgetWifi(wifiCol.net.ssid)
                            }
                        }
                    }
                }
            }
            StateLayer {
                id: wifiMouse
                radius: 0
                color: Theme.textPrimary
                onClicked: {
                    if (wifiCol.active) {
                        NetworkService.disconnectWifi()
                        return
                    }
                    if (wifiCol.secured) {
                        root.pwSsid = wifiCol.pwOpen ? "" : wifiCol.net.ssid
                    } else {
                        root.busySsid = wifiCol.net.ssid
                        busyTimer.restart()
                        NetworkService.connectWifi(wifiCol.net.ssid, "")
                    }
                }
            }
        }
        // Password editor (M3 outlined text field + text button).
        Rectangle {
            visible: wifiCol.pwOpen
            width: parent.width
            height: visible ? 64 : 0
            bottomLeftRadius: wifiCol.isLast ? 28 : 0
            bottomRightRadius: wifiCol.isLast ? 28 : 0
            color: Theme.panelCard
            antialiasing: Theme.shapesAa
            NexusControls.RowDivider {}
            Row {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                NexusControls.IconBadge {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰌾"
                    tint: Theme.tertiary
                }
                Rectangle {
                    id: pwFieldBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 56 - pwGo.width - 12)
                    height: 40
                    radius: 20
                    color: Theme.panelCardHighest
                    border.width: pwField.activeFocus ? 2 : 0
                    border.color: Theme.accent
                    antialiasing: Theme.shapesAa
                    TextInput {
                        id: pwField
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        color: Theme.textPrimary
                        selectionColor: Theme.accent
                        passwordCharacter: "•"
                        echoMode: TextInput.Password
                        clip: true
                        onAccepted: {
                            root.busySsid = wifiCol.net.ssid
                            busyTimer.restart()
                            root.pwSsid = ""
                            NetworkService.connectWifi(wifiCol.net.ssid, text)
                        }
                    }
                }
                NexusControls.TextButton {
                    id: pwGo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Connect"
                    enabled2: pwField.text.length > 0
                    onClicked: pwField.accepted()
                }
            }
        }
    }

    NexusControls.SectionHeader { text: "Nearby networks" }
    NexusControls.NavRow {
        icon: "↻"
        text: "Rescan networks"
        subtext: root.scanning ? "Scanning…" : "Look for nearby Wi-Fi networks"
        showChevron: false
        first: true
        last: true
        onClicked: {
            root.scanning = true
            scanTimer.restart()
            NetworkService.rescan()
        }
    }

    // ---- Ethernet --------------------------------------------------------
    NexusControls.SectionHeader { visible: NetworkService.ethernetConns.length > 0; text: "Ethernet" }
    Repeater {
        model: NetworkService.ethernetConns
        delegate: NexusControls.NavRow {
            required property var modelData
            required property int index
            icon: "󰈀"
            tint: Theme.tertiary
            text: modelData.name
            subtext: modelData.active ? "Connected" : "Tap to connect"
            showChevron: false
            first: index === 0
            last: index === NetworkService.ethernetConns.length - 1
            onClicked: {
                if (modelData.active) NetworkService.ethDisconnect(modelData.name)
                else NetworkService.ethConnect(modelData.name)
            }
        }
    }

    // ---- Private DNS -----------------------------------------------------
    NexusControls.SectionHeader { visible: root.dnsVisible; text: "Private DNS" }
    NexusControls.DropdownRow {
        visible: root.dnsVisible
        first: true
        last: true
        icon: "󰖟"
        tint: Theme.primary
        label: "DNS provider"
        subtext: NetworkService.dnsBusy ? "Applying…" : (NetworkService.dnsServers.length > 0 ? NetworkService.dnsServers.join(", ") : "")
        options: ["Automatic", "Cloudflare", "Google"]
        current: root.dnsLabel(NetworkService.dnsMode)
        onPicked: v => root.pickDns(v)
    }

    // ---- Connection details ---------------------------------------------
    NexusControls.SectionHeader { visible: root.detailsVisible; text: "Connection details" }
    NexusControls.InfoRow {
        visible: root.detailsVisible
        first: true
        label: "IP address"
        value: NetworkService.ipAddr !== "" ? NetworkService.ipAddr : "--"
    }
    NexusControls.InfoRow {
        visible: root.detailsVisible
        label: "Gateway"
        value: NetworkService.gateway !== "" ? NetworkService.gateway : "--"
    }
    NexusControls.InfoRow {
        visible: root.detailsVisible
        label: "Received"
        value: NetworkService.rxBytes
    }
    NexusControls.InfoRow {
        visible: root.detailsVisible
        label: "Sent"
        value: NetworkService.txBytes
    }
    NexusControls.InfoRow {
        visible: root.detailsVisible
        label: "Ping"
        value: NetworkService.pingMs !== "" ? NetworkService.pingMs : "--"
    }
    NexusControls.InfoRow {
        visible: root.detailsVisible
        last: true
        label: "Signal"
        value: root.wifiActive ? NetworkService.signal + "%" : (NetworkService.activeType === "ethernet" ? "Wired" : "--")
    }
}
