// Anim — Caelestia-expressive animation primitives.
//
// Port of caelestia-dots/shell components/Anim.qml + CAnim.qml to jhqs
// Theme tokens:
//   type selects a Material-3-expressive duration + BezierSpline curve
//   (Anim itself), CAnim is the color/opacity counterpart and always uses
//   the slow-effects curve.
// Durations collapse to 0 when Theme.animationsEnabled is off, so callers
// never need their own `enabled:` guards for the global toggle.
//
// Usage: Behavior on x { Anim { type: Anim.DefaultSpatial } }
//        Anim { target: foo; property: "opacity"; to: 0; type: Anim.FastEffects }
//        Behavior on color { Anim.CAnim {} }
pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

NumberAnimation {
    id: root

    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial

    duration: Theme.animDurationFor(type)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.animCurveFor(type)

    // Color/opacity fades always use the slow-effects curve (300ms).
    component CAnim: ColorAnimation {
        duration: Theme.durSlowEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveSlowEffects
    }
}
