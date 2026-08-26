import DesignSystem
import SwiftUI

struct ChallengeCardGarmentsView: View {
    let garments: CardGarments
    let topPosition: FigmaPosition
    let bottomPosition: FigmaPosition
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            garment(garments.top, at: topPosition, label: "challenge.card.garment.top")
            garment(garments.bottom, at: bottomPosition, label: "challenge.card.garment.bottom")
        }
    }

    @ViewBuilder
    private func garment(_ garment: CardGarment?, at position: FigmaPosition, label: String) -> some View {
        if let garment {
            DownsampledPhotoView(data: garment.data, maxPixel: 320)
                .frame(
                    width: width * position.widthFraction,
                    height: height * position.heightFraction
                )
                .rotationEffect(.degrees(position.rotation))
                .position(x: width * position.x, y: height * position.y)
                .accessibilityLabel(String(format: LocalizedKey.resolve(label), garment.name))
        }
    }
}
