pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../themes"

Singleton {
    id: root
    property PwNode sink: Pipewire.defaultAudioSink
    property bool sinkReady: sink && sink.ready && sink.audio
    // BINDING: PipeWire objects stay unbound (no ready/audio/volume signals)
    // unless tracked. Without this, sinkReady was false forever and every
    // indicator (bar, OSD, panel) fell back to slow 5s shell polling.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    property int pct: sinkReady ? Math.round(sink.audio.volume * 100) : fbPct
    property bool isMuted: sinkReady ? sink.audio.muted : fbMuted
    property int fbPct: 0
    property bool fbMuted: false

    FileView {
        id: volumeFile
        path: Quickshell.env("HOME") + "/.config/quickshell/jhqs/config/volume.json"
        watchChanges: true; blockLoading: true; printErrors: false
        onFileChanged: volumeReloadDebounce.restart()
        adapter: JsonAdapter {
            property bool showPct: false
        }
    }
    Timer {
        id: volumeReloadDebounce
        interval: 250; repeat: false
        onTriggered: { try { volumeFile.reload() } catch (e) { } }
    }
    readonly property bool showPct: volumeFile.adapter.showPct === true
    function setShowPct(v: bool): void {
        let nv = !!v
        if ((volumeFile.adapter.showPct === true) === nv) return
        volumeFile.adapter.showPct = nv
        volumeFile.writeAdapter()
    }

    readonly property string icon: volumeIcon(isMuted, pct)

    // Schwellen in einer Tabelle statt verschachteltem Ternary.
    function volumeIcon(muted: bool, percent: int): string {
        if (muted || percent === 0) return "󰝟"
        if (percent < 34) return "󰕿"
        if (percent < 67) return "󰖀"
        return "󰕾"
    }

    Process {
        id: volProbe
        command: ["bash", "-c", Quickshell.env("HOME") + "/.config/quickshell/jhqs/scripts/volume.sh get 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (text || "").trim()
                if (out === "muted") root.fbMuted = true
                else if (out.endsWith("%")) {
                    let n = parseInt(out)
                    if (!isNaN(n)) { root.fbPct = n; root.fbMuted = false }
                }
            }
        }
    }
    // CPU/RAM: fallback shell probe used to run every 1s forever, even when
    // PipeWire signals already drive pct/isMuted. Gate it to !sinkReady and
    // slow to 5s so the steady state is zero forks on a working PipeWire box.
    // STABILITY: back off to 15s after 3 consecutive empty probes (broken
    // PipeWire shouldn't fork forever at 5s).
    property int _probeFails: 0
    Timer {
        interval: _probeFails >= 3 ? 15000 : 5000
        running: !root.sinkReady
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!volProbe.running) volProbe.running = true
    }

    Process { id: volUp; command: ["/usr/bin/wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+", "-l", "1.0"]; onExited: pumpStepProc() }
    Process { id: volDown; command: ["/usr/bin/wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]; onExited: pumpStepProc() }
    Process { id: volMuteToggle; command: ["/usr/bin/wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] }
    Process { id: volMuteSetProc; command: ["bash", "-c", "echo"] }
    Process { id: volSetProc; command: ["bash", "-c", "echo"] }

    function stepUp(): void { stepBy(0.05) }
    function stepDown(): void { stepBy(-0.05) }

    // Fast path: PipeWire direct set (needs the PwObjectTracker above).
    // No fork, no wpctl round-trip — pct/isMuted follow on the next PipeWire
    // event (~ms), so bar/OSD/panel update instantly.
    function stepBy(d: real): void {
        if (trySink(sink => {
            let v = Math.round(((sink.audio.volume || 0) + d) * 100) / 100
            sink.audio.volume = Math.max(0, Math.min(1, v))
            if (sink.audio.muted && v > 0) sink.audio.muted = false
        })) { Theme.triggerVolumeOsd(); return }
        runVolumeProc(d > 0 ? volUp : volDown)
    }
    // STABILITY: guard key-hold storms (20/s). Coalesce — intermediate
    // steps are obsolete the moment a newer one arrives — but never drop the
    // latest one, and always trigger the OSD (old code dropped both).
    property var _stepPending: null
    function runVolumeProc(proc: var): void {
        Theme.triggerVolumeOsd()
        if (proc.running) { _stepPending = proc; return }
        proc.running = true
    }
    function pumpStepProc(): void {
        if (_stepPending === null || _stepPending === undefined) return
        let p = _stepPending
        _stepPending = null
        if (!p.running) p.running = true
        else _stepPending = p
    }
    // Führt fn gegen die PipeWire-Senke aus; false bei Fallback-Bedarf.
    // (Ersetzt 3x identische try/sinkReady-Blöcke.)
    function trySink(fn: var): bool {
        try {
            if (sinkReady) {
                fn(sink)
                return true
            }
        } catch (e) {}
        return false
    }
    function toggleMute(): void {
        if (trySink(sink => { sink.audio.muted = !sink.audio.muted })) { Theme.triggerVolumeOsd(); return }
        if (!volMuteToggle.running) volMuteToggle.running = true
        Theme.triggerVolumeOsd()
    }
    function setMuted(m: bool): void {
        if (trySink(sink => { sink.audio.muted = !!m })) { Theme.triggerVolumeOsd(); return }
        if (!volMuteSetProc.running) {
            volMuteSetProc.command = ["/usr/bin/wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", m ? "1" : "0"]
            volMuteSetProc.running = true
        }
        Theme.triggerVolumeOsd()
    }
    function setVolumeFrac(v: real): void {
        const target = Math.max(0, Math.min(1, v))
        Theme.triggerVolumeOsd()
        if (trySink(sink => {
            sink.audio.volume = target
            if (sink.audio.muted && target > 0) sink.audio.muted = false
        })) return
        // PERF: throttle fallback slider path (80ms) — each tick forks wpctl.
        _pendingVol = target
        if (!volThrottle.running) { volThrottle.start(); flushFallbackVol() }
    }
    property real _pendingVol: -1
    Timer {
        id: volThrottle
        interval: 80; repeat: false
        onTriggered: flushFallbackVol()
    }
    function flushFallbackVol(): void {
        if (_pendingVol < 0) return
        if (volSetProc.running) { volThrottle.restart(); return }
        let v2 = _pendingVol
        _pendingVol = -1
        volSetProc.command = ["/usr/bin/wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.round(v2 * 100) + "%"]
        volSetProc.running = true
    }
}
