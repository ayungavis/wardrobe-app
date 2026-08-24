import CoreGraphics
import SwiftUI

struct CanvasBackgroundView: View {
    let background: CanvasBackground
    var photo: (UUID) -> CGImage? = { _ in nil }

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
