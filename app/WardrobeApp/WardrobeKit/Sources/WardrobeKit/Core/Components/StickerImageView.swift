import SwiftUI

struct StickerImageView: View {
    let sticker: StickerPlacement
    let containerSize: CGSize

    var body: some View {
        let width: CGFloat = containerSize.width * sticker.widthFraction
        let x: CGFloat = containerSize.width * sticker.x
        let y: CGFloat = containerSize.height * sticker.y

        Image(sticker.imageName, bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(sticker.rotation))
            .position(x: x, y: y)
    }
}
