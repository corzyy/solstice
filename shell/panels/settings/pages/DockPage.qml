pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import ".."

// Dock settings, reached through Settings > Panels > Dock.
// Port of DankMaterialShell's dock settings tabs (General / Appearance /
// Advanced / Widgets) reduced to the options this port implements; every
// row persists to backend/config/dock.json through Theme.
NexusControls.PageBase {
    id: root
    title: "Dock"

    readonly property var positionIds: ["bottom", "top", "left", "right"]
    readonly property var positionLabels: ["Bottom", "Top", "Left", "Right"]
    function positionLabelFor(id: string): string {
        const i = root.positionIds.indexOf(id)
        return i >= 0 ? root.positionLabels[i] : root.positionLabels[0]
    }
    readonly property var indicatorIds: ["circle", "line"]
    readonly property var indicatorLabels: ["Circle", "Line"]
    function indicatorLabelFor(id: string): string {
        const i = root.indicatorIds.indexOf(id)
        return i >= 0 ? root.indicatorLabels[i] : root.indicatorLabels[0]
    }
    readonly property var pinnedList: Theme.dockPinnedApps()

    NexusControls.SectionHeader { first: true; text: "General" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰍹"
        text: "Enable dock"
        subtext: "Pinned launchers and running apps on the screen edge"
        checked: Theme.dockEnabled
        onToggled: n => Theme.setDockEnabled(n)
    }
    NexusControls.DropdownRow {
        last: true
        label: "Position"
        subtext: "Screen edge the dock sits on"
        options: root.positionLabels
        current: root.positionLabelFor(Theme.dockPosition)
        onPicked: v => {
            const i = root.positionLabels.indexOf(v)
            if (i >= 0) Theme.setDockPosition(root.positionIds[i])
        }
    }

    NexusControls.SectionHeader { text: "Visibility" }
    NexusControls.ToggleRow {
        first: true
        text: "Auto-hide"
        subtext: "Collapse to an edge strip, reveal on hover"
        checked: Theme.dockAutoHide
        onToggled: n => Theme.setDockAutoHide(n)
    }
    NexusControls.ToggleRow {
        text: "Overlay layer"
        subtext: "Float above fullscreen windows instead of the top layer"
        checked: Theme.dockOverlay
        onToggled: n => Theme.setDockOverlay(n)
    }
    NexusControls.ToggleRow {
        last: true
        text: "Show on fullscreen"
        subtext: "Keep the dock visible over fullscreen windows"
        checked: Theme.dockShowFullscreen
        onToggled: n => Theme.setDockShowFullscreen(n)
    }

    NexusControls.SectionHeader { text: "Appearance" }
    NexusControls.SliderRow {
        first: true
        icon: "󰍹"
        label: "Icon size"
        from: 16
        to: 96
        stepSize: 1
        unit: "px"
        value: Theme.dockIconSize
        onMoved: v => Theme.setDockIconSize(Math.round(v))
        onApplied: v => Theme.setDockIconSize(Math.round(v))
    }
    NexusControls.SliderRow {
        icon: "󰕰"
        label: "Padding"
        from: 0
        to: 32
        stepSize: 1
        unit: "px"
        value: Theme.dockSpacing
        onMoved: v => Theme.setDockSpacing(Math.round(v))
        onApplied: v => Theme.setDockSpacing(Math.round(v))
    }
    NexusControls.SliderRow {
        icon: "󰕰"
        tint: Theme.tertiary
        label: "Item spacing"
        from: 0
        to: 32
        stepSize: 1
        unit: "px"
        value: Theme.dockItemSpacing
        onMoved: v => Theme.setDockItemSpacing(Math.round(v))
        onApplied: v => Theme.setDockItemSpacing(Math.round(v))
    }
    NexusControls.SliderRow {
        icon: "󰖔"
        label: "Edge margin"
        from: 0
        to: 100
        stepSize: 1
        unit: "px"
        value: Theme.dockMargin
        onMoved: v => Theme.setDockMargin(Math.round(v))
        onApplied: v => Theme.setDockMargin(Math.round(v))
    }
    NexusControls.SliderRow {
        icon: "󰂵"
        tint: Theme.tertiary
        label: "Opacity"
        from: 0.3
        to: 1.0
        stepSize: 0.05
        value: Theme.dockOpacity
        onMoved: v => Theme.setDockOpacity(v)
        onApplied: v => Theme.setDockOpacity(v)
    }
    NexusControls.ToggleRow {
        last: true
        text: "Border"
        subtext: "Accent outline around the dock card"
        checked: Theme.dockBorderEnabled
        onToggled: n => Theme.setDockBorderEnabled(n)
    }

    NexusControls.SectionHeader { text: "Apps" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰍉"
        text: "Launcher button"
        subtext: "OS icon that opens the app launcher"
        checked: Theme.dockLauncherEnabled
        onToggled: n => Theme.setDockLauncherEnabled(n)
    }
    NexusControls.ToggleRow {
        text: "Group by app"
        subtext: "One icon per app; click cycles its windows"
        checked: Theme.dockGroupByApp
        onToggled: n => Theme.setDockGroupByApp(n)
    }
    NexusControls.ToggleRow {
        text: "Current workspace only"
        subtext: "Show only windows from the active workspace"
        checked: Theme.dockCurrentWorkspaceOnly
        onToggled: n => Theme.setDockCurrentWorkspaceOnly(n)
    }
    NexusControls.ToggleRow {
        text: "Running indicators"
        subtext: "Dot under icons with open windows"
        checked: Theme.dockShowIndicators
        onToggled: n => Theme.setDockShowIndicators(n)
    }
    NexusControls.DropdownRow {
        label: "Indicator style"
        subtext: "Shape of the running marker"
        options: root.indicatorLabels
        current: root.indicatorLabelFor(Theme.dockIndicatorStyle)
        onPicked: v => {
            const i = root.indicatorLabels.indexOf(v)
            if (i >= 0) Theme.setDockIndicatorStyle(root.indicatorIds[i])
        }
    }
    NexusControls.ToggleRow {
        last: true
        text: "Magnify on hover"
        subtext: "Enlarge icons under the cursor"
        checked: Theme.dockMagnify
        onToggled: n => Theme.setDockMagnify(n)
    }

    NexusControls.SectionHeader { text: "Pinned apps"; visible: root.pinnedList.length > 0 }
    Repeater {
        model: root.pinnedList
        delegate: NexusControls.NavRow {
            required property var modelData
            required property int index
            icon: "󰀻"
            text: modelData + ""
            subtext: "Pinned — click to unpin"
            first: index === 0
            last: index === root.pinnedList.length - 1
            onClicked: Theme.setDockPinned(modelData + "", false)
        }
    }

    NexusControls.Note {
        text: "Right-click a dock icon for Pin, Focus and Close actions. "
            + "Middle-click closes the window (or launches a pinned app). "
            + "Clicking a grouped icon cycles its windows."
    }
}
