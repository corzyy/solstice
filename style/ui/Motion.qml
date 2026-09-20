// Motion — M3 transition-pattern driver (one instance per content slot).
//
// Implements the patterns from
// m3.material.io/styles/motion/transitions/transition-patterns:
//   FadeThrough   unrelated content (category/tab swaps). The old slot fades
//                 out over the first 35% of the run; the new slot fades in
//                 afterwards while scaling 92% -> 100%.
//   SharedAxisX   lateral navigation (sibling pages). Both slots slide 30dp
//                 on x and fade. direction +1: new enters from the right,
//                 old exits left.
//   SharedAxisY   vertical navigation (steps in a flow): same on y.
//   SharedAxisZ   parent/child navigation (drill-down). Both slots scale and
//                 fade. direction +1: new 80% -> 100%, old 100% -> 110%;
//                 direction -1 mirrors it.
//
// Timing follows m3.material.io/styles/motion/easing-and-duration:
// emphasized easing cubic-bezier(0.2, 0, 0, 1), 300ms fade through / 400ms
// shared axis. Durations collapse to 0 when animations are disabled.
//
// Hosts bind their visuals to the readonly outputs and flip `active`:
//   Ui.Motion { id: motion; active: isCurrent; pattern: Ui.Motion.SharedAxisX }
//   opacity: motion.opacity; x: motion.x; scale: motion.scale
// Set `direction` before flipping `active`. complete() snaps a run to its
// end state (cold opens and mid-flight retargets that must not replay).
pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

QtObject {
    id: root

    enum Pattern {
        FadeThrough = 0,
        SharedAxisX,
        SharedAxisY,
        SharedAxisZ
    }

    property bool active: false
    property int pattern: Motion.FadeThrough
    // +1 forward (x: left, y: up, z: into the screen), -1 backward.
    property int direction: 1
    property bool enabled: Theme.animationsEnabled
    // Animated run progress. 0 = hidden pose, 1 = settled pose.
    property real phase: 0

    readonly property int _duration: {
        if (!root.enabled) return 0
        return root.pattern === Motion.FadeThrough ? Theme.durMotionFadeThrough : Theme.durMotionSharedAxis
    }
    // Object-valued properties: QtObject has no default property to hold
    // animation children, so the runners live here.
    property NumberAnimation _enterAnimation: NumberAnimation {
        target: root
        property: "phase"
        to: 1
        duration: root._duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveMotion
    }
    property NumberAnimation _exitAnimation: NumberAnimation {
        target: root
        property: "phase"
        to: 0
        duration: root._duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveMotion
    }

    // _ready guards against binding-order effects while the component is
    // still being constructed (required `active` can bind before the
    // animation properties exist).
    property bool _ready: false
    Component.onCompleted: {
        root._ready = true
        root.phase = root.active ? 1 : 0
    }
    onActiveChanged: {
        if (!root._ready) return
        _enterAnimation.stop()
        _exitAnimation.stop()
        if (!root.enabled) {
            root.phase = root.active ? 1 : 0
            return
        }
        if (root.active) _enterAnimation.start()
        else _exitAnimation.start()
    }
    onEnabledChanged: if (root._ready && !root.enabled) root.complete()
    function complete(): void {
        _enterAnimation.stop()
        _exitAnimation.stop()
        root.phase = root.active ? 1 : 0
    }
    // One-shot enter run from the hidden pose (e.g. a new month sliding in).
    function replay(): void {
        if (!root.active) return
        _enterAnimation.stop()
        _exitAnimation.stop()
        if (!root.enabled) {
            root.phase = 1
            return
        }
        root.phase = 0
        _enterAnimation.start()
    }

    // Material fade-through thresholds: outgoing fades over [0, 0.35] of the
    // run, incoming over [0.35, 1].
    readonly property real _fadeIn: Math.max(0, Math.min(1, (phase - Theme.motionFadeThroughExit) / Theme.motionFadeThroughEnter))
    readonly property real _fadeOut: Math.max(0, Math.min(1, (phase - (1 - Theme.motionFadeThroughExit)) / Theme.motionFadeThroughExit))

    readonly property real opacity: root.enabled ? (root.active ? _fadeIn : _fadeOut) : (root.active ? 1 : 0)

    readonly property real scale: {
        if (!root.enabled) return 1
        if (root.pattern === Motion.FadeThrough)
            return root.active ? Theme.motionFadeThroughScale + (1 - Theme.motionFadeThroughScale) * _fadeIn : 1
        if (root.pattern === Motion.SharedAxisZ) {
            if (root.active)
                return root.direction > 0 ? Theme.motionAxisZScaleIn + (1 - Theme.motionAxisZScaleIn) * _fadeIn : Theme.motionAxisZScaleOut - (Theme.motionAxisZScaleOut - 1) * _fadeIn
            return root.direction > 0 ? 1 + (Theme.motionAxisZScaleOut - 1) * (1 - _fadeOut) : Theme.motionAxisZScaleIn + (1 - Theme.motionAxisZScaleIn) * _fadeOut
        }
        return 1
    }

    readonly property real x: {
        if (!root.enabled || root.pattern !== Motion.SharedAxisX) return 0
        const d = Theme.motionSlideDistance * root.direction
        return root.active ? d * (1 - root.phase) : -d * (1 - root.phase)
    }
    readonly property real y: {
        if (!root.enabled || root.pattern !== Motion.SharedAxisY) return 0
        const d = Theme.motionSlideDistance * root.direction
        return root.active ? d * (1 - root.phase) : -d * (1 - root.phase)
    }
}
