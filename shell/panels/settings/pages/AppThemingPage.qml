pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../../style/themes"
import "../../../../backend/services"
import "../../../../style/ui" as Ui
import ".."

// App Theming — matugen template browser for the InioX/matugen-themes
// collection. Lives under Apps > Library ("theming" sub-view of AppsPage,
// loaded with showTitle: false); the catalogue
// (backend/config/matugen_themes.json) is served by
// backend/scripts/matugen-themes.py, which also reports which templates are
// installed (their [templates.*] blocks in ~/.config/matugen/config.toml) and
// active (theming_settings.json toggles). Installing downloads the upstream
// template, wires the config block, enables its toggle and re-applies the
// current theme engine so the app is themed immediately; Remove drops the
// block again.
NexusControls.PageBase {
    id: root
    title: "App Theming"

    // Same theme driver as Wallpaper & style: after a template is wired we
    // re-run the active engine (monet from the wallpaper, or the preset
    // renderer) so the new app output is generated right away.
    ThemeEngine { id: themeEngine }

    property var entries: []
    property bool loading: true
    property string filterText: ""
    property string busyId: ""
    property string pendingAction: ""
    property string pendingTitle: ""
    property string errorText: ""

    readonly property string scriptPath: Quickshell.shellDir + "/backend/scripts/matugen-themes.py"
    readonly property var categoryIcons: ({
        "Desktop & system": "󰍹",
        "Terminals": "󰆍",
        "Editors & tools": "󰆾",
        "Apps & media": "󰀻",
        "Browsers": "󰖟",
        "Notifications & launchers": "󰂚"
    })
    function iconFor(category: string): string {
        return root.categoryIcons[category] || "󰏘"
    }

    readonly property var filteredEntries: {
        let q = (root.filterText || "").toLowerCase().trim()
        let all = root.entries
        if (q.length === 0) return all
        return all.filter(e => ((e.title + " " + e.category + " " + e.desc + " " + (e.note || "")).toLowerCase().indexOf(q) !== -1))
    }
    readonly property var installedEntries: root.filteredEntries.filter(e => e.installed || e.partial)
    readonly property var availableGroups: {
        let groups = []
        let rows = root.filteredEntries.filter(e => !e.installed && !e.partial)
        for (let i = 0; i < rows.length; ++i) {
            let row = rows[i]
            let group = null
            for (let j = 0; j < groups.length; ++j) {
                if (groups[j].title === row.category) { group = groups[j]; break }
            }
            if (group === null) {
                group = { title: row.category, rows: [] }
                groups.push(group)
            }
            row.first = group.rows.length === 0
            if (group.rows.length > 0) group.rows[group.rows.length - 1].last = false
            row.last = true
            group.rows.push(row)
        }
        return groups
    }

    onPageEntered: root.refresh()
    // Nested in AppsPage the Loader instantiates this page on entry (the
    // standalone pageEntered hook never fires), so refresh here too.
    Component.onCompleted: root.refresh()

    function refresh(): void {
        if (listProc.running) return
        root.loading = root.entries.length === 0
        listProc.running = true
    }
    function runAction(id: string, action: string, title: string): void {
        if (root.busyId !== "") return
        root.busyId = id
        root.pendingAction = action
        root.pendingTitle = title
        actionProc.command = ["python3", root.scriptPath, action, id]
        actionProc.running = true
    }
    function applyTheme(): void {
        if (themeEngine.currentEngine === "wallpaper") themeEngine.enqueueThemeApply("monetCurrent", true)
        else themeEngine.enqueueThemeApply("preset:" + themeEngine.currentEngine, true)
    }

    Process {
        id: listProc
        command: ["python3", root.scriptPath, "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let parsed = null
                try { parsed = JSON.parse(text || "{}") } catch (e) { parsed = null }
                if (parsed !== null && parsed.ok !== false) {
                    root.entries = Array.isArray(parsed.entries) ? parsed.entries : []
                    root.errorText = ""
                } else {
                    root.entries = []
                    root.errorText = (parsed && parsed.error) || "Could not read the theme catalogue."
                }
                root.loading = false
            }
        }
        stderr: StdioCollector { waitForEnd: true }
    }
    Process {
        id: actionProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let res = null
                try { res = JSON.parse(text || "{}") } catch (e) { res = null }
                const title = root.pendingTitle || "App Theming"
                if (res !== null && res.ok) {
                    let detail = root.pendingAction === "remove"
                        ? ((res.removedFiles && res.removedFiles.length > 0) ? "Removed · app theme deleted" : "Removed")
                        : res.manual ? "Downloaded to the matugen templates folder"
                        : "Installed · applying"
                    Theme.triggerThemeOsd(title, detail, false)
                    if (root.pendingAction === "install" && !res.manual) root.applyTheme()
                    root.errorText = ""
                } else {
                    const msg = (res && res.error) || "Action failed"
                    Theme.triggerThemeOsd(title, msg, true)
                    root.errorText = msg
                }
                root.refresh()
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => {
            root.busyId = ""
            root.pendingAction = ""
            root.pendingTitle = ""
        }
    }

    // ---- source / filter --------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: 34
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: refreshBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Templates from github.com/InioX/matugen-themes"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            color: Theme.textMuted
            elide: Text.ElideRight
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        NexusControls.TextButton {
            id: refreshBtn
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: "Refresh"
            enabled2: root.busyId === "" && !listProc.running
            onClicked: root.refresh()
        }
    }
    NexusControls.SearchBar {
        width: parent.width
        text: root.filterText
        placeholder: "Filter templates"
        onTextChanged2: t => root.filterText = t
    }
    Text {
        visible: root.loading
        width: parent.width
        topPadding: 20
        leftPadding: 8
        text: "Loading templates…"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        color: Theme.textMuted
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }
    Text {
        visible: !root.loading && root.entries.length === 0
        width: parent.width
        topPadding: 20
        leftPadding: 8
        rightPadding: 8
        wrapMode: Text.WordWrap
        text: root.errorText.length > 0 ? root.errorText : "No templates found."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        color: root.errorText.length > 0 ? Theme.error : Theme.textMuted
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }

    // ---- installed --------------------------------------------------------
    NexusControls.SectionHeader {
        visible: !root.loading && root.installedEntries.length > 0
        first: true
        text: "Installed · " + root.installedEntries.length
    }
    Column {
        visible: !root.loading && root.installedEntries.length > 0
        width: parent.width
        spacing: 0
        Repeater {
            model: root.installedEntries
            delegate: ThemeRow {
                required property int index
                first: index === 0
                last: index === root.installedEntries.length - 1
            }
        }
    }

    // ---- available --------------------------------------------------------
    Repeater {
        model: root.availableGroups
        delegate: Column {
            id: groupColumn
            required property var modelData
            required property int index
            width: parent ? parent.width : 300
            NexusControls.SectionHeader {
                first: groupColumn.index === 0 && root.installedEntries.length === 0
                text: groupColumn.modelData.title + " · " + groupColumn.modelData.rows.length
            }
            Repeater {
                model: groupColumn.modelData.rows
                delegate: ThemeRow {
                    first: modelData.first
                    last: modelData.last
                }
            }
        }
    }
    Text {
        visible: !root.loading && root.entries.length > 0 && root.filteredEntries.length === 0
        width: parent.width
        topPadding: 20
        leftPadding: 8
        text: "No templates match the filter."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        color: Theme.textMuted
        antialiasing: Theme.textAa
        renderType: Theme.textRenderType
    }
    NexusControls.Note {
        visible: !root.loading && root.entries.length > 0
        text: "Installing downloads the application's matugen template, adds its [templates.*] block and re-applies the current theme, which writes the app's own theme file. Removing drops the block again, deletes that generated theme file (empty folders left behind are pruned) and asks the running app or daemon to reload (kitty, waybar, mako, btop, …), so the theme really disappears on both sides. Some apps still need the import line from the row note added to their config; manual entries only hold the downloaded template file, which Remove deletes."
    }

    // ---- row --------------------------------------------------------------
    // Same card shape as the Wallpaper & style theme list (28/4 grouped
    // corners). Row click runs the primary action: install for available
    // entries, re-apply for installed ones (the script is idempotent and also
    // re-enables a disabled toggle). Remove drops the config block again.
    component ThemeRow: Rectangle {
        id: row
        required property var modelData
        property bool first: false
        property bool last: false
        readonly property bool isInstalled: !!row.modelData.installed || !!row.modelData.partial
        readonly property bool isManual: !!row.modelData.manual
        readonly property bool isBusy: root.busyId === row.modelData.id
        readonly property string statusText: {
            if (!row.isInstalled) return ""
            if (row.isManual) return "Downloaded"
            if (row.modelData.partial) return "Partial"
            return row.modelData.active ? "✓ Active" : "Disabled"
        }
        width: root.width
        height: 68
        topLeftRadius: row.first ? 28 : 4
        topRightRadius: row.first ? 28 : 4
        bottomLeftRadius: row.last ? 28 : 4
        bottomRightRadius: row.last ? 28 : 4
        color: Theme.panelCard
        antialiasing: Theme.shapesAa

        // Below the layout (which holds the interactive buttons on top) so a
        // click anywhere else on the row still runs the primary action.
        Ui.StateLayer {
            showHoverBackground: false
            disabled: root.busyId !== ""
            radius: 28
            color: Theme.textPrimary
            onClicked: {
                if (root.busyId !== "") return
                root.runAction(row.modelData.id, "install", row.modelData.title)
            }
        }
        Row {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: 18
                color: Theme.withAlpha(row.isInstalled ? Theme.accent : Theme.primary, 0.18)
                antialiasing: Theme.shapesAa
                Text {
                    anchors.centerIn: parent
                    text: root.iconFor(row.modelData.category)
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(18)
                    color: row.isInstalled ? Theme.accent : Theme.primary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Column {
                width: Math.max(0, rowLayout.width - 36 - 12 - trailing.width - 12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: row.modelData.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    width: parent.width
                    text: row.modelData.desc + (row.modelData.note ? " · " + row.modelData.note : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            Row {
                id: trailing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isBusy || row.statusText.length > 0
                    text: row.isBusy ? "Working…" : row.statusText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Medium
                    color: row.statusText === "Disabled" || row.statusText === "Partial" ? Theme.textMuted : Theme.accent
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                NexusControls.TextButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !row.isBusy
                    enabled2: root.busyId === ""
                    text: row.isInstalled ? "Remove" : row.isManual ? "Download" : "Install"
                    onClicked: row.isInstalled
                        ? root.runAction(row.modelData.id, "remove", row.modelData.title)
                        : root.runAction(row.modelData.id, "install", row.modelData.title)
                }
            }
        }
    }
}
