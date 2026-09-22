pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import ".."

// Screenshot UI settings, reached through Settings > Panels > Screenshot UI.
// The pill itself lives in shell/overlays/ScreenshotUI.qml, the capture backend in
// backend/scripts/screenshot.sh; everything here persists to backend/config/screenshot.json.
NexusControls.PageBase {
    id: root
    title: "Screenshot UI"

    readonly property var modeIds: ["region", "window", "fullscreen"]
    readonly property var modeLabels: ["Region", "Window", "Fullscreen"]
    function modeLabelFor(id: string): string {
        const i = root.modeIds.indexOf(id)
        return i >= 0 ? root.modeLabels[i] : root.modeLabels[0]
    }

    NexusControls.SectionHeader { first: true; text: "Capture" }
    NexusControls.DropdownRow {
        first: true
        label: "Default mode"
        subtext: "Mode the pill opens with (PRINT keybind)"
        options: root.modeLabels
        current: root.modeLabelFor(Theme.screenshotDefaultMode)
        onPicked: v => {
            const i = root.modeLabels.indexOf(v)
            if (i >= 0) Theme.setScreenshotDefaultMode(root.modeIds[i])
        }
    }
    NexusControls.ToggleRow {
        last: true
        icon: "󰆟"
        text: "Include cursor"
        subtext: "Draw the mouse pointer into the shot"
        checked: Theme.screenshotIncludeCursor
        onToggled: n => Theme.setScreenshotIncludeCursor(n)
    }

    NexusControls.SectionHeader { text: "Output" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰅌"
        text: "Copy to clipboard"
        subtext: "Hand the image to wl-copy after capture"
        checked: Theme.screenshotCopyToClipboard
        onToggled: n => Theme.setScreenshotCopyToClipboard(n)
    }
    NexusControls.ToggleRow {
        last: true
        icon: "󰂚"
        tint: Theme.tertiary
        text: "Show notification"
        subtext: "Toast with the saved file after capture"
        checked: Theme.screenshotNotify
        onToggled: n => Theme.setScreenshotNotify(n)
    }

    NexusControls.SectionHeader { text: "Storage" }
    NexusControls.TextFieldRow {
        first: true
        last: true
        label: "Save folder"
        subtext: "Empty = ~/Pictures/Screenshots; ~ is expanded"
        value: Theme.screenshotSaveDir
        placeholder: "~/Pictures/Screenshots"
        onEditingFinished: v => Theme.setScreenshotSaveDir(v)
    }

    NexusControls.Note {
        text: "PRINT toggles the pill. Region opens pre-armed: drag on the "
            + "dimmed overlay to select (pill stays usable), release to capture. "
            + "Window grabs the focused window by geometry, Fullscreen grabs "
            + "every display."
    }
}
