pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../themes"
import "../ui" as Ui

Scope {
    id: osdScope

    readonly property int barT: Theme.barThickness
    readonly property string barPos: Theme.barPosition
    readonly property int quattroPad: 10
    readonly property int quattroGap: 10
    readonly property int quattroIconGap: 16
    readonly property int quattroBarWidth: 96
    readonly property int quattroBottomMargin: 67
    readonly property string quattroMessage: displayMuted ? "Muted" : displayPct + "%"
    // Lautstärkestufe 0-3 (eine Schwellen-Tabelle für beide Icon-Sets).
    function volumeTier(pct: int, muted: bool): int {
        if (muted || pct <= 0) return 0
        if (pct <= 33) return 1
        if (pct <= 66) return 2
        return 3
    }
    readonly property var quattroIcons: ["", "", "", ""]
    function iconForQuattro(pct: int, muted: bool): string {
        return quattroIcons[volumeTier(pct, muted)]
    }

    property PwNode sink: Pipewire.defaultAudioSink
    property bool sinkReady: sink && sink.ready && sink.audio
    // Same as VolumeService: without tracking the node stays unbound and
    // volPct/isMuted never update (OSD stuck on slow shell polling).
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    property int volPct: sinkReady ? Math.round(sink.audio.volume * 100) : 0
    property bool isMuted: sinkReady ? sink.audio.muted : false
    property string sinkIdentity: sink ? (sink.name + ":" + sink.id) : ""

    property bool osdVisible: false
    // OSD kinds share the card: volume changes show icon/bar/value, layout
    // switches show the layout glyph + name, theme applies show a palette +
    // label/detail.
    property string osdKind: "volume"
    readonly property bool volumeMode: osdKind === "volume"
    readonly property bool layoutMode: osdKind === "layout"
    readonly property bool themeMode: osdKind === "theme"
    property string layoutName: ""
    readonly property string layoutMessage: layoutName.length > 0
        ? layoutName.substring(0, 1).toUpperCase() + layoutName.substring(1)
        : ""
    readonly property string layoutGlyph: ""
    property string themeLabel: ""
    property string themeDetail: ""
    property bool themeError: false
    readonly property string themeMessage: themeLabel + (themeDetail.length > 0
        ? (themeLabel.length > 0 ? " (" + themeDetail + ")" : themeDetail) : "")
    readonly property string themeGlyph: "󰏘"
    property bool _winVisible: osdVisible
    // The window lingers for the fade-out duration so the exit run stays
    // visible (0 with animations off — instant, as before). Must match the
    // Ui.Motion FadeThrough run below (durMotionFadeThrough), not the
    // effects token: a shorter linger cut the fade mid-flight.
    Timer { id: osdHideTimer; interval: Theme.durMotionFadeThrough; repeat: false; onTriggered: if (!osdScope.osdVisible) osdScope._winVisible = false }
    onOsdVisibleChanged: {
        if (osdVisible) { _winVisible = true; osdHideTimer.stop() }
        else osdHideTimer.restart()
    }
    property bool inited: false
    property int lastPct: -1
    property bool lastMuted: false
    property bool sinkSwitchGuard: false
    Timer { id: sinkSwitchClear; interval: 400; repeat: false; onTriggered: osdScope.sinkSwitchGuard = false }

    // Senkenwechsel-Snapshot (ein Pfad statt 2x kopierter Guard-Snapshots).
    function snapshotSinkState(): void {
        sinkSwitchGuard = true
        sinkSwitchClear.restart()
        lastPct = volPct
        lastMuted = isMuted
    }

    onSinkIdentityChanged: {
        if (!inited) return
        snapshotSinkState()
    }
    onSinkReadyChanged: {
        if (!inited) return
        if (sinkReady) snapshotSinkState()
    }

    Timer {
        id: initTimer
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
            osdScope.inited = true
            osdScope.lastPct = osdScope.volPct
            osdScope.lastMuted = osdScope.isMuted
        }
    }

    Timer {
        id: hideTimer
        interval: 1600
        repeat: false
        onTriggered: osdScope.osdVisible = false
    }

    function showVolume() {
        // Explicit triggers (keys, wheel, sliders, IPC) must show immediately
        // even during the startup grace period — `inited` only gates the
        // *automatic* change handlers so boot doesn't flash the OSD.
        if (!Theme.osdVolumeEnabled) return
        osdKind = "volume"
        osdVisible = true
        hideTimer.interval = Theme.osdDuration
        hideTimer.restart()
    }

    // Layout-switch notification (UmbrielService -> Theme.triggerLayoutOsd).
    function showLayout(name: string) {
        if (!Theme.osdLayoutEnabled) return
        let l = ("" + (name || "")).trim()
        if (l.length === 0) return
        layoutName = l
        osdKind = "layout"
        osdVisible = true
        hideTimer.interval = Theme.osdDuration
        hideTimer.restart()
    }

    // Theme-switch notification (ThemeEngine -> Theme.triggerThemeOsd).
    function showTheme(label: string, detail: string, isError: bool) {
        if (!Theme.osdThemeEnabled) return
        let l = ("" + (label || "")).trim()
        let d = ("" + (detail || "")).trim()
        if (l.length === 0 && d.length === 0) return
        themeLabel = l
        themeDetail = d
        themeError = !!isError
        osdKind = "theme"
        osdVisible = true
        hideTimer.interval = Theme.osdDuration
        hideTimer.restart()
    }

    onVolPctChanged: {
        if (!inited) return
        if (pollOverride && volPct === fallbackPct && isMuted === fallbackMuted) pollOverride = false
        if (sinkSwitchGuard) { lastPct = volPct; return }
        if (volPct !== lastPct) {
            if (lastPct !== -1) showVolume()
            lastPct = volPct
        }
    }
    onIsMutedChanged: {
        if (!inited) return
        if (pollOverride && isMuted === fallbackMuted && volPct === fallbackPct) pollOverride = false
        if (sinkSwitchGuard) { lastMuted = isMuted; return }
        if (isMuted !== lastMuted) {
            showVolume()
            lastMuted = isMuted
        }
    }

    Connections {
        target: Theme
        function onVolumeOsdTriggerChanged() { osdScope.showVolume() }
        function onLayoutOsdTriggerChanged() { osdScope.showLayout(Theme.layoutOsdName) }
        function onThemeOsdTriggerChanged() { osdScope.showTheme(Theme.themeOsdLabel, Theme.themeOsdDetail, Theme.themeOsdError) }
    }

    Process {
        id: eventMonProc
        running: true
        command: ["bash", "-c", "command -v pw-mon >/dev/null 2>&1 && exec pw-mon || sleep 2147483647"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => { if (!externalDebounce.running) externalDebounce.restart() }
        }
        onExited: (code, status) => eventMonRestart.restart()
    }
    Timer { id: eventMonRestart; interval: 1000; repeat: false; onTriggered: if (!eventMonProc.running) eventMonProc.running = true }
    Timer {
        id: externalDebounce
        interval: 70
        repeat: false
        onTriggered: { if (!pollProc.running) pollProc.running = true }
    }

    Connections {
        target: osdScope.sink && osdScope.sink.audio ? osdScope.sink.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (!osdScope.inited || osdScope.sinkSwitchGuard) return
            if (!osdScope.sinkReady) return
            let p = Math.round(osdScope.sink.audio.volume * 100)
            if (p !== osdScope.lastPct) osdScope.showVolume()
        }
        function onMutedChanged() {
            if (!osdScope.inited || osdScope.sinkSwitchGuard) return
            if (!osdScope.sinkReady) return
            if (osdScope.sink.audio.muted !== osdScope.lastMuted) osdScope.showVolume()
        }
    }

    property bool pollOverride: false
    Process {
        id: pollProc
        command: ["bash", "-c", Quickshell.shellDir + "/scripts/volume.sh get 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = (text || "").trim()
                if (txt.length === 0) return
                let muted = txt.toLowerCase() === "muted"
                let pct = -1
                if (txt.endsWith("%")) {
                    let n = parseInt(txt)
                    if (!isNaN(n)) pct = n
                }
                if (pct < 0 && !muted) return
                if (muted) pct = osdScope.displayPct
                if (pct !== osdScope.lastPct || muted !== osdScope.lastMuted) {
                    if (!osdScope.sinkReady) {
                        osdScope.fallbackPct = pct
                        osdScope.fallbackMuted = muted
                        osdScope.showVolume()
                    } else if (pct !== osdScope.volPct || muted !== osdScope.isMuted) {
                        osdScope.fallbackPct = pct
                        osdScope.fallbackMuted = muted
                        osdScope.pollOverride = true
                        osdScope.showVolume()
                        pollOverrideClearTimer.restart()
                    }
                    osdScope.lastPct = pct
                    osdScope.lastMuted = muted
                }
            }
        }
    }
    Timer { id: pollOverrideClearTimer; interval: 1200; repeat: false; onTriggered: osdScope.pollOverride = false }
    Timer {
        id: pollTimer
        // STABILITY: back off to 30s after 3 empty probes (was 5s forever
        // when PipeWire is broken, forking volume.sh endlessly while hidden).
        property int fails: 0
        interval: fails >= 3 ? 30000 : 5000
        running: osdScope.osdVisible || !osdScope.sinkReady
        repeat: true
        triggeredOnStart: false
        onTriggered: if (!pollProc.running && osdScope.inited) pollProc.running = true
    }

    IpcHandler {
        target: "volumeOsd"
        function show(): void { osdScope.showVolume() }
        function status(): string { return "visible=" + osdScope.osdVisible + " volPct=" + osdScope.volPct + " displayPct=" + osdScope.displayPct + " displayMuted=" + osdScope.displayMuted + " lastPct=" + osdScope.lastPct + " inited=" + osdScope.inited }
        function trigger(pct: int, muted: bool): void {
            if (!osdScope.sinkReady) {
                fallbackPct = pct
                fallbackMuted = muted
                osdScope.showVolume()
            }
        }
    }
    IpcHandler {
        target: "osd"
        function showVolume(): void { osdScope.showVolume() }
        function showLayout(name: string): void { osdScope.showLayout(name) }
        function showTheme(label: string, detail: string, isError: bool): void { osdScope.showTheme(label, detail, isError) }
        function status(): string { return "visible=" + osdScope.osdVisible + " kind=" + (osdScope.layoutMode ? "layout:" + osdScope.layoutMessage : osdScope.themeMode ? "theme:" + osdScope.themeMessage : "volume") + " vol=" + osdScope.displayPct + (osdScope.displayMuted ? " muted" : "") }
    }
    property int fallbackPct: 0
    property bool fallbackMuted: false
    property int displayPct: pollOverride ? fallbackPct : (sinkReady ? volPct : fallbackPct)
    property bool displayMuted: pollOverride ? fallbackMuted : (sinkReady ? isMuted : fallbackMuted)

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: osdScope._winVisible && Theme.isPrimaryScreen(modelData)
            color: "transparent"
            exclusiveZone: 0
            mask: Region { item: quattroWrapper }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "volumeosd"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; left: true; right: true; bottom: true }

            Item {
                id: quattroWrapper
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: osdScope.quattroBottomMargin
                width: quattroCard.width
                height: quattroCard.height
                // OSD show/hide: M3 fade through (fade + settle from 92%),
                // rise coupled to the driver so it can never desync.
                Ui.Motion {
                    id: osdMotion
                    active: osdScope.osdVisible
                    pattern: Ui.Motion.FadeThrough
                }
                opacity: osdMotion.opacity
                scale: osdMotion.scale
                transformOrigin: Item.Bottom
                transform: Translate { y: (1 - osdMotion.opacity) * 12 }

                Rectangle {
                    id: quattroCard
                    // PERF: fixed icon/value widths (was 3x TextMetrics with
                    // tightBoundingRect recomputed per % tick during drag).
                    readonly property int iconW: 24
                    readonly property int valueW: 52
                    width: 2 + osdScope.quattroPad + iconW + osdScope.quattroIconGap + osdScope.quattroBarWidth + osdScope.quattroGap + valueW + osdScope.quattroPad + 2
                    height: 2 + osdScope.quattroPad + 20 + osdScope.quattroPad + 2
                    radius: Theme.cornerRadius
                    color: Theme.panelWindowBg
                    border.color: Theme.panelBorderColor
                    border.width: 2
                    antialiasing: Theme.shapesAa

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 2 + osdScope.quattroPad
                        anchors.rightMargin: 2 + osdScope.quattroPad
                        anchors.topMargin: 2 + osdScope.quattroPad
                        anchors.bottomMargin: 2 + osdScope.quattroPad
                        spacing: osdScope.quattroGap
                        Item {
                            width: quattroCard.iconW + osdScope.quattroIconGap - osdScope.quattroGap
                            height: parent.height
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: osdScope.themeMode ? osdScope.themeGlyph : osdScope.layoutMode ? osdScope.layoutGlyph : osdScope.iconForQuattro(osdScope.displayPct, osdScope.displayMuted)
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(20)
                                color: osdScope.themeMode && osdScope.themeError ? Theme.errorColor : Theme.textPrimary
                                textFormat: Text.PlainText
                            }
                        }
                        Rectangle {
                            visible: osdScope.volumeMode
                            width: osdScope.quattroBarWidth
                            height: 6
                            radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.withAlpha(Theme.textPrimary, 0.45)
                            antialiasing: Theme.shapesAa
                            Rectangle {
                                height: parent.height
                                width: parent.width * Math.max(0, Math.min(1, osdScope.displayPct / 100))
                                radius: 3
                                color: osdScope.displayMuted ? Theme.errorColor : Theme.accent
                                antialiasing: Theme.shapesAa
                                // Fill glides between steps instead of jumping.
                                Behavior on width { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects } }
                                Behavior on color { enabled: Theme.animationsEnabled; ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects } }
                            }
                        }
                        Text {
                            visible: osdScope.volumeMode
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            width: quattroCard.valueW
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: osdScope.quattroMessage
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(14)
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }
                        Text {
                            visible: osdScope.layoutMode
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            width: osdScope.quattroBarWidth + osdScope.quattroGap + quattroCard.valueW
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignLeft
                            text: osdScope.layoutMessage
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(14)
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }
                        Text {
                            visible: osdScope.themeMode
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            width: osdScope.quattroBarWidth + osdScope.quattroGap + quattroCard.valueW
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignLeft
                            text: osdScope.themeMessage
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(14)
                            font.bold: true
                            color: osdScope.themeError ? Theme.errorColor : Theme.textPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }
                    }

                    // NOTE: TextMetrics removed — fixed iconW/valueW above cover
                    // all 4 volume glyphs at fs(20); per-tick measuring cost
                    // more than the 2px worst-case width difference.
                }
            }

        }
    }
}
