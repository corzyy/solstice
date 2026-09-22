pragma ComponentBehavior: Bound

import QtQuick
import "../themes"

Item {
    id: root
    visible: false

    required property string moduleId
    property real panelWidth: 380
    property real panelHeight: 400
    property real screenWidth: 0
    property real screenHeight: 0
    property real gap: 0
    property real margin: 12
    property real fallbackX: 0
    property real fallbackY: 0

    readonly property var anchor: Theme.barAnchor(moduleId)
    readonly property bool valid: anchor !== null
    readonly property real cx: valid ? anchor.x + anchor.w / 2 : fallbackX + panelWidth / 2
    readonly property real cy: valid ? anchor.y + anchor.h / 2 : fallbackY + panelHeight / 2

    readonly property var winRect: Theme.barWindowRect
    readonly property real barExcl: Theme.barEffectiveHeight + Theme.barTopDistance
    readonly property real fullH: screenHeight + barExcl
    readonly property real winEdge: {
        try {
            let r = winRect
            if (r && r.w > 0 && r.h > 0) {
                return r.y + r.h
            }
        } catch (e) { }
        return Theme.barEffectiveHeight + Theme.barTopDistance
    }
    readonly property real edgeOffset: winEdge + gap - Theme.barTopDistance

    // Zentriert um center, hält margin zu beiden Screen-Rändern ein.
    function clampToScreen(center: real, size: real, total: real): real {
        return Math.max(margin, Math.min(center - size / 2, total - size - margin))
    }

    readonly property real panelX: {
        if (!valid) return fallbackX
        return clampToScreen(cx, panelWidth, screenWidth)
    }
    readonly property real panelY: edgeOffset

    readonly property int origin: computeOrigin()

    // Einstiegspunkt der Panel-Animation.
    readonly property real slideFromX: 0
    readonly property real slideFromY: -Theme.panelSlideOffset

    // Verankerungs-Ursprung: Drittelt den Screen, damit Panels zum Rand hin öffnen.
    function computeOrigin(): int {
        const third = screenWidth / 3
        if (cx < third)
            return Item.TopLeft
        if (cx > screenWidth - third)
            return Item.TopRight
        return Item.Top
    }
}
