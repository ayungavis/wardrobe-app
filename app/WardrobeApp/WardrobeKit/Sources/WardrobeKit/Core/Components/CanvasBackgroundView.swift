import SwiftUI

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
