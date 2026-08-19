import DesignSystem
import SwiftUI

/// Displays JPEG data decoded off-main at bounded size (no 12MP decode on
/// the render path).
struct DownsampledPhotoView: View {
    let data: Data
    // ponytail: fixed decode budget; derive from displayScale when profiling says so.
    var maxPixel: CGFloat = 1600
    var contentMode: ContentMode = .fit

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
            }
        }
        .task(id: data) {
            let bytes = data
            let budget = maxPixel
            image = await Task.detached(priority: .userInitiated) {
                ImageDecoding.downsampledImage(from: bytes, maxPixel: budget)
            }.value
        }
    }
}
