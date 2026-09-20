pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import "../../../services"
import ".."

// Umbriel appearance page. Changes are written to
// ~/.config/umbriel/configs/shell.toml (shell-managed optional include) and
// applied live.
NexusControls.PageBase {
    id: root
    title: "Umbriel"

    NexusControls.SectionHeader { first: true; text: "Layout" }
    Row {
        width: parent.width; spacing: 8
        Repeater {
            model: [
                { id: "dwindle", label: "Dwindle" },
                { id: "scrolling", label: "Scrolling" },
                { id: "master", label: "Master" }
            ]
            delegate: NexusControls.PreviewTile {
                required property var modelData
                readonly property string layId: modelData.id
                readonly property bool isCurrent: UmbrielService.umbLayout === layId
                width: (parent.width - 16) / 3; height: 78
                selected: isCurrent
                label: modelData.label
                onClicked: UmbrielService.applyLayout(layId)
                Rectangle {
                    antialiasing: Theme.shapesAa
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44
                    height: 30
                    radius: 2
                    color: "transparent"
                    border.color: isCurrent ? Theme.accent : Theme.divider
                    border.width: 1
                    // Dwindle: recursive split — master left, right stacked then split
                    Rectangle {
                        visible: layId === "dwindle"
                        x: 2; y: 2; width: 19; height: 26; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.accent; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "dwindle"
                        x: 23; y: 2; width: 19; height: 12; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "dwindle"
                        x: 23; y: 16; width: 8; height: 12; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "dwindle"
                        x: 33; y: 16; width: 9; height: 12; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                    // Scrolling: full-height window strip, focused center
                    Rectangle {
                        visible: layId === "scrolling"
                        x: 2; y: 2; width: 10; height: 26; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "scrolling"
                        x: 14; y: 2; width: 16; height: 26; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.accent; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "scrolling"
                        x: 32; y: 2; width: 10; height: 26; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                    // Master: master area left, stack rows right
                    Rectangle {
                        visible: layId === "master"
                        x: 2; y: 2; width: 18; height: 26; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.accent; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "master"
                        x: 22; y: 2; width: 20; height: 12; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                    Rectangle {
                        visible: layId === "master"
                        x: 22; y: 16; width: 20; height: 12; radius: 1
                        color: Theme.withAlpha(Theme.textPrimary, 0.10)
                        border.color: Theme.divider; border.width: 1
                    }
                }
            }
        }
    }
    NexusControls.Note {
        text: "Writes configs/shell.toml (shell-managed, overrides the hand-written configs) and reloads Umbriel live."
    }

    NexusControls.SectionHeader { text: "Gaps & Borders" }
    NexusControls.SliderRow { first: true; icon: "󰖔"; label: "Gap"; from: 0; to: 100; stepSize: 1; unit: "px"; value: UmbrielService.umbGap; onMoved: v => UmbrielService.preview("gap", Math.round(v)); onApplied: v => UmbrielService.applyGap(v) }
    NexusControls.SliderRow { last: true; icon: "󰖔"; tint: Theme.tertiary; label: "Border Size"; from: 0; to: 20; stepSize: 1; unit: "px"; value: UmbrielService.umbBorderWidth; onMoved: v => UmbrielService.preview("borderWidth", Math.round(v)); onApplied: v => UmbrielService.applyBorderWidth(v) }

    NexusControls.SectionHeader { text: "Animations" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰒓"
        text: "Enabled"
        checked: UmbrielService.umbAnimations
        onToggled: n => UmbrielService.applyAnimations(n)
    }
    NexusControls.DropdownRow {
        icon: "󰒓"
        label: "Open"
        options: ["popin", "zoom", "slide", "fade", "none"]
        current: UmbrielService.umbAnimOpen
        onPicked: v => UmbrielService.applyAnimType("open", v)
    }
    NexusControls.DropdownRow {
        icon: "󰒓"
        label: "Close"
        options: ["fade", "slide"]
        current: UmbrielService.umbAnimClose
        onPicked: v => UmbrielService.applyAnimType("close", v)
    }
    NexusControls.SliderRow { icon: "󰒓"; label: "Open Duration"; from: 50; to: 2000; stepSize: 10; unit: "ms"; value: UmbrielService.umbAnimDurOpen; onMoved: v => UmbrielService.preview("animDurOpen", Math.round(v)); onApplied: v => UmbrielService.applyAnimDur("open", v) }
    NexusControls.SliderRow { icon: "󰒓"; tint: Theme.tertiary; label: "Close Duration"; from: 50; to: 2000; stepSize: 10; unit: "ms"; value: UmbrielService.umbAnimDurClose; onMoved: v => UmbrielService.preview("animDurClose", Math.round(v)); onApplied: v => UmbrielService.applyAnimDur("close", v) }
    NexusControls.SliderRow { icon: "󰒓"; label: "Move Duration"; from: 50; to: 2000; stepSize: 10; unit: "ms"; value: UmbrielService.umbAnimDurMove; onMoved: v => UmbrielService.preview("animDurMove", Math.round(v)); onApplied: v => UmbrielService.applyAnimDur("move", v) }
    NexusControls.SliderRow { last: true; icon: "󰒓"; tint: Theme.tertiary; label: "Workspace Duration"; from: 50; to: 2000; stepSize: 10; unit: "ms"; value: UmbrielService.umbAnimDurWorkspace; onMoved: v => UmbrielService.preview("animDurWorkspace", Math.round(v)); onApplied: v => UmbrielService.applyAnimDur("workspace", v) }

    NexusControls.SectionHeader { text: "Effects" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰖔"
        text: "Blur"
        subtext: "Window and layer blur engine"
        checked: UmbrielService.umbBlurEnabled
        onToggled: n => UmbrielService.applyBlur(n)
    }
    NexusControls.ToggleRow {
        icon: "󰖔"
        text: "Optimized Blur"
        subtext: "One cached background blur per output"
        checked: UmbrielService.umbBlurOptimized
        onToggled: n => UmbrielService.applyBlurOptimized(n)
    }
    NexusControls.ToggleRow {
        icon: "󰖔"
        text: "Optimized Panel Blur"
        subtext: "Shared backdrop for bar and panels"
        checked: UmbrielService.umbShellBlurOptimized
        onToggled: n => UmbrielService.applyShellBlurOptimized(n)
    }
    NexusControls.ToggleRow {
        last: true
        icon: "󰖔"
        text: "Shadows"
        checked: UmbrielService.umbShadowEnabled
        onToggled: n => UmbrielService.applyShadows(n)
    }
}
