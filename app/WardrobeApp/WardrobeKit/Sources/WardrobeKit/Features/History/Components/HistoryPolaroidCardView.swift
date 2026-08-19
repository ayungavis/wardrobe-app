import DesignSystem
import SwiftUI

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
            AppColor.surface
        }
    }
}
