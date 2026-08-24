import DesignSystem
import SwiftUI

struct ChallengeCardView: View {
    let card: ChallengeCard
    let onAccept: () -> Void
    private static let frameWidth: CGFloat = 346
    private static let frameHeight: CGFloat = 617
    @State private var isPulsing = false

    private static func sticker(
        _ name: String,
        _ figmaX: CGFloat, _ figmaY: CGFloat,
        _ figmaWidth: CGFloat, _ figmaHeight: CGFloat
    ) -> StickerPlacement {
        StickerPlacement(
            name,
            figmaX: figmaX, figmaY: figmaY,
            figmaWidth: figmaWidth, figmaHeight: figmaHeight,
            frameWidth: frameWidth, frameHeight: frameHeight
        )
    }

    private static func position(
        _ figmaX: CGFloat, _ figmaY: CGFloat,
        _ figmaWidth: CGFloat, _ figmaHeight: CGFloat,
        rotation: Double = 0
    ) -> FigmaPosition {
        FigmaPosition(
            figmaX: figmaX, figmaY: figmaY,
            figmaWidth: figmaWidth, figmaHeight: figmaHeight,
            frameWidth: frameWidth, frameHeight: frameHeight,
            rotation: rotation
        )
    }

    private static let takePicPosition = position(182, 426, 108, 50)
    private static let titleTextPosition = position(67, 64, 220, 60, rotation: -3)
    private static let smallTitleTextPosition = position(160, 35, 220, 60, rotation: 10)
    private static let stickyPlacement = sticker("Sticky", 53.8, 290, 261.33, 124.32)

    private static let cardStickers = [
        sticker("Star", 38, 39, 29, 36),
        sticker("Kancing", 20, 142, 30, 30),
        sticker("LeftTape", 0, 298, 25.4, 96.65),
        sticker("Pin", 290, 301, 33, 39),
        sticker("Clip", 21, 451, 58, 59),
        sticker("Camera", 21, 409, 96, 81),
        sticker("Barcode", 82, 500, 169, 46),
        sticker("Kancing2", 256, 514, 52.59, 52.59),
    ]

    var body: some View {
        GeometryReader { cardGeo in
            let cw = cardGeo.size.width
            let ch = cardGeo.size.height

            ZStack {
                Image("ChallengeSheet", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                Image(Self.stickyPlacement.imageName, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: cw * Self.stickyPlacement.widthFraction)
                    .position(x: cw * Self.stickyPlacement.x, y: ch * Self.stickyPlacement.y)

                Text(card.prompt)
                    .font(AppFont.body)
                    .multilineTextAlignment(.center)
                    .frame(width: cw * Self.stickyPlacement.widthFraction * 0.8)
                    .position(x: cw * Self.stickyPlacement.x, y: ch * Self.stickyPlacement.y)

                PrimaryButtonView(Text("challenge.accept", bundle: .module), action: onAccept)
                    .frame(width: cw * Self.takePicPosition.widthFraction)
                    .scaleEffect(isPulsing ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .position(x: cw * Self.takePicPosition.x, y: ch * Self.takePicPosition.y)
                    .onAppear {
                        isPulsing = true
                    }

                Text("challenge.card.title", bundle: .module)
                    .font(AppFont.customTitle)
                    .frame(width: cw * Self.titleTextPosition.widthFraction + 100)
                    .rotationEffect(.degrees(Self.titleTextPosition.rotation))
                    .position(x: cw * Self.titleTextPosition.x, y: ch * Self.titleTextPosition.y)
                    .foregroundStyle(AppColor.pink)

                Text("challenge.card.today", bundle: .module)
                    .font(AppFont.customSmallTitle)
                    .frame(width: cw * Self.smallTitleTextPosition.widthFraction + 70)
                    .rotationEffect(.degrees(Self.smallTitleTextPosition.rotation))
                    .position(x: cw * Self.smallTitleTextPosition.x, y: ch * Self.smallTitleTextPosition.y)

                ForEach(Self.cardStickers) { sticker in
                    Image(sticker.imageName, bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: cw * sticker.widthFraction)
                        .rotationEffect(.degrees(sticker.rotation))
                        .position(x: cw * sticker.x, y: ch * sticker.y)
                }
            }
        }
        .aspectRatio(346 / 617, contentMode: .fit)
    }
}

#Preview {
    let _ = FontRegistration.registerCustomFonts()
    ChallengeCardView(
        card: ChallengeCard(id: UUID(), prompt: "Wear something you haven't worn in a month"),
        onAccept: {}
    )
}
