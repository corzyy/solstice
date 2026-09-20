pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../../style/themes"
import "../../../../backend/services"
import ".."

// Language & Region — system language and formats via systemd-localed
// (localectl), plus the shell's own language and format region, reachable
// from Setup. System changes land in /etc/locale.conf and apply to
// applications started after the next login (the polkit prompt comes from
// the shell's resident agent); the shell language and formats switch live
// through the small I18n backend.
NexusControls.PageBase {
    id: root
    title: I18n.t("Language & Region")

    // ---- state -----------------------------------------------------------
    property string sysLang: ""
    property string sysFormat: ""
    property string pendingLang: ""
    property string message: ""

    readonly property var systemLanguageNames: ["English", "Deutsch"]
    readonly property string languageCurrent: {
        if (root.pendingLang !== "") return root.pendingLang.startsWith("de") ? "Deutsch" : "English"
        if (root.sysLang.startsWith("de")) return "Deutsch"
        if (root.sysLang.startsWith("en")) return "English"
        return root.sysLang.length > 0 ? root.sysLang : "—"
    }
    readonly property string activeLocale: {
        if (root.sysLang.length === 0) return "—"
        return root.sysFormat.length > 0 && root.sysFormat !== root.sysLang
            ? root.sysLang + "  ·  " + root.sysFormat
            : root.sysLang
    }

    function normalizeLocale(loc: string, fb: string): string {
        if (loc.startsWith("de")) return "de_DE.UTF-8"
        if (loc.startsWith("en")) return "en_US.UTF-8"
        return fb
    }
    function regionOf(loc: string): string {
        if (loc.startsWith("de_DE")) return "DE"
        if (loc.startsWith("en_US")) return "US"
        return ""
    }
    // "System Locale: LANG=… / LC_TIME=…" block (localectl status, run with
    // LC_ALL=C below so the label is untranslated) -> { LANG: …, LC_TIME: … }.
    function parseLocale(text: string): var {
        const out = ({})
        const lines = (text || "").split("\n")
        let inBlock = false
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.indexOf("System Locale:") !== -1) inBlock = true
            else if (inBlock && line.trim().indexOf("=") === -1) inBlock = false
            if (!inBlock) continue
            const pairs = line.match(/[A-Z_]+=[^\s]+/g)
            if (!pairs) continue
            for (let j = 0; j < pairs.length; j++) {
                const eq = pairs[j].indexOf("=")
                out[pairs[j].slice(0, eq)] = pairs[j].slice(eq + 1)
            }
        }
        return out
    }

    function refreshStatus(): void {
        if (!statusProc.running) statusProc.running = true
    }
    // LANG from the language pick, formats from the shell's Location.
    function targetLocales(): var {
        const lang = root.pendingLang !== ""
            ? root.pendingLang
            : root.normalizeLocale(root.sysLang, "en_US.UTF-8")
        const fmt = I18n.locationLocale(I18n.location)
        return [lang, fmt]
    }
    function assignmentsFor(locs: var): string {
        return "LANG=" + locs[0] + " LC_TIME=" + locs[1] + " LC_NUMERIC=" + locs[1]
            + " LC_MONETARY=" + locs[1] + " LC_MEASUREMENT=" + locs[1]
    }
    function generationCommand(locs: var): string {
        const bases = []
        for (let i = 0; i < locs.length; i++) {
            const base = locs[i].split(".")[0]
            if (bases.indexOf(base) === -1) bases.push(base)
        }
        let cmd = ""
        for (let i = 0; i < bases.length; i++)
            cmd += "localedef -i " + bases[i] + " -f UTF-8 " + bases[i] + ".UTF-8 2>/dev/null; "
        return cmd
    }
    function pushLocale(): void {
        if (setProc.running || genProc.running) return
        root.message = ""
        setProc.command = ["bash", "-c",
            "LC_ALL=C localectl set-locale " + root.assignmentsFor(root.targetLocales())]
        setProc.running = true
    }
    function setSystemLanguage(name: string): void {
        if (name !== "English" && name !== "Deutsch") return
        root.pendingLang = name === "Deutsch" ? "de_DE.UTF-8" : "en_US.UTF-8"
        root.pushLocale()
    }
    function setLocation(name: string): void {
        I18n.setLocationByName(name)
        root.pushLocale()
    }

    Component.onCompleted: root.refreshStatus()
    onPageEntered: root.refreshStatus()

    // ---- processes -------------------------------------------------------
    Process {
        id: statusProc
        command: ["bash", "-c", "LC_ALL=C localectl status 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = root.parseLocale(text)
                root.sysLang = map["LC_ALL"] || map["LANG"] || ""
                root.sysFormat = map["LC_ALL"] || map["LC_TIME"] || map["LANG"] || ""
                I18n.syncLocation(root.regionOf(root.sysFormat))
            }
        }
    }
    Process {
        id: setProc
        command: ["localectl", "set-locale", "LANG=en_US.UTF-8"]
        stderr: StdioCollector {
            onStreamFinished: {
                const e = (text || "").trim()
                if (e.length > 0) root.message = e
            }
        }
        onExited: (code, status) => {
            // systemd-localed refuses locales that aren't generated yet
            // (e.g. en_US.UTF-8 on a Fedora box with only de_*). Generate
            // them and retry in one privileged command: pkexec prompts via
            // the shell's polkit agent, then localectl runs as root.
            if (code !== 0 && root.message.indexOf("not installed") !== -1) {
                const locs = root.targetLocales()
                root.message = ""
                genProc.command = ["pkexec", "bash", "-c",
                    root.generationCommand(locs)
                    + "LC_ALL=C localectl set-locale " + root.assignmentsFor(locs)]
                genProc.running = true
                return
            }
            // Clear the optimistic label either way: on success the refreshed
            // status matches it, on failure the dropdown snaps back.
            root.pendingLang = ""
            root.refreshStatus()
        }
    }
    Process {
        id: genProc
        command: ["pkexec", "bash", "-c", "true"]
        stderr: StdioCollector {
            onStreamFinished: {
                const e = (text || "").trim()
                if (e.length > 0) root.message = e
            }
        }
        onExited: (code, status) => {
            root.pendingLang = ""
            root.refreshStatus()
        }
    }

    // ---- language --------------------------------------------------------
    NexusControls.SectionHeader { first: true; text: "Language" }
    NexusControls.DropdownRow {
        first: true
        label: I18n.t("System language")
        subtext: I18n.t("System-wide locale (LANG)")
        options: root.systemLanguageNames
        current: root.languageCurrent
        onPicked: v => root.setSystemLanguage(v)
    }
    NexusControls.DropdownRow {
        label: I18n.t("Shell language")
        subtext: I18n.t("Language of menus and surfaces translated by the shell")
        options: I18n.languageNames
        current: I18n.languageName(I18n.language)
        onPicked: v => I18n.setLanguageByName(v)
    }
    NexusControls.InfoRow {
        last: true
        icon: "󰗊"
        label: I18n.t("Active locale")
        value: root.activeLocale
        valueMaxWidth: Math.round(width * 0.5)
    }
    NexusControls.Note {
        text: I18n.t("Applies to applications started after your next login; the shell language switches immediately.")
    }

    // ---- region ----------------------------------------------------------
    NexusControls.SectionHeader { text: "Region" }
    NexusControls.DropdownRow {
        first: true
        last: true
        label: I18n.t("Location")
        subtext: I18n.t("Date, time and number formats")
        options: I18n.locationNames
        current: I18n.locationName(I18n.location)
        onPicked: v => root.setLocation(v)
    }
    NexusControls.Note {
        visible: root.message.length > 0
        color: Theme.error
        text: root.message
    }
    NexusControls.Note {
        visible: root.message.length === 0
        text: I18n.t("The location sets the system formats (LC_TIME, LC_NUMERIC, …) and the shell's calendar and clock formats immediately. Missing locales are generated on demand (authentication required).")
    }
}
