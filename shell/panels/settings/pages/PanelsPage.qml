pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import "../../../ui" as Ui
import ".."

// Android 17 Settings — Panels.
// Entry point for shell-surface settings: pick a panel, edit it in place.
// Taskbar and Notifications (toasts + OSD screens) are the panels for now;
// new panels just add an entry to `panels` and a component in the Loader
// switch below.
//
// The single back row is context-aware: it steps out of a component drill-in
// first ("All components / <name>"), then out of the panel ("All panels").
NexusControls.PageBase {
    id: root
    title: "Panels"
    showTitle: root.panelId === ""

    readonly property var panels: [
        {id: "taskbar", title: "Taskbar", icon: "󰍹", desc: "Position, modules, spacing"},
        {id: "launcher", title: "Launcher", icon: "󰍉", desc: "App search, OS icon, panel size"},
        {id: "screenshot", title: "Screenshot UI", icon: "󰹑", desc: "Region, window, fullscreen capture"},
        {id: "notifications", title: "Notifications", icon: "󰂚", desc: "Toasts, Volume, Layout & Theme OSDs"}
    ]
    property string panelId: ""
    readonly property var currentPanel: {
        for (let i = 0; i < root.panels.length; i++) if (root.panels[i].id === root.panelId) return root.panels[i]
        return null
    }
    // Nested state of the hosted panel (TopBarPage exposes componentId).
    readonly property bool inComponent: panelLoader.item ? (panelLoader.item.componentId || "") !== "" : false
    readonly property string componentTitle: {
        if (!panelLoader.item || !root.inComponent) return ""
        let c = panelLoader.item.currentComp
        return c ? c.title : ""
    }
    function openPanel(id: string): void { root.panelId = id }
    function closePanel(): void { root.panelId = "" }
    function back(): void {
        if (root.inComponent && panelLoader.item) {
            panelLoader.item.componentId = ""
            return
        }
        root.closePanel()
    }

    // ---- panel picker ----------------------------------------------------
    NexusControls.SectionHeader { first: true; visible: root.panelId === ""; text: "Available panels" }
    Repeater {
        model: root.panelId === "" ? root.panels : []
        delegate: NexusControls.NavRow {
            required property var modelData
            required property int index
            icon: modelData.icon
            tint: index % 2 === 0 ? Theme.primary : Theme.tertiary
            text: modelData.title
            subtext: modelData.desc
            first: index === 0
            last: index === root.panels.length - 1
            onClicked: root.openPanel(modelData.id)
        }
    }

    // ---- sub-page header + selected panel --------------------------------
    // Nexus sub-page header: round back button + page title.
    Item {
        visible: root.panelId !== ""
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
                radius: 20
                color: backMouse.containsMouse ? Theme.panelCardHighest : Theme.panelCardHigh
                antialiasing: Theme.shapesAa
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: Theme.fs(20)
                    color: Theme.textPrimary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Ui.StateLayer { id: backMouse; radius: 20; color: Theme.textPrimary; onClicked: root.back() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.inComponent ? root.componentTitle : (root.currentPanel ? root.currentPanel.title : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(22)
                font.weight: Font.Medium
                color: Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }
    Loader {
        id: panelLoader
        visible: root.panelId !== ""
        width: parent.width
        asynchronous: false
        sourceComponent: {
            if (root.panelId === "taskbar") return taskbarComp
            if (root.panelId === "launcher") return launcherComp
            if (root.panelId === "screenshot") return screenshotComp
            if (root.panelId === "notifications") return notificationsComp
            return null
        }
    }

    Component {
        id: taskbarComp
        TopBarPage { showTitle: false }
    }
    Component {
        id: launcherComp
        LauncherSettings { showTitle: false }
    }
    Component {
        id: screenshotComp
        ScreenshotSettings { showTitle: false }
    }
    // Same page as the left rail's Notifications entry — one source of truth
    // for toast + OSD settings, just reachable through the surface grouping.
    Component {
        id: notificationsComp
        NotificationsPage { showTitle: false }
    }
}
