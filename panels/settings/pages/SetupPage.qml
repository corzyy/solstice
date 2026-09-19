pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../themes"
import "../../../ui" as Ui
import ".."

// Setup — quick access to the tools that configure the session.
// Date & Time, Language & Region, Keybinds and Update live on their own
// in-page sub-views (round back row), like PanelsPage; in compact mode the
// panel's header back returns to the category list from the main view only.
NexusControls.PageBase {
    id: root
    title: "Setup"
    showTitle: root.view === ""
    // SettingsPanel's FloatingWindow, forwarded to KeybindsPage for its
    // shortcuts inhibitor (key capture must not trigger Umbriel's own binds).
    property var hostWindow: null

    // Sub-view state: "" (main), "datetime", "language", "keybinds" or "update".
    property string view: ""
    readonly property string viewTitle: root.view === "datetime" ? "Date & Time"
        : root.view === "language" ? "Language & Region"
        : root.view === "keybinds" ? "Keybinds" : "Update"
    function back(): void { root.view = "" }

    // ---- main ------------------------------------------------------------
    NexusControls.SectionHeader { first: true; visible: root.view === ""; text: "System" }
    NexusControls.NavRow {
        visible: root.view === ""
        first: true
        icon: "󰃰"
        text: "Date & Time"
        subtext: "System clock, time zone, NTP"
        onClicked: root.view = "datetime"
    }
    NexusControls.NavRow {
        visible: root.view === ""
        last: true
        icon: "󰗊"
        text: "Language & Region"
        subtext: "System language, shell language, formats"
        onClicked: root.view = "language"
    }
    NexusControls.SectionHeader { visible: root.view === ""; text: "Shell" }
    NexusControls.NavRow {
        visible: root.view === ""
        first: true
        last: true
        icon: "󰌌"
        text: "Keybinds"
        subtext: "Shell actions and compositor shortcuts"
        onClicked: root.view = "keybinds"
    }
    NexusControls.SectionHeader { visible: root.view === ""; text: "Maintenance" }
    NexusControls.NavRow {
        visible: root.view === ""
        first: true
        last: true
        icon: "󰚰"
        text: "Update"
        subtext: "Update and restart the shell"
        onClicked: root.view = "update"
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

    // ---- date & time -----------------------------------------------------
    Loader {
        visible: root.view === "datetime"
        width: parent.width
        asynchronous: false
        sourceComponent: root.view === "datetime" ? datetimeComp : null
    }
    Component {
        id: datetimeComp
        DateTimePage { showTitle: false }
    }

    // ---- language & region -----------------------------------------------
    Loader {
        visible: root.view === "language"
        width: parent.width
        asynchronous: false
        sourceComponent: root.view === "language" ? languageComp : null
    }
    Component {
        id: languageComp
        LanguageRegionPage { showTitle: false }
    }

    // ---- keybinds --------------------------------------------------------
    Loader {
        visible: root.view === "keybinds"
        width: parent.width
        asynchronous: false
        sourceComponent: root.view === "keybinds" ? keybindsComp : null
    }
    Component {
        id: keybindsComp
        KeybindsPage { showTitle: false; hostWindow: root.hostWindow }
    }

    // ---- update ----------------------------------------------------------
    NexusControls.NavRow {
        visible: root.view === "update"
        first: true
        icon: "󰚰"
        text: "Shell update"
        subtext: "Reinstall from GitHub, keeping config/"
        onClicked: Quickshell.execDetached(["bash", "-c",
            "kitty --class solstice-shell-update --title \"Shell Update\" bash -lc 'bash \"$HOME/.config/quickshell/solstice/scripts/update-shell.sh\"; echo; echo \"--- Done ---\"; read -n1 -s' &"])
    }
    NexusControls.NavRow {
        visible: root.view === "update"
        last: true
        icon: "󰑐"
        text: "Reload shell"
        subtext: "Restart Quickshell to apply config changes"
        onClicked: Quickshell.reload(true)
    }

    NexusControls.Note {
        visible: root.view === "update"
        text: "The shell update clones the latest version over the install and keeps config/ and themes/snapshots/."
    }
}
