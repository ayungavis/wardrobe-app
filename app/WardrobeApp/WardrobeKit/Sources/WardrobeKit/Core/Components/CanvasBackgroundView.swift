import SwiftUI

/// Draws a palette entry. Used by the canvas, by the exporter, and by the
/// picker's swatches — so a swatch cannot promise a colour the canvas does not
/// deliver.
struct CanvasBackgroundView: View {
    let background: CanvasBackground

    var body: some View {
        LinearGradient(
            colors: background.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
