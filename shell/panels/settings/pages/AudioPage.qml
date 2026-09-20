pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../../../../style/themes"
import "../../../../backend/services"
import "../../../../style/ui"
import ".."

// Android 17 Settings — Sound.
// Output (level, mute, device) and Input (level, mute, device) on M3E cards.
NexusControls.PageBase {
    id: root
    title: "Sound"

    property bool pageVisible: false
    property var sinks: []
    property string defaultSink: ""
    property var sources: []
    property string defaultSource: ""
    property int inputPct: 0
    property bool inputMuted: false
    readonly property bool hasInput: root.sources.length > 0

    // ---- device enumeration ---------------------------------------------
    function parseDevices(out: string): var {
        let arr = []
        let seen = {}
        for (let ln of (out || "").split("\n")) {
            ln = ln.trim()
            if (!ln) continue
            let sep = ln.indexOf("|")
            if (sep === -1) continue
            let nm = ln.substring(0, sep).trim()
            let ds = ln.substring(sep + 1).trim()
            if (!nm || seen[nm]) continue
            seen[nm] = true
            arr.push({name: nm, desc: Util.cleanAudioName(ds, nm)})
        }
        return arr
    }
    function labelFor(list: var, name: string): string {
        for (let i = 0; i < list.length; i++) if (list[i].name === name) return list[i].desc.length > 0 ? list[i].desc : list[i].name
        return name
    }
    Process {
        id: sinkListProc
        command: ["bash", "-c", "LC_ALL=C pactl list sinks 2>/dev/null | awk ' /Name:/{n=$2} /Description:|Beschreibung:/{sub(/^[^:]*: /, \"\"); d=$0; print n\"|\"d}'"]
        stdout: StdioCollector {
            onStreamFinished: root.sinks = root.parseDevices(text || "")
        }
    }
    Process {
        id: sourceListProc
        command: ["bash", "-c", "LC_ALL=C pactl list sources 2>/dev/null | grep -v '\\.monitor' | awk ' /Name:/{n=$2} /Description:|Beschreibung:/{sub(/^[^:]*: /, \"\"); d=$0; print n\"|\"d}'"]
        stdout: StdioCollector {
            onStreamFinished: root.sources = root.parseDevices(text || "")
        }
    }
    Process {
        id: sinkDefProc
        command: ["bash", "-c", "pactl get-default-sink 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let o = (text || "").trim()
                if (o) root.defaultSink = o
            }
        }
    }
    // Default source + its level/mute in one fork.
    Process {
        id: sourceStateProc
        command: ["bash", "-c", "def=$(pactl get-default-source 2>/dev/null); vol=$(pactl get-source-volume \"$def\" 2>/dev/null | grep -oP '\\d+%' | head -1); mute=$(pactl get-source-mute \"$def\" 2>/dev/null | grep -oP '(yes|no)' | head -1); echo \"$def|$vol|$mute\" | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = ((text || "").trim()).split("|")
                root.defaultSource = (p[0] || "").trim()
                let v = parseInt((p[1] || "").replace("%", ""))
                if (!isNaN(v)) root.inputPct = Math.max(0, Math.min(100, v))
                root.inputMuted = (p[2] || "").trim() === "yes"
            }
        }
    }
    function refreshSinks(): void {
        if (!sinkListProc.running) sinkListProc.running = true
        if (!sinkDefProc.running) sinkDefProc.running = true
    }
    function refreshSources(): void {
        if (!sourceListProc.running) sourceListProc.running = true
        if (!sourceStateProc.running) sourceStateProc.running = true
    }
    function refreshAll(): void {
        refreshSinks()
        refreshSources()
    }
    Component.onCompleted: refreshAll()
    onPageEntered: {
        root.pageVisible = true
        root.refreshAll()
    }
    onPageLeft: root.pageVisible = false
    Timer { interval: 10000; running: root.pageVisible; repeat: true; onTriggered: root.refreshAll() }

    // ---- actions ---------------------------------------------------------
    Process { id: sinkSetProc; command: ["bash", "-c", "echo"] }
    function switchSink(name: string): void {
        if (!name) return
        // STABILITY: full DQ-escape ($ ` \ ") — old code only escaped quotes,
        // leaving command substitution open on crafted sink names.
        let safe = Util.shellEscapeDq(name)
        root.defaultSink = name
        sinkSetProc.command = ["bash", "-c", "pactl set-default-sink \"" + safe + "\" 2>/dev/null; for i in $(pactl list short sink-inputs 2>/dev/null | cut -f1); do pactl move-sink-input \"$i\" \"" + safe + "\" 2>/dev/null; done; echo done"]
        if (!sinkSetProc.running) sinkSetProc.running = true
    }
    Process { id: sourceSetProc; command: ["bash", "-c", "echo"]; stdout: StdioCollector { onStreamFinished: root.refreshSources() } }
    function switchSource(name: string): void {
        if (!name) return
        let safe = Util.shellEscapeDq(name)
        root.defaultSource = name
        sourceSetProc.command = ["bash", "-c", "pactl set-default-source \"" + safe + "\" 2>/dev/null; echo done"]
        if (!sourceSetProc.running) sourceSetProc.running = true
    }
    // Input level: optimistic value, coalesced 100ms flush (dragging must not
    // fork pactl per pixel).
    Process { id: sourceVolProc; command: ["bash", "-c", "echo"] }
    property string _srcVolPending: ""
    Timer { id: srcVolTimer; interval: 100; repeat: false; onTriggered: root.flushSrcVol() }
    function setInputVolume(pct: int): void {
        root.inputPct = pct
        root._srcVolPending = "pactl set-source-volume @DEFAULT_SOURCE@ " + pct + "% 2>/dev/null; pactl set-source-mute @DEFAULT_SOURCE@ 0 2>/dev/null; echo done"
        srcVolTimer.restart()
    }
    function flushSrcVol(): void {
        if (root._srcVolPending === "") return
        if (sourceVolProc.running) { srcVolTimer.restart(); return }
        sourceVolProc.command = ["bash", "-c", root._srcVolPending]
        root._srcVolPending = ""
        sourceVolProc.running = true
    }
    Process { id: sourceMuteProc; command: ["bash", "-c", "echo"]; stdout: StdioCollector { onStreamFinished: root.refreshSources() } }
    function setInputMuted(m: bool): void {
        m = !!m
        if (m === root.inputMuted) return
        root.inputMuted = m
        if (!sourceMuteProc.running) {
            sourceMuteProc.command = ["bash", "-c", "pactl set-source-mute @DEFAULT_SOURCE@ " + (m ? "1" : "0") + " 2>/dev/null; echo done"]
            sourceMuteProc.running = true
        }
    }

    // ---- UI --------------------------------------------------------------
    NexusControls.SectionHeader { first: true; text: "Output" }
    // NOTE: volume/mute go through VolumeService (PipeWire direct, instant
    // indicators). The old per-pixel wpctl fork queue lived here and lagged
    // behind the finger.
    NexusControls.SliderRow {
        first: true
        icon: VolumeService.icon
        label: "Output"
        from: 0; to: 100; stepSize: 1; unit: "%"
        value: VolumeService.pct
        onMoved: v => VolumeService.setVolumeFrac(Math.round(v) / 100)
        onApplied: v => VolumeService.setVolumeFrac(Math.round(v) / 100)
    }
    NexusControls.ToggleRow {
        icon: VolumeService.isMuted ? "󰝟" : "󰕾"
        tint: VolumeService.isMuted ? Theme.errorColor : Theme.primary
        text: VolumeService.isMuted ? "Unmute" : "Mute"
        checked: !VolumeService.isMuted
        onToggled: n => VolumeService.setMuted(!n)
    }
    NexusControls.DropdownRow {
        last: true
        icon: "󰓃"
        tint: Theme.tertiary
        label: "Output device"
        options: root.sinks.map(s => s.desc.length > 0 ? s.desc : s.name)
        current: root.labelFor(root.sinks, root.defaultSink)
        onPicked: v => { let m = root.sinks.find(s => (s.desc.length > 0 ? s.desc : s.name) === v); if (m) switchSink(m.name) }
    }

    NexusControls.SectionHeader { visible: root.hasInput; text: "Input" }
    NexusControls.SliderRow {
        visible: root.hasInput
        first: true
        icon: "󰍬"
        label: "Input"
        from: 0; to: 100; stepSize: 1; unit: "%"
        value: root.inputPct
        onMoved: v => root.setInputVolume(Math.round(v))
        onApplied: v => root.setInputVolume(Math.round(v))
    }
    NexusControls.ToggleRow {
        visible: root.hasInput
        icon: root.inputMuted ? "󰍭" : "󰍬"
        tint: root.inputMuted ? Theme.errorColor : Theme.primary
        text: root.inputMuted ? "Unmute input" : "Mute input"
        checked: !root.inputMuted
        onToggled: n => root.setInputMuted(!n)
    }
    NexusControls.DropdownRow {
        visible: root.hasInput
        last: true
        icon: "󰍬"
        tint: Theme.tertiary
        label: "Input device"
        options: root.sources.map(s => s.desc.length > 0 ? s.desc : s.name)
        current: root.labelFor(root.sources, root.defaultSource)
        onPicked: v => { let m = root.sources.find(s => (s.desc.length > 0 ? s.desc : s.name) === v); if (m) switchSource(m.name) }
    }
}
