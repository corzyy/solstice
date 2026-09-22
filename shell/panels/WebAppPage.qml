pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import "../../style/themes"
import "../../style/ui"

// Web App manager page of the launcher, reached through the prefix menu
// ("!webapp " by default). Add writes a Chromium --app .desktop entry via
// backend/scripts/webapp-install.sh; Remove lists the installed web apps
// (backend/scripts/webapp-list.sh) and deletes them with backend/scripts/webapp-remove.sh.
// State and processes live in LauncherPanel (scope); this file is the view.
Item {
    id: root
    required property var scope
    clip: true

    readonly property bool isAdd: root.scope.webAppPageMode !== "remove"
    readonly property bool busy: root.scope.webAppBusy
    readonly property bool success: root.scope.webAppSuccess

    property int fieldIdx: 0
    property int selIdx: 0

    // Page strip (LauncherPanel): web app is slot 2, placed and shown by the
    // shared slide (pageVisible/pageX), so the page needs no transition of
    // its own.
    visible: root.scope.pageVisible(root.scope.pageWebApp)
    opacity: root.scope.pageOpacity(root.scope.pageWebApp)
    transform: Translate { x: root.scope.pageX(root.scope.pageWebApp, root.width) }
    enabled: root.scope.webAppMode

    function focusField(): void {
        if (!root.scope.webAppMode || !root.isAdd) return
        if (root.fieldIdx === 0 && nameField) nameField.forceActiveFocus()
        else if (root.fieldIdx === 1 && urlField) urlField.forceActiveFocus()
        else if (root.fieldIdx === 2 && iconField) iconField.forceActiveFocus()
    }
    function doInstall(): void {
        if (root.busy) return
        root.scope.installWebApp(
            nameField ? nameField.text : "",
            urlField ? urlField.text : "",
            iconField ? iconField.text : "")
    }
    function doRemove(name): void {
        if (root.busy) return
        let n = name
        if (n === undefined || n === null || ("" + n).trim().length === 0) {
            const cur = root.scope.filteredWebApps[root.selIdx]
            n = cur ? cur.name : ""
        }
        if (n && ("" + n).trim().length > 0) root.scope.removeWebApp(n)
    }
    function ensureVisible(): void {
        if (!removeList.visible) return
        removeList.positionViewAtIndex(root.selIdx, ListView.Contain)
    }
    // Called by the panel when the page opens (mode/prefix change).
    function focusInitial(): void {
        if (!root.scope.webAppMode) return
        if (root.isAdd) {
            root.fieldIdx = 0
            Qt.callLater(() => root.focusField())
        } else {
            root.selIdx = 0
            Qt.callLater(() => root.ensureVisible())
        }
    }
    // Primary action behind search-field Enter and the footer button.
    function triggerPrimary(): void {
        if (root.isAdd) root.doInstall()
        else if (root.scope.filteredWebApps.length > 0) root.doRemove()
    }
    // Routed from the panel's Keys handler before generic launcher keys.
    // TAB is reserved for the launcher's page cycling: the panel (and the
    // fields' own BeforeItem handler) handles it before this runs, so only
    // Up/Down hop between form fields.
    function handleKey(event): bool {
        if (!root.scope.webAppMode) return false
        if (root.isAdd) {
            if (event.key === Qt.Key_Down) {
                root.fieldIdx = (root.fieldIdx + 1) % 3
                root.focusField()
                return true
            }
            if (event.key === Qt.Key_Up) {
                root.fieldIdx = (root.fieldIdx + 2) % 3
                root.focusField()
                return true
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.doInstall()
                return true
            }
            return false
        }
        const n = root.scope.filteredWebApps.length
        if (event.key === Qt.Key_Down) { if (n > 0) { root.selIdx = (root.selIdx + 1) % n; root.ensureVisible() } return true }
        if (event.key === Qt.Key_Up) { if (n > 0) { root.selIdx = (root.selIdx - 1 + n) % n; root.ensureVisible() } return true }
        if (event.key === Qt.Key_PageDown) { if (n > 0) { root.selIdx = Math.min(root.selIdx + 5, n - 1); root.ensureVisible() } return true }
        if (event.key === Qt.Key_PageUp) { if (n > 0) { root.selIdx = Math.max(root.selIdx - 5, 0); root.ensureVisible() } return true }
        if (event.key === Qt.Key_Home) { if (n > 0) { root.selIdx = 0; root.ensureVisible() } return true }
        if (event.key === Qt.Key_End) { if (n > 0) { root.selIdx = n - 1; root.ensureVisible() } return true }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (n > 0) root.doRemove()
            return true
        }
        return false
    }

    Connections {
        target: root.scope
        function onWebAppPageModeChanged() {
            root.fieldIdx = 0
            root.selIdx = 0
            removeList.contentY = 0
            root.focusInitial()
        }
        function onFilteredWebAppsChanged() {
            const n = root.scope.filteredWebApps.length
            if (root.selIdx > Math.max(0, n - 1)) root.selIdx = Math.max(0, n - 1)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ---- header with the Add / Remove switch ------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "󰖟"
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(22)
                color: root.busy ? Theme.accent : Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: "Web Apps"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(15)
                    font.weight: Font.Medium
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    Layout.fillWidth: true
                    text: root.isAdd
                        ? "Install a site as its own window"
                        : (root.scope.webAppLoading ? "Loading…"
                            : root.scope.webAppList.length + (root.scope.webAppList.length === 1 ? " web app" : " web apps"))
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            // Segmented Add / Remove switch.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: segRow.implicitWidth + 6
                implicitHeight: 34
                radius: 17
                color: Theme.panelCardLowest
                antialiasing: Theme.shapesAa
                RowLayout {
                    id: segRow
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: [
                            { mode: "add", label: "Add" },
                            { mode: "remove", label: "Remove" }
                        ]
                        delegate: Rectangle {
                            id: segBtn
                            required property var modelData
                            readonly property bool current: root.scope.webAppPageMode === segBtn.modelData.mode
                            implicitWidth: segText.implicitWidth + 24
                            implicitHeight: 28
                            radius: 14
                            color: segBtn.current
                                ? Theme.accent
                                : segMouse.containsMouse ? Theme.withAlpha(Theme.textPrimary, 0.08) : "transparent"
                            antialiasing: Theme.shapesAa
                            Behavior on color {
                                enabled: Theme.animationsEnabled
                                ColorAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
                            }
                            Text {
                                id: segText
                                anchors.centerIn: parent
                                text: segBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(12)
                                font.weight: segBtn.current ? Font.Medium : Font.Normal
                                color: segBtn.current ? Theme.onAccent : Theme.textSecondary
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            MouseArea {
                                id: segMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.scope.setWebAppPageMode(segBtn.modelData.mode)
                            }
                        }
                    }
                }
            }
        }

        // ---- add form ---------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.isAdd
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.preferredWidth: 54
                    text: "Name"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.textSecondary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    color: Theme.panelCardLowest
                    border.color: nameField.activeFocus ? Theme.accent : Theme.divider
                    border.width: nameField.activeFocus ? 2 : 1
                    antialiasing: Theme.shapesAa
                    TextField {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        background: null
                        placeholderText: "e.g. YouTube Music"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        selectByMouse: true
                        maximumLength: 64
                        cursorDelegate: Rectangle { width: 2; color: Theme.accent; antialiasing: Theme.shapesAa }
                        onAccepted: root.doInstall()
                        // TAB cycles the launcher's prefix pages (Shift+TAB
                        // backwards); field hopping stays on Up/Down.
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => {
                            if (root.scope.handlePageTab(event)) event.accepted = true
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.preferredWidth: 54
                    text: "URL"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.textSecondary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    color: Theme.panelCardLowest
                    border.color: urlField.activeFocus ? Theme.accent : Theme.divider
                    border.width: urlField.activeFocus ? 2 : 1
                    antialiasing: Theme.shapesAa
                    TextField {
                        id: urlField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        background: null
                        placeholderText: "https://… (https:// is added automatically)"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        selectByMouse: true
                        inputMethodHints: Qt.ImhUrlCharactersOnly
                        cursorDelegate: Rectangle { width: 2; color: Theme.accent; antialiasing: Theme.shapesAa }
                        onAccepted: root.doInstall()
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => {
                            if (root.scope.handlePageTab(event)) event.accepted = true
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.preferredWidth: 54
                    text: "Icon"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.textSecondary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 12
                    color: Theme.panelCardLowest
                    border.color: iconField.activeFocus ? Theme.accent : Theme.divider
                    border.width: iconField.activeFocus ? 2 : 1
                    antialiasing: Theme.shapesAa
                    TextField {
                        id: iconField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        background: null
                        placeholderText: "optional — auto favicon, URL, file or icon name"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        selectByMouse: true
                        cursorDelegate: Rectangle { width: 2; color: Theme.accent; antialiasing: Theme.shapesAa }
                        onAccepted: root.doInstall()
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => {
                            if (root.scope.handlePageTab(event)) event.accepted = true
                        }
                    }
                }
            }
        }

        // ---- remove list ------------------------------------------------
        // Wrapper: the ScrollIndicator anchors to the flickable, so the
        // layout must not position it itself.
        Item {
            visible: !root.isAdd
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
            id: removeList
            anchors.fill: parent
            clip: true
            spacing: 3
            boundsBehavior: Flickable.DragAndOvershootBounds
            boundsMovement: Flickable.FollowBoundsBehavior
            reuseItems: true
            cacheBuffer: 200
            model: root.scope.filteredWebApps
            currentIndex: root.selIdx
            delegate: Rectangle {
                id: appRow
                required property var modelData
                required property int index
                readonly property var entry: appRow.modelData
                readonly property bool isCurrent: root.selIdx === appRow.index
                readonly property string iconValue: appRow.entry ? String(appRow.entry.icon || "") : ""
                width: removeList.width
                height: 54
                radius: 12
                antialiasing: Theme.shapesAa
                color: appRow.isCurrent
                    ? Theme.withAlpha(Theme.textPrimary, 0.10)
                    : rowMouse.containsMouse ? Theme.withAlpha(Theme.textPrimary, 0.06) : "transparent"
                Behavior on color {
                    enabled: Theme.animationsEnabled
                    ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 12
                    Item {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter
                        IconImage {
                            anchors.centerIn: parent
                            visible: Util.iconSource(appRow.iconValue, "").length > 0
                            width: 26
                            height: 26
                            source: visible ? Util.iconSource(appRow.iconValue, "") : ""
                            asynchronous: true
                            implicitSize: Qt.size(52, 52)
                            mipmap: Theme.imageMipmap
                            smooth: Theme.imageSmooth
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: Util.iconSource(appRow.iconValue, "").length === 0
                            text: "󰖟"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(17)
                            color: appRow.isCurrent ? Theme.accent : Theme.textPrimary
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: (appRow.entry && (appRow.entry.displayName || appRow.entry.name)) || "—"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                            font.weight: Font.Medium
                            color: appRow.isCurrent ? Theme.accent : Theme.textPrimary
                            elide: Text.ElideRight
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: appRow.entry ? String(appRow.entry.url || "") : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: delText.implicitWidth + 22
                        implicitHeight: 28
                        radius: 14
                        color: delMouse.containsMouse ? Theme.error : "transparent"
                        border.color: delMouse.containsMouse ? Theme.error : Theme.divider
                        border.width: 1
                        antialiasing: Theme.shapesAa
                        Text {
                            id: delText
                            anchors.centerIn: parent
                            text: "Remove"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            color: delMouse.containsMouse ? Theme.onAccent : Theme.textSecondary
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selIdx = appRow.index
                                root.doRemove(appRow.entry ? appRow.entry.name : "")
                            }
                        }
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selIdx = appRow.index
                        root.ensureVisible()
                    }
                }
                z: -1
            }
            Column {
                anchors.centerIn: parent
                visible: removeList.count === 0
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰖟"
                    font.family: Theme.iconFontFamily
                    font.pixelSize: Theme.fs(26)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.scope.webAppLoading ? "Loading web apps…" : "No web apps installed"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    color: Theme.textMuted
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            }
            EdgeFade { flick: removeList }
            ScrollIndicator { flick: removeList }
            OverscrollSpring { flick: removeList }
        }

        // ---- status + log -----------------------------------------------
        Text {
            Layout.fillWidth: true
            visible: root.scope.webAppStatus.length > 0 || root.busy
            text: root.busy
                ? "◌ " + (root.scope.webAppStatus.length > 0 ? root.scope.webAppStatus : "Working…")
                : root.scope.webAppStatus
            color: root.busy ? Theme.textMuted
                : root.success ? Theme.accent
                : root.scope.webAppStatus.startsWith("✗") ? Theme.error : Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            font.weight: root.success ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
        }
        Rectangle {
            id: logBox
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            visible: root.scope.webAppLog.length > 0
            radius: 12
            color: Theme.panelCardLowest
            border.color: Theme.divider
            border.width: 1
            clip: true
            antialiasing: Theme.shapesAa
            Flickable {
                id: logFlick
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                contentWidth: width
                contentHeight: logText.implicitHeight
                Text {
                    id: logText
                    width: logFlick.width
                    text: root.scope.webAppLog
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    lineHeight: 1.3
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
            }
            EdgeFade { flick: logFlick; fadeColor: Theme.panelCardLowest }
            ScrollIndicator { flick: logFlick }
            OverscrollSpring { flick: logFlick }
            Connections {
                target: root.scope
                function onWebAppLogChanged() {
                    Qt.callLater(() => { logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height) })
                }
            }
        }
        // Keeps the footer at the bottom while no log fills the space.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.isAdd && !logBox.visible
        }

        // ---- footer ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.isAdd
                    ? (root.busy ? "Installing…" : "Tab: next page · Enter: install")
                    : (root.scope.filteredWebApps.length + (root.scope.filteredWebApps.length === 1 ? " result" : " results") + " · Enter: remove")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.textMuted
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Rectangle {
                visible: root.isAdd && (nameField.text.length > 0 || urlField.text.length > 0 || iconField.text.length > 0)
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: clearText.implicitWidth + 22
                implicitHeight: 30
                radius: 15
                color: clearMouse.containsMouse ? Theme.withAlpha(Theme.textPrimary, 0.08) : "transparent"
                border.color: Theme.divider
                border.width: 1
                antialiasing: Theme.shapesAa
                Text {
                    id: clearText
                    anchors.centerIn: parent
                    text: "Clear"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.textSecondary
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        nameField.text = ""
                        urlField.text = ""
                        iconField.text = ""
                        root.scope.clearWebAppStatus()
                        root.fieldIdx = 0
                        root.focusField()
                    }
                }
            }
            Rectangle {
                readonly property bool primaryEnabled: !root.busy && (root.isAdd
                    ? nameField.text.trim().length > 0 && urlField.text.trim().length > 0
                    : root.scope.filteredWebApps.length > 0)
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: primaryText.implicitWidth + 26
                implicitHeight: 32
                radius: 16
                color: root.isAdd ? Theme.accent : Theme.error
                opacity: primaryEnabled ? 1 : 0.45
                antialiasing: Theme.shapesAa
                Text {
                    id: primaryText
                    anchors.centerIn: parent
                    text: root.busy ? "Working…" : (root.isAdd ? "Install" : "Remove")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Medium
                    color: Theme.onAccent
                    antialiasing: Theme.textAa
                    renderType: Theme.textRenderType
                }
                MouseArea {
                    id: primaryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (parent.primaryEnabled) root.triggerPrimary()
                }
            }
        }
    }
}
