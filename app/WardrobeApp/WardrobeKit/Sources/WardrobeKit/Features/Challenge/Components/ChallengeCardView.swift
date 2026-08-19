import DesignSystem
import SwiftUI

struct ChallengeCardView: View {
    let card: ChallengeCard
    let onAccept: () -> Void
    // The card's real design size in Figma — the single source of truth for every position below
    private let cardFrameWidth: CGFloat = 346
    private let cardFrameHeight: CGFloat = 617
    
    private let takePicPosition: FigmaPosition
    private let cardStickers: [StickerPlacement]
    private let stickyPlacement: StickerPlacement
    private let titleTextPosition: FigmaPosition
    private let smallTitleTextPosition: FigmaPosition

    init(card: ChallengeCard, onAccept: @escaping () -> Void) {
        self.card = card
        self.onAccept = onAccept
        
        let w: CGFloat = cardFrameWidth
        let h: CGFloat = cardFrameHeight
        
        takePicPosition = FigmaPosition(
            figmaX: 182, figmaY: 426,
            figmaWidth: 108, figmaHeight: 50,
            frameWidth: w, frameHeight: h
        )
        
        titleTextPosition = FigmaPosition(
            figmaX: 67, figmaY: 64,
            figmaWidth: 220, figmaHeight: 60,
            frameWidth: w, frameHeight: h,
            rotation: -3
        )
        
        smallTitleTextPosition = FigmaPosition(
            figmaX: 160, figmaY: 35,
            figmaWidth: 220, figmaHeight: 60,
            frameWidth: w, frameHeight: h,
            rotation: 10
        )

        
        cardStickers = [
            StickerPlacement("Star", figmaX: 38, figmaY: 39, figmaWidth: 29, figmaHeight: 36, frameWidth: w, frameHeight: h),
            StickerPlacement("Kancing", figmaX: 20, figmaY: 142, figmaWidth: 30, figmaHeight: 30, frameWidth: w, frameHeight: h),
            StickerPlacement("LeftTape", figmaX: 0, figmaY: 298, figmaWidth: 25.4, figmaHeight: 96.65, frameWidth: w, frameHeight: h),
            StickerPlacement("Pin", figmaX: 290, figmaY: 301, figmaWidth: 33, figmaHeight: 39, frameWidth: w, frameHeight: h),
            StickerPlacement("Clip", figmaX: 21, figmaY: 451, figmaWidth: 58, figmaHeight: 59, frameWidth: w, frameHeight: h),
            StickerPlacement("Camera", figmaX: 21, figmaY: 409, figmaWidth: 96, figmaHeight: 81, frameWidth: w, frameHeight: h),
            StickerPlacement("Barcode", figmaX: 82, figmaY: 500, figmaWidth: 169, figmaHeight: 46, frameWidth: w, frameHeight: h),
            StickerPlacement("Kancing2", figmaX: 256, figmaY: 514, figmaWidth: 52.59, figmaHeight: 52.59, frameWidth: w, frameHeight: h),
        ]
        
        stickyPlacement = StickerPlacement(
            "Sticky", figmaX: 53.8, figmaY: 290, figmaWidth: 261.33, figmaHeight: 124.32,
            frameWidth: w, frameHeight: h
        )
        
        
    }
    var body: some View {
        GeometryReader { cardGeo in
            let cw = cardGeo.size.width
            let ch = cardGeo.size.height
            
            ZStack {
                Image("ChallengeSheet", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                //.frame(width: 346, height: 617)
                
                
                Image(stickyPlacement.imageName, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: cw * stickyPlacement.widthFraction)
                    .position(x: cw * stickyPlacement.x, y: ch * stickyPlacement.y)
                
                // Text layered directly on top of the sticky note, same position + matching size
                VStack(spacing: 4) {
                    Text("Prompt Title")
                        .font(AppFont.body.bold())
                    Text(card.prompt)
                        .font(AppFont.body)
                        .multilineTextAlignment(.center)
                }
                .frame(width: cw * stickyPlacement.widthFraction * 0.8) // slightly narrower than the note so text doesn't touch edges
                .position(x: cw * stickyPlacement.x, y: ch * stickyPlacement.y)
                
                
                PrimaryButtonView(Text("challenge.accept", bundle: .module), action: onAccept)
                    .frame(width: cw * takePicPosition.widthFraction)
                    .position(x: cw * takePicPosition.x, y: ch * takePicPosition.y)
                
                Text("challenge.card.title", bundle: .module)
                    .font(AppFont.customTitle)
                    .frame(width: cw * titleTextPosition.widthFraction + 100)
                    .rotationEffect(.degrees(titleTextPosition.rotation))
                    .position(x: cw * titleTextPosition.x, y: ch * titleTextPosition.y)
                    .foregroundStyle(AppColor.pink)
                
                Text("challenge.card.today", bundle: .module)
                    .font(AppFont.customSmallTitle)
                    .frame(width: cw * smallTitleTextPosition.widthFraction + 70)
                    .rotationEffect(.degrees(smallTitleTextPosition.rotation))
                    .position(x: cw * smallTitleTextPosition.x, y: ch * smallTitleTextPosition.y)
                
                ForEach(cardStickers) { sticker in
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
        //.foregroundStyle(AppColor.textPrimary)
    }
}

#Preview {
    let _ = FontRegistration.registerCustomFonts()
    ChallengeCardView(
        card: ChallengeCard(id: UUID(), prompt: "Wear something you haven't worn in a month"),
        onAccept: {}
    )
}
