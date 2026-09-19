import QtQuick
import "../../themes"
import "../../ui"

// Volume slider in the settings app's M3 expressive style (Ui.MSlider, same
// component family as NexusControls.SliderRow), dialed to a thick rounded
// variant: 32dp track with a 12dp radius, 6dp gap around the handle, stop
// dot at the inactive end and a floating value bubble on hover/drag.
//
// `value` is a caller-owned binding target: the internal control owns the
// live value while dragging (extValue pattern from the settings SliderRow),
// so a `value: VolumeService.pct / 100` binding is never destroyed by
// interaction — volume keys keep moving the slider.
Item {
    id: control

    property real value: 0
    property bool muted: false

    signal userMoved(real value)

    implicitWidth: slider.implicitWidth
    implicitHeight: slider.implicitHeight

    onValueChanged: if (!slider.dragging) slider.value = control.value
    Component.onCompleted: slider.value = control.value

    MSlider {
        id: slider
        from: 0
        to: 1
        trackHeight: 32
        trackRadius: 12
        trackInnerRadius: 12
        handleWidth: 8
        handleHeight: 44
        handleRadius: 3
        indicatorRadius: 8
        valueText: Math.round(slider.value * 100) + "%"
        activeTrackColor: control.muted ? Theme.textMuted : Theme.primary
        handleColor: control.muted ? Theme.textMuted : Theme.primary
        stateLayerColor: control.muted ? Theme.textMuted : Theme.primary
        onMoved: v => control.userMoved(v)
    }
}
