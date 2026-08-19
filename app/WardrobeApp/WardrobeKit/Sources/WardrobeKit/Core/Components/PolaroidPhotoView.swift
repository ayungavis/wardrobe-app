import CoreGraphics
import SwiftUI

/// The cropped 3:4 capture inside its polaroid frame (FR-092).
///
/// Every dimension is a fraction of `width`, including the shadow. That is not
/// tidiness: the editor lays this out at roughly 200 points and the exporter at
/// roughly 600, so an absolute shadow would come out three times smaller in the
/// file than on screen — the picture people share would not be the picture they
/// arranged.
struct PolaroidPhotoView: View {
    /// Fraction of the canvas width a photo layer occupies at scale 1.
    static let widthRatio: CGFloat = 0.58

    /// Total height as a multiple of the frame's width: top border, the 3:4
    /// photo well, then the fat bottom lip.
    static func height(forWidth width: CGFloat) -> CGFloat {
        let border = borderWidth(forWidth: width)
        return border + photoSize(forWidth: width).height + width * bottomLipRatio
    }

    /// The photo well — portrait 3:4, exactly what the crop step produces, so
    /// the aspect fill below never actually has to cut anything off.
    static func photoSize(forWidth width: CGFloat) -> CGSize {
        let photoWidth = width - borderWidth(forWidth: width) * 2
        return CGSize(width: photoWidth, height: photoWidth * 4 / 3)
    }

    static func borderWidth(forWidth width: CGFloat) -> CGFloat {
        max(minimumBorder, width * borderRatio)
    }

    private static let borderRatio: CGFloat = 0.03
    private static let bottomLipRatio: CGFloat = 0.16
    /// Keeps the frame readable in a thumbnail-sized preview, where 3 % would
    /// round away to nothing.
    private static let minimumBorder: CGFloat = 4

    let photo: CGImage?
    let width: CGFloat

    var body: some View {
        let border = Self.borderWidth(forWidth: width)
        let photoSize = Self.photoSize(forWidth: width)

        Rectangle()
            // A literal white, not `.white`: this is paper, and paper does not
            // turn dark when the system does.
            .fill(Color(red: 1, green: 1, blue: 1))
            .frame(width: width, height: Self.height(forWidth: width))
            .overlay(alignment: .top) {
                photoWell(size: photoSize)
                    .padding(.top, border)
            }
            // One shadow for the whole card rather than one per element.
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
            // FR-092: a photo that cannot be read leaves the layer in place
            // rather than blocking export or completion.
            Rectangle()
                .fill(Color(red: 0.92, green: 0.92, blue: 0.92))
                .frame(width: size.width, height: size.height)
        }
    }
}
