// PanelSpring — open/close animation for all bar panels + menu.
//
// Follows Qt's animation framework (doc.qt.io/qt-6/animation-overview),
// mapped to its QML equivalents:
//   QPropertyAnimation  -> NumberAnimation with explicit to/duration/easing
//   QParallelAnimationGroup -> ParallelAnimation (fade + slide + zoom together)
//   QEasingCurve        -> easing.type on each animation
//   start()/stop()      -> runs are started/stopped explicitly; no Behaviors,
//                          so show/hide always produce exactly one
//                          deterministic run. `from` is intentionally omitted
//                          everywhere: the run starts from the current value,
//                          which keeps rapid open->close->open retargeting
//                          smooth instead of jumping.
//
// Timing: the enter run starts on the first RENDERED frame (FrameAnimation),
// not at Loader creation — async instantiation + surface mapping latency
// would otherwise eat the fade before anything is visible. Exit runs on the
// already-mapped window, so it starts immediately; boxVisible drops in
// onFinished. With animations off everything snaps instantly.
//
// Property names are the long-standing call-site contract (PanelShell,
// NotificationCenterPanel, SystemTrayPanel, ControlCenterPanel all bind
// visible/opacity/scale/Translate to boxVisible/fade/zoom/slideX/slideY).
pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

Item {
    id: root
    visible: false
    required property bool shown
    required property real hiddenX
    required property real hiddenY
    property bool minimal: false
    // Subtle mode (centered modals): nudge a few px + fade instead of the
    // full emerge-from-bar travel. Bar-anchored panels leave this off so
    // open slides the box its full height out from behind the bar edge.
    property bool slideFade: false
    property real slideFadeDist: 12

    // Island morph driver: 0 = compact pill tucked at the bar, 1 = full
    // panel. Full-travel mode animates it (DefaultSpatial out, FastEffects
    // back); minimal/slideFade modes hold 1 (fade/nudge only, no size
    // morph). Call sites bind island geometry (style/ui/IslandMorph) to this so
    // shape and position can never desync from the open run.
    property real grow: 1
    // True once the enter run has fully completed. Gates position/size
    // Behaviors on call sites so they only chase post-open changes, never
    // the open morph itself.
    property bool settled: false
    function growHidden(): real { return (root.minimal || root.slideFade) ? 1 : 0 }

    readonly property bool anim: Theme.animationsEnabled

    // Hidden-state targets: minimal fades only; slideFade nudges a few px
    // toward the bar; otherwise the box tucks its full hidden distance
    // behind the bar edge (hiddenX/Y already encode the bar side).
    function hx(): real {
        if (minimal) return 0
        if (slideFade) {
            if (hiddenX > 0) return slideFadeDist
            if (hiddenX < 0) return -slideFadeDist
            return 0
        }
        return hiddenX
    }
    function hy(): real {
        if (minimal) return 0
        if (slideFade) {
            if (hiddenY > 0) return slideFadeDist
            if (hiddenY < 0) return -slideFadeDist
            return 0
        }
        return hiddenY
    }
    readonly property real hiddenZoom: minimal ? 1.0 : 0.96

    // Rendered values. Plain properties with constant initializers plus
    // imperative setup in onCompleted: binding initializers that read
    // `shown`/`anim` proved order-sensitive at instantiation time (the
    // spring could start at the visible values with no way back), while
    // direct assignment in onCompleted always lands before the first frame.
    property real fade: 0
    property real zoom: 1
    property real slideX: 0
    property real slideY: 0
    // Plain property, set imperatively: a `shown` binding here would hide
    // the box the instant shown flips, cutting the exit run off mid-flight.
    property bool boxVisible: false
    readonly property int hideDelay: Theme.panelHideDelay

    // Enter run: fade + directional slide + settle zoom + island grow, in
    // parallel. Caelestia-expressive: fade rides DefaultEffects (200ms),
    // slide/zoom/grow ride the panel-open curve (Theme.curvePanelOpen over
    // the DefaultSpatial duration): the reference shell's drawer curve with
    // the overshoot cut back, so the full-height travel settles instead of
    // bouncing.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "fade"; to: 1; duration: Theme.panelAnimFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
        NumberAnimation { target: root; property: "slideX"; to: 0; duration: Theme.panelAnimSlide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curvePanelOpen }
        NumberAnimation { target: root; property: "slideY"; to: 0; duration: Theme.panelAnimSlide; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curvePanelOpen }
        NumberAnimation { target: root; property: "zoom"; to: 1; duration: Theme.panelAnimScale; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curvePanelOpen }
        NumberAnimation { target: root; property: "grow"; to: 1; duration: Theme.durDefaultSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curvePanelOpen }
        onFinished: if (root.shown) root.settled = true
    }
    // Exit run: quick fade/slide back. The slide `to` values are stamped in
    // startExit(): `to` bindings on a function result would go stale, while
    // assigning at start() time always uses the current geometry.
    // Caelestia-expressive: FastEffects out (150ms, [0.31,0.94,0.34,1]).
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "fade"; to: 0; duration: Theme.panelAnimExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        NumberAnimation { id: exitSlideX; target: root; property: "slideX"; duration: Theme.panelAnimExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        NumberAnimation { id: exitSlideY; target: root; property: "slideY"; duration: Theme.panelAnimExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        NumberAnimation { target: root; property: "zoom"; to: root.hiddenZoom; duration: Theme.panelAnimExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        NumberAnimation { id: exitGrow; target: root; property: "grow"; duration: Theme.panelAnimExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
        onFinished: { root.settled = false; if (!root.shown) root.boxVisible = false }
    }
    // One-shot first-frame trigger for cold opens (fresh Loader item).
    FrameAnimation {
        id: enterFrame
        running: false
        onTriggered: {
            running = false
            startEnter()
        }
    }

    function startEnter(): void {
        enterFrame.running = false
        exitAnim.stop()
        root.boxVisible = true
        root.settled = false
        if (!root.anim) {
            enterAnim.stop()
            root.fade = 1
            root.zoom = 1
            root.slideX = 0
            root.slideY = 0
            root.grow = 1
            root.settled = true
            return
        }
        enterAnim.start()
    }
    function startExit(): void {
        enterFrame.running = false
        enterAnim.stop()
        root.settled = false
        if (!root.anim || root.hideDelay <= 0) {
            exitAnim.stop()
            root.fade = 0
            root.zoom = root.hiddenZoom
            root.slideX = hx()
            root.slideY = hy()
            root.grow = growHidden()
            root.boxVisible = false
            return
        }
        exitSlideX.to = hx()
        exitSlideY.to = hy()
        exitGrow.to = growHidden()
        exitAnim.start()
    }

    property bool _ready: false
    onShownChanged: {
        if (!root._ready) return
        if (root.shown) startEnter()
        else startExit()
    }
    onHiddenXChanged: if (!root.shown && !exitAnim.running) root.slideX = hx()
    onHiddenYChanged: if (!root.shown && !exitAnim.running) root.slideY = hy()
    // Toggle flipped at runtime: stop everything, snap to the end state.
    // The _ready guard skips the spurious fire at instantiation, when the
    // `anim` binding first takes effect (reading it would otherwise snap
    // every fresh spring straight to the visible values, voiding the
    // enter run before it starts).
    onAnimChanged: {
        if (!root._ready) return
        enterFrame.running = false
        enterAnim.stop()
        exitAnim.stop()
        if (root.shown) {
            root.boxVisible = true
            root.fade = 1
            root.zoom = 1
            root.slideX = 0
            root.slideY = 0
            root.grow = 1
            root.settled = true
        } else {
            root.fade = 0
            root.zoom = root.hiddenZoom
            root.slideX = hx()
            root.slideY = hy()
            root.grow = growHidden()
            root.boxVisible = false
        }
    }

    Component.onCompleted: {
        if (root.shown && root.anim) {
            // Cold open: park at the hidden values now (pre-first-frame),
            // then arm the first-frame trigger. The window is already
            // marked visible (boxVisible) so frames render; the run itself
            // starts once content can actually be seen.
            root.fade = 0
            root.zoom = root.hiddenZoom
            root.slideX = hx()
            root.slideY = hy()
            root.grow = growHidden()
            root.boxVisible = true
            enterFrame.running = true
        } else if (root.shown) {
            root.fade = 1
            root.zoom = 1
            root.slideX = 0
            root.slideY = 0
            root.grow = 1
            root.boxVisible = true
        } else {
            root.fade = 0
            root.zoom = root.hiddenZoom
            root.slideX = hx()
            root.slideY = hy()
            root.grow = growHidden()
            root.boxVisible = false
        }
        _ready = true
    }
}
