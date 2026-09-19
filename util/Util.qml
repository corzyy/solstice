pragma Singleton
import QtQuick
import Quickshell

QtObject {
    id: root

    function fileUrl(path: string): string {
        if (!path) return ""
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
    }

    // Icon-Name oder Glyphe? Menüeinträge tragen Nerd/MDI-Glyphen (PUA) im
    // `icon`-Feld; ungültige Namen würden pro Menü-Öffnung ~18
    // "Could not load icon"-Warnungen in den Icon-Loader spammen.
    // Theme-Namen sind ASCII — alles andere kann kein Icon-Name sein.
    function isGlyphIcon(value: string): bool {
        const s = String(value || "")
        return s.length > 0 && /[^\x20-\x7E]/.test(s)
    }

    // Warnungsfreie Icon-Quelle: Pfade passieren, Theme-Namen werden
    // aufgelöst, Glyphen/leere/unbekannte Namen ergeben `fallback`
    // (meist "" — IconImage bleibt leer wie bei fehlgeschlagenem Load).
    // Absolute Pfade werden als file:// URL zurückgegeben: ein roher
    // "/home/..."-String wird von Quickshell zu "qrc:/home/..." aufgelöst
    // und schlägt fehl (WebApp-.desktop-Dateien nutzen absolute Icon=).
    function iconSource(icon: var, fallback: string): string {
        const s = String(icon || "").trim()
        if (s.length === 0 || isGlyphIcon(s)) return fallback || ""
        if (s[0] === "/") return fileUrl(s)
        if (s.indexOf("file://") === 0 || s.indexOf("image://") === 0 || s.indexOf("qrc:") === 0) return s
        try {
            if (Quickshell.hasThemeIcon(s)) return Quickshell.iconPath(s)
            const low = s.toLowerCase()
            if (low !== s && Quickshell.hasThemeIcon(low)) return Quickshell.iconPath(low)
        } catch (e) {}
        return fallback || ""
    }

    function shellEscapeDq(value: string): string {
        return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\$/g, "\\$").replace(/`/g, "\\`")
    }

    // Turn verbose PipeWire/ALSA descriptions into short human labels.
    // e.g. "Fractal Scape Dongle Analog Stereo" -> "Fractal Scape Dongle",
    // "TU116 High Definition Audio Controller Digital Stereo (HDMI)" -> "TU116 (HDMI)",
    // "Built-in Audio Analog Stereo" -> "Built-in Audio".
    // Handles EN + DE suffixes ("Analoges Stereo", "Digitales Stereo (HDMI)").
    function cleanAudioName(desc: string, nodeName: string): string {
        var s = String(desc || "").trim()
        var n = String(nodeName || "").trim()
        if (!s) s = n
        if (!s) return ""
        // Raw node name instead of a description (e.g. locale parse miss) — prettify it.
        if (/^alsa_(output|input)\./i.test(s) || /^bluez_/i.test(s)) {
            var pretty = prettifyAudioNodeName(s)
            if (pretty) return pretty
        }
        // Strip monitor prefix (EN/DE).
        s = s.replace(/^(Monitor\s+(of|von)\s+|Monitor:\s*)/i, "")
        var hasHdmi = /\bhdmi\b/i.test(s)
        var hasDisplayPort = /displayport/i.test(s)
        // Strip trailing profile/format suffixes. Loop since they can stack
        // ("Analog Stereo Duplex", "Mono Fallback", ...).
        var patterns = [
            /\s+digital(?:es)?\s+stereo\s*\(hdmi\)\s*$/i,
            /\s+digital(?:es)?\s+surround[^$]*$/i,
            /\s+analog(?:es)?\s+surround[^$]*$/i,
            /\s+analog(?:es)?\s+stereo\s*$/i,
            /\s+multichannel[^$]*$/i,
            /\s+duplex\s*$/i,
            /\s+stereo\s*$/i,
            /\s+mono(\s*fallback)?\s*$/i,
            /\s+fallback\s*$/i,
            /\s+output\s*$/i,
            /\s+input\s*$/i
        ]
        var prev = ""
        var guard = 0
        while (prev !== s && guard < 5) {
            prev = s
            for (var i = 0; i < patterns.length; i++) s = s.replace(patterns[i], "")
            guard++
        }
        // Shorten verbose controller phrases, keep the chip/model token.
        s = s.replace(/\bHigh\s+Definition\s+Audio\s+Controller\b/i, "")
        s = s.replace(/\bFamily\s+[0-9a-z\/\.]+\s+HD\s+Audio\s+Controller\b/i, "HD Audio")
        s = s.replace(/\s{2,}/g, " ").replace(/^[\s\-–—:;,.]+/, "").replace(/[\s\-–—:;,.]+$/, "").trim()
        // Deduplicate a repeated leading vendor word ("Fractal Fractal Scape" -> "Fractal Scape").
        s = s.replace(/^(\S+)\s+\1(\s+|$)/i, "$1$2")
        s = s.replace(/\s{2,}/g, " ").trim()
        // Re-add the connection tag when it was part of the stripped profile.
        if (hasHdmi && !/\bhdmi\b/i.test(s)) s = (s ? s + " " : "") + "(HDMI)"
        else if (hasDisplayPort && !/displayport/i.test(s)) s = (s ? s + " " : "") + "(DisplayPort)"
        s = s.trim()
        if (!s) {
            var fb = prettifyAudioNodeName(n)
            return fb || n
        }
        return s
    }

    // Fallback prettifier for raw PipeWire node names when no Description exists.
    // "alsa_output.usb-Fractal_Fractal_Scape_Dongle_000...-00.analog-stereo" -> "Fractal Scape Dongle"
    function prettifyAudioNodeName(nodeName: string): string {
        var s = String(nodeName || "").trim()
        if (!s) return ""
        s = s.replace(/^alsa_(output|input)\./i, "").replace(/^bluez_(output|input)\./i, "")
        // Drop trailing profile suffix ("analog-stereo", "hdmi-stereo", "mono-fallback", "a2dp-sink", ...).
        var dot = s.lastIndexOf(".")
        if (dot !== -1) {
            var tail = s.substring(dot + 1)
            if (/stereo|mono|surround|hdmi|displayport|duplex|a2dp|sco|fallback|output|input|iec958|multichannel/i.test(tail))
                s = s.substring(0, dot)
        }
        if (/^usb-/i.test(s)) {
            s = s.replace(/^usb-/i, "")
            s = s.replace(/\.monitor$/i, "")
            s = s.split("_").join(" ").split("-").join(" ")
            var parts = []
            var tokens = s.split(/\s+/)
            for (var i = 0; i < tokens.length; i++) {
                var t = tokens[i]
                if (!t) continue
                // Drop USB serials / bus ids ("00000000911AD59C0265", "00").
                if (/^[0-9a-f]{6,}$/i.test(t)) continue
                if (/^[0-9]+$/.test(t)) continue
                parts.push(t)
            }
            s = parts.join(" ")
            // Deduplicate repeated leading word ("Fractal Fractal Scape" -> "Fractal Scape").
            s = s.replace(/^(\S+)\s+\1(\s+|$)/i, "$1$2")
            s = s.replace(/\s{2,}/g, " ").trim()
            return s || String(nodeName || "").trim()
        }
        if (/^pci-/i.test(s)) {
            // No friendly name recoverable — keep bus + profile hint.
            var m = String(nodeName || "").match(/\.([^.]+)$/)
            var prof = m ? m[1].replace(/[-_]+/g, " ").trim() : ""
            if (/hdmi/i.test(prof)) return "HDMI Output"
            if (/displayport/i.test(prof)) return "DisplayPort Output"
            if (/analog/i.test(prof)) return "Built-in Audio"
            return prof ? prof.charAt(0).toUpperCase() + prof.slice(1) : s
        }
        return s.split("_").join(" ").replace(/\s{2,}/g, " ").trim() || String(nodeName || "").trim()
    }
}
