import DesignSystem
import SwiftUI

struct HeroView: View {
    let data: Data?
    let isEditing: Bool

    var body: some View {
        Group {
            if let data {
                DownsampledPhotoView(data: data)
            } else {
                Image(systemName: "tshirt")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
