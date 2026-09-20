pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool netActive: true

    property bool wifiEnabled: true
    property string ssid: ""
    property int signal: 0
    property string activeType: ""

    Process {
        id: netPollProc
        command: ["bash", "-c", "state=$(nmcli -t -f STATE g 2>/dev/null | tr -d '\\n'); conn=$(nmcli -t -f NAME,DEVICE,STATE c show --active 2>/dev/null | grep ':activated' | head -1 | cut -d: -f1); echo \"$state|$conn\" | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = (text || "").trim().split("|")
                let state = (parts[0] || "").toLowerCase()
                let conn = (parts[1] || "").trim()
                root.netActive = state.includes("verbunden") || state.includes("connected") || conn.length > 0
            }
        }
    }
    // PERF: 60s poll (was 30s). linkProc runs `nmcli dev wifi` which wakes
    // the wifi driver + forks 3x nmcli; nothing here changes faster than
    // NetworkManager D-Bus signals consumers already observe on demand.
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { if (!netPollProc.running) netPollProc.running = true; if (!linkProc.running) linkProc.running = true } }

    Process {
        id: linkProc
        command: ["bash", "-c", "radio=$(nmcli -t -f WIFI g 2>/dev/null | tr -d '\\n'); act=$(nmcli -t -f NAME,TYPE,DEVICE c show --active 2>/dev/null | head -3); sig=$(nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null | grep '^\\*' | head -1 | cut -d: -f2 | tr -d '\\n'); echo \"$radio\"; echo \"$act\"; echo \"$sig\" | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = ((text || "").trim()).split("\n")
                let radio = ((lines[0] || "").trim()).toLowerCase()
                root.wifiEnabled = radio !== "disabled" && radio !== "deaktiviert"
                const found = findActiveConn(lines)
                if (root.ssid !== found.ssid) root.ssid = found.ssid
                if (root.activeType !== found.type) root.activeType = found.type
                // A connection seen here means the network is up; keeping the
                // stale false from a toggle-off would hide the bar/tile icon
                // for up to a minute (netActive otherwise only polled).
                if (found.type !== "" && !root.netActive) root.netActive = true
                let sig = parseInt((lines[lines.length - 1] || "").trim())
                sig = isNaN(sig) ? 0 : Math.max(0, Math.min(100, sig))
                if (root.signal !== sig) root.signal = sig
            }
        }
    }
    // Shell-Quoting für doppelte Anführungszeichen (ein Pfad statt 6x kopiert).
    function shellDq(s: string): string {
        return String(s || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
    }
    // Aktive Verbindung: erst WLAN, dann Ethernet (eine Schleife pro Typ
    // über die gleiche Zeilenmenge statt 2x kopierter Schleifen).
    function findActiveConn(lines: var): var {
        const rows = []
        for (let i = 1; i < lines.length - 1; i++) {
            const p = (lines[i] || "").split(":")
            if (p.length < 2) continue
            rows.push({ name: (p[0] || "").trim(), type: (p[1] || "").trim() })
        }
        const matchers = [
            { type: "wifi", keys: ["802-11-wireless", "wifi"] },
            { type: "ethernet", keys: ["802-3-ethernet", "ethernet"] }
        ]
        for (let m = 0; m < matchers.length; m++) {
            for (let r = 0; r < rows.length; r++) {
                const t = rows[r].type
                for (let k = 0; k < matchers[m].keys.length; k++) {
                    const key = matchers[m].keys[k]
                    if (t === key || (key.length > 4 && t.indexOf(key) === 0))
                        return { ssid: rows[r].name, type: matchers[m].type }
                }
            }
        }
        return { ssid: "", type: "" }
    }
    function refreshLink() { if (!linkProc.running) linkProc.running = true }

    function wifiIconFor(sig: int): string {
        if (sig >= 75) return "󰤨"
        if (sig >= 55) return "󰤥"
        if (sig >= 35) return "󰤢"
        if (sig > 0) return "󰤟"
        return "󰤯"
    }
    // Ethernet wins; a disabled Wi-Fi radio shows the off glyph even while
    // fresher link state is still in flight (toggle -> immediate icon).
    // Radio on but not connected shows the empty signal glyph, never the
    // off glyph, so on/off toggles always read as a state change.
    readonly property string icon: {
        if (activeType === "ethernet") return "󰈀"
        if (!wifiEnabled) return "󰤮"
        return !netActive ? "󰤯" : wifiIconFor(signal)
    }

    property var wifiNetworks: []
    property var ethernetConns: []
    Process {
        id: wifiListProc
        command: ["bash", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi 2>/dev/null | grep -v '^--' | while IFS=: read -r inuse ssid signal sec; do if [ -z \"$ssid\" ]; then continue; fi; if [ \"$ssid\" = \"--\" ]; then continue; fi; iu=$(echo \"$inuse\" | xargs); sig=$(echo \"$signal\" | xargs); ssec=$(echo \"$sec\" | xargs); if [ \"$iu\" = \"*\" ]; then active=yes; else active=no; fi; if [ -z \"$sig\" ]; then sig=0; fi; if [ -z \"$ssec\" ]; then ssec=\"--\"; fi; echo \"$active|$ssid|$sig|$ssec\"; done | sort -t'|' -k3 -nr | head -12"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (text || "").trim()
                if (out.length === 0) { root.wifiNetworks = []; return }
                let arr = []
                let seen = {}
                for (let l of out.split("\n")) {
                    let p = l.trim().split("|")
                    if (p.length < 2) continue
                    let active = (p[0] || "no").trim().toLowerCase() === "yes"
                    let s = (p[1] || "").trim()
                    if (s.length === 0 || seen[s]) continue
                    seen[s] = true
                    let sig = parseInt((p[2] || "0").trim()); if (isNaN(sig)) sig = 0
                    arr.push({ ssid: s, signal: Math.max(0, Math.min(100, sig)), security: (p[3] || "--").trim(), active: active })
                }
                arr.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
                root.wifiNetworks = arr
            }
        }
    }
    Process {
        id: ethListProc
        command: ["bash", "-c", "nmcli -t -f NAME,TYPE,STATE con show 2>/dev/null | grep -E ':802-3-ethernet|:ethernet' | while IFS=: read -r name type state; do if [ -z \"$name\" ]; then continue; fi; echo \"$name|$state\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (text || "").trim()
                if (out.length === 0) { root.ethernetConns = []; return }
                let arr = []
                for (let l of out.split("\n")) {
                    let p = l.trim().split("|")
                    if (p.length < 1 || (p[0] || "").trim().length === 0) continue
                    let st = (p[1] || "").toLowerCase()
                    arr.push({ name: (p[0] || "").trim(), active: st.indexOf("activated") !== -1 || st.indexOf("verbunden") !== -1 })
                }
                root.ethernetConns = arr
            }
        }
    }
    function refreshLists() { if (!wifiListProc.running) wifiListProc.running = true; if (!ethListProc.running) ethListProc.running = true }
    Process { id: wifiRescanProc; command: ["bash", "-c", "nmcli dev wifi rescan 2>/dev/null; echo done"] }
    // STABILITY: scan needs 3-5s to populate; immediate refreshLists showed
    // stale results. Delay to let the driver finish.
    Timer { id: rescanDelay; interval: 4000; repeat: false; onTriggered: refreshLists() }
    function rescan() { if (!wifiRescanProc.running) wifiRescanProc.running = true; rescanDelay.restart() }

    Process { id: netActProc; command: ["bash", "-c", "echo"]; stdout: StdioCollector { onStreamFinished: { root.pumpNetAct(); refreshDebounce.restart() } } }
    property var _netActPending: null
    // STABILITY: queue instead of drop. Overwriting command while running
    // silently lost the 2nd click (connect + immediate disconnect, etc).
    function runNetAct(cmd: string): void {
        if (netActProc.running) { _netActPending = cmd; return }
        netActProc.command = ["bash", "-c", cmd]
        netActProc.running = true
    }
    function pumpNetAct(): void {
        if (_netActPending === null || _netActPending === undefined) return
        let c = _netActPending
        _netActPending = null
        if (netActProc.running) { _netActPending = c; return }
        netActProc.command = ["bash", "-c", c]
        netActProc.running = true
    }
    // PERF: one refresh pass per action burst, not 4 procs per click.
    Timer {
        id: refreshDebounce
        interval: 1000; repeat: false
        onTriggered: { refreshLink(); refreshLists(); refreshDns() }
    }
    function setWifiEnabled(on: bool): void {
        // Optimistic: toggles (settings switch, control-center tile, bar
        // icon) must flip the moment they are clicked, not after the poll.
        // The refresh after the action corrects the state if nmcli failed.
        if (root.wifiEnabled !== on) root.wifiEnabled = on
        if (!on && root.activeType !== "ethernet") root.netActive = false
        runNetAct("nmcli radio wifi " + (on ? "on" : "off") + " 2>/dev/null; echo done")
    }
    function toggleWifi(): void { setWifiEnabled(!wifiEnabled) }
    function connectWifi(ssid: string, password: string): void {
        const s = shellDq(ssid)
        if ((password || "").length > 0) {
            const p = shellDq(password)
            runNetAct("nmcli dev wifi connect \"" + s + "\" password \"" + p + "\" 2>/dev/null || nmcli con up id \"" + s + "\" 2>/dev/null; echo done")
        } else {
            runNetAct("nmcli dev wifi connect \"" + s + "\" 2>/dev/null || nmcli con up id \"" + s + "\" 2>/dev/null; echo done")
        }
    }
    function disconnectWifi(): void { runNetAct("nmcli dev disconnect $(nmcli -t -f DEVICE,TYPE dev 2>/dev/null | grep ':wifi' | head -1 | cut -d: -f1) 2>/dev/null; echo done") }
    function forgetWifi(ssid: string): void {
        runNetAct("nmcli con delete id \"" + shellDq(ssid) + "\" 2>/dev/null; echo done")
    }
    function ethConnect(name: string): void {
        runNetAct("nmcli con up id \"" + shellDq(name) + "\" 2>/dev/null; echo done")
    }
    function ethDisconnect(name: string): void {
        runNetAct("nmcli con down id \"" + shellDq(name) + "\" 2>/dev/null; echo done")
    }

    property string activeConnName: ""
    property string activeConnUuid: ""
    property var dnsServers: []
    property string dnsMode: "auto"
    property bool dnsBusy: false
    readonly property var dnsPresets: ({
        "cloudflare": { v4: "1.1.1.1,1.0.0.1", v6: "2606:4700:4700::1111,2606:4700:4700::1001", mark: "1.1.1.1" },
        "google": { v4: "8.8.8.8,8.8.4.4", v6: "2001:4860:4860::8888,2001:4860:4860::8844", mark: "8.8.8.8" }
    })
    function dnsModeFor(dns4: string, ignoreAutoDns: string): string {
        let ign = (ignoreAutoDns || "").toLowerCase().trim()
        let d4 = (dns4 || "").trim()
        if ((ign === "no" || ign === "") && d4 === "") return "auto"
        for (let key of Object.keys(dnsPresets)) {
            if (d4.indexOf(dnsPresets[key].mark) !== -1) return key
        }
        return "custom"
    }
    Process {
        id: dnsProc
        command: ["bash", "-c",
            "dev=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep ':connected' | grep -v '^lo:' | head -1 | cut -d: -f1); "
            + "if [ -z \"$dev\" ]; then echo \"NAME=\"; echo \"UUID=\"; echo \"DNS4=\"; echo \"IGN4=\"; echo \"EFF=\"; exit 0; fi; "
            + "uuid=$(nmcli -t -f GENERAL.CON-UUID dev show \"$dev\" 2>/dev/null | head -1 | cut -d: -f2- | xargs); "
            + "name=$(nmcli -t -f GENERAL.CONNECTION dev show \"$dev\" 2>/dev/null | head -1 | cut -d: -f2- | xargs); "
            + "dns4=$(nmcli -t -f ipv4.dns con show \"$uuid\" 2>/dev/null | cut -d: -f2- | xargs); "
            + "ign4=$(nmcli -t -f ipv4.ignore-auto-dns con show \"$uuid\" 2>/dev/null | cut -d: -f2- | xargs); "
            + "eff=$(nmcli -t -f IP4.DNS,IP6.DNS dev show \"$dev\" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' | grep -v '^$' | paste -sd' ' -); "
            + "echo \"NAME=$name\"; echo \"UUID=$uuid\"; echo \"DNS4=$dns4\"; echo \"IGN4=$ign4\"; echo \"EFF=$eff\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let vals = { NAME: "", UUID: "", DNS4: "", IGN4: "", EFF: "" }
                for (let l of ((text || "").trim()).split("\n")) {
                    let i = l.indexOf("=")
                    if (i === -1) continue
                    let k = l.slice(0, i).trim()
                    if (k in vals) vals[k] = l.slice(i + 1).trim()
                }
                root.activeConnName = vals["NAME"]
                root.activeConnUuid = vals["UUID"]
                root.dnsServers = vals["EFF"].split(/[ ,]+/).filter(s => s.length > 0)
                root.dnsMode = root.dnsModeFor(vals["DNS4"], vals["IGN4"])
            }
        }
    }
    function refreshDns() { if (!dnsProc.running) dnsProc.running = true }
    Process {
        id: dnsActProc
        command: ["bash", "-c", "echo"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.dnsBusy = false
                refreshDns()
                refreshStats()
            }
        }
    }
    function setDnsPreset(mode: string): void {
        const uuid = shellDq(root.activeConnUuid)
        if (uuid === "" || root.dnsBusy) return
        let cmd = ""
        if (mode in dnsPresets) {
            let p = dnsPresets[mode]
            cmd = "nmcli con mod \"" + uuid + "\" ipv4.dns \"" + p.v4 + "\" ipv4.ignore-auto-dns yes"
                + " ipv6.dns \"" + p.v6 + "\" ipv6.ignore-auto-dns yes 2>/dev/null;"
                + " nmcli con up \"" + uuid + "\" 2>/dev/null; echo done"
        } else {
            cmd = "nmcli con mod \"" + uuid + "\" ipv4.dns \"\" ipv4.ignore-auto-dns no"
                + " ipv6.dns \"\" ipv6.ignore-auto-dns no 2>/dev/null;"
                + " nmcli con up \"" + uuid + "\" 2>/dev/null; echo done"
        }
        root.dnsBusy = true
        dnsActProc.command = ["bash", "-c", cmd]
        if (!dnsActProc.running) dnsActProc.running = true
    }

    property string ipAddr: ""
    property string gateway: ""
    property string rxBytes: ""
    property string txBytes: ""
    property string pingMs: ""
    Process {
        id: statsProc
        command: ["bash", "-c", "dev=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep ':connected' | head -1 | cut -d: -f1); ip=$(nmcli -t -f IP4.ADDRESS dev show \"$dev\" 2>/dev/null | head -1 | cut -d: -f2- | cut -d/ -f1); gw=$(nmcli -t -f IP4.GATEWAY dev show \"$dev\" 2>/dev/null | head -1 | cut -d: -f2-); rx=$(cat /sys/class/net/$dev/statistics/rx_bytes 2>/dev/null); tx=$(cat /sys/class/net/$dev/statistics/tx_bytes 2>/dev/null); ping=$(ping -c 1 -W 1 1.1.1.1 2>/dev/null | grep -oP 'time=\\K[\\d.]+' | head -1); echo \"$ip|$gw|$rx|$tx|$ping\" | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = ((text || "").trim()).split("|")
                root.ipAddr = (p[0] || "").trim()
                root.gateway = (p[1] || "").trim()
                root.rxBytes = root.fmtBytes((p[2] || "").trim())
                root.txBytes = root.fmtBytes((p[3] || "").trim())
                let ping = (p[4] || "").trim()
                root.pingMs = ping.length > 0 ? ping + " ms" : "--"
            }
        }
    }
    function fmtBytes(v: string): string {
        const n = parseFloat(v)
        if (isNaN(n) || n <= 0) return "--"
        const units = [
            [1073741824, "GB"],
            [1048576, "MB"],
            [1024, "KB"]
        ]
        for (let i = 0; i < units.length; i++) {
            if (n >= units[i][0]) return (Math.round(n / units[i][0] * 10) / 10) + " " + units[i][1]
        }
        return Math.round(n) + " B"
    }
    function refreshStats() { if (!statsProc.running) statsProc.running = true }
}
