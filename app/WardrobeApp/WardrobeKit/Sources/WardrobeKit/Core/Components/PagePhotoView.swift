import CoreGraphics
import SwiftUI

struct PagePhotoView: View {
    let photo: CGImage?
    let size: CGSize

    var body: some View {
        Group {
            if let photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color(red: 0.92, green: 0.92, blue: 0.92))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
