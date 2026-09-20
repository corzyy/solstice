pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../style/themes"

// SettingsService — compositor-agnostic app settings (kitty, fish prompt,
// brightness). Window-manager look lives in UmbrielService.
Singleton {
    id: root

    property int kittyPadding: 10
    property real kittyFontSize: 12.0
    property real kittyOpacity: 1.0
    property string fishPrompt: "minimal"
    property int brightness: 100

    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/config/settings.json"
        watchChanges: true; blockLoading: true; printErrors: false
        onFileChanged: settingsReloadDebounce.restart()
        adapter: JsonAdapter {
            property int kittyPadding: 10
            property real kittyFontSize: 12.0
            property real kittyOpacity: 1.0
            property string fishPrompt: "minimal"
            property int brightness: 100
        }
    }

    function syncFromFile(): void {
        kittyPadding = clampInt(settingsFile.adapter.kittyPadding, 0, 40, 10)
        kittyFontSize = clampReal(settingsFile.adapter.kittyFontSize, 6, 32, 12)
        kittyOpacity = clampReal(settingsFile.adapter.kittyOpacity, 0.3, 1.0, 1.0)
        fishPrompt = (settingsFile.adapter.fishPrompt || "minimal") + ""
        brightness = clampInt(settingsFile.adapter.brightness, 5, 100, 100)
    }

    function clampInt(v, lo, hi, fb): int {
        let n = parseInt(v)
        if (isNaN(n)) return fb
        return Math.max(lo, Math.min(hi, Math.round(n)))
    }
    function clampReal(v, lo, hi, fb): real {
        let n = parseFloat(v)
        if (isNaN(n)) return fb
        return Math.max(lo, Math.min(hi, n))
    }
    // STABILITY + PERF: coalesce editor save bursts; debounce disk writes
    // and backend forks (slider drags used to write+fork per tick).
    Timer {
        id: settingsReloadDebounce
        interval: 250; repeat: false
        onTriggered: { try { settingsFile.reload() } catch (e) { } try { syncFromFile() } catch (e2) { } }
    }
    Timer {
        id: persistDebounce
        interval: 300; repeat: false
        onTriggered: { try { settingsFile.writeAdapter() } catch (e) { } pumpBackend() }
    }
    property var _backendPending: null
    function persist(): void { persistDebounce.restart() }

    Process {
        id: backendProc
        command: ["bash", "-c", "echo"]
        stdout: StdioCollector {}
        onExited: pumpBackend()
    }
    function runBackend(args: var): void {
        // Coalesce to latest — intermediate slider ticks are obsolete.
        _backendPending = args
        if (!backendProc.running && !persistDebounce.running) pumpBackend()
    }
    function pumpBackend(): void {
        if (_backendPending === null || _backendPending === undefined) return
        if (backendProc.running) return
        let args = _backendPending
        _backendPending = null
        let script = Quickshell.env("HOME") + "/.config/quickshell/solstice/backend/scripts/settings-apply.py"
        backendProc.command = ["python3", script].concat(args)
        backendProc.running = true
    }

    Component.onCompleted: Qt.callLater(() => { syncFromFile() })
    function refresh(): void { syncFromFile() }

    // Einziger Schreibpfad: clampen -> Property -> Adapter -> persistieren -> Backend.
    // (Vorher 5x kopiert für kitty/fish/brightness.)
    function applySetting(key: string, value: var, backend: var): void {
        settingsFile.adapter[key] = value
        root[key] = value
        persist()
        runBackend(backend)
    }

    function applyKittyPadding(v): void { const c = clampInt(v, 0, 40, kittyPadding); applySetting("kittyPadding", c, ["kitty", "padding=" + c]) }
    function applyKittyFont(v): void { const c = Math.round(clampReal(v, 6, 32, kittyFontSize) * 2) / 2; applySetting("kittyFontSize", c, ["kitty", "font_size=" + c]) }
    function applyKittyOpacity(v): void { const c = Math.round(clampReal(v, 0.3, 1.0, kittyOpacity) * 100) / 100; applySetting("kittyOpacity", c, ["kitty", "opacity=" + c]) }
    function applyFishPrompt(s): void { applySetting("fishPrompt", s, ["fish", "prompt=" + s]) }
    function applyBrightness(v): void { const c = clampInt(v, 5, 100, brightness); applySetting("brightness", c, ["brightness", "level=" + c]) }
}
