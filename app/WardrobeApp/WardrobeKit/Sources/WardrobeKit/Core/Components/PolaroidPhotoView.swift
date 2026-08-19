import CoreGraphics
import SwiftUI

struct PolaroidPhotoView: View {
    static let widthRatio: CGFloat = 0.58

    static func height(forWidth width: CGFloat) -> CGFloat {
        let border = borderWidth(forWidth: width)
        return border + photoSize(forWidth: width).height + width * bottomLipRatio
    }

    static func photoSize(forWidth width: CGFloat) -> CGSize {
        let photoWidth = width - borderWidth(forWidth: width) * 2
        return CGSize(width: photoWidth, height: photoWidth * 4 / 3)
    }

    static func borderWidth(forWidth width: CGFloat) -> CGFloat {
        max(minimumBorder, width * borderRatio)
    }

    private static let borderRatio: CGFloat = 0.03
    private static let bottomLipRatio: CGFloat = 0.16
    private static let minimumBorder: CGFloat = 4

    let photo: CGImage?
    let width: CGFloat

    var body: some View {
        let border = Self.borderWidth(forWidth: width)
        let photoSize = Self.photoSize(forWidth: width)

        Rectangle()
            .fill(Color(red: 1, green: 1, blue: 1))
            .frame(width: width, height: Self.height(forWidth: width))
            .overlay(alignment: .top) {
                photoWell(size: photoSize)
                    .padding(.top, border)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.28), radius: width * 0.015, x: 0, y: width * 0.02)
    }

    @ViewBuilder
    private func photoWell(size: CGSize) -> some View {
        if let photo {
            Image(decorative: photo, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Rectangle()
                .fill(Color(red: 0.92, green: 0.92, blue: 0.92))
                .frame(width: size.width, height: size.height)
        }
    }
}
