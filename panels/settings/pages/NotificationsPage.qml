pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import ".."

NexusControls.PageBase {
    id: root
    title: "Notifications"

    readonly property var positionOptions: [
        { id: "top-left", label: "Top Left" },
        { id: "top-center", label: "Top Center" },
        { id: "top-right", label: "Top Right" },
        { id: "bottom-left", label: "Bottom Left" },
        { id: "bottom-center", label: "Bottom Center" },
        { id: "bottom-right", label: "Bottom Right" }
    ]
    function positionLabelFor(id: string): string {
        for (let i = 0; i < root.positionOptions.length; i++)
            if (root.positionOptions[i].id === id) return root.positionOptions[i].label
        return "Top Right"
    }

    NexusControls.SectionHeader { first: true; text: "Position" }
    NexusControls.DropdownRow {
        first: true
        last: true
        label: "Position"
        subtext: "Screen corner that hosts the toasts"
        options: root.positionOptions.map(p => p.label)
        current: root.positionLabelFor(Theme.notifPosition)
        onPicked: v => {
            let m = root.positionOptions.find(p => p.label === v)
            if (m) Theme.setNotifPosition(m.id)
        }
    }
    NexusControls.SectionHeader { text: "Timing" }
    NexusControls.SliderRow { first: true; last: true; icon: "󰂚"; label: "Timeout"; from: 0; to: 30; stepSize: 1; unit: "s"; value: Theme.notifTimeout; onMoved: v => Theme.setNotifTimeout(Math.round(v)); onApplied: v => Theme.setNotifTimeout(Math.round(v)) }

    NexusControls.SectionHeader { text: "Focus" }
    NexusControls.ToggleRow {
        first: true
        last: true
        icon: "󰂚"
        tint: Theme.tertiary
        text: "Do Not Disturb"
        checked: Theme.dndEnabled
        onToggled: n => Theme.setDndEnabled(n)
    }

    // Transient on-screen displays share this page with the toasts (both are
    // "notification" surfaces), housed in Settings > Panels > Notifications.
    NexusControls.SectionHeader { text: "OSD screens" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰕾"
        text: "Volume OSD"
        subtext: "Volume and mute changes"
        checked: Theme.osdVolumeEnabled
        onToggled: n => Theme.setOsdVolumeEnabled(n)
    }
    NexusControls.ToggleRow {
        icon: "󰖔"
        tint: Theme.tertiary
        text: "Layout OSD"
        subtext: "Compositor layout switches"
        checked: Theme.osdLayoutEnabled
        onToggled: n => Theme.setOsdLayoutEnabled(n)
    }
    NexusControls.ToggleRow {
        icon: "󰏘"
        tint: Theme.secondary
        text: "Theme OSD"
        subtext: "Theme and color scheme switches"
        checked: Theme.osdThemeEnabled
        onToggled: n => Theme.setOsdThemeEnabled(n)
    }
    NexusControls.SliderRow {
        last: true
        icon: "󱎫"
        label: "OSD Duration"
        from: 0.5
        to: 5
        stepSize: 0.5
        unit: "s"
        value: Theme.osdDuration / 1000
        onMoved: v => Theme.setOsdDuration(Math.round(v * 1000))
        onApplied: v => Theme.setOsdDuration(Math.round(v * 1000))
    }
}
