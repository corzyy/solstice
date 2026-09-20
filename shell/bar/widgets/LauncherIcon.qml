pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../themes"

// OS launcher icon — the bar module that opens the app launcher.
//
// The glyph is resolved from /etc/os-release at runtime, so the module shows
// the logo of whatever distro the shell runs on (Fedora, Arch, EndeavourOS,
// Debian, …) with a Tux fallback. Glyphs come from the Nerd Font linux set
// (nf-linux-*) of Theme.iconFontFamily. Left-click is routed through
// BarModule/BarSlot like every other module (this item owns no MouseArea);
// the shared background card follows the workspaces card
// (Theme.barBackgroundEnabled maps "launcher" onto "workspaces").
Item {
    id: root
    property bool vertical: false
    property bool slotHovered: false

    // ---- distro detection ------------------------------------------------
    property string osId: ""
    property string osIdLike: ""
    FileView {
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            const lines = text().split("\n")
            const field = key => {
                const line = lines.find(l => l.startsWith(key + "="))
                return line ? line.slice(key.length + 1).replace(/^"|"$/g, "").trim().toLowerCase() : ""
            }
            root.osId = field("ID")
            root.osIdLike = field("ID_LIKE")
        }
    }
    // Nerd Font nf-linux-* codepoints (verified against JetBrainsMono Nerd
    // Font). Unknown distros get Tux; ID_LIKE is consulted before that.
    readonly property var distroGlyphs: ({
        alpine: "\uf300", aosc: "\uf301", apple: "\uf302",
        arch: "\uf303", archarm: "\uf303", archlabs: "\uf31e", archcraft: "\uf345", arcolinux: "\uf346",
        artix: "\uf31f", almalinux: "\uf31d",
        centos: "\uf304", coreos: "\uf305", cachyos: "\uf385",
        debian: "\uf306", devuan: "\uf307", deepin: "\uf321",
        elementary: "\uf309", endeavouros: "\uf322",
        fedora: "\uf30a", freebsd: "\uf30c",
        garuda: "\uf337", gentoo: "\uf30d", guix: "\uf325",
        kali: "\uf327", kdeneon: "\uf331", kubuntu: "\uf333",
        linuxmint: "\uf30e", mageia: "\uf310", mandriva: "\uf311", manjaro: "\uf312",
        mx: "\uf33f", nobara: "\uf380", nixos: "\uf313",
        opensuse: "\uf314", "opensuse-leap": "\uf37e", "opensuse-tumbleweed": "\uf37d",
        openwrt: "\uf382", parrot: "\uf329", pop: "\uf32a",
        qubes: "\uf342", raspbian: "\uf315", rhel: "\uf316", redhat: "\uf316",
        rocky: "\uf32b", sabayon: "\uf317", slackware: "\uf318",
        solus: "\uf32d", suse: "\uf314", tails: "\uf343", trisquel: "\uf344",
        ubuntu: "\uf31b", void: "\uf32e", zorin: "\uf32f",
        linux: "\uf31a"
    })
    readonly property string osGlyph: {
        const map = root.distroGlyphs
        if (root.osId.length > 0 && map[root.osId] !== undefined) return map[root.osId]
        const likes = root.osIdLike.split(/\s+/)
        for (let i = 0; i < likes.length; i++) {
            if (likes[i].length > 0 && map[likes[i]] !== undefined) return map[likes[i]]
        }
        return "\uf31a"
    }

    implicitWidth: vertical ? 28 : label.implicitWidth + 16
    implicitHeight: vertical ? 26 : Math.max(24, label.implicitHeight + 8)

    Item {
        id: scaleWrap
        anchors.centerIn: parent
        width: label.implicitWidth
        height: label.implicitHeight
        scale: root.slotHovered ? Theme.hoverScale : 1
        transformOrigin: Item.Center
        Behavior on scale {
            enabled: Theme.animationsEnabled
            NumberAnimation { duration: Theme.durFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveFastSpatial }
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: root.osGlyph
            color: root.slotHovered ? Theme.accent : Theme.textPrimary
            font.family: Theme.iconFontFamily
            font.pixelSize: Theme.fs(18)
            antialiasing: Theme.textAa
            renderType: Theme.textRenderType
            Behavior on color {
                enabled: Theme.animationsEnabled
                ColorAnimation { duration: Theme.durSlowEffects; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSlowEffects }
            }
        }
    }
}
