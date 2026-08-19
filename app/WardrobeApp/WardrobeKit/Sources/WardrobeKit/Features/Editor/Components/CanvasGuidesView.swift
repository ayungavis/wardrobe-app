import DesignSystem
import SwiftUI

/// The centre lines a layer snaps to (FR-089).
///
/// Drawn in canvas space rather than inside a layer's transform, so the lines
/// stay axis-aligned however the layer is rotated. Hidden from VoiceOver on
/// purpose: the non-visual channel is the layer's own accessibility value, and
/// two voices saying the same thing is one too many.
struct CanvasGuidesView: View {
    let alignment: CanvasAlignment

    var body: some View {
        ZStack {
            if alignment.showsVerticalLine {
                Rectangle()
                    .fill(AppColor.accent)
                    .frame(width: 1)
            }

            if alignment.showsHorizontalLine {
                Rectangle()
                    .fill(AppColor.accent)
                    .frame(height: 1)
            }

            if alignment == .centred {
                Circle()
                    .fill(AppColor.accent)
                    .frame(width: 7, height: 7)
                    .overlay { Circle().stroke(AppColor.onMedia, lineWidth: 1) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
