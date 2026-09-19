// Tray: pinned items render as their real app icons in the bar; the grid
// button next to them opens SystemTrayPanel (activate / menu / pin / hide
// for every item). Hidden items never appear here, and pin/hide in the
// panel updates the bar live (Theme filewatcher -> isTrayPinned).
//
// BarSlot owns the module MouseArea, so clicks arrive as coordinates via
// BarModule: click() hit-tests the pinned slots and only falls through to
// the button when the click is not on an icon.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.DBusMenu
import Quickshell.Services.SystemTray as TrayService
import "../../themes"

BarWidgetBase {
    id: root
    // Tighter than the default: the slots already carry their own padding.
    hPad: 10
    vPad: 8
    rowPadV: 6

    readonly property int slotExtent: 24
    readonly property int iconPx: 16
    readonly property int buttonGap: 6

    readonly property color _fg: hovered ? Theme.accent : Theme.textPrimary

    // PERF: the panel filters the same way; only non-passive items exist.
    readonly property var rawItems: {
        let out = []
        try {
            let vals = TrayService.SystemTray.items.values
            for (let i = 0; i < vals.length; i++) {
                let it = vals[i]
                if (!it || it.status === TrayService.Status.Passive) continue
                out.push(it)
            }
        } catch (e) { }
        return out
    }
    // Pinned and not hidden -> icon in the bar (hidden wins, like the old
    // drawer buckets). Everything else lives in the panel only.
    readonly property var pinnedItems: {
        let out = []
        let items = root.rawItems
        for (let i = 0; i < items.length; i++) {
            let id = String((items[i] && items[i].id) || "")
            if (Theme.isTrayHidden(id)) continue
            if (Theme.isTrayPinned(id)) out.push(items[i])
        }
        return out
    }
    readonly property real pinnedExtent: root.pinnedItems.length * root.slotExtent
    readonly property real rowExtent: root.pinnedExtent + (root.pinnedItems.length > 0 ? root.buttonGap : 0) + root.slotExtent

    property var hoveredItem: null
    // Along-axis position (bar coords) of the slot the menu was opened for.
    property real _menuAlong: 0

    // The row is centered inside the widget (BarWidgetBase contentScale);
    // click coords are widget-relative, so the hit-test needs the origin.
    function rowOrigin(): real {
        return (root.vertical ? root.height - root.rowExtent : root.width - root.rowExtent) / 2
    }

    function iconClick(item, button: int): bool {
        if (!item) return false
        if (button === Qt.RightButton) {
            if (item.hasMenu) root.openMenuFor(item)
            return true
        }
        if (button === Qt.MiddleButton) {
            try { item.secondaryActivate() } catch (e) { }
            return true
        }
        if (item.onlyMenu) {
            if (item.hasMenu) root.openMenuFor(item)
            return true
        }
        try { item.activate() } catch (e) { }
        return true
    }

    function click(button: int, x: real, y: real): bool {
        if (root.pinnedItems.length === 0) return false
        const rel = (root.vertical ? y : x) - root.rowOrigin()
        if (rel < 0 || rel >= root.pinnedExtent) return false
        const i = Math.floor(rel / root.slotExtent)
        if (i < 0 || i >= root.pinnedItems.length) return false
        root._menuAlong = root.rowOrigin() + i * root.slotExtent + root.slotExtent / 2
        return root.iconClick(root.pinnedItems[i], button)
    }

    function wheel(dy: real): bool {
        if (!root.hoveredItem) return false
        try { root.hoveredItem.scroll(dy, false) } catch (e) { }
        return true
    }

    function openMenuFor(item): void {
        // CRASH FIX (same as the former drawer): anchor.item/window must be
        // set imperatively — a binding would re-fire while the delegate is
        // torn down and segfault in PopupAnchor::onItemWindowChanged.
        qsMenuAnchor.anchor.window = root.QsWindow.window
        qsMenuAnchor.anchor.item = menuAnchorHost
        menuAnchorHost.x = Math.round(root.vertical ? (root.width - 1) / 2 : root._menuAlong)
        menuAnchorHost.y = Math.round(root.vertical ? root._menuAlong : (root.height - 1) / 2)
        qsMenuAnchor.menu = item ? item.menu : null
        qsMenuAnchor.open()
    }

    component TraySlot: Item {
        id: traySlot
        required property var modelData
        // PERF: per-delegate caches (string split + Image.Error resets).
        readonly property string iconSrc: String((traySlot.modelData && traySlot.modelData.icon) || "")
        readonly property bool symbolic: {
            let n = iconSrc.split("?")[0]
            return n.slice(-9) === "-symbolic"
        }
        Layout.preferredWidth: root.slotExtent
        Layout.preferredHeight: root.slotExtent
        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadiusSmall
            color: slotHover.hovered ? Theme.bgHover : "transparent"
        }
        Item {
            anchors.centerIn: parent
            width: root.iconPx
            height: root.iconPx
            Image {
                smooth: Theme.imageSmooth
                mipmap: Theme.imageMipmap
                id: slotImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                // PERF: fixed 32px decode (was DPR-scaled, refetching all
                // icons on DPR change for a 16px display).
                sourceSize.width: 32
                sourceSize.height: 32
                source: traySlot.symbolic ? "" : traySlot.iconSrc
                asynchronous: true
                cache: true
                visible: !traySlot.symbolic
                onStatusChanged: if (status === Image.Error && source !== "") source = ""
            }
            // PERF: MultiEffect is an offscreen pass per icon — Loader-gate
            // so only symbolic icons pay for it.
            Loader {
                anchors.fill: parent
                active: traySlot.symbolic
                asynchronous: true
                sourceComponent: symbolFx
            }
            Component {
                id: symbolFx
                MultiEffect {
                    source: slotImg
                    colorization: 1.0
                    colorizationColor: Theme.textPrimary
                }
            }
        }
        HoverHandler {
            id: slotHover
            onHoveredChanged: {
                if (hovered) root.hoveredItem = traySlot.modelData
                else if (root.hoveredItem === traySlot.modelData) root.hoveredItem = null
            }
        }
    }

    // Panel button: a view-grid reads as "all app icons" at a glance; the
    // old inbox glyph looked like a terminal prompt at bar size.
    component TrayButton: Text {
        text: "󰀻"
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
        font.family: Theme.iconFontFamily
        font.pixelSize: Theme.fs(14)
        color: root._fg
        Layout.preferredWidth: root.slotExtent
        Layout.preferredHeight: root.slotExtent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component TrayGap: Item {
        Layout.preferredWidth: root.vertical ? 1 : (root.pinnedItems.length > 0 ? root.buttonGap : 0)
        Layout.preferredHeight: root.vertical ? (root.pinnedItems.length > 0 ? root.buttonGap : 0) : 1
    }

    rowContent: Component {
        RowLayout {
            spacing: 0
            Repeater {
                model: root.pinnedItems
                delegate: TraySlot { }
            }
            TrayGap { }
            TrayButton { }
        }
    }
    colContent: Component {
        ColumnLayout {
            spacing: 0
            Repeater {
                model: root.pinnedItems
                delegate: TraySlot { }
            }
            TrayGap { }
            TrayButton { }
        }
    }

    // Shared menu anchor for pinned icon right-clicks; moved to the clicked
    // slot right before opening (see openMenuFor).
    Item {
        id: menuAnchorHost
        width: 1
        height: 1
    }
    QsMenuAnchor {
        id: qsMenuAnchor
        anchor.rect.x: 0
        anchor.rect.y: 0
        anchor.rect.width: 1
        anchor.rect.height: 1
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Top
        anchor.margins.top: 4
        anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipX | PopupAdjustment.FlipY
    }
}
