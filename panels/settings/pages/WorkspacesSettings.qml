pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import ".."

// Caelestia bar.workspaces settings (nexus/pages/panels/taskbar/
// BarWorkspaces.qml) adapted for the Umbriel port. Shared by the Workspaces
// page and the Taskbar > Workspaces drill-in.
Column {
    id: root
    width: parent ? parent.width : 300
    spacing: 0

    NexusControls.SectionHeader { first: true; text: "Workspaces" }
    NexusControls.StepperRow {
        first: true
        label: "Shown"
        subtext: "Number of workspaces displayed"
        value: Theme.workspaceShown
        from: 1
        to: 20
        stepSize: 1
        onMoved: v => Theme.setWorkspaceShown(v)
    }
    NexusControls.ToggleRow {
        text: "Active indicator"
        checked: Theme.workspaceActiveIndicator
        onToggled: n => Theme.setWorkspaceActiveIndicator(n)
    }
    NexusControls.ToggleRow {
        text: "Active trail"
        checked: Theme.workspaceActiveTrail
        onToggled: n => Theme.setWorkspaceActiveTrail(n)
    }
    NexusControls.ToggleRow {
        text: "Background"
        subtext: "Rounded container behind the workspace indicators"
        checked: Theme.barBackgroundEnabled("workspaces")
        onToggled: n => Theme.setBarBackgroundEnabled("workspaces", n)
    }
    NexusControls.ToggleRow {
        visible: Theme.barBackgroundEnabled("workspaces")
        text: "Occupied background"
        subtext: "Highlight workspaces that contain windows"
        checked: Theme.workspaceOccupiedBg
        onToggled: n => Theme.setWorkspaceOccupiedBg(n)
    }
    NexusControls.ToggleRow {
        text: "Show unoccupied"
        subtext: "Show workspaces that are inactive and empty"
        checked: Theme.workspaceShowUnoccupied
        onToggled: n => Theme.setWorkspaceShowUnoccupied(n)
    }
    NexusControls.ToggleRow {
        text: "Per monitor"
        subtext: "Hide workspaces not on the current monitor"
        checked: Theme.workspacePerMonitor
        onToggled: n => Theme.setWorkspacePerMonitor(n)
    }
    NexusControls.ToggleRow {
        text: "Show windows"
        subtext: "Show icons of open windows on each workspace"
        checked: Theme.workspaceShowWindows
        onToggled: n => Theme.setWorkspaceShowWindows(n)
    }
    NexusControls.StepperRow {
        last: true
        label: "Max window icons"
        value: Theme.workspaceMaxWindowIcons
        from: 0
        to: 20
        stepSize: 1
        onMoved: v => Theme.setWorkspaceMaxWindowIcons(v)
    }

    NexusControls.SectionHeader { text: "Display" }
    NexusControls.DropdownRow {
        first: true
        label: "Display type"
        options: ["shapes", "numbers"]
        current: Theme.workspaceDisplayType
        onPicked: v => Theme.setWorkspaceDisplayType(v)
    }
    NexusControls.SliderRow {
        icon: ""
        label: "Distance"
        from: 0
        to: 24
        stepSize: 1
        unit: "px"
        value: Theme.workspaceSpacing
        onMoved: v => Theme.setWorkspaceSpacing(Math.round(v))
        onApplied: v => Theme.setWorkspaceSpacing(Math.round(v))
    }
    NexusControls.SliderRow {
        last: true
        icon: ""
        tint: Theme.tertiary
        label: "Widget Scale"
        from: 50
        to: 200
        stepSize: 5
        unit: "%"
        value: Theme.workspaceScale * 100
        onMoved: v => Theme.setWorkspaceScale(v / 100)
        onApplied: v => Theme.setWorkspaceScale(v / 100)
    }
}
