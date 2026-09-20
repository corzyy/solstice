pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import "../../../../backend/services"
import "../../../../style/ui" as Ui
import ".."

// Settings — Connected Devices.
// Power switch, saved-device list and the pairing flow for the Bluetooth
// adapter, plus per-device settings. Views swap in place: "" shows the saved
// devices, "device" the selected device and "pair" discovery. Discovery only
// runs while the pairing view is shown; data comes from BluetoothService.
NexusControls.PageBase {
    id: root
    title: root.view === "" ? "Connected Devices" : root.viewTitle
    showTitle: root.view === ""

    // "" = saved devices, "device" = per-device settings, "pair" = pairing.
    property string view: ""
    property string deviceAddress: ""
    property string pairAddress: ""

    readonly property bool btEnabled: BluetoothService.btActive
    // Connected devices first, then the rest of the remembered ones.
    readonly property var savedDevs: BluetoothService.connectedDevs.concat(BluetoothService.pairedDevs)
    readonly property var foundDevs: BluetoothService.availDevs
    readonly property var selectedDev: {
        const want = root.deviceAddress
        if (want === "")
            return null
        const all = BluetoothService.btDevices
        for (let i = 0; i < all.length; i++) {
            if (all[i] && all[i].address === want)
                return all[i]
        }
        return null
    }
    readonly property bool devConnected: !!(root.selectedDev && root.selectedDev.connected)
    readonly property bool devBusy: {
        if (!root.selectedDev)
            return false
        const p = BluetoothService.actionFor(root.selectedDev.address)
        return p === "connecting" || p === "disconnecting"
    }
    readonly property string viewTitle: {
        if (root.view === "device")
            return root.selectedDev ? root.selectedDev.label : "Device"
        if (root.view === "pair")
            return "Pair new device"
        return ""
    }

    // BlueZ advertises a freedesktop icon name per device; map it onto the
    // shell's Nerd Font glyphs (headphones fallback for the rest).
    function glyphFor(dev): string {
        const s = ((dev && dev.icon) ? dev.icon : "").toLowerCase()
        if (s.indexOf("headset") !== -1 || s.indexOf("headphone") !== -1)
            return "󰋋"
        if (s.indexOf("audio") !== -1 || s.indexOf("speaker") !== -1)
            return "󰓃"
        if (s.indexOf("phone") !== -1)
            return "󰄜"
        if (s.indexOf("mouse") !== -1)
            return "󰍽"
        if (s.indexOf("keyboard") !== -1)
            return "󰌌"
        if (s.indexOf("laptop") !== -1 || s.indexOf("computer") !== -1)
            return "󰌢"
        if (s.indexOf("watch") !== -1)
            return "󰖉"
        if (s.indexOf("gamepad") !== -1 || s.indexOf("joystick") !== -1)
            return "󰊖"
        if (s.indexOf("printer") !== -1)
            return "󰐪"
        if (s.indexOf("tablet") !== -1)
            return "󰓶"
        if (s.indexOf("video") !== -1 || s.indexOf("display") !== -1)
            return "󰔂"
        return "󰂯"
    }

    function openDevice(addr: string): void {
        if (!addr)
            return
        root.deviceAddress = addr
        root.view = "device"
    }
    function pairDevice(addr: string): void {
        if (!addr)
            return
        root.pairAddress = addr
        BluetoothService.connectDevice(addr)
    }
    function back(): void {
        root.view = ""
        root.deviceAddress = ""
        root.pairAddress = ""
    }

    // Discovery runs only on the pairing view (and pauses while hidden).
    onViewChanged: {
        if (root.view !== "device")
            root.deviceAddress = ""
        BluetoothService.setScanning(root.view === "pair" && root.btEnabled)
    }
    onBtEnabledChanged: if (!root.btEnabled && root.view !== "") root.back()
    onSelectedDevChanged: if (root.view === "device" && !root.selectedDev) root.back()
    onPageEntered: if (root.view === "pair" && root.btEnabled) BluetoothService.setScanning(true)
    onPageLeft: BluetoothService.setScanning(false)
    Component.onDestruction: BluetoothService.setScanning(false)

    // Pairing succeeded: the device reappears as saved, so leave discovery.
    onSavedDevsChanged: {
        if (root.view !== "pair" || root.pairAddress === "")
            return
        const saved = root.savedDevs
        for (let i = 0; i < saved.length; i++) {
            if (saved[i] && saved[i].address === root.pairAddress) {
                root.back()
                return
            }
        }
    }

    // ---- main: power + saved devices -------------------------------------
    NexusControls.ToggleRow {
        visible: root.view === ""
        icon: !root.btEnabled ? "󰂲" : (BluetoothService.connectedDevs.length > 0 ? "󰂱" : "󰂯")
        tint: root.btEnabled ? Theme.primary : Theme.textMuted
        text: "Bluetooth"
        subtext: {
            if (!BluetoothService.btReady) return "Loading…"
            if (!BluetoothService.btAvailable) return "No adapter"
            if (!root.btEnabled) return "Off"
            if (BluetoothService.btScanning) return "Scanning…"
            if (BluetoothService.connectedDevs.length > 0) return BluetoothService.connectedDevs.length + (BluetoothService.connectedDevs.length === 1 ? " device connected" : " devices connected")
            return "On"
        }
        checked: root.btEnabled
        first: true
        last: false
        onToggled: BluetoothService.togglePower()
    }
    ErrorText { visible: root.view === "" && BluetoothService.btLastError !== "" }

    // Empty saved list reads as the list card itself (same seam as a row).
    NexusControls.ConnectedRect {
        visible: root.view === "" && root.savedDevs.length === 0
        first: false
        last: false
        height: 140
        Column {
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.btEnabled ? "󰂯" : "󰂲"
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(26)
                color: Theme.textMuted
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.btEnabled ? "No saved devices" : "Bluetooth disabled"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(14)
                color: Theme.textMuted
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    Repeater {
        model: root.view === "" ? root.savedDevs : []
        delegate: DeviceRow {
            required property var modelData
            required property int index
            dev: modelData
            onSettingsRequested: root.openDevice(dev.address)
        }
    }

    NexusControls.NavRow {
        visible: root.view === ""
        icon: "󰐕"
        text: "Pair new device"
        subtext: root.btEnabled ? "Search for nearby devices" : "Turn Bluetooth on to pair"
        disabled: !root.btEnabled
        first: false
        last: true
        onClicked: root.view = "pair"
    }

    Item { visible: root.view === ""; width: 1; height: 20 }

    NexusControls.ToggleRow {
        visible: root.view === ""
        text: "Discoverable"
        subtext: "Allow nearby devices to find this one"
        disabled: !root.btEnabled
        checked: BluetoothService.btDiscoverable
        first: true
        last: false
        onToggled: next => BluetoothService.setDiscoverable(next)
    }
    NexusControls.ToggleRow {
        visible: root.view === ""
        text: "Pairable"
        subtext: "Allow nearby devices to pair with this one"
        disabled: !root.btEnabled
        checked: BluetoothService.btPairable
        first: false
        last: true
        onToggled: next => BluetoothService.setPairable(next)
    }

    // ---- sub-page header --------------------------------------------------
    Item {
        visible: root.view !== ""
        width: parent.width
        implicitHeight: 56
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Rectangle {
                width: 40
                height: 40
                // M3E shape morph: circle at rest, rounded square while hovered.
                radius: backHover.containsMouse ? 12 : 20
                color: backHover.containsMouse ? Theme.panelCardHighest : Theme.panelCardHigh
                antialiasing: Theme.shapesAa
                Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: Theme.fs(20)
                    color: Theme.textPrimary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Ui.StateLayer { id: backHover; radius: parent.radius; color: Theme.textPrimary; onClicked: root.back() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.viewTitle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(22)
                font.weight: Font.Medium
                color: Theme.textPrimary
                elide: Text.ElideRight
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    // ---- device view ------------------------------------------------------
    Item {
        visible: root.view === "device"
        width: parent.width
        implicitHeight: deviceButtons.implicitHeight
        Row {
            id: deviceButtons
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(0, Math.round(root.width * 0.7))
            spacing: 12
            BigButton {
                width: Math.max(0, (deviceButtons.width - deviceButtons.spacing) / 2)
                icon: root.devConnected ? "󰅖" : "󰐕"
                label: root.devConnected ? "Disconnect" : "Connect"
                base: Theme.primary_container
                onBase: Theme.on_primary_container
                disabled: root.devBusy
                onClicked: {
                    if (!root.selectedDev || root.devBusy)
                        return
                    if (root.devConnected)
                        BluetoothService.disconnectDevice(root.selectedDev.address)
                    else
                        BluetoothService.connectDevice(root.selectedDev.address)
                }
            }
            BigButton {
                width: Math.max(0, (deviceButtons.width - deviceButtons.spacing) / 2)
                icon: "󰆴"
                label: "Forget"
                base: Theme.panelCardHighest
                onBase: Theme.textSecondary
                danger: true
                onClicked: {
                    if (root.selectedDev)
                        BluetoothService.forgetDevice(root.selectedDev.address)
                    root.back()
                }
            }
        }
    }

    ErrorText { visible: root.view === "device" && BluetoothService.btLastError !== "" }

    NexusControls.ToggleRow {
        visible: root.view === "device"
        text: "Trusted"
        subtext: "Allow this device to connect automatically"
        checked: !!(root.selectedDev && root.selectedDev.trusted)
        first: true
        last: false
        onToggled: next => {
            if (root.selectedDev)
                BluetoothService.setDeviceTrusted(root.selectedDev.address, next)
        }
    }
    NexusControls.ToggleRow {
        visible: root.view === "device"
        text: "Blocked"
        subtext: "Prevent this device from connecting"
        checked: !!(root.selectedDev && root.selectedDev.blocked)
        first: false
        last: false
        onToggled: next => {
            if (root.selectedDev)
                BluetoothService.setDeviceBlocked(root.selectedDev.address, next)
        }
    }
    NexusControls.ToggleRow {
        visible: root.view === "device"
        text: "Wake allowed"
        subtext: "Allow this device to wake the system"
        checked: !!(root.selectedDev && root.selectedDev.wakeAllowed)
        first: false
        last: true
        onToggled: next => {
            if (root.selectedDev)
                BluetoothService.setDeviceWakeAllowed(root.selectedDev.address, next)
        }
    }

    Item { visible: root.view === "device"; width: 1; height: 20 }

    NexusControls.ConnectedRect {
        visible: root.view === "device"
        first: true
        last: false
        implicitHeight: batteryCol.implicitHeight + 32
        Column {
            id: batteryCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 10
            Row {
                width: parent.width
                Text {
                    id: batteryLabel
                    text: "Battery"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Item {
                    width: Math.max(0, parent.width - batteryLabel.width - batteryValue.width)
                    height: 1
                }
                Text {
                    id: batteryValue
                    text: (root.selectedDev && root.selectedDev.batteryAvailable) ? Math.round(root.selectedDev.battery * 100) + "%" : "Unavailable"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Rectangle {
                visible: !!(root.selectedDev && root.selectedDev.batteryAvailable)
                width: parent.width
                height: 6
                radius: 3
                color: Theme.secondary_container
                antialiasing: Theme.shapesAa
                Rectangle {
                    width: Math.max(0, Math.min(1, root.selectedDev ? root.selectedDev.battery : 0)) * parent.width
                    height: parent.height
                    radius: 3
                    color: Theme.accent
                    antialiasing: Theme.shapesAa
                    Behavior on width { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultSpatial } }
                }
            }
        }
    }
    NexusControls.InfoRow {
        visible: root.view === "device"
        label: "Address"
        value: root.selectedDev ? root.selectedDev.address : ""
        first: false
        last: true
    }

    // ---- pairing view -----------------------------------------------------
    NexusControls.SectionHeader {
        visible: root.view === "pair"
        first: true
        text: "Available devices"
    }
    Item {
        id: scanTrack
        visible: root.view === "pair"
        width: parent.width
        height: 4
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.secondary_container
            antialiasing: Theme.shapesAa
        }
        Rectangle {
            id: scanFill
            width: Math.max(48, Math.round(scanTrack.width / 4))
            height: parent.height
            radius: 2
            color: Theme.accent
            antialiasing: Theme.shapesAa
            NumberAnimation on x {
                running: root.view === "pair" && BluetoothService.btScanning
                from: -scanFill.width
                to: scanTrack.width
                duration: 1400
                easing.type: Easing.InOutSine
                loops: Animation.Infinite
            }
        }
    }

    Repeater {
        model: root.view === "pair" ? root.foundDevs : []
        delegate: PairRow {
            required property var modelData
            required property int index
            dev: modelData
            first: index === 0
            last: index === root.foundDevs.length - 1
            onPairRequested: root.pairDevice(dev.address)
        }
    }
    ErrorText { visible: root.view === "pair" && BluetoothService.btLastError !== "" }
    NexusControls.Note {
        visible: root.view === "pair" && root.foundDevs.length === 0
        text: BluetoothService.btScanning ? "Searching for devices…" : "Make the device discoverable to pair."
    }

    // ---- rows -------------------------------------------------------------
    component ErrorText: Text {
        width: parent ? parent.width : 300
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

    component DeviceRow: Rectangle {
        id: devRow
        required property var dev
        signal settingsRequested()
        readonly property bool connected: !!(devRow.dev && devRow.dev.connected)
        readonly property string pend: (devRow.dev && devRow.dev.address) ? BluetoothService.actionFor(devRow.dev.address) : ""
        readonly property bool busy: pend === "connecting" || pend === "disconnecting"
        readonly property string status: {
            if (devRow.pend === "connecting" || (devRow.dev && (devRow.dev.state === 3 || devRow.dev.pairing === true))) return "Connecting…"
            if (devRow.pend === "disconnecting" || (devRow.dev && devRow.dev.state === 2)) return "Disconnecting…"
            if (devRow.connected) return devRow.dev.batteryAvailable ? "Connected • " + Math.round(devRow.dev.battery * 100) + "%" : "Connected"
            return "Saved"
        }
        width: parent ? parent.width : 300
        implicitHeight: 64
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: 4
        topRightRadius: 4
        bottomLeftRadius: 4
        bottomRightRadius: 4
        antialiasing: Theme.shapesAa

        // Row action underneath the content: the gear button above it keeps
        // its own clicks, everything else toggles the connection.
        Ui.StateLayer {
            id: devMouse
            radius: 4
            color: Theme.textPrimary
            disabled: devRow.busy
            onClicked: {
                if (!devRow.dev || !devRow.dev.address)
                    return
                if (devRow.connected)
                    BluetoothService.disconnectDevice(devRow.dev.address)
                else
                    BluetoothService.connectDevice(devRow.dev.address)
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 14
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 20
                color: devRow.connected ? Theme.accent : Theme.secondary_container
                antialiasing: Theme.shapesAa
                Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                Text {
                    anchors.centerIn: parent
                    text: root.glyphFor(devRow.dev)
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(20)
                    color: devRow.connected ? Theme.onAccent : Theme.on_secondary_container
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Column {
                width: Math.max(0, parent.width - 40 - 40 - 28)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: (devRow.dev && devRow.dev.label) || "Device"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    text: devRow.status
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: (devRow.connected || devRow.pend !== "") ? Theme.accent : Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Item {
                width: 40
                height: 40
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent
                    visible: !devRow.busy
                    radius: 20
                    color: Theme.panelCardHighest
                    antialiasing: Theme.shapesAa
                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(18)
                        color: Theme.textSecondary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Ui.StateLayer {
                        radius: 20
                        color: Theme.textPrimary
                        onClicked: mouse => {
                            mouse.accepted = true
                            devRow.settingsRequested()
                        }
                    }
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: devRow.busy
                }
            }
        }
    }

    component PairRow: Rectangle {
        id: pairRow
        required property var dev
        property bool first: false
        property bool last: false
        signal pairRequested()
        readonly property string pend: (pairRow.dev && pairRow.dev.address) ? BluetoothService.actionFor(pairRow.dev.address) : ""
        readonly property bool pairing: pairRow.pend === "connecting" || !!(pairRow.dev && pairRow.dev.pairing)
        width: parent ? parent.width : 300
        implicitHeight: 64
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: pairRow.first ? 28 : 4
        topRightRadius: pairRow.first ? 28 : 4
        bottomLeftRadius: pairRow.last ? 28 : 4
        bottomRightRadius: pairRow.last ? 28 : 4
        antialiasing: Theme.shapesAa

        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 14
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyphFor(pairRow.dev)
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(20)
                color: Theme.textSecondary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Column {
                width: Math.max(0, parent.width - 24 - 40 - 28)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: (pairRow.dev && pairRow.dev.label) || "Unknown device"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    text: pairRow.pairing ? "Pairing…" : ((pairRow.dev && pairRow.dev.address) || "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: pairRow.pairing ? Theme.accent : Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Item {
                width: 40
                height: 40
                anchors.verticalCenter: parent.verticalCenter
                Spinner { anchors.centerIn: parent; visible: pairRow.pairing }
            }
        }

        Ui.StateLayer {
            id: pairMouse
            radius: (pairRow.first || pairRow.last) ? 28 : 4
            color: Theme.textPrimary
            disabled: pairRow.pairing
            onClicked: pairRow.pairRequested()
        }
    }

    component BigButton: Rectangle {
        id: bigButton
        property string icon: ""
        property string label: ""
        property color base: Theme.primary_container
        property color onBase: Theme.on_primary_container
        // Destructive actions stay neutral until hovered, then wash red.
        property bool danger: false
        property bool disabled: false
        signal clicked()
        readonly property bool hovered: bigMouse.containsMouse
        readonly property bool washed: danger && hovered && !disabled
        readonly property color activeBase: washed ? Theme.error_container : base
        readonly property color activeOn: washed ? Theme.on_error_container : onBase
        implicitHeight: bigCol.implicitHeight + 20
        height: implicitHeight
        // M3E shape morph: pill at rest, rounded rectangle while hovered.
        radius: hovered ? 12 : Math.round(height / 2)
        color: activeBase
        opacity: bigButton.disabled ? 0.5 : 1
        antialiasing: Theme.shapesAa
        Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
        Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
        Column {
            id: bigCol
            anchors.centerIn: parent
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bigButton.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(20)
                color: bigButton.activeOn
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: bigButton.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                color: bigButton.activeOn
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
        Ui.StateLayer {
            id: bigMouse
            radius: bigButton.radius
            color: bigButton.activeOn
            disabled: bigButton.disabled
            onClicked: bigButton.clicked()
        }
    }

    component Spinner: Item {
        id: spin
        implicitWidth: 24
        implicitHeight: 24
        Text {
            anchors.centerIn: parent
            text: "󰝲"
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(18)
            color: Theme.primary
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        RotationAnimator on rotation {
            running: spin.visible
            from: 0
            to: 360
            duration: 1000
            loops: Animation.Infinite
        }
    }
}
