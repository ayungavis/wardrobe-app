import DesignSystem
import SwiftUI

/// One completed challenge as a print: the composition the user confirmed,
/// inside a paper border with the date on the lip.
///
/// The frame is drawn rather than an image asset. The asset it replaces was a
/// plain opaque white rectangle supplied at 1× only, so it blurred as soon as
/// the card grew — and being a fixed bitmap it could not follow the window's
/// aspect ratio.
struct HistoryPolaroidCardView: View {
    let completion: CompletedChallenge
    let previewData: Data?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let inset = width * HistoryPolaroidGeometry.padding

            VStack(spacing: 0) {
                window
                    .frame(
                        width: width * HistoryPolaroidGeometry.windowWidth,
                        height: width * HistoryPolaroidGeometry.windowHeight
                    )
                    .clipShape(.rect(cornerRadius: inset))

                Text(completion.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, inset)
            .padding(.top, inset)
            .background(
                // A literal white, like `PolaroidPhotoView`: this is paper, and
                // paper does not turn dark when the system does.
                Color(red: 1, green: 1, blue: 1),
                in: .rect(cornerRadius: inset * 1.5)
            )
            // One shadow for the whole card rather than one per element —
            // without this the preview and the date each grow their own.
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 4)
        }
        .aspectRatio(HistoryPolaroidGeometry.cardAspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private var window: some View {
        if let previewData {
            DownsampledPhotoView(data: previewData, contentMode: .fill)
        } else {
            // A completion whose composition cannot be rendered still shows a
            // print, so History never has a hole in it.
            AppColor.surface
        }
    }
}
