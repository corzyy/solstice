pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import ".."

// Launcher settings, reached through Settings > Panels > Launcher.
// Covers the bar OS icon and the launcher popup (size, descriptions,
// result cap). The panel itself lives in shell/panels/LauncherPanel.qml.
NexusControls.PageBase {
    id: root
    title: "Launcher"

    NexusControls.SectionHeader { first: true; text: "Taskbar" }
    NexusControls.ToggleRow {
        first: true
        last: true
        icon: ""
        text: "Show icon in taskbar"
        subtext: "Operating system logo at the left end of the bar"
        checked: !Theme.isBarModuleHidden("launcher")
        onToggled: n => {
            if (n) Theme.showBarModule("launcher")
            else Theme.hideBarModule("launcher")
        }
    }
    NexusControls.SectionHeader { text: "Panel" }
    NexusControls.StepperRow {
        first: true
        label: "Width"
        subtext: "Launcher panel width"
        value: Theme.launcherWidth
        from: 360
        to: 900
        stepSize: 20
        onMoved: v => Theme.setLauncherWidth(v)
    }
    NexusControls.StepperRow {
        label: "Height"
        subtext: "Launcher panel height"
        value: Theme.launcherHeight
        from: 280
        to: 900
        stepSize: 20
        onMoved: v => Theme.setLauncherHeight(v)
    }
    NexusControls.ToggleRow {
        last: true
        text: "Show descriptions"
        subtext: "Application comment under the application name"
        checked: Theme.launcherShowDescriptions
        onToggled: n => Theme.setLauncherShowDescriptions(n)
    }

    NexusControls.SectionHeader { text: "Search" }
    NexusControls.StepperRow {
        first: true
        label: "Max results"
        subtext: "Maximum number of applications listed"
        value: Theme.launcherMaxResults
        from: 5
        to: 200
        stepSize: 5
        onMoved: v => Theme.setLauncherMaxResults(v)
    }
    NexusControls.TextFieldRow {
        last: true
        label: "Menu prefix"
        subtext: "Type it first to search the extra menus (wallpaper, calculator, …)"
        value: Theme.launcherMenuPrefix
        placeholder: "!"
        onEditingFinished: v => Theme.setLauncherMenuPrefix(v)
    }
}
