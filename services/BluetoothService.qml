pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "BluetoothModel.js" as Bt

// Native BlueZ backend (Quickshell.Bluetooth D-Bus binding) — no bluetoothctl
// polling. Panel/pin model ported from AROICE-HQ/omarchy-bluetooth (MIT):
// connected/known/discovered sections, per-device battery, pin-for-
// auto-reconnect with a background watcher (20s poll, 60s per-device
// cooldown, survives sleep/resume), audio-output follow on connect.
Singleton {
    id: root

    // ---- Native bindings ----
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var rawDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []

    // ---- Compat state (read by widget/bar/panel) ----
    readonly property bool btAvailable: adapter !== null
    readonly property bool btActive: !!adapter && adapter.enabled
    readonly property bool btScanning: !!adapter && adapter.discovering
    property var btDevices: []
    // Cold start: BlueZ enumeration takes ~2-3s after shell start, during
    // which adapter is null and the panel must show loading — not "no
    // adapter". Latched true on first sighting, with a timeout fallback so
    // a missing backend can't wedge the UI forever.
    property bool btReady: false
    Timer { interval: 6000; running: !root.btReady; repeat: false; onTriggered: root.btReady = true }
    onAdapterChanged: if (root.adapter !== null) root.btReady = true

    readonly property string icon: {
        if (!btActive)
            return "󰂲";
        try {
            for (let d of btDevices) {
                if (d && d.connected)
                    return "󰂱";
            }
        } catch (e) {}
        return "󰂯";
    }

    // Global busy label for the hero line; per-row labels via actionFor().
    readonly property string btAction: {
        try {
            for (var addr in pendingActions) {
                let a = pendingActions[addr];
                if (a === "connecting")
                    return "Connecting…";
                if (a === "disconnecting")
                    return "Disconnecting…";
                if (a === "forgetting")
                    return "Removing…";
            }
        } catch (e) {}
        return "";
    }
    property string btLastError: ""
    function clearError(): void {
        if (root.btLastError !== "")
            root.btLastError = "";
    }

    // ---- Buckets (human-named, sorted — same grouping as upstream) ----
    readonly property var _btGroups: {
        try {
            return Bt.deviceLists(root.btDevices);
        } catch (e) {
            return { connected: [], known: [], discovered: [] };
        }
    }
    readonly property var connectedDevs: _btGroups.connected
    // Compat: "paired" section = remembered but not connected.
    readonly property var pairedDevs: _btGroups.known
    // Compat: "available" section = discovered while scanning.
    readonly property var availDevs: _btGroups.discovered

    // ---- Projection: native Device objects -> plain rows ----
    // (Never hold Device QObjects in models: BlueZ churn can destroy them
    // while a delegate incubates, segfaulting quickshell.)
    // Grace cache: discovery adds/drops temporary objects every few seconds,
    // which rebuilt the whole list (flicker, cursor jumps). Missing entries
    // are kept briefly — remembered 60s, discovered 15s — and flagged stale.
    property var _rowCache: ({})
    property var _forgetBlock: ({})
    readonly property int _graceRememberedMs: 60000
    readonly property int _graceDiscoveredMs: 15000
    function syncDevices(): void {
        let now = Date.now();
        let arr = [];
        let seen = ({});
        // PERF: one clone per sync instead of one per device. The old loop
        // cloned the whole map inside the device loop (O(n^2) per 2s tick).
        let nextCache = Bt.cloneMap(_rowCache);
        try {
            for (let d of (root.rawDevices || [])) {
                let r = Bt.deviceRow(d);
                if (!r)
                    continue;
                r.stale = false;
                arr.push(r);
                // Cache keyed UPPER-case: pending/forget keys are normalized.
                let key = ((r.address || "").toUpperCase());
                seen[key] = true;
                nextCache[key] = { row: r, at: now };
            }
        } catch (e) {}
        try {
            for (let addr in nextCache) {
                if (seen[addr])
                    continue;
                let e = nextCache[addr];
                if (!e || !e.row)
                    continue;
                if ((pendingActions[addr] || "") === "forgetting" || _forgetBlock[addr]) {
                    delete nextCache[addr];
                    continue;
                }
                let grace = Bt.remembered(e.row) ? root._graceRememberedMs : root._graceDiscoveredMs;
                if (now - (e.at || 0) > grace) {
                    delete nextCache[addr];
                    continue;
                }
                let g = Bt.cloneMap(e.row);
                g.stale = true;
                arr.push(g);
            }
        } catch (e2) {}
        _rowCache = nextCache;
        let cur = root.btDevices;
        if (!isSameRowList(cur, arr))
            root.btDevices = arr;
        syncPendingActions();
    }

    // Zeilenvergleich für compare-before-assign (kein Repeater-Reset bei
    // identischer Aufzählung — dem häufigsten Poll-Ergebnis).
    function isSameRowList(cur: var, next: var): bool {
        if (cur.length !== next.length) return false
        for (let i = 0; i < next.length; i++) {
            const a = next[i], b = cur[i]
            if (!b || a.address !== b.address || a.name !== b.name
                || a.deviceName !== b.deviceName || a.connected !== b.connected
                || a.paired !== b.paired || a.bonded !== b.bonded
                || a.trusted !== b.trusted || a.pairing !== b.pairing
                || a.state !== b.state || a.batteryAvailable !== b.batteryAvailable
                || a.battery !== b.battery || !!a.stale !== !!b.stale) return false
        }
        return true
    }
    onRawDevicesChanged: syncDevices()
    // Cheap pure-JS re-projection (zero forks): catches inner property flips
    // (connected/battery/paired) even when the model itself doesn't re-emit.
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: syncDevices() }

    // ---- Discovery (driven by panel open/close via setScanning) ----
    property bool scanWanted: false
    // Keep nudging discovery on while the panel is open: BlueZ rejects
    // StartDiscovery while powering up and sessions can time out alone.
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.scanWanted && root.adapter !== null && root.btActive && !root.btScanning
        onTriggered: { root.adapter.discovering = true; }
    }
    // Declarative stop: bound to confirmed state, so a stop issued while a
    // just-fired start awaits confirmation isn't swallowed. Bounded so a
    // session another client holds can't draw stops forever.
    property int _stopAttempts: 0
    Timer {
        interval: 1000; repeat: true
        running: !root.scanWanted && root.adapter !== null && root.btScanning
        onRunningChanged: if (running) root._stopAttempts = 0
        onTriggered: {
            root._stopAttempts += 1;
            if (root._stopAttempts > 3) {
                root.scanWanted = false;
                return;
            }
            root.adapter.discovering = false;
        }
    }
    function setScanning(on: bool): void {
        root.clearError();
        if (on) {
            root.scanWanted = true;
            if (root.adapter !== null && root.btActive && !root.btScanning)
                root.adapter.discovering = true;
        } else {
            root.scanWanted = false;
        }
    }

    function togglePower(): void {
        root.clearError();
        if (root.adapter !== null)
            root.adapter.enabled = !root.adapter.enabled;
    }

    // ---- Device lookup + actions ----
    function deviceByAddress(address: string): var {
        let want = ((address || "").trim().toUpperCase());
        if (want === "")
            return null;
        try {
            for (let d of (root.rawDevices || [])) {
                if (d && ((d.address || "").toUpperCase() === want))
                    return d;
            }
        } catch (e) {}
        return null;
    }
    function rememberedNative(d): bool {
        return !!d && (!!d.paired || !!d.bonded || !!d.trusted);
    }

    property var pendingActions: ({})
    Timer { id: pendingTimeout; interval: 20000; repeat: false; onTriggered: root.pendingActions = ({}); }
    function actionFor(address: string): string {
        try {
            return Bt.pendingAction(root.pendingActions, ((address || "").trim().toUpperCase()));
        } catch (e) {
            return "";
        }
    }
    function setPendingAction(address: string, action: string): void {
        let k = ((address || "").trim().toUpperCase());
        if (k === "")
            return;
        root.pendingActions = Bt.withPendingAction(root.pendingActions, k, action);
        if (action)
            pendingTimeout.restart();
    }
    // Tracks pair->connect handoff so a failed connect isn't retried forever.
    property var _pairConnected: ({})

    // Agent-backed pair pipeline (single flight + one queued). Native
    // pair() has no BlueZ agent behind it, so it fails for anything but
    // the trivial case; the piped bluetoothctl session registers
    // NoInputNoOutput, pairs, trusts and connects in one go.
    property string _pairAddr: ""
    property string _pairQueued: ""
    Process {
        id: pairProc
        stdout: StdioCollector {
            onStreamFinished: finishPair(text || "")
        }
    }
    function pairPipeline(address: string): void {
        // Shell-safe: escMac allow-lists hex + colons only.
        let m = escMac(address);
        if (m === "")
            return;
        root.clearError();
        setPendingAction(m, "connecting");
        if (pairProc.running) {
            root._pairQueued = m;
            return;
        }
        root._pairAddr = m;
        pairProc.command = ["bash", "-c", "printf 'agent NoInputNoOutput\\ndefault-agent\\npairable on\\npair " + m + "\\ntrust " + m + "\\nconnect " + m + "\\nquit\\n' | timeout 25 bluetoothctl 2>&1; echo done:$?"];
        pairProc.running = true;
    }
    // Pair-Fehlerstichworte (ein Array statt 7x verkettetem indexOf).
    readonly property var _pairFailures: [
        "failed to pair", "authentication failed", "not available",
        "no default controller", "failed to connect",
        "connection attempt failed", "not connected"
    ]
    function pairFailureOf(line: string): string {
        const low = line.toLowerCase()
        for (let i = 0; i < _pairFailures.length; i++) {
            if (low.indexOf(_pairFailures[i]) !== -1)
                return line.length > 90 ? line.slice(0, 90) + "…" : line
        }
        return ""
    }
    function finishPair(out: string): void {
        let addr = root._pairAddr;
        root._pairAddr = "";
        let fail = "";
        try {
            for (let raw of out.split("\n")) {
                let l = (raw || "").replace(/\x1b\[[0-9;]*m/g, "").trim();
                if (l.length === 0 || l === "done" || l.indexOf("done:") === 0)
                    continue;
                fail = pairFailureOf(l);
                if (fail !== "") break;
            }
        } catch (e) {}
        if (fail !== "")
            root.btLastError = fail;
        else if (root.btLastError !== "")
            root.btLastError = "";
        if (addr !== "")
            root.pendingActions = Bt.withPendingAction(root.pendingActions, addr, "");
        syncDevices();
        if (root._pairQueued !== "" && !pairProc.running) {
            let q = root._pairQueued;
            root._pairQueued = "";
            pairPipeline(q);
        }
    }

    function connectDevice(address: string): void {
        let dev = deviceByAddress(address);
        if (!dev || dev.connected)
            return;
        root.clearError();
        if (rememberedNative(dev)) {
            // Paired/trusted: plain connect needs no agent.
            setPendingAction(address, "connecting");
            try {
                dev.connect();
            } catch (e) {}
        } else {
            // New device: BlueZ pairing needs a registered agent, which the
            // native binding doesn't provide — use the bluetoothctl agent
            // pipeline (agent + pair + trust + connect), same as upstream's
            // helper did.
            pairPipeline(address);
        }
    }
    function disconnectDevice(address: string): void {
        let dev = deviceByAddress(address);
        if (!dev || !dev.connected)
            return;
        root.clearError();
        setPendingAction(address, "disconnecting");
        try {
            dev.disconnect();
        } catch (e) {}
    }
    function forgetDevice(address: string): void {
        let dev = deviceByAddress(address);
        if (!dev)
            return;
        root.clearError();
        // Block grace-cache resurrection for this address until BlueZ
        // confirms the removal (see syncPendingActions).
        _forgetBlock = Bt.cloneMap(_forgetBlock);
        _forgetBlock[((address || "").trim().toUpperCase())] = true;
        setPendingAction(address, "forgetting");
        try {
            // BlueZ refuses RemoveDevice on a connected device: drop the
            // link first, syncPendingActions() issues forget() once down.
            if (dev.connected)
                dev.disconnect();
            else
                dev.forget();
        } catch (e) {}
    }
    function syncPendingActions(): void {
        let next = null;
        try {
            for (var address in pendingActions) {
                let action = pendingActions[address];
                let found = deviceByAddress(address);
                if (action === "connecting" && found && found.connected) {
                    scheduleAudioOutputSwitch(found);
                    (next = next || Bt.cloneMap(pendingActions));
                    delete next[address];
                    _pairConnected = Bt.cloneMap(_pairConnected);
                    delete _pairConnected[address];
                } else if (action === "connecting" && found && !found.connected
                    && !found.pairing && rememberedNative(found) && !_pairConnected[address]) {
                    // Pair finished without connecting (native pair() only
                    // pairs) — follow up with connect exactly once.
                    _pairConnected = Bt.cloneMap(_pairConnected);
                    _pairConnected[address] = true;
                    try {
                        found.connect();
                    } catch (e) {}
                } else if (action === "disconnecting" && found && !found.connected) {
                    (next = next || Bt.cloneMap(pendingActions));
                    delete next[address];
                } else if (action === "forgetting" && found && found.connected) {
                    // Still linked (direct forget was refused) — keep
                    // dropping the link; forget() follows once down.
                    try {
                        found.disconnect();
                    } catch (e) {}
                } else if (action === "forgetting" && (!found || !rememberedNative(found))) {
                    (next = next || Bt.cloneMap(pendingActions));
                    delete next[address];
                    // BlueZ confirmed removal: drop grace entry + block so
                    // the row vanishes immediately instead of lingering.
                    _rowCache = Bt.cloneMap(_rowCache);
                    delete _rowCache[address];
                    _forgetBlock = Bt.cloneMap(_forgetBlock);
                    delete _forgetBlock[address];
                } else if (action === "forgetting" && found && !found.connected && rememberedNative(found)) {
                    try {
                        found.forget();
                    } catch (e) {}
                }
            }
        } catch (e) {}
        if (next)
            root.pendingActions = next;
    }

    // STABILITY: strict MAC validation — reject non-MAC input before any
    // shell/native use.
    function escMac(mac: string): string {
        let m = ((mac || "").trim().toUpperCase());
        if (!/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(m))
            return "";
        return m;
    }
    // ---- Pin for auto-reconnect (shared pin store) ----
    PersistentProperties {
        id: autoReconnectPins
        reloadableId: "solstice.bluetooth-autoreconnect"
        property var devices: []
    }
    readonly property var pinnedAddresses: autoReconnectPins.devices || []
    function isPinned(address: string): bool {
        return !!address && pinnedAddresses.indexOf(address) !== -1;
    }
    function togglePin(address: string): void {
        if (!address)
            return;
        let list = (pinnedAddresses || []).slice();
        let i = list.indexOf(address);
        if (i === -1)
            list.push(address);
        else
            list.splice(i, 1);
        autoReconnectPins.devices = list;
    }

    // ---- Background auto-reconnect watcher ----
    // Runs whether or not the panel is open. After sleep/resume no hook is
    // needed: the first poll after wake finds the device disconnected like
    // any other drop and retries it.
    property var _lastAttempt: ({})
    readonly property int _reconnectCooldownMs: 60000
    Timer {
        interval: 20000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: checkPinned()
    }
    function checkPinned(): void {
        if (root.adapter === null || !root.btActive)
            return;
        let pins = [];
        try {
            pins = (pinnedAddresses || []).slice();
        } catch (e) {
            return;
        }
        if (pins.length === 0)
            return;
        let now = Date.now();
        for (let i = 0; i < pins.length; i++) {
            let addr = pins[i];
            let dev = deviceByAddress(addr);
            // Unknown to BlueZ this session, or already connected: skip.
            if (!dev || dev.connected)
                continue;
            let last = _lastAttempt[addr] || 0;
            if (now - last < root._reconnectCooldownMs)
                continue;
            _lastAttempt = Bt.cloneMap(_lastAttempt);
            _lastAttempt[addr] = now;
            try {
                if (rememberedNative(dev))
                    dev.connect();
                // Unremembered pins can't reconnect — leave for the panel.
            } catch (e) {}
        }
    }

    // ---- Audio-output follow: route default sink to just-connected audio ----
    property var _pendingAudio: null
    property int _pendingAudioAttempts: 0
    Timer { id: audioSwitchTimer; interval: 500; repeat: false; onTriggered: switchPendingAudioOutput() }
    function scheduleAudioOutputSwitch(device): void {
        if (!device)
            return;
        root._pendingAudio = {
            address: device.address || "",
            name: device.name || "",
            deviceName: device.deviceName || ""
        };
        root._pendingAudioAttempts = 0;
        audioSwitchTimer.restart();
    }
    function switchPendingAudioOutput(): void {
        if (!root._pendingAudio)
            return;
        let sink = null;
        try {
            for (let n of (root.pipewireNodes || [])) {
                if (Bt.bluetoothSinkMatchesDevice(n, root._pendingAudio)) {
                    sink = n;
                    break;
                }
            }
        } catch (e) {}
        if (sink) {
            try {
                Pipewire.preferredDefaultAudioSink = sink;
            } catch (e) {}
            try {
                if (sink.id !== undefined)
                    Quickshell.execDetached(["wpctl", "set-default", String(sink.id)]);
            } catch (e) {}
            root._pendingAudio = null;
            audioSwitchTimer.stop();
            return;
        }
        root._pendingAudioAttempts += 1;
        if (root._pendingAudioAttempts >= 8)
            root._pendingAudio = null;
        else
            audioSwitchTimer.restart();
    }
}
