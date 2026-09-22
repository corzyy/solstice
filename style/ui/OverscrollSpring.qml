pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

// OverscrollSpring — rubber-band feedback when a scrollable hits its end.
//
// Drop next to any Flickable/ListView/GridView (same contract as EdgeFade
// and ScrollIndicator, which anchor themselves to the flickable):
//   ListView { id: appList; ... }
//   OverscrollSpring { flick: appList }
//
// What it does:
//   1. Enables the native drag overshoot (DragAndOvershootBounds) for
//      non-snapped views, so touch/drag past the edge already springs back.
//      Snapped carousels (SnapToItem / StrictlyEnforceRange) keep
//      StopAtBounds so the snap never fights the bounce.
//   2. Observes wheel ticks (observer WheelHandler parented to the
//      flickable itself — the same delivery path as a hand-written child
//      handler): the tick that lands on the end/top kicks with a landing
//      thud, and further pushes at the edge keep throbbing via
//      kickY()/kickX(). Hosts with a custom clamped wheel handler
//      (SettingsPanel.wheelScroll, horizontal chip strips) route the delta
//      through scrollY()/scrollX() instead and set interceptWheel: false.
//      The content stretches past the edge with resistance and springs back
//      with a SpringAnimation. The observer never accepts the event, so
//      normal (and nested) scrolling is untouched.
//
// The visual offset rides on flick.contentItem.transform, so it composes
// with contentY/contentX instead of fighting the Flickable's own position.
// With animations off the offset stays 0 (no bounce, same as before).
Item {
    id: root

    required property Flickable flick
    // Maximum visual stretch past the edge, in px.
    property real maxOvershoot: 64
    // Resistance applied to the incoming wheel delta (0..1). Lower feels
    // stiffer, higher feels looser.
    property real resistance: 0.35
    property bool verticalEnabled: true
    property bool horizontalEnabled: true
    property bool bounceEnabled: true
    // Wheel observation: when the list already sits exactly at the end/top
    // and another wheel tick pushes further out, the observer below
    // stretches the content itself (the Flickable's built-in wheel handling
    // just clamps silently there, so without this nothing would be felt).
    // It never accepts the event, so the Flickable (or an outer scroller)
    // always scrolls normally. Interior ticks are ignored so the Flickable
    // keeps its own scroll feel; an arrival watcher adds the landing thud
    // (see _wheelFresh). Lists with their own clamped wheel handler that
    // already routes through scrollY()/scrollX() (SettingsPanel, chip
    // strips) set this to false to avoid a second kick on the same tick.
    property bool interceptWheel: true
    // px per mouse notch used for kick magnitude (kept in sync with
    // SettingsPanel.wheelNotchPixels).
    property real wheelStep: 180
    // True once the wheel observer was attached to the flickable (false
    // when interceptWheel is off or the attach failed — then only native
    // overshoot and explicit kick/scroll calls apply).
    property bool wheelObserverActive: false

    readonly property bool _anim: root.bounceEnabled && Theme.animationsEnabled

    // Extra visual offset, driven by kick*() and eased back to 0.
    property real shiftY: 0
    property real shiftX: 0

    // Applied to the flickable's content so the rows themselves stretch
    // past the edge (clipped by the viewport, like the native overshoot).
    // contentItem almost never carries its own transform, but preserve any
    // pre-existing entries instead of overwriting them.
    property Translate _bounce: Translate {
        x: root.shiftX
        y: root.shiftY
    }

    // Spring back to the settled pose. SpringAnimation (not a fixed
    // duration) gives the rubber-band settle: fast return with a small
    // overshoot past 0. Stopped while the user keeps pushing (kick
    // restarts the settle timer instead).
    property SpringAnimation _springY: SpringAnimation {
        target: root
        property: "shiftY"
        to: 0
        spring: 4.2
        damping: 0.32
        mass: 1.0
        epsilon: 0.4
        // Keep the motion under the global toggle: with animations off the
        // kick path never accumulates, so this only guards the tail.
        onRunningChanged: if (!root._anim && running) stop()
    }
    property SpringAnimation _springX: SpringAnimation {
        target: root
        property: "shiftX"
        to: 0
        spring: 4.2
        damping: 0.32
        mass: 1.0
        epsilon: 0.4
        onRunningChanged: if (!root._anim && running) stop()
    }

    // Settle delay: the last wheel tick starts the spring back. While the
    // wheel keeps turning the offset accumulates with resistance instead
    // of fighting the return run.
    property Timer _settle: Timer {
        interval: 90
        repeat: false
        onTriggered: {
            if (!root._anim) {
                root._springY.stop()
                root._springX.stop()
                root.shiftY = 0
                root.shiftX = 0
                return
            }
            if (root.shiftY !== 0) root._springY.start()
            if (root.shiftX !== 0) root._springX.start()
        }
    }

    // Anchors itself to the flickable like EdgeFade/ScrollIndicator, so it
    // can sit anywhere outside layouts. Overlay only: never steals
    // clicks/wheel (same contract as EdgeFade).
    anchors.top: flick.top
    anchors.bottom: flick.bottom
    anchors.left: flick.left
    anchors.right: flick.right
    enabled: false
    visible: false

    // Freshness window linking a wheel tick to the contentY/X arrival it
    // caused (the built-in handler consumes interior ticks silently).
    property real _lastWheelDy: 0
    property real _lastWheelDx: 0
    property Timer _wheelFresh: Timer {
        interval: 150
        repeat: false
    }

    // Wheel observer, attached straight to the flickable on completion (a
    // hand-written WheelHandler child of a Flickable is the shell's proven
    // delivery path — e.g. SettingsPanel; a sibling overlay is NOT reliably
    // in the wheel delivery path, which is why at-edge ticks went unfelt).
    // It only observes: kicks are visual-only and the event is deliberately
    // never accepted, so the Flickable (or an outer scroller — nested lists
    // like the wallpaper grid inside the settings page keep working: the
    // inner list stretches while the outer page still scrolls) always
    // receives the tick.
    property Component _wheelFactory: Component {
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => root._observeWheel(event)
        }
    }
    function _observeWheel(event: var): void {
        let dy = 0
        let dx = 0
        try {
            const ay = event.angleDelta ? event.angleDelta.y : 0
            const ax = event.angleDelta ? event.angleDelta.x : 0
            const py = event.pixelDelta ? event.pixelDelta.y : 0
            const px = event.pixelDelta ? event.pixelDelta.x : 0
            if (ay !== 0) dy = ay / 120 * root.wheelStep
            else if (py !== 0) dy = py
            if (ax !== 0) dx = ax / 120 * root.wheelStep
            else if (px !== 0) dx = px
            // Vertical notches drive a horizontal-only strip.
            if (dx === 0 && dy !== 0 && root.horizontalEnabled && !root.verticalEnabled) {
                dx = dy
                dy = 0
            }
        } catch (e) { return }
        if (dy === 0 && dx === 0) return
        root._lastWheelDy = dy
        root._lastWheelDx = dx
        root._wheelFresh.restart()
        if (!root._anim) return
        // Only when settled exactly at the end/top with no native
        // overshoot showing: interior and arrival ticks belong to the
        // Flickable's own wheel handling (the watcher below adds the
        // landing thud for those).
        if (root.verticalEnabled && dy !== 0) {
            const cy = root.flick.contentY
            if (cy >= -0.5 && cy <= 0.5 && dy > 0) {
                root.kickY(dy)
            } else if (cy >= root._maxY - 0.5 && cy <= root._maxY + 0.5 && dy < 0) {
                root.kickY(dy)
            }
        }
        if (root.horizontalEnabled && dx !== 0) {
            const cx = root.flick.contentX
            if (cx >= -0.5 && cx <= 0.5 && dx > 0) {
                root.kickX(dx)
            } else if (cx >= root._maxX - 0.5 && cx <= root._maxX + 0.5 && dx < 0) {
                root.kickX(dx)
            }
        }
    }

    function _clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v))
    }

    readonly property real _maxY: Math.max(0, flick.contentHeight - flick.height)
    readonly property real _maxX: Math.max(0, flick.contentWidth - flick.width)
    function atTop(): bool { return flick.contentY <= 0.5 }
    function atBottom(): bool { return flick.contentY >= root._maxY - 0.5 }
    function atLeft(): bool { return flick.contentX <= 0.5 }
    function atRight(): bool { return flick.contentX >= root._maxX - 0.5 }

    // Push the content past the edge. Positive dy moves rows down (top
    // edge), negative moves them up (bottom edge); same on x for left/right.
    // Call only when the scroll attempt cannot move contentY/X further —
    // normal scrolling must go through the Flickable untouched.
    //
    // Repeated pushes must stay visible again and again: a hard clamp would
    // saturate after 2-3 notches and further ticks would do nothing. So the
    // gain softens with distance (rubber-band) and pushing past the hard cap
    // re-throbs (dip toward 0, then stretch back out) instead of sticking.
    readonly property real _hardCapScale: 1.5
    function _gain(cur: real): real {
        const dist = Math.abs(cur) / Math.max(1, root.maxOvershoot)
        return root.resistance * Math.max(0.25, 1.0 - dist * 0.55)
    }
    // Inward step for a saturated push, so every extra notch throbs
    // instead of sticking at the cap.
    readonly property real _throbStep: 22
    function kickY(dy: real): void {
        if (!root.verticalEnabled || !root._anim || dy === 0) return
        root._springY.stop()
        const cap = root.maxOvershoot * root._hardCapScale
        const cur = root.shiftY
        const pushingOut = (dy > 0 && cur >= 0) || (dy < 0 && cur <= 0)
        if (pushingOut && Math.abs(cur) >= cap - 0.5) {
            // Saturated: dip back toward 0 — the next tick stretches out
            // again, so holding the wheel throbs again and again.
            root.shiftY = _clamp(cur - Math.sign(dy) * root._throbStep, -cap, cap)
        } else {
            root.shiftY = _clamp(cur + dy * _gain(cur), -cap, cap)
        }
        root._settle.restart()
    }
    function kickX(dx: real): void {
        if (!root.horizontalEnabled || !root._anim || dx === 0) return
        root._springX.stop()
        const cap = root.maxOvershoot * root._hardCapScale
        const cur = root.shiftX
        const pushingOut = (dx > 0 && cur >= 0) || (dx < 0 && cur <= 0)
        if (pushingOut && Math.abs(cur) >= cap - 0.5) {
            // Saturated: dip back toward 0 — the next tick stretches out
            // again, so holding the wheel throbs again and again.
            root.shiftX = _clamp(cur - Math.sign(dx) * root._throbStep, -cap, cap)
        } else {
            root.shiftX = _clamp(cur + dx * _gain(cur), -cap, cap)
        }
        root._settle.restart()
    }

    // Convenience for custom wheel handlers with a signed scroll delta
    // where `dy` follows the SettingsPanel.wheelScroll convention:
    // contentY -= dy (dy > 0 scrolls toward the top). Returns true when the
    // delta was absorbed as an edge bounce (caller must accept the event
    // and skip the clamped contentY assignment).
    function absorbWheel(dy: real, dx: real): bool {
        let used = false
        if (root.verticalEnabled && dy !== 0) {
            if ((dy > 0 && atTop()) || (dy < 0 && atBottom())) {
                kickY(dy)
                used = true
            }
        }
        if (root.horizontalEnabled && dx !== 0) {
            if ((dx > 0 && atLeft()) || (dx < 0 && atRight())) {
                kickX(dx)
                used = true
            }
        }
        return used
    }

    // Same, driven directly by a WheelHandler event (angleDelta for mice,
    // pixelDelta for touchpads). `notchPixels` converts one 120-step notch
    // into px — keep in sync with the host's wheel step (SettingsPanel uses
    // wheelNotchPixels = 180).
    function absorbWheelEvent(event: var, notchPixels: real): bool {
        let dy = 0
        let dx = 0
        try {
            const angleY = event.angleDelta ? event.angleDelta.y : 0
            const angleX = event.angleDelta ? event.angleDelta.x : 0
            const pixY = event.pixelDelta ? event.pixelDelta.y : 0
            const pixX = event.pixelDelta ? event.pixelDelta.x : 0
            const step = (notchPixels || 0) > 0 ? notchPixels : 180
            if (angleY !== 0) dy = angleY / 120 * step
            else if (pixY !== 0) dy = pixY
            if (angleX !== 0) dx = angleX / 120 * step
            else if (pixX !== 0) dx = pixX
            // Vertical mice report the notch on y for a horizontal strip:
            // fall back to y when x is empty and horizontal bounce is on.
            if (dx === 0 && dy !== 0 && root.horizontalEnabled && !root.verticalEnabled) {
                dx = dy
                dy = 0
            }
        } catch (e) {
            return false
        }
        return absorbWheel(dy, dx)
    }

    // Full scroll path with edge feedback: moves contentY/contentX like a
    // plain clamped assignment, but the tick that LANDS on the end/top also
    // kicks the spring with the leftover amount — so arriving at the edge
    // thuds instead of stopping dead — and further pushes keep throbbing
    // via kickY()/kickX(). `dy`/`dx` follow the contentY -= dy convention
    // (dy > 0 scrolls toward the top/left). With animations off this is just
    // a clamped assignment (no bounce, same as before).
    function scrollY(dy: real): void {
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (!root._anim) {
            flick.contentY = _clamp(flick.contentY - dy, 0, maxY)
            return
        }
        const target = flick.contentY - dy
        if (target < 0) {
            flick.contentY = 0
            kickY(-target)
        } else if (target > maxY) {
            flick.contentY = maxY
            kickY(-(target - maxY))
        } else {
            flick.contentY = target
        }
    }
    function scrollX(dx: real): void {
        const maxX = Math.max(0, flick.contentWidth - flick.width)
        if (!root._anim) {
            flick.contentX = _clamp(flick.contentX - dx, 0, maxX)
            return
        }
        const target = flick.contentX - dx
        if (target < 0) {
            flick.contentX = 0
            kickX(-target)
        } else if (target > maxX) {
            flick.contentX = maxX
            kickX(-(target - maxX))
        } else {
            flick.contentX = target
        }
    }

    function cancel(): void {
        root._settle.stop()
        root._springY.stop()
        root._springX.stop()
        root.shiftY = 0
        root.shiftX = 0
    }

    onBounceEnabledChanged: if (!root.bounceEnabled) cancel()
    // Arrival watcher: interior wheel ticks are consumed by the Flickable's
    // own handling, which clamps silently when it lands exactly on the
    // end/top. If contentY/X arrives at a bound within the freshness window
    // of a wheel tick, add the landing thud here. Skipped when a native
    // overshoot is already showing (that feedback needs no doubling), when
    // no wheel happened recently (programmatic jumps like
    // positionViewAtBeginning, keyboard-driven highlight scrolls), and when
    // animations are off. At-edge ticks change nothing (already clamped),
    // so this never double-fires with the interceptor above.
    Connections {
        target: root.flick
        function onContentYChanged() {
            if (!root.interceptWheel || !root._anim || !root.verticalEnabled) return
            if (!root._wheelFresh.running) return
            const cy = root.flick.contentY
            if (cy < -0.5 || cy > root._maxY + 0.5) return
            if (root._lastWheelDy > 0 && root.atTop()) root.kickY(Math.min(140, root._lastWheelDy))
            else if (root._lastWheelDy < 0 && root.atBottom()) root.kickY(Math.max(-140, root._lastWheelDy))
        }
        function onContentXChanged() {
            if (!root.interceptWheel || !root._anim || !root.horizontalEnabled) return
            if (!root._wheelFresh.running) return
            const cx = root.flick.contentX
            if (cx < -0.5 || cx > root._maxX + 0.5) return
            if (root._lastWheelDx > 0 && root.atLeft()) root.kickX(Math.min(140, root._lastWheelDx))
            else if (root._lastWheelDx < 0 && root.atRight()) root.kickX(Math.max(-140, root._lastWheelDx))
        }
    }

    Component.onCompleted: {
        // Attach the wheel observer straight to the flickable (same
        // delivery path as a hand-written WheelHandler child). Lists whose
        // own handler already routes through scrollY()/scrollX() opt out via
        // interceptWheel (no observer, no watcher — single kick per tick).
        if (root.interceptWheel) {
            try {
                root._wheelFactory.createObject(root.flick)
                root.wheelObserverActive = true
            } catch (e0) {}
        }
        // Attach the visual offset without clobbering an existing transform.
        try {
            const ci = root.flick.contentItem
            if (ci) {
                const cur = ci.transform
                if (cur && cur.length > 0) {
                    const arr = []
                    for (let i = 0; i < cur.length; i++) arr.push(cur[i])
                    arr.push(root._bounce)
                    ci.transform = arr
                } else {
                    ci.transform = root._bounce
                }
            }
        } catch (e) {}
        // Native drag overshoot for everything that is not snap-driven.
        try {
            let snapped = false
            const f = root.flick
            // ListView/GridView expose snapMode; carousels also pin
            // highlightRangeMode to StrictlyEnforceRange.
            if (f && f.snapMode !== undefined && f.snapMode !== Flickable.NoSnap) snapped = true
            if (f && f.highlightRangeMode !== undefined && f.highlightRangeMode === ListView.StrictlyEnforceRange) snapped = true
            if (!snapped) {
                if (f.boundsBehavior === Flickable.StopAtBounds)
                    f.boundsBehavior = Flickable.DragAndOvershootBounds
                if (f.boundsMovement !== undefined)
                    f.boundsMovement = Flickable.FollowBoundsBehavior
            }
        } catch (e2) {}
    }
}
