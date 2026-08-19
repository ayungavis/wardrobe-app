import CoreGraphics
import Foundation
import Testing
@testable import WardrobeKit

/// The crop step decides which pixels survive into the export, so its maths is
/// tested directly rather than through a screen.
struct CropGeometryTests {
    private let cropSize = CGSize(width: 300, height: 400) // 3:4
    private let wide = CGSize(width: 4000, height: 3000) // landscape source
    /// Deliberately narrower than 3:4, or "fills the width and crops the height"
    /// would be vacuously true.
    private let tall = CGSize(width: 3000, height: 5000)

    // MARK: Aspect fill

    /// Fill, not fit: a gap inside the box would export pixels the photo never
    /// had. Both orientations must cover it.
    @Test func theImageAlwaysCoversTheCropBox() {
        for source in [wide, tall, CGSize(width: 300, height: 400)] {
            let fill = CropGeometry.aspectFillSize(imageSize: source, cropSize: cropSize)

            #expect(fill.width >= cropSize.width - 0.001)
            #expect(fill.height >= cropSize.height - 0.001)
        }
    }

    @Test func aspectFillKeepsTheSourceProportions() {
        let fill = CropGeometry.aspectFillSize(imageSize: wide, cropSize: cropSize)

        let sourceAspect = wide.width / wide.height
        #expect(abs(fill.width / fill.height - sourceAspect) < 0.001)
    }

    /// A zero-sized image would otherwise divide by zero on the way in.
    @Test func aDegenerateImageFallsBackToTheCropBox() {
        let fill = CropGeometry.aspectFillSize(imageSize: .zero, cropSize: cropSize)

        #expect(fill == cropSize)
    }

    // MARK: Clamping

    @Test func scaleIsHeldInsideItsRange() {
        #expect(CropGeometry.clampedScale(0.2) == 1)
        #expect(CropGeometry.clampedScale(3) == 3)
        #expect(CropGeometry.clampedScale(99) == 6)
    }

    /// At scale 1 a portrait source has no horizontal slack, so panning
    /// sideways must not be able to reveal the background.
    @Test func offsetCannotPullAnEdgeIntoTheBox() {
        let offset = CropGeometry.clampedOffset(
            CGSize(width: 500, height: 0), scale: 1, imageSize: tall, cropSize: cropSize
        )

        #expect(offset.width == 0)
    }

    @Test func zoomingInCreatesSlackToPanInto() {
        let offset = CropGeometry.clampedOffset(
            CGSize(width: 10000, height: 0), scale: 2, imageSize: tall, cropSize: cropSize
        )

        #expect(offset.width > 0)
        // Still bounded: half the overhang, never more.
        let fill = CropGeometry.aspectFillSize(imageSize: tall, cropSize: cropSize)
        #expect(offset.width <= (fill.width * 2 - cropSize.width) / 2 + 0.001)
    }

    // MARK: Normalized rect

    @Test func theRectStaysInsideTheUnitSquare() {
        for scale in [CGFloat(1), 2.5, 6] {
            let rect = CropGeometry.normalizedRect(
                scale: scale,
                offset: CGSize(width: 9999, height: -9999),
                imageSize: wide,
                cropSize: cropSize
            )

            #expect(rect.minX >= -0.001)
            #expect(rect.minY >= -0.001)
            #expect(rect.maxX <= 1.001)
            #expect(rect.maxY <= 1.001)
        }
    }

    /// Untouched, the crop keeps the whole of the narrow side — that is what
    /// "fills the box" means once it is expressed in unit space.
    @Test func anUntouchedPortraitCropKeepsTheFullWidth() {
        let rect = CropGeometry.normalizedRect(
            scale: 1, offset: .zero, imageSize: tall, cropSize: cropSize
        )

        #expect(abs(rect.width - 1) < 0.001)
        #expect(rect.height < 1)
        #expect(abs(rect.midY - 0.5) < 0.001) // centred
    }

    @Test func anUntouchedLandscapeCropKeepsTheFullHeight() {
        let rect = CropGeometry.normalizedRect(
            scale: 1, offset: .zero, imageSize: wide, cropSize: cropSize
        )

        #expect(abs(rect.height - 1) < 0.001)
        #expect(rect.width < 1)
        #expect(abs(rect.midX - 0.5) < 0.001)
    }

    /// The rect is what the exporter multiplies by the full-resolution image,
    /// so its proportions have to match the box the user framed with.
    @Test func theRectHasTheCropBoxProportions() {
        let rect = CropGeometry.normalizedRect(
            scale: 2, offset: CGSize(width: 20, height: -35), imageSize: wide, cropSize: cropSize
        )

        let pixels = CGSize(width: rect.width * wide.width, height: rect.height * wide.height)
        #expect(abs(pixels.width / pixels.height - CropGeometry.aspectRatio) < 0.01)
    }

    @Test func zoomingInSelectsLessOfThePhoto() {
        let wideOpen = CropGeometry.normalizedRect(
            scale: 1, offset: .zero, imageSize: tall, cropSize: cropSize
        )
        let zoomed = CropGeometry.normalizedRect(
            scale: 3, offset: .zero, imageSize: tall, cropSize: cropSize
        )

        #expect(zoomed.width < wideOpen.width)
        #expect(zoomed.height < wideOpen.height)
    }

    // MARK: Crop box

    @Test func theCropBoxIsThreeByFourAndFitsTheSpace() {
        let size = CropGeometry.cropSize(
            fitting: CGSize(width: 390, height: 844), insets: CGSize(width: 32, height: 220)
        )

        #expect(abs(size.width / size.height - CropGeometry.aspectRatio) < 0.001)
        #expect(size.width <= 390 - 32 + 0.001)
        #expect(size.height <= 844 - 220 + 0.001)
    }

    /// A short screen has to give up width rather than overflow.
    @Test func aShortSpaceConstrainsTheBoxByHeight() {
        let size = CropGeometry.cropSize(
            fitting: CGSize(width: 1000, height: 400), insets: CGSize(width: 32, height: 220)
        )

        #expect(abs(size.height - 180) < 0.001)
        #expect(abs(size.width - 135) < 0.001)
    }
}
