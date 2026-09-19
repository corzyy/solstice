// PanelMorph — handoff state for cross-panel morphs (ui/CaelestiaPopout).
//
// shell.qml calls begin(from, to, direction) just before it flips
// activePanel; begin() stays inactive for a cold open, so the handoff only
// ever runs panel-to-panel. Every bar popout publishes its settled card rect
// under its morphId while open; the incoming popout claims the outgoing rect
// when it maps, starts its card at that pose and glides to its own
// (container transform). The outgoing content starts fading/shifting out the
// instant the switch begins and its card holds until the incoming one has
// rendered its first frame (markReady); the incoming card swaps in at the
// same pose on the shared departure clock (leftAt) and its content follows;
// the outgoing card fades out underneath it. `direction` drives the content
// travel of that choreography.
pragma Singleton
import QtQuick

QtObject {
    id: root

    // A handoff is in flight (from -> to); cleared by finish().
    property bool active: false
    // The incoming popout has rendered at the outgoing pose.
    property bool ready: false
    property string fromId: ""
    property string toId: ""
    // Overlay drill-in (control center): the CC stays mapped as the dimmed
    // backdrop and the incoming card grows out of the clicked button's rect
    // instead of taking over an outgoing card's pose. There is no outgoing
    // side to hold, so the handoff is a one-sided glide from the origin.
    property bool overlay: false
    // morphId -> origin { x, y, width, height } of the active overlay run.
    property var origins: ({})
    // morphId -> origin published by the source panel (consumed by
    // shell.qml's beginPanelMorph, one-shot).
    property var pendingOrigins: ({})
    // Button that sourced the current overlay drill-in ("" = none). Set by
    // beginOverlay and kept for the WHOLE lifetime of the overlay run — the
    // source panel reads it to hide the button while its panel is open — and
    // cleared when the return run has dissolved into it (finish()/begin()).
    property string originId: ""
    // Visibility of the origin button: 0 while the panel is open, animated
    // back to 1 by the popout's return run (the card dissolves into it), so
    // the button reappears exactly as the panel shrinks into its pose.
    property real sourceReveal: 1
    // Wall-clock (Date.now()) at which the outgoing side started its content
    // exit. Both sides share this clock: the incoming side only waits out
    // whatever is left of the lead when its first frame lands, so a slow
    // surface map no longer stacks a full fixed pause on top of the map
    // latency. 0 until the outgoing popout reports the departure.
    property double leftAt: 0
    // Depth of the switch for the content choreography (CaelestiaPopout):
    // +1 deeper into a drill-in (control center -> audio/bluetooth/updates),
    // -1 back out, 0 lateral (bar panel <-> bar panel).
    property int direction: 0
    // morphId -> { x, y, width, height } in window/screen coordinates.
    property var rects: ({})

    function begin(from: string, to: string, direction: int): void {
        root.fromId = from
        root.toId = to
        root.direction = direction === undefined ? 0 : direction
        root.ready = false
        root.leftAt = 0
        root.overlay = false
        root.origins = ({})
        // A regular handoff replaces (or aborts) any overlay source: its
        // button becomes visible again.
        root.originId = ""
        root.sourceReveal = 1
        root.active = from !== "" && to !== "" && from !== to
    }
    // Source side (control center tile/button): remember where the drill-in
    // was clicked from. shell.qml hands the rect to beginOverlay() when the
    // panel switch starts.
    function publishOrigin(id: string, rect): void {
        if (!id || !rect || rect.width <= 0 || rect.height <= 0)
            return
        root.pendingOrigins[id] = { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
    }
    function takeOrigin(id: string): var {
        const r = root.pendingOrigins[id] || null
        if (r)
            delete root.pendingOrigins[id]
        return r
    }
    // Overlay handoff: to is the incoming panel, origin the clicked rect.
    // The button itself stays visible until the incoming card's first frame
    // hides it (CaelestiaPopout.morphFrame); `sourceReveal` is then animated
    // back to 1 by the return run.
    function beginOverlay(to: string, origin, direction: int): void {
        root.fromId = ""
        root.toId = to
        root.direction = direction === undefined ? 1 : direction
        root.ready = false
        root.leftAt = 0
        root.overlay = to !== "" && origin !== null && origin !== undefined
        let m = {}
        if (root.overlay)
            m[to] = origin
        root.origins = m
        root.originId = root.overlay ? to : ""
        root.sourceReveal = 1
        root.active = root.overlay
    }
    function originOf(id: string): var {
        if (!root.active || !root.overlay)
            return null
        return root.origins[id] || null
    }
    // Outgoing side: content exit is on the animation clock now. Reports the
    // departure once per handoff (begin() clears it).
    function noteDeparture(): void {
        if (root.active && root.leftAt === 0)
            root.leftAt = Date.now()
    }
    // Milliseconds left of `lead` since noteDeparture(); full `lead` while no
    // departure was reported (a timer scheduled from here can never fire
    // before the outgoing content has actually started leaving).
    function leadRemaining(lead: int): int {
        if (root.leftAt === 0)
            return lead
        return Math.max(0, lead - (Date.now() - root.leftAt))
    }
    function isSource(id: string): bool {
        return root.active && root.fromId === id
    }
    function isTarget(id: string): bool {
        return root.active && root.toId === id
    }
    function publish(id: string, rect): void {
        if (!id || !rect || rect.width <= 0 || rect.height <= 0)
            return
        // Plain object on purpose: the rects map is read via rectOf() only,
        // so no change notification (and no binding churn) is needed.
        root.rects[id] = { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
    }
    function rectOf(id: string): var {
        return root.rects[id] || null
    }
    function markReady(id: string): void {
        if (root.active && root.toId === id)
            root.ready = true
    }
    // Handoff state only: the overlay source (originId/sourceReveal) stays,
    // so the source panel keeps the button hidden while the panel is open —
    // and while its return run is still dissolving into it. Used for opens,
    // switches and dismissals; the return run releases the source itself
    // (CaelestiaPopout._finishMorphBack).
    function clear(): void {
        root.active = false
        root.ready = false
        root.fromId = ""
        root.toId = ""
        root.leftAt = 0
        root.overlay = false
        root.origins = ({})
        root.pendingOrigins = ({})
    }
    // Full reset (a switch that cannot run an overlay return, e.g. a panel
    // with no registered origin): the button is visible again immediately.
    function finish(): void {
        root.clear()
        root.originId = ""
        root.sourceReveal = 1
    }
}
