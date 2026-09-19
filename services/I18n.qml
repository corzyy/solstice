pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// I18n — the shell's language + region backend, deliberately tiny: one JS
// dictionary per language, no catalogs, no compiled resources. English
// source strings double as dictionary keys, so call sites are just
// `I18n.t("Shell language")`; a missing entry falls back to the key itself.
// Translating a surface = wrapping its strings in I18n.t(...), adding a
// language = one dictionary entry.
//
// `language` (shell UI) and `location` (formats) are independent and
// persisted in config/language.json. Both switch live: `t()` reads
// `language` and `formatLocale` reads `location` inside the callers'
// bindings, so QML re-evaluates them without a reload.
Singleton {
    id: root

    property string language: "en"
    property string location: "US"

    // ---- translations ----------------------------------------------------
    readonly property var strings: ({
        de: {
            "Language & Region": "Sprache & Region",
            "System language": "Systemsprache",
            "System-wide locale (LANG)": "Systemweites Gebietsschema (LANG)",
            "Shell language": "Shell-Sprache",
            "Language of menus and surfaces translated by the shell":
                "Sprache der vom Shell übersetzten Menüs und Oberflächen",
            "Active locale": "Aktives Gebietsschema",
            "Applies to applications started after your next login; the shell language switches immediately.":
                "Gilt für Anwendungen, die nach der nächsten Anmeldung gestartet werden; die Shell-Sprache wechselt sofort.",
            "Location": "Standort",
            "Date, time and number formats": "Datums-, Zeit- und Zahlenformate",
            "The location sets the system formats (LC_TIME, LC_NUMERIC, …) and the shell's calendar and clock formats immediately. Missing locales are generated on demand (authentication required).":
                "Der Standort setzt die Systemformate (LC_TIME, LC_NUMERIC, …) und sofort die Kalender- und Uhrformate der Shell. Fehlende Gebietsschemata werden bei Bedarf erzeugt (Authentifizierung erforderlich)."
        }
    })
    function t(s: string): string {
        const dict = root.strings[root.language]
        return dict && dict[s] !== undefined ? dict[s] : s
    }

    // ---- languages -------------------------------------------------------
    readonly property var languages: [
        { code: "en", name: "English" },
        { code: "de", name: "Deutsch" }
    ]
    readonly property var languageNames: root.languages.map(l => l.name)
    function languageName(code: string): string {
        for (let i = 0; i < root.languages.length; i++)
            if (root.languages[i].code === code) return root.languages[i].name
        return code
    }
    function setLanguage(code: string): void {
        if (code === root.language || !root.hasLanguage(code)) return
        root.language = code
        root.persist()
    }
    function setLanguageByName(name: string): void {
        for (let i = 0; i < root.languages.length; i++)
            if (root.languages[i].name === name) { root.setLanguage(root.languages[i].code); return }
    }
    function hasLanguage(code: string): bool {
        for (let i = 0; i < root.languages.length; i++)
            if (root.languages[i].code === code) return true
        return false
    }

    // ---- locations (format regions) -------------------------------------
    readonly property var locations: [
        { code: "US", name: "United States", locale: "en_US.UTF-8" },
        { code: "DE", name: "Germany", locale: "de_DE.UTF-8" }
    ]
    readonly property var locationNames: root.locations.map(l => l.name)
    function locationName(code: string): string {
        for (let i = 0; i < root.locations.length; i++)
            if (root.locations[i].code === code) return root.locations[i].name
        return code
    }
    function locationLocale(code: string): string {
        for (let i = 0; i < root.locations.length; i++)
            if (root.locations[i].code === code) return root.locations[i].locale
        return "en_US.UTF-8"
    }
    function setLocation(code: string): void {
        if (code === root.location) return
        let known = false
        for (let i = 0; i < root.locations.length; i++)
            if (root.locations[i].code === code) known = true
        if (!known) return
        root.location = code
        root.persist()
    }
    function setLocationByName(name: string): void {
        for (let i = 0; i < root.locations.length; i++)
            if (root.locations[i].name === name) { root.setLocation(root.locations[i].code); return }
    }
    // The settings page mirrors the system's LC_TIME into the shell so the
    // formats agree from the first visit on (without a second setting).
    function syncLocation(code: string): void {
        if (code !== "US" && code !== "DE") return
        if (root.location !== code) root.setLocation(code)
    }

    // ---- formatting ------------------------------------------------------
    // QLocale used by every date/number label that should follow Location.
    readonly property var formatLocale: Qt.locale(root.location === "DE" ? "de_DE" : "en_US")
    // QLocale::toString keeps the field order of the pattern, so order-
    // sensitive labels get a per-region pattern instead of a translated one.
    readonly property string monthDayFormat: root.location === "DE" ? "d. MMM" : "MMM d"
    readonly property string weekdayMonthDayFormat: root.location === "DE" ? "ddd, d. MMM" : "ddd, MMM d"

    // ---- persistence (config/language.json) ------------------------------
    FileView {
        id: languageFile
        path: Quickshell.env("HOME") + "/.config/quickshell/jhqs/config/language.json"
        watchChanges: true; blockLoading: true; printErrors: false
        onFileChanged: languageReloadDebounce.restart()
        adapter: JsonAdapter {
            property string language: "en"
            property string location: "US"
        }
    }
    // The initial FileView read is queued and can finish after
    // Component.onCompleted, so sync off adapter changes instead of the
    // construction order (bindings see both the first load and later edits).
    readonly property string storedLanguage: languageFile.adapter.language || ""
    readonly property string storedLocation: languageFile.adapter.location || ""
    onStoredLanguageChanged: root.syncFromFile()
    onStoredLocationChanged: root.syncFromFile()

    Timer {
        id: languageReloadDebounce
        interval: 250; repeat: false
        onTriggered: { try { languageFile.reload() } catch (e) { } }
    }
    function persist(): void {
        try {
            languageFile.adapter.language = root.language
            languageFile.adapter.location = root.location
            languageFile.writeAdapter()
        } catch (e) { }
    }
    function syncFromFile(): void {
        if (root.hasLanguage(root.storedLanguage) && root.language !== root.storedLanguage)
            root.language = root.storedLanguage
        if ((root.storedLocation === "US" || root.storedLocation === "DE") && root.location !== root.storedLocation)
            root.location = root.storedLocation
    }
}
