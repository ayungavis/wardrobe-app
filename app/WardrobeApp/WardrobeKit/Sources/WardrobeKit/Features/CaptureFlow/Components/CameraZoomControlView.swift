import DesignSystem
import SwiftUI

struct CameraZoomControlView: View {
    let options: [CGFloat]
    let selected: CGFloat
    let isFrontCamera: Bool
    let onSelect: (CGFloat) -> Void
    let onToggle: () -> Void

    var body: some View {
        Group {
            if options.count < 2 {
                EmptyView()
            } else if isFrontCamera {
                frontToggle
            } else {
                presetRow
            }
        }
        .padding(.bottom, Spacing.lg)
    }

    private var presetRow: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(verbatim: Self.label(for: option))
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(isSelected(option) ? AppColor.accent : AppColor.onMedia)
                        .frame(width: 44, height: 44)
                        .background(isSelected(option) ? AppColor.onMedia.opacity(0.25) : .clear, in: Circle())
                }
                .accessibilityLabel(Text(verbatim: Self.label(for: option)))
                .accessibilityAddTraits(isSelected(option) ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, Spacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var frontToggle: some View {
        Button(action: onToggle) {
            Image(systemName: isZoomedIn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.onMedia)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel(Text(isZoomedIn ? "capture.camera.zoomOut" : "capture.camera.zoomIn", bundle: .module))
    }

    private var isZoomedIn: Bool {
        guard let last = options.last else { return false }
        return selected >= last
    }

    private func isSelected(_ option: CGFloat) -> Bool {
        abs(selected - option) < 0.05
    }

    private static func label(for option: CGFloat) -> String {
        option == option.rounded() ? "\(Int(option))x" : "\(option)x"
    }
}
