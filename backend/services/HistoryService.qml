pragma Singleton
import QtQuick
import Quickshell

// RAM: history entries are capped and large strings truncated so 100
// notifications cannot pin MBs of markup.
// NOTE: `import Quickshell` is required — it provides the `Singleton` type.
Singleton {
    id: root
    property var history: []
    readonly property int maxHistory: 100
    // PERF: burst-coalesced adds. Notification bursts (20+ toasts) used to
    // copy the array + notify all consumers per toast. Now appends queue
    // and flush once per event loop tick.
    property var _pending: []
    property bool _flushScheduled: false
    function add(entry: var): void {
        let safe = sanitize(entry)
        if (!safe) return
        _pending.push(safe)
        if (!_flushScheduled) {
            _flushScheduled = true
            Qt.callLater(flushPending)
        }
    }
    function flushPending(): void {
        _flushScheduled = false
        if (_pending.length === 0) return
        let next = history.concat(_pending)
        _pending = []
        if (next.length > maxHistory) next = next.slice(-maxHistory)
        history = next
    }
    function sanitize(entry: var): var {
        // CRASH FIX: only plain JSON-safe types may enter history.
        // Storing notification.actions (list<NotificationAction QObjects>)
        // or other Qt objects makes the CalendarPanel Repeaters segfault
        // in QV4::fromData/fromQVariantMap on open (all recent crashes
        // share that stack). Rebuild a sanitized snapshot here so no
        // caller can smuggle a QObject into `history`.
        try {
            if (!entry) return null
            return {
                id: Math.round(finiteNumber(entry.id, -1)),
                appName: String(entry.appName || "Notification").slice(0, 120),
                summary: String(entry.summary || "").slice(0, 300),
                body: String(entry.body || "").slice(0, 500),
                urgency: Math.round(finiteNumber(entry.urgency, 1)),
                time: Math.round(normalizeTime(entry.time))
            }
        } catch (e) { return null }
    }

    function finiteNumber(value: var, fallback: real): real {
        const n = Number(value)
        return isFinite(n) ? n : fallback
    }

    function normalizeTime(t: var): real {
        try {
            if (typeof t === "number" && isFinite(t)) return Math.round(t)
            if (t instanceof Date && !isNaN(t.getTime())) return t.getTime()
            if (t !== undefined && t !== null) {
                const d = new Date(t)
                if (!isNaN(d.getTime())) return d.getTime()
            }
        } catch (e) {}
        return Date.now()
    }
    function remove(id: int): void {
        let before = history.length
        if (before === 0) return
        let next = history.filter(e => e.id !== id)
        if (next.length === before) return
        history = next
    }
    function clear(): void { if (history.length === 0 && _pending.length === 0) return; _pending = []; history = [] }
    // NOTE: count() removed — dead wrapper, callers use history.length.
}
