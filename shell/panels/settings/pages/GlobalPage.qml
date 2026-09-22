pragma ComponentBehavior: Bound
import QtQuick
import "../../../../style/themes"
import "../../../../backend/services"
import ".."

NexusControls.PageBase {
    id: root
    title: "Appearance"

    NexusControls.SectionHeader { first: true; text: "Material" }
    NexusControls.SliderRow { first: true; icon: "󰔎"; label: "Transparency"; from: 0; to: 100; stepSize: 1; unit: "%"; value: Math.round(Theme.panelTransparency * 100); onMoved: v => Theme.setPanelTransparency(v / 100); onApplied: v => Theme.setPanelTransparency(v / 100) }
    NexusControls.SliderRow { last: true; icon: "󰔎"; tint: Theme.tertiary; label: "Rounding"; from: 0; to: 40; stepSize: 1; unit: "px"; value: Theme.cornerRadius; onMoved: v => Theme.setCornerRadius(Math.round(v)); onApplied: v => Theme.setCornerRadius(Math.round(v)) }
    NexusControls.SectionHeader { text: "Animations" }
    NexusControls.ToggleRow {
        first: true
        icon: "󰒓"
        text: "Shell Animations"
        subtext: "Panels, menus, toggles and sliders"
        checked: Theme.animationsEnabled
        onToggled: n => Theme.setAnimationsEnabled(n)
    }
    NexusControls.ToggleRow {
        icon: "󰒓"
        tint: Theme.primary
        text: "Fluid Motion"
        subtext: "Less overshoot, smoother without VSync"
        checked: Theme.motionFluid
        onToggled: n => Theme.setMotionFluid(n)
    }
    NexusControls.SliderRow {
        last: true
        icon: "󰒓"
        label: "Animation Speed"
        from: 50; to: 200; stepSize: 10; unit: "%"
        value: Math.round(Theme.animationSpeed * 100)
        onMoved: v => Theme.setAnimationSpeed(v / 100)
        onApplied: v => Theme.setAnimationSpeed(v / 100)
    }

    NexusControls.SectionHeader { text: "Font" }
    NexusControls.SliderRow { first: true; icon: "󰛖"; tint: Theme.primary; label: "Shell Text Size"; from: 85; to: 125; stepSize: 5; unit: "%"; value: Theme.fontScale * 100; onMoved: v => Theme.setFontScale(v / 100); onApplied: v => Theme.setFontScale(v / 100) }
    NexusControls.SliderRow { icon: "󰛖"; tint: Theme.primary; label: "System Text Size"; from: 8; to: 16; stepSize: 1; unit: "pt"; value: Theme.fontSize; onMoved: v => Theme.setFontSize(v); onApplied: v => Theme.setFontSize(v) }
    NexusControls.ToggleRow {
        last: true
        icon: "󰛖"
        tint: Theme.primary
        text: "Bold Text"
        checked: Theme.textBold
        onToggled: n => Theme.setTextBold(n)
    }
}
