// CaelestiaPopout — 1:1 port of Caelestia's bar-popout open/close animation.
//
// Sources (caelestia-dots/shell):
//   modules/bar/popouts/ClipWrapper.qml   offsetScale driver + curtain clip
//   modules/bar/popouts/Wrapper.qml       size Behaviors + slide offset
//   modules/bar/popouts/Content.qml       nested loader fades
//
// Caelestia drives the whole run off a single value, exactly as here:
//   offsetScale        Behavior Anim{}               expressive default spatial
//                                                    (500ms, [0.38,1.21,0.22,1,1,1])
//   axis extent        full * (1 - offsetScale)      curtain reveal, clip: true
//   content offset     (-full - 5) * offsetScale     slides out from behind the bar edge
//   perp position      bar item centre               Behavior Anim{} (ClipWrapper.x/y)
//   full size changes  Behavior Anim{500ms}          (Wrapper implicitWidth/Height)
//   popup fade         0/1, 200ms default effects    (Comp transitions)
//   inner fade         0/1, 300ms slow effects in    (Popout transitions)
//                           200ms default effects out
//
// Caelestia's bar is vertical so its curtain runs on x; the identical math
// runs on y for solstice's top bar.
//
// One addition over the reference: the layer surface only maps on open, so
// the driver waits for the first rendered frame — starting the Behavior at
// the same instant the surface is created would swallow the first frames of
// the run (surface mapping latency) and visibly fast-forward the motion.
//
// Second addition: a drop shadow around the card (see shadowSource, which
// blurs a plain card-shaped rect rather than the card contents). The
// popout reserves extra room past the card's free edge so the shadow can
// paint there, while the curtain clip cuts it along the fused bar edge —
// the panel keeps reading as one mass with the bar.
//
// Third addition: the cross-panel morph (style/ui/PanelMorph). Opening a bar panel
// while another one is already open — and only then; a cold open always
// plays the plain curtain run — no longer plays two independent runs. The
// outgoing content starts leaving the instant the switch begins (instant
// feedback, no waiting for the incoming surface to map) while its card
// holds. The incoming popout maps already at the outgoing card's pose; when
// its first frame lands it waits out only the remainder of the shared
// content lead (PanelMorph.leftAt), swaps its card in at the identical pose
// and glides to its own settled pose on a plain NumberAnimation (no
// curtain): a container transform. The outgoing card is released on the
// same beat and fades underneath it. The incoming content follows with the
// shared-axis travel. Hosts bind content opacity to `contentFade` and the
// transform to `contentScale`/`contentOffset*` (PanelShell does both).
//
// Fourth addition: the overlay container transform. A drill-in opened from
// a control-center tile/button claims the origin's source descriptor
// ({ component, props }, published by the CC) into `_morphSource`; the host
// (PanelShell) renders that replica over the growing card and morphs it
// into the page header. `_overlayContent` is the crossfade between the
// replica (0) and the real page content (1): the open run brings the
// content in over the tail, the return takes it out up front so the replica
// can shrink back into the button.
//
// Fifth addition: interrupted runs never snap. A popout switched away while
// its card is still gliding in freezes at its current pose — the successor
// claimed that same rect — and dissolves in place (`_inFade`), releasing the
// frozen geometry only once it is invisible; a return re-opened mid-collapse
// resumes from the card's current pose instead of snapping back to the
// origin button.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../themes"

Item {
    id: root

    property bool shown: false
    // Open (full) size of the popout. Changes glide on the spatial curve
    // while open (Caelestia Wrapper implicitWidth/implicitHeight).
    property real fullWidth: 300
    property real fullHeight: 200
    // Perpendicular centre the popout tracks: the bar item's centre
    // (Caelestia popouts.currentCenter).
    property real anchorCenter: 0
    // Coordinate of the bar's inner edge: the fixed edge the
    // curtain reveals from (top bar: panel top).
    property real edge: 0
    property real screenSize: 0
    property real margin: 12
    // Offset of the settled card from the fused bar edge (drill-in overlay:
    // the CC sub-panels settle below the control center's tile row). A
    // detached card must not draw the fused bar joint, so the fillet flags
    // below fall away with it.
    property real edgeInset: 0
    // Perpendicular room for the drop shadow on the card's free sides.
    property real perpPad: 48
    // Room past the card's free (far) edge for the drop shadow. The shadow
    // is clipped at the fused bar edge, so the panel stays one mass with
    // the bar.
    property real shadowPad: 48
    // Caelestia's "(-implicitWidth - 5)": the hidden pose clears the far edge.
    readonly property real travel: 5

    default property alias content: holder.data
    readonly property alias offsetScale: root._offsetScale
    // Inner (popout) fold fade, for hosts to bind their content to.
    readonly property alias innerFade: root._innerFade
    // Corners on the bar side stay square: the popout meets the bar edge
    // with a clean right angle instead of a rounded corner cutout. An inset
    // card floats free of the bar, so it keeps its rounded corners.
    readonly property bool fusedTop: root.edgeInset === 0
    // Settled (open) sizes, straight from the host bindings.
    readonly property real settledAxis: fullHeight
    readonly property real settledPerp: fullWidth

    // ---- cross-panel morph (style/ui/PanelMorph, see header) -----------------
    // morphId is the bar module id of the host panel: it keys the published
    // card rect and tells this popout whether it is the outgoing or the
    // incoming side of a switch. `_morphIn` drives the card from the
    // outgoing panel's pose instead of the settled one; `_morphOut` holds
    // the card open until the incoming surface has rendered, then fades it.
    // `_morphDir` snapshots PanelMorph.direction for the content run (it
    // must survive PanelMorph.finish() while the outgoing card still fades).
    property string morphId: ""
    property bool _morphIn: false
    property bool _morphOut: false
    // Overlay drill-in: the card was opened from a button rect (CC tile) and
    // glides back into it on close instead of playing the curtain.
    property bool _morphBack: false
    property bool _overlayOrigin: false
    property bool _morphFade: false
    property bool _morphStarted: false
    property int _morphDir: 0
    // Source descriptor ({ component, props }) published with the origin by
    // the control center: the host (PanelShell) renders it as the
    // container-transform replica. Claimed by _tryMorphIn, held until the
    // return has dissolved into the origin button.
    property var _morphSource: null
    // Overlay container transform: crossfade between the source replica (0)
    // and the real page content (1). Only meaningful while `_overlayOrigin`.
    property real _overlayContent: 1
    // Content choreography (driven by the animations below): the outgoing
    // content leads — it fades/shifts out while the incoming card is still
    // hidden — then the card is swapped in and the incoming content
    // follows. All 0..1 progress values.
    property real _morphCardIn: 1
    property real _morphContentIn: 1
    property real _morphContentOut: 1
    // Interrupted-in dissolve: a popout switched away while its card is still
    // gliding in freezes at its current pose (the successor claimed that same
    // rect) and fades out in place. The flag-based card fade cannot carry it:
    // the holder's opacity Behavior is disabled during morph-in (the card is
    // driven by `_morphCardIn` then), so this animated 1 -> 0 value drives the
    // freeze-and-dissolve instead.
    property real _inFade: 1
    // Only the primary screen's window runs the handoff; the other screen
    // variants share the show flags but never map. Hosts pass
    // Theme.isPrimaryScreen(modelData) down (PanelShell forwards it via
    // screenActive), so this is decided at construction, not at map time.
    property bool morphActive: true
    readonly property bool morphEnabled: Theme.animationsEnabled && root.morphActive
    // Effective sizes/edge: morphed while a run drives `_morphT` (in from a
    // button/panel pose, or back into the origin), settled otherwise.
    readonly property bool _morphing: root._morphIn || root._morphBack
    readonly property real axisSize: root._morphing ? _morphH : settledAxis
    readonly property real perpSize: root._morphing ? _morphW : settledPerp
    readonly property real effEdge: root._morphing ? _morphEdge : edge
    // Overlay-return fade: the card dissolves as it lands on the button (the
    // tile is revealed underneath, not covered by a vanishing card). Keyed to
    // the spatial progress, not the wall clock: the card stays solid while it
    // travels (the standard return curve spreads the distance evenly) and
    // fades only over the last tenth of the distance — by then the replica is
    // within a few pixels of the origin rect — so the CC tile (revealed in
    // lockstep via sourceReveal) crossfades with it at the same pose instead
    // of ghosting next to it mid-flight.
    readonly property real _backFade: root._morphBack
        ? Math.max(0, Math.min(1, root._morphT / 0.1))
        : 1
    // Card rect in window coordinates (== screen coordinates: every panel
    // window is full-screen). Published while open so the next switch can
    // start from the exact pose this card settles at.
    readonly property rect cardRect: Qt.rect(Math.round(x + holder.x), Math.round(y + holder.y), holder.width, holder.height)

    // ---- surface-mapping gate (see header) -----------------------------
    property bool _open: false
    FrameAnimation {
        id: enterFrame
        running: false
        onTriggered: {
            running = false
            root._open = true
            root._publishRect()
        }
    }
    onShownChanged: {
        if (root.shown) {
            morphSettleTimer.stop()
            morphRun.stop()
            morphBackAnim.stop()
            if (root._tryMorphIn())
                return
            morphHoldTimer.stop()
            morphFadeTimer.stop()
            root.stopMorphRuns()
            root._morphIn = false
            root._morphOut = false
            root._morphBack = false
            root._overlayOrigin = false
            root._morphFade = false
            root._open = false
            root._clearOverlaySource()
            enterFrame.running = true
        } else {
            enterFrame.running = false
            morphSettleTimer.stop()
            morphRun.stop()
            if (root._tryMorphOut())
                return
            if (root._tryMorphBack())
                return
            if (root._morphIn) {
                // Dismissed mid-glide (no handoff to hand the pose to):
                // dissolve the frozen card in place instead of releasing
                // `_morphIn` (which would snap the frame to its settled size
                // for the close run).
                root.dropMorphOut()
                return
            }
            morphBackAnim.stop()
            morphHoldTimer.stop()
            morphFadeTimer.stop()
            root.stopMorphRuns()
            root._morphIn = false
            root._morphOut = false
            root._morphBack = false
            root._overlayOrigin = false
            root._morphFade = false
            root._open = false
            root._clearOverlaySource()
        }
    }
    // No overlay return ran (plain open/close, e.g. animations disabled):
    // release the source registration so the button is visible again. Only
    // the morph-active (primary screen) popout may touch it — the other
    // screen variants share the shown flag but never ran the handoff.
    function _clearOverlaySource(): void {
        if (!root.morphActive)
            return
        if (PanelMorph.originId === root.morphId) {
            PanelMorph.originId = ""
            PanelMorph.sourceReveal = 1
        }
    }
    Component.onDestruction: root._clearOverlaySource()
    Component.onCompleted: {
        if (!root.shown)
            return
        if (root._tryMorphIn())
            return
        enterFrame.running = true
    }

    // ---- drivers -------------------------------------------------------
    // Frame driver (ClipWrapper offsetScale): the frame STRETCHES along the
    // bar axis. Its near edge is pinned to the bar, so the panel is attached
    // for the whole run and can never be separated from the bar by a gap.
    // Open rides the panel-open curve (500ms, reduced overshoot: see
    // Theme.curvePanelOpen); close rides the shorter exit token (350ms, no
    // overshoot) so dismissal snaps back. Duration/curve bindings are read
    // when the Behavior fires, i.e. exactly when `_open` flips.
    property real _offsetScale: _open ? 0 : 1
    Behavior on _offsetScale {
        // Morph-in snaps the curtain open: the card is already at the
        // outgoing/origin pose and only glides from there (see morph below).
        // A morph-back snaps it shut once the card has reached the origin.
        enabled: Theme.animationsEnabled && !root._morphIn && !root._morphBack
        NumberAnimation {
            duration: root._open ? Theme.durDefaultSpatial : Theme.panelAnimClose
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root._open ? Theme.curvePanelOpen : Theme.curvePanelClose
        }
    }
    // Content driver: the content rides the same 0/1 range but on its own
    // curve/duration, so the frame stretches first and the content settles
    // after it — the content moves independently of the frame. On close it
    // matches the frame run so both land together.
    property real _contentOffset: _open ? 0 : 1
    Behavior on _contentOffset {
        enabled: Theme.animationsEnabled && !root._morphIn && !root._morphBack
        NumberAnimation {
            duration: root._open ? Theme.durSlowSpatial : Theme.panelAnimClose
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root._open ? Theme.curvePanelOpen : Theme.curvePanelClose
        }
    }

    // ---- morph drivers -------------------------------------------------
    // The incoming card glides from the outgoing pose (primed in
    // `_tryMorphIn` into `_from*`) to the settled pose over one shared
    // 0..1 run. The settled side is read live, so a host geometry change
    // during the glide (content settling after the first frame) is
    // followed instead of being frozen at the value captured at start.
    property real _morphT: 0
    property real _fromW: 0
    property real _fromH: 0
    property real _fromPos: 0
    property real _fromEdge: 0
    readonly property real _morphW: root._fromW + (root.fullWidth - root._fromW) * root._morphT
    readonly property real _morphH: root._fromH + (root.fullHeight - root._fromH) * root._morphT
    readonly property real _morphPos: root._fromPos + (root.perpTarget - root._fromPos) * root._morphT
    readonly property real _morphEdge: root._fromEdge + (root.edge - root._fromEdge) * root._morphT
    component MorphShift: NumberAnimation {
        duration: Theme.durPanelMorph
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curvePanelMorph
    }
    MorphShift {
        id: morphRun
        target: root
        property: "_morphT"
        from: 0
        to: 1
    }
    // Incoming card takeover: hidden while the outgoing content leads, then
    // swapped in at the outgoing pose — the cards match there, so the swap
    // is invisible — exactly when the glide starts. The cards never blend:
    // two translucent layer surfaces wash out the desktop and flicker.
    // The pause is re-stamped per handoff (see morphFrame): only the
    // remainder of the outgoing lead is waited, not the full token.
    SequentialAnimation {
        id: morphCardInAnim
        PauseAnimation { id: morphCardPause; duration: Theme.panelMorphLead }
        NumberAnimation {
            target: root
            property: "_morphCardIn"
            from: 0
            to: 1
            duration: 1
        }
    }
    // Glide phase gate: the container transform starts with the takeover.
    SequentialAnimation {
        id: morphGlidePhase
        PauseAnimation { id: morphGlidePause; duration: Theme.panelMorphLead }
        ScriptAction { script: morphRun.start() }
    }
    // Incoming content: arrives with the takeover, after the outgoing
    // content has cleared.
    SequentialAnimation {
        id: morphContentInAnim
        PauseAnimation { id: morphContentInPause; duration: Theme.panelMorphContentDelay }
        NumberAnimation {
            target: root
            property: "_morphContentIn"
            from: 0
            to: 1
            duration: Theme.panelMorphContentIn
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveDefaultEffects
        }
    }
    // Outgoing content: leads the run, leaving before the new content
    // arrives so the two never double-expose.
    NumberAnimation {
        id: morphContentOutAnim
        target: root
        property: "_morphContentOut"
        from: 1
        to: 0
        duration: Theme.panelMorphContentOut
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveFastEffects
    }
    // Interrupted-in dissolve (see `_inFade`): freezes the card at its current
    // morph pose and dissolves it in place. The geometry is only released once
    // this has landed (invisible), so the frame never snaps mid-fade.
    NumberAnimation {
        id: inFadeAnim
        target: root
        property: "_inFade"
        from: 1
        to: 0
        duration: Theme.durDefaultEffects
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveDefaultEffects
        onFinished: root._resetInterruptedIn()
    }
    // Overlay container transform: the replica leads the open run while the
    // page content follows over the tail of the card glide (delay + fade
    // half of durPanelMorph each, so the handoff happens at the header pose
    // once the card has essentially settled).
    SequentialAnimation {
        id: overlayContentInAnim
        PauseAnimation { id: overlayContentPause; duration: Theme.panelMorphReplicaDelay }
        NumberAnimation {
            target: root
            property: "_overlayContent"
            from: 0
            to: 1
            duration: Theme.panelMorphReplicaFade
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveDefaultEffects
        }
    }
    // Return: the content drops as the return starts, so the replica takes
    // over the whole collapse (and crossfades back into the CC tile, which
    // sourceReveal mirrors).
    NumberAnimation {
        id: overlayContentOutAnim
        target: root
        property: "_overlayContent"
        to: 0
        duration: Theme.panelMorphContentOut
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.curveFastEffects
    }
    function stopMorphRuns(): void {
        morphCardInAnim.stop()
        morphGlidePhase.stop()
        morphContentInAnim.stop()
        morphContentOutAnim.stop()
        overlayContentInAnim.stop()
        overlayContentOutAnim.stop()
        inFadeAnim.stop()
        root._morphCardIn = 1
        root._morphContentIn = 1
        root._morphContentOut = 1
        root._overlayContent = 1
        root._inFade = 1
        root._morphSource = null
    }
    // Abort a morph-out without flashing the content back in: the outgoing
    // content may already be gone (it leads from the moment the switch
    // begins), so the frame is faded out instead of retracted with its
    // content restored (what stopMorphRuns would do).
    function dropMorphOut(): void {
        morphCardInAnim.stop()
        morphGlidePhase.stop()
        morphContentInAnim.stop()
        overlayContentInAnim.stop()
        overlayContentOutAnim.stop()
        if (root._overlayOrigin)
            root._clearOverlaySource()
        if (root._morphIn) {
            // Interrupted incoming side (switched away or dismissed mid-
            // glide): freeze at the current pose and dissolve there. The
            // successor claimed this exact rect, so the two line up, and
            // releasing `_morphIn` now would snap the frame to its settled
            // size while the card is still fading.
            morphRun.stop()
            morphBackAnim.stop()
            morphSettleTimer.stop()
            morphHoldTimer.stop()
            morphFadeTimer.stop()
            morphFrame.running = false
            root._morphStarted = false
            root._morphOut = true
            root._morphFade = true
            if (!inFadeAnim.running) {
                root._inFade = 1
                inFadeAnim.restart()
            }
            return
        }
        root._overlayContent = 1
        root._morphIn = false
        root._morphOut = false
        root._morphFade = true
        root._open = false
    }
    // The interrupted-in dissolve has landed: release the frozen geometry now
    // that the card is fully transparent (the bindings snap with opacity 0,
    // so the snap is invisible).
    function _resetInterruptedIn(): void {
        if (!root._morphIn)
            return
        root._open = false
        root._morphIn = false
        root._morphOut = false
        root._morphFade = false
        root.stopMorphRuns()
    }

    function _publishRect(): void {
        if (root.morphId === "" || !root._open || !root.morphActive)
            return
        PanelMorph.publish(root.morphId, root.cardRect)
    }
    onMorphIdChanged: root._publishRect()
    onCardRectChanged: root._publishRect()

    // Incoming side: claim the origin pose (a button rect for an overlay
    // drill-in, the outgoing card otherwise), then glide to the settled one.
    function _tryMorphIn(): bool {
        // No `_morphIn` guard: a re-targeted switch can arrive while this
        // popout is still dissolving an earlier interrupted glide, and the
        // handoff must take over that frozen card (the dissolve is stopped
        // with the other drivers below) instead of falling back to a plain
        // open over the successor.
        if (!root.morphEnabled)
            return false
        if (root.morphId === "" || !PanelMorph.isTarget(root.morphId))
            return false
        // Overlay origin first: the control center stays mapped behind and
        // published the clicked tile/button. `rectOf(fromId)` would be the
        // whole CC card (or null: an overlay run has no from side).
        const o = PanelMorph.originOf(root.morphId)
        const r = o !== null ? o : PanelMorph.rectOf(PanelMorph.fromId)
        if (!r) {
            PanelMorph.finish()
            return false
        }
        // Interrupted return (re-opened mid-collapse): continue from the
        // card's current return pose instead of snapping back to the origin
        // rect. The origin is the same button either way.
        const wasBack = root._morphBack
        const curW = root._morphW
        const curH = root._morphH
        const curPos = root._morphPos
        const curEdge = root._morphEdge
        root._overlayOrigin = o !== null
        root._morphOut = false
        root._morphBack = false
        root._morphFade = false
        morphHoldTimer.stop()
        morphFadeTimer.stop()
        morphBackAnim.stop()
        morphSettleTimer.stop()
        morphRun.stop()
        morphCardInAnim.stop()
        morphGlidePhase.stop()
        morphContentInAnim.stop()
        morphContentOutAnim.stop()
        overlayContentInAnim.stop()
        overlayContentOutAnim.stop()
        inFadeAnim.stop()
        root._inFade = 1
        root._morphT = 0
        if (wasBack) {
            root._fromW = curW
            root._fromH = curH
            root._fromPos = curPos
            root._fromEdge = curEdge
        } else {
            root._fromW = r.width
            root._fromH = r.height
            root._fromPos = r.x
            root._fromEdge = r.y
        }
        root._morphDir = PanelMorph.direction
        // Source replica (container transform) rides the origin object; only
        // an overlay run can carry one. The content starts fully hidden
        // behind it and follows over the tail (overlayContentInAnim).
        root._morphSource = root._overlayOrigin && o !== null && o.source !== undefined ? o.source : null
        root._overlayContent = root._overlayOrigin ? 0 : 1
        // Overlay runs morph on the even container curve (see Theme); a
        // sibling-card handoff keeps the curtain's panel-open attack.
        morphRun.easing.bezierCurve = root._overlayOrigin ? Theme.curvePanelMorphOverlay : Theme.curvePanelMorph
        root._morphCardIn = 0
        root._morphContentIn = 0
        root._morphContentOut = 1
        root._morphIn = true
        root._morphStarted = false
        root._open = true
        root._publishRect()
        morphFrame.running = true
        return true
    }
    FrameAnimation {
        id: morphFrame
        running: false
        onTriggered: {
            running = false
            if (!root._morphIn || root._morphStarted)
                return
            // First rendered frame. The outgoing content already started
            // leaving when the switch began (PanelMorph.leftAt), so only
            // what is left of the lead is waited out here: a late surface
            // map glides immediately instead of adding a full fixed pause.
            // markReady releases the outgoing card on the same beat. An
            // overlay drill-in has no outgoing side: the card is already
            // rendering its source replica at the origin pose on this frame,
            // so the glide (and the replica's morph) starts immediately.
            const lead = root._overlayOrigin ? 0 : PanelMorph.leadRemaining(Theme.panelMorphLead)
            root._morphStarted = true
            morphCardPause.duration = lead
            morphGlidePause.duration = lead
            morphCardInAnim.restart()
            morphGlidePhase.restart()
            if (root._overlayOrigin) {
                // Container transform: the source replica leads, the page
                // content follows over the tail of the card glide.
                overlayContentPause.duration = Theme.panelMorphReplicaDelay
                overlayContentInAnim.restart()
            } else {
                morphContentInPause.duration = Theme.panelMorphContentDelay
                morphContentInAnim.restart()
            }
            morphSettleTimer.interval = lead + Theme.durPanelMorph + 20
            morphSettleTimer.restart()
            if (root._overlayOrigin) {
                // Handoff done, but the overlay source stays registered so
                // the CC keeps the origin button hidden until the return run
                // has dissolved into it. The card is on screen at the origin
                // pose in this very frame, so hiding the button is seamless.
                PanelMorph.clear()
                PanelMorph.sourceReveal = 0
            } else {
                PanelMorph.markReady(root.morphId)
            }
        }
    }
    Timer {
        id: morphSettleTimer
        interval: Theme.panelMorphLead + Theme.durPanelMorph + 20
        repeat: false
        onTriggered: root._morphIn = false
    }

    // Overlay drill-in return: an overlay card closes while its origin
    // button is still on screen (the control center stayed open behind it),
    // so it glides back into the button pose instead of playing the curtain.
    // finishMorphBack then snaps the (already faded) frame shut.
    function _tryMorphBack(): bool {
        if (!root.morphEnabled || !root._overlayOrigin || root._morphBack || !root._open)
            return false
        // Stop every open-run driver: a return that interrupts the open
        // glide (quick tap) would otherwise fight the back animation for
        // `_morphT` (morphGlidePhase can restart morphRun).
        morphRun.stop()
        morphCardInAnim.stop()
        morphGlidePhase.stop()
        morphContentInAnim.stop()
        morphContentOutAnim.stop()
        overlayContentInAnim.stop()
        overlayContentOutAnim.stop()
        inFadeAnim.stop()
        root._inFade = 1
        root._morphIn = false
        root._morphOut = false
        root._morphFade = false
        root._morphCardIn = 1
        root._morphContentIn = 1
        root._morphContentOut = 1
        root._morphDir = -1
        root._morphBack = true
        // Continue from wherever the card is (an interrupted open starts its
        // return mid-pose instead of snapping to fully open first).
        morphBackAnim.from = Math.min(1, Math.max(0, root._morphT))
        // The page content drops right away and the source replica takes
        // over the collapse from the header pose; the origin button then
        // reappears exactly as the card dissolves into it (sourceReveal
        // mirrors the card's own return fade, 1 -> 0), so the two
        // cross-dissolve at the button pose. The binding self-resets to 1
        // when `_morphBack` clears in _finishMorphBack.
        overlayContentOutAnim.restart()
        PanelMorph.sourceReveal = Qt.binding(() => 1 - root._backFade)
        morphBackAnim.restart()
        return true
    }
    // Return run: the open's duration on the standard curve, so the card
    // retracts at an even, legible rate — not front-loaded (over in the
    // first frames) and not accelerating (creep, then dart).
    MorphShift {
        id: morphBackAnim
        target: root
        property: "_morphT"
        from: 1
        to: 0
        duration: Theme.durPanelMorph
        easing.bezierCurve: Theme.curveStandard
        onFinished: root._finishMorphBack()
    }
    function _finishMorphBack(): void {
        root.stopMorphRuns()
        // Instant: the drivers' Behaviors are disabled while `_morphBack`
        // is set, so the frame snaps shut at the origin pose instead of
        // playing a second curtain run from there.
        root._open = false
        root._overlayOrigin = false
        root._morphBack = false
        root._morphIn = false
        root._morphT = 1
        // The button is visible again (binding above already evaluated to 1
        // with the cleared flag); release the source registration.
        PanelMorph.sourceReveal = 1
        if (PanelMorph.originId === root.morphId)
            PanelMorph.originId = ""
    }

    // Outgoing side: hold the open card until the incoming surface is on
    // screen, then fade it out (the incoming card covers the same pixels).
    // The content leads from the moment the switch begins — instant feedback
    // instead of a pause that lasts until the incoming surface has mapped —
    // while the card itself keeps holding, so a slow map can never expose
    // the desktop.
    function _tryMorphOut(): bool {
        if (!root.morphEnabled || !root._open)
            return false
        if (root.morphId === "" || !PanelMorph.isSource(root.morphId))
            return false
        // Switching away from an overlay drill-in (no return run): release
        // the source registration so its button is visible again.
        if (root._overlayOrigin)
            root._clearOverlaySource()
        root._morphDir = PanelMorph.direction
        if (root._morphIn) {
            // The panel is still gliding in (quick re-switch). Freeze the
            // card at its current pose — the successor starts from this same
            // rect — and hold it visible until the incoming surface is up,
            // then dissolve in place (morphFadeTimer -> dropMorphOut). Its
            // content stays at the frozen incoming pose; the whole card
            // fades as one.
            morphRun.stop()
            morphGlidePhase.stop()
            morphCardInAnim.stop()
            morphContentInAnim.stop()
            overlayContentInAnim.stop()
            morphSettleTimer.stop()
            // Also cancel a pending first-frame gate: with `_morphStarted`
            // cleared it would otherwise restart the whole open run on the
            // next frame and fight the dissolve.
            morphFrame.running = false
            root._morphStarted = false
            root._morphOut = true
            root._morphFade = false
            root._inFade = 1
        } else {
            root._morphOut = true
            root._morphFade = false
            root._morphContentOut = 1
            morphContentOutAnim.restart()
        }
        // Start the shared clock: the incoming side waits only the remainder
        // of the lead once its first frame lands (PanelMorph.leadRemaining).
        PanelMorph.noteDeparture()
        morphHoldTimer.restart()
        return true
    }
    Timer {
        id: morphHoldTimer
        interval: Theme.durPanelMorphHold
        repeat: false
        onTriggered: {
            // Incoming surface never rendered: fall back to a normal close.
            if (!root._morphOut || root._morphFade)
                return
            PanelMorph.finish()
            root.dropMorphOut()
        }
    }
    Connections {
        target: PanelMorph
        function onReadyChanged() {
            if (!PanelMorph.ready || !root._morphOut || root._morphFade)
                return
            morphHoldTimer.stop()
            // Incoming surface is up. Its card takes over once the outgoing
            // content has fully left (shared clock); release the outgoing
            // card on that same beat, so its fade only ever dissolves the
            // rim the incoming one does not cover.
            morphFadeTimer.interval = PanelMorph.leadRemaining(Theme.panelMorphLead)
            morphFadeTimer.restart()
        }
        function onActiveChanged() {
            // Handoff aborted (incoming side could not claim a rect).
            if (PanelMorph.active || !root._morphOut || root._morphFade)
                return
            morphHoldTimer.stop()
            morphFadeTimer.stop()
            root.dropMorphOut()
        }
    }
    // Outgoing card release: runs as the incoming card takes over (opaque by
    // then), so the outgoing fade only ever dissolves its uncovered rim.
    Timer {
        id: morphFadeTimer
        interval: Theme.panelMorphLead
        repeat: false
        onTriggered: {
            if (!root._morphOut || root._morphFade)
                return
            if (root._morphIn) {
                // Interrupted incoming side: dissolve the frozen card in
                // place (dropMorphOut sets `_morphFade` first, so finish()'s
                // Connections handler leaves the running dissolve alone).
                root.dropMorphOut()
                PanelMorph.finish()
                return
            }
            root._morphFade = true
            PanelMorph.finish()
        }
    }

    // ---- geometry ------------------------------------------------------
    // Stretched frame size along the bar axis: 0 at the bar edge -> full.
    readonly property real frameAxis: axisSize * (1 - _offsetScale)
    // Snap the frame extent to whole pixels: the shadow layer above
    // resamples its source on fractional geometry (shadow shimmer), and
    // the sub-pixel step is invisible at animation speeds. Content renders
    // directly (not through the layer), so text stays native either way.
    readonly property real frameExtent: Math.ceil(frameAxis)
    readonly property real perpExtent: Math.ceil(perpSize)
    // Content offset along the axis: full-size content parked outside the
    // frame's far edge (own driver -> independent motion).
    readonly property real contentTranslate: -axisSize * _contentOffset
    readonly property real contentX: 0
    readonly property real contentY: contentTranslate
    // While the frame is shorter than the radius, clamp so it reads as a
    // pill being stretched out of the bar instead of a squashed panel.
    readonly property real frameRadius: Math.min(Theme.cornerRadius, frameAxis / 2)

    width: perpExtent + perpPad * 2
    height: frameExtent + shadowPad
    visible: frameAxis > 0.5
    clip: true

    // Perp anchor follow, gated like the reference: a closed popout snaps
    // into place so the next open starts from the right spot.
    readonly property real perpTarget: {
        const lo = margin;
        const hi = screenSize - settledPerp - margin;
        if (hi < lo)
            return lo;
        return Math.max(lo, Math.min(anchorCenter - settledPerp / 2, hi));
    }
    // While a morph run drives the pose, the card rides the morphed position
    // directly (the perp Behavior is off, so the two runs cannot chase each
    // other).
    property real perpPos: root._morphing ? root._morphPos : perpTarget
    Behavior on perpPos {
        // Also off while the size Behaviors below run: perpTarget already
        // moves smoothly with the animated size, and a second Behavior
        // chasing that moving target lags behind — the card would grow
        // off-centre and slide back after the size settles. Direct follow
        // keeps the anchor (or screen centre) fixed for the whole resize.
        enabled: Theme.animationsEnabled && root._offsetScale < 1 && !root._morphing && !root._resizing
        NumberAnimation {
            duration: Theme.durDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveDefaultSpatial
        }
    }
    // The fixed edge stays put; the far edge is where the curtain grows.
    // Integer positions keep the shadow source texture 1:1 (no shimmer).
    x: Math.round(perpPos - perpPad)
    y: Math.round(effEdge)

    // Wrapper implicitWidth/implicitHeight Behaviors. Panel-open curve: the
    // first size settle after a cold open is part of the opening run and
    // must not spring.
    Behavior on fullWidth {
        enabled: Theme.animationsEnabled && root._offsetScale < 1
        NumberAnimation {
            id: fullWidthAnim
            duration: Theme.durDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curvePanelOpen
        }
    }
    Behavior on fullHeight {
        enabled: Theme.animationsEnabled && root._offsetScale < 1
        NumberAnimation {
            id: fullHeightAnim
            duration: Theme.durDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curvePanelOpen
        }
    }
    // True while a size Behavior is gliding: the perp position must then
    // follow perpTarget directly (see the perpPos Behavior above). Hosts
    // resize while open whenever the content changes pose (launcher prefix
    // pages, notification list growth, tray list growth).
    readonly property bool _resizing: fullWidthAnim.running || fullHeightAnim.running

    // Drop shadow, cast from a plain card silhouette instead of the card
    // contents. The layer wraps only the flat card shape, never the panel
    // text, and the popout paints the card fill here; host cards stay
    // transparent so the silhouette is only composited once. sourceRect
    // reaches into the padding on every free side so the blur can spill
    // there; the fused bar edge stays clipped so the panel keeps reading
    // as one mass with the bar (the popout viewport has no room there
    // either). Without the free-edge room the layer texture ends at the
    // card edge and the shadow is cut mid-blur into a hard-edged smudge.
    //
    // The layer's geometry is the SETTLED card and the current frame is
    // painted by scaling that texture (Scale below) instead of resizing the
    // item. Resizing forced a full card raster + MultiEffect blur on every
    // animated frame; with two panels overlapping during a handoff that was
    // the main stutter of the morph. A transformed layer keeps the texture
    // and only moves it, so the per-frame cost drops to one texture scale
    // (open/close curtain included).
    //
    // The concave fillets that merge the popout into the bar are part of
    // this silhouette too — Caelestia unions the bar and popout into one
    // SDF blob group (BlobGroup/BlobRect in ContentWindow.qml), so its
    // shadow wraps the merged mass. Drawing the shoulders as separate
    // patches on top (the old PanelFillet) left a hairline where the
    // card's shadow and the shoulder edge failed to overlap. Here the
    // shadow is cast from the union, so the cove reads as one mass.
    Item {
        id: shadowSource

        // Settled card size: the static layer geometry (holder's size at
        // rest, so the scale is exactly 1 when settled and the fill/border
        // seam stays hairline-free).
        readonly property real baseW: Math.max(1, Math.ceil(root.settledPerp))
        readonly property real baseH: Math.max(1, Math.ceil(root.settledAxis))
        // Settled corner radius (frameRadius only clamps while the curtain
        // is shorter than the radius; at rest the two are equal).
        readonly property real baseRadius: Math.min(Theme.cornerRadius, Math.min(baseW, baseH) / 2)

        x: holder.x
        y: holder.y
        width: baseW
        height: baseH
        visible: root.visible
        // The morphing card fades its frame; the shadow must follow.
        opacity: holder.opacity
        layer.enabled: true
        // Blur spill room on every side the viewport has room (perpPad on
        // the flanks, shadowPad past the free edge); the fused bar edge is
        // left out, matching the viewport clip.
        layer.sourceRect: Qt.rect(-root.perpPad, 0, width + root.perpPad * 2, height + root.shadowPad)
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.withAlpha(Theme.shadow, 0.5)
            shadowOpacity: 0.45
            shadowBlur: 0.9
            // Cast away from the fused bar edge.
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 8
        }
        // Frame pinned at the fused bar edge (axis) and anchored at the
        // card's near corner (perp: holder coordinates start at the card
        // edge).
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: holder.width / shadowSource.width
            yScale: holder.height / shadowSource.height
        }
        Rectangle {
            anchors.fill: parent
            topLeftRadius: root.fusedTop ? 0 : shadowSource.baseRadius
            topRightRadius: root.fusedTop ? 0 : shadowSource.baseRadius
            bottomLeftRadius: shadowSource.baseRadius
            bottomRightRadius: shadowSource.baseRadius
            color: Theme.panelWindowBg
            antialiasing: Theme.shapesAa
        }

        // Concave shoulder at one end of the fused edge: top edge fused with
        // the bar, side edge fused with the card, one tangent cubic cove
        // between them. Canonical geometry is drawn for left/top; mirrors
        // handle the other corners (Scale carries its own origin).
        component Fillet: Shape {
            id: fillet

            // "left" | "right": which end of the fused edge.
            required property string side
            // Fused edge at the card's top (bar above) or bottom (bar below).
            required property bool atTop

            // 1:1 with Appearance > Rounding, like the card corners; 0
            // (square shell) leaves the joint a plain right angle.
            property real extent: Theme.cornerRadius
            property real length: Theme.cornerRadius
            property color fillColor: Theme.panelWindowBg

            readonly property bool mirrorX: side === "right"
            readonly property bool mirrorY: !atTop
            // Cubic control offset for a near-circular tangent cove.
            readonly property real ck: 0.5523

            x: side === "left" ? -extent : parent.width
            y: atTop ? 0 : parent.height - length
            width: extent
            height: length
            preferredRendererType: Shape.CurveRenderer
            // The layer's sourceRect clips the part past the card's free
            // edge, so a short frame never leaves the shoulder floating.
            transform: Scale {
                xScale: fillet.mirrorX ? -1 : 1
                yScale: fillet.mirrorY ? -1 : 1
                origin.x: fillet.width / 2
                origin.y: fillet.height / 2
            }

            ShapePath {
                fillColor: fillet.fillColor
                strokeWidth: 0
                strokeColor: "transparent"

                startX: 0
                startY: 0
                PathLine { x: fillet.extent; y: 0 }
                PathLine { x: fillet.extent; y: fillet.length }
                PathCubic {
                    x: 0
                    y: 0
                    control1X: fillet.extent
                    control1Y: fillet.length - fillet.ck * fillet.length
                    control2X: fillet.ck * fillet.extent
                    control2Y: 0
                }
            }
        }

        Fillet { side: "left"; atTop: true; visible: root.fusedTop && Theme.cornerRadius > 0 }
        Fillet { side: "right"; atTop: true; visible: root.fusedTop && Theme.cornerRadius > 0 }
    }

    // Holder = the stretched frame. Its near edge sits exactly on the bar
    // edge (the viewport is pinned there), so the card always touches the
    // bar. The extra shadowPad keeps the card's free edge away from the far
    // viewport edge, leaving room for the drop shadow.
    Item {
        id: holder

        x: root.perpPad
        y: 0
        width: root.perpExtent
        height: root.frameExtent

        // Comp transition: 0/1 with default effects both ways. A morphing
        // source fades its frame here once the incoming surface is up.
        // During a morph-in the card is hidden through `_morphCardIn`
        // until the lead phase ends (driven in morphFrame), so the outgoing
        // content is never cut off by an abrupt cover. A morph-back fades
        // the card as it lands on the origin button (`_backFade`). An
        // interrupted morph-in dissolves the frozen card through `_inFade`
        // (the Behavior stays off for morph-in, so the value drives it).
        opacity: {
            if (!root._open)
                return 0
            if (root._morphIn)
                return root._morphCardIn * root._inFade
            if (root._morphFade)
                return 0
            if (root._morphBack)
                return root._backFade
            return 1
        }
        Behavior on opacity {
            enabled: Theme.animationsEnabled && !root._morphIn && !root._morphBack
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    // Content handoff (style/ui/PanelMorph choreography): the outgoing content
    // leads — it fades/shifts out while the incoming card is still hidden —
    // then the incoming content arrives once the card is swapped in.
    // Hosts bind their content item's opacity to this
    // (PanelShell multiplies it into innerFade) and their content transform
    // to contentScale/contentOffset*.
    // The leaving side: a morph-out handoff or an overlay return. Handoffs
    // fade the content out ahead of the frame; an overlay return drops it
    // right away so the source replica can carry the collapse back into the
    // button (the card dissolves after it, see _backFade).
    readonly property bool _contentLeaving: (root._morphOut && !root._morphIn) || root._morphBack
    // Incoming content progress: overlay runs crossfade from the source
    // replica (`_overlayContent`), regular handoffs from `_morphContentIn`.
    readonly property real _contentIn: root._overlayOrigin ? root._overlayContent : root._morphContentIn
    // An interrupted incoming side (`_morphIn && _morphOut`) keeps its frozen
    // incoming content pose while the whole card dissolves: the flag-based
    // content-out run would pop the crossfade to full for a card that never
    // reached it.
    property real contentFade: (root._morphOut && !root._morphIn) ? root._morphContentOut
                             : root._morphBack ? (root._overlayOrigin ? root._overlayContent : 1)
                             : root._morphIn ? root._contentIn
                             : 1
    readonly property real morphOutT: root._morphBack
        ? 1 - root._overlayContent
        : (root._morphOut && !root._morphIn) ? 1 - root._morphContentOut
        : 0
    // Replica visibility for the host (PanelShell renders the source
    // component while this is > 0): inverse of the content crossfade, hidden
    // once the run is over or the panel is switching away. An interrupted
    // incoming side keeps its replica: the card dissolves as one mass.
    readonly property real morphReplicaOpacity: (root._morphSource === null
        || (!root._morphIn && (root._morphOut || root._morphFade)))
        ? 0
        : Math.max(0, 1 - root._overlayContent)
    // Shared-axis travel: drill-in switches push the content along the bar
    // axis (forward: old content exits up, new arrives from below; back:
    // mirrored). Lateral switches (bar panel <-> bar panel) crossfade with
    // the scale only, no travel.
    readonly property real morphTravel: root._contentLeaving
        ? -root._morphDir * Theme.panelMorphShift * root.morphOutT
        : root._morphIn ? root._morphDir * Theme.panelMorphShift * (1 - root._contentIn) : 0
    readonly property real contentOffsetX: 0
    readonly property real contentOffsetY: root._morphDir !== 0 ? root.morphTravel : 0
    readonly property real contentScale: root._contentLeaving ? 1 - Theme.panelMorphScale * root.morphOutT
                                        : root._morphIn ? 1 - Theme.panelMorphScale * (1 - root._contentIn)
                                        : 1

    // Popout transition: slow effects on the way in, default effects out.
    property real _innerFade: _open ? 1 : 0
    Behavior on _innerFade {
        // A morph-in drives its content purely through `contentFade` (the
        // card swap is separate), so the inner fade snaps for it; a
        // morph-back snaps it shut with the frame (see _finishMorphBack).
        enabled: Theme.animationsEnabled && !root._morphIn && !root._morphBack
        NumberAnimation {
            duration: root._open ? Theme.durSlowEffects : Theme.durDefaultEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root._open ? Theme.curveSlowEffects : Theme.curveDefaultEffects
        }
    }
}
