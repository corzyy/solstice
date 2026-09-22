pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../../../style/themes"
import "../../../../style/ui" as Ui
import ".."

// Keybinds — one page for every shortcut, in three layers: the shell action
// catalog (launcher, power menu, settings, screenshot, lock, …) stays on top,
// followed by the curated Hyprland compositor groups and finally any remaining
// binds from the compositor bind files. Each row shows the effective chord
// and can be rebound in place: system compositor binds live in
// ~/.config/hypr/configs/binds/system.lua, user binds in
// binds/user.lua, and rows edit whichever file currently holds them.
//
// Holding a row captures the next chord. A Wayland shortcuts inhibitor
// (auto-activated by Hyprland when it advertises the protocol) keeps the
// compositor from consuming the keys we want to record; without it chords the
// compositor already binds fire instead of reaching the capture. Escape
// cancels, a single modifier is recorded on tap.
NexusControls.PageBase {
    id: root
    title: "Keybinds"
    // SettingsPanel's FloatingWindow; the shortcuts inhibitor is tied to it.
    property var hostWindow: null

    property var binds: []
    property string capturing: ""
    property string heldDisplay: ""
    property var heldModTokens: []
    property bool nonModSeen: false
    property int modsPressed: 0
    property bool busy: false
    property bool messageIsError: false
    property string message: ""

    readonly property string scriptPath: Quickshell.shellDir + "/backend/scripts/hyprland-keybinds.py"
    readonly property string appsScriptPath: Quickshell.shellDir + "/backend/scripts/apps-manage.py"
    // Resolved default terminal / browser / file manager (the same state the
    // Apps page edits). Their spawn actions get their own catalog group so
    // the rows read "Launch Terminal" instead of "spawn:kitty".
    property var defaultApps: ({})

    readonly property var shellCatalog: [
        { id: "launcher", label: "Launcher", subtext: "Open the app launcher", action: "spawn:solstice module launcher toggle" },
        { id: "power", label: "Power menu", subtext: "Lock, logout, restart, shut down", action: "spawn:solstice module power toggle" },
        { id: "settings", label: "Settings", subtext: "Toggle the settings window", action: "spawn:solstice module settings toggle" },
        { id: "screenshot", label: "Screenshot", subtext: "Region, window or fullscreen capture", action: "spawn:solstice module screenshot toggle" },
        { id: "lock", label: "Lock screen", subtext: "Lock the session", action: "spawn:solstice lock" },
        { id: "notificationcenter", label: "Notification center", subtext: "Toggle the notification center", action: "spawn:solstice module notificationcenter toggle" },
        { id: "systemtray", label: "System tray", subtext: "Toggle the system tray panel", action: "spawn:solstice module systemtray toggle" },
        { id: "reload", label: "Reload shell", subtext: "Restart Quickshell and apply config changes", action: "spawn:solstice reload" }
    ]
    // Default-application launchers (Apps > Default applications). Actions
    // follow the stored defaults, so switching the app there relabels the row
    // here. An unbound default still gets a row ("Not bound") so it can be
    // (re)bound without opening the Apps page first.
    readonly property var appCatalog: {
        const kinds = [
            { kind: "terminal", label: "Launch Terminal", subtext: "Default terminal" },
            { kind: "browser", label: "Launch Web Browser", subtext: "Default web browser" },
            { kind: "fileManager", label: "Launch File Manager", subtext: "Default file manager" }
        ]
        let out = []
        for (let i = 0; i < kinds.length; i++) {
            const d = root.defaultApps[kinds[i].kind]
            if (!d || !d.action) continue
            const app = String(d.name || d.command || "")
            out.push({
                group: "Applications",
                id: "app:" + kinds[i].kind,
                label: kinds[i].label,
                subtext: app.length > 0 ? kinds[i].subtext + " · " + app : kinds[i].subtext,
                action: d.action
            })
        }
        return out
    }
    // Curated useful Hyprland actions, grouped like the compositor cheatsheet.
    // Actions bound in binds/system.lua are edited there, user binds in
    // binds/user.lua, so every row round-trips to its own file.
    // Action ids resolve through backend/scripts/hyprland-keybinds.py
    // (ACTIONS): window/focus binds use the lua dispatcher forms, workspace
    // cycling and monitor moves go through `hyprctl dispatch`.
    readonly property var compositorCatalog: [
        { group: "Windows", id: "close", label: "Close window", subtext: "Close the focused window", action: "close" },
        { group: "Windows", id: "float", label: "Toggle floating", subtext: "Float or tile the focused window", action: "toggle-float" },
        { group: "Windows", id: "fullscreen", label: "Toggle fullscreen", subtext: "Fullscreen the focused window", action: "toggle-fullscreen" },
        { group: "Windows", id: "maximize", label: "Toggle maximize", subtext: "Maximize, keeping gaps and borders", action: "toggle-maximize" },
        { group: "Focus & layout", id: "focus-left", label: "Focus left", subtext: "Focus the window to the left", action: "focus-left" },
        { group: "Focus & layout", id: "focus-right", label: "Focus right", subtext: "Focus the window to the right", action: "focus-right" },
        { group: "Focus & layout", id: "focus-up", label: "Focus up", subtext: "Focus the window above", action: "focus-up" },
        { group: "Focus & layout", id: "focus-down", label: "Focus down", subtext: "Focus the window below", action: "focus-down" },
        { group: "Focus & layout", id: "move-left", label: "Move window left", subtext: "Move the focused window one position left", action: "move-left" },
        { group: "Focus & layout", id: "move-right", label: "Move window right", subtext: "Move the focused window one position right", action: "move-right" },
        { group: "Focus & layout", id: "move-up", label: "Move window up", subtext: "Move the window up", action: "move-up" },
        { group: "Focus & layout", id: "move-down", label: "Move window down", subtext: "Move the window down", action: "move-down" },
        { group: "Focus & layout", id: "layout-toggle", label: "Toggle layout", subtext: "Switch the tiling layout (master / dwindle / scrolling)", action: "layout-toggle" },
        { group: "Workspaces", id: "ws-next", label: "Next workspace", subtext: "Switch to the next workspace", action: "ws-next" },
        { group: "Workspaces", id: "ws-prev", label: "Previous workspace", subtext: "Switch to the previous workspace", action: "ws-prev" },
        { group: "Workspaces", id: "ws-move-next", label: "Move window to next workspace", subtext: "Take the focused window along", action: "ws-move-next" },
        { group: "Workspaces", id: "ws-move-prev", label: "Move window to previous workspace", subtext: "Take the focused window along", action: "ws-move-prev" },
        { group: "Special", id: "scratchpad", label: "Toggle scratchpad", subtext: "Special workspace", action: "scratchpad" },
        { group: "Outputs", id: "out-left", label: "Focus monitor left", subtext: "Focus the monitor to the left", action: "out-left" },
        { group: "Outputs", id: "out-right", label: "Focus monitor right", subtext: "Focus the monitor to the right", action: "out-right" },
        { group: "Outputs", id: "out-move-left", label: "Move window to monitor left", subtext: "Send the focused window to the left monitor", action: "out-move-left" },
        { group: "Outputs", id: "out-move-right", label: "Move window to monitor right", subtext: "Send the focused window to the right monitor", action: "out-move-right" },
        { group: "Media & brightness", id: "vol-up", label: "Volume up", subtext: "Raise the default sink volume", action: "spawn:wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+" },
        { group: "Media & brightness", id: "vol-down", label: "Volume down", subtext: "Lower the default sink volume", action: "spawn:wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" },
        { group: "Media & brightness", id: "vol-mute", label: "Mute output", subtext: "Toggle sink mute", action: "spawn:wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" },
        { group: "Media & brightness", id: "mic-mute", label: "Mute microphone", subtext: "Toggle source mute", action: "spawn:wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" },
        { group: "Media & brightness", id: "bright-up", label: "Brightness up", subtext: "Raise the screen brightness", action: "spawn:brightnessctl -e4 -n2 set 5%+" },
        { group: "Media & brightness", id: "bright-down", label: "Brightness down", subtext: "Lower the screen brightness", action: "spawn:brightnessctl -e4 -n2 set 5%-" },
        { group: "Media & brightness", id: "player-play", label: "Play / pause", subtext: "Toggle media playback", action: "spawn:playerctl play-pause" },
        { group: "Media & brightness", id: "player-next", label: "Next track", subtext: "Skip to the next track", action: "spawn:playerctl next" },
        { group: "Media & brightness", id: "player-prev", label: "Previous track", subtext: "Go back one track", action: "spawn:playerctl previous" },
        { group: "Session", id: "config-reload", label: "Reload compositor config", subtext: "Re-read the Hyprland config files", action: "spawn:hyprctl reload" },
        { group: "Session", id: "quit", label: "Quit session", subtext: "Exit Hyprland", action: "quit" }
    ]
    // Actions kept off the page (the config bind stays active).
    readonly property var hiddenActions: ["spawn:opencode"]
    // Shell actions first, then the default-application launchers and the
    // compositor groups, then every remaining effective bind in the
    // compositor files so nothing in binds/system.lua/user.lua is unreachable.
    // Shell spawns are covered by the shell catalog, app launchers by the
    // app catalog, and both are excluded from "Other binds".
    readonly property var catalog: {
        let base = root.shellCatalog.concat(root.appCatalog, root.compositorCatalog)
        const known = {}
        for (let i = 0; i < base.length; ++i) known[base[i].action] = true
        const binds = root.binds
        const seen = {}
        let other = []
        for (let i = 0; i < binds.length; ++i) {
            const bind = binds[i]
            const action = bind.action
            if (known[action] === true || seen[action] === true) continue
            seen[action] = true
            if (action.indexOf("spawn:solstice") === 0
                    || root.hiddenActions.indexOf(action) !== -1) continue
            let label = bind.description || ""
            let subtext = action
            if (label.length === 0 && action.indexOf("spawn:") === 0) {
                label = action.slice(6)
                subtext = "Launch command"
            } else if (label.length === 0) {
                label = action
                subtext = ""
            }
            other.push({
                group: "Other binds",
                id: "action:" + action,
                label: label,
                subtext: subtext,
                action: action
            })
        }
        return base.concat(other)
    }

    readonly property var rows: {
        let out = []
        const catalog = root.catalog
        const binds = root.binds
        for (let i = 0; i < catalog.length; ++i) {
            const entry = catalog[i]
            const hits = root.matchesFor(entry.action)
            let display = ""
            let source = ""
            for (let j = 0; j < hits.length; ++j) {
                display += (j > 0 ? " · " : "") + hits[j].display
                source = hits[j].source
            }
            out.push({
                id: entry.id,
                label: entry.label,
                subtext: entry.subtext,
                action: entry.action,
                group: entry.group || "Shell actions",
                bound: hits.length > 0,
                display: display,
                source: source,
                first: false,
                last: false
            })
        }
        return out
    }
    readonly property var rowGroups: {
        let groups = []
        const rows = root.rows
        for (let i = 0; i < rows.length; ++i) {
            const row = rows[i]
            let group = null
            for (let j = 0; j < groups.length; ++j) {
                if (groups[j].title === row.group) { group = groups[j]; break }
            }
            if (group === null) {
                group = { title: row.group, rows: [] }
                groups.push(group)
            }
            row.first = group.rows.length === 0
            if (group.rows.length > 0) group.rows[group.rows.length - 1].last = false
            row.last = true
            group.rows.push(row)
        }
        return groups
    }

    function matchesFor(action: string): var {
        let out = []
        const binds = root.binds
        for (let i = 0; i < binds.length; ++i)
            if (binds[i].action === action) out.push(binds[i])
        return out
    }
    function editSourceFor(action: string): string {
        let source = ""
        const binds = root.binds
        for (let i = 0; i < binds.length; ++i)
            if (binds[i].action === action) source = binds[i].source
        return source
    }

    function catalogFor(id: string): var {
        const catalog = root.catalog
        for (let i = 0; i < catalog.length; ++i) if (catalog[i].id === id) return catalog[i]
        return null
    }
    function setMessage(text: string, isError: bool): void {
        root.message = text || ""
        root.messageIsError = !!isError
    }
    function refresh(): void {
        if (!listProc.running) listProc.running = true
        if (!defaultsProc.running) defaultsProc.running = true
    }

    // ---- capture ---------------------------------------------------------
    function startCapture(actionId: string): void {
        if (root.busy) return
        root.capturing = actionId
        root.heldModTokens = []
        root.heldDisplay = ""
        root.nonModSeen = false
        root.modsPressed = 0
        root.setMessage("Press a chord to bind. Esc cancels.", false)
        Qt.callLater(() => root.forceActiveFocus())
    }
    function cancelCapture(): void {
        if (root.capturing === "") return
        root.capturing = ""
        root.heldModTokens = []
        root.heldDisplay = ""
    }
    function updateHeldDisplay(): void {
        root.heldDisplay = root.heldModTokens.length > 0
            ? root.heldModTokens.join(" + ") + " + …" : ""
    }
    function applyBind(action: string, chord: string, file: string): void {
        if (root.busy) return
        root.busy = true
        root.setMessage("Applying " + chord + "…", false)
        let cmd = ["python3", root.scriptPath, "set", action, chord]
        if (file !== undefined && file.length > 0) cmd = cmd.concat(["--file", file])
        editProc.command = cmd.concat(["--json"])
        if (!editProc.running) editProc.running = true
    }
    function unbindAction(actionId: string): void {
        const entry = root.catalogFor(actionId)
        if (entry === null || root.busy) return
        root.busy = true
        root.setMessage("Removing bind…", false)
        let cmd = ["python3", root.scriptPath, "unbind", entry.action]
        const file = root.editSourceFor(entry.action)
        if (file.length > 0) cmd = cmd.concat(["--file", file])
        editProc.command = cmd.concat(["--json"])
        if (!editProc.running) editProc.running = true
    }
    function finishCapture(chord: string): void {
        const actionId = root.capturing
        root.cancelCapture()
        const entry = root.catalogFor(actionId)
        if (entry === null) return
        const hits = root.matchesFor(entry.action)
        for (let i = 0; i < hits.length; ++i) {
            if (hits[i].chord === chord) {
                root.setMessage("Already bound to " + hits[i].display + ".", false)
                return
            }
        }
        root.applyBind(entry.action, chord, root.editSourceFor(entry.action))
    }

    // ---- Qt key -> Hyprland chord --------------------------------------
    // Chords use Hyprland key names ("SUPER + Space", "XF86AudioMute").
    // Shifted symbols map back to the base key so the stored chord reads
    // "SUPER + Shift + 1".
    function modifierName(key: int): string {
        if (key === Qt.Key_Shift) return "Shift"
        if (key === Qt.Key_Control) return "Ctrl"
        if (key === Qt.Key_Alt) return "Alt"
        if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R
                || key === Qt.Key_Hyper_L || key === Qt.Key_Hyper_R) return "SUPER"
        return ""
    }
    function chordFor(event): string {
        let mods = []
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl")
        if (event.modifiers & Qt.AltModifier) mods.push("Alt")
        if (event.modifiers & Qt.ShiftModifier) mods.push("Shift")
        mods.push(root.keyToken(event))
        return mods.join("+")
    }
    function keyToken(event): string {
        const k = event.key
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35) return "F" + (k - Qt.Key_F1 + 1)
        switch (k) {
        case Qt.Key_Space: return "Space"
        case Qt.Key_Comma: case Qt.Key_Less: return "Comma"
        case Qt.Key_Period: case Qt.Key_Greater: return "Period"
        case Qt.Key_Slash: case Qt.Key_Question: return "Slash"
        case Qt.Key_Semicolon: case Qt.Key_Colon: return "Semicolon"
        case Qt.Key_Apostrophe: case Qt.Key_QuoteDbl: return "Apostrophe"
        case Qt.Key_BracketLeft: case Qt.Key_BraceLeft: return "BracketLeft"
        case Qt.Key_BracketRight: case Qt.Key_BraceRight: return "BracketRight"
        case Qt.Key_Backslash: case Qt.Key_Bar: return "Backslash"
        case Qt.Key_Minus: case Qt.Key_Underscore: return "Minus"
        case Qt.Key_Equal: case Qt.Key_Plus: return "Equal"
        case Qt.Key_QuoteLeft: case Qt.Key_AsciiTilde: return "Grave"
        case Qt.Key_Exclam: return "1"
        case Qt.Key_At: return "2"
        case Qt.Key_NumberSign: return "3"
        case Qt.Key_Dollar: return "4"
        case Qt.Key_Percent: return "5"
        case Qt.Key_AsciiCircum: return "6"
        case Qt.Key_Ampersand: return "7"
        case Qt.Key_Asterisk: return "8"
        case Qt.Key_ParenLeft: return "9"
        case Qt.Key_ParenRight: return "0"
        case Qt.Key_Escape: return "Escape"
        case Qt.Key_Tab: case Qt.Key_Backtab: return "Tab"
        case Qt.Key_Backspace: return "BackSpace"
        case Qt.Key_Return: return "Return"
        case Qt.Key_Enter: return "KP_Enter"
        case Qt.Key_Insert: return "Insert"
        case Qt.Key_Delete: return "Delete"
        case Qt.Key_Home: return "Home"
        case Qt.Key_End: return "End"
        case Qt.Key_PageUp: return "Page_Up"
        case Qt.Key_PageDown: return "Page_Down"
        case Qt.Key_Left: return "Left"
        case Qt.Key_Up: return "Up"
        case Qt.Key_Right: return "Right"
        case Qt.Key_Down: return "Down"
        case Qt.Key_Print: return "Print"
        case Qt.Key_Pause: return "Pause"
        case Qt.Key_Menu: return "Menu"
        case Qt.Key_ScrollLock: return "Scroll_Lock"
        case Qt.Key_NumLock: return "Num_Lock"
        case Qt.Key_CapsLock: return "Caps_Lock"
        case Qt.Key_VolumeMute: return "XF86AudioMute"
        case Qt.Key_VolumeDown: return "XF86AudioLowerVolume"
        case Qt.Key_VolumeUp: return "XF86AudioRaiseVolume"
        case Qt.Key_MediaPlay: case Qt.Key_MediaTogglePlayPause: return "XF86AudioPlay"
        case Qt.Key_MediaStop: return "XF86AudioStop"
        case Qt.Key_MediaPrevious: return "XF86AudioPrev"
        case Qt.Key_MediaNext: return "XF86AudioNext"
        case Qt.Key_MediaPause: return "XF86AudioPause"
        case Qt.Key_MediaRecord: return "XF86AudioRecord"
        case Qt.Key_AudioRewind: return "XF86AudioRewind"
        case Qt.Key_AudioForward: return "XF86AudioForward"
        case Qt.Key_MonBrightnessUp: return "XF86MonBrightnessUp"
        case Qt.Key_MonBrightnessDown: return "XF86MonBrightnessDown"
        case Qt.Key_KeyboardBrightnessUp: return "XF86KbdBrightnessUp"
        case Qt.Key_KeyboardBrightnessDown: return "XF86KbdBrightnessDown"
        case Qt.Key_Sleep: return "XF86Sleep"
        case Qt.Key_WakeUp: return "XF86WakeUp"
        case Qt.Key_PowerDown: return "XF86PowerDown"
        case Qt.Key_Standby: return "XF86Standby"
        case Qt.Key_HomePage: return "XF86HomePage"
        case Qt.Key_LaunchMail: return "XF86Mail"
        case Qt.Key_LaunchMedia: return "XF86AudioMedia"
        case Qt.Key_Search: return "XF86Search"
        case Qt.Key_Favorites: return "XF86Favorites"
        case Qt.Key_Refresh: return "XF86Refresh"
        case Qt.Key_Stop: return "XF86Stop"
        case Qt.Key_Back: return "XF86Back"
        case Qt.Key_Forward: return "XF86Forward"
        }
        const text = event.text
        if (text && text.length === 1) {
            if (text >= "a" && text <= "z") return text.toUpperCase()
            if (text >= "0" && text <= "9") return text
        }
        return ""
    }

    function handleKeyPressed(event): void {
        if (root.capturing === "") return
        event.accepted = true
        if (event.isAutoRepeat) return
        const mod = root.modifierName(event.key)
        if (mod !== "") {
            if (root.heldModTokens.indexOf(mod) < 0)
                root.heldModTokens = root.heldModTokens.concat([mod])
            root.modsPressed = Math.max(root.modsPressed, root.heldModTokens.length)
            root.updateHeldDisplay()
            return
        }
        if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
            root.cancelCapture()
            root.setMessage("Capture cancelled.", false)
            return
        }
        const token = root.keyToken(event)
        if (token === "") {
            root.setMessage("That key cannot be bound. Esc cancels.", true)
            return
        }
        root.nonModSeen = true
        root.finishCapture(root.chordFor(event))
    }
    function handleKeyReleased(event): void {
        if (root.capturing === "") return
        event.accepted = true
        const mod = root.modifierName(event.key)
        if (mod === "") return
        const at = root.heldModTokens.indexOf(mod)
        if (at >= 0)
            root.heldModTokens = root.heldModTokens.slice(0, at).concat(root.heldModTokens.slice(at + 1))
        root.updateHeldDisplay()
        if (!root.nonModSeen && root.heldModTokens.length === 0 && root.modsPressed === 1) {
            root.finishCapture(mod)
            return
        }
        if (root.heldModTokens.length === 0) root.modsPressed = 0
    }

    focus: root.capturing !== ""
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => root.handleKeyPressed(event)
    Keys.onReleased: event => root.handleKeyReleased(event)

    onPageEntered: root.refresh()
    Component.onCompleted: root.refresh()

    ShortcutInhibitor {
        id: inhibitor
        enabled: root.capturing !== "" && root.hostWindow !== null
        window: root.hostWindow
        onCancelled: {
            root.cancelCapture()
            root.setMessage("The compositor cancelled the key capture.", true)
        }
    }

    Process {
        id: listProc
        command: ["python3", root.scriptPath, "list", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text || "[]")
                    root.binds = Array.isArray(parsed) ? parsed : []
                } catch (e) {
                    root.binds = []
                    root.setMessage("Could not read the Hyprland binds.", true)
                }
            }
        }
    }
    Process {
        id: defaultsProc
        command: ["python3", root.appsScriptPath, "defaults", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let parsed = null
                try { parsed = JSON.parse(text || "{}") } catch (e) {}
                if (parsed && parsed.ok) root.defaultApps = parsed.defaults || ({})
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }
    Process {
        id: editProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let res = null
                try { res = JSON.parse(text || "{}") } catch (e) {}
                if (res !== null && res.ok) root.setMessage(res.message || "Saved.", false)
                else root.setMessage((res && res.message) || "Could not update the keybind.", true)
                root.refresh()
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { root.busy = false }
    }

    // ---- UI --------------------------------------------------------------
    Repeater {
        model: root.rowGroups
        delegate: Column {
            id: groupColumn
            required property var modelData
            required property int index
            width: parent ? parent.width : 300
            NexusControls.SectionHeader {
                first: groupColumn.index === 0
                width: parent.width
                text: groupColumn.modelData.title
            }
            Repeater {
                model: groupColumn.modelData.rows
                delegate: KeyRow {
                    required property var modelData
                    rowData: modelData
                    first: modelData.first
                    last: modelData.last
                    capturing: root.capturing === modelData.id
                    heldDisplay: root.heldDisplay
                    busy: root.busy
                    onRebindRequested: root.capturing === modelData.id
                        ? root.cancelCapture() : root.startCapture(modelData.id)
                    onClearRequested: root.unbindAction(modelData.id)
                }
            }
        }
    }

    Text {
        visible: root.message.length > 0
        width: parent.width
        leftPadding: 8
        rightPadding: 8
        topPadding: 12
        bottomPadding: 4
        wrapMode: Text.WordWrap
        text: root.message
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(11)
        color: root.messageIsError ? Theme.error : Theme.accent
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }
    NexusControls.Note {
        text: "Rebinding replaces the chord on its line in binds/system.lua (compositor defaults) or ~/.config/hypr/configs/binds/user.lua (your binds) — comments are kept — and reloads Hyprland. “SUPER” is the Super key."
    }

    // KeyRow = InfoRow shape with a key cap + clear button. The delegate wires
    // capture/cancel and the page's live held-modifier display.
    component KeyRow: Rectangle {
        id: row
        property var rowData: null
        property bool first: false
        property bool last: false
        property bool capturing: false
        property string heldDisplay: ""
        property bool busy: false
        readonly property bool bound: rowData !== null && rowData.bound
        readonly property string display: rowData !== null ? rowData.display : ""
        signal rebindRequested()
        signal clearRequested()

        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: content.implicitHeight + 24
        height: implicitHeight
        color: Theme.panelCard
        topLeftRadius: first ? 28 : 4
        topRightRadius: first ? 28 : 4
        bottomLeftRadius: last ? 28 : 4
        bottomRightRadius: last ? 28 : 4

        Ui.StateLayer {
            radius: 28
            showHoverBackground: false
            color: Theme.textPrimary
            disabled: row.busy
            onClicked: row.rebindRequested()
        }

        Row {
            id: content
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12

            Column {
                width: Math.max(0, parent.width - cap.width - clearButton.width - 24)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: row.rowData !== null ? row.rowData.label : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: row.rowData !== null && row.rowData.subtext.length > 0
                    text: row.rowData !== null ? row.rowData.subtext : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }

            Rectangle {
                id: cap
                anchors.verticalCenter: parent.verticalCenter
                height: 32
                width: Math.max(76, capText.implicitWidth + 24)
                radius: 10
                color: row.capturing ? Theme.secondary_container : Theme.panelCardHighest
                border.color: row.capturing ? Theme.accent : "transparent"
                border.width: row.capturing ? 2 : 0
                antialiasing: Theme.shapesAa
                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects }
                }
                Text {
                    id: capText
                    anchors.centerIn: parent
                    text: row.capturing
                        ? (row.heldDisplay.length > 0 ? row.heldDisplay : "Press a key…")
                        : (row.bound ? row.display : "Not bound")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: row.capturing
                        ? Theme.on_secondary_container
                        : (row.bound ? Theme.textPrimary : Theme.textMuted)
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }

            Rectangle {
                id: clearButton
                visible: row.bound && !row.capturing
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: Theme.panelCardHighest
                antialiasing: Theme.shapesAa
                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(14)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Ui.StateLayer {
                    radius: 16
                    color: Theme.error
                    disabled: row.busy
                    onClicked: row.clearRequested()
                }
            }
        }
    }
}
