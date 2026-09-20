//@ pragma UseQApplication
//@ pragma IconTheme Papirus

import Quickshell
import "./style/themes"
import "./backend/services"
import QtQuick
import Quickshell.Io
import Quickshell.Services.Notifications
import "./shell/bar" as Bar
import "./shell/overlays" as Overlays
import "./shell/panels" as Panels
import "./shell/panels/controlcenter" as Cc
import "./shell/panels/settings" as Settings
import "./style/ui" as Ui

ShellRoot {
    id: root

    // LOGGING: persist every runtime error/warning to logs/errors.log
    // while the shell is running (backend/services/LogService.qml).
    QtObject { Component.onCompleted: LogService.start() }
    // PERF: instantiate the wallpaper backend at startup so its background
    // scan + thumbnail cache are warm before the first settings/carousel
    // open (singletons are lazy; without this the first open pays the scan).
    QtObject { Component.onCompleted: WallpaperService.refresh() }
    // SINGLE INSTANCE: a second shell for this config would fight the first
    // over the notification server and polkit agent DBus names. The guard
    // (backend/services/InstanceGuard.qml) checks whether an older live
    // instance exists and this one exits before registering any service.
    // The notification server below and the polkit agent are gated on
    // InstanceGuard.isPrimary for the same reason.
    Connections {
        target: InstanceGuard
        function onCheckedChanged() {
            if (InstanceGuard.checked && !InstanceGuard.isPrimary) {
                console.info("[solstice] another instance of this configuration is already running; exiting")
                Qt.quit()
            }
        }
    }
    Connections {
        target: Quickshell
        function onReloadFailed(errorString) { LogService.record("error", errorString, "reload") }
    }

    Process {
        id: wallpaperGuardProc
        command: ["bash", "-c", "echo"]
    }
    Timer {
        interval: 1200; running: true; repeat: false
        onTriggered: {
            if (wallpaperGuardProc.running) return
            let cmd = "pgrep -x swaybg >/dev/null 2>&1 && exit 0;"
            cmd += " WALL=\"$(cat ~/.config/quickshell/solstice/backend/config/current_wallpaper.txt 2>/dev/null | tr -d '\\r\\n')\";"
            cmd += " [ -f \"$WALL\" ] || WALL=\"$(cat ~/.cache/swaybg/current 2>/dev/null | tr -d '\\r\\n')\";"
            cmd += " [ -f \"$WALL\" ] || WALL=\"$(cat ~/.cache/awww/current 2>/dev/null | tr -d '\\r\\n')\";"
            cmd += " if [ ! -f \"$WALL\" ]; then for d in \"$HOME/Bilder/wallpapers\" \"$HOME/Pictures/wallpapers\" \"$HOME/Wallpapers\" \"${XDG_PICTURES_DIR:-$HOME/Pictures}/wallpapers\" \"$HOME/wallpapers\"; do if [ -d \"$d\" ]; then WALL=\"$(find \"$d\" -mindepth 1 -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tiff' \\) 2>/dev/null | sort | head -1)\"; [ -f \"$WALL\" ] && break; fi; done; fi;"
            cmd += " [ -f \"$WALL\" ] || exit 0;"
            cmd += " MODE=$(jq -r '.mode // \"fill\"' \"$HOME/.config/quickshell/solstice/backend/config/wallpaper_settings.json\" 2>/dev/null); case \"$MODE\" in stretch|fit|fill|center|tile) ;; *) MODE=fill;; esac;"
            cmd += " setsid nohup swaybg -i \"$WALL\" -m \"$MODE\" >/dev/null 2>&1 < /dev/null & disown; echo restored"
            wallpaperGuardProc.command = ["bash", "-c", cmd]
            wallpaperGuardProc.running = true
        }
    }

    // Notification server: only created once the instance guard confirmed
    // this is the primary shell. On a duplicate the Loader never activates
    // and the shell exits, so no registration is ever attempted (and no
    // "one is already registered" warning is logged).
    property var notifServer: notifLoader.item
    Loader {
        id: notifLoader
        active: InstanceGuard.isPrimary
        sourceComponent: notifComp
    }
    Component {
        id: notifComp
        NotificationServer {
            keepOnReload: true
            persistenceSupported: false
            bodySupported: true
            bodyMarkupSupported: true
            bodyHyperlinksSupported: true
            bodyImagesSupported: true
            imageSupported: true
            actionsSupported: true
            actionIconsSupported: true
            inlineReplySupported: true
            onNotification: notification => {
                // CRASH FIX: snapshot only plain types. Never store
                // notification.actions (QObjects) — dangling actions crash
                // CalendarPanel Repeaters in QV4::fromData on open.
                // HistoryService.add() sanitizes again as defense-in-depth.
                try {
                    HistoryService.add({
                        id: Number(notification.id),
                        appName: String(notification.appName || "Notification"),
                        appIcon: String(notification.appIcon || notification.image || ""),
                        summary: String(notification.summary || ""),
                        body: String(notification.body || ""),
                        urgency: Number(notification.urgency),
                        time: Date.now()
                    })
                } catch (e) { }
                if (Theme.dndEnabled) return
                notification.tracked = true
                root.expireOldTrackedNotifications()
            }
        }
    }

    function expireOldTrackedNotifications() {
        // PERF: coalesce burst expiry — 20 toasts used to alloc values[] +
        // expire per notification. One deferred pass per burst instead.
        if (_expireScheduled) return
        _expireScheduled = true
        Qt.callLater(() => {
            _expireScheduled = false
            try {
                const m = notifServer.trackedNotifications
                const vals = m ? m.values : []
                if (!vals || vals.length <= 5) return
                const extra = vals.length - 5
                for (let i = 0; i < extra; i++) {
                    try { vals[i].expire() } catch (e) { }
                }
            } catch (e) { }
        })
    }
    property bool _expireScheduled: false

    QtObject {
        id: panel
        readonly property int none: 0
        readonly property int calendar: 1
        // 2 was settings: no longer an exclusive panel (see settingsVisible).
        readonly property int systemTray: 3
        readonly property int controlCenter: 4
        readonly property int audio: 5
        readonly property int bluetoothMenu: 6
        readonly property int updatesMenu: 7
        readonly property int launcher: 8
        readonly property int power: 9
    }

    property int activePanel: panel.none
    // The settings app is a regular toplevel (FloatingWindow), not a
    // bar-anchored popout, so it gets its own flag and can stay open while
    // bar panels open, switch and close around it.
    property bool settingsVisible: false
    property string settingsSection: "wallpaper"
    // Screenshot tool (shell/overlays/ScreenshotUI.qml): its own flag like
    // settings — a transient overlay, not part of the exclusive panel state.
    property bool screenshotVisible: false
    // Anchor mode of the open launcher: false = bar icon (under the icon at
    // the left), true = SUPER+SPACE (centred under the bar).
    property bool launcherCentered: false

    readonly property bool calendarVisible: activePanel === panel.calendar
    readonly property bool systemTrayVisible: activePanel === panel.systemTray
    readonly property bool controlCenterVisible: activePanel === panel.controlCenter
    readonly property bool audioVisible: activePanel === panel.audio
    readonly property bool bluetoothMenuVisible: activePanel === panel.bluetoothMenu
    readonly property bool updatesMenuVisible: activePanel === panel.updatesMenu
    readonly property bool launcherVisible: activePanel === panel.launcher
    readonly property bool powerVisible: activePanel === panel.power
    // Drill-ins that open OVER the control center (Android-QS style): the CC
    // window stays mapped as the dimmed backdrop under the sub-panel, and the
    // sub-panel morphs out of the clicked tile/button (see style/ui/PanelMorph
    // overlay runs and CaelestiaPopout._tryMorphBack).
    readonly property bool drillInVisible: audioVisible || bluetoothMenuVisible || updatesMenuVisible
    readonly property bool ccUnderlay: drillInVisible
    // Control-center backdrop state, computed straight from `activePanel`:
    // 0 = closed, 1 = plain open, 2 = open as the drill-in backdrop. The CC
    // popout used to chain this through controlCenterVisible/ccUnderlay, and
    // during the binding cascade of a back-switch it could read a stale
    // value for a tick — `popped` dipped false, the CC curtain started
    // closing and re-opened (the visible flick on close). Reading the plain
    // activePanel value inside one binding can never observe an in-between.
    function ccViewState(): int {
        if (activePanel === panel.controlCenter) return 1
        if (activePanel === panel.audio || activePanel === panel.bluetoothMenu || activePanel === panel.updatesMenu) return 2
        return 0
    }

    property bool _anchorsDirty: false
    function refreshBarAnchors() {
        if (_anchorsDirty) return
        _anchorsDirty = true
        Qt.callLater(() => {
            _anchorsDirty = false
            Theme.refreshBarAnchors()
        })
    }

    // Close the bar popouts (only one is open at a time). The settings
    // window is independent and survives; use hideSettings() for it.
    // clear(), not finish(): an open overlay drill-in keeps its origin button
    // registered and releases it when its return run has dissolved into it.
    function closePanels() {
        Ui.PanelMorph.clear()
        activePanel = panel.none
    }

    // Geteilte Loader-Hülle für Panels (10x identisches active/async-Muster).
    // Der Loader lebt während der Exit-Animation weiter (hold): sonst würde
    // active:false das Panel sofort zerstören und die Close-Animation wäre
    // nie sichtbar. Ohne Animationen ist panelHideDelay 0, also exakt wie
    // vorher. hold wird bewusst imperativ gesetzt — ein Binding wie
    // (shown || item._winVisible) feuert über Loader.item-Erzeugung zurück
    // und meldet "Binding loop detected for property active".
    component PanelLoader: Loader {
        required property bool shown
        property bool hold: false
        active: shown || hold
        asynchronous: true
        Timer {
            id: holdTimer
            interval: Theme.panelHideDelay
            repeat: false
            onTriggered: parent.hold = false
        }
        onShownChanged: {
            if (shown) {
                hold = false
                holdTimer.stop()
            } else if (item && Theme.animationsEnabled) {
                hold = true
                holdTimer.restart()
            }
        }
    }

    // Name -> Panel-Enum (eine Tabelle für IPC-Namen und Modul-IDs statt
    // dreier kopierter Zuordnungsstellen: IpcHandler, onClosePanel).
    // Settings has no entry: it is not part of the exclusive panel state.
    readonly property var panelForName: ({
        calendar: panel.calendar,
        systemtray: panel.systemTray,
        controlcenter: panel.controlCenter,
        audio: panel.audio,
        bluetoothmenu: panel.bluetoothMenu, updatesmenu: panel.updatesMenu,
        launcher: panel.launcher, power: panel.power
    })
    // Bar-Modul-IDs weichen teils ab (clock->calendar).
    readonly property var panelForModule: ({
        clock: panel.calendar,
        systemtray: panel.systemTray,
        controlcenter: panel.controlCenter,
        launcher: panel.launcher
    })

    function toggleNamedPanel(name: string): void {
        const p = panelForName[name]
        if (p !== undefined) toggleExclusive(p)
    }
    function showNamedPanel(name: string): void {
        const p = panelForName[name]
        if (p !== undefined) openPanel(p)
    }

    // Bar panels that take part in the cross-panel morph (style/ui/PanelMorph).
    // The ids match each panel popout's `morphId` (= BarAnchor moduleId).
    // Settings is not bar-anchored and keeps its own run.
    readonly property var panelMorphId: ({
        [panel.calendar]: "clock",
        [panel.systemTray]: "systemtray",
        [panel.controlCenter]: "controlcenter",
        [panel.audio]: "audio",
        [panel.bluetoothMenu]: "bluetoothmenu",
        [panel.updatesMenu]: "updatesmenu",
        [panel.launcher]: "launcher"
    })

    // Depth on the control-center drill-in axis: bar panels are lateral (0),
    // the CC is level 1, its drill-ins level 2. The content choreography
    // slides deeper (+) or back (-) along that axis; lateral switches (bar
    // panel <-> bar panel) only crossfade.
    function panelDepth(p: int): int {
        if (p === panel.controlCenter) return 1
        if (p === panel.audio || p === panel.bluetoothMenu || p === panel.updatesMenu) return 2
        return 0
    }

    // Start the handoff before activePanel flips: the outgoing popout must
    // already know it is the source when its `shown` turns false. Switches
    // without a bar-to-bar pair just cancel any stale handoff. This is
    // strictly a panel-to-panel transition: opening the first panel (none
    // open) always plays the plain popout open, never the handoff.
    function beginPanelMorph(to: int): void {
        // Back into the control center: it is already on screen under the
        // drill-in (ccUnderlay), so there is no card handoff — the drill-in
        // shrinks back into its origin button on its own (CaelestiaPopout
        // _tryMorphBack). Handoff state is dropped, but the overlay source
        // stays registered for the return crossfade.
        if (to === panel.controlCenter && root.ccUnderlay) {
            Ui.PanelMorph.clear()
            return
        }
        const toId = panelMorphId[to]
        // Button-anchored drill-in: the CC published the clicked rect; the
        // incoming panel grows out of it while the CC stays open behind.
        if (toId !== undefined) {
            const origin = Ui.PanelMorph.takeOrigin(toId)
            if (origin) {
                Ui.PanelMorph.beginOverlay(toId, origin, 1)
                return
            }
            // Drill-in without a published button rect (IPC/script open): the
            // CC stays behind, so there is no card to hand over — the
            // sub-panel plays its plain open over the dimmed CC instead.
            if (root.activePanel === panel.controlCenter
                    && (to === panel.audio || to === panel.bluetoothMenu || to === panel.updatesMenu)) {
                Ui.PanelMorph.finish()
                return
            }
        }
        if (root.activePanel === panel.none) {
            Ui.PanelMorph.finish()
            return
        }
        const from = panelMorphId[root.activePanel]
        if (from === undefined || toId === undefined || from === toId) {
            Ui.PanelMorph.finish()
            return
        }
        const fromDepth = panelDepth(root.activePanel)
        const toDepth = panelDepth(to)
        Ui.PanelMorph.begin(from, toId, toDepth === fromDepth ? 0 : (toDepth > fromDepth ? 1 : -1))
    }

    // The lockscreen window is mapped permanently (so a merge lock never
    // loses its first frames) and therefore sits BELOW panels mapped later.
    // Closed while locked and no panel may open: otherwise a panel opened
    // from a global keybind would cover the lock AND steal its exclusive
    // keyboard focus.
    function openPanel(p: int) {
        if (lockscreen.locked) return
        if (root.screenshotVisible) root.hideScreenshot()
        refreshBarAnchors()
        beginPanelMorph(p)
        activePanel = p
    }

    function toggleExclusive(p: int) {
        if (lockscreen.locked) return
        if (root.screenshotVisible) root.hideScreenshot()
        refreshBarAnchors()
        if (activePanel !== p) beginPanelMorph(p)
        activePanel = (activePanel === p) ? panel.none : p
    }

    Connections {
        target: lockscreen
        function onLockedChanged() {
            if (lockscreen.locked) {
                root.hideScreenshot()
                root.closePanels()
            }
        }
    }

    // Launcher anchor mode is decided by the entry point (bar icon click vs
    // SUPER+SPACE) and must be set before the panel starts its morph/open run.
    function toggleLauncher(centered: bool): void {
        root.launcherCentered = centered
        root.toggleExclusive(panel.launcher)
    }
    function showLauncher(centered: bool): void {
        root.launcherCentered = centered
        root.openPanel(panel.launcher)
    }
    function hideLauncher(): void {
        if (root.launcherVisible) root.closePanels()
    }

    // RAM: dead aliases removed (settingsPanel was never read).
    // Panel visibility is derived from a single activePanel int to avoid
    // per-panel booleans fanning out through TopBar.

    Bar.TopBar {
        calendarOpen: root.calendarVisible
        trayOpen: root.systemTrayVisible
        controlCenterOpen: root.controlCenterVisible
        launcherOpen: root.launcherVisible
        anyPanelOpen: root.activePanel !== panel.none

        onToggleCalendar: root.toggleExclusive(panel.calendar)
        onToggleSystemTray: root.toggleExclusive(panel.systemTray)
        onToggleControlCenter: root.toggleExclusive(panel.controlCenter)
        onToggleLauncher: root.toggleLauncher(false)

        // CPU: table-driven close — replaces if/else chain so
        // closePanel is O(1) and cannot drift out of sync with panel enum.
        // PERF: switch instead of per-signal object alloc + 10 prop reads.
        onClosePanel: moduleId => {
            const p = panelForModule[moduleId]
            if (p !== undefined && root.activePanel === p) root.closePanels()
        }
    }

    function openSettings(section: string): void {
        let s = (section || "wallpaper").trim() || "wallpaper"
        // Legacy ids: bar/modules and notif all point at the Panels page now
        // (notifications + OSDs are a Panels sub-page); theming now lives in
        // the Apps page's library.
        if (s === "bar" || s === "modules" || s === "notif") s = "panels"
        else if (s === "theming") s = "apps"
        let valid = ["wallpaper", "global", "umbriel", "audio", "apps", "panels", "network", "bluetooth", "about", "setup"]
        if (valid.indexOf(s) === -1) s = "wallpaper"
        settingsSection = s
        if (settingsLoader.item) settingsLoader.item.section = s
        settingsVisible = true
    }
    function hideSettings(): void {
        settingsVisible = false
    }
    function toggleSettings(): void {
        if (settingsVisible) hideSettings()
        else openSettings(settingsSection || "wallpaper")
    }

    // Screenshot tool. Opening closes the bar popouts so they can't cover
    // the shot (the pill itself unmaps before the capture runs).
    function showScreenshot(): void {
        if (lockscreen.locked) return
        root.closePanels()
        root.screenshotVisible = true
    }
    function hideScreenshot(): void {
        root.screenshotVisible = false
    }
    function toggleScreenshot(): void {
        if (root.screenshotVisible) root.hideScreenshot()
        else root.showScreenshot()
    }

    IpcHandler {
        target: "dnd"
        function toggle(): string { Theme.toggleDnd(); return "dnd=" + Theme.dndEnabled }
        function enable(): string { Theme.setDndEnabled(true); return "dnd=true" }
        function disable(): string { Theme.setDndEnabled(false); return "dnd=false" }
        function status(): string { return "dnd=" + Theme.dndEnabled }
    }
    IpcHandler {
        target: "gamemode"
        function toggle(): string { Theme.toggleGamemode(); return "gamemode=" + Theme.gamemodeEnabled }
        function enable(): string { Theme.setGamemodeEnabled(true); return "gamemode=true" }
        function disable(): string { Theme.setGamemodeEnabled(false); return "gamemode=false" }
        function status(): string { return "gamemode=" + Theme.gamemodeEnabled }
    }
    IpcHandler {
        target: "notif"
        function count(): string {
            try {
                let h = HistoryService.history.length
                let t = 0
                try { t = notifServer && notifServer.trackedNotifications ? notifServer.trackedNotifications.values.length : 0 } catch (e) { }
                return "history=" + h + " tracked=" + t
            } catch (e) { return "history=? tracked=?" }
        }
        function list(): string {
            try {
                let hist = HistoryService.history.slice(-10)
                let out = hist.map(h => (h.appName || "?") + ": " + (h.summary || ""))
                return out.length > 0 ? out.join("\n") : "(empty)"
            } catch (e) { return "(error)" }
        }
    }

    IpcHandler {
        target: "solstice"
        function state(): string {
            return "calendar=" + root.calendarVisible
            + " settings=" + root.settingsVisible
            + " systemtray=" + root.systemTrayVisible
            + " controlcenter=" + root.controlCenterVisible
            + " audio=" + root.audioVisible
            + " bluetoothmenu=" + root.bluetoothMenuVisible
            + " updatesmenu=" + root.updatesMenuVisible
            + " launcher=" + root.launcherVisible
            + " power=" + root.powerVisible
        }
        function toggleCalendar(): void { root.toggleNamedPanel("calendar") }
        function showCalendar(): void { root.showNamedPanel("calendar") }
        function hideCalendar(): void { root.closePanels() }
        function toggleControlCenter(): void { root.toggleNamedPanel("controlcenter") }
        function showControlCenter(): void { root.showNamedPanel("controlcenter") }
        function hideControlCenter(): void { root.closePanels() }
        function toggleAudio(): void { root.toggleNamedPanel("audio") }
        function showAudio(): void { root.showNamedPanel("audio") }
        function hideAudio(): void { root.closePanels() }
        function toggleBluetoothMenu(): void { root.toggleNamedPanel("bluetoothmenu") }
        function showBluetoothMenu(): void { root.showNamedPanel("bluetoothmenu") }
        function hideBluetoothMenu(): void { root.closePanels() }
        function toggleUpdatesMenu(): void { root.toggleNamedPanel("updatesmenu") }
        function showUpdatesMenu(): void { root.showNamedPanel("updatesmenu") }
        function hideUpdatesMenu(): void { root.closePanels() }
        function toggleSystemTray(): void { root.toggleNamedPanel("systemtray") }
        function showSystemTray(): void { root.showNamedPanel("systemtray") }
        function hideSystemTray(): void { root.closePanels() }
        // Shortcut entry point: the launcher opens centred under the bar.
        // Pass centered=false to anchor it under the bar OS icon instead.
        function toggleLauncher(centered: bool): void { root.toggleLauncher(centered) }
        function showLauncher(centered: bool): void { root.showLauncher(centered) }
        function hideLauncher(): void { root.hideLauncher() }
        function togglePower(): void { root.toggleNamedPanel("power") }
        function showPower(): void { root.showNamedPanel("power") }
        function hidePower(): void { root.closePanels() }
        function toggleSettings(): void { root.toggleSettings() }
        function showSettings(s: string): void { root.openSettings(s || "wallpaper") }
        function hideSettings(): void { root.hideSettings() }
        function toggleScreenshot(): void { root.toggleScreenshot() }
        function showScreenshot(): void { root.showScreenshot() }
        function hideScreenshot(): void { root.hideScreenshot() }
        function reload(): void { Quickshell.reload(true) }
    }

    Overlays.Notifications {
        notifServer: root.notifServer
    }

    PanelLoader { id: calLoader; shown: root.calendarVisible; sourceComponent: calComp }
    Component {
        id: calComp
        Panels.CalendarPanel {
            showCalendar: root.calendarVisible
            notifServer: root.notifServer
            onDismissed: root.closePanels()
        }
    }

    PanelLoader { id: trayLoader; shown: root.systemTrayVisible; sourceComponent: trayComp }
    Component {
        id: trayComp
        Panels.SystemTrayPanel {
            showTray: root.systemTrayVisible
            onDismissed: root.closePanels()
        }
    }

    PanelLoader { id: launcherLoader; shown: root.launcherVisible; sourceComponent: launcherComp }
    Component {
        id: launcherComp
        Panels.LauncherPanel {
            showLauncher: root.launcherVisible
            centered: root.launcherCentered
            onDismissed: root.closePanels()
            // Built-in launcher Settings entries (no .desktop): close the
            // launcher, then open the settings window on the requested
            // section (empty = the last shown one).
            onSettingsRequested: section => {
                root.closePanels()
                root.openSettings(section.length > 0 ? section : (root.settingsSection || "wallpaper"))
            }
        }
    }

    PanelLoader {
        id: ccLoader
        // Stays shown while a drill-in is open: the sub-panel opens over the
        // CC, which keeps rendering as the dimmed backdrop (behind=true).
        shown: root.controlCenterVisible || root.ccUnderlay
        sourceComponent: ccComp
    }
    Component {
        id: ccComp
        Cc.ControlCenterPanel {
            popped: root.ccViewState() !== 0
            behind: root.ccViewState() === 2
            onDismissed: root.closePanels()
            onSettingsRequested: {
                root.closePanels()
                root.openSettings("wallpaper")
            }
            onAudioRequested: root.openPanel(panel.audio)
            onBluetoothRequested: root.openPanel(panel.bluetoothMenu)
            onUpdatesRequested: root.openPanel(panel.updatesMenu)
            onPowerRequested: root.toggleExclusive(panel.power)
        }
    }

    // Updates drill-in: opened from the CC updates tile, reuses the
    // standalone update-center body in back-header mode, anchored to the
    // control center so the card morphs out of / back into the CC card.
    PanelLoader { id: updMenuLoader; shown: root.updatesMenuVisible; sourceComponent: updMenuComp }
    Component {
        id: updMenuComp
        Panels.UpdateCenterPanel {
            showUpdates: root.updatesMenuVisible
            showBack: true
            panelModuleId: "updatesmenu"
            anchorModuleId: "controlcenter"
            onDismissed: root.closePanels()
            onBackRequested: root.openPanel(panel.controlCenter)
        }
    }

    // Bluetooth drill-in: opened from the CC bluetooth tile, reuses the
    // standalone BluetoothPanel body in back-header mode, anchored to the
    // control center so the card morphs out of / back into the CC card.
    PanelLoader { id: btMenuLoader; shown: root.bluetoothMenuVisible; sourceComponent: btMenuComp }
    Component {
        id: btMenuComp
        Panels.BluetoothPanel {
            showBluetooth: root.bluetoothMenuVisible
            showBack: true
            panelModuleId: "bluetoothmenu"
            anchorModuleId: "controlcenter"
            onDismissed: root.closePanels()
            onBackRequested: root.openPanel(panel.controlCenter)
        }
    }

    // Audio drill-in: opened from the CC volume block, morphs out of the CC
    // card. Back returns to the control center (reverse handoff via
    // beginPanelMorph); Escape/outside click closes everything like the CC's
    // other drill-ins.
    PanelLoader { id: audioLoader; shown: root.audioVisible; sourceComponent: audioComp }
    Component {
        id: audioComp
        Cc.AudioPanel {
            showAudio: root.audioVisible
            onDismissed: root.closePanels()
            onBackRequested: root.openPanel(panel.controlCenter)
        }
    }

    // Power menu: opened from the CC header's power button or its IPC. A
    // standalone Android-style modal (dimmed + compositor-blurred backdrop,
    // centred card), deliberately NOT a CC drill-in: no morph, no anchor.
    // Lock is raised here (the lockscreen overlay is a resident surface,
    // not part of the panel state); the session actions
    // (logout/restart/shutdown) run inside the panel.
    PanelLoader { id: powerLoader; shown: root.powerVisible; sourceComponent: powerComp }
    Component {
        id: powerComp
        Panels.PowerPanel {
            showPower: root.powerVisible
            onDismissed: root.closePanels()
            onLockRequested: {
                // Hand the open card's pose to the lockscreen before the
                // menu starts closing: the lock box morphs out of it.
                const rect = powerLoader.item ? powerLoader.item.cardRect : null
                root.closePanels()
                lockscreen.lockFrom(rect)
            }
        }
    }

    PanelLoader {
        id: settingsLoader
        shown: root.settingsVisible
        sourceComponent: settingsComp
        onLoaded: if (item) item.section = root.settingsSection
    }
    Component {
        id: settingsComp
        Settings.SettingsPanel {
            showSettings: root.settingsVisible
            Component.onCompleted: section = root.settingsSection
            onDismissed: root.hideSettings()
        }
    }

    // NOTE: VolumeOSD/Lockscreen/Polkit stay resident on purpose:
    // they are trigger listeners (Theme.volumeOsdTrigger/layoutOsdTrigger/
    // themeOsdTrigger, lock IPC, polkit agent). Gating them on a visible flag would break
    // the trigger itself. Their windows already render nothing when hidden
    // (_winVisible=false -> visible:false), so steady-state cost is one
    // Scope + timers, not a scene tree. Real RAM wins are the 14 panel
    // Loaders above, which ARE correctly gated.
    Overlays.VolumeOSD { }
    // FPS debug overlay (Setup > Experimental). Resident Scope, but its
    // window and frame ticker only run while Theme.debugFpsEnabled is on.
    Overlays.DebugOverlay { }
    Overlays.ScreenshotUI {
        showScreenshot: root.screenshotVisible
        onDismissed: root.hideScreenshot()
    }
    Overlays.Lockscreen { id: lockscreen }

    Overlays.Polkit { }
}
