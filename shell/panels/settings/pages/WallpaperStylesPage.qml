pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Widgets
import "../../../themes"
import "../../../services"
import "../../../ui" as Ui
import ".."

// Wallpaper & style — Nexus port of the Caelestia page: recent-wallpaper
// carousel, live wallpaper preview and the Wallpapers / Colours / Fonts
// sub-pages in one page. Sub-views are in-page (round back row) like
// PanelsPage; in compact mode the panel's header back returns to the
// category list from the main view only.
NexusControls.PageBase {
    id: root
    title: root.view === "" ? "Wallpaper & style" : root.viewTitle
    showTitle: root.view === ""

    // Sub-view state: "" (main), "wallpapers", "colours", "fonts".
    property string view: ""
    readonly property string viewTitle: root.view === "wallpapers" ? "Wallpapers"
        : root.view === "colours" ? "Colours"
        : root.view === "fonts" ? "Fonts" : ""
    function back(): void { root.view = "" }

    // Themes + monet live in ThemeEngine; the page drives them directly
    // (same JSON state on disk as the rest of the shell).
    ThemeEngine { id: themeEngine }
    readonly property var themeOptions: [
        {id: "wallpaper", title: "Wallpaper / Monet", icon: "󰸉", subtitle: "Automatic from wallpaper", placeholder: false},
        {id: "petrichor", title: "Petrichor", icon: "󰋊", subtitle: "Omarchy Petrichor • #93a06b / #171a15", placeholder: false},
        {id: "everforest", title: "Everforest", icon: "󰇧", subtitle: "Everforest Soft • #A7C080", placeholder: false},
        {id: "gruvbox", title: "Gruvbox", icon: "󰌛", subtitle: "Omarchy Gruvbox • #7daea3 / #282828", placeholder: false},
        {id: "tokyonight", title: "Tokyo Night", icon: "󰖔", subtitle: "Tokyo Night • #7aa2f7 / #1a1b26", placeholder: false},
        {id: "catppuccin", title: "Catppuccin Mocha", icon: "󰄛", subtitle: "Catppuccin Mocha • #cba6f7 / #1e1e2e", placeholder: false},
        {id: "monochrome", title: "Monochrome", icon: "󰃥", subtitle: "Grayscale 16 • #e7e7e7 / #181818", placeholder: false}
    ]
    Connections {
        target: themeEngine
        function onWallpaperDisplayRequested(path) { WallpaperService.setWallpaperDisplay(path) }
    }

    Component.onCompleted: WallpaperService.refresh()
    onPageEntered: WallpaperService.refresh()

    // ---- data ------------------------------------------------------------
    // Landing page: the current wallpaper as a large preview on top, the five
    // latest wallpapers as a plain nameless thumbnail row underneath.
    readonly property string previewPath: WallpaperService.current !== ""
        ? WallpaperService.current
        : (WallpaperService.files.length > 0 ? WallpaperService.files[0] : "")
    readonly property var recentList: {
        // Recents first, topped up from the scanned folder so the row always
        // holds five wallpapers once the folder has them.
        let out = []
        let seen = {}
        let push = p => {
            let s = "" + (p || "")
            if (s.length === 0 || seen[s]) return
            seen[s] = true
            out.push(s)
        }
        let rec = WallpaperService.recents
        let files = WallpaperService.files
        for (let i = 0; i < rec.length && out.length < root.recentCount; i++) push(rec[i])
        for (let i = 0; i < files.length && out.length < root.recentCount; i++) push(files[i])
        return out
    }
    readonly property int recentCount: 5
    readonly property int recentGap: 12
    readonly property int recentTileWidth: Math.max(72, Math.floor((width - (root.recentCount - 1) * root.recentGap - 16) / root.recentCount))
    readonly property int wallpaperGridRows: Math.max(1, Math.min(4, Math.ceil(WallpaperService.files.length / 3)))
    readonly property var schemeLabels: themeEngine.matugenTypes.map(t => themeEngine.matugenTypeLabels[t])
    readonly property bool lightBg: (0.299 * Theme.bg.r + 0.587 * Theme.bg.g + 0.114 * Theme.bg.b) > 0.5
    function themePrimary(id: string): color {
        if (id === "wallpaper") return Theme.primary
        if (id === "everforest") return lightBg ? "#8DA101" : "#A7C080"
        if (id === "tokyonight") return lightBg ? "#2959aa" : "#7aa2f7"
        if (id === "petrichor") return lightBg ? "#7f9459" : "#93a06b"
        if (id === "monochrome") return lightBg ? "#181818" : "#e7e7e7"
        if (id === "catppuccin") return lightBg ? "#8839ef" : "#cba6f7"
        if (id === "gruvbox") return "#7daea3"
        return Theme.textPrimary
    }

    function applyWallpaper(path: string): void {
        if (!path || path.length === 0) return
        if (!WallpaperService.setWallpaperDisplay(path)) return
        themeEngine.rememberWallpaper(themeEngine.currentEngine, path)
        if (themeEngine.currentEngine === "wallpaper") themeEngine.applyMonetFromPath(path)
    }
    function setTheme(id: string): void {
        if (themeEngine.wallpaperForTheme(id) === "") {
            let first = WallpaperService.firstForTheme(id)
            if (first !== "") themeEngine.rememberWallpaper(id, first)
        }
        themeEngine.setThemeEngine(id)
    }

    // ---- fonts (curated typefaces) ---------------------------------------
    property var fontFallback: []
    property int fontRevision: 0
    Process {
        id: fontListProc
        command: ["bash", "-c", "fc-list : family 2>/dev/null | tr ',' '\\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | grep -i -E 'JetBrains ?Mono|Geist ?Mono|Inter|Google ?Sans ?Flex' | sort -u | head -n 800"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = (text || "").trim()
                root.fontFallback = out.length === 0 ? [] : out.split("\n").map(s => s.trim()).filter(s => s.length > 0)
                root.fontRevision++
            }
        }
    }
    function fontGroupTitleFor(family: string): string {
        try {
            let n = ("" + family).toLowerCase().replace(/[\s_\-]+/g, "")
            if (n.includes("jetbrainsmono")) return "JetBrains Mono"
            if (n.includes("geistmono")) return "Geist Mono"
            if (n.includes("googlesansflex")) return "Google Sans Flex"
            if (n.startsWith("inter")) return "Inter"
        } catch (e) { }
        return ("" + family).trim()
    }
    function fontWeightRank(family: string): int {
        try {
            let n = ("" + family).toLowerCase()
            if (n.includes("thin")) return 1
            if (n.includes("extralight")) return 2
            if (n.includes("light")) return 3
            if (n.includes("medium")) return 5
            if (n.includes("semibold")) return 6
            if (n.includes("extrabold")) return 8
            if (n.includes("bold")) return 7
            if (n.includes("black")) return 9
        } catch (e) { }
        return 4
    }
    readonly property var fontGroups: {
        root.fontRevision
        let all = []
        try { let qtf = Qt.fontFamilies(); if (qtf && qtf.length > 0) all = qtf.slice() } catch (e) { }
        try {
            let fb = root.fontFallback
            let seen = { }
            for (let i = 0; i < all.length; i++) seen["" + all[i]] = true
            for (let j = 0; j < fb.length; j++) {
                let f = "" + fb[j]
                if (!seen[f]) { seen[f] = true; all.push(fb[j]) }
            }
        } catch (e) { }
        let allowed = ["jetbrainsmono", "geistmono", "inter", "googlesansflex"]
        all = all.filter(f => {
            try {
                let n = ("" + f).toLowerCase().replace(/[\s_\-]+/g, "")
                for (let i = 0; i < allowed.length; i++) if (n.includes(allowed[i])) return true
                return false
            } catch (e) { return false }
        })
        let map = { }
        let order = []
        for (let i = 0; i < all.length; i++) {
            let fam = "" + all[i]
            let g = root.fontGroupTitleFor(fam)
            if (!map[g]) { map[g] = []; order.push(g) }
            if (map[g].indexOf(fam) === -1) map[g].push(fam)
        }
        order.sort((a, b) => {
            const rank = s => s === "JetBrains Mono" ? 0 : s === "Geist Mono" ? 1 : s === "Inter" ? 2 : s === "Google Sans Flex" ? 3 : 4
            let ra = rank(a), rb = rank(b)
            if (ra !== rb) return ra - rb
            return ("" + a).toLowerCase() < ("" + b).toLowerCase() ? -1 : 1
        })
        let out = []
        for (let k = 0; k < order.length; k++) {
            let variants = map[order[k]].slice()
            variants.sort((a, b) => root.fontWeightRank(a) - root.fontWeightRank(b))
            let preview = variants.length > 0 ? variants[0] : order[k]
            for (let v = 0; v < variants.length; v++) {
                if (root.fontWeightRank(variants[v]) === 4) { preview = variants[v]; break }
            }
            out.push({ title: order[k], preview: preview })
        }
        return out
    }

    // ---- current wallpaper ------------------------------------------------
    Item {
        visible: root.view === ""
        width: parent.width
        height: previewCard.height + 44
        ClippingRectangle {
            id: previewCard
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 16
            width: Math.min(parent.width * 0.72, 520)
            height: Math.round(width * 9 / 16)
            radius: 20
            color: Theme.panelCard
            antialiasing: Theme.shapesAa
            Image {
                // Binding-safe thumb fallback: if the cached thumbnail is
                // missing/corrupt, show the original for as long as that path
                // is current (no imperative source assignment, so delegate
                // reuse in the grids keeps working).
                property string brokenThumb: ""
                anchors.fill: parent
                source: brokenThumb === root.previewPath
                    ? WallpaperService.originalUrl(root.previewPath)
                    : WallpaperService.imageUrl(root.previewPath)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 1040
                sourceSize.height: 585
                smooth: Theme.imageSmooth
                mipmap: Theme.imageMipmap
                onStatusChanged: if (status === Image.Error && brokenThumb !== root.previewPath) brokenThumb = root.previewPath
            }
            Column {
                anchors.centerIn: parent
                visible: root.previewPath.length === 0
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰋩"
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(32)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No wallpaper"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
        }
    }

    // ---- recent wallpapers (latest five, no names) -----------------------
    Column {
        visible: root.view === ""
        width: parent.width
        spacing: 8
        Item {
            width: parent.width
            height: Math.max(recentLabel.implicitHeight, viewAllBtn.implicitHeight)
            Text {
                id: recentLabel
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Recent"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.Medium
                color: Theme.textSecondary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            NexusControls.TextButton {
                id: viewAllBtn
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "View all"
                onClicked: root.view = "wallpapers"
            }
        }
        Rectangle {
            visible: root.recentList.length > 0
            width: parent.width
            height: recentRow.height + 32
            radius: 28
            color: Theme.panelCard
            antialiasing: Theme.shapesAa
            Row {
                id: recentRow
                anchors.centerIn: parent
                spacing: root.recentGap
                Repeater {
                    model: root.recentList.slice(0, root.recentCount)
                    delegate: Item {
                        id: recentTile
                        required property var modelData
                        required property int index
                        width: root.recentTileWidth
                        height: width
                        readonly property bool isCurrent: ("" + recentTile.modelData) === WallpaperService.current
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Theme.panelCard
                            antialiasing: Theme.shapesAa
                            Image {
                                property string brokenThumb: ""
                                anchors.fill: parent
                                source: brokenThumb === recentTile.modelData
                                    ? WallpaperService.originalUrl(recentTile.modelData)
                                    : WallpaperService.imageUrl(recentTile.modelData)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 320
                                sourceSize.height: 320
                                smooth: Theme.imageSmooth
                                mipmap: Theme.imageMipmap
                                onStatusChanged: if (status === Image.Error && brokenThumb !== recentTile.modelData) brokenThumb = recentTile.modelData
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: "transparent"
                            border.width: recentTile.isCurrent ? 2 : 0
                            border.color: Theme.accent
                            antialiasing: Theme.shapesAa
                        }
                        Ui.StateLayer { radius: 16; color: Theme.textPrimary; onClicked: root.applyWallpaper(recentTile.modelData) }
                    }
                }
            }
        }
        Text {
            visible: root.recentList.length === 0
            width: parent.width
            text: "No wallpapers found in " + WallpaperService.dirDisplay
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            color: Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        Item { width: 1; height: 20 }
    }

    // ---- pills -----------------------------------------------------------
    Item {
        visible: root.view === ""
        width: parent.width
        height: pillRow.height + 20
        Row {
            id: pillRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20
            spacing: 12
            StylePill { icon: "󰋩"; text: "Wallpapers"; onClicked: root.view = "wallpapers" }
            StylePill { icon: "󰏘"; text: "Colours"; onClicked: root.view = "colours" }
            StylePill { icon: "󰛖"; text: "Fonts"; onClicked: root.view = "fonts" }
        }
    }

    // ---- sub-page header -------------------------------------------------
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
                radius: 20
                color: backMouse.containsMouse ? Theme.panelCardHighest : Theme.panelCardHigh
                antialiasing: Theme.shapesAa
                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: Theme.fs(20)
                    color: Theme.textPrimary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Ui.StateLayer { id: backMouse; radius: 20; color: Theme.textPrimary; onClicked: root.back() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.viewTitle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(22)
                font.weight: Font.Medium
                color: Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    // ---- wallpapers ------------------------------------------------------
    Column {
        visible: root.view === "wallpapers"
        width: parent.width
        spacing: 0
        GridView {
            id: wallpaperGrid
            width: parent.width
            height: root.wallpaperGridRows * cellHeight
            clip: true
            cellWidth: Math.floor(width / 3)
            cellHeight: 140
            // PERF: an invisible GridView still instantiates its visible
            // delegates, so the landing view used to decode 12 full-size
            // wallpaper images before the user ever opened this sub-view.
            // Only bind the model while the view is actually shown.
            model: root.view === "wallpapers" ? WallpaperService.files : []
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            cacheBuffer: 400
            delegate: Item {
                id: wpTile
                required property var modelData
                required property int index
                width: wallpaperGrid.cellWidth
                height: wallpaperGrid.cellHeight
                readonly property bool isCurrent: ("" + wpTile.modelData) === WallpaperService.current
                readonly property string baseName: {
                    let s = String(wpTile.modelData || "")
                    let i = s.lastIndexOf("/")
                    return i >= 0 ? s.substring(i + 1) : s
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: 16
                    color: Theme.panelCard
                    border.width: wpTile.isCurrent ? 2 : 1
                    border.color: wpTile.isCurrent ? Theme.accent : "transparent"
                    clip: true
                    antialiasing: Theme.shapesAa
                    Column {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 5
                        ClippingRectangle {
                            width: parent.width
                            height: parent.height - 16
                            radius: 12
                            color: Theme.panelCardHigh
                            antialiasing: Theme.shapesAa
                            Image {
                                property string brokenThumb: ""
                                anchors.fill: parent
                                source: brokenThumb === wpTile.modelData
                                    ? WallpaperService.originalUrl(wpTile.modelData)
                                    : WallpaperService.imageUrl(wpTile.modelData)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 360
                                sourceSize.height: 167
                                smooth: Theme.imageSmooth
                                mipmap: Theme.imageMipmap
                                onStatusChanged: if (status === Image.Error && brokenThumb !== wpTile.modelData) brokenThumb = wpTile.modelData
                            }
                        }
                        Text {
                            width: parent.width
                            text: wpTile.baseName
                            color: wpTile.isCurrent ? Theme.accent : Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            font.weight: wpTile.isCurrent ? Font.Medium : Font.Normal
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 1
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                    Ui.StateLayer { radius: 16; color: Theme.textPrimary; onClicked: root.applyWallpaper(wpTile.modelData) }
                }
            }
        }
        Text {
            visible: WallpaperService.files.length === 0
            width: parent.width
            topPadding: 24
            text: "No wallpapers in " + WallpaperService.dirDisplay + " — put images there to see them here"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            color: Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        NexusControls.SectionHeader { visible: WallpaperService.files.length > 0; text: "Wallpaper settings" }
        NexusControls.DropdownRow {
            visible: WallpaperService.files.length > 0
            first: true
            label: "Fit mode"
            subtext: "How swaybg scales the image"
            options: WallpaperService.modes.map(m => m.charAt(0).toUpperCase() + m.slice(1))
            current: WallpaperService.mode.charAt(0).toUpperCase() + WallpaperService.mode.slice(1)
            onPicked: v => {
                let i = WallpaperService.modes.findIndex(m => m.charAt(0).toUpperCase() + m.slice(1) === v)
                if (i >= 0) WallpaperService.setMode(WallpaperService.modes[i])
            }
        }
        NexusControls.InfoRow {
            visible: WallpaperService.files.length > 0
            last: true
            label: "Folder"
            subtext: "Scanned two levels deep"
            value: WallpaperService.dirDisplay
            valueMaxWidth: Math.round(width * 0.5)
        }
    }

    // ---- colours ---------------------------------------------------------
    Column {
        visible: root.view === "colours"
        width: parent.width
        spacing: 0
        NexusControls.SectionHeader { first: true; text: "Themes" }
        Repeater {
            model: root.themeOptions
            delegate: Rectangle {
                id: presetRow
                required property var modelData
                required property int index
                width: root.width
                height: 64
                readonly property bool isCurrent: themeEngine.currentEngine === presetRow.modelData.id
                topLeftRadius: presetRow.index === 0 ? 28 : 4
                topRightRadius: presetRow.index === 0 ? 28 : 4
                bottomLeftRadius: presetRow.index === root.themeOptions.length - 1 ? 28 : 4
                bottomRightRadius: presetRow.index === root.themeOptions.length - 1 ? 28 : 4
                color: Theme.panelCard
                antialiasing: Theme.shapesAa
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 18
                        color: Theme.withAlpha(root.themePrimary(presetRow.modelData.id), 0.18)
                        antialiasing: Theme.shapesAa
                        Text {
                            anchors.centerIn: parent
                            text: presetRow.modelData.icon
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(18)
                            color: root.themePrimary(presetRow.modelData.id)
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                    Column {
                        width: Math.max(0, parent.width - 36 - 12 - checkText.width - 12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            width: parent.width
                            text: presetRow.modelData.title
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        Text {
                            width: parent.width
                            text: presetRow.modelData.subtitle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                    Text {
                        id: checkText
                        anchors.verticalCenter: parent.verticalCenter
                        visible: presetRow.isCurrent
                        text: "✓"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(14)
                        color: Theme.accent
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                Ui.StateLayer { radius: 28; color: Theme.textPrimary; onClicked: root.setTheme(presetRow.modelData.id) }
            }
        }
        NexusControls.SectionHeader { text: "Scheme settings" }
        NexusControls.ToggleRow {
            first: true
            text: "Dark theme"
            subtext: "Recolour from the wallpaper in dark mode"
            checked: themeEngine.monetMode === "dark"
            onToggled: n => themeEngine.applyMonetScheme(themeEngine.monetType, n ? "dark" : "light")
        }
        NexusControls.DropdownRow {
            last: true
            label: "Colour scheme"
            subtext: "Matugen colour distribution"
            options: root.schemeLabels
            current: themeEngine.matugenTypeLabels[themeEngine.monetType] || themeEngine.monetType
            onPicked: v => {
                let i = root.schemeLabels.indexOf(v)
                if (i >= 0) themeEngine.applyMonetScheme(themeEngine.matugenTypes[i], themeEngine.monetMode)
            }
        }
    }

    // ---- fonts -----------------------------------------------------------
    Column {
        visible: root.view === "fonts"
        onVisibleChanged: if (visible && !fontListProc.running) fontListProc.running = true
        width: parent.width
        spacing: 0
        NexusControls.SectionHeader { first: true; text: root.fontGroups.length === 1 ? "Typeface" : "Typefaces" }
        Repeater {
            model: root.fontGroups
            delegate: Rectangle {
                id: fontRow
                required property var modelData
                required property int index
                width: root.width
                height: 64
                readonly property bool isActive: {
                    let cur = ("" + Theme.fontFamily).trim()
                    return cur === ("" + fontRow.modelData.preview) || cur === ("" + fontRow.modelData.title)
                }
                topLeftRadius: fontRow.index === 0 ? 28 : 4
                topRightRadius: fontRow.index === 0 ? 28 : 4
                bottomLeftRadius: fontRow.index === root.fontGroups.length - 1 ? 28 : 4
                bottomRightRadius: fontRow.index === root.fontGroups.length - 1 ? 28 : 4
                color: Theme.panelCard
                antialiasing: Theme.shapesAa
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Aa"
                        font.family: fontRow.modelData.preview
                        font.pixelSize: Theme.fs(18)
                        color: fontRow.isActive ? Theme.accent : Theme.textPrimary
                        horizontalAlignment: Text.AlignHCenter
                        width: 36
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                    Column {
                        width: Math.max(0, parent.width - 36 - 12 - checkFontText.width - 12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: fontRow.modelData.title
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(15)
                            font.weight: Font.Medium
                            color: fontRow.isActive ? Theme.accent : Theme.textPrimary
                            elide: Text.ElideRight
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        Text {
                            width: parent.width
                            text: "Aa Bb Cc 123"
                            font.family: fontRow.modelData.preview
                            font.pixelSize: Theme.fs(11)
                            color: Theme.textPrimary
                            opacity: 0.52
                            elide: Text.ElideRight
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                    Text {
                        id: checkFontText
                        anchors.verticalCenter: parent.verticalCenter
                        visible: fontRow.isActive
                        text: "✓"
                        font.family: Theme.iconFontFamily
                        font.pixelSize: Theme.fs(14)
                        color: Theme.accent
                        antialiasing: Theme.textAa
                        renderType: Theme.textRenderType
                    }
                }
                Ui.StateLayer { radius: 28; color: Theme.textPrimary; onClicked: Theme.setSystemFont(fontRow.modelData.preview) }
            }
        }
        Text {
            visible: root.fontGroups.length === 0
            width: parent.width
            topPadding: 24
            text: "No supported fonts found"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            color: Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
    }

    // ---- components ------------------------------------------------------
    component StylePill: Rectangle {
        id: pill
        property string icon: ""
        property string text: ""
        signal clicked()
        implicitWidth: pillContent.implicitWidth + 40
        implicitHeight: 40
        radius: height / 2
        color: Theme.panelCardHigh
        antialiasing: Theme.shapesAa
        Row {
            id: pillContent
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(16)
                color: Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(14)
                font.weight: Font.Medium
                color: Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
        Ui.StateLayer { id: pillMouse; radius: pill.height / 2; color: Theme.textPrimary; onClicked: pill.clicked() }
    }
}
