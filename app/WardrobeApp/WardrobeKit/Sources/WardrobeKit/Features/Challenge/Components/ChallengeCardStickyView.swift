import DesignSystem
import SwiftUI

struct ChallengeCardStickyView: View {
    let card: ChallengeCard
    let placement: StickerPlacement
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let noteWidth = width * placement.widthFraction
        let noteHeight = height * placement.heightFraction

        ZStack {
            Image(placement.imageName, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: noteWidth)

            VStack(alignment: .leading, spacing: noteHeight * 0.06) {
                if let title = card.title {
                    Text(verbatim: "“\(title)”")
                        .font(AppFont.roundedTitle2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Text(card.prompt)
                    .font(AppFont.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(noteWidth * 0.035)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                AppColor.textPrimary.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(AppColor.textPrimary)
            .padding(.leading, noteWidth * 0.07)
            .padding(.trailing, noteWidth * 0.09)
            .padding(.vertical, noteHeight * 0.09)
            .frame(width: noteWidth, height: noteHeight)
        }
        .position(x: width * placement.x, y: height * placement.y)
    }
}
