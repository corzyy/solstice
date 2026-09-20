pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import ".."

// Taskbar settings, mirroring Caelestia Nexus TaskbarPanel:
// Behaviour (persistent / show on hover / drag threshold), Components
// (one drill-in per taskbar entry) and Scroll actions.
NexusControls.PageBase {
    id: root
    title: "Taskbar"

    property string componentId: ""
    readonly property var comps: [
        {id: "workspaces", title: "Workspaces", desc: "Indicators, window icons", icon: "󰕰"},
        {id: "activewindow", title: "Active window", desc: "Title display, popup", icon: "󰍹"},
        {id: "systemtray", title: "Status Icons", desc: "System tray icons", icon: "󰆍"},
        {id: "clock", title: "Clock", desc: "Date, icon, background", icon: ""},
        {id: "controlcenter", title: "Control center", desc: "Quick toggles, media", icon: "󰘮"}
    ]
    readonly property var currentComp: {
        for (let i = 0; i < root.comps.length; i++) if (root.comps[i].id === root.componentId) return root.comps[i]
        return null
    }
    function showInTaskbar(id: string): bool { return !Theme.isBarModuleHidden(id) }
    function setInTaskbar(id: string, on: bool): void {
        if (on) Theme.showBarModule(id)
        else Theme.hideBarModule(id)
    }
    // Merge only makes sense while at least one module card is on, so the
    // option appears with the first background that gets enabled.
    readonly property bool anyBackground: {
        for (let i = 0; i < root.comps.length; i++) {
            if (Theme.barBackgroundEnabled(root.comps[i].id)) return true
        }
        return false
    }

    // ---- top level -------------------------------------------------------
    Column {
        width: parent.width
        spacing: 0
        visible: root.componentId === ""

        NexusControls.SectionHeader { first: true; text: "Behaviour" }
        NexusControls.ToggleRow {
            first: true
            text: "Persistent"
            subtext: "Keep the bar visible at all times"
            checked: Theme.barPersistent
            onToggled: n => Theme.setBarPersistent(n)
        }
        NexusControls.ToggleRow {
            text: "Show on hover"
            subtext: "Reveal the bar when the cursor reaches the screen edge"
            checked: Theme.barShowOnHover
            onToggled: n => Theme.setBarShowOnHover(n)
        }
        NexusControls.StepperRow {
            last: true
            label: "Drag threshold"
            subtext: "Pixels dragged before the bar reveals"
            value: Theme.barDragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => Theme.setBarDragThreshold(v)
        }

        NexusControls.SectionHeader { text: "Components" }
        Repeater {
            model: root.comps
            delegate: NexusControls.NavRow {
                required property var modelData
                required property int index
                icon: modelData.icon
                tint: index % 2 === 0 ? Theme.primary : Theme.tertiary
                text: modelData.title
                subtext: modelData.desc
                first: index === 0
                last: index === root.comps.length - 1
                onClicked: root.componentId = modelData.id
            }
        }

        NexusControls.SectionHeader { visible: root.anyBackground; text: "Backgrounds" }
        NexusControls.ToggleRow {
            visible: root.anyBackground
            first: true
            last: true
            text: "Merge background"
            subtext: "Join cards of neighbouring modules into one seamless surface"
            checked: Theme.barBackgroundMerge
            onToggled: n => Theme.setBarBackgroundMerge(n)
        }

        NexusControls.SectionHeader { text: "Scroll actions" }
        NexusControls.ToggleRow {
            first: true
            text: "Workspaces"
            subtext: "Scroll over the workspace indicator to switch workspaces"
            checked: Theme.barScrollWorkspaces
            onToggled: n => Theme.setBarScrollWorkspaces(n)
        }
        NexusControls.ToggleRow {
            text: "Volume"
            subtext: "Scroll on the top half of the bar to adjust volume"
            checked: Theme.barScrollVolume
            onToggled: n => Theme.setBarScrollVolume(n)
        }
        NexusControls.ToggleRow {
            last: true
            text: "Brightness"
            subtext: "Scroll on the bottom half of the bar to adjust brightness"
            checked: Theme.barScrollBrightness
            onToggled: n => Theme.setBarScrollBrightness(n)
        }
    }

    // ---- component drill-in ----------------------------------------------
    // The back row lives in PanelsPage (context-aware), so the drill-in
    // renders its content only.
    Loader {
        visible: root.componentId !== ""
        width: parent.width
        asynchronous: false
        sourceComponent: {
            switch (root.componentId) {
            case "workspaces": return workspacesComp
            case "activewindow": return activeWindowComp
            case "systemtray": return statusComp
            case "clock": return clockComp
            case "controlcenter": return controlCenterComp
            }
            return null
        }
    }

    // ---- Workspaces ------------------------------------------------------
    // Same rows as the dedicated Workspaces page (ported Caelestia
    // bar.workspaces settings), plus the taskbar visibility toggle.
    Component {
        id: workspacesComp
        Column {
            width: parent ? parent.width : 300
            spacing: 0
            NexusControls.SectionHeader { first: true; text: "Taskbar" }
            NexusControls.ToggleRow {
                first: true
                last: true
                icon: "󰕰"
                text: "Show in taskbar"
                subtext: "Workspace indicators with focus highlight"
                checked: root.showInTaskbar("workspaces")
                onToggled: n => root.setInTaskbar("workspaces", n)
            }
            WorkspacesSettings {}
        }
    }

    // ---- Active window ---------------------------------------------------
    Component {
        id: activeWindowComp
        Column {
            width: parent ? parent.width : 300
            spacing: 0
            NexusControls.SectionHeader { first: true; text: "Active window" }
            NexusControls.ToggleRow {
                first: true
                last: true
                icon: "󰍹"
                text: "Show in taskbar"
                subtext: "Focused window icon in the taskbar"
                checked: root.showInTaskbar("activewindow")
                onToggled: n => root.setInTaskbar("activewindow", n)
            }
            NexusControls.SectionHeader { text: "Title" }
            NexusControls.ToggleRow {
                first: true
                last: true
                icon: "󰍹"
                tint: Theme.tertiary
                text: "Window title"
                subtext: "Show the focused window's title next to its icon"
                checked: Theme.barLabelVisible("activewindow")
                onToggled: n => Theme.setBarLabelVisible("activewindow", n)
            }
            NexusControls.SectionHeader { text: "Background" }
            NexusControls.ToggleRow {
                first: true
                last: true
                text: "Background"
                subtext: "Rounded card behind the window icon and title"
                checked: Theme.barBackgroundEnabled("activewindow")
                onToggled: n => Theme.setBarBackgroundEnabled("activewindow", n)
            }
            NexusControls.Note {
                text: "Right-clicking the taskbar component toggles the title as well."
            }
        }
    }

    // ---- Status Icons ----------------------------------------------------
    Component {
        id: statusComp
        Column {
            width: parent ? parent.width : 300
            spacing: 0
            NexusControls.SectionHeader { first: true; text: "Status Icons" }
            NexusControls.ToggleRow {
                first: true
                last: true
                icon: "󰆍"
                text: "Show in taskbar"
                subtext: "System tray icons and the tray button"
                checked: root.showInTaskbar("systemtray")
                onToggled: n => root.setInTaskbar("systemtray", n)
            }
            NexusControls.SectionHeader { text: "Background" }
            NexusControls.ToggleRow {
                first: true
                last: true
                text: "Background"
                subtext: "Rounded card behind the tray icons"
                checked: Theme.barBackgroundEnabled("systemtray")
                onToggled: n => Theme.setBarBackgroundEnabled("systemtray", n)
            }
            NexusControls.Note {
                text: "Pinned and hidden tray icons are managed from the tray popout."
            }
        }
    }

    // ---- Clock -----------------------------------------------------------
    Component {
        id: clockComp
        Column {
            width: parent ? parent.width : 300
            spacing: 0
            NexusControls.SectionHeader { first: true; text: "Clock" }
            NexusControls.ToggleRow {
                first: true
                last: true
                icon: ""
                text: "Show in taskbar"
                subtext: "Date and time"
                checked: root.showInTaskbar("clock")
                onToggled: n => root.setInTaskbar("clock", n)
            }
            NexusControls.SectionHeader { text: "Format" }
            NexusControls.DropdownRow {
                first: true
                last: true
                icon: ""
                tint: Theme.tertiary
                label: "Date format"
                options: ["full", "short", "date", "timeOnly"]
                current: Theme.clockFormat
                onPicked: v => Theme.setClockFormat(v)
            }
            NexusControls.Note {
                text: "Right-clicking the clock cycles through the formats as well."
            }
            NexusControls.SectionHeader { text: "Background" }
            NexusControls.ToggleRow {
                first: true
                last: true
                text: "Background"
                subtext: "Rounded card behind the date and time"
                checked: Theme.barBackgroundEnabled("clock")
                onToggled: n => Theme.setBarBackgroundEnabled("clock", n)
            }
        }
    }

    // ---- Control center --------------------------------------------------
    Component {
        id: controlCenterComp
        Column {
            width: parent ? parent.width : 300
            spacing: 0
            NexusControls.SectionHeader { first: true; text: "Control center" }
            NexusControls.ToggleRow {
                first: true
                last: true
                icon: "󰘮"
                text: "Show in taskbar"
                subtext: "Quick toggles and media player"
                checked: root.showInTaskbar("controlcenter")
                onToggled: n => root.setInTaskbar("controlcenter", n)
            }
            NexusControls.SectionHeader { text: "Background" }
            NexusControls.ToggleRow {
                first: true
                last: true
                text: "Background"
                subtext: "Rounded card behind the status icons"
                checked: Theme.barBackgroundEnabled("controlcenter")
                onToggled: n => Theme.setBarBackgroundEnabled("controlcenter", n)
            }
        }
    }
}
