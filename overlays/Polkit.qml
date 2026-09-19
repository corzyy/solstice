pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io // required — provides IpcHandler
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Polkit
import "../themes"
import "../ui"

Scope {
    id: polkitScope

    Loader {
        id: agentLoader
        active: true
        sourceComponent: agentComponent
    }
    Component {
        id: agentComponent
        PolkitAgent {
            onAuthenticationRequestStarted: polkitScope.clearInput()
        }
    }
    property var agentObj: agentLoader.item
    property string agentPath: "/org/quickshell/PolkitAgent"
    onAgentObjChanged: if (agentObj && agentObj.path) agentPath = agentObj.path
    property bool agentActive: agentObj ? agentObj.isActive : false
    property bool agentRegistered: agentObj ? agentObj.isRegistered : false
    onAgentRegisteredChanged: { try { Theme.setPolkitReady(agentRegistered) } catch (e) { } }
    function recreateAgent(): void {
        if (!agentLoader.active) { agentLoader.active = true; return }
        agentLoader.active = false
        agentRecreateTimer.restart()
    }
    Timer {
        id: agentRecreateTimer
        interval: 700; repeat: false
        onTriggered: agentLoader.active = true
    }
    Timer {
        id: agentWatchdog
        // STABILITY: bounded retries. If another polkit agent (GNOME/KDE/
        // hyprpolkitagent, a second shell instance, …) already owns the
        // session, registration fails permanently with "An authentication
        // agent already exists for the given subject". Retrying forever only
        // spams the journal. We back off and stop, and can be re-armed with
        // `quickshell ipc -c solstice call polkit retry`.
        property int failures: 0
        readonly property int maxFailures: 5
        interval: failures >= 3 ? 30000 : 8000
        repeat: true
        running: !polkitScope.agentRegistered && !polkitScope.agentActive && failures < maxFailures
        onTriggered: {
            try { Theme.setPolkitReady(polkitScope.agentRegistered) } catch (e) { }
            if (polkitScope.agentRegistered || polkitScope.agentActive) { failures = 0; return }
            failures++
            if (failures >= maxFailures) {
                console.log("[solstice][polkit] giving up after " + failures + " attempts — another authentication agent is likely already registered")
                return
            }
            console.log("[solstice][polkit] no agent registered — retrying listener registration (" + failures + "/" + maxFailures + ")")
            polkitScope.recreateAgent()
        }
    }
    function retryAgent(): void {
        agentWatchdog.failures = 0
        recreateAgent()
        agentWatchdog.restart()
    }

    property var flow: agentObj ? agentObj.flow : null
    property bool hasRequest: agentActive && flow !== null

    property bool _winVisible: hasRequest
    // Linger for the fade-through exit run (0 when animations are off).
    Timer { id: polkitHideTimer; interval: Theme.animationsEnabled ? Theme.durMotionFadeThrough + 20 : 0; repeat: false; onTriggered: if (!polkitScope.hasRequest) polkitScope._winVisible = false }
    onHasRequestChanged: {
        if (hasRequest) {
            _winVisible = true
            polkitHideTimer.stop()
        } else {
            polkitHideTimer.restart()
        }
        clearInput()
    }

    property string inputText: ""
    // Einziger Reset-Pfad für das Eingabefeld (war 5x kopiert).
    function clearInput(): void {
        if (inputText !== "") inputText = ""
    }
    property bool isPassword: true
    property int shakeCount: 0
    function requestShake() { shakeCount++ }
    property double lastSubmitMs: 0
    onFlowChanged: {
        if (flow) isPassword = !flow.responseVisible
        else isPassword = true
    }

    Connections {
        target: flow
        ignoreUnknownSignals: true
        function onFailedChanged() {
            if (flow && flow.failed) polkitScope.requestShake()

        }
        function onSupplementaryMessageChanged() {
            if (flow && flow.supplementaryIsError) {
                polkitScope.requestShake()
            }
        }
        function onResponseVisibleChanged() {
            if (flow) polkitScope.isPassword = !flow.responseVisible
        }
    }

    function submitCurrent() {
        if (!flow) return
        if (flow.isResponseRequired && inputText.length === 0) {
            polkitScope.requestShake()
            return
        }
        let now = Date.now()
        if (now - lastSubmitMs < 500) return
        lastSubmitMs = now
        flow.submit(flow.isResponseRequired ? inputText : "")
        clearInput()
    }
    function cancelCurrent() {
        if (!flow) return
        flow.cancelAuthenticationRequest()
        clearInput()
    }

    readonly property int barT: Theme.barThickness
    readonly property string barPos: Theme.barPosition

    IpcHandler {
        target: "polkit"
        function status(): string {
            if (!polkitScope.agentRegistered) return "agent not registered (attempts=" + agentWatchdog.failures + "/" + agentWatchdog.maxFailures + "; path=" + polkitScope.agentPath + ")"
            if (!polkitScope.agentActive || !flow) return "idle registered=" + polkitScope.agentRegistered + " active=" + polkitScope.agentActive
            let s = "active action=" + (flow.actionId || "?") + " msg=" + (flow.message || "").substring(0,60)
            s += " prompt=" + (flow.inputPrompt || "") + " needResponse=" + flow.isResponseRequired + " visible=" + flow.responseVisible
            s += " failed=" + flow.failed + " completed=" + flow.isCompleted + " success=" + flow.isSuccessful
            try {
                let ids = flow.identities ? flow.identities : []
                s += " identities=" + ids.length + "["
                for (let i = 0; i < ids.length; i++) {
                    let d = ids[i]
                    s += (i > 0 ? "," : "") + (d ? (d.displayName + (d.isGroup ? "(group)" : "")) : "?")
                }
                s += "]"
                let sel = flow.selectedIdentity
                s += " selected=" + (sel ? (sel.displayName + (sel.isGroup ? "(group)" : "")) : "none")
            } catch (e) { s += " identErr=" + e }
            if (flow.supplementaryMessage) s += " supp=" + flow.supplementaryMessage.substring(0,80)
            return s
        }
        function cancel(): string { if (flow) flow.cancelAuthenticationRequest(); return "cancel sent" }
        function retry(): string { polkitScope.retryAgent(); return "polkit agent re-register requested" }
        function trigger(): string { return "run: ~/.config/quickshell/solstice/scripts/test-polkit.sh  or  pkexec --disable-internal-agent id" }
    }

    // Single fullscreen window per screen: no separate backdrop layer, so the
    // dialog can never end up UNDER a dim rectangle (darkened + unclickable).
    // There is intentionally no dim/scrim — the desktop stays as-is and only
    // this centered card asks for attention.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: polkitScope._winVisible
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "polkit"
            WlrLayershell.keyboardFocus: Theme.isPrimaryScreen(modelData) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            // Transparent modal blocker: swallows clicks outside the card so
            // they can't fall through to windows underneath mid-auth.
            // (No visual dim — color stays fully transparent.)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onPressed: mouse => mouse.accepted = true
                onClicked: mouse => mouse.accepted = true
                onWheel: wheel => wheel.accepted = true
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (!polkitScope.hasRequest) return
                    if (event.key === Qt.Key_Escape) {
                        polkitScope.cancelCurrent()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (polkitScope.flow) {
                            polkitScope.submitCurrent()
                            event.accepted = true
                        }
                    }
                }
                Component.onCompleted: forceActiveFocus()
                onVisibleChanged: if (visible) Qt.callLater(() => forceActiveFocus())
            }
            Item {
                id: dialogWrapper
                anchors.centerIn: parent
                anchors.verticalCenterOffset: polkitScope.barPos === "top" ? polkitScope.barT * 0.15 : polkitScope.barPos === "bottom" ? -polkitScope.barT * 0.15 : 0
                width: 420
                implicitHeight: dialogBox.implicitHeight
                // Dialog enter/exit: M3 fade through (fade + settle from 92%).
                Motion {
                    id: dialogMotion
                    active: polkitScope.hasRequest
                    pattern: Motion.FadeThrough
                }
                opacity: dialogMotion.opacity
                scale: dialogMotion.scale
                transform: Translate {
                    x: dialogWrapper.shakeX
                    // Rise/fade coupled to the driver so they never desync.
                    y: (1 - dialogMotion.opacity) * -Theme.panelSlideOffset
                }

                property real shakeX: 0
                // Denied-prompt shake steps (utility motion, short + standard
                // easing; collapses when animations are off).
                readonly property int shakeStep: Theme.animationsEnabled ? 60 : 0
                transformOrigin: Item.Center
                Connections {
                    target: polkitScope
                    function onShakeCountChanged() { shakeAnim.restart() }
                }
                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: dialogWrapper; property: "shakeX"; to: -12; duration: dialogWrapper.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandardAccel }
                    NumberAnimation { target: dialogWrapper; property: "shakeX"; to: 10; duration: dialogWrapper.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandard }
                    NumberAnimation { target: dialogWrapper; property: "shakeX"; to: -6; duration: dialogWrapper.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandard }
                    NumberAnimation { target: dialogWrapper; property: "shakeX"; to: 4; duration: dialogWrapper.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandard }
                    NumberAnimation { target: dialogWrapper; property: "shakeX"; to: 0; duration: dialogWrapper.shakeStep; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveStandardDecel }
                }

                Rectangle {
                    antialiasing: Theme.shapesAa
                    id: dialogBox
                    width: parent.width
                    implicitHeight: mainCol.implicitHeight + 36
                    radius: Theme.cornerRadius
                    color: Theme.panelBg
                    border.color: Theme.panelBorderColor
                    border.width: 1
                    clip: true
                    layer.enabled: polkitScope.hasRequest
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.withAlpha(Theme.scrim, 0.45)
                        shadowBlur: 0.9
                        shadowOpacity: 0.42
                        shadowVerticalOffset: 10
                        shadowHorizontalOffset: 0
                    }

                    ColumnLayout {
                        id: mainCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.topMargin: 20
                        anchors.bottomMargin: 16
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                antialiasing: Theme.shapesAa
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                radius: 22
                                color: polkitScope.flow && polkitScope.flow.failed ? Theme.withAlpha(Theme.error, 0.18) : Theme.withAlpha(Theme.accent, 0.14)
                                border.color: polkitScope.flow && polkitScope.flow.failed ? Theme.withAlpha(Theme.errorColor, 0.45) : Theme.withAlpha(Theme.accent, 0.35)
                                border.width: 1

                                IconImage {
                                    anchors.centerIn: parent
                                    width: 22; height: 22
                                    asynchronous: true
                                    // PERF: 22px decode (was 44px = 4x pixels for
                                    // a 22px display).
                                    implicitSize: Qt.size(22, 22)
                                    source: {
                                        if (!polkitScope.flow) return ""
                                        let n = polkitScope.flow.iconName
                                        if (!n || n.length === 0) return Quickshell.iconPath("dialog-password")
                                        if (n.startsWith("/") || n.startsWith("file://") || n.startsWith("image://")) return n
                                        if (Quickshell.hasThemeIcon(n)) return Quickshell.iconPath(n)
                                        return Quickshell.iconPath("dialog-password")
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                    Layout.fillWidth: true
                                    text: "Authentication required"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(14)
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                    Layout.fillWidth: true
                                    visible: polkitScope.flow && polkitScope.flow.actionId && polkitScope.flow.actionId.length > 0
                                    text: polkitScope.flow ? polkitScope.flow.actionId : ""
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                }
                            }
                            Rectangle {
                                antialiasing: Theme.shapesAa
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 15
                                color: cancelHover.containsMouse ? Theme.withAlpha(Theme.error, 0.14) : "transparent"
                                border.color: "transparent"
                                border.width: 0
                                Text {
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                    anchors.centerIn: parent
                                    text: "✕"
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: Theme.fs(12)
                                    color: cancelHover.containsMouse ? Theme.errorColor : Theme.textMuted
                                }
                                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: polkitScope.cancelCurrent()
                                }
                            }
                        }

                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            Layout.fillWidth: true
                            visible: polkitScope.flow && polkitScope.flow.message && polkitScope.flow.message.length > 0
                            text: polkitScope.flow ? polkitScope.flow.message : ""
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(13)
                            wrapMode: Text.WordWrap
                            lineHeight: 1.25
                            textFormat: Text.PlainText
                        }

                        Rectangle {
                            antialiasing: Theme.shapesAa
                            Layout.fillWidth: true
                            visible: polkitScope.flow && polkitScope.flow.supplementaryMessage && polkitScope.flow.supplementaryMessage.length > 0
                            implicitHeight: suppText.implicitHeight + 10
                            radius: Theme.cornerRadiusSmall
                            color: polkitScope.flow && polkitScope.flow.supplementaryIsError ? Theme.withAlpha(Theme.error, 0.14) : Theme.withAlpha(Theme.panelSurface, 0.9)
                            border.color: polkitScope.flow && polkitScope.flow.supplementaryIsError ? Theme.withAlpha(Theme.errorColor, 0.28) : Theme.divider
                            border.width: 1
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                id: suppText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                text: polkitScope.flow ? polkitScope.flow.supplementaryMessage : ""
                                color: polkitScope.flow && polkitScope.flow.supplementaryIsError ? Theme.errorColor : Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: polkitScope.flow && polkitScope.flow.identities && polkitScope.flow.identities.length > 1

                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                text: "Authenticate as:"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Medium
                                Layout.fillWidth: true
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: polkitScope.flow ? polkitScope.flow.identities : []
                                    delegate: Rectangle {
                                        id: identityDelegate
                                        required property var modelData
                                        required property int index
                                        property var ident: modelData
                                        property bool isSelected: polkitScope.flow && polkitScope.flow.selectedIdentity === ident
                                        width: identRow.implicitWidth + 14
                                        height: 28
                                        radius: Theme.cornerRadiusSmall
                                        color: isSelected ? Theme.bgSelected : identMouse.containsMouse ? Theme.panelSurface : "transparent"
                                        border.color: isSelected ? Theme.divider : identMouse.containsMouse ? Theme.divider : "transparent"
                                        border.width: 1

                                        RowLayout {
                                            id: identRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                antialiasing: Theme.textAa
                                                renderType: Theme.textRenderType
                                                text: identityDelegate.isSelected ? "󰄬" : (identityDelegate.ident && identityDelegate.ident.isGroup ? "󰅺" : "󰀄")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(11)
                                                color: identityDelegate.isSelected ? Theme.accent : Theme.textSecondary
                                            }
                                            Text {
                                                antialiasing: Theme.textAa
                                                renderType: Theme.textRenderType
                                                text: identityDelegate.ident ? identityDelegate.ident.displayName : ""
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fs(11)
                                                font.weight: identityDelegate.isSelected ? Font.Medium : Font.Normal
                                                color: identityDelegate.isSelected ? Theme.textPrimary : Theme.textSecondary
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 160
                                            }
                                        }
                                        MouseArea {
                                            id: identMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!polkitScope.flow) return
                                                if (polkitScope.flow.selectedIdentity !== identityDelegate.ident) {
                                                    polkitScope.flow.selectedIdentity = identityDelegate.ident
                                                    polkitScope.clearInput()
                                                    if (polkitField) {
                                                        polkitField.text = ""
                                                        Qt.callLater(() => polkitField.forceActiveFocus())
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.withAlpha(Theme.divider, 0.6)
                                antialiasing: Theme.shapesAa
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: polkitScope.flow && polkitScope.flow.identities && polkitScope.flow.identities.length === 1
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                text: "󰀄"
                                font.family: Theme.iconFontFamily
                                font.pixelSize: Theme.fs(11)
                                color: Theme.textMuted
                            }
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                Layout.fillWidth: true
                                text: polkitScope.flow && polkitScope.flow.identities && polkitScope.flow.identities.length === 1 ? polkitScope.flow.identities[0].displayName : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                            }
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                visible: polkitScope.flow && polkitScope.flow.identities && polkitScope.flow.identities[0] && polkitScope.flow.identities[0].isGroup
                                text: "(Group)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.textMuted
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: polkitScope.flow && polkitScope.flow.isResponseRequired

                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                Layout.fillWidth: true
                                text: polkitScope.flow ? (polkitScope.flow.inputPrompt.length > 0 ? polkitScope.flow.inputPrompt : "Password:") : "Password:"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                            }

                            Rectangle {
                                antialiasing: Theme.shapesAa
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: Theme.cornerRadiusSmall
                                color: polkitField.activeFocus ? Theme.bgSelected : Theme.panelSurface
                                border.color: polkitScope.flow && polkitScope.flow.failed ? Theme.errorColor : (polkitField.activeFocus ? Theme.accent : Theme.divider)
                                border.width: polkitField.activeFocus || (polkitScope.flow && polkitScope.flow.failed) ? 1.6 : 1
                                // Clicking the field padding focuses the text input.
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: polkitField.forceActiveFocus()
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 6
                                    spacing: 6
                                    Text {
                                        antialiasing: Theme.textAa
                                        renderType: Theme.textRenderType
                                        text: polkitScope.isPassword ? "󰌾" : "󰈈"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(13)
                                        color: polkitField.activeFocus ? Theme.accent : Theme.textMuted
                                    }
                                    TextInput {
                                        id: polkitField
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.textPrimary
                                        selectionColor: Theme.accent
                                        selectedTextColor: Theme.onAccent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(13)
                                        echoMode: polkitScope.isPassword ? TextInput.Password : TextInput.Normal
                                        passwordCharacter: "•"
                                        clip: true
                                        focus: polkitScope.hasRequest
                                        activeFocusOnTab: true
                                        selectByMouse: true
                                        text: polkitScope.inputText
                                        onTextChanged: {
                                            if (text !== polkitScope.inputText) polkitScope.inputText = text
                                        }
                                        Connections {
                                            target: polkitScope
                                            function onInputTextChanged() {
                                                if (polkitField.text !== polkitScope.inputText) polkitField.text = polkitScope.inputText
                                            }
                                        }
                                        onAccepted: polkitScope.submitCurrent()
                                        Keys.onPressed: event => {
                                            if (event.key === Qt.Key_Escape) {
                                                polkitScope.cancelCurrent()
                                                event.accepted = true
                                            }
                                        }
                                        Connections {
                                            target: polkitScope
                                            function onHasRequestChanged() {
                                                if (polkitScope.hasRequest) Qt.callLater(() => {
                                                    try { if (polkitField) polkitField.forceActiveFocus() } catch(e) { }
                                                })
                                            }
                                        }
                                        Component.onCompleted: if (polkitScope.hasRequest) Qt.callLater(() => { try { polkitField.forceActiveFocus() } catch(e) { } })
                                    }
                                    Rectangle {
                                        antialiasing: Theme.shapesAa
                                        visible: polkitScope.flow && !polkitScope.flow.responseVisible
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 24
                                        radius: Theme.cornerRadiusSmall
                                        color: eyeMouse.containsMouse ? Theme.bgHover : "transparent"
                                        Text {
                                            antialiasing: Theme.textAa
                                            renderType: Theme.textRenderType
                                            anchors.centerIn: parent
                                            text: polkitScope.isPassword ? "󰈈" : "󰈉"
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12)
                                            color: eyeMouse.containsMouse ? Theme.textPrimary : Theme.textMuted
                                        }
                                        MouseArea {
                                            id: eyeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: polkitScope.isPassword = !polkitScope.isPassword
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            Layout.fillWidth: true
                            visible: polkitScope.flow && !polkitScope.flow.isResponseRequired && (!polkitScope.flow.supplementaryMessage || polkitScope.flow.supplementaryMessage.length === 0)
                            text: "Press “Authenticate” to continue."
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Layout.topMargin: 4

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                antialiasing: Theme.shapesAa
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 34
                                radius: Theme.cornerRadiusSmall
                                color: cancelBtnMouse.pressed ? Theme.bgSelected : cancelBtnMouse.containsMouse ? Theme.bgHover : Theme.panelSurface
                                border.color: cancelBtnMouse.containsMouse ? Theme.textMuted : Theme.divider
                                border.width: 1
                                Text {
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Medium
                                    color: Theme.textPrimary
                                }
                                MouseArea {
                                    id: cancelBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: polkitScope.cancelCurrent()
                                }
                            }

                            Rectangle {
                                antialiasing: Theme.shapesAa
                                Layout.preferredWidth: 142
                                Layout.preferredHeight: 34
                                radius: Theme.cornerRadiusSmall
                                color: !enabled ? Theme.withAlpha(Theme.accent, 0.45) : authBtnMouse.pressed ? Theme.withAlpha(Theme.accent, 0.78) : authBtnMouse.containsMouse ? Theme.withAlpha(Theme.accent, 0.92) : Theme.accent
                                border.color: Theme.accent
                                border.width: 1
                                enabled: !polkitScope.flow || !polkitScope.flow.isResponseRequired || polkitScope.inputText.length > 0
                                opacity: enabled ? 1 : 0.6
                                Text {
                                    antialiasing: Theme.textAa
                                    renderType: Theme.textRenderType
                                    anchors.centerIn: parent
                                    text: "Authenticate"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Medium
                                    color: Theme.onAccent
                                }
                                MouseArea {
                                    id: authBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: parent.enabled
                                    onClicked: polkitScope.submitCurrent()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: polkitScope.flow && polkitScope.flow.failed
                            Text {
                                antialiasing: Theme.textAa
                                renderType: Theme.textRenderType
                                visible: polkitScope.flow && polkitScope.flow.failed
                                text: "Authentication failed — try again"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.errorColor
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}
