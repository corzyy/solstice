pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../style/themes"
import "../../backend/services"
import "../../style/ui"

Scope {
    id: scope
    property bool showBluetooth: false
    signal dismissed()
    // CC drill-in mode: the hero row is replaced by a back header (title,
    // status, power switch) and the card settles under the control-center
    // anchor, growing out of / shrinking back into the clicked bluetooth
    // tile via the container transform (shell.qml bluetoothmenu panel). The
    // standalone bar panel keeps the hero.
    property bool showBack: false
    signal backRequested()
    property string panelModuleId: "bluetooth"
    property string anchorModuleId: "bluetooth"
    property bool _winVisible: showBluetooth
    Timer { id: hideTimer; interval: Theme.panelHideDelay; repeat: false; onTriggered: if (!scope.showBluetooth) scope._winVisible = false }
    onShowBluetoothChanged: {
        if (showBluetooth) {
            _winVisible = true
            hideTimer.stop()
            if (scope.connectedDevs.length > 0) { focusSection = "connected"; selectedIndex = 0 }
            else if (scope.pairedDevs.length > 0) { focusSection = "paired"; selectedIndex = 0 }
            else if (scope.availDevs.length > 0) { focusSection = "available"; selectedIndex = 0 }
            else { focusSection = "header" }
            actionFocused = false
            cursorActive = false
            BluetoothService.setScanning(true)
        } else {
            hideTimer.restart()
            BluetoothService.setScanning(false)
        }
    }
    // Attached-bar morph: tuck under the bar edge (see Theme.panelAttachOverlap)
    // instead of floating detached below it.
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)

    // Native backend is live (2s projection sync in service) — no polling
    // timer needed while open.

    component Hairline: Rectangle {
        antialiasing: Theme.shapesAa
        color: Theme.withAlpha(Theme.textPrimary, 0.12)
        height: 1
    }
    component OmSwitch: Item {
        id: swRoot
        property bool checked: false
        signal toggled()
        implicitWidth: 42
        implicitHeight: 22
        Rectangle {
            anchors.centerIn: parent
            width: 42; height: 22
            radius: height / 2
            color: swRoot.checked ? Theme.withAlpha(Theme.textPrimary, 0.18) : Theme.withAlpha(Theme.textPrimary, 0.04)
            border.color: swRoot.checked ? "transparent" : Theme.withAlpha(Theme.textPrimary, 0.4)
            border.width: swRoot.checked ? 0 : 1
            Rectangle {
                width: 16; height: 16
                radius: width / 2
                x: swRoot.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                color: swRoot.checked ? Theme.textPrimary : Theme.textSecondary
            }
        }
        StateLayer {
            radius: Math.round(height / 2)
            color: Theme.textPrimary
            onClicked: swRoot.toggled()
        }
    }
    component DeviceRow: Rectangle {
        id: rowRect
        required property var dev
        required property string section
        required property int rowIndex
        antialiasing: Theme.shapesAa
        // Keyboard cursor: accent tint; hover: StateLayer wash.
        readonly property bool rowSelected: scope.cursorActive && scope.focusSection === rowRect.section && scope.selectedIndex === rowRect.rowIndex
        color: rowRect.rowSelected ? Theme.withAlpha(Theme.accent, 0.16) : "transparent"
        readonly property bool isConnected: dev && dev.connected
        readonly property bool isDiscovered: rowRect.section === "available"
        readonly property bool isRemembered: dev && (!!dev.paired || !!dev.bonded || !!dev.trusted)
        readonly property string pend: (dev && dev.address) ? BluetoothService.actionFor(dev.address) : ""
        readonly property bool pinned: (dev && dev.address) ? BluetoothService.isPinned(dev.address) : false
        readonly property bool pinVisible: rowRect.isRemembered || rowRect.isConnected
        readonly property bool forgetAvailable: rowRect.isRemembered || rowRect.isConnected
        readonly property bool showForget: rowRect.forgetAvailable && (rowMouse.containsMouse || (rowRect.rowSelected && scope.actionFocused))
        readonly property string statusText: {
            if (!dev) return ""
            if (pend === "forgetting") return "Forgetting…"
            if (pend === "disconnecting" || dev.state === 2) return "Disconnecting…"
            if (isConnected) {
                if (dev.batteryAvailable) return Math.round(dev.battery * 100) + "%"
                return rowRect.section === "connected" ? "" : "Connected"
            }
            if (pend === "connecting" || dev.state === 3 || dev.pairing === true) return "Connecting…"
            if (isDiscovered) return ""
            return ""
        }
        // Behind the buttons: unhandled clicks fall through to this, while
        // pin/forget areas (later siblings, on top) get first refusal.
        StateLayer {
            id: rowMouse
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onContainsMouseChanged: if (containsMouse) {
                scope.cursorActive = true
                scope.focusSection = rowRect.section
                scope.selectedIndex = rowRect.rowIndex
                scope.actionFocused = false
            }
            onClicked: mouse => {
                if (!rowRect.dev || !rowRect.dev.address) return
                mouse.accepted = true
                let addr = rowRect.dev.address
                if (mouse.button === Qt.RightButton) {
                    if (rowRect.isConnected) BluetoothService.disconnectDevice(addr)
                    else if (rowRect.isRemembered) BluetoothService.forgetDevice(addr)
                    return
                }
                if (rowRect.isConnected) BluetoothService.disconnectDevice(addr)
                else BluetoothService.connectDevice(addr)
            }
        }
        // Anchored content (no Row math): info stretches between icon and
        // whichever buttons are visible, so nothing relayouts on hover.
        Item {
            anchors.fill: parent
            anchors.leftMargin: 10; anchors.rightMargin: 10
            Text {
                id: rowIcon
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
                text: rowRect.isConnected ? "󰂱" : "󰂯"
                color: rowRect.isConnected ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(16)
                width: 22
                horizontalAlignment: Text.AlignHCenter
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }
            Item {
                id: forgetBox
                // Opacity instead of visible (no relayout on hover).
                opacity: rowRect.showForget ? 1 : 0
                visible: opacity > 0.01
                enabled: visible
                width: 22; height: 22
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.centerIn: parent
                    text: "󰅙"
                    color: (rowRect.rowSelected && scope.actionFocused) ? Theme.accent : Theme.errorColor
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(13)
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                StateLayer {
                    radius: Math.round(width / 2)
                    color: (rowRect.rowSelected && scope.actionFocused) ? Theme.accent : Theme.errorColor
                    onEntered: {
                        scope.cursorActive = true
                        scope.focusSection = rowRect.section
                        scope.selectedIndex = rowRect.rowIndex
                        scope.actionFocused = true
                    }
                    onExited: if (rowMouse.containsMouse) scope.actionFocused = false
                    onClicked: mouse => { mouse.accepted = true; scope.forgetRow(rowRect) }
                }
            }
            Item {
                id: pinBox
                visible: rowRect.pinVisible
                width: 22; height: 22
                anchors.right: forgetBox.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.centerIn: parent
                    text: rowRect.pinned ? "󰓎" : "󰓒"
                    color: rowRect.pinned ? Theme.accent : Theme.textSecondary
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(13)
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                StateLayer {
                    radius: Math.round(width / 2)
                    color: rowRect.pinned ? Theme.accent : Theme.textSecondary
                    onClicked: mouse => {
                        mouse.accepted = true
                        if (rowRect.dev && rowRect.dev.address) BluetoothService.togglePin(rowRect.dev.address)
                    }
                }
            }
            Column {
                anchors.left: rowIcon.right
                anchors.leftMargin: 10
                anchors.right: rowRect.pinVisible ? pinBox.left : forgetBox.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                    width: parent.width
                    text: (rowRect.dev && (rowRect.dev.label || rowRect.dev.name)) || "Device"
                    color: (rowRect.dev && rowRect.dev.stale) ? Theme.textMuted : Theme.textPrimary
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(12)
                    elide: Text.ElideRight
                }
                Text {
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                    visible: text !== ""
                    width: parent.width
                    text: rowRect.statusText
                    color: (rowRect.isConnected || rowRect.pend !== "") ? Theme.textPrimary : Theme.textMuted
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(11)
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Buckets come from the service (native BlueZ, human-named + sorted).
    readonly property var connectedDevs: BluetoothService.connectedDevs
    readonly property var pairedDevs: BluetoothService.pairedDevs
    readonly property var availDevs: BluetoothService.availDevs
    // "available" only exists while discovering (upstream behavior).
    readonly property bool availVisible: BluetoothService.btScanning && scope.availDevs.length > 0
    readonly property string heroStatus: {
        if (!BluetoothService.btReady) return "…"
        if (!BluetoothService.btAvailable) return "NO ADAPTER"
        if (BluetoothService.btAction !== "") return BluetoothService.btAction.toUpperCase()
        if (!BluetoothService.btActive) return "TURNED OFF"
        if (scope.connectedDevs.length > 0) return "CONNECTED"
        if (BluetoothService.btScanning) return "SCANNING…"
        return "ON"
    }

    // ---- Keyboard cursor (ported from upstream): "header" is virtual for
    // the hero power switch; sections follow live device lists by address.
    property string focusSection: "connected"
    property int selectedIndex: 0
    property bool actionFocused: false
    property bool cursorActive: false
    property string focusedDeviceAddress: ""
    readonly property bool headerHasCursor: scope.cursorActive && scope.focusSection === "header"
    function sectionCount(section: string): int {
        if (section === "connected") return scope.connectedDevs.length
        if (section === "paired") return scope.pairedDevs.length
        if (section === "available") return scope.availDevs.length
        return 0
    }
    function sectionVisible(section: string): bool {
        if (section === "connected") return scope.connectedDevs.length > 0
        if (section === "paired") return scope.pairedDevs.length > 0
        if (section === "available") return scope.availVisible
        return false
    }
    readonly property var visibleSections: {
        let s = []
        if (scope.connectedDevs.length > 0) s.push("connected")
        if (scope.pairedDevs.length > 0) s.push("paired")
        if (scope.availVisible) s.push("available")
        return s
    }
    function devicesForSection(section: string): var {
        if (section === "connected") return scope.connectedDevs
        if (section === "paired") return scope.pairedDevs
        if (section === "available") return scope.availDevs
        return []
    }
    function deviceAt(section: string, index: int): var {
        let list = devicesForSection(section)
        return (index >= 0 && index < list.length) ? list[index] : null
    }
    function forgetRow(rowRect): void {
        if (!rowRect || !rowRect.dev || !rowRect.dev.address) return
        BluetoothService.forgetDevice(rowRect.dev.address)
    }
    function moveCursor(delta: int): void {
        let sections = scope.visibleSections
        if (focusSection === "header") {
            if (delta > 0 && sections.length > 0) {
                focusSection = sections[0]; selectedIndex = 0; actionFocused = false
            }
            return
        }
        if (sections.length === 0) { focusSection = "header"; actionFocused = false; return }
        let sIdx = sections.indexOf(focusSection)
        if (sIdx < 0) { focusSection = sections[0]; selectedIndex = 0; actionFocused = false; return }
        let max = sectionCount(focusSection) - 1
        if (delta > 0) {
            if (selectedIndex < max) { selectedIndex += 1; actionFocused = false; return }
            if (sIdx < sections.length - 1) { focusSection = sections[sIdx + 1]; selectedIndex = 0; actionFocused = false }
        } else {
            if (selectedIndex > 0) { selectedIndex -= 1; actionFocused = false; return }
            if (sIdx > 0) { focusSection = sections[sIdx - 1]; selectedIndex = sectionCount(focusSection) - 1; actionFocused = false }
            else { focusSection = "header"; actionFocused = false }
        }
    }
    function moveCursorH(delta: int): void {
        if (!cursorActive) { cursorActive = true; return }
        if (focusSection !== "paired" && focusSection !== "connected") return
        let dev = deviceAt(focusSection, selectedIndex)
        if (!dev || !dev.address) return
        if (delta > 0) actionFocused = true
        else if (delta < 0) actionFocused = false
    }
    function activateCursor(): void {
        if (focusSection === "header") { BluetoothService.togglePower(); return }
        if (actionFocused) { deleteSelected(); return }
        let dev = deviceAt(focusSection, selectedIndex)
        if (!dev || !dev.address) return
        if (dev.connected) BluetoothService.disconnectDevice(dev.address)
        else BluetoothService.connectDevice(dev.address)
    }
    function deleteSelected(): void {
        if (focusSection !== "paired" && focusSection !== "connected") return
        let dev = deviceAt(focusSection, selectedIndex)
        if (!dev || !dev.address) return
        BluetoothService.forgetDevice(dev.address)
    }
    function updateFocusedAddress(): void {
        let d = deviceAt(focusSection, selectedIndex)
        focusedDeviceAddress = d ? (d.address || "") : ""
    }
    function reselectFocusedDevice(): void {
        if (focusedDeviceAddress === "") { clampCursor(); return }
        for (let s of ["connected", "paired", "available"]) {
            if (!sectionVisible(s)) continue
            let list = devicesForSection(s)
            for (let i = 0; i < list.length; i++) {
                if (list[i] && list[i].address === focusedDeviceAddress) {
                    focusSection = s; selectedIndex = i; clampCursor(); return
                }
            }
        }
        clampCursor()
    }
    function clampCursor(): void {
        if (focusSection === "header") return
        let sections = scope.visibleSections
        // Binding teardown can deliver undefined here while the panel is
        // destroyed; treat it as "no sections".
        if (!sections || sections.length === 0) { selectedIndex = 0; return }
        if (sections.indexOf(focusSection) < 0) { focusSection = sections[0]; selectedIndex = 0; return }
        let count = sectionCount(focusSection)
        if (count === 0) {
            let sIdx = sections.indexOf(focusSection)
            focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
            selectedIndex = Math.max(0, sectionCount(focusSection) - 1)
            return
        }
        if (selectedIndex > count - 1) selectedIndex = count - 1
        if (selectedIndex < 0) selectedIndex = 0
    }
    onSelectedIndexChanged: updateFocusedAddress()
    onFocusSectionChanged: updateFocusedAddress()
    onConnectedDevsChanged: reselectFocusedDevice()
    onPairedDevsChanged: reselectFocusedDevice()
    onAvailDevsChanged: reselectFocusedDevice()
    onVisibleSectionsChanged: clampCursor()

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: scope._winVisible && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bluetoothpanel"
            // Hyprland: OnDemand + focus grab (see HyprlandService) so the
            // taskbar stays clickable while the panel is open.
            WlrLayershell.keyboardFocus: HyprlandService.isHyprland ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
            Component.onCompleted: HyprlandService.registerPanelWindow(this)
            Component.onDestruction: HyprlandService.unregisterPanelWindow(this)
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { scope.dismissed(); event.accepted = true }
                    else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { scope.cursorActive = true; scope.moveCursor(1); event.accepted = true }
                    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { scope.cursorActive = true; scope.moveCursor(-1); event.accepted = true }
                    else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) { scope.moveCursorH(-1); event.accepted = true }
                    else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) { scope.moveCursorH(1); event.accepted = true }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { if (scope.cursorActive) scope.activateCursor(); event.accepted = true }
                    else if (event.key === Qt.Key_X) { if (scope.cursorActive) scope.deleteSelected(); event.accepted = true }
                    else if (event.key === Qt.Key_B) { BluetoothService.togglePower(); event.accepted = true }
                }
                Component.onCompleted: forceActiveFocus()
            }
            // Disabled while the panel is closing: during a morph handoff
            // the outgoing window stays mapped for panelHideDelay and must
            // not eat the click that belongs to the panel now on top.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                enabled: scope.showBluetooth
                onClicked: scope.dismissed()
            }
            PanelShell {
                moduleId: scope.panelModuleId
                anchorModuleId: scope.anchorModuleId
                // Container transform: the tile replica glides into the
                // drill-in header while the card grows out of the tile.
                morphTarget: backHeader
                // Drill-in mode settles below the CC header/tile row: the CC
                // stays open and dimmed behind this card.
                edgeInset: scope.showBack ? Theme.panelDrillInInset : 0
                screenActive: Theme.isPrimaryScreen(modelData)
                panelGap: scope.panelGap
                shown: scope.showBluetooth
                boxWidth: scope.showBack ? 360 : 380
                contentMargins: scope.showBack ? 10 : 18
                contentSpacing: scope.showBack ? 12 : 14
                heightPadding: scope.showBack ? 20 : 36
                    // Drill-in header: back into the CC + power switch. The
                    // hero stays for the standalone bar panel.
                    Item {
                        visible: scope.showBack
                        width: parent.width
                        implicitHeight: backHeader.implicitHeight
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -6
                            visible: scope.headerHasCursor
                            color: Theme.withAlpha(Theme.accent, 0.12)
                        }
                        RowLayout {
                            id: backHeader
                            anchors.fill: parent
                            spacing: 6
                            PanelKit.BackButton {
                                onClicked: scope.backRequested()
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: "Bluetooth"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(13)
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: scope.heroStatus
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    elide: Text.ElideRight
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                }
                            }
                            OmSwitch {
                                checked: BluetoothService.btActive
                                Layout.alignment: Qt.AlignVCenter
                                onToggled: BluetoothService.togglePower()
                            }
                        }
                    }
                    Item {
                        visible: !scope.showBack
                        width: parent.width
                        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -6
                            visible: scope.headerHasCursor
                            color: Theme.withAlpha(Theme.accent, 0.12)
                        }
                        Text {
                            id: heroIcon
                            text: BluetoothService.icon
                            color: Theme.textPrimary
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(24)
                            opacity: BluetoothService.btActive ? 1.0 : 0.5
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        OmSwitch {
                            id: powerSwitch
                            checked: BluetoothService.btActive
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            onToggled: BluetoothService.togglePower()
                        }
                        Column {
                            id: heroLabels
                            anchors.left: heroIcon.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: powerSwitch.width + 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: "Bluetooth"
                                color: Theme.textPrimary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(16)
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            Text {
                                width: parent.width
                                text: scope.heroStatus
                                color: Theme.textSecondary
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2
                                elide: Text.ElideRight
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }
                    }
                    Hairline { width: parent.width }
                    Text {
                        visible: BluetoothService.btAction !== ""
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: BluetoothService.btAction
                        color: Theme.accent
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        visible: BluetoothService.btLastError !== ""
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: BluetoothService.btLastError
                        color: Theme.errorColor
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(11)
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Column {
                        visible: scope.connectedDevs.length > 0
                        width: parent.width
                        spacing: 10
                        PanelKit.SectionLabel { iconFont: true; text: "CONNECTED" }
                        Repeater {
                            model: scope.connectedDevs
                            delegate: DeviceRow {
                                required property var modelData
                                required property int index
                                dev: modelData
                                section: "connected"
                                rowIndex: index
                                width: parent.width
                                implicitHeight: 48
                            }
                        }
                    }
                    Hairline { visible: scope.connectedDevs.length > 0 && (scope.pairedDevs.length > 0 || scope.availVisible); width: parent.width }
                    Item {
                        width: parent.width
                        implicitHeight: Math.min(listCol.implicitHeight, 400)
                        Flickable {
                            id: btFlick
                            anchors.fill: parent
                        contentHeight: listCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.DragAndOvershootBounds
                        boundsMovement: Flickable.FollowBoundsBehavior
                        Column {
                            id: listCol
                            width: parent.width
                            spacing: 10
                            PanelKit.SectionLabel { iconFont: true; visible: scope.pairedDevs.length > 0; text: "PAIRED" }
                            Repeater {
                                model: scope.pairedDevs
                                delegate: DeviceRow {
                                    required property var modelData
                                    required property int index
                                    dev: modelData
                                    section: "paired"
                                    rowIndex: index
                                    width: listCol.width
                                    implicitHeight: 48
                                }
                            }
                            PanelKit.SectionLabel { iconFont: true; visible: scope.availVisible; text: "AVAILABLE" }
                            Repeater {
                                model: scope.availVisible ? scope.availDevs : []
                                delegate: DeviceRow {
                                    required property var modelData
                                    required property int index
                                    dev: modelData
                                    section: "available"
                                    rowIndex: index
                                    width: listCol.width
                                    implicitHeight: 48
                                }
                            }
                            Text {
                                visible: scope.connectedDevs.length === 0 && scope.pairedDevs.length === 0 && !scope.availVisible
                                width: listCol.width
                                horizontalAlignment: Text.AlignHCenter
                                text: !BluetoothService.btReady ? "Loading Bluetooth…" : (!BluetoothService.btAvailable ? "No Bluetooth adapter found" : (!BluetoothService.btActive ? "Turn Bluetooth on to scan" : (BluetoothService.btScanning ? "Scanning…" : "No devices found — reopen to scan")))
                                color: Theme.textMuted
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(11)
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }
                        }
                        EdgeFade { flick: btFlick }
                        OverscrollSpring { flick: btFlick }
                    }
        }
    }
}

}
