// PanelShell — shared container for all bar panels.
//
// The open/close run is the 1:1 Caelestia popout animation (style/ui/CaelestiaPopout
// — ClipWrapper + Wrapper + Content): the card is clipped at the bar's inner
// edge and slides out from behind it on the expressive default spatial curve
// (500ms) while the popout fades in over 200ms, exactly like the reference.
// The old pill/size/scale morph is gone: Caelestia's popouts keep their full
// size and are revealed by the curtain, so nothing reflows.
//
// Overlay drill-ins (control-center sub-panels) add the container transform:
// the clicked tile/button is re-rendered from its own component (published
// with the origin) as a replica that fills the card at the origin pose and
// morphs into the page header (morphTarget) while the card grows out of the
// origin rect. The page content follows behind the replica, so the panel
// reads as the source tile expanding rather than a miniature of the page
// scaling up.
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
    property real panelGap: 0
    // Item in the content the source replica morphs into (usually the page
    // header). Its settled pose supplies the replica's target rect.
    // The replica component itself rides the overlay run: it is published
    // with the origin by the control center (PanelMorph.publishOrigin) and
    // claimed by the popout (CaelestiaPopout._morphSource); see morphReplica.
    property Item morphTarget: null
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
    // Settled position of the fused edge, shifted off the bar by edgeInset.
    readonly property real cardEdge: shellAnchor.panelY + root.edgeInset

    BarAnchor {
        id: shellAnchor
        moduleId: root.anchorModuleId
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
        fullWidth: root.boxWidth
        fullHeight: root.cardHeight
        anchorCenter: shellAnchor.cx
        // Bar inner edge: the fixed edge the curtain reveals from (shifted
        // by edgeInset for detached overlay drill-ins).
        edge: root.cardEdge
        edgeInset: root.edgeInset
        screenSize: shellAnchor.screenWidth
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
            topLeftRadius: popout.fusedTop ? 0 : popout.frameRadius
            topRightRadius: popout.fusedTop ? 0 : popout.frameRadius
            bottomLeftRadius: popout.frameRadius
            bottomRightRadius: popout.frameRadius
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
                y: 0
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
                boundsBehavior: Flickable.DragAndOvershootBounds
                boundsMovement: Flickable.FollowBoundsBehavior
                interactive: contentHeight > height
                // Cross-panel morph choreography: the outgoing content
                // shifts/scales out, the incoming one shifts/scales in
                // (direction-aware, see style/ui/CaelestiaPopout). Overlay
                // drill-ins crossfade from their source replica instead of
                // scaling (see morphReplica below).
                scale: popout.contentScale
                // The fade/scale anchors at the card's top-left — the corner
                // the button sits in (center origin would let the content
                // drift away from the collapsing frame).
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

            // Container transform: a replica of the clicked tile/button
            // rendered from the same component, filling the card at the
            // origin pose and morphing into the page header while the card
            // grows out of the origin rect. Purely visual (disabled), it
            // crossfades with the page content on `morphReplicaOpacity`.
            // Card-local coordinates: at `_morphT` 0 the card's top-left
            // sits exactly on the origin rect (CaelestiaPopout._fromEdge),
            // so the replica starts as (0, 0, _fromW, _fromH).
            Loader {
                id: morphReplica

                active: popout._morphSource !== null && (popout._morphIn || popout._morphBack)
                sourceComponent: active && popout._morphSource
                    ? popout._morphSource.component
                    : null
                asynchronous: false
                // Never takes clicks/hover: the replica is a transition
                // visual, the live controls sit in the content underneath.
                enabled: false
                z: 10

                // Settled pose of the morph target in card coordinates.
                readonly property rect target: {
                    const item = root.morphTarget
                    if (item === null)
                        return Qt.rect(root.contentMargins, root.contentMargins,
                            root.boxWidth - root.contentMargins * 2, Math.max(48, popout._fromH))
                    const p = item.mapToItem(contentCol, 0, 0)
                    return Qt.rect(root.contentMargins + p.x, root.contentMargins + p.y, item.width, item.height)
                }
                // Clamped: the open curve can overshoot past 1, and the
                // replica must not poke out of the card while it settles.
                readonly property real t: Math.max(0, Math.min(1, popout._morphT))
                // Ceil'd like the frame (CaelestiaPopout.frameExtent), so the
                // replica covers the card exactly on the takeover frame.
                readonly property real fromW: Math.ceil(popout._fromW)
                readonly property real fromH: Math.ceil(popout._fromH)
                x: target.x * t
                y: target.y * t
                width: fromW + (target.width - fromW) * t
                height: fromH + (target.height - fromH) * t
                opacity: popout.morphReplicaOpacity

                onLoaded: {
                    item.enabled = false
                    const src = popout._morphSource
                    if (!src || !src.props)
                        return
                    for (const k in src.props) {
                        try { item[k] = src.props[k] } catch (e) { }
                    }
                }
            }
        }
    }
}
