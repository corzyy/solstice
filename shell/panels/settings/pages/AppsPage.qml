pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../../../style/themes"
import "../../../../style/ui" as Ui
import ".."

// Apps — default applications and the app library.
//
// "Default applications" binds the terminal / browser / file manager to the
// matching Hyprland spawn bind. Picking an app runs
// backend/scripts/apps-manage.py, which rebinds the chord the previous
// command held (config-reload included, so the shortcut changes live) and
// remembers the selection in backend/config/default_apps.json.
//
// "Library" holds "All apps" (every app the launcher would show, with one
// shared detail page bound to selectedAppId, no per-app instance: open, hide
// from the launcher via launcher.json hiddenApps, or uninstall) and "App
// Theming" (the matugen template browser, see AppThemingPage).
NexusControls.PageBase {
    id: root
    title: "Apps"
    showTitle: root.view === ""

    // Sub-view state: "" (overview), "library" (all apps), "detail",
    // "theming" (App Theming).
    property string view: ""
    property string selectedAppId: ""
    property string searchText: ""
    property string statusText: ""
    property bool statusIsError: false
    property var defaults: ({})
    property var appInfo: ({})
    property bool infoFailed: false
    property bool confirmUninstall: false
    property bool uninstalling: false
    property string pendingKind: ""
    property string pendingLabel: ""

    readonly property string scriptPath: Quickshell.shellDir + "/backend/scripts/apps-manage.py"

    readonly property var defaultKinds: [
        { kind: "terminal", label: "Terminal", icon: "󰆍", tint: Theme.primary, category: "TerminalEmulator" },
        { kind: "browser", label: "Web Browser", icon: "󰖟", tint: Theme.primary, category: "WebBrowser" },
        { kind: "fileManager", label: "File Manager", icon: "󰉋", tint: Theme.tertiary, category: "FileManager" }
    ]

    // ---- app model -------------------------------------------------------
    // Same set as the launcher: readable entries, no helper daemons. Hidden
    // apps stay in the library (that is where they get unhidden).
    readonly property var libraryApps: {
        Theme.appsRev
        let out = []
        try {
            let model = DesktopEntries.applications
            if (!model) return out
            let vals = model.values
            if (typeof vals === "function") vals = vals()
            if (!vals) return out
            let seen = ({})
            for (let i = 0; i < vals.length; i++) {
                let e = vals[i]
                if (!e || e.noDisplay === true) continue
                let id = String(e.id || "")
                if (id.startsWith("avahi-") || id.indexOf("blueman") !== -1) continue
                if (id.length > 0) {
                    if (seen[id] === true) continue
                    seen[id] = true
                }
                out.push(e)
            }
            out.sort((a, b) => {
                let an = String(a.name || a.id || "").toLowerCase()
                let bn = String(b.name || b.id || "").toLowerCase()
                return an.localeCompare(bn)
            })
        } catch (e) { console.log("[Apps] desktop entries error", e) }
        return out
    }
    readonly property var filteredLibrary: {
        let q = root.searchText.trim().toLowerCase()
        if (q.length === 0) return root.libraryApps
        return root.libraryApps.filter(e => (String(e.name || "") + " " + String(e.comment || "") + " " + String(e.id || "")).toLowerCase().indexOf(q) !== -1)
    }

    // Dropdown options per kind: only apps whose desktop categories match the
    // kind (TerminalEmulator / WebBrowser / FileManager). Solstice web apps
    // declare WebBrowser but are site shortcuts, not browsers, so they stay
    // out of the browser list. A category with no match at all falls back to
    // every app so the dropdown never goes empty. Labels are de-duplicated.
    readonly property var optionSets: {
        Theme.appsRev
        let sets = ({})
        for (let k = 0; k < root.defaultKinds.length; k++) {
            const kind = root.defaultKinds[k].kind
            const cat = root.defaultKinds[k].category
            const apps = root.libraryApps
            let matched = []
            for (let i = 0; i < apps.length; i++) {
                const e = apps[i]
                if (cat === "WebBrowser" && root.isWebAppEntry(e)) continue
                let hit = false
                try {
                    const cats = e.categories || []
                    for (let c = 0; c < cats.length; c++) if (String(cats[c]) === cat) { hit = true; break }
                } catch (err) {}
                if (hit) matched.push(e)
            }
            const all = matched.length > 0 ? matched : apps
            let used = ({})
            let out = []
            for (let i = 0; i < all.length; i++) {
                const e = all[i]
                const id = String(e.id || "")
                let base = String(e.name || id)
                let label = base
                if (used[label] === true) label = base + " · " + id
                used[label] = true
                out.push({ id: id, name: label, base: base })
            }
            sets[kind] = out
        }
        return sets
    }

    // ---- selection / info ------------------------------------------------
    readonly property var selectedEntry: {
        Theme.appsRev
        if (root.selectedAppId.length === 0) return null
        try {
            let e = DesktopEntries.byId(root.selectedAppId)
            if (e) return e
        } catch (err) {}
        const apps = root.libraryApps
        for (let i = 0; i < apps.length; i++) if (String(apps[i].id || "") === root.selectedAppId) return apps[i]
        return null
    }
    readonly property string selectedName: {
        const e = root.selectedEntry
        return e ? String(e.name || e.id || root.selectedAppId) : root.selectedAppId
    }
    readonly property bool selectedHidden: {
        Theme.hiddenAppsRev
        return root.selectedAppId.length > 0 && Theme.isAppHidden(root.selectedAppId)
    }
    readonly property bool infoReady: !!(root.appInfo && root.appInfo.kind)
    readonly property string selectedSource: root.infoFailed ? "Unknown" : root.infoReady ? root.sourceLabel(root.appInfo.kind) : "Checking…"

    function entryForCommand(command: string): var {
        const base = String(command || "").split("/").pop()
        if (base.length === 0) return null
        const apps = root.libraryApps
        for (let i = 0; i < apps.length; i++) {
            let cmd = null
            try { cmd = apps[i].command } catch (err) {}
            if (cmd && cmd.length > 0 && String(cmd[0]).split("/").pop() === base) return apps[i]
        }
        return null
    }
    // Solstice web apps (webapp-install.sh) are launcher shortcuts to a site;
    // their desktop files declare WebBrowser to be openable by browsers.
    function isWebAppEntry(e: var): bool {
        if (!e) return false
        try {
            const c = e.command
            if (c && c.length > 0) {
                const first = String(c[0])
                if (first.indexOf("webapp-launch.sh") !== -1 || first.indexOf("webapp-handler") !== -1) return true
                for (let i = 0; i < c.length; i++) if (String(c[i]).indexOf("--app=") === 0) return true
            }
        } catch (err) {}
        return false
    }
    function optionNames(kind: string): var {
        const set = root.optionSets[kind] || []
        let out = []
        for (let i = 0; i < set.length; i++) out.push(set[i].name)
        return out
    }
    function currentLabel(kind: string): string {
        const s = root.defaults[kind]
        if (!s) return "—"
        const opts = root.optionSets[kind] || []
        if (s.id) for (let i = 0; i < opts.length; i++) if (opts[i].id === s.id) return opts[i].name
        const byCmd = root.entryForCommand(s.command)
        if (byCmd) for (let i = 0; i < opts.length; i++) if (opts[i].id === String(byCmd.id || "")) return opts[i].name
        return s.name || s.command || "—"
    }
    function defaultSubtext(kind: string): string {
        const s = root.defaults[kind]
        if (!s) return "Loading…"
        const cmd = s.command || ""
        if (s.bound === false) return cmd + " · shortcut not bound"
        return (s.chord || "—") + " · " + cmd
    }
    function commandText(): string {
        const e = root.selectedEntry
        if (!e) return "—"
        try {
            const c = e.command
            return (c && c.length > 0) ? c.join(" ") : "—"
        } catch (err) { return "—" }
    }
    function sourceLabel(kind: string): string {
        if (kind === "rpm" || kind === "dpkg" || kind === "pacman") return "System package"
        if (kind === "flatpak") return "Flatpak"
        if (kind === "webapp") return "Web app"
        if (kind === "user") return "User launcher"
        return "No package owner"
    }
    function infoField(key: string): string {
        const v = root.appInfo ? root.appInfo[key] : ""
        if (v === undefined || v === null || v === "") return root.infoReady ? "—" : root.infoFailed ? "—" : "Checking…"
        return String(v)
    }
    function kindLabel(kind: string): string {
        for (let i = 0; i < root.defaultKinds.length; i++) if (root.defaultKinds[i].kind === kind) return root.defaultKinds[i].label
        return kind
    }
    function uninstallHint(): string {
        if (root.infoFailed) return "Could not identify how this app is installed. Hiding it from the launcher is the safe option."
        const kind = root.appInfo ? String(root.appInfo.kind || "") : ""
        if (kind === "flatpak") return "Runs flatpak uninstall " + root.infoField("package") + "."
        if (kind === "webapp") return "Removes this web app and its launcher entry."
        if (kind === "user") return "Deletes the user launcher entry. The app itself stays on disk."
        if (kind === "rpm" || kind === "dpkg" || kind === "pacman") return "Removes the package " + root.infoField("package") + " and its unused dependencies. You will be asked to authenticate first."
        if (kind === "unknown") return "This app has no package owner. Hiding it from the launcher is the safe option."
        return "Removes this app from the system."
    }
    function setStatus(text: string, isError: bool): void {
        root.statusText = text || ""
        root.statusIsError = !!isError
    }

    // ---- navigation / actions --------------------------------------------
    function refreshDefaults(): void {
        if (!defaultsProc.running) defaultsProc.running = true
    }
    function refreshInfo(): void {
        if (root.selectedAppId.length === 0) return
        infoProc.command = ["python3", root.scriptPath, "info", "--id", root.selectedAppId, "--json"]
        infoProc.running = true
    }
    function openLibrary(): void {
        root.view = "library"
        root.searchText = ""
        root.setStatus("", false)
    }
    function openTheming(): void {
        root.view = "theming"
        root.setStatus("", false)
    }
    function openApp(id: string): void {
        if (id.length === 0) return
        root.selectedAppId = id
        root.appInfo = ({})
        root.infoFailed = false
        root.confirmUninstall = false
        root.setStatus("", false)
        root.view = "detail"
        root.refreshInfo()
    }
    function back(): void {
        if (root.view === "detail") {
            root.view = "library"
            root.confirmUninstall = false
            return
        }
        root.view = ""
        root.searchText = ""
    }
    function openSelected(): void {
        const e = root.selectedEntry
        if (!e) return
        try { if (typeof e.execute === "function") e.execute() } catch (err) { console.log("[Apps] open failed", err) }
    }
    function pickDefault(kind: string, label: string): void {
        if (setProc.running) return
        const opts = root.optionSets[kind] || []
        for (let i = 0; i < opts.length; i++) {
            if (opts[i].name !== label) continue
            root.pendingKind = kind
            root.pendingLabel = opts[i].base
            setProc.command = ["python3", root.scriptPath, "set-default", "--kind", kind, "--id", opts[i].id, "--name", opts[i].base, "--json"]
            setProc.running = true
            return
        }
    }
    function runUninstall(): void {
        if (root.uninstalling || root.selectedAppId.length === 0) return
        root.uninstalling = true
        root.confirmUninstall = false
        uninstallProc.command = ["python3", root.scriptPath, "uninstall", "--id", root.selectedAppId, "--json"]
        uninstallProc.running = true
    }

    onPageEntered: {
        root.view = ""
        root.selectedAppId = ""
        root.searchText = ""
        root.setStatus("", false)
        root.confirmUninstall = false
        root.refreshDefaults()
    }

    // ---- backend processes -----------------------------------------------
    Process {
        id: defaultsProc
        command: ["python3", root.scriptPath, "defaults", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let parsed = null
                try { parsed = JSON.parse(text || "{}") } catch (e) {}
                if (parsed && parsed.ok) root.defaults = parsed.defaults || ({})
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }
    Process {
        id: setProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let res = null
                try { res = JSON.parse(text || "{}") } catch (e) {}
                if (res && res.ok) {
                    root.defaults = res.defaults || root.defaults
                    root.setStatus(res.message || "Default updated.", false)
                    Theme.triggerThemeOsd(root.kindLabel(root.pendingKind), root.pendingLabel + " · " + (res.message || "updated"), false)
                } else {
                    const msg = (res && res.error) || "Could not change the default."
                    root.setStatus(msg, true)
                    Theme.triggerThemeOsd("Default applications", msg, true)
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { root.pendingKind = ""; root.pendingLabel = "" }
    }
    Process {
        id: infoProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let parsed = null
                try { parsed = JSON.parse(text || "{}") } catch (e) {}
                if (parsed && parsed.ok && parsed.info && String(parsed.info.id || "") === root.selectedAppId) {
                    root.appInfo = parsed.info
                    root.infoFailed = false
                } else {
                    root.appInfo = ({})
                    root.infoFailed = true
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }
    Process {
        id: uninstallProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let res = null
                try { res = JSON.parse(text || "{}") } catch (e) {}
                if (res && res.ok) {
                    const msg = res.message || "Uninstalled."
                    Theme.triggerThemeOsd(root.selectedName, msg, false)
                    root.setStatus(msg, false)
                    root.appInfo = ({})
                    root.infoFailed = false
                    root.selectedAppId = ""
                    root.confirmUninstall = false
                    root.view = "library"
                } else {
                    const msg = (res && res.error) || "Uninstall failed."
                    Theme.triggerThemeOsd(root.selectedName, msg, true)
                    root.setStatus(msg, true)
                }
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { root.uninstalling = false }
    }

    // ---- status line -----------------------------------------------------
    Text {
        visible: root.statusText.length > 0
        width: parent.width
        leftPadding: 8
        rightPadding: 8
        bottomPadding: 4
        text: root.statusText
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        color: root.statusIsError ? Theme.error : Theme.textSecondary
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }

    // ---- overview: default applications ----------------------------------
    NexusControls.SectionHeader { first: true; visible: root.view === ""; text: "Default applications" }
    Repeater {
        model: root.view === "" ? root.defaultKinds : []
        delegate: NexusControls.DropdownRow {
            required property var modelData
            required property int index
            icon: modelData.icon
            tint: modelData.tint
            label: modelData.label
            subtext: root.defaultSubtext(modelData.kind)
            options: root.optionNames(modelData.kind)
            current: root.currentLabel(modelData.kind)
            first: index === 0
            last: index === root.defaultKinds.length - 1
            onPicked: value => root.pickDefault(modelData.kind, value)
        }
    }
    NexusControls.Note {
        visible: root.view === ""
        text: "Picking an app rebinds the matching Hyprland bind right away."
    }

    // ---- overview: library ------------------------------------------------
    NexusControls.SectionHeader { visible: root.view === ""; text: "Library" }
    NexusControls.NavRow {
        visible: root.view === ""
        first: true
        icon: "󰀻"
        text: "All apps"
        subtext: root.libraryApps.length + " apps · open, hide or uninstall"
        onClicked: root.openLibrary()
    }
    NexusControls.NavRow {
        visible: root.view === ""
        last: true
        icon: "󰏘"
        text: "App Theming"
        subtext: "Matugen templates for installed apps"
        onClicked: root.openTheming()
    }

    // ---- sub-page header --------------------------------------------------
    Item {
        visible: root.view !== ""
        width: parent.width
        implicitHeight: 56
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Rectangle {
                width: 40
                height: 40
                // M3E shape morph: circle at rest, rounded square while hovered.
                radius: backMouse.containsMouse ? 12 : 20
                color: backMouse.containsMouse ? Theme.panelCardHighest : Theme.panelCardHigh
                antialiasing: Theme.shapesAa
                Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: Theme.fs(20)
                    color: Theme.textPrimary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Ui.StateLayer { id: backMouse; radius: parent.radius; color: Theme.textPrimary; onClicked: root.back() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.view === "detail" ? root.selectedName : root.view === "theming" ? "App Theming" : "All apps"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(22)
                font.weight: Font.Medium
                color: Theme.textPrimary
                elide: Text.ElideRight
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    // ---- library: all apps ------------------------------------------------
    NexusControls.SearchBar {
        visible: root.view === "library"
        width: parent.width
        text: root.searchText
        placeholder: "Search apps"
        onTextChanged2: t => root.searchText = t
    }
    Text {
        visible: root.view === "library" && root.filteredLibrary.length === 0
        width: parent.width
        leftPadding: 8
        topPadding: 8
        text: "No apps match this search."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        color: Theme.textMuted
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }
    Repeater {
        model: root.view === "library" ? root.filteredLibrary : []
        delegate: AppListRow {
            required property var modelData
            required property int index
            appEntry: modelData
            isFirst: index === 0
            isLast: index === root.filteredLibrary.length - 1
            onActivated: root.openApp(String(modelData.id || ""))
        }
    }

    // ---- library: app theming (matugen template browser) -----------------
    // Loaded only while shown; AppThemingPage refreshes on completion.
    Loader {
        visible: root.view === "theming"
        width: parent.width
        asynchronous: false
        sourceComponent: root.view === "theming" ? themingComp : null
    }
    Component {
        id: themingComp
        AppThemingPage { showTitle: false }
    }

    // ---- detail: one shared page, bound to the selected app --------------
    Rectangle {
        visible: root.view === "detail"
        width: parent.width
        implicitHeight: detailHeader.implicitHeight + 32
        color: Theme.panelCard
        radius: 16
        antialiasing: Theme.shapesAa
        Row {
            id: detailHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 16
            AppIcon {
                size: 56
                appId: root.selectedAppId
                iconValue: root.selectedEntry ? String(root.selectedEntry.icon || "") : ""
            }
            Column {
                width: Math.max(0, parent.width - 56 - 16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: root.selectedName
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(22)
                    font.weight: Font.Medium
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.selectedEntry ? String(root.selectedEntry.comment || "") : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
        }
    }

    NexusControls.SectionHeader { visible: root.view === "detail"; text: "Actions" }
    NexusControls.NavRow {
        visible: root.view === "detail"
        first: true
        icon: "󰐊"
        text: "Open"
        subtext: "Launch " + root.selectedName
        disabled: root.selectedEntry === null
        onClicked: root.openSelected()
    }
    NexusControls.ToggleRow {
        visible: root.view === "detail"
        icon: "󰈈"
        text: "Hide from Launcher"
        subtext: "Keeps the app installed, but out of launcher results"
        disabled: root.selectedEntry === null
        checked: root.selectedHidden
        onToggled: next => Theme.setAppHidden(root.selectedAppId, next)
    }
    DangerRow {
        visible: root.view === "detail"
        last: true
        icon: "󰩹"
        text: "Uninstall"
        subtext: (root.infoReady || root.infoFailed) ? root.uninstallHint() : "Checking how this app is installed…"
        disabled: root.selectedEntry === null || root.infoFailed || (root.infoReady && root.appInfo.kind === "unknown")
        onClicked: root.confirmUninstall = true
    }
    Rectangle {
        visible: root.view === "detail" && root.confirmUninstall
        width: parent.width
        implicitHeight: confirmCol.implicitHeight + 32
        color: Theme.panelCard
        radius: 16
        border.color: Theme.withAlpha(Theme.error, 0.5)
        border.width: 1
        antialiasing: Theme.shapesAa
        Column {
            id: confirmCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 8
            Text {
                width: parent.width
                text: "Uninstall " + root.selectedName + "?"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(14)
                font.weight: Font.Medium
                color: Theme.error
                wrapMode: Text.WordWrap
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                width: parent.width
                text: root.uninstallHint()
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Row {
                spacing: 12
                NexusControls.TextButton {
                    text: "Cancel"
                    enabled2: !root.uninstalling
                    onClicked: root.confirmUninstall = false
                }
                DangerButton {
                    text: "Uninstall"
                    busy: root.uninstalling
                    onClicked: root.runUninstall()
                }
            }
        }
    }

    NexusControls.SectionHeader { visible: root.view === "detail"; text: "Details" }
    NexusControls.InfoRow {
        visible: root.view === "detail"
        first: true
        label: "Application ID"
        value: root.selectedAppId
    }
    NexusControls.InfoRow {
        visible: root.view === "detail"
        label: "Command"
        value: root.commandText()
    }
    NexusControls.InfoRow {
        visible: root.view === "detail"
        label: "Source"
        value: root.selectedSource
    }
    NexusControls.InfoRow {
        visible: root.view === "detail"
        label: "Package"
        value: root.infoField("package")
    }
    NexusControls.InfoRow {
        visible: root.view === "detail"
        label: "Version"
        value: root.infoField("version")
    }
    NexusControls.InfoRow {
        visible: root.view === "detail"
        last: true
        label: "Desktop file"
        value: root.infoField("path")
        valueMaxWidth: 320
    }

    // ---- inline components -----------------------------------------------
    component AppIcon: Item {
        id: appIcon
        property string appId: ""
        property string iconValue: ""
        property int size: 36
        implicitWidth: appIcon.size
        implicitHeight: appIcon.size
        readonly property bool glyphIcon: Ui.Util.isGlyphIcon(appIcon.iconValue)
        // Resolved imperatively: Theme.appIconFor() memoises into Theme's
        // caches, so calling it from a binding would write a property the
        // binding reads and trip a binding loop (same pattern as
        // ActiveWindow/Workspaces).
        property string resolvedSource: ""
        function resolveIcon(): void {
            if (appIcon.glyphIcon) {
                appIcon.resolvedSource = ""
                return
            }
            let src = ""
            try {
                src = (appIcon.iconValue.length === 0 && appIcon.appId.length === 0)
                    ? ""
                    : Ui.Util.iconSource(appIcon.iconValue, Theme.appIconFor(appIcon.appId))
            } catch (e) {}
            if (appIcon.resolvedSource !== src) appIcon.resolvedSource = src
        }
        onAppIdChanged: resolveIcon()
        onIconValueChanged: resolveIcon()
        Component.onCompleted: resolveIcon()
        Connections {
            target: Theme
            function onAppsRevChanged() { appIcon.resolveIcon() }
        }
        IconImage {
            anchors.centerIn: parent
            visible: !appIcon.glyphIcon
            width: appIcon.size
            height: appIcon.size
            source: appIcon.resolvedSource
            asynchronous: true
            implicitSize: Qt.size(appIcon.size * 2, appIcon.size * 2)
            mipmap: Theme.imageMipmap
            smooth: Theme.imageSmooth
        }
        Text {
            anchors.centerIn: parent
            visible: appIcon.glyphIcon
            text: appIcon.glyphIcon ? appIcon.iconValue : ""
            font.family: Theme.iconFontFamily
            font.pixelSize: Math.round(appIcon.size * 0.62)
            color: Theme.textPrimary
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
    }

    component AppListRow: Rectangle {
        id: appRow
        required property var appEntry
        required property bool isFirst
        required property bool isLast
        signal activated()

        readonly property string appId: appRow.appEntry ? String(appRow.appEntry.id || "") : ""
        readonly property string appName: appRow.appEntry ? String(appRow.appEntry.name || appRow.appEntry.id || "") : ""
        readonly property string appComment: appRow.appEntry ? String(appRow.appEntry.comment || "") : ""
        readonly property string appIconValue: appRow.appEntry ? String(appRow.appEntry.icon || "") : ""
        readonly property bool isHidden: {
            Theme.hiddenAppsRev
            return Theme.isAppHidden(appRow.appId)
        }

        width: parent ? parent.width : 300
        implicitHeight: 64
        height: implicitHeight
        color: rowMouse.containsMouse ? Theme.panelCardHigh : Theme.panelCard
        topLeftRadius: appRow.isFirst ? 28 : 4
        topRightRadius: appRow.isFirst ? 28 : 4
        bottomLeftRadius: appRow.isLast ? 28 : 4
        bottomRightRadius: appRow.isLast ? 28 : 4
        antialiasing: Theme.shapesAa
        Row {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 20
            spacing: 14
            AppIcon {
                anchors.verticalCenter: parent.verticalCenter
                size: 34
                appId: appRow.appId
                iconValue: appRow.appIconValue
            }
            Column {
                width: Math.max(0, parent.width - 34 - 14 - badge.width - 24 - 14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: appRow.appName
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    font.weight: Font.Medium
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: appRow.appComment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Rectangle {
                id: badge
                visible: appRow.isHidden
                anchors.verticalCenter: parent.verticalCenter
                width: badgeText.implicitWidth + 16
                height: 22
                radius: 11
                color: Theme.secondary_container
                antialiasing: Theme.shapesAa
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: "Hidden"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.on_secondary_container
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                font.pixelSize: Theme.fs(18)
                color: Theme.textSecondary
                antialiasing: Theme.textAa
            }
        }
        Ui.StateLayer {
            id: rowMouse
            showHoverBackground: false
            radius: 28
            color: Theme.textPrimary
            onClicked: appRow.activated()
        }
    }

    component DangerRow: Rectangle {
        id: danger
        property string icon: ""
        property string text: ""
        property string subtext: ""
        property bool disabled: false
        property bool first: false
        property bool last: false
        signal clicked()
        antialiasing: Theme.shapesAa
        width: parent ? parent.width : 300
        implicitHeight: Math.max(dangerIcon.implicitHeight, dangerCol.implicitHeight) + 24
        height: implicitHeight
        color: danger.disabled ? Theme.panelCard : dangerMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.14) : Theme.panelCard
        topLeftRadius: danger.first ? 28 : 4
        topRightRadius: danger.first ? 28 : 4
        bottomLeftRadius: danger.last ? 28 : 4
        bottomRightRadius: danger.last ? 28 : 4
        Row {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            opacity: danger.disabled ? 0.5 : 1
            Text {
                id: dangerIcon
                visible: danger.icon.length > 0
                text: danger.icon
                font.family: Theme.iconFontFamily; font.pixelSize: Theme.fs(18)
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Column {
                id: dangerCol
                width: Math.max(0, parent.width - 30)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    width: parent.width
                    text: danger.text
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                    color: Theme.error
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    visible: danger.subtext.length > 0
                    text: danger.subtext
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
        }
        Ui.StateLayer {
            id: dangerMouse
            showHoverBackground: false
            disabled: danger.disabled
            radius: 28
            color: Theme.error
            onClicked: danger.clicked()
        }
    }

    component DangerButton: Rectangle {
        id: dangerBtn
        property string text: ""
        property bool busy: false
        signal clicked()
        implicitWidth: dangerLabel.implicitWidth + 32
        implicitHeight: 36
        radius: dangerBtnMouse.pressed ? 10 : 18
        color: Theme.withAlpha(Theme.error, dangerBtnMouse.containsMouse ? 0.22 : 0.14)
        antialiasing: Theme.shapesAa
        Behavior on radius { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durDefaultEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveDefaultEffects } }
        Text {
            id: dangerLabel
            anchors.centerIn: parent
            text: dangerBtn.busy ? "Working…" : dangerBtn.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.weight: Font.Medium
            color: Theme.error
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        Ui.StateLayer {
            id: dangerBtnMouse
            showHoverBackground: false
            disabled: dangerBtn.busy
            radius: 18
            color: Theme.error
            onClicked: dangerBtn.clicked()
        }
    }
}
