pragma ComponentBehavior: Bound
import QtQuick
import "../../../themes"
import "../../../services"
import ".."

NexusControls.PageBase {
    id: root
    title: "Vitals"

    // Metrik-Text je Kennung (ein Pfad statt verschachteltem Ternary).
    function metricTextFor(id: string): string {
        if (id === "cpu") return Math.round(VitalsService.cpuPct) + "%"
        if (id === "ram") return Math.round(VitalsService.ramPct) + "%"
        if (id === "gpu") return Math.round(VitalsService.gpuPct) + "%"
        return "" + VitalsService.topProcs.length
    }

    NexusControls.SectionHeader { first: true; text: "Meters" }
    Grid {
        width: parent.width
        columns: 2
        spacing: 8
        Repeater {
            model: [
                { id: "cpu", label: "CPU", icon: "󰻠", flag: "showCpu", defTrue: false },
                { id: "ram", label: "RAM", icon: "󰍛", flag: "showRam", defTrue: false },
                { id: "gpu", label: "GPU", icon: "󰢮", flag: "showGpu", defTrue: false },
                { id: "top", label: "Processes", icon: "", flag: "showTopProcs", defTrue: true }
            ]
            delegate: NexusControls.PreviewTile {
                required property var modelData
                readonly property string metricId: modelData.id
                readonly property bool isAvail: metricId === "top" ? true : metricId !== "gpu" || VitalsService.gpuAvailable
                // Flag-Lesart je Metrik (defTrue: !==-false-Semantik wie im Service).
                readonly property bool isCurrent: isAvail && (modelData.defTrue ? VitalsService[modelData.flag] !== false : !!VitalsService[modelData.flag])
                readonly property string metricText: !isAvail ? "–" : root.metricTextFor(metricId)
                width: (parent.width - 8) / 2
                height: 64
                selected: isCurrent
                interactionEnabled: isAvail
                label: modelData.label
                contentSpacing: 4
                onClicked: VitalsService.setFlag(modelData.flag, !isCurrent, modelData.defTrue)
                Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            text: modelData.icon
                            font.family: Theme.iconFontFamily
                            font.pixelSize: Theme.fs(14)
                            color: isCurrent ? Theme.textPrimary : Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            antialiasing: Theme.textAa
                            renderType: Theme.textRenderType
                            text: metricText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.Medium
                            color: isCurrent ? Theme.textPrimary : Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }

    NexusControls.SectionHeader { text: "Thresholds" }
    NexusControls.SliderRow { first: true; label: "Refresh"; from: 1; to: 10; stepSize: 1; unit: "s"; value: VitalsService.refreshSeconds; onMoved: v => VitalsService.setRefreshSeconds(Math.round(v)); onApplied: v => VitalsService.setRefreshSeconds(Math.round(v)) }
    NexusControls.SliderRow { label: "Warn at"; from: 10; to: 95; stepSize: 1; unit: "%"; value: VitalsService.warnThreshold; onMoved: v => VitalsService.setWarnThreshold(Math.round(v)); onApplied: v => VitalsService.setWarnThreshold(Math.round(v)) }
    NexusControls.SliderRow { last: true; label: "Critical at"; from: 20; to: 99; stepSize: 1; unit: "%"; value: VitalsService.critThreshold; onMoved: v => VitalsService.setCritThreshold(Math.round(v)); onApplied: v => VitalsService.setCritThreshold(Math.round(v)) }
}
