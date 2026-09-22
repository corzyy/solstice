pragma Singleton
import QtQuick

// CarouselEffect — reusable math for centered cover-flow carousels.
//
// Extracted from the wallpaper-carousel prototype (variable-width ListView
// cards with parallax thumbnails) so every future carousel shares one
// implementation. Two pieces work together:
//
//  1. Growth: CarouselCard steps its width with the distance to the current
//     index (widthForOffset) while centerNorm tracks the card centre against
//     the viewport centre every frame while scrolling.
//  2. Parallax: an overscanned image (see CarouselParallaxImage, full bleed
//     width = card width + 2 * pad) pans with parallaxX(centerNorm, pad), so
//     the picture drifts against the scroll direction instead of sticking to
//     the card.
//
// Works for ListView delegates (centerNormList, content coordinates) and
// PathView delegates (centerNormPath, items already live in view
// coordinates). All outputs are plain values — animation curves/durations
// stay with the call site's Theme tokens.
QtObject {
    id: root

    // Clamp a raw centre distance to the [-1, 1] scroll range. Returns 0
    // when the range is not positive (misconfiguration instead of NaN).
    function norm(offset: real, range: real): real {
        if (!(range > 0)) return 0
        return Math.max(-1, Math.min(1, offset / range))
    }

    // ListView delegate: continuous position of the card centre relative to
    // the viewport centre. Bind itemX/itemWidth to the delegate's x/width.
    function centerNormList(itemX: real, itemWidth: real, contentX: real, viewWidth: real, range: real): real {
        return root.norm(itemX - contentX + itemWidth / 2 - viewWidth / 2, range)
    }

    // PathView delegate: items are positioned in view coordinates, so there
    // is no content offset to subtract.
    function centerNormPath(itemX: real, itemWidth: real, viewWidth: real, range: real): real {
        return root.norm(itemX + itemWidth / 2 - viewWidth / 2, range)
    }

    // Discrete card-size step from the distance to the current index:
    // 0 -> focused, ±1 -> neighbour, anything else -> distant.
    function widthForOffset(offset: int, focused: real, neighbour: real, distant: real): real {
        if (offset === 0) return focused
        if (offset === 1 || offset === -1) return neighbour
        return distant
    }

    // Parallax shift for an overscanned image: -pad rests the image while
    // the card is centred, ±pad pans it at the scroll extremes.
    function parallaxX(centerNorm: real, pad: real): real {
        return -pad - centerNorm * pad
    }

    // Full bleed width an image needs so the pan never exposes an edge.
    function parallaxWidth(cardWidth: real, pad: real): real {
        return cardWidth + 2 * pad
    }
}
