import DesignSystem
import SwiftUI

/// Crop tool with its own Cancel/Done bar, dark styled.
struct CropStageView: View {
    let image: CGImage?
    let spec: CropSpec
    let onChange: (CropSpec) -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Text("common.cancel", bundle: .module)
                        .frame(minHeight: 44)
                }

                Spacer()

                Button(action: onDone) {
                    Text("common.done", bundle: .module)
                        .bold()
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(AppColor.onMedia)
            .padding(.horizontal, Spacing.lg)

            CropToolView(image: image, spec: spec, onChange: onChange)
                .padding(Spacing.lg)
        }
    }
}
