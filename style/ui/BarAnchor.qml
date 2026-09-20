pragma ComponentBehavior: Bound

import QtQuick
import "../themes"

Item {
    id: root
    visible: false

    required property string moduleId
    property string barPos: "top"
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
    readonly property bool isVertical: barPos === "left" || barPos === "right"

    readonly property var winRect: Theme.barWindowRect
    readonly property real barExcl: (isVertical ? Theme.barEffectiveWidth : Theme.barEffectiveHeight) + Theme.barTopDistance
    readonly property real fullW: screenWidth + (isVertical ? barExcl : 0)
    readonly property real fullH: screenHeight + (isVertical ? 0 : barExcl)
    readonly property real winEdge: {
        try {
            let r = winRect
            if (r && r.w > 0 && r.h > 0) {
                if (barPos === "bottom") return fullH - r.y
                if (barPos === "left") return r.x + r.w
                if (barPos === "right") return fullW - r.x
                return r.y + r.h
            }
        } catch (e) { }
        let base = isVertical ? Theme.barEffectiveWidth : Theme.barEffectiveHeight
        return base + Theme.barTopDistance
    }
    readonly property real edgeOffset: winEdge + gap - Theme.barTopDistance

    // Zentriert um center, hält margin zu beiden Screen-Rändern ein.
    function clampToScreen(center: real, size: real, total: real): real {
        return Math.max(margin, Math.min(center - size / 2, total - size - margin))
    }

    readonly property real panelX: {
        if (barPos === "left") return edgeOffset
        if (barPos === "right") return screenWidth - panelWidth - edgeOffset
        if (!valid) return fallbackX
        return clampToScreen(cx, panelWidth, screenWidth)
    }
    readonly property real panelY: {
        if (isVertical) {
            if (!valid) return fallbackY
            return clampToScreen(cy, panelHeight, screenHeight)
        }
        if (barPos === "bottom") return screenHeight - panelHeight - edgeOffset
        return edgeOffset
    }

    readonly property int origin: computeOrigin()

    // Einstiegspunkt der Panel-Animation je nach Bar-Position.
    readonly property real slideFromX: barPos === "left" ? -Theme.panelSlideOffset : barPos === "right" ? Theme.panelSlideOffset : 0
    readonly property real slideFromY: barPos === "top" ? -Theme.panelSlideOffset : barPos === "bottom" ? Theme.panelSlideOffset : 0

    // Verankerungs-Ursprung: Drittelt den Screen, damit Panels zum Rand hin öffnen.
    function computeOrigin(): int {
        if (isVertical) {
            const third = screenHeight / 3
            const top = cy < third
            const bottom = cy > screenHeight - third
            if (barPos === "left")
                return top ? Item.TopLeft : bottom ? Item.BottomLeft : Item.Left
            return top ? Item.TopRight : bottom ? Item.BottomRight : Item.Right
        }
        const third = screenWidth / 3
        const bottom = barPos === "bottom"
        if (cx < third)
            return bottom ? Item.BottomLeft : Item.TopLeft
        if (cx > screenWidth - third)
            return bottom ? Item.BottomRight : Item.TopRight
        return bottom ? Item.Bottom : Item.Top
    }
}
