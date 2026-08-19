import DesignSystem
import SwiftUI

struct CanvasGuidesView: View {
    let alignment: CanvasAlignment

    var body: some View {
        ZStack {
            if alignment.showsVerticalLine {
                Rectangle()
                    .fill(AppColor.accent)
                    .frame(width: 1)
            }

            if alignment.showsHorizontalLine {
                Rectangle()
                    .fill(AppColor.accent)
                    .frame(height: 1)
            }

            if alignment == .centred {
                Circle()
                    .fill(AppColor.accent)
                    .frame(width: 7, height: 7)
                    .overlay { Circle().stroke(AppColor.onMedia, lineWidth: 1) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
