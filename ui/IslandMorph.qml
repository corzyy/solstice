// IslandMorph — Dynamic-Island open morph geometry for bar panels.
//
// Pure function of the PanelSpring `grow` driver (0 = compact pill tucked
// at the bar, 1 = full panel): compact size -> full size, corner radius
// pill -> open radius. Grow overshoots slightly past 1 mid-flight (spatial
// curve), which reads as the island bounce; `t` is the clamped 0..1 twin
// for values that must not overshoot (radius, opacities).
//
// Call sites keep their open-geometry bindings as the full-size inputs and
// only swap the rendered size/radius to w/h/radius:
//   width: island.w; height: island.h; radius: island.radius
// Because w/h converge exactly to fullW/fullH at grow == 1, the handoff to
// post-open size Behaviors is seamless. Content columns keep their FULL
// width (never parent.width) so text never reflows mid-morph; the clip on
// the scrolling container turns the growth into a curtain reveal.
pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

Item {
    id: root
    visible: false

    required property real grow
    required property real fullW
    required property real fullH
    // Launch-widget width (0 when the bar anchor is unknown): the pill
    // starts widget-sized, centered on the widget by the BarAnchor math.
    property real anchorW: 0
    property real openRadius: 0

    // Clamped progress (opacities, radius) and unclamped progress (size,
    // so the spatial overshoot becomes a bounce past full size).
    readonly property real t: Math.max(0, Math.min(1, grow))
    readonly property real gu: Math.max(0, grow)

    readonly property real compactW: Math.min(fullW, Math.max(96, anchorW + 40))
    readonly property real compactH: Math.min(fullH, Theme.barThickness + 12)

    readonly property real w: compactW + (fullW - compactW) * gu
    readonly property real h: compactH + (fullH - compactH) * gu
    readonly property real radius: openRadius + (Math.min(w, h) / 2 - openRadius) * (1 - t)
}
