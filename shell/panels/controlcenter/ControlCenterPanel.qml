pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import "../../themes"
import "../../services"
import "../../ui"

Scope {
    id: scope

    // Panel open, OR the CC is the backdrop under an open drill-in (they are
    // set by shell.qml as plain assignments: `popped` never dips through
    // false during a drill-in open, so the curtain must not re-run).
    property bool popped: false
    // A drill-in (audio/bluetooth/updates) is open over this panel: the CC
    // stays open as the dimmed backdrop and stops taking input until the
    // sub-panel closes (shell.qml root.ccUnderlay).
    property bool behind: false
    signal dismissed()
    signal settingsRequested()
    // Opens the audio drill-in panel (shell.qml panel.audio): the card grows
    // out of the clicked button and shrinks back into it.
    signal audioRequested()
    // Opens the bluetooth drill-in panel (shell.qml panel.bluetoothMenu),
    // same button-anchored overlay handoff.
    signal bluetoothRequested()
    // Opens the updates drill-in panel (shell.qml panel.updatesMenu), same
    // button-anchored overlay handoff.
    signal updatesRequested()
    // Opens the power drill-in panel (shell.qml panel.power): lock, logout,
    // restart, shutdown in the same morph handoff.
    signal powerRequested()

    property bool editing: false

    // Window lifetime follows `popped`, which stays true while a drill-in is
    // open: the CC keeps rendering as the backdrop without re-running the
    // open/close curtain.
    property bool _winVisible: popped
    Timer {
        id: hideTimer
        interval: Theme.panelHideDelay
        repeat: false
        onTriggered: if (!scope.popped) scope._winVisible = false
    }
    onPoppedChanged: {
        if (popped) {
            _winVisible = true
            hideTimer.stop()
        } else {
            editing = false
            hideTimer.restart()
        }
    }
    onBehindChanged: if (behind) editing = false

    readonly property string barPos: Theme.barPosition
    property int panelGap: -(Theme.barThickness + Theme.panelAttachOverlap)

    // Hidden tiles persist in config/controlcenter.json (hiddenTiles array)
    // so a hide survives closing/reopening the panel.
    function hiddenTileIds(): var {
        let out = []
        try {
            let v = ccLayoutFile.adapter.hiddenTiles
            if (v && typeof v.length === "number") {
                for (let i = 0; i < v.length; i++) {
                    let id = "" + v[i]
                    if (ccTileIds.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
                }
            }
        } catch (e) { }
        return out
    }
    function tileHidden(id: string): bool { return hiddenTileIds().indexOf(id) >= 0 }
    function tileVisible(id: string): bool { return editing || !tileHidden(id) }
    function toggleTile(id: string): void {
        let h = hiddenTileIds()
        let i = h.indexOf(id)
        if (i >= 0) h.splice(i, 1)
        else h.push(id)
        ccLayoutFile.adapter.hiddenTiles = h
        ccLayoutFile.writeAdapter()
    }

    // Edit mode: the panel's reorderable sections (see moveBlock) and the
    // tiles inside the tiles block (free 4-column placement + 1x1..2x2 span
    // per tile, see tilePos/tileCols/tileRows). All of it persists in
    // config/controlcenter.json so a dragged layout survives restarts;
    // unknown/missing ids fall back to the default order.
    readonly property var ccBlockIds: ["tiles", "sliders", "media"]
    readonly property var ccTileIds: ["wifi", "bluetooth", "dnd", "updates"]
    FileView {
        id: ccLayoutFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/config/controlcenter.json"
        watchChanges: true; onFileChanged: ccReloadTimer.restart(); blockLoading: true; printErrors: false
        adapter: JsonAdapter {
            property var blocks: ["tiles", "sliders", "media"]
            property var tiles: ["wifi", "bluetooth", "dnd", "updates"]
            property var tileCols: ({})
            property var tileRows: ({})
            property var tilePos: ({})
            property var hiddenTiles: []
        }
    }
    // Debounce: our own writeAdapter() triggers the watcher; reloading the
    // just-written file mid-drag would momentarily revert the adapter.
    Timer {
        id: ccReloadTimer
        interval: 300; repeat: false
        onTriggered: { try { ccLayoutFile.reload() } catch (e) { } }
    }
    function sanitizeCcBlocks(v: var): var {
        let out = []
        try {
            if (v !== null && v !== undefined && typeof v.length === "number") {
                for (let i = 0; i < v.length; i++) {
                    let id = "" + v[i]
                    if (ccBlockIds.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
                }
            }
        } catch (e) {}
        for (let i = 0; i < ccBlockIds.length; i++) if (out.indexOf(ccBlockIds[i]) < 0) out.push(ccBlockIds[i])
        return out
    }
    readonly property var ccBlocks: sanitizeCcBlocks(ccLayoutFile.adapter.blocks)
    function setCcBlocks(arr: var): void {
        ccLayoutFile.adapter.blocks = arr
        ccLayoutFile.writeAdapter()
    }
    function moveBlock(from: int, to: int): void {
        let arr = ccBlocks.slice()
        if (from < 0 || from >= arr.length) return
        let target = Math.max(0, Math.min(to, arr.length - 1))
        if (target === from) return
        let block = arr.splice(from, 1)[0]
        arr.splice(target, 0, block)
        setCcBlocks(arr)
    }

    function sanitizeTileOrder(v: var): var {
        let out = []
        try {
            if (v !== null && v !== undefined && typeof v.length === "number") {
                for (let i = 0; i < v.length; i++) {
                    let id = "" + v[i]
                    if (ccTileIds.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
                }
            }
        } catch (e) {}
        for (let i = 0; i < ccTileIds.length; i++) if (out.indexOf(ccTileIds[i]) < 0) out.push(ccTileIds[i])
        return out
    }
    readonly property var ccTileOrder: sanitizeTileOrder(ccLayoutFile.adapter.tiles)
    // Free placement: tilePos stores each tile's top-left grid cell. Tiles
    // without a stored slot fall back to the order-based flow (the old
    // layout), so existing configs keep their arrangement until the first
    // manual move freezes every slot.
    readonly property int ccTileColumns: 4
    function flowPositions(): var {
        let out = {}
        let cells = {}
        function reserve(c0, r0, cw, rh) {
            for (let c = c0; c < c0 + cw; c++)
                for (let r = r0; r < r0 + rh; r++) cells[c + ":" + r] = true
        }
        function free(c0, r0, cw, rh) {
            for (let c = c0; c < c0 + cw; c++)
                for (let r = r0; r < r0 + rh; r++)
                    if (cells[c + ":" + r]) return false
            return true
        }
        for (let i = 0; i < ccTileOrder.length; i++) {
            let id = ccTileOrder[i]
            let cw = tileCols(id)
            let rh = tileRows(id)
            let placed = false
            for (let r = 0; !placed && r < 100; r++) {
                for (let c = 0; c + cw <= ccTileColumns; c++) {
                    if (free(c, r, cw, rh)) {
                        out[id] = [c, r]
                        reserve(c, r, cw, rh)
                        placed = true
                        break
                    }
                }
            }
        }
        return out
    }
    function tilePosition(id: string): var {
        try {
            let m = ccLayoutFile.adapter.tilePos
            if (m && typeof m === "object") {
                let p = m[id]
                if (p && typeof p.length === "number" && p.length >= 2) {
                    let c = Math.round(Number(p[0]))
                    let r = Math.round(Number(p[1]))
                    if (!isNaN(c) && !isNaN(r))
                        return [Math.max(0, Math.min(ccTileColumns - 1, c)), Math.max(0, r)]
                }
            }
        } catch (e) { }
        let d = flowPositions()
        return d[id] !== undefined ? d[id] : [0, 0]
    }
    function setTilePos(id: string, col: int, row: int): void {
        // Freeze the whole arrangement on first placement: every tile gets
        // its current slot written, so a later span change can never reflow
        // the others through the flow fallback.
        let m = {}
        for (let i = 0; i < ccTileIds.length; i++) {
            let tid = ccTileIds[i]
            if (tid === id) continue
            m[tid] = tilePosition(tid)
        }
        m[id] = [Math.max(0, Math.min(ccTileColumns - 1, col)), Math.max(0, row)]
        ccLayoutFile.adapter.tilePos = m
        ccLayoutFile.writeAdapter()
    }
    // Overlap rule: a tile only fits where no other tile sits. Hidden tiles
    // count too — they are only parked and come back in edit mode.
    function tileAreaFree(ignoreId: string, col: int, row: int, cols: int, rows: int): bool {
        for (let i = 0; i < ccTileOrder.length; i++) {
            let id = ccTileOrder[i]
            if (id === ignoreId) continue
            let p = tilePosition(id)
            let c = p[0]
            let r = p[1]
            let w = tileCols(id)
            let h = tileRows(id)
            if (col < c + w && c < col + cols && row < r + h && r < row + rows) return false
        }
        return true
    }
    // Tile spans, persisted per tile: 2x2 is the largest size, 1x1 the
    // smallest (compact, icon only); 2x1 is the default. Both axes are
    // driven by the bottom-left resize grip in edit mode.
    function tileCols(id: string): int {
        try {
            let m = ccLayoutFile.adapter.tileCols
            if (m && typeof m === "object") {
                if (m[id] === 1) return 1
                if (m[id] === 2) return 2
            }
        } catch (e) { }
        return 2
    }
    function tileRows(id: string): int {
        try {
            let m = ccLayoutFile.adapter.tileRows
            if (m && typeof m === "object") {
                if (m[id] === 1) return 1
                if (m[id] === 2) return 2
            }
        } catch (e) { }
        return 1
    }
    function setTileSize(id: string, cols: int, rows: int): void {
        let mc = {}
        try {
            let cur = ccLayoutFile.adapter.tileCols
            for (let k in cur) mc[k] = cur[k]
        } catch (e) { }
        mc[id] = cols === 1 ? 1 : 2
        ccLayoutFile.adapter.tileCols = mc
        let mr = {}
        try {
            let cur = ccLayoutFile.adapter.tileRows
            for (let k in cur) mr[k] = cur[k]
        } catch (e) { }
        mr[id] = rows === 1 ? 1 : 2
        ccLayoutFile.adapter.tileRows = mr
        ccLayoutFile.writeAdapter()
    }

    // Tile metadata (the tiles block renders ccTileOrder through these).
    function tileGlyph(id: string): string {
        if (id === "wifi") return NetworkService.icon
        if (id === "bluetooth") return BluetoothService.icon
        if (id === "dnd") return Theme.dndEnabled ? "󰂛" : "󰂚"
        if (id === "updates") return "󰚰"
        return "󰝚"
    }
    function tileTitle(id: string): string {
        if (id === "wifi") return "WLAN"
        if (id === "bluetooth") return "Bluetooth"
        if (id === "dnd") return "Nicht stören"
        if (id === "updates") return "Updates"
        return id
    }
    function tileStatus(id: string): string {
        if (id === "wifi") return wifiStatus()
        if (id === "bluetooth") return bluetoothStatus()
        if (id === "dnd") return Theme.dndEnabled ? "An" : "Aus"
        if (id === "updates") return UpdateService.displayCount > 0 ? UpdateService.displayCount + " verfügbar" : "Aktuell"
        return ""
    }
    function tileActive(id: string): bool {
        if (id === "wifi") return NetworkService.wifiEnabled
        if (id === "bluetooth") return BluetoothService.btActive
        if (id === "dnd") return Theme.dndEnabled
        if (id === "updates") return UpdateService.hasUpdates
        return false
    }
    // Publish where a drill-in was clicked from (window coordinates): the
    // incoming panel morphs out of that rect and back into it (ui/PanelMorph
    // overlay run).
    function publishOriginFor(targetId: string, item: var): void {
        if (!item)
            return
        let p = item.mapToItem(null, 0, 0)
        PanelMorph.publishOrigin(targetId, Qt.rect(p.x, p.y, item.width, item.height))
    }
    // Panel id a tile opens as a drill-in ("" for tiles that act in place).
    // Keys the source-button visibility against PanelMorph.originId.
    function tileMorphTarget(id: string): string {
        if (id === "bluetooth") return "bluetoothmenu"
        if (id === "updates") return "updatesmenu"
        return ""
    }
    function tileAction(id: string, item: var): void {
        if (id === "wifi") NetworkService.toggleWifi()
        // Tile opens the bluetooth menu (Android QS style); power lives on
        // the switch inside the drill-in and on bar middle/right-click.
        else if (id === "bluetooth") {
            scope.publishOriginFor("bluetoothmenu", item)
            scope.bluetoothRequested()
        }
        else if (id === "dnd") Theme.toggleDnd()
        // Update tile opens the update center as its own drill-in panel
        // (shell.qml panel.updatesMenu), same as bluetooth/audio.
        else if (id === "updates") {
            scope.publishOriginFor("updatesmenu", item)
            scope.updatesRequested()
        }
    }

    // Drag state for edit mode. The dragged block follows the pointer via a
    // Translate (layout untouched), the drop math runs against the stable
    // positioner y values of all blocks.
    property bool blockDragActive: false
    property int blockDragIndex: -1
    property int blockDropIndex: -1
    property real blockDragDelta: 0
    property real blockDragStartY: 0
    function beginBlockDrag(index: int, pointerY: real): void {
        blockDragActive = true
        blockDragIndex = index
        blockDropIndex = index
        blockDragStartY = pointerY
        blockDragDelta = 0
    }
    // delta/dropIndex are computed by the delegate: only it can see the
    // block repeater (id scoping — a scope-level lookup would be undefined).
    function updateBlockDrag(deltaY: real, dropIndex: int): void {
        if (!blockDragActive) return
        blockDragDelta = deltaY
        blockDropIndex = dropIndex
    }
    function endBlockDrag(): void {
        if (!blockDragActive) return
        let from = blockDragIndex
        let boundary = blockDropIndex
        cancelBlockDrag()
        if (boundary < 0) return
        // Dropping below its own slot shifts the insert position by one
        // (the block is removed from the list before re-inserting).
        moveBlock(from, boundary > from ? boundary - 1 : boundary)
    }
    function cancelBlockDrag(): void {
        blockDragActive = false
        blockDragIndex = -1
        blockDropIndex = -1
        blockDragDelta = 0
    }

    readonly property var battery: UPower.displayDevice
    readonly property bool batteryVisible: battery !== null && battery.ready && battery.isPresent
    readonly property int batteryPct: batteryVisible ? Math.round(battery.percentage * 100) : 0
    readonly property bool batteryCharging: batteryVisible
        && (battery.state === UPowerDeviceState.Charging || battery.state === UPowerDeviceState.FullyCharged)

    function batteryGlyph(pct: int, charging: bool): string {
        if (charging) return "󰂄"
        if (pct >= 90) return "󰁹"
        if (pct >= 80) return "󰂁"
        if (pct >= 60) return "󰁿"
        if (pct >= 40) return "󰁽"
        if (pct >= 20) return "󰁻"
        return "󰂃"
    }

    readonly property int btConnected: BluetoothService.connectedDevs ? BluetoothService.connectedDevs.length : 0

    function wifiStatus(): string {
        if (!NetworkService.wifiEnabled) return "Aus"
        if (!NetworkService.netActive) return "Kein Netz"
        if (NetworkService.activeType === "ethernet") return NetworkService.ssid !== "" ? NetworkService.ssid : "Ethernet"
        return NetworkService.ssid !== "" ? NetworkService.ssid : "Verbunden"
    }
    function bluetoothStatus(): string {
        if (!BluetoothService.btActive) return "Aus"
        if (btConnected > 0) return btConnected + (btConnected === 1 ? " Gerät" : " Geräte")
        return "An"
    }

    component HeaderStatusIcon: Text {
        color: Theme.textPrimary
        font.family: Theme.iconFontFamily
        font.pixelSize: Theme.fs(16)
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        verticalAlignment: Text.AlignVCenter
    }

    component FooterButton: Item {
        id: footerButton
        property string glyph
        property bool emphasized: false
        signal clicked()
        implicitWidth: 42
        implicitHeight: 42

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadiusSmall
            antialiasing: Theme.shapesAa
            color: "transparent"

            Text {
                anchors.centerIn: parent
                text: footerButton.glyph
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(18)
                color: footerButton.emphasized ? Theme.primary : (footerMouse.containsMouse ? Theme.primary : Theme.textPrimary)
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType

                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
            }
        }

        StateLayer {
            id: footerMouse
            radius: Theme.cornerRadiusSmall
            color: footerButton.emphasized ? Theme.primary : Theme.textPrimary
            onClicked: footerButton.clicked()
        }
    }

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
            WlrLayershell.namespace: "controlcenterpanel"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        scope.dismissed()
                        event.accepted = true
                    }
                }
                Component.onCompleted: forceActiveFocus()
            }

            // Disabled while the panel is closing: during a morph handoff
            // the outgoing window stays mapped for panelHideDelay and must
            // not eat the click that belongs to the panel now on top. Also
            // disabled while `behind`: the sub-panel above owns the clicks.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                enabled: scope.popped && !scope.behind
                onClicked: scope.dismissed()
            }

            PanelShell {
                moduleId: "controlcenter"
                screenActive: Theme.isPrimaryScreen(modelData)
                barPos: scope.barPos
                panelGap: scope.panelGap
                shown: scope.popped
                boxWidth: 360
                contentSpacing: 12

                // Header: settings / edit buttons (moved up from the footer)
                // with the battery tucked in on machines that have one.
                RowLayout {
                    width: parent.width
                    spacing: 6

                    FooterButton {
                        glyph: "󰒓"
                        onClicked: scope.settingsRequested()
                    }
                    FooterButton {
                        glyph: scope.editing ? "󰄬" : "󰏫"
                        emphasized: scope.editing
                        onClicked: scope.editing = !scope.editing
                    }
                    Item { Layout.fillWidth: true }

                    FooterButton {
                        glyph: "󰐥"
                        onClicked: scope.powerRequested()
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        visible: scope.batteryVisible
                        spacing: 4
                        HeaderStatusIcon { text: scope.batteryGlyph(scope.batteryPct, scope.batteryCharging) }
                        Text {
                            text: scope.batteryPct + "%"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.Medium
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    spacing: 8
                    // Edit chrome enters/exits within the screen: M3 fade
                    // (enter emphasized decelerate, exit emphasized accelerate).
                    opacity: scope.editing ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity {
                        enabled: Theme.animationsEnabled
                        NumberAnimation {
                            duration: scope.editing ? Theme.durSlowEffects : Theme.durFastEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: scope.editing ? Theme.curveEmphasizedDecelerate : Theme.curveEmphasizedAccelerate
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Layout bearbeiten"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.Medium
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Text {
                        text: "Ziehen sortiert · Tippen blendet aus"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }

                // Reorderable sections (edit mode): one delegate per block id
                // in stored order. Dragging anywhere on the section moves it
                // with a Translate; the drop line shows where it lands. Must
                // stay named "blocksRepeater" (drop math).
                Repeater {
                    id: blocksRepeater
                    model: scope.ccBlocks
                    delegate: Item {
                        id: blockItem
                        required property string modelData
                        required property int index

                        readonly property bool dragging: scope.blockDragActive && scope.blockDragIndex === blockItem.index
                        readonly property bool dropBefore: scope.blockDragActive && !dragging && scope.blockDropIndex === blockItem.index
                        readonly property bool dropAfter: scope.blockDragActive && !dragging && blockItem.index === blocksRepeater.count - 1 && scope.blockDropIndex === blocksRepeater.count

                        // First block whose vertical center is below the pointer;
                        // count = drop past the last block (delegate-local:
                        // blocksRepeater is only visible in this scope).
                        function dropBoundaryAt(pointerY: real): int {
                            for (let i = 0; i < blocksRepeater.count; i++) {
                                let it = blocksRepeater.itemAt(i)
                                if (!it) continue
                                if (pointerY < it.y + it.height / 2) return i
                            }
                            return blocksRepeater.count
                        }

                        width: parent.width
                        height: blockLoader.implicitHeight
                        // Also raised while a tile is dragged or resized
                        // beyond the block, so it stays above the blocks
                        // below it (responsiveness beats strict z order here).
                        z: dragging || (blockLoader.item !== null
                            && (blockLoader.item.dragActive === true || blockLoader.item.resizeActive === true)) ? 100 : 0
                        transform: Translate { y: blockItem.dragging ? scope.blockDragDelta : 0 }

                        // Whole-section drag (edit mode): the underlay catches
                        // the presses the section content lets through — every
                        // control is disabled while editing — so the whole
                        // module can be dragged. The tiles block opts out:
                        // there only the tiles themselves move, so dragging
                        // its gaps or empty cells does nothing.
                        MouseArea {
                            id: blockDragArea
                            anchors.fill: parent
                            enabled: scope.editing && blockItem.modelData !== "tiles"
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.SizeAllCursor : undefined
                            preventStealing: true
                            onPressed: mouse => {
                                let p = blockItem.mapToItem(blockItem.parent, mouse.x, mouse.y)
                                scope.beginBlockDrag(blockItem.index, p.y)
                            }
                            onPositionChanged: mouse => {
                                if (!scope.blockDragActive) return
                                let p = blockItem.mapToItem(blockItem.parent, mouse.x, mouse.y)
                                scope.updateBlockDrag(p.y - scope.blockDragStartY, blockItem.dropBoundaryAt(p.y))
                            }
                            onReleased: scope.endBlockDrag()
                            onCanceled: scope.cancelBlockDrag()
                        }

                        Loader {
                            id: blockLoader
                            width: parent.width
                            sourceComponent: blockItem.modelData === "tiles" ? tilesBlockComp
                                : blockItem.modelData === "sliders" ? slidersBlockComp
                                : mediaBlockComp
                        }

                        // Drop indicator at the block edge the drag currently
                        // targets (the trailing edge gets its own line).
                        Rectangle {
                            visible: blockItem.dropBefore
                            anchors.top: parent.top
                            anchors.topMargin: -6
                            width: parent.width
                            height: 3
                            radius: height / 2
                            color: Theme.accent
                            antialiasing: Theme.shapesAa
                        }
                        Rectangle {
                            visible: blockItem.dropAfter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -6
                            width: parent.width
                            height: 3
                            radius: height / 2
                            color: Theme.accent
                            antialiasing: Theme.shapesAa
                        }

                        // Hover / drag chrome for the whole section: a light
                        // tint with a centered move glyph. Input-less (plain
                        // rectangles), so it never steals events from the
                        // drag area or the tiles. Not for the tiles block: its
                        // tiles highlight themselves instead.
                        Rectangle {
                            anchors.fill: parent
                            z: 70
                            visible: scope.editing && blockItem.modelData !== "tiles"
                                && (blockDragArea.containsMouse || blockItem.dragging)
                            radius: Theme.cornerRadius
                            color: Theme.withAlpha(Theme.textPrimary, blockItem.dragging ? 0.10 : 0.06)
                            antialiasing: Theme.shapesAa

                            Text {
                                anchors.centerIn: parent
                                text: "󰆾"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(24)
                                color: Theme.textPrimary
                                opacity: 0.85
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }
                    }
                }

            }

            // Backdrop scrim for an open drill-in: dims the CC (and the
            // desktop under it) so the sub-panel on the overlay above reads
            // as the active layer. Fades in fast, and on back/close fades
            // out over the drill-in's morph-back run.
            Rectangle {
                anchors.fill: parent
                color: Theme.scrim
                // While a drill-in returns, the scrim rides the card's own
                // fade (`sourceReveal` mirrors it), so the backdrop lifts in
                // lockstep with the card instead of lingering dim over the
                // already revealed CC. A close without an overlay return
                // (IPC, animations off) keeps the plain close-token fade.
                // On open the dim waits for the card's first rendered frame
                // (overlay) — dimming while the sub-panel window is still
                // mapping reads as the whole CC flashing dark for no reason.
                opacity: {
                    if (scope.behind) {
                        if (PanelMorph.originId !== "" && PanelMorph.sourceReveal === 1)
                            return 0
                        return 0.5
                    }
                    return 0.5 * (1 - PanelMorph.sourceReveal)
                }
                visible: opacity > 0.001
                antialiasing: false

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && (scope.behind || PanelMorph.sourceReveal === 1)
                    NumberAnimation {
                        duration: scope.behind ? Theme.durDefaultEffects : Theme.panelAnimClose
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: scope.behind ? Theme.curveDefaultEffects : Theme.curvePanelOpen
                    }
                }
            }
        }
    }

    // Tiles block: one delegate per tile in the stored order. In edit mode
    // hovering a tile tints it and shows a centered move glyph; dragging the
    // tile moves it freely on the grid (a tap still toggles visibility), and
    // the bottom-right resize grip sizes it from 1x1 up to 2x2 with a live
    // preview.
    Component {
        id: tilesBlockComp
        Item {
            id: tilesBlock
            width: parent.width
            implicitHeight: tilesGrid.contentHeight

            // Placement grid (edit mode): one rounded outline per cell of
            // the 4-column layout, behind the tiles. The 10px gaps between
            // tiles and any empty cells reveal it, so the slots a tile can
            // occupy (and the resize targets) stay visible while editing.
            Item {
                id: placementGrid
                anchors.fill: parent
                z: -1
                opacity: scope.editing ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity {
                    enabled: Theme.animationsEnabled
                    NumberAnimation {
                        duration: scope.editing ? Theme.durSlowEffects : Theme.durFastEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: scope.editing ? Theme.curveEmphasizedDecelerate : Theme.curveEmphasizedAccelerate
                    }
                }

                Repeater {
                    model: tilesGrid.contentRows * tilesGrid.columns
                    delegate: Rectangle {
                        required property int index
                        width: tilesGrid.cellW
                        height: tilesGrid.tileHeight
                        x: (index % tilesGrid.columns) * (width + tilesGrid.columnSpacing)
                        y: Math.floor(index / tilesGrid.columns) * (height + tilesGrid.rowSpacing)
                        radius: Theme.cornerRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.5)
                        antialiasing: Theme.shapesAa
                    }
                }
            }

            Item {
                id: tilesGrid
                width: parent.width
                height: contentHeight

                // 4 columns: a normal tile spans two (halfwidth, 2x1), the
                // compact size spans one (quarter width, 1x1).
                readonly property int columns: scope.ccTileColumns
                readonly property real columnSpacing: 10
                readonly property real rowSpacing: 10
                readonly property real tileHeight: 72
                readonly property real cellW: (width - (columns - 1) * columnSpacing) / columns
                readonly property real unitX: cellW + columnSpacing
                readonly property real unitY: tileHeight + rowSpacing

                // Rows the placement currently spans: the lowest tile edge,
                // live with the resize preview. While editing every tile
                // counts, so a hidden one keeps its row and can be brought
                // back; outside edit mode hidden tiles are skipped, so a row
                // that only held hidden tiles collapses.
                readonly property int contentRows: {
                    let maxRow = 0
                    for (let i = 0; i < scope.ccTileOrder.length; i++) {
                        let id = scope.ccTileOrder[i]
                        if (!scope.editing && scope.tileHidden(id)) continue
                        let p = scope.tilePosition(id)
                        let rs = (resizeActive && id === resizeId) ? previewRows : scope.tileRows(id)
                        maxRow = Math.max(maxRow, p[1] + rs)
                    }
                    return maxRow
                }
                readonly property real contentHeight: contentRows > 0 ? contentRows * unitY - rowSpacing : 0

                // Drag state: free placement. The tile follows the pointer
                // via the Translate while dropCol/Row is the snapped target
                // cell (clamped to the grid), previewed by the highlight
                // below; release writes the new slot, so nothing snaps back.
                property int dragIndex: -1
                property real dragDX: 0
                property real dragDY: 0
                property real pressX: 0
                property real pressY: 0
                property int dropCol: 0
                property int dropRow: 0
                property int dropCols: 2
                property int dropRows: 1
                // Overlap rule: cells already taken make the drop invalid.
                property bool dropValid: true
                readonly property bool dragActive: dragIndex >= 0

                function updateDropTarget(): void {
                    let it = tilesRepeater.itemAt(dragIndex)
                    if (!it) return
                    dropCols = it.cols
                    dropRows = it.rows
                    dropCol = Math.max(0, Math.min(columns - it.cols, Math.round((it.x + dragDX) / unitX)))
                    dropRow = Math.max(0, Math.round((it.y + dragDY) / unitY))
                    dropValid = scope.tileAreaFree(it.modelData, dropCol, dropRow, dropCols, dropRows)
                }
                function beginTileDrag(index: int, px: real, py: real): void {
                    dragIndex = index
                    pressX = px
                    pressY = py
                    dragDX = 0
                    dragDY = 0
                    dropValid = true
                    updateDropTarget()
                }
                function updateTileDrag(px: real, py: real): void {
                    if (!dragActive) return
                    dragDX = px - pressX
                    dragDY = py - pressY
                    updateDropTarget()
                }
                function endTileDrag(): void {
                    if (!dragActive) return
                    let it = tilesRepeater.itemAt(dragIndex)
                    let id = it ? it.modelData : ""
                    let c = dropCol
                    let r = dropRow
                    let ok = dropValid
                    cancelTileDrag()
                    // Occupied target: keep the tile where it was.
                    if (id !== "" && ok) scope.setTilePos(id, c, r)
                }
                function cancelTileDrag(): void {
                    dragIndex = -1
                    dragDX = 0
                    dragDY = 0
                }



                // Resize state: the delegate whose grip is being dragged
                // renders the preview spans instead of the persisted ones;
                // release commits them to the config (position untouched).
                property int resizeIndex: -1
                property string resizeId: ""
                property int previewCols: 2
                property int previewRows: 1
                // Continuous pixel size of the dragged tile: the tile itself
                // tracks the pointer 1:1, while previewCols/Rows snap at the
                // cell boundaries so the size commits to the grid.
                property real previewW: 0
                property real previewH: 0
                property real resizeStartX: 0
                property real resizeStartY: 0
                property int resizeStartCols: 2
                property int resizeStartRows: 1
                readonly property bool resizeActive: resizeIndex >= 0

                function beginTileResize(index: int, id: string, cols: int, rows: int, px: real, py: real): void {
                    resizeIndex = index
                    resizeId = id
                    previewCols = cols
                    previewRows = rows
                    previewW = cols * unitX - columnSpacing
                    previewH = rows * unitY - rowSpacing
                    resizeStartX = px
                    resizeStartY = py
                    resizeStartCols = cols
                    resizeStartRows = rows
                }
                // The grip tracks the tile's bottom-right corner: moving right
                // grows the width, moving down grows the height. The pixel size
                // follows the pointer continuously (1x1..2x2) so the change is
                // visible on every move; the spans snap for the grid reflow.
                function updateTileResize(px: real, py: real): void {
                    if (!resizeActive) return
                    let w0 = resizeStartCols * unitX - columnSpacing
                    let h0 = resizeStartRows * unitY - rowSpacing
                    let nw = Math.max(unitX - columnSpacing, Math.min(2 * unitX - columnSpacing, w0 + (px - resizeStartX)))
                    let nh = Math.max(tileHeight, Math.min(2 * unitY - rowSpacing, h0 + (py - resizeStartY)))
                    previewW = nw
                    previewH = nh
                    previewCols = Math.max(1, Math.min(2, Math.round((nw + columnSpacing) / unitX)))
                    previewRows = Math.max(1, Math.min(2, Math.round((nh + rowSpacing) / unitY)))
                }
                function endTileResize(): void {
                    if (!resizeActive) return
                    let it = tilesRepeater.itemAt(resizeIndex)
                    let id = resizeId
                    let col = it ? it.gridCol : 0
                    let row = it ? it.gridRow : 0
                    let c = previewCols
                    let r = previewRows
                    cancelTileResize()
                    // Growing past the last column shifts the tile left so
                    // the free placement always stays inside the grid.
                    let effCol = Math.min(col, columns - c)
                    // Overlap rule: reject a size that would cover another
                    // tile (the old size stays).
                    if (!scope.tileAreaFree(id, effCol, row, c, r)) return
                    scope.setTileSize(id, c, r)
                    if (effCol !== col) scope.setTilePos(id, effCol, row)
                }
                function cancelTileResize(): void {
                    resizeIndex = -1
                    resizeId = ""
                }

                Repeater {
                    id: tilesRepeater
                    model: scope.ccTileOrder
                    delegate: Item {
                        id: tileItem
                        required property string modelData
                        required property int index

                        readonly property bool resizing: tilesGrid.resizeIndex === index
                        readonly property int cols: resizing ? tilesGrid.previewCols : scope.tileCols(modelData)
                        readonly property int rows: resizing ? tilesGrid.previewRows : scope.tileRows(modelData)
                        readonly property var pos: scope.tilePosition(modelData)
                        readonly property int gridCol: pos[0]
                        readonly property int gridRow: pos[1]
                        readonly property bool compact: cols === 1
                        readonly property bool dragging: tilesGrid.dragIndex === index
                        // Temporary clamp while a span sticks out of the last
                        // column (release shifts the stored slot accordingly).
                        readonly property int effCol: Math.min(gridCol, tilesGrid.columns - cols)

                        // Free placement: x/y come straight from the stored
                        // slot; the size from the spans (live preview included).
                        x: effCol * tilesGrid.unitX
                        y: gridRow * tilesGrid.unitY
                        width: cols * tilesGrid.cellW + (cols - 1) * tilesGrid.columnSpacing
                        height: rows * tilesGrid.tileHeight + (rows - 1) * tilesGrid.rowSpacing
                        visible: scope.tileVisible(modelData)
                        z: dragging || resizing ? 50 : 0
                        transform: Translate {
                            x: tileItem.dragging ? tilesGrid.dragDX : 0
                            y: tileItem.dragging ? tilesGrid.dragDY : 0
                        }
                        opacity: dragging ? 0.9 : 1

                        // While resizing, the visible tile follows the pointer
                        // continuously (top-left anchored) so the size feedback
                        // is instant; the cell span snaps underneath and release
                        // settles the tile into its cell.
                        QuickToggle {
                            id: quickToggle
                            width: tileItem.resizing ? tilesGrid.previewW : tileItem.width
                            height: tileItem.resizing ? tilesGrid.previewH : tileItem.height
                            compact: tileItem.compact
                            editing: scope.editing
                            selected: !scope.tileHidden(tileItem.modelData)
                            glyph: scope.tileGlyph(tileItem.modelData)
                            title: scope.tileTitle(tileItem.modelData)
                            status: scope.tileStatus(tileItem.modelData)
                            active: scope.tileActive(tileItem.modelData)
                            // The tile its drill-in grew out of stays hidden
                            // while the panel is open and reappears as the
                            // card dissolves back into it (PanelMorph).
                            opacity: {
                                const t = scope.tileMorphTarget(tileItem.modelData)
                                return t !== "" && t === PanelMorph.originId ? PanelMorph.sourceReveal : 1
                            }
                            enabled: opacity > 0.5
                            onToggled: scope.tileAction(tileItem.modelData, quickToggle)
                            onEditToggled: scope.toggleTile(tileItem.modelData)
                        }

                        // Whole-tile edit interaction: hover tints the tile
                        // and shows a centered move glyph; press+drag moves
                        // the tile (free placement), a plain tap keeps the
                        // hide/show toggle. Sits under the resize grip.
                        Rectangle {
                            anchors.fill: parent
                            visible: scope.editing
                            z: 55
                            radius: quickToggle.cornerRadius
                            color: tileDragArea.containsMouse || tileItem.dragging ? Theme.withAlpha(Theme.textPrimary, 0.12) : "transparent"
                            antialiasing: Theme.shapesAa

                            Behavior on color {
                                enabled: Theme.animationsEnabled
                                ColorAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰆾"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(24)
                                color: Theme.textPrimary
                                opacity: tileDragArea.containsMouse || tileItem.dragging ? 0.9 : 0
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType

                                Behavior on opacity {
                                    enabled: Theme.animationsEnabled
                                    NumberAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
                                }
                            }

                            MouseArea {
                                id: tileDragArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.SizeAllCursor
                                preventStealing: true
                                property real pressGX: 0
                                property real pressGY: 0

                                // 5px threshold: a tap still toggles, only a
                                // held-button move starts the free placement
                                // drag (so no drop outline flashes on taps,
                                // and hovering never moves the tile).
                                onPressed: mouse => {
                                    let p = tileItem.mapToItem(tilesGrid, mouse.x, mouse.y)
                                    pressGX = p.x
                                    pressGY = p.y
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed) return
                                    let p = tileItem.mapToItem(tilesGrid, mouse.x, mouse.y)
                                    if (!tilesGrid.dragActive) {
                                        if (Math.abs(p.x - pressGX) + Math.abs(p.y - pressGY) < 5) return
                                        tilesGrid.beginTileDrag(tileItem.index, pressGX, pressGY)
                                    }
                                    tilesGrid.updateTileDrag(p.x, p.y)
                                }
                                onReleased: {
                                    if (tilesGrid.dragActive) tilesGrid.endTileDrag()
                                    else scope.toggleTile(tileItem.modelData)
                                    pressGX = 0
                                    pressGY = 0
                                }
                                onCanceled: {
                                    tilesGrid.cancelTileDrag()
                                    pressGX = 0
                                    pressGY = 0
                                }
                            }
                        }

                        // Resize grip (edit mode only): drag the bottom-right
                        // corner to size the tile from 1x1 to 2x2. Dragging right
                        // grows the width, down grows the height; the grid shows
                        // the new spans live and release persists them.
                        Rectangle {
                            id: resizeGrip
                            visible: scope.editing
                            width: 22
                            height: 22
                            radius: width / 2
                            // Anchored to the visible tile, so the grip stays on
                            // the corner the pointer is dragging.
                            anchors.right: quickToggle.right
                            anchors.bottom: quickToggle.bottom
                            anchors.margins: 8
                            z: 60
                            color: resizeMouse.containsMouse || tileItem.resizing ? Theme.primary : Theme.surface_container_highest
                            border.width: 1
                            border.color: tileItem.resizing ? Theme.primary : Theme.outline_variant
                            antialiasing: Theme.shapesAa

                            Text {
                                anchors.centerIn: parent
                                text: "󰩨"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(13)
                                color: resizeMouse.containsMouse || tileItem.resizing ? Theme.on_primary : Theme.textPrimary
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }

                            MouseArea {
                                id: resizeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.SizeFDiagCursor
                                preventStealing: true
                                // Grid-space coords: mapping the pointer through
                                // the (moving) tile still yields its position in
                                // the grid, so the drag math stays stable while
                                // the tile reflows under the pointer.
                                onPressed: mouse => {
                                    let p = tileItem.mapToItem(tilesGrid, mouse.x, mouse.y)
                                    tilesGrid.beginTileResize(tileItem.index, tileItem.modelData, tileItem.cols, tileItem.rows, p.x, p.y)
                                }
                                onPositionChanged: mouse => {
                                    if (!tilesGrid.resizeActive) return
                                    let p = tileItem.mapToItem(tilesGrid, mouse.x, mouse.y)
                                    tilesGrid.updateTileResize(p.x, p.y)
                                }
                            onReleased: tilesGrid.endTileResize()
                            onCanceled: tilesGrid.cancelTileResize()
                            }
                        }
                    }
                }

                // Drop target highlight: the snapped cell the dragged tile
                // lands on. Accent = fits, error = occupied (overlap rule),
                // where the release keeps the tile at its old slot.
                Rectangle {
                    visible: tilesGrid.dragActive
                    x: tilesGrid.dropCol * tilesGrid.unitX
                    y: tilesGrid.dropRow * tilesGrid.unitY
                    width: tilesGrid.dropCols * tilesGrid.cellW + (tilesGrid.dropCols - 1) * tilesGrid.columnSpacing
                    height: tilesGrid.dropRows * tilesGrid.tileHeight + (tilesGrid.dropRows - 1) * tilesGrid.rowSpacing
                    radius: Theme.cornerRadius
                    color: tilesGrid.dropValid ? "transparent" : Theme.withAlpha(Theme.error, 0.12)
                    border.width: 1
                    border.color: tilesGrid.dropValid ? Theme.withAlpha(Theme.accent, 0.5) : Theme.error
                    antialiasing: Theme.shapesAa
                    z: 45
                }
            }
        }
    }

    Component {
        id: slidersBlockComp
        ColumnLayout {
            id: slidersBlock
            width: parent.width
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                CcSlider {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    // Edit mode: the slider greys out and ignores input.
                    enabled: !scope.editing
                    muted: VolumeService.isMuted
                    value: Math.max(0, Math.min(1, VolumeService.pct / 100))
                    onUserMoved: v => VolumeService.setVolumeFrac(v)
                }

                // Audio drill-in: the chevron opens the audio panel, which
                // morphs out of this card and back into it (shell.qml
                // panel.audio). Same height as the slider row.
                Rectangle {
                    id: audioMenuButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: height / 2
                    antialiasing: Theme.shapesAa
                    color: Theme.surface_container_highest
                    scale: audioMenuButtonMouse.pressed ? Theme.pressScale : 1
                    // Hidden while the audio drill-in is open; reappears as
                    // the card dissolves back into it (PanelMorph).
                    opacity: PanelMorph.originId === "audio" ? PanelMorph.sourceReveal : 1
                    enabled: opacity > 0.5

                    Behavior on scale {
                        enabled: Theme.animationsEnabled
                        NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅀"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(22)
                        color: Theme.textPrimary
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }

                    StateLayer {
                        id: audioMenuButtonMouse
                        radius: Math.round(width / 2)
                        color: Theme.textPrimary
                        disabled: scope.editing
                        onClicked: {
                            scope.publishOriginFor("audio", audioMenuButton)
                            scope.audioRequested()
                        }
                    }
                }
            }
        }
    }

    Component {
        id: mediaBlockComp
        MediaPlayerCard {
            width: parent.width
            editing: scope.editing
        }
    }
}
