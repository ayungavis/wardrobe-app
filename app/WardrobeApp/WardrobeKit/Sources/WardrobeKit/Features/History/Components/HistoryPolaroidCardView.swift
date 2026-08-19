//
//  HistoryPolaroidCardView.swift
//  WardrobeKit
//
//  Created by Luisa Haning Tyas on 17/08/26.
//

import DesignSystem
import SwiftUI

struct HistoryPolaroidCardView: View {
    let completion: CompletedChallenge
    let photoData: Data?

    /// Figma numbers for where the photo sits inside the polaroid frame —
    /// same system as ChallengeCardView's stickers.
    private let photoPlacement = FigmaPosition(
        figmaX: 6.7, figmaY: 50.7,
        figmaWidth: 158.04, figmaHeight: 200.57,
        frameWidth: 170.06, frameHeight: 312.01
    )

    private let completionDatePlacement = FigmaPosition(
        figmaX: 0, figmaY: 291.77,
        figmaWidth: 100, figmaHeight: 20,
        frameWidth: 170.06, frameHeight: 312.01
    )

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack {
                Image("HistoryPolaroidFrame", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 4)

                if let photoData {
                    DownsampledPhotoView(data: photoData, contentMode: .fill)
                        .frame(width: width * photoPlacement.widthFraction, height: height * photoPlacement.heightFraction)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: width * photoPlacement.x, y: height * photoPlacement.y)
                }

                Text(completion.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(
                        width: width * completionDatePlacement.widthFraction,
                        height: height * completionDatePlacement.heightFraction
                    )
                    .position(x: width * completionDatePlacement.x, y: height * completionDatePlacement.y)
            }
        }
        .aspectRatio(170.06 / 312.01, contentMode: .fit) // ⚠️ match your real polaroid frame's proportions
    }
}
