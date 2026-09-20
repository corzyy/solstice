pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// InstanceGuard — single-instance guard for the solstice shell.
//
// A second instance of the same config would fight the first over the
// notification server and polkit agent DBus names (and stack a second bar on
// screen). quickshell's `--no-duplicate` flag only covers launches through
// backend/scripts/solstice, so the config runs the same check itself:
// backend/scripts/instance-check.sh reports whether this process is the
// oldest live instance of this config.
//
// The guard only reports; shell.qml decides what to do (quit duplicates) and
// gates the notification server / polkit agent on isPrimary so no service is
// registered before the check has run.
//
// If the check cannot run or times out, isPrimary defaults to true: a broken
// guard must never keep the shell from starting.
Singleton {
    id: root

    readonly property bool checked: _checked
    readonly property bool isPrimary: _isPrimary
    readonly property bool isDuplicate: _checked && !_isPrimary
    property bool _checked: false
    property bool _isPrimary: false

    Component.onCompleted: start()

    function start(): void {
        if (_checked || checkProc.running) return
        checkProc.running = true
        checkTimeout.restart()
    }

    function settle(primary: bool): void {
        if (_checked) return
        _isPrimary = primary
        _checked = true
        checkTimeout.stop()
    }

    Process {
        id: checkProc
        command: [
            "bash",
            Quickshell.shellDir + "/backend/scripts/instance-check.sh",
            Quickshell.shellDir + "/shell.qml",
            String(Quickshell.processId)
        ]
        stdout: StdioCollector {
            onStreamFinished: root.settle(("" + text).trim() !== "duplicate")
        }
    }

    Timer {
        id: checkTimeout
        interval: 3000; repeat: false
        onTriggered: {
            // Process failed to produce output (missing bash, hung list, …):
            // treat this instance as primary rather than blocking the shell.
            try { checkProc.running = false } catch (e) { }
            root.settle(true)
        }
    }
}
