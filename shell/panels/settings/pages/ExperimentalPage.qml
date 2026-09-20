pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../../style/themes"
import ".."

// Experimental — opt-in rendering switches, reachable from Setup.
// Qt locks in its RHI backend (QSG_RHI_BACKEND) before the scene graph
// starts, so a backend change cannot be applied at runtime. This page pins
// the choice in backend/config/gpu.conf through backend/scripts/set-renderer.sh
// and restarts the shell through backend/scripts/solstice, which sources the
// file on every start.
NexusControls.PageBase {
    id: root
    title: "Experimental"

    // Active RHI backend of the running shell. GraphicsInfo has no change
    // signal and only reports a value once this window's scene graph has
    // initialized, so it is read on completion with a retry timer instead of
    // a plain binding.
    property int api: GraphicsInfo.Unknown
    // Backend the user just picked, shown until the restart lands.
    property string pending: ""
    property bool restartQueued: false
    property string message: ""

    readonly property string setter: Quickshell.shellDir + "/backend/scripts/set-renderer.sh"
    readonly property string launcher: Quickshell.shellDir + "/backend/scripts/solstice"
    readonly property string activeBackend: root.api === GraphicsInfo.Vulkan ? "vulkan"
        : root.api === GraphicsInfo.OpenGL ? "opengl" : ""
    readonly property string activeName: root.api === GraphicsInfo.Vulkan ? "Vulkan"
        : root.api === GraphicsInfo.OpenGL ? "OpenGL" : "Detecting…"
    readonly property string shownBackend: root.pending.length > 0 ? root.pending : root.activeBackend
    readonly property bool vulkanOn: root.shownBackend === "vulkan"
    readonly property string toggleSubtext: {
        if (root.pending.length > 0)
            return "Restarting into " + (root.pending === "vulkan" ? "Vulkan" : "OpenGL") + "…"
        return "Active: " + root.activeName + " — toggling restarts the shell"
    }

    function refreshApi(): void { root.api = GraphicsInfo.api }
    Component.onCompleted: root.refreshApi()
    Timer {
        interval: 250
        repeat: true
        running: root.api === GraphicsInfo.Unknown
        onTriggered: root.refreshApi()
    }

    function applyBackend(mode: string): void {
        root.message = ""
        root.pending = mode
        // Already running this backend: pin it for the next start, no
        // disruptive restart needed.
        root.restartQueued = mode !== root.activeBackend
        pinProc.command = ["bash", root.setter, mode]
        if (!pinProc.running) pinProc.running = true
    }

    function restartShell(): void {
        root.restartQueued = false
        // Detached so it survives the launcher stopping this instance. The
        // short delay lets the running frame finish before the window goes
        // away; the launcher itself waits for the process to exit before
        // booting the replacement.
        // The pacing variables are stripped from the inherited environment:
        // this process carries the pacing it was started with, and the
        // launcher's "only fill unset variables" rule would otherwise keep
        // replaying the old setting on every restart (the toggles would
        // stick). The launcher re-derives them from debug.json/gpu.conf.
        Quickshell.execDetached([
            "env",
            "-u", "QSG_USE_SIMPLE_ANIMATION_DRIVER",
            "-u", "QSG_FIXED_ANIMATION_STEP",
            "-u", "QSG_NO_VSYNC",
            "bash", "-c", "sleep 0.4; exec \"$1\" restart", "bash", root.launcher
        ])
    }

    Process {
        id: pinProc
        command: ["bash", root.setter, "opengl"]
        stderr: StdioCollector {
            onStreamFinished: {
                const e = (text || "").trim()
                if (e.length > 0) root.message = e
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.restartQueued = false
                root.pending = ""
                if (root.message.length === 0)
                    root.message = "Could not write backend/config/gpu.conf."
                return
            }
            if (root.restartQueued) root.restartShell()
            else root.pending = ""
        }
    }

    // ---- rendering -------------------------------------------------------
    NexusControls.SectionHeader { first: true; text: "Rendering" }
    NexusControls.ToggleRow {
        first: true
        text: "Vulkan renderer"
        subtext: root.toggleSubtext
        checked: root.vulkanOn
        onToggled: n => root.applyBackend(n ? "vulkan" : "opengl")
    }
    NexusControls.InfoRow {
        last: true
        icon: "󱤓"
        label: "Active renderer"
        subtext: "Qt scenegraph backend currently in use"
        value: root.activeName
    }
    NexusControls.Note {
        visible: root.message.length > 0
        color: Theme.error
        text: root.message
    }

    // ---- debug -----------------------------------------------------------
    // Frame pacing is baked in before Qt starts (QSG_* env vars are read at
    // scene-graph init), so changing the frame cap restarts the shell
    // through the launcher, which translates debug.json into the environment.
    readonly property bool activeSimpleDriver: {
        let v = Quickshell.env("QSG_USE_SIMPLE_ANIMATION_DRIVER")
        return v !== null && v !== undefined && ("" + v) !== "" && ("" + v) !== "0"
    }
    readonly property bool activeFixedStep: {
        let v = Quickshell.env("QSG_FIXED_ANIMATION_STEP")
        return v !== null && v !== undefined && ("" + v) !== "" && ("" + v) !== "no"
    }
    readonly property bool activeNoVsync: {
        let v = Quickshell.env("QSG_NO_VSYNC")
        return v !== null && v !== undefined && ("" + v) !== "" && ("" + v) !== "0"
    }
    readonly property string activePacing: root.activeFixedStep ? "60 FPS cap"
        : root.activeSimpleDriver ? (root.activeNoVsync ? "Uncapped" : "Display rate")
        : "Qt default"

    NexusControls.SectionHeader { text: "Debug" }
    NexusControls.ToggleRow {
        first: true
        text: "FPS overlay"
        subtext: "Live shell frame rate, bottom-right corner"
        checked: Theme.debugFpsEnabled
        onToggled: n => Theme.setDebugFpsEnabled(n)
    }
    NexusControls.DropdownRow {
        label: "Frame cap"
        subtext: "Hard 60 FPS cap, or the display's highest refresh rate"
        options: ["Display", "60 FPS"]
        current: Theme.debugFpsCap === "60" ? "60 FPS" : "Display"
        onPicked: v => {
            Theme.setDebugFpsCap(v)
            root.restartShell()
        }
    }
    NexusControls.InfoRow {
        last: true
        icon: "󰒓"
        label: "Active pacing"
        subtext: "Applied at shell start"
        value: root.activePacing
    }
    NexusControls.Note {
        text: "Frame pacing is fixed when Qt starts, so changing the frame cap restarts the shell."
    }
}
