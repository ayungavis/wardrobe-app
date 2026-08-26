import CoreGraphics
import DesignSystem
import SwiftUI

struct IllustrationDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let data: Data

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()

            if let image {
                #if os(iOS)
                    ZoomableImageView(image: image)
                        .ignoresSafeArea()
                #endif
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topLeading) {
            MediaCircleButtonView(systemName: "xmark") { dismiss() }
                .accessibilityLabel(Text("common.close", bundle: .module))
                .padding(Spacing.lg)
        }
        .presentationBackground(.clear)
        .task {
            let bytes = data
            image = await Task.detached(priority: .userInitiated) {
                ImageDecoding.downsampledImage(from: bytes, maxPixel: 2048)
            }.value
        }
    }
}
