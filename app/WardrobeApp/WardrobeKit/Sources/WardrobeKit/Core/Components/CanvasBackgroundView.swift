import CoreGraphics
import SwiftUI

struct CanvasBackgroundView: View {
    let background: CanvasBackground
    /// The same lookup the layers use — a photo background is an id like any
    /// other, already cropped by `updateCroppedPreviews()`.
    var photo: (String) -> CGImage? = { _ in nil }

    var body: some View {
        switch background {
        case let .palette(palette):
            LinearGradient(
                colors: palette.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case let .photo(id, _):
            photoFill(photo(id))
        }
    }

    @ViewBuilder
    private func photoFill(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: CanvasBackground.Palette.white.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
