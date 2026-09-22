pragma ComponentBehavior: Bound
import QtQuick

// CarouselParallaxImage — thumbnail image that pans against the scroll
// direction inside a carousel card (the prototype's parallax pan).
//
// The image is overscanned: fullWidth should stay constant at
//   CarouselEffect.parallaxWidth(<focused card width>, parallaxPad)
// so every card shows the same image scale and the pan never exposes an
// edge. x follows CarouselEffect.parallaxX(centerNorm, parallaxPad).
//
// Place inside a clipped card (Ui.ClipRect or Rectangle with clip: true)
// and set height + source only — never anchors.fill, it would override the
// x/width bindings that drive the effect.
Image {
    id: root

    // Continuous card position from CarouselCard.centerNorm (ListView) or
    // CarouselEffect.centerNormPath(...) (PathView), in [-1, 1].
    property real centerNorm: 0
    // Overscan per side; the pan travels ±parallaxPad (prototype: 71).
    property real parallaxPad: 28
    // Constant bleed width, e.g. focusedWidth + 2 * parallaxPad.
    property real fullWidth: 296

    x: -parallaxPad - centerNorm * parallaxPad
    width: fullWidth
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
}
