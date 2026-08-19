import CoreGraphics
import Testing
@testable import WardrobeKit

/// FR-092. The numbers matter twice over: the editor lays the frame out at
/// roughly 200 points and the exporter at roughly 600, so anything that is not
/// a fraction of the width would make the shared file differ from the screen.
struct PolaroidGeometryTests {
    @Test func thePhotoWellIsPortraitThreeByFour() {
        let size = PolaroidPhotoView.photoSize(forWidth: 400)

        #expect(abs(size.height / size.width - 4.0 / 3.0) < 0.0001)
    }

    @Test func theFrameIsTallerThanItIsWideBecauseOfTheBottomLip() {
        let width: CGFloat = 400
        let height = PolaroidPhotoView.height(forWidth: width)
        let well = PolaroidPhotoView.photoSize(forWidth: width)
        let border = PolaroidPhotoView.borderWidth(forWidth: width)

        // Top border, the photo well, then the fat lip — nothing unaccounted for.
        #expect(abs(height - (border + well.height + width * 0.16)) < 0.0001)
        #expect(height > width)
    }

    /// The guard against the mistake this whole design exists to avoid: every
    /// dimension has to scale with the frame, or the export stops matching the
    /// canvas.
    @Test func everyDimensionScalesWithTheWidth() {
        let small: CGFloat = 200
        let large = small * 3

        #expect(abs(PolaroidPhotoView.height(forWidth: large) / PolaroidPhotoView.height(forWidth: small) - 3) < 0.0001)
        #expect(abs(
            PolaroidPhotoView.photoSize(forWidth: large).width
                / PolaroidPhotoView.photoSize(forWidth: small).width - 3
        ) < 0.0001)
        #expect(abs(
            PolaroidPhotoView.borderWidth(forWidth: large)
                / PolaroidPhotoView.borderWidth(forWidth: small) - 3
        ) < 0.0001)
    }

    /// A swatch-sized frame would round its border away to nothing, so there is
    /// a floor — the one place a point value is right.
    @Test func aTinyFrameKeepsAVisibleBorder() {
        #expect(PolaroidPhotoView.borderWidth(forWidth: 20) == 4)
    }

    /// It has to leave room for the background it sits on; that is what makes
    /// choosing one meaningful.
    @Test func theFrameLeavesTheCanvasVisibleAroundIt() {
        let canvasWidth: CGFloat = 360
        let canvasHeight = canvasWidth / StoryCanvas.aspectRatio
        let width = canvasWidth * PolaroidPhotoView.widthRatio

        #expect(width < canvasWidth)
        #expect(PolaroidPhotoView.height(forWidth: width) < canvasHeight)
    }
}
