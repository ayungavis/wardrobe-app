//
//  AppBackgroundImageView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 21/08/26.
//


import DesignSystem
import SwiftUI

struct AppBackgroundImageView: View {
    var body: some View {
        Image("appBG", bundle: .module)
            .resizable()
            .ignoresSafeArea()
    }
}

struct AppBackgroundView: View {
    var body: some View {
        ZStack {
            AppBackgroundImageView()

            GeometryReader { screenGeo in
                let size = screenGeo.size

                ForEach([StickerPlacement].appBackground) { sticker in
                    StickerImageView(sticker: sticker, containerSize: size)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct StickerImageView: View {
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
extension [StickerPlacement] {
    static let appBackground: [StickerPlacement] = [
        StickerPlacement(
            "StampElement",
            figmaX: 284, figmaY: 56, figmaWidth: 142, figmaHeight: 162,
            frameWidth: 375, frameHeight: 812
        ),
        StickerPlacement(
            "StampDetail",
            figmaX: 38, figmaY: 752, figmaWidth: 104, figmaHeight: 120,
            frameWidth: 375, frameHeight: 812
        ),
        StickerPlacement(
            "Kancing2",
            figmaX: -18, figmaY: 257, figmaWidth: 52, figmaHeight: 52,
            frameWidth: 375, frameHeight: 812
        ),
        StickerPlacement(
            "Stargold",
            figmaX: 314, figmaY: 650, figmaWidth: 66, figmaHeight: 67,
            frameWidth: 375, frameHeight: 812
        ),
    ]
}

extension View {
    func appBackgroundStickers() -> some View {
        background(AppBackgroundView())
    }

    func appBackgroundOnly() -> some View {
        background(AppBackgroundImageView())
    }
}
