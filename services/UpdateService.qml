pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
    id: root
    property var updates: []
    property bool checking: false
    property var lastCheckedAt: null
    property var knownUpdateKeys: ({})
    property bool hasCompletedFirstCheck: false

    // DRY: updateCount was an exact duplicate of totalCount and isVisible was
    // never read (callers use displayCount). Keep one canonical count.
    readonly property int totalCount: updates.length
    readonly property bool hasUpdates: updates.length > 0
    property bool debugForce: false
    property int debugCount: 5
    property int displayCount: debugForce ? debugCount : updates.length
    // NOTE: isVisible removed — dead (callers use displayCount > 0).

    readonly property string checkSchedule: settingsFile.adapter.checkSchedule !== undefined ? settingsFile.adapter.checkSchedule : "At startup only"
    readonly property bool offerShutdownAction: {
        let v = settingsFile.adapter.offerShutdownAction
        return v === true || String(v) === "true"
    }
    readonly property int checkIntervalMs: {
        // Lookup statt if-Kette — neue Pläne nur hier ergänzen.
        const table = {
            "Every 30 minutes": 30 * 60 * 1000,
            "Every 2 hours": 2 * 60 * 60 * 1000,
            "Every 6 hours": 6 * 60 * 60 * 1000,
            "Every 12 hours": 12 * 60 * 60 * 1000,
            "Every 24 hours": 24 * 60 * 60 * 1000
        }
        return table[checkSchedule] !== undefined ? table[checkSchedule] : 0
    }

    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/jhqs/config/update_center.json"
        watchChanges: true; blockLoading: true; printErrors: false
        onFileChanged: settingsReloadDebounce.restart()
        adapter: JsonAdapter {
            property string checkSchedule: "At startup only"
            property bool offerShutdownAction: true
        }
    }
    // STABILITY: coalesce editor save bursts (create+write = 2 reloads).
    // FileView defaults already cover missing keys, so no boot mkdir+jq fork.
    Timer {
        id: settingsReloadDebounce
        interval: 300; repeat: false
        onTriggered: { try { settingsFile.reload() } catch (e) { } }
    }

    function checkNow(): void {
        // PERF: coalesce boot + net-flap + rpm-touch storms. All 5 timer
        // sources funnel here; without this 3 check-updates.sh runs queue up.
        checkCoalesce.restart()
    }
    Timer {
        id: checkCoalesce
        interval: 2000; repeat: false
        onTriggered: {
            if (updProc.running) return
            checking = true
            updProc.running = true
        }
    }
    function status(): string {
        return "system=" + _counts.system + " flatpak=" + _counts.flatpak
            + " total=" + totalCount + " hasUpdates=" + hasUpdates
            + " checking=" + checking + " schedule=\"" + checkSchedule + "\""
            + " debugForce=" + debugForce + " display=" + displayCount
    }
    function setDebug(arg: string): string {
        const a = (arg || "").trim().toLowerCase()
        // Ein/Aus-Schalter als Tabelle; count/Numerik fallen unten durch.
        const switches = {
            on: true, "true": true, "1": true, show: true,
            off: false, "false": false, "0": false, hide: false
        }
        if (a === "toggle") {
            debugForce = !debugForce
            return "debugForce=" + debugForce
        }
        if (switches[a] !== undefined) {
            debugForce = switches[a]
            return "debugForce=" + (debugForce ? "ON display=" + displayCount : "OFF hasUpdates=" + hasUpdates)
        }
        let n = parseInt(a.replace(/^count\s+/, ""))
        if (!isNaN(n)) {
            debugCount = n
            debugForce = true
            return "debugCount=" + n
        }
        return "usage: debug on|off|toggle|count <n> | debug 5"
    }

    // Cached per-updates-change breakdown so status()/panel header don't
    // re-scan the list on every binding evaluation.
    readonly property var _counts: {
        let s = 0, f = 0
        for (let i = 0; i < updates.length; i++) {
            let src = updates[i].source
            if (src === "system") s++
            else if (src === "flatpak") f++
        }
        return { system: s, flatpak: f }
    }

    function parseUpdates(raw: string): void {
        let parsed = []
        let nextKeys = ({})
        let newlyAvailable = 0
        let lines = String(raw || "").trim().split("\n")
        for (let i = 0; i < lines.length; i++) {
            if (!lines[i]) continue
            let fields = lines[i].split("\t")
            if (fields.length < 3) continue
            if (fields[0] !== "system" && fields[0] !== "flatpak") continue
            if ((fields[1] || "").trim().length === 0) continue
            let item = { source: fields[0], name: fields[1], detail: fields.slice(2).join("\t") }
            let key = item.source + "\t" + item.name
            nextKeys[key] = true
            if (hasCompletedFirstCheck && !knownUpdateKeys[key]) newlyAvailable++
            parsed.push(item)
        }
        // PERF: compare-before-assign. Identical check results (the common
        // case) must not reset panel Repeaters + _counts bindings.
        lastCheckedAt = new Date()
        hasCompletedFirstCheck = true
        if (isSameUpdateList(parsed, nextKeys)) return
        updates = parsed
        knownUpdateKeys = nextKeys
        if (newlyAvailable > 0) notifyNewUpdates(newlyAvailable)
    }

    // Listenvergleich: Länge + Schlüsselmenge + Reihenfolge/Inhalt.
    function isSameUpdateList(parsed: var, nextKeys: var): bool {
        if (parsed.length !== updates.length) return false
        const oldKeys = knownUpdateKeys
        let newCount = 0, oldCount = 0
        for (let k in nextKeys) newCount++
        for (let k in oldKeys) oldCount++
        if (newCount !== oldCount) return false
        for (let k in nextKeys) {
            if (!oldKeys[k]) return false
        }
        for (let i = 0; i < parsed.length; i++) {
            const a = parsed[i], b = updates[i]
            if (!b || a.source !== b.source || a.name !== b.name || a.detail !== b.detail) return false
        }
        return true
    }

    function notifyNewUpdates(n: int): void {
        let message = n === 1 ? "1 new update is available." : n + " new updates are available."
        notifyProc.command = ["notify-send", "Update Center", message]
        if (!notifyProc.running) notifyProc.running = true
    }
    Process { id: notifyProc; command: ["notify-send", "Update Center", ""] }

    Process {
        id: updProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/jhqs/scripts/check-updates.sh"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseUpdates(text)
        }
        onExited: root.checking = false
    }

    Timer {
        id: pollTimer
        interval: root.checkIntervalMs > 0 ? root.checkIntervalMs : 60000
        running: root.checkIntervalMs > 0
        repeat: true
        onTriggered: root.checkNow()
    }
    Timer { id: startupTimer; interval: 60000; running: true; repeat: false; onTriggered: root.checkNow() }

    Timer { id: netActiveTimer; interval: 8000; repeat: false; onTriggered: root.checkNow() }
    Connections { target: NetworkService; function onNetActiveChanged() { if (NetworkService.netActive) netActiveTimer.restart() } }

    property double _lastDnfMtime: 0
    Process {
        id: dnfMtimeProc
        command: ["bash", "-c", "stat -c %Y /var/log/dnf5.log 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let n = parseInt(((text || "").trim() || "0"))
                if (isNaN(n)) return
                if (root._lastDnfMtime === 0) { root._lastDnfMtime = n; return }
                if (n !== root._lastDnfMtime) { root._lastDnfMtime = n; externalTimer.restart() }
            }
        }
    }
    Timer { id: dnfMtimeTimer; interval: 1800000; running: true; repeat: true; triggeredOnStart: false; onTriggered: if (!dnfMtimeProc.running) dnfMtimeProc.running = true }
    Timer { id: externalTimer; interval: 4000; repeat: false; onTriggered: root.checkNow() }
}
