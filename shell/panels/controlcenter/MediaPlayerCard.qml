import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../../../style/themes"
import "../../../backend/services"
import "../../../style/ui"

// Android 17 / M3 Expressive media carousel:
// - every MPRIS session is a card; the active one is large, the others are
//   narrow pills next to it
// - selecting a pill runs a container-transform morph (Android 17 style):
//   the pill expands into the large card while the previous large card
//   minimizes, animating width, corner radius and content reveal together
// - track change on the active card: content slides left to right
Item {
    id: root

    readonly property var players: Mpris.players.values
    readonly property int playerCount: players ? players.length : 0
    property int activeIndex: 0
    // Control center edit mode: playback, seek and expand interaction is
    // disabled while the layout is being edited.
    property bool editing: false
    // Clamp only against a non-empty list: the model can briefly be empty at
    // startup, which must not reset an explicitly chosen activeIndex.
    onPlayersChanged: {
        if (players && players.length > 0 && root.activeIndex >= players.length) root.activeIndex = 0
        root.maybeFollowPlaying()
    }
    // Sessions can go idle while another one is audible (e.g. an app exposing
    // a stopped session next to the playing one). Keep the expanded card on
    // whatever is playing: a user-selected card is left alone while it plays.
    function maybeFollowPlaying(): void {
        const vals = root.players
        if (!vals || vals.length === 0) return
        const cur = vals[root.activeIndex]
        if (cur && cur.isPlaying) return
        for (let i = 0; i < vals.length; i++) {
            if (vals[i] && vals[i].isPlaying) {
                root.activeIndex = i
                return
            }
        }
    }

    implicitHeight: playerCount > 0 ? 150 : 96

    // The card sits on (blurred) album art, so its foreground is always
    // light with a dark scrim instead of the shell's surface colors.
    readonly property color fg: Qt.rgba(1, 1, 1, 1.0)
    readonly property color fgDim: Qt.rgba(1, 1, 1, 0.74)
    readonly property color glass: Qt.rgba(1, 1, 1, 0.16)

    // Carousel geometry: the active card takes whatever the peeks leave over.
    readonly property real peekWidth: 40
    readonly property real cardGap: 6
    readonly property real bigWidth: Math.max(peekWidth, width - Math.max(0, playerCount - 1) * (peekWidth + cardGap))
    // Parallax overscan per side for the album art (see
    // CarouselParallaxImage): the art bleeds past the card and pans
    // against the scroll direction while switching sessions.
    readonly property int artParallaxPad: 40

    readonly property string outputName: {
        try {
            let s = VolumeService.sink
            if (s) {
                let d = s.description || s.nickname || s.name
                if (d && ("" + d).length > 0) return "" + d
            }
        } catch (e) { }
        return "Audio"
    }

    function requestExpand(index: int): void {
        if (index < 0 || index >= playerCount || index === root.activeIndex) return
        activeIndex = index
    }

    // Scroll switching: wheel anywhere on the carousel moves to the previous
    // session (up) or next (down), wrapping around. Deeper consumers still
    // win — the seek bar's MouseArea accepts the wheel first (delivery walks
    // items deepest-first), so scrolling over the bar keeps seeking.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.playerCount > 1 && !root.editing
        onWheel: event => {
            if (event.angleDelta.y === 0) return
            // One switch per notch: momentum scrolling would otherwise race
            // through every card (one switch per wheel notch).
            if (playerScrollDebounce.running) {
                event.accepted = true
                return
            }
            playerScrollDebounce.start()
            const n = root.playerCount
            const step = event.angleDelta.y > 0 ? -1 : 1
            root.activeIndex = (root.activeIndex + step + n) % n
            event.accepted = true
        }
    }

    Timer {
        id: playerScrollDebounce
        interval: 100
    }

    // Session strip: a plain row — the active card is large and flush
    // with the tiles on the left while the rest shrink to peeks trailing
    // right. Deliberately NOT a scroll view: the widths are exact-fill
    // (big + peeks + gaps == width), so there is zero scroll room and a
    // ListView's range/snap enforcement fights its own clamps and lands
    // cards off-position. The scroll *effect* (grow/shrink + art panning
    // against the switch direction) is driven by the width morph itself
    // via reveal/panNorm below — one layout driver, deterministic.
    RowLayout {
        anchors.fill: parent
        spacing: root.cardGap
        visible: root.playerCount > 0

        Repeater {
            model: root.players
            delegate: MediaCard {
                required property var modelData
                required property int index
                Layout.fillHeight: true
                cardPlayer: modelData
                active: index === root.activeIndex
                onPlayingChanged: root.maybeFollowPlaying()
                onExpandRequested: root.requestExpand(index)
            }
        }
    }

    // No session at all: single placeholder card.
    ClipRect {
        anchors.fill: parent
        visible: root.playerCount === 0
        radius: Math.min(Theme.cornerRadius, Math.min(width, height) / 2)
        color: Theme.panelCardHigh
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        antialiasing: Theme.shapesAa

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary_container, 0.25) }
                GradientStop { position: 1.0; color: Theme.panelCardHigh }
            }
        }
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 28
            spacing: 4

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰝚"
                font.family: Theme.iconFontFamily
                font.pixelSize: Theme.fs(24)
                color: root.fgDim
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Keine Wiedergabe"
                color: root.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(14)
                font.weight: Font.Medium
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Kein Medienplayer aktiv"
                color: root.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    component IconButton: Item {
        id: button
        property string glyph
        property bool active: false
        signal activated()
        implicitWidth: 30
        implicitHeight: 30
        opacity: button.enabled ? 1.0 : 0.35

        Rectangle {
            anchors.centerIn: parent
            width: 28
            height: 28
            radius: width / 2
            color: "transparent"
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(16)
            color: button.active ? Theme.primary : root.fg
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType

            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
            }
        }

        StateLayer {
            id: buttonMouse
            radius: 14
            color: button.active ? Theme.primary : root.fg
            onClicked: button.activated()
        }
    }

    // One card per session. The same component renders the large active card
    // and the narrow peeks; only width, radius and content reveal differ, so
    // the morph is a single animated property (implicitWidth).
    component MediaCard: Item {
        id: cardItem
        required property var cardPlayer
        property bool active: false
        signal expandRequested()

        readonly property bool playing: cardItem.cardPlayer ? cardItem.cardPlayer.isPlaying : false
        readonly property bool canToggle: cardItem.cardPlayer ? cardItem.cardPlayer.canTogglePlaying : false
        readonly property bool canPrev: cardItem.cardPlayer ? cardItem.cardPlayer.canGoPrevious : false
        readonly property bool canNext: cardItem.cardPlayer ? cardItem.cardPlayer.canGoNext : false
        readonly property bool canShuffle: cardItem.cardPlayer ? (cardItem.cardPlayer.shuffleSupported && cardItem.cardPlayer.canControl) : false
        readonly property bool shuffleOn: cardItem.cardPlayer ? (cardItem.cardPlayer.shuffleSupported && cardItem.cardPlayer.shuffle) : false
        readonly property bool canLoop: cardItem.cardPlayer ? (cardItem.cardPlayer.loopSupported && cardItem.cardPlayer.canControl) : false
        readonly property bool loopOn: cardItem.cardPlayer ? (cardItem.cardPlayer.loopSupported && cardItem.cardPlayer.loopState !== MprisLoopState.None) : false
        readonly property bool loopOne: cardItem.cardPlayer ? (cardItem.cardPlayer.loopSupported && cardItem.cardPlayer.loopState === MprisLoopState.Track) : false
        readonly property bool seekable: cardItem.cardPlayer ? (cardItem.cardPlayer.canSeek && cardItem.cardPlayer.positionSupported) : false
        readonly property bool hasProgress: cardItem.cardPlayer ? (cardItem.cardPlayer.positionSupported && cardItem.cardPlayer.lengthSupported && trackLength > 0) : false
        readonly property real trackLength: cardItem.cardPlayer ? Math.max(0, cardItem.cardPlayer.length || 0) : 0

        // Track metadata is rendered from a snapshot so the slide can
        // still show the old track while the player already reports the new.
        property real _txX: 0
        property real _bgFade: 1
        property string _dispTitle: ""
        property string _dispArtist: ""
        property string _dispArt: ""

        readonly property string titleText: cardItem._dispTitle !== "" ? cardItem._dispTitle : "Unbekannter Titel"
        readonly property string artistText: cardItem._dispArtist !== "" ? cardItem._dispArtist : (cardItem.cardPlayer && cardItem.cardPlayer.identity ? cardItem.cardPlayer.identity : "")
        readonly property string artUrl: cardItem._dispArt

        function syncDisplay(): void {
            if (!cardItem.cardPlayer) { _dispTitle = ""; _dispArtist = ""; _dispArt = ""; return }
            _dispTitle = cardItem.cardPlayer.trackTitle || ""
            _dispArtist = cardItem.cardPlayer.trackArtist || ""
            _dispArt = cardItem.cardPlayer.trackArtUrl || ""
        }
        onCardPlayerChanged: { syncDisplay(); refreshAppIcon() }
        Component.onCompleted: { syncDisplay(); refreshAppIcon() }

        // Playback position: MPRIS pushes updates on (non)linear changes;
        // the 1s poke keeps players that stay silent fresh. The *displayed*
        // position is extrapolated between pushes so the bar and thumb
        // glide instead of stepping once per second.
        property real positionSecs: 0
        property double positionStamp: 0
        // Ignore stale position signals right after a seek commit: the
        // player acks asynchronously and would bounce the thumb backwards.
        property double seekGuardUntil: 0
        property bool seeking: false
        // While seeking this holds seconds (converted from the mouse
        // fraction), so displayPosition has one unit everywhere.
        property real seekPreview: 0
        property int _posTick: 0
        readonly property real displayPosition: {
            if (cardItem.seeking)
                return Math.max(0, Math.min(cardItem.trackLength, cardItem.seekPreview))
            if (!cardItem.playing || !cardItem.hasProgress || cardItem.positionStamp <= 0)
                return cardItem.positionSecs
            cardItem._posTick
            return Math.min(cardItem.trackLength, cardItem.positionSecs + (Date.now() - cardItem.positionStamp) / 1000)
        }
        readonly property real progressFrac: trackLength > 0 ? Math.max(0, Math.min(1, displayPosition / trackLength)) : 0

        function syncPosition(): void {
            if (!cardItem.cardPlayer) return
            let p = cardItem.cardPlayer.position
            cardItem.positionSecs = (isFinite(p) && p > 0) ? p : 0
            cardItem.positionStamp = Date.now()
        }
        onActiveChanged: {
            if (cardItem.active) cardItem.syncPosition()
            else cardItem.seeking = false
        }
        onPlayingChanged: if (cardItem.playing) cardItem.syncPosition()

        Timer {
            running: cardItem.active && cardItem.playing && cardItem.hasProgress
            interval: 1000
            repeat: true
            onTriggered: if (cardItem.cardPlayer) cardItem.cardPlayer.positionChanged()
        }
        // Extrapolation tick: at typical track rates this is sub-pixel per
        // step, so the bar reads as continuously moving.
        Timer {
            running: cardItem.active && cardItem.playing && cardItem.hasProgress
            interval: 200
            repeat: true
            onTriggered: cardItem._posTick++
        }
        Connections {
            target: cardItem.cardPlayer
            ignoreUnknownSignals: true
            function onPositionChanged() {
                if (cardItem.seeking || Date.now() < cardItem.seekGuardUntil) return
                cardItem.syncPosition()
            }
            function onPostTrackChanged() {
                cardItem.positionSecs = 0
                cardItem.positionStamp = Date.now()
                cardItem.seekGuardUntil = Date.now() + 400
                cardItem.seeking = false
                if (cardItem.active) trackChangeAnim.restart()
                else cardItem.syncDisplay()
            }
        }

        // Left-to-right slide for track changes (only the active card
        // animates): foreground content slides out to the right while the
        // background art fades out, then the snapshot swaps and the new
        // content slides in from the left while the new art fades in.
        SequentialAnimation {
            id: trackChangeAnim
            ParallelAnimation {
                NumberAnimation { target: cardItem; property: "_txX"; to: Theme.motionSlideDistance; duration: Theme.durMotionSharedAxis * Theme.motionFadeThroughExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
                NumberAnimation { target: cardItem; property: "_bgFade"; to: 0; duration: Theme.durMotionSharedAxis * Theme.motionFadeThroughExit; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
            }
            ScriptAction { script: cardItem.syncDisplay() }
            ScriptAction { script: cardItem._txX = -Theme.motionSlideDistance }
            ParallelAnimation {
                NumberAnimation { target: cardItem; property: "_txX"; to: 0; duration: Theme.durMotionSharedAxis * Theme.motionFadeThroughEnter; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
                NumberAnimation { target: cardItem; property: "_bgFade"; to: 1; duration: Theme.durMotionSharedAxis * Theme.motionFadeThroughEnter; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
            }
            ScriptAction { script: artSyncTimer.restart() }
        }
        // Some players publish trackArtUrl slightly after the track change;
        // pick it up once the slide has finished.
        Timer {
            id: artSyncTimer
            interval: 1500
            repeat: false
            onTriggered: {
                if (cardItem.cardPlayer && cardItem.cardPlayer.trackArtUrl && cardItem.cardPlayer.trackArtUrl !== cardItem._dispArt) {
                    cardItem._dispArt = cardItem.cardPlayer.trackArtUrl
                }
            }
        }

        // Imperative (not a binding): Theme.appIconFor() writes its memo
        // caches, which would trip "binding loop detected" if reactive.
        property string appIconPath: ""
        function refreshAppIcon(): void {
            let next = ""
            try {
                if (cardItem.cardPlayer && cardItem.cardPlayer.desktopEntry && cardItem.cardPlayer.desktopEntry.length > 0) {
                    let p = Theme.appIconFor(cardItem.cardPlayer.desktopEntry)
                    if (p && p.length > 0 && p !== Quickshell.iconPath("application-x-executable")) next = p
                }
            } catch (e) { }
            if (next !== appIconPath) appIconPath = next
        }
        Connections {
            target: Theme
            function onAppsRevChanged() { cardItem.refreshAppIcon() }
        }

        function togglePlay(): void { if (cardItem.cardPlayer && cardItem.canToggle) cardItem.cardPlayer.togglePlaying() }
        function prev(): void { if (cardItem.canPrev) cardItem.cardPlayer.previous() }
        function next(): void { if (cardItem.canNext) cardItem.cardPlayer.next() }
        function toggleShuffle(): void { if (cardItem.canShuffle) cardItem.cardPlayer.shuffle = !cardItem.cardPlayer.shuffle }
        function cycleLoop(): void {
            if (!cardItem.canLoop) return
            let s = cardItem.cardPlayer.loopState
            cardItem.cardPlayer.loopState = (s === MprisLoopState.None) ? MprisLoopState.Playlist
                : (s === MprisLoopState.Playlist) ? MprisLoopState.Track : MprisLoopState.None
        }
        function commitSeek(frac: real): void {
            if (!cardItem.seekable || cardItem.trackLength <= 0) { cardItem.seeking = false; return }
            let target = Math.max(0, Math.min(cardItem.trackLength, frac * cardItem.trackLength))
            cardItem.seeking = false
            cardItem.positionSecs = target
            cardItem.positionStamp = Date.now()
            cardItem.seekGuardUntil = cardItem.positionStamp + 400
            cardItem.cardPlayer.position = target
        }

        // Container-transform morph: width drives everything. The radius
        // interpolates pill -> extra-large and the foreground fades in with a
        // smoothstep so the expanding card reveals its content.
        readonly property real reveal: {
            let span = root.bigWidth - root.peekWidth
            if (span <= 0) return 1
            let t = Math.max(0, Math.min(1, (cardItem.width - root.peekWidth) / span))
            return t * t * (3 - 2 * t)
        }
        readonly property bool controlsEnabled: cardItem.active && cardItem.reveal > 0.85

        // Scroll-effect pan, driven by the width morph (not a scroll
        // position): 0 on the settled active card, ±1 on a settled peek
        // (sign = side), sweeping through the morph. Pure function of
        // layout state, so it can never desync or leave a stale offset.
        readonly property real panNorm: (index < root.activeIndex ? -1 : 1) * (1 - cardItem.reveal)

        implicitWidth: cardItem.active ? root.bigWidth : root.peekWidth
        Behavior on implicitWidth {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durMotionSharedAxis; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveMotion }
        }

        ClipRect {
            anchors.fill: parent
            radius: Math.min(Theme.cornerRadius, width / 2)
            color: Theme.panelCardHigh
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
            antialiasing: Theme.shapesAa

            // Foreground content slides left to right on track change;
            // the background art only fades; the card box and scrim stay
            // static.
            // Full-bleed album art, decoded at thumbnail size and scaled up
            // (cheap blur) with a scrim for text contrast.
            Rectangle {
                anchors.fill: parent
                visible: !artImage.visible
                opacity: cardItem._bgFade
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.55) }
                    GradientStop { position: 1.0; color: Theme.withAlpha(Theme.primary_container, 0.9) }
                }
            }
            CarouselParallaxImage {
                id: artImage
                height: parent.height
                fullWidth: root.bigWidth + 2 * root.artParallaxPad
                parallaxPad: root.artParallaxPad
                centerNorm: cardItem.panNorm
                source: cardItem.artUrl
                sourceSize: Qt.size(64, 64)
                cache: true
                smooth: Theme.imageSmooth
                visible: status === Image.Ready
                opacity: cardItem._bgFade
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.42) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.30) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.58) }
                }
            }

            // Foreground: laid out at the full card width and clipped by the
            // container, so the morph reveals it without a reflow.
            ColumnLayout {
                x: 14
                y: 14
                width: root.bigWidth - 28
                height: parent.height - 28
                spacing: 8
                opacity: cardItem.reveal
                transform: Translate { x: cardItem._txX }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: width / 2
                        color: root.glass

                        Image {
                            anchors.fill: parent
                            anchors.margins: 5
                            source: cardItem.appIconPath
                            sourceSize: Qt.size(48, 48)
                            asynchronous: true
                            cache: true
                            smooth: Theme.imageSmooth
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: cardItem.appIconPath.length === 0
                            text: "󰝚"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(15)
                            color: root.fg
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: Math.min(outputRow.implicitWidth + 20, 168)
                        radius: height / 2
                        color: root.glass

                        RowLayout {
                            id: outputRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "󰓃"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(13)
                                color: root.fgDim
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.maximumWidth: 126
                                text: root.outputName
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                color: root.fg
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: cardItem.titleText
                            color: root.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(15)
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "󰎇"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(12)
                                color: root.fgDim
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                            Text {
                                Layout.fillWidth: true
                                text: cardItem.artistText
                                color: root.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }
                    }

                    Rectangle {
                        id: playButton
                        // Playing (pause glyph showing): wide rounded
                        // rectangle; paused (play glyph): circle. Width is
                        // driven through an animatable property so the morph
                        // glides instead of snapping the title.
                        property real buttonWidth: cardItem.playing ? 64 : 46
                        Behavior on buttonWidth {
                            enabled: Theme.animationsEnabled
                            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                        }
                        Layout.preferredWidth: Math.round(buttonWidth)
                        Layout.preferredHeight: 46
                        radius: cardItem.playing ? 15 : width / 2
                        color: Theme.primary
                        opacity: cardItem.canToggle && !root.editing ? 1.0 : 0.55
                        scale: playMouse.pressed ? Theme.pressScale : (playMouse.containsMouse ? 1.04 : 1.0)
                        transformOrigin: Item.Center
                        antialiasing: Theme.shapesAa

                        Behavior on radius {
                            enabled: Theme.animationsEnabled
                            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                        }
                        Behavior on scale {
                            enabled: Theme.animationsEnabled
                            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                        }
                        Behavior on opacity {
                            enabled: Theme.animationsEnabled
                            NumberAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: cardItem.playing ? "󰏤" : "󰐊"
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(22)
                            color: Theme.on_primary
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                        }

                        StateLayer {
                            id: playMouse
                            disabled: root.editing || !(cardItem.controlsEnabled && cardItem.canToggle)
                            radius: playButton.radius
                            color: Theme.on_primary
                            onClicked: cardItem.togglePlay()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    IconButton {
                        glyph: "󰒮"
                        enabled: cardItem.controlsEnabled && cardItem.canPrev && !root.editing
                        onActivated: cardItem.prev()
                    }

                    // Seek bar: straight progress line with a thumb; a time
                    // pill tracks the thumb while scrubbing.
                    Item {
                        id: seekBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        visible: cardItem.hasProgress

                        readonly property bool hot: seekMouse.containsMouse || cardItem.seeking
                        readonly property real trackHeight: 4
                        readonly property real progressPx: seekBar.width * cardItem.progressFrac

                        // Full-track line in the inactive tint.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: seekBar.trackHeight
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.26)
                            antialiasing: Theme.shapesAa
                        }
                        // Played portion.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(height, seekBar.progressPx)
                            height: seekBar.trackHeight
                            radius: height / 2
                            color: root.fg
                            antialiasing: Theme.shapesAa
                        }

                        // M3 state halo behind the thumb.
                        Rectangle {
                            anchors.centerIn: seekThumb
                            width: 30
                            height: 30
                            radius: 15
                            color: Qt.rgba(1, 1, 1, 0.14)
                            opacity: seekBar.hot ? 1 : 0
                            antialiasing: Theme.shapesAa
                            Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects } }
                        }
                        Rectangle {
                            id: seekThumb
                            width: cardItem.seeking ? 18 : (seekBar.hot ? 15 : 12)
                            height: width
                            radius: width / 2
                            x: Math.max(0, Math.min(seekBar.width - width, seekBar.progressPx - width / 2))
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.fg
                            antialiasing: Theme.shapesAa

                            Behavior on width {
                                enabled: Theme.animationsEnabled
                                NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
                            }
                        }

                        // Scrub time pill, Android-media style.
                        Rectangle {
                            width: bubbleText.implicitWidth + 18
                            height: 22
                            radius: 11
                            x: Math.max(0, Math.min(seekBar.width - width, seekBar.progressPx - width / 2))
                            y: -height - 4
                            color: Qt.rgba(0, 0, 0, 0.62)
                            border.color: Qt.rgba(1, 1, 1, 0.2)
                            border.width: 1
                            antialiasing: Theme.shapesAa
                            visible: opacity > 0.01
                            opacity: cardItem.seeking ? 1 : 0

                            Behavior on opacity { enabled: Theme.animationsEnabled; NumberAnimation { duration: Theme.durFastEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastEffects } }

                            Text {
                                id: bubbleText
                                anchors.centerIn: parent
                                text: seekBar.formatTime(cardItem.displayPosition)
                                color: root.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                            }
                        }

                        function fracAt(x: real): real {
                            return width > 0 ? Math.max(0, Math.min(1, x / width)) : 0
                        }
                        // seekPreview is stored in seconds so displayPosition
                        // never mixes units while scrubbing (the old code fed
                        // a 0..1 fraction into the seconds path, pinning the
                        // thumb near the start during drags).
                        function previewAt(x: real): void {
                            cardItem.seekPreview = seekBar.fracAt(x) * cardItem.trackLength
                        }
                        function formatTime(secs: real): string {
                            let v = Math.max(0, isFinite(secs) ? secs : 0)
                            let s = Math.floor(v % 60)
                            let m = Math.floor(v / 60) % 60
                            let h = Math.floor(v / 3600)
                            if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
                            return m + ":" + (s < 10 ? "0" : "") + s
                        }

                        MouseArea {
                            id: seekMouse
                            anchors.fill: parent
                            enabled: cardItem.controlsEnabled && cardItem.seekable && !root.editing
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            onPressed: mouse => {
                                cardItem.seeking = true
                                seekBar.previewAt(mouse.x)
                            }
                            onPositionChanged: mouse => {
                                if (cardItem.seeking) seekBar.previewAt(mouse.x)
                            }
                            onReleased: mouse => cardItem.commitSeek(seekBar.fracAt(mouse.x))
                            onCanceled: cardItem.seeking = false
                            onWheel: wheel => {
                                if (!cardItem.seekable || cardItem.trackLength <= 0) return
                                const step = wheel.angleDelta.y > 0 ? 5 : -5
                                cardItem.commitSeek(Math.max(0, Math.min(1, cardItem.progressFrac + step / cardItem.trackLength)))
                                wheel.accepted = true
                            }
                        }
                    }

                    IconButton {
                        glyph: "󰒭"
                        enabled: cardItem.controlsEnabled && cardItem.canNext && !root.editing
                        onActivated: cardItem.next()
                    }
                    IconButton {
                        glyph: "󰒝"
                        enabled: cardItem.controlsEnabled && cardItem.canShuffle && !root.editing
                        active: cardItem.shuffleOn
                        onActivated: cardItem.toggleShuffle()
                    }
                    IconButton {
                        glyph: cardItem.loopOne ? "󰑘" : "󰑖"
                        enabled: cardItem.controlsEnabled && cardItem.canLoop && !root.editing
                        active: cardItem.loopOn
                        onActivated: cardItem.cycleLoop()
                    }
                }
            }
        }

        // Selecting a pill expands it; the active card's controls sit above
        // this area and win whenever this card is already active.
        StateLayer {
            disabled: cardItem.active || root.editing
            radius: Math.min(Theme.cornerRadius, width / 2)
            color: root.fg
            onClicked: cardItem.expandRequested()
        }
    }
}
