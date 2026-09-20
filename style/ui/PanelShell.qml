// PanelShell — shared container for all bar panels.
//
// The open/close run is the 1:1 Caelestia popout animation (ui/CaelestiaPopout
// — ClipWrapper + Wrapper + Content): the card is clipped at the bar's inner
// edge and slides out from behind it on the expressive default spatial curve
// (500ms) while the popout fades in over 200ms, exactly like the reference.
// The old pill/size/scale morph is gone: Caelestia's popouts keep their full
// size and are revealed by the curtain, so nothing reflows.
//
// Usage: PanelShell { moduleId: "volume"; shown: scope.showVolume; ... }
pragma ComponentBehavior: Bound
import QtQuick
import "../themes"

Item {
    id: root

    required property string moduleId
    // Bar module whose anchor the panel settles under. Defaults to moduleId;
    // drill-in panels whose own id has no bar widget (audio) share the
    // anchor of the panel they morph out of.
    property string anchorModuleId: root.moduleId
    property string barPos: "top"
    property real panelGap: 0
    // Overlay drill-ins (control-center sub-panels): settle this far from
    // the fused bar edge so the panel under it (the control center) stays
    // visible above. 0 keeps the card attached to the bar as usual.
    property real edgeInset: 0
    // Theme.isPrimaryScreen(modelData): only that window runs the
    // cross-panel morph (see CaelestiaPopout).
    property bool screenActive: true
    required property bool shown
    property real boxWidth: 340
    property real minHeight: 120
    // Extra height added to content (Flickable margins + breathing room).
    property real heightPadding: 20
    property real contentMargins: 10
    property real contentSpacing: 8

    default property alias content: contentCol.children

    // Full (open) card height; changes glide inside the popout while open.
    readonly property real cardHeight: Math.max(minHeight, Math.min(contentCol.implicitHeight + heightPadding, shellAnchor.screenHeight - shellAnchor.edgeOffset - root.edgeInset - 24))
    // Settled position of the fused edge, shifted off the bar by edgeInset
    // (per bar side: top/left grow away from the bar, bottom/right shrink
    // toward it).
    readonly property real cardEdge: {
        if (root.barPos === "bottom") return shellAnchor.panelY + root.cardHeight - root.edgeInset
        if (root.barPos === "right") return shellAnchor.panelX + root.boxWidth - root.edgeInset
        if (root.barPos === "left") return shellAnchor.panelX + root.edgeInset
        return shellAnchor.panelY + root.edgeInset
    }

    BarAnchor {
        id: shellAnchor
        moduleId: root.anchorModuleId
        barPos: root.barPos
        panelWidth: root.boxWidth
        panelHeight: root.cardHeight
        screenWidth: root.parent.width
        screenHeight: root.parent.height
        gap: root.panelGap
        fallbackX: (root.parent.width - root.boxWidth) / 2
        fallbackY: (root.parent.height - root.cardHeight) / 2
    }

    CaelestiaPopout {
        id: popout

        shown: root.shown
        morphId: root.moduleId
        morphActive: root.screenActive
        barPos: root.barPos
        fullWidth: root.boxWidth
        fullHeight: root.cardHeight
        anchorCenter: shellAnchor.isVertical ? shellAnchor.cy : shellAnchor.cx
        // Bar inner edge: the fixed edge the curtain reveals from (shifted
        // by edgeInset for detached overlay drill-ins).
        edge: root.cardEdge
        edgeInset: root.edgeInset
        screenSize: shellAnchor.isVertical ? shellAnchor.screenHeight : shellAnchor.screenWidth
        margin: shellAnchor.margin

        Rectangle {
            id: card

            // Frame: stretched by the popout (top edge pinned at the bar),
            // radius clamped while short so it reads as a pill being pulled
            // out of the bar.
            width: parent.width
            height: parent.height
            antialiasing: Theme.shapesAa
            // Fill comes from the popout's shadow layer (see CaelestiaPopout
            // shadowSource): it paints the same rounded silhouette behind
            // this card so the shadow silhouette is only composited once.
            color: "transparent"
            border.color: Theme.panelBorderColor
            border.width: 2
            // Bar-side corners square, free corners rounded (fused joint).
            // Driven by the popout's fused flags (which fall away for a
            // detached edgeInset card, matching the shadow silhouette).
            topLeftRadius: (popout.fusedTop || popout.fusedLeft) ? 0 : popout.frameRadius
            topRightRadius: (popout.fusedTop || popout.fusedRight) ? 0 : popout.frameRadius
            bottomLeftRadius: (popout.fusedBottom || popout.fusedLeft) ? 0 : popout.frameRadius
            bottomRightRadius: (popout.fusedBottom || popout.fusedRight) ? 0 : popout.frameRadius
            // Clip the content to the card: while a morph runs the frame is
            // smaller than the full-size content layout, and without this
            // the overflow would paint into the popout's shadow padding
            // (a band of panel content outside the shrinking card).
            clip: true

            // Swallow clicks/wheel so they don't dismiss the panel. Off
            // while closing: the window outlives the card (morph/close
            // hold) and must not steal input from the panel on top.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                enabled: root.shown
                onClicked: mouse => mouse.accepted = true
                onPressed: mouse => mouse.accepted = true
                onWheel: wheel => wheel.accepted = true
            }

            // Seam strip: erases the collar outline along the fused edge so
            // the joint reads as one mass. Same background, below content.
            // Only needed while the accent border draws that outline; with the
            // transparent default it would just double-paint the card top.
            Rectangle {
                antialiasing: Theme.shapesAa
                visible: Theme.panelAccentBorder && root.edgeInset === 0
                x: 0
                y: root.barPos === "bottom" ? root.cardHeight - 2 : 0
                width: root.boxWidth
                height: 2
                color: Theme.panelWindowBg
            }

            Flickable {
                // Content moves independently of the frame: always laid out
                // at the full panel size (so nothing reflows mid-stretch) and
                // travelled by the popout's own content driver.
                x: root.contentMargins + popout.contentX
                y: root.contentMargins + popout.contentY
                width: root.boxWidth - root.contentMargins * 2
                height: popout.fullHeight - root.contentMargins * 2
                contentHeight: contentCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                // Cross-panel morph choreography: the outgoing content
                // shifts/scales out, the incoming one shifts/scales in
                // (direction-aware, see ui/CaelestiaPopout). Button-origin
                // runs additionally shrink the layout with the frame
                // (contentShrink), so the panel is a miniature of itself
                // while it grows out of / collapses into its button.
                scale: popout.contentScale * popout.contentShrink
                // The shrink anchors at the card's top-left — the corner the
                // button sits in (center origin would let the content drift
                // away from the collapsing frame).
                transformOrigin: Item.TopLeft
                transform: Translate { x: popout.contentOffsetX; y: popout.contentOffsetY }
                // Popout transition (Caelestia Content/Popout loader fades):
                // slow effects in, default effects out. No scale/rise — the
                // reference only folds the content. contentFade additionally
                // hides the full-size layout while the card morphs between
                // panel poses (see CaelestiaPopout).
                opacity: popout.innerFade * popout.contentFade
                Column {
                    id: contentCol
                    width: root.boxWidth - root.contentMargins * 2
                    spacing: root.contentSpacing
                }
            }
        }
    }
}
