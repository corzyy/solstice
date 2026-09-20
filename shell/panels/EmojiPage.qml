pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../style/themes"
import "../../style/ui"
import "./emoji_data.js" as EmojiData

// Emoji picker page of the launcher, reached through the prefix menu
// ("!emoji " by default). The search bar stays visible: the text after the
// prefix filters the grid (label + keywords, AND per word). Category chips
// switch between Recent and the Unicode groups; picking an emoji copies it
// with wl-copy, bumps the recents and dismisses the launcher.
// State (results, query, category, recents) lives in LauncherPanel; this
// file is the view. Emoji text forces QtRendering — colour glyphs from
// Noto Color Emoji do not draw through the native raster engine.
Item {
    id: root
    required property var scope
    clip: true

    readonly property bool searchActive: root.scope.emojiQuery.length > 0
    // Category list: index 0 is Recent, the rest map 1:1 onto
    // EmojiData.groups (scope.emojiCategory uses the same indexing).
    readonly property var categories: {
        const out = [{ label: "Recent", group: -1 }]
        const groups = EmojiData.groups
        for (let i = 0; i < groups.length; i++)
            out.push({ label: groups[i].split(" & ")[0], group: i })
        return out
    }
    readonly property int cols: Math.max(1, Math.floor(emojiGrid.width / root.cellSize))
    readonly property int cellSize: 44

    property int selIdx: 0

    // Page strip (LauncherPanel): emoji is slot 3, placed and shown by the
    // shared slide (pageVisible/pageX), so the page needs no transition of
    // its own.
    visible: root.scope.pageVisible(root.scope.pageEmoji)
    transform: Translate { x: root.scope.pageX(root.scope.pageEmoji, root.width) }
    enabled: root.scope.emojiMode

    function currentEntry(): var {
        if (!root.scope.emojiMode) return null
        const list = root.scope.emojiResults
        return (root.selIdx >= 0 && root.selIdx < list.length) ? list[root.selIdx] : null
    }
    function selectIndex(i: int): void {
        const n = root.scope.emojiResults.length
        if (n === 0) { root.selIdx = 0; return }
        root.selIdx = Math.max(0, Math.min(n - 1, i))
        Qt.callLater(() => emojiGrid.positionViewAtIndex(root.selIdx, GridView.Contain))
    }
    function move(delta: int): void {
        root.selectIndex(root.selIdx + delta)
    }
    function moveRows(rows: int): void {
        root.selectIndex(root.selIdx + rows * root.cols)
    }
    function movePages(pages: int): void {
        const perPage = Math.max(1, Math.floor(emojiGrid.height / root.cellSize) - 1)
        root.selectIndex(root.selIdx + pages * perPage * root.cols)
    }
    function activateCurrent(): void {
        const e = root.currentEntry()
        if (e) root.scope.copyEmoji("" + e.char)
    }
    // Keys while the search field owns focus (BeforeItem handler): grid
    // movement only, so typing, cursor movement and Enter keep working.
    // TAB is reserved for the launcher's page cycling (the panel handles it
    // before this runs), so categories switch by chip click.
    function handleFieldKey(event): bool {
        if (!root.scope.emojiMode) return false
        switch (event.key) {
        case Qt.Key_Up: root.moveRows(-1); return true
        case Qt.Key_Down: root.moveRows(1); return true
        case Qt.Key_PageUp: root.movePages(-1); return true
        case Qt.Key_PageDown: root.movePages(1); return true
        }
        return false
    }
    // Keys routed from the panel while the result area owns focus.
    function handleKey(event): bool {
        if (!root.scope.emojiMode) return false
        switch (event.key) {
        case Qt.Key_Up: root.move(-root.cols); return true
        case Qt.Key_Down: root.move(root.cols); return true
        case Qt.Key_Left: root.move(-1); return true
        case Qt.Key_Right: root.move(1); return true
        case Qt.Key_Home: root.selectIndex(0); return true
        case Qt.Key_End: root.selectIndex(root.scope.emojiResults.length - 1); return true
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activateCurrent()
            return true
        }
        return false
    }

    Connections {
        target: root.scope
        function onEmojiResultsChanged() {
            root.selIdx = root.scope.emojiResults.length > 0 ? 0 : -1
            Qt.callLater(() => emojiGrid.positionViewAtBeginning())
        }
        function onEmojiModeChanged() {
            if (root.scope.emojiMode) {
                root.selIdx = root.scope.emojiResults.length > 0 ? 0 : -1
                emojiGrid.contentY = 0
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ---- category chips ----------------------------------------------
        ListView {
            id: categoryList
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            visible: !root.searchActive
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.categories
            delegate: Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool current: !root.searchActive && root.scope.emojiCategory === chip.index
                width: chipText.implicitWidth + 22
                height: 30
                radius: 15
                color: chip.current ? Theme.accent : Theme.panelCardLowest
                antialiasing: Theme.shapesAa
                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
                }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: chip.current ? Font.Medium : Font.Normal
                    color: chip.current ? Theme.onAccent : Theme.textSecondary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                StateLayer {
                    radius: 15
                    onClicked: root.scope.setEmojiCategory(chip.index)
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const max = Math.max(0, categoryList.contentWidth - categoryList.width)
                    categoryList.contentX = Math.max(0, Math.min(max, categoryList.contentX - event.angleDelta.y))
                    event.accepted = true
                }
            }
        }

        // ---- emoji grid ----------------------------------------------------
        // Wrapper: the ScrollIndicator anchors to the flickable, so the
        // layout must not position it itself.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            GridView {
            id: emojiGrid
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            cacheBuffer: 600
            model: root.scope.emojiMode ? root.scope.emojiResults : []
            currentIndex: root.selIdx
            cellWidth: Math.floor(width / root.cols)
            cellHeight: root.cellSize
            delegate: Rectangle {
                id: emojiCell
                required property var modelData
                required property int index
                readonly property bool isCurrent: emojiGrid.currentIndex === emojiCell.index
                width: emojiGrid.cellWidth
                height: emojiGrid.cellHeight
                color: emojiCell.isCurrent ? Theme.withAlpha(Theme.textPrimary, 0.10) : "transparent"
                radius: 10
                antialiasing: Theme.shapesAa
                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
                Text {
                    anchors.centerIn: parent
                    text: emojiCell.modelData ? ("" + emojiCell.modelData.char) : ""
                    // Colour glyphs: explicit colour font + QtRendering (the
                    // native raster path drops them to tofu).
                    font.family: Theme.emojiFontFamily
                    font.pixelSize: Theme.fs(26)
                    color: Theme.textPrimary
                    antialiasing: Theme.textAa
                    renderType: Text.QtRendering
                }
                StateLayer {
                    radius: 10
                    onClicked: {
                        emojiGrid.currentIndex = emojiCell.index
                        root.selIdx = emojiCell.index
                        root.scope.copyEmoji("" + emojiCell.modelData.char)
                    }
                }
            }
            }

            // Empty states: nothing in Recent yet vs no search hit.
            Column {
                anchors.centerIn: parent
                visible: emojiGrid.count === 0
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\udb83\udc68"
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(28)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.searchActive ? "No emoji found"
                        : root.scope.emojiCategory === 0 ? "No recent emoji yet" : "No emoji"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(13)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.searchActive && root.scope.emojiCategory === 0
                    text: "Picked emoji show up here"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            ScrollIndicator { flick: emojiGrid }
        }

        // ---- footer: highlighted emoji + result count ----------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 8
            Text {
                visible: root.currentEntry() !== null
                text: root.currentEntry() ? ("" + root.currentEntry().char) : ""
                font.family: Theme.emojiFontFamily
                font.pixelSize: Theme.fs(18)
                antialiasing: Theme.textAa
                renderType: Text.QtRendering
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                    const e = root.currentEntry()
                    if (!e) return ""
                    return ("" + e.name).charAt(0).toUpperCase() + ("" + e.name).slice(1)
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.textSecondary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: {
                    if (!root.scope.emojiMode) return ""
                    const n = root.scope.emojiResults.length
                    return n + (n === 1 ? " result" : " results") + " · Enter: copy"
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.textMuted
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }
}
