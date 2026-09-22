pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import "../../../../backend/services"
import ".."

// Hyprland compositor page. Changes are written to
// ~/.config/hypr/configs/solstice.lua (shell-managed require at the end of
// hyprland.lua) and applied live through `hyprctl keyword`.
NexusControls.PageBase {
    id: root
    title: "Hyprland"

    NexusControls.SectionHeader { first: true; text: "Gaps" }
    NexusControls.SliderRow {
        first: true
        icon: "󰖔"
        label: "Inner gaps"
        from: 0
        to: 50
        stepSize: 1
        unit: "px"
        value: HyprlandService.hyprGapsIn
        onMoved: v => HyprlandService.preview("gapsIn", Math.round(v))
        onApplied: v => HyprlandService.applyGapsIn(v)
    }
    NexusControls.SliderRow {
        last: true
        icon: "󰖔"
        tint: Theme.tertiary
        label: "Outer gaps"
        from: 0
        to: 50
        stepSize: 1
        unit: "px"
        value: HyprlandService.hyprGapsOut
        onMoved: v => HyprlandService.preview("gapsOut", Math.round(v))
        onApplied: v => HyprlandService.applyGapsOut(v)
    }
    NexusControls.Note {
        text: "Writes configs/solstice.lua (shell-managed, required last) and applies the values live with hyprctl keyword — no reload needed."
    }

    NexusControls.SectionHeader { text: "Windows" }
    NexusControls.SliderRow {
        first: true
        last: true
        icon: "󰖔"
        label: "Border width"
        from: 0
        to: 8
        stepSize: 1
        unit: "px"
        value: HyprlandService.hyprBorderSize
        onMoved: v => HyprlandService.preview("borderSize", Math.round(v))
        onApplied: v => HyprlandService.applyBorderSize(v)
    }
    NexusControls.Note {
        text: "Window rounding follows Appearance > Rounding."
    }

    NexusControls.SectionHeader { text: "Shadow" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰖔"
        text: "Enabled"
        checked: HyprlandService.hyprShadow
        onToggled: n => HyprlandService.applyShadow(n)
    }
    NexusControls.SliderRow {
        last: true
        icon: "󰖔"
        tint: Theme.tertiary
        label: "Range"
        from: 0
        to: 40
        stepSize: 1
        unit: "px"
        value: HyprlandService.hyprShadowRange
        onMoved: v => HyprlandService.preview("shadowRange", Math.round(v))
        onApplied: v => HyprlandService.applyShadowRange(v)
    }

    NexusControls.SectionHeader { text: "Animations" }
    NexusControls.ToggleRow {
        first: true
        last: true
        icon: "󰒓"
        text: "Enabled"
        subtext: "Master switch for Hyprland animations"
        checked: HyprlandService.hyprAnimations
        onToggled: n => HyprlandService.applyAnimations(n)
    }

    NexusControls.SectionHeader { text: "Panel blur" }
    NexusControls.SliderRow {
        first: true
        last: true
        icon: "󰔎"
        label: "Panel blur"
        from: 0
        to: 100
        stepSize: 1
        unit: "%"
        value: Math.round(Theme.panelBlur * 100)
        onMoved: v => Theme.setPanelBlur(v / 100)
        onApplied: v => Theme.setPanelBlur(v / 100)
    }
    NexusControls.Note {
        text: "Frosted bar and panels: blurs the wallpaper behind the shell surfaces through Hyprland layer rules (managed in configs/solstice.lua, applied live). 0% turns it off. Only visible with translucent panels (Appearance > Transparency); the blur radius itself is set in looknfeel.lua."
    }
    NexusControls.Note {
        text: "Border and shadow colours follow the wallpaper through the Hyprland app-theming template (configs/colors.lua)."
    }
}
