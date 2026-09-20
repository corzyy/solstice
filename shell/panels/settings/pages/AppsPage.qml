pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import "../../../services"
import ".."

NexusControls.PageBase {
    id: root
    title: "Apps"

    NexusControls.SectionHeader { first: true; text: "Kitty Terminal" }
    NexusControls.SliderRow { first: true; icon: "󰀻"; label: "Padding"; from: 0; to: 40; stepSize: 1; unit: "px"; value: SettingsService.kittyPadding; onMoved: v => SettingsService.applyKittyPadding(v); onApplied: v => SettingsService.applyKittyPadding(v) }
    NexusControls.SliderRow { icon: "󰀻"; tint: Theme.tertiary; label: "Font Size"; from: 6; to: 32; stepSize: 0.5; unit: "pt"; value: SettingsService.kittyFontSize; onMoved: v => SettingsService.applyKittyFont(v); onApplied: v => SettingsService.applyKittyFont(v) }
    NexusControls.SliderRow { last: true; icon: "󰀻"; label: "Opacity"; from: 0.3; to: 1.0; stepSize: 0.05; value: SettingsService.kittyOpacity; onMoved: v => SettingsService.applyKittyOpacity(v); onApplied: v => SettingsService.applyKittyOpacity(v) }

    NexusControls.SectionHeader { text: "Fish Prompt" }
    NexusControls.DropdownRow {
        first: true
        last: true
        icon: "󰀻"
        tint: Theme.tertiary
        label: "Style"
        options: ["minimal", "starship", "tide", "pure"]
        current: SettingsService.fishPrompt
        onPicked: v => SettingsService.applyFishPrompt(v)
    }
}
