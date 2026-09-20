pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import "../../../themes"
import "../../../util"
import ".."

// About — Android-style system information page. Mirrors the Nexus
// About layout: a hero card (OS logo, name, version) over grouped
// System / Hardware rows. Everything is probed live so the
// page always describes the running install.
NexusControls.PageBase {
    id: root
    title: "About"

    // ---- identity ------------------------------------------------------
    property string osName: ""
    property string osPrettyName: ""
    property string osVersionId: ""
    property string osLogoSource: ""
    property string hostname: ""
    property string kernel: ""
    property string boardVendor: ""
    property string boardName: ""
    property string firmware: ""
    // Hardware
    property string cpuName: ""
    property string gpuName: ""
    property string memory: ""
    property string storage: ""
    property string mainboardVendor: ""
    property string mainboardName: ""

    // "Fedora Linux" -> "Fedora"; other distro names pass through.
    readonly property string heroName: {
        const n = root.osName.replace(/\s+Linux$/i, "").trim()
        if (n.length > 0) return n
        return root.osPrettyName.length > 0 ? root.osPrettyName : "Linux"
    }
    readonly property string heroVersion: root.osVersionId

    // DMI fields often carry OEM placeholder strings; drop those.
    function sanitiseDmi(s: string): string {
        const t = (s || "").trim()
        const junk = ["to be filled by o.e.m.", "system product name", "system manufacturer", "system version", "default string", "o.e.m.", "not specified", "not applicable", "unknown", "none", ""]
        return junk.indexOf(t.toLowerCase()) >= 0 ? "" : t
    }
    // Vendor + model, dropping the vendor when the model already names it.
    readonly property string device: {
        if (root.boardName.length === 0) return root.boardVendor
        if (root.boardVendor.length === 0 || root.boardName.toLowerCase().indexOf(root.boardVendor.toLowerCase()) === 0) return root.boardName
        return root.boardVendor + " " + root.boardName
    }
    readonly property string mainboard: {
        if (root.mainboardName.length === 0) return root.mainboardVendor
        if (root.mainboardVendor.length === 0 || root.mainboardName.toLowerCase().indexOf(root.mainboardVendor.toLowerCase()) === 0) return root.mainboardName
        return root.mainboardVendor + " " + root.mainboardName
    }
    // lsblk size ("1.8T") -> human ("1.8 TB").
    function sizeText(s: string): string {
        return (s || "").replace(",", ".").replace(/^([\d.]+)([KMGTPE])$/, "$1 $2B")
    }

    // ---- system sources --------------------------------------------------
    FileView {
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            const lines = text().split("\n")
            const field = key => {
                const line = lines.find(l => l.startsWith(key + "="))
                return line ? line.slice(key.length + 1).replace(/^"|"$/g, "") : ""
            }
            root.osName = field("NAME")
            root.osPrettyName = field("PRETTY_NAME")
            root.osVersionId = field("VERSION_ID")
            root.osLogoSource = Util.iconSource(field("LOGO"), "")
        }
    }
    FileView { path: "/proc/sys/kernel/hostname"; printErrors: false; onLoaded: root.hostname = text().trim() }
    FileView { path: "/proc/sys/kernel/osrelease"; printErrors: false; onLoaded: root.kernel = text().trim() }
    FileView { path: "/sys/class/dmi/id/sys_vendor"; printErrors: false; onLoaded: root.boardVendor = root.sanitiseDmi(text()) }
    FileView { path: "/sys/class/dmi/id/product_name"; printErrors: false; onLoaded: root.boardName = root.sanitiseDmi(text()) }
    FileView { path: "/sys/class/dmi/id/bios_version"; printErrors: false; onLoaded: root.firmware = root.sanitiseDmi(text()) }
    FileView {
        path: "/proc/cpuinfo"
        printErrors: false
        onLoaded: {
            const line = text().split("\n").find(l => /^model name\s*:/.test(l))
            root.cpuName = line ? line.slice(line.indexOf(":") + 1).trim() : ""
        }
    }
    FileView {
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const line = text().split("\n").find(l => l.startsWith("MemTotal:"))
            const m = line ? line.match(/(\d+)/) : null
            root.memory = m ? (parseInt(m[1], 10) / 1048576).toFixed(1) + " GiB" : ""
        }
    }
    FileView { path: "/sys/class/dmi/id/board_vendor"; printErrors: false; onLoaded: root.mainboardVendor = root.sanitiseDmi(text()) }
    FileView { path: "/sys/class/dmi/id/board_name"; printErrors: false; onLoaded: root.mainboardName = root.sanitiseDmi(text()) }

    // ---- hardware sources ------------------------------------------------
    Process {
        running: true
        command: ["lspci", "-mm"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = []
                for (const line of text.trim().split("\n")) {
                    const fields = line.split('"').filter((_, i) => i % 2 === 1)
                    if (fields.length < 3 || !/^(VGA|3D|Display)/i.test(fields[0])) continue
                    const vendor = fields[1].replace(/[,\s]+(Corporation|Inc\.?|Ltd\.?|LLC)$/i, "")
                    let name = fields[2]
                    if (/^Device\s/i.test(name)) name = (vendor + " " + name).trim()
                    if (name.length > 0) names.push(name)
                }
                root.gpuName = names.join(" + ")
            }
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "LC_ALL=C lsblk -dno NAME,SIZE,RM,ROTA -P -e 7,11,1 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = []
                for (const line of text.trim().split("\n")) {
                    if (line.length === 0) continue
                    const field = key => {
                        const m = line.match(new RegExp(key + '="([^"]*)"'))
                        return m ? m[1] : ""
                    }
                    const name = field("NAME")
                    if (name.indexOf("zram") === 0) continue
                    const size = root.sizeText(field("SIZE"))
                    if (size.length === 0) continue
                    let kind
                    if (field("RM") === "1") kind = "USB"
                    else if (name.indexOf("nvme") === 0) kind = "NVMe SSD"
                    else if (field("ROTA") === "1") kind = "HDD"
                    else kind = "SSD"
                    parts.push(size + " " + kind)
                }
                root.storage = parts.join(" + ")
            }
        }
    }

    // ---- hero ------------------------------------------------------------
    NexusControls.ConnectedRect {
        first: true
        last: true
        width: parent.width
        height: hero.implicitHeight + 64

        Column {
            id: hero
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 8

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 116
                height: 84
                Image {
                    id: osLogo
                    anchors.fill: parent
                    source: root.osLogoSource
                    sourceSize: Qt.size(256, 256)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready
                }
                // Distro logo fallback when os-release names an icon that
                // is not installed.
                HeroLogo {
                    anchors.fill: parent
                    visible: !osLogo.visible
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.heroName
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(28)
                font.weight: Font.Medium
                color: Theme.textPrimary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.heroVersion.length > 0
                text: root.heroVersion
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                color: Theme.textSecondary
                antialiasing: Theme.textAa
                renderType: Theme.textRenderType
            }
        }
    }

    // ---- system ----------------------------------------------------------
    NexusControls.SectionHeader { text: "System" }
    NexusControls.InfoRow { first: true; label: "Hostname"; value: root.hostname || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { label: "Device"; value: root.device || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { label: "Distro"; value: root.osPrettyName || root.osName || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { label: "Kernel"; value: root.kernel || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { last: true; label: "Firmware"; value: root.firmware || "…"; valueMaxWidth: Math.round(width * 0.62) }

    // ---- hardware --------------------------------------------------------
    NexusControls.SectionHeader { text: "Hardware" }
    NexusControls.InfoRow { first: true; label: "Processor"; value: root.cpuName || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { label: "Graphics"; value: root.gpuName || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { label: "Memory"; value: root.memory || "…" }
    NexusControls.InfoRow { label: "Storage"; value: root.storage || "…"; valueMaxWidth: Math.round(width * 0.62) }
    NexusControls.InfoRow { last: true; label: "Motherboard"; value: root.mainboard || "…"; valueMaxWidth: Math.round(width * 0.62) }

    // Caelestia mark, used when the distro logo cannot be resolved.
    component HeroLogo: Item {
        id: logoRoot
        readonly property real designWidth: 128
        readonly property real designHeight: 90.38

        Shape {
            anchors.centerIn: parent
            width: logoRoot.designWidth
            height: logoRoot.designHeight
            scale: Math.min(logoRoot.width / width, logoRoot.height / height)
            transformOrigin: Item.Center
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: Theme.primary
                strokeColor: "transparent"
                PathSvg { path: "m42.56,42.96c-7.76,1.6-16.36,4.22-22.44,6.22-.49.16-.88-.44-.53-.82,5.37-5.85,9.66-13.3,9.66-13.3,8.66-14.67,22.97-23.51,39.85-21.14,6.47.91,12.33,3.38,17.26,6.98.99.72,1.14,2.14.31,3.04-.4.44-.95.67-1.51.67-.34,0-.69-.09-1-.26-3.21-1.84-6.82-2.69-10.71-3.24-13.1-1.84-25.41,4.75-31.06,15.83-.94,1.84-.61,3.81.45,5.21.22.3.07.72-.29.8Z" }
            }
            ShapePath {
                fillColor: Theme.textPrimary
                strokeColor: "transparent"
                PathSvg { path: "m103.02,51.8c-.65.11-1.26-.37-1.28-1.03-.06-1.96.15-3.89-.2-5.78-.28-1.48-1.66-2.5-3.16-2.34h-.05c-6.53.73-24.63,3.1-48,9.32-6.89,1.83-9.83,10-5.67,15.79,4.62,6.44,11.84,10.93,20.41,12.13,11.82,1.66,22.99-3.36,29.21-12.65.54-.81,1.54-1.17,2.47-.86.91.3,1.47,1.15,1.47,2.04,0,.33-.08.66-.24.98-7.23,14.21-22.91,22.95-39.59,20.6-7.84-1.1-14.8-4.5-20.28-9.43,0,0,0,0-.02-.01-7.28-5.14-14.7-9.99-27.24-11.98-18.82-2.98-9.53-8.75.46-13.78,7.36-3.13,25.17-7.9,36.24-10.73.16-.03.31-.06.47-.1,1.52-.4,3.2-.83,5.02-1.29,1.06-.26,1.93-.48,2.58-.64.09-.02.18-.04.26-.06.31-.08.56-.14.73-.18.03,0,.06-.01.08-.02.03,0,.05-.01.07-.02.02,0,.04,0,.06-.01.01,0,.03,0,.04-.01,0,0,.02,0,.03,0,.01,0,.02,0,.02,0,10.62-2.58,24.63-5.62,37.74-7.34,1.02-.13,2.03-.26,3.03-.37,7.49-.87,14.58-1.26,20.42-.81,25.43,1.95-4.71,16.77-15.12,18.61Z" }
            }
            ShapePath {
                fillColor: Theme.primary
                strokeColor: "transparent"
                PathSvg { path: "m98.12.06c-.29,2.08-1.72,8.42-8.36,9.19-.09,0-.09.13,0,.14,6.64.78,8.07,7.11,8.36,9.19.01.08.13.08.14,0,.29-2.08,1.72-8.42,8.36-9.19.09,0,.09-.13,0-.14-6.64-.78-8.07-7.11-8.36-9.19-.01-.08-.13-.08-.14,0Z" }
            }
            ShapePath {
                fillColor: Theme.primary
                strokeColor: "transparent"
                PathSvg { path: "m113.36,15.5c-.22,1.29-1.08,4.35-4.38,4.87-.08.01-.08.13,0,.14,3.3.52,4.17,3.58,4.38,4.87.01.08.13.08.14,0,.22-1.29,1.08-4.35,4.38-4.87.08-.01.08-.13,0-.14-3.3-.52-4.17-3.58-4.38-4.87-.01-.08-.13-.08-.14,0Z" }
            }
            ShapePath {
                fillColor: Theme.primary
                strokeColor: "transparent"
                PathSvg { path: "m112.69,65.22c-.19,1.01-.86,3.15-3.2,3.57-.08.01-.08.13,0,.14,2.34.42,3.01,2.56,3.2,3.57.01.08.13.08.14,0,.19-1.01.86-3.15,3.2-3.57.08-.01.08-.13,0-.14-2.34-.42-3.01-2.56-3.2-3.57-.01-.08-.13-.08-.14,0Z" }
            }
        }
    }
}
