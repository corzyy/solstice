pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// LogService — persistent error logging while the shell is running.
//
// Qt/QML runtime errors and warnings only live on Quickshell's internal
// log (ephemeral, under $XDG_RUNTIME_DIR). This service follows that log
// with backend/scripts/log-errors.sh and appends every ERROR / WARN / CRITICAL /
// FATAL line, timestamped, to <shellDir>/logs/errors.log.
//
// A unique marker is emitted into the shell log on every start; the
// follower ignores everything before it, so a config reload never
// duplicates earlier entries. The shell itself can report caught errors
// via record() (e.g. shell.qml reports Quickshell.reloadFailed).
// NOTE: `import Quickshell` is required — it provides the `Singleton` type.
Singleton {
    id: root

    readonly property string logDir: Quickshell.shellDir + "/logs"
    readonly property string errorLogPath: logDir + "/errors.log"
    property bool enabled: true

    // One-time marker: everything decoded before it is stale history.
    readonly property string _marker: "solstice-log-marker-" + Date.now() + "-" + Math.floor(Math.random() * 4294967296).toString(16)
    property bool _started: false

    function start(): void {
        if (_started || !enabled) return
        _started = true
        // Stop the previous config's follower first: it survives reloads
        // (QProcess children are not killed). Only then emit the marker,
        // so nothing between marker and takeover can be logged twice.
        stopProc.running = true
    }

    function emitMarkerAndTail(): void {
        if (!_started || !enabled) return
        console.info(_marker)
        if (ensureDirProc.running) startTail()
        else ensureDirProc.running = true
    }

    Process {
        id: stopProc
        command: ["bash", Quickshell.shellDir + "/backend/scripts/log-errors.sh", "--stop", root.logDir]
        onExited: root.emitMarkerAndTail()
    }

    function startTail(): void {
        if (!_started || !enabled) return
        tailProc.command = [
            "bash",
            Quickshell.shellDir + "/backend/scripts/log-errors.sh",
            String(Quickshell.processId),
            _marker,
            errorLogPath
        ]
        if (!tailProc.running) tailProc.running = true
    }

    // Report an error raised by the shell itself.
    // STABILITY: Quickshell delivers some signals (e.g. reloadFailed)
    // twice per event. Consecutive identical reports within 2s are one
    // event — drop the echo so the log stays readable.
    property string _lastRecordKey: ""
    property double _lastRecordTime: 0
    function record(level: string, message: string, source: string): void {
        if (!enabled) return
        let ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
        // Keep one log line per entry — multi-line messages (e.g. reload
        // failures) are folded so every line stays timestamped.
        let flat = String(message).replace(/\n+/g, " | ").trim()
        let key = String(level) + "|" + String(source) + "|" + flat
        let now = Date.now()
        if (key === _lastRecordKey && (now - _lastRecordTime) < 2000) return
        _lastRecordKey = key
        _lastRecordTime = now
        let line = "[" + ts + "] [" + String(level).toUpperCase() + "] "
            + (source ? String(source) + ": " : "") + flat
        _queue.push(line)
        pumpWriter()
    }

    // STABILITY: single writer process drained from a queue — concurrent
    // record() calls coalesce instead of forking one bash per line.
    property var _queue: []
    property bool _writing: false
    function pumpWriter(): void {
        if (_writing || _queue.length === 0) return
        _writing = true
        let payload = _queue.join("\n")
        _queue = []
        writerProc.command = [
            "bash", "-c",
            "printf '%s\\n' \"$1\" >> \"$2\"",
            "solstice-log", payload, errorLogPath
        ]
        writerProc.running = true
    }
    Process {
        id: writerProc
        command: ["bash", "-c", "true"]
        onExited: { root._writing = false; root.pumpWriter() }
    }

    Process {
        id: ensureDirProc
        command: ["bash", "-c", "mkdir -p \"$1\"", "solstice-log", root.logDir]
        onExited: root.startTail()
    }

    Process {
        id: tailProc
        command: ["bash", "-c", "true"]
        // The follower only exits if the log backend dies or the script
        // is killed. Retry once after a delay, unless we were stopped.
        onExited: if (root._started && root.enabled) tailRestartTimer.start()
    }
    Timer {
        id: tailRestartTimer
        interval: 2000; repeat: false
        onTriggered: if (root._started && root.enabled && !tailProc.running) tailProc.running = true
    }
}
